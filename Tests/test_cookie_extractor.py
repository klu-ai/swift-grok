#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "Scripts" / "cookie_extractor.py"
SPEC = importlib.util.spec_from_file_location("cookie_extractor", SCRIPT_PATH)
cookie_extractor = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(cookie_extractor)


class CookieExtractorTests(unittest.TestCase):
    def create_wal_cookie_db(self, root: Path) -> tuple[Path, sqlite3.Connection]:
        db_path = root / "Cookies"
        connection = sqlite3.connect(db_path)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute(
            "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB)"
        )
        connection.commit()
        connection.execute(
            "INSERT INTO cookies VALUES (?, ?, ?, ?)",
            (".grok.com", "sso", "wal-cookie", b""),
        )
        connection.commit()
        self.assertTrue(Path(str(db_path) + "-wal").exists())
        return db_path, connection

    def test_sqlite_rows_reads_live_wal_data(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            db_path, connection = self.create_wal_cookie_db(Path(temp_name))
            try:
                rows = list(cookie_extractor.sqlite_rows(db_path))
            finally:
                connection.close()

        self.assertEqual(rows, [(".grok.com", "sso", "wal-cookie", b"")])

    def test_sqlite_rows_copy_fallback_includes_wal_sidecars(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            db_path, connection = self.create_wal_cookie_db(Path(temp_name))
            real_connect = sqlite3.connect
            attempts = 0

            def flaky_connect(*args, **kwargs):
                nonlocal attempts
                attempts += 1
                if attempts == 1:
                    raise sqlite3.Error("simulate locked live database")
                return real_connect(*args, **kwargs)

            try:
                with patch.object(cookie_extractor.sqlite3, "connect", side_effect=flaky_connect):
                    rows = list(cookie_extractor.sqlite_rows(db_path))
            finally:
                connection.close()

        self.assertEqual(rows, [(".grok.com", "sso", "wal-cookie", b"")])
        self.assertGreaterEqual(attempts, 2)

    def test_sqlite_rows_keeps_invalid_encrypted_text_as_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            db_path = Path(temp_name) / "Cookies"
            connection = sqlite3.connect(db_path)
            try:
                connection.execute(
                    "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value TEXT)"
                )
                connection.execute(
                    """
                    INSERT INTO cookies
                    VALUES ('.grok.com', 'sso', '', CAST(X'763130fffe' AS TEXT))
                    """
                )
                connection.commit()
            finally:
                connection.close()

            rows = list(cookie_extractor.sqlite_rows(db_path))

        self.assertEqual(rows, [(".grok.com", "sso", "", b"v10\xff\xfe")])

    def test_discover_cookie_db_infers_browser_from_explicit_cookie_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            cookie_db = (
                Path(temp_name)
                / "Library"
                / "Application Support"
                / "Google"
                / "Chrome"
                / "Default"
                / "Network"
                / "Cookies"
            )
            cookie_db.parent.mkdir(parents=True)
            cookie_db.touch()

            self.assertEqual(
                cookie_extractor.discover_cookie_dbs("auto", None, str(cookie_db)),
                [("chrome", cookie_db)],
            )

    def test_discover_profile_dir_infers_browser_from_explicit_profile_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            profile_dir = (
                Path(temp_name)
                / "Library"
                / "Application Support"
                / "BraveSoftware"
                / "Brave-Browser"
                / "Profile 1"
            )
            cookie_db = profile_dir / "Network" / "Cookies"
            cookie_db.parent.mkdir(parents=True)
            cookie_db.touch()

            self.assertEqual(
                cookie_extractor.discover_cookie_dbs("auto", str(profile_dir), None),
                [("brave", cookie_db)],
            )

    def test_auto_keychain_tries_chromium_services_for_unknown_explicit_path(self) -> None:
        calls: list[str] = []

        def fake_run(command, **_kwargs):
            calls.append(command[-1])
            return SimpleNamespace(returncode=1, stdout="")

        with patch.object(cookie_extractor.sys, "platform", "darwin"):
            with patch.object(cookie_extractor.subprocess, "run", side_effect=fake_run):
                self.assertIsNone(cookie_extractor.keychain_password("auto"))

        self.assertIn("Chrome Safe Storage", calls)
        self.assertIn("Brave Safe Storage", calls)
        self.assertIn("Microsoft Edge Safe Storage", calls)
        self.assertIn("Arc Safe Storage", calls)
        self.assertIn("Chromium Safe Storage", calls)

    def test_required_accepts_any_grok_auth_cookie_with_envelope_cookies(self) -> None:
        self.assertTrue(cookie_extractor.validate_required({
            "x-anonuserid": "anon",
            "cf_clearance": "clearance",
            "__cf_bm": "bot-cookie",
            "grok_device_id": "device",
        }, True))

    def test_required_rejects_envelope_cookies_without_auth_cookie(self) -> None:
        self.assertFalse(cookie_extractor.validate_required({
            "cf_clearance": "clearance",
            "__cf_bm": "bot-cookie",
            "grok_device_id": "device",
        }, True))

    def test_chromium_extraction_preserves_browser_envelope_cookies(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            db_path = Path(temp_name) / "Cookies"
            connection = sqlite3.connect(db_path)
            try:
                connection.execute(
                    "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB)"
                )
                for name in ("x-anonuserid", "cf_clearance", "__cf_bm", "grok_device_id"):
                    connection.execute(
                        "INSERT INTO cookies VALUES (?, ?, ?, ?)",
                        (".grok.com", name, f"{name}-value", b""),
                    )
                connection.commit()
            finally:
                connection.close()

            cookies, encrypted_matches = cookie_extractor.extract_from_chromium_db(
                db_path,
                "chrome",
                ".grok.com",
            )

        self.assertEqual(encrypted_matches, 0)
        self.assertEqual(cookies["x-anonuserid"], "x-anonuserid-value")
        self.assertEqual(cookies["cf_clearance"], "cf_clearance-value")
        self.assertEqual(cookies["__cf_bm"], "__cf_bm-value")
        self.assertEqual(cookies["grok_device_id"], "grok_device_id-value")


if __name__ == "__main__":
    unittest.main()
