#!/usr/bin/env python3
"""
Extract grok.com cookies for the Swift Grok CLI.

The script avoids printing cookie values. JSON mode writes only the requested
credentials file, while Swift mode is available for older embedding workflows.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import secrets
import shutil
import socket
import sqlite3
import ssl
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


AUTH_COOKIES = ("sso", "sso-rw", "x-userid", "x-anonuserid")
OPTIONAL_AUTH_COOKIES = ("x-challenge", "x-signature", "cf_clearance", "__cf_bm", "grok_device_id")

SAFARI_COOKIE_PATHS = (
    "~/Library/Cookies/Cookies.binarycookies",
    "~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
    "~/Library/HTTPStorages/grok.binarycookies",
    "~/Library/HTTPStorages/com.apple.Safari.binarycookies",
)

BROWSER_PATHS = {
    "atlas": [
        ("~/Library/Application Support/com.openai.atlas/browser-data/host", ("*/Cookies", "*/Network/Cookies")),
    ],
    "chrome": [
        ("~/Library/Application Support/Google/Chrome", ("*/Network/Cookies", "*/Cookies")),
    ],
    "chromium": [
        ("~/Library/Application Support/Chromium", ("*/Network/Cookies", "*/Cookies")),
    ],
    "brave": [
        ("~/Library/Application Support/BraveSoftware/Brave-Browser", ("*/Network/Cookies", "*/Cookies")),
    ],
    "edge": [
        ("~/Library/Application Support/Microsoft Edge", ("*/Network/Cookies", "*/Cookies")),
    ],
    "arc": [
        ("~/Library/Application Support/Arc/User Data", ("*/Network/Cookies", "*/Cookies")),
    ],
}

AUTO_CHROMIUM_BROWSERS = ("chrome", "brave", "edge", "arc", "chromium", "atlas")

BROWSER_PATH_HINTS = (
    ("atlas", ("com.openai.atlas/browser-data/host", "openai atlas")),
    ("chrome", ("google/chrome",)),
    ("brave", ("bravesoftware/brave-browser",)),
    ("edge", ("microsoft edge",)),
    ("arc", ("arc/user data",)),
    ("chromium", ("application support/chromium", "/chromium/")),
)

KEYCHAIN_SERVICES = {
    "atlas": (
        "ChatGPT Atlas Safe Storage",
        "OpenAI Atlas Safe Storage",
        "com.openai.atlas Safe Storage",
        "Chromium Safe Storage",
        "Chrome Safe Storage",
    ),
    "chrome": ("Chrome Safe Storage", "Chromium Safe Storage"),
    "chromium": ("Chromium Safe Storage", "Chrome Safe Storage"),
    "brave": ("Brave Safe Storage", "Chrome Safe Storage", "Chromium Safe Storage"),
    "edge": ("Microsoft Edge Safe Storage", "Chrome Safe Storage", "Chromium Safe Storage"),
    "arc": ("Arc Safe Storage", "Chrome Safe Storage", "Chromium Safe Storage"),
}
KEYCHAIN_SERVICES["auto"] = tuple(
    dict.fromkeys(
        service
        for browser in AUTO_CHROMIUM_BROWSERS
        for service in KEYCHAIN_SERVICES.get(browser, ())
    )
)


def domain_matches(host: str, requested_domain: str) -> bool:
    host = host.lstrip(".").lower()
    requested = requested_domain.lstrip(".").lower()
    return host == requested or host.endswith("." + requested)


def read_http_json(url: str) -> Any:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


class DevToolsWebSocket:
    def __init__(self, websocket_url: str):
        parsed = urllib.parse.urlparse(websocket_url)
        if parsed.scheme not in ("ws", "wss"):
            raise ValueError(f"Unsupported DevTools websocket URL: {websocket_url}")

        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or (443 if parsed.scheme == "wss" else 80)
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query

        sock = socket.create_connection((host, port), timeout=5)
        if parsed.scheme == "wss":
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
        self.sock = sock

        key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self.sock.sendall(request.encode("ascii"))
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(4096)
            if not chunk:
                break
            response += chunk
        if b" 101 " not in response.split(b"\r\n", 1)[0]:
            raise RuntimeError("DevTools websocket upgrade failed")

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def _read_exact(self, length: int) -> bytes:
        data = b""
        while len(data) < length:
            chunk = self.sock.recv(length - len(data))
            if not chunk:
                raise RuntimeError("DevTools websocket closed unexpectedly")
            data += chunk
        return data

    def send_json(self, payload: Dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        mask = secrets.token_bytes(4)
        if len(data) < 126:
            header = bytes([0x81, 0x80 | len(data)])
        elif len(data) < 65536:
            header = bytes([0x81, 0x80 | 126]) + len(data).to_bytes(2, "big")
        else:
            header = bytes([0x81, 0x80 | 127]) + len(data).to_bytes(8, "big")
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(data))
        self.sock.sendall(header + mask + masked)

    def recv_json(self) -> Dict[str, Any]:
        while True:
            first, second = self._read_exact(2)
            opcode = first & 0x0F
            masked = bool(second & 0x80)
            length = second & 0x7F
            if length == 126:
                length = int.from_bytes(self._read_exact(2), "big")
            elif length == 127:
                length = int.from_bytes(self._read_exact(8), "big")
            mask = self._read_exact(4) if masked else b""
            payload = self._read_exact(length) if length else b""
            if masked:
                payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))

            if opcode == 0x1:
                return json.loads(payload.decode("utf-8"))
            if opcode == 0x8:
                raise RuntimeError("DevTools websocket closed")
            if opcode == 0x9:
                self.sock.sendall(bytes([0x8A, len(payload)]) + payload)


def extract_from_devtools(devtools_url: str, domain: str) -> Dict[str, str]:
    base = devtools_url.rstrip("/")
    targets = read_http_json(f"{base}/json/list")
    if not targets:
        try:
            request = urllib.request.Request(f"{base}/json/new?https://grok.com", method="PUT")
            with urllib.request.urlopen(request, timeout=5):
                pass
            targets = read_http_json(f"{base}/json/list")
        except Exception:
            targets = []

    target = next(
        (
            item for item in targets
            if item.get("type") == "page" and item.get("webSocketDebuggerUrl")
        ),
        None,
    )
    if not target:
        version = read_http_json(f"{base}/json/version")
        target = {"webSocketDebuggerUrl": version.get("webSocketDebuggerUrl")}

    websocket_url = target.get("webSocketDebuggerUrl")
    if not websocket_url:
        raise RuntimeError("No DevTools websocket target available")

    websocket = DevToolsWebSocket(websocket_url)
    try:
        for command_id, method in ((1, "Network.getAllCookies"), (2, "Storage.getCookies")):
            websocket.send_json({"id": command_id, "method": method})
            while True:
                message = websocket.recv_json()
                if message.get("id") != command_id:
                    continue
                if "error" in message:
                    break
                raw_cookies = message.get("result", {}).get("cookies", [])
                cookies = {
                    item["name"]: item.get("value", "")
                    for item in raw_cookies
                    if item.get("name") and item.get("value") and domain_matches(item.get("domain", ""), domain)
                }
                if cookies:
                    return cookies
                break
    finally:
        websocket.close()

    return {}


def browser_order(browser: str) -> List[str]:
    if browser == "auto":
        return ["safari", "chrome", "brave", "edge", "arc", "chromium", "firefox", "atlas"]
    return [browser]


def infer_chromium_browser_from_path(path: Path) -> Optional[str]:
    normalized = str(path.expanduser()).replace("\\", "/").lower()
    for browser, hints in BROWSER_PATH_HINTS:
        if any(hint in normalized for hint in hints):
            return browser
    return None


def browser_for_explicit_path(browser: str, path: Path) -> str:
    if browser != "auto":
        return browser
    return infer_chromium_browser_from_path(path) or "auto"


def discover_cookie_dbs(browser: str, profile_dir: Optional[str], cookie_db: Optional[str]) -> List[Tuple[str, Path]]:
    if cookie_db:
        path = Path(cookie_db).expanduser()
        return [(browser_for_explicit_path(browser, path), path)]

    if profile_dir:
        root = Path(profile_dir).expanduser()
        candidates = [root / "Cookies", root / "Network" / "Cookies"]
        resolved_browser = browser_for_explicit_path(browser, root)
        return [(resolved_browser, path) for path in candidates if path.exists()]

    dbs: List[Tuple[str, Path]] = []
    for name in browser_order(browser):
        for root, patterns in BROWSER_PATHS.get(name, []):
            root_path = Path(root).expanduser()
            for pattern in patterns:
                dbs.extend((name, path) for path in root_path.glob(pattern) if path.exists())
    return sorted(set(dbs), key=lambda item: (item[0], str(item[1])))


def discover_safari_cookie_files(profile_dir: Optional[str], cookie_db: Optional[str]) -> List[Path]:
    if cookie_db:
        path = Path(cookie_db).expanduser()
        return [path] if path.exists() else []

    if profile_dir:
        root = Path(profile_dir).expanduser()
        return sorted(path for path in root.rglob("*.binarycookies") if path.exists())

    files = [Path(path).expanduser() for path in SAFARI_COOKIE_PATHS]
    http_storage = Path("~/Library/HTTPStorages").expanduser()
    if http_storage.exists():
        files.extend(http_storage.glob("*.binarycookies"))

    return sorted({path for path in files if path.exists()})


def keychain_password(browser: str) -> Optional[str]:
    if sys.platform != "darwin":
        return None

    for service in KEYCHAIN_SERVICES.get(browser, ()):
        try:
            result = subprocess.run(
                ["/usr/bin/security", "find-generic-password", "-w", "-s", service],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except OSError:
            continue

        password = result.stdout.strip()
        if result.returncode == 0 and password:
            return password

    return None


def decrypt_chromium_value(encrypted_value: bytes, browser: str) -> Optional[str]:
    if not encrypted_value:
        return None

    if not encrypted_value.startswith((b"v10", b"v11")):
        try:
            return encrypted_value.decode("utf-8")
        except UnicodeDecodeError:
            return None

    password = keychain_password(browser)
    if not password:
        return None

    try:
        from cryptography.hazmat.backends import default_backend
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes
    except ImportError:
        raise RuntimeError(
            "Encrypted Chromium cookies require: python3 -m pip install cryptography"
        )

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA1(),
        length=16,
        salt=b"saltysalt",
        iterations=1003,
        backend=default_backend(),
    )
    key = kdf.derive(password.encode("utf-8"))
    cipher = Cipher(algorithms.AES(key), modes.CBC(b" " * 16), backend=default_backend())
    decryptor = cipher.decryptor()
    decrypted = decryptor.update(encrypted_value[3:]) + decryptor.finalize()

    if not decrypted:
        return None

    padding = decrypted[-1]
    if padding <= 16:
        decrypted = decrypted[:-padding]

    for candidate in (decrypted, decrypted[32:] if len(decrypted) > 32 else b""):
        if not candidate:
            continue
        try:
            return candidate.decode("utf-8")
        except UnicodeDecodeError:
            continue

    return None


def sqlite_uri(path: Path) -> str:
    quoted_path = urllib.parse.quote(str(path), safe="/")
    return f"file:{quoted_path}?mode=ro"


def copy_sqlite_store(db_path: Path, temp_dir: Path) -> Path:
    temp_db = temp_dir / db_path.name
    shutil.copy2(db_path, temp_db)
    for suffix in ("-wal", "-shm"):
        sidecar = Path(str(db_path) + suffix)
        if sidecar.exists():
            shutil.copy2(sidecar, temp_dir / (db_path.name + suffix))
    return temp_db


def sqlite_rows(db_path: Path) -> Iterable[Tuple[str, str, str, bytes]]:
    connection: Optional[sqlite3.Connection] = None
    temp_context: Optional[tempfile.TemporaryDirectory[str]] = None
    try:
        connection = sqlite3.connect(sqlite_uri(db_path), uri=True)
    except sqlite3.Error:
        temp_context = tempfile.TemporaryDirectory(prefix="grok-cookies-")
        temp_db = copy_sqlite_store(db_path, Path(temp_context.name))
        connection = sqlite3.connect(sqlite_uri(temp_db), uri=True)

    try:
        connection.text_factory = bytes
        cursor = connection.cursor()
        cursor.execute("SELECT host_key, name, value, encrypted_value FROM cookies")
        for host, name, value, encrypted_value in cursor.fetchall():
            yield (
                sqlite_text(host),
                sqlite_text(name),
                sqlite_text(value),
                sqlite_blob(encrypted_value),
            )
    finally:
        if connection is not None:
            connection.close()
        if temp_context is not None:
            temp_context.cleanup()


def sqlite_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    return str(value)


def sqlite_blob(value: Any) -> bytes:
    if value is None:
        return b""
    if isinstance(value, bytes):
        return value
    if isinstance(value, str):
        return value.encode("utf-8", errors="ignore")
    return bytes(value)


def read_c_string(data: bytes, offset: int) -> str:
    if offset <= 0 or offset >= len(data):
        return ""
    end = data.find(b"\x00", offset)
    if end < 0:
        end = len(data)
    try:
        return data[offset:end].decode("utf-8")
    except UnicodeDecodeError:
        return ""


def parse_safari_binarycookies(path: Path, domain: str) -> Dict[str, str]:
    data = path.read_bytes()
    if len(data) < 8 or data[:4] != b"cook":
        return {}

    page_count = struct.unpack(">I", data[4:8])[0]
    offset = 8
    page_sizes = []
    for _ in range(page_count):
        if offset + 4 > len(data):
            return {}
        page_sizes.append(struct.unpack(">I", data[offset:offset + 4])[0])
        offset += 4

    cookies: Dict[str, str] = {}
    for page_size in page_sizes:
        page = data[offset:offset + page_size]
        offset += page_size
        if len(page) < 8:
            continue

        cookie_count = struct.unpack("<I", page[4:8])[0]
        if cookie_count > 10000:
            continue

        cookie_offsets = []
        for index in range(cookie_count):
            start = 8 + (index * 4)
            if start + 4 > len(page):
                break
            cookie_offsets.append(struct.unpack("<I", page[start:start + 4])[0])

        for cookie_offset in cookie_offsets:
            if cookie_offset + 48 > len(page):
                continue

            cookie_size = struct.unpack("<I", page[cookie_offset:cookie_offset + 4])[0]
            cookie = page[cookie_offset:cookie_offset + cookie_size]
            if len(cookie) < 48:
                continue

            try:
                domain_offset = struct.unpack("<I", cookie[16:20])[0]
                name_offset = struct.unpack("<I", cookie[20:24])[0]
                value_offset = struct.unpack("<I", cookie[28:32])[0]
            except struct.error:
                continue

            host = read_c_string(cookie, domain_offset)
            name = read_c_string(cookie, name_offset)
            value = read_c_string(cookie, value_offset)

            if host and name and value and domain_matches(host, domain):
                cookies[name] = value

    return cookies


def extract_from_safari(args: argparse.Namespace) -> Tuple[Dict[str, str], List[str]]:
    cookies: Dict[str, str] = {}
    sources: List[str] = []
    for path in discover_safari_cookie_files(args.profile_dir, args.cookie_db):
        try:
            file_cookies = parse_safari_binarycookies(path, args.domain)
        except Exception as error:
            if not args.quiet:
                print(f"Skipped {path}: {error}", file=sys.stderr)
            continue

        if file_cookies:
            cookies.update(file_cookies)
            sources.append(f"safari:{path.name} ({len(file_cookies)} cookies)")

    return cookies, sources


def extract_from_chromium_db(db_path: Path, browser: str, domain: str) -> Tuple[Dict[str, str], int]:
    cookies: Dict[str, str] = {}
    encrypted_matches = 0

    for host, name, value, encrypted_value in sqlite_rows(db_path):
        if not domain_matches(host, domain):
            continue

        cookie_value = value
        if not cookie_value and encrypted_value:
            encrypted_matches += 1
            cookie_value = decrypt_chromium_value(encrypted_value, browser) or ""

        if cookie_value:
            cookies[name] = cookie_value

    return cookies, encrypted_matches


def extract_with_browsercookie(browser: str, domain: str) -> Dict[str, str]:
    try:
        import browsercookie
    except ImportError:
        return {}

    loaders = []
    if browser in ("auto", "chrome"):
        loaders.append(("chrome", browsercookie.chrome))
    if browser in ("auto", "firefox"):
        loaders.append(("firefox", browsercookie.firefox))

    cookies: Dict[str, str] = {}
    for _, loader in loaders:
        try:
            jar = loader()
        except Exception:
            continue
        for cookie in jar:
            if domain_matches(cookie.domain, domain):
                cookies[cookie.name] = cookie.value

    return cookies


def extract_cookies(args: argparse.Namespace) -> Tuple[Dict[str, str], List[str], int]:
    cookies: Dict[str, str] = {}
    sources: List[str] = []
    encrypted_matches = 0

    if args.devtools_url:
        try:
            devtools_cookies = extract_from_devtools(args.devtools_url, args.domain)
        except Exception as error:
            if not args.quiet:
                print(f"Could not read cookies from DevTools: {error}", file=sys.stderr)
            devtools_cookies = {}
        if devtools_cookies:
            cookies.update(devtools_cookies)
            sources.append(f"devtools ({len(devtools_cookies)} cookies)")

    if args.browser in ("auto", "safari"):
        safari_cookies, safari_sources = extract_from_safari(args)
        if safari_cookies:
            cookies.update(safari_cookies)
            sources.extend(safari_sources)

    if args.browser in ("auto", "chrome", "firefox") and not args.cookie_db and not args.profile_dir:
        browsercookie_cookies = extract_with_browsercookie(args.browser, args.domain)
        if browsercookie_cookies:
            cookies.update(browsercookie_cookies)
            sources.append(f"browsercookie ({len(browsercookie_cookies)} cookies)")

    chromium_browser = "auto" if args.browser == "auto" else args.browser
    if chromium_browser == "safari":
        return cookies, sources, encrypted_matches

    for browser, db_path in discover_cookie_dbs(chromium_browser, args.profile_dir, args.cookie_db):
        try:
            db_cookies, encrypted_count = extract_from_chromium_db(db_path, browser, args.domain)
        except RuntimeError as error:
            print(str(error), file=sys.stderr)
            encrypted_matches += 1
            continue
        except Exception as error:
            if not args.quiet:
                print(f"Skipped {db_path}: {error}", file=sys.stderr)
            continue

        encrypted_matches += encrypted_count
        if db_cookies:
            cookies.update(db_cookies)
            sources.append(f"{browser}:{db_path.parent.name} ({len(db_cookies)} cookies)")

    return cookies, sources, encrypted_matches


def write_json(cookies: Dict[str, str], output: str) -> None:
    output_path = Path(output).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(cookies, indent=2, sort_keys=True) + "\n")
    os.chmod(output_path, 0o600)


def swift_literal(cookies: Dict[str, str]) -> str:
    lines = [
        "import Foundation",
        "",
        "public struct GrokCookies {",
        "    public static let cookies: [String: String] = [",
    ]
    for name, value in sorted(cookies.items()):
        escaped_value = value.replace("\\", "\\\\").replace('"', '\\"')
        escaped_name = name.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'        "{escaped_name}": "{escaped_value}",')
    lines.extend(["    ]", "}", ""])
    return "\n".join(lines)


def write_swift(cookies: Dict[str, str], output: str) -> None:
    output_path = Path(output).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(swift_literal(cookies))
    os.chmod(output_path, 0o600)


def validate_required(cookies: Dict[str, str], strict: bool) -> bool:
    if not strict:
        return True

    if not any(cookies.get(name) for name in AUTH_COOKIES):
        print(f"Missing required Grok auth cookies: one of {', '.join(AUTH_COOKIES)}", file=sys.stderr)
        present = [name for name in AUTH_COOKIES + OPTIONAL_AUTH_COOKIES if cookies.get(name)]
        if present:
            print(f"Auth-related cookies found: {', '.join(present)}", file=sys.stderr)
        else:
            print("No auth-related grok.com cookies were found.", file=sys.stderr)
        return False

    return True


def default_swift_output() -> str:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent if script_dir.name == "Scripts" else Path.cwd()
    return str(project_root / "Sources" / "GrokClient" / "GrokCookies.swift")


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract grok.com cookies for GrokCLI")
    parser.add_argument("--domain", default=".grok.com", help="Cookie domain to extract")
    parser.add_argument(
        "--browser",
        choices=["auto", "safari", "atlas", "chrome", "firefox", "chromium", "brave", "edge", "arc"],
        default="auto",
        help="Browser/profile family to scan",
    )
    parser.add_argument("--profile-dir", help="Explicit Chromium profile directory")
    parser.add_argument("--cookie-db", help="Explicit Chromium Cookies SQLite database")
    parser.add_argument("--devtools-url", help="Chrome DevTools HTTP URL for a browser launched with --remote-debugging-port")
    parser.add_argument("--format", choices=["json", "swift", "both"], default="json")
    parser.add_argument("--output", help="Output file")
    parser.add_argument("--required", action="store_true", help="Require login auth cookies")
    parser.add_argument("--quiet", action="store_true", help="Reduce progress output")
    args = parser.parse_args()

    if not args.quiet:
        print(f"Extracting cookies for {args.domain} from {args.browser}...", flush=True)

    cookies, sources, encrypted_matches = extract_cookies(args)

    if not cookies:
        print("No grok.com cookies found. Log in to https://grok.com in the selected browser first.", file=sys.stderr)
        if encrypted_matches:
            print("Some matching cookies were encrypted and could not be decrypted.", file=sys.stderr)
        return 1

    if not validate_required(cookies, args.required):
        if encrypted_matches:
            print("Some matching cookies were encrypted and could not be decrypted.", file=sys.stderr)
        return 2

    if not args.quiet:
        source_text = ", ".join(sources) if sources else "direct browser stores"
        present = [name for name in AUTH_COOKIES + OPTIONAL_AUTH_COOKIES if cookies.get(name)]
        print(f"Found {len(cookies)} grok.com cookies from {source_text}.")
        print(f"Auth-related cookies present: {', '.join(present) if present else 'none'}")

    if args.format == "json":
        if not args.output:
            print("--output is required for JSON credentials", file=sys.stderr)
            return 1
        write_json(cookies, args.output)
        if not args.quiet:
            print(f"Wrote JSON credentials to {args.output}")
    elif args.format == "swift":
        output = args.output or default_swift_output()
        write_swift(cookies, output)
        if not args.quiet:
            print(f"Wrote Swift credentials to {output}")
    else:
        if not args.output:
            print("--output is required for combined output", file=sys.stderr)
            return 1
        write_json(cookies, args.output)
        write_swift(cookies, default_swift_output())
        if not args.quiet:
            print(f"Wrote JSON credentials to {args.output}")
            print(f"Wrote Swift credentials to {default_swift_output()}")

    return 0


if __name__ == "__main__":
    sys.exit(main())