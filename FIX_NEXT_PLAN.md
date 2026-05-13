# Fix Next Plan

This file captures the review feedback that should be fixed next. All three items are P2 because they can break advertised behavior or make the cookie extractor silently miss valid auth cookies in common setups.

## 1. Preserve streaming instead of buffering responses

**Review finding:** `Sources/GrokClient/GrokClient.swift` regresses streaming by buffering the full response before yielding parsed events. For SSE or line-streaming responses, using `URLSession.data(for:)` waits for the server to finish the body before any tokens are emitted. If the server keeps the stream open, callers using `--stream` can hang without receiving incremental output.

**Relevant code:**

- `streamResponses(from lines:)` at `Sources/GrokClient/GrokClient.swift` already parses an `AsyncSequence<String>` incrementally and should remain the primary streaming parser.
- `streamResponses(from data:)` at `Sources/GrokClient/GrokClient.swift` converts the whole body into one `String` and then splits by newline, so it cannot provide incremental tokens.
- `streamResponses(for request:)` should ensure the streaming code path never depends on `data(for:)` for a live stream.

**Implementation direction:**

- Keep the line-based `streamResponses(from lines:)` helper as the shared parser.
- Route streaming requests through a byte or line stream so parsing happens as lines arrive.
- Avoid using `session.data(for:)` for streaming responses. If a platform-specific fallback is necessary, document why and make sure it does not affect advertised streaming behavior for supported streaming clients.
- Preserve the existing HTTP error handling behavior: collect enough response body data for useful error messages on non-2xx responses, but do not consume or buffer successful streaming responses.
- Consider removing `streamResponses(from data:)` if it is no longer needed, or keep it only for non-streaming tests/fixtures so it is not accidentally used by production streaming code.

**Verification:**

- Add or update a test with a delayed line/SSE source that yields multiple chunks and asserts the first parsed `ConversationResponse` is delivered before the source completes.
- Add a regression check for a stream that remains open after yielding at least one event, proving consumers receive partial output instead of waiting for EOF.
- Run the Swift package tests and manually exercise `--stream` against a real or mocked Grok streaming endpoint.

## 2. Read Chromium WAL data before extracting cookies

**Review finding:** `Scripts/cookie_extractor.py` opens Chromium cookie databases with `immutable=1`. Chrome, Brave, Arc, Edge, and other Chromium browsers commonly keep the Cookies database in WAL mode while the browser is open. An immutable connection ignores `Cookies-wal`, so recent `sso` or `sso-rw` rows can be missing, and the query can even see stale schema state.

**Relevant code:**

- `sqlite_rows(db_path)` currently builds `file:{db_path}?mode=ro&immutable=1`.
- The fallback copy path only copies the main `Cookies` file, not adjacent `Cookies-wal` and `Cookies-shm` files.
- `extract_from_chromium_db(...)` depends on `sqlite_rows(...)`, so this affects all Chromium-family browser DB reads.

**Implementation direction:**

- Prefer a normal read-only SQLite connection that can see WAL state, for example `mode=ro` without `immutable=1`, when reading the original browser database.
- If a copy fallback is needed, copy the main database plus adjacent WAL files using the same basename:
  - `Cookies`
  - `Cookies-wal`
  - `Cookies-shm`
- Connect to the copied database only after those sidecar files are in place, so SQLite can recover a consistent snapshot.
- Clean up temporary directories after use if the current fallback leaves them behind.
- Keep error handling quiet unless `--quiet` is disabled, matching the existing extractor behavior.

**Verification:**

- Create or use a temporary SQLite cookie database in WAL mode, insert a matching `.grok.com` cookie without checkpointing, and assert `sqlite_rows(...)` can read it.
- Test the copy fallback with `Cookies`, `Cookies-wal`, and `Cookies-shm` present.
- Manually verify against an open Chromium-family browser profile where `Cookies-wal` exists and contains recent auth cookie writes.

## 3. Infer a real browser for explicit cookie stores

**Review finding:** If a user passes `--cookie-db` or `--profile-dir` while leaving `--browser auto`, encrypted Chromium cookies are decrypted using browser `"auto"`. `KEYCHAIN_SERVICES` has no `"auto"` entry, so valid encrypted cookies are treated as undecryptable even though the path often reveals the real browser.

**Relevant code:**

- `discover_cookie_dbs(browser, profile_dir, cookie_db)` returns `(browser, path)` directly for explicit paths, so `"auto"` flows through unchanged.
- `decrypt_chromium_value(encrypted_value, browser)` calls `keychain_password(browser)`.
- `keychain_password(browser)` looks up `KEYCHAIN_SERVICES[browser]`; with `"auto"`, it tries no services.

**Implementation direction:**

- Add a browser inference helper for explicit paths. It should inspect the supplied `--cookie-db` or `--profile-dir` path and map known profile roots to browser names such as `chrome`, `brave`, `edge`, `arc`, `chromium`, or `atlas`.
- Use the inferred browser in `discover_cookie_dbs(...)` when the caller passed `--browser auto`.
- If the path cannot be confidently inferred, try a safe ordered set of Chromium keychain services rather than giving up immediately. This can be implemented by either:
  - adding an `"auto"` service list to `KEYCHAIN_SERVICES`, or
  - teaching `keychain_password("auto")` / `decrypt_chromium_value(..., "auto")` to try the known Chromium services in a deterministic order.
- Avoid using Safari or Firefox keychain behavior for Chromium SQLite cookie stores.
- Include the resolved browser name in the source label so troubleshooting output reflects what was actually used for decryption.

**Verification:**

- Unit-test browser inference with paths under common roots:
  - `~/Library/Application Support/Google/Chrome/...`
  - `~/Library/Application Support/BraveSoftware/Brave-Browser/...`
  - `~/Library/Application Support/Microsoft Edge/...`
  - `~/Library/Application Support/Arc/User Data/...`
  - `~/Library/Application Support/Chromium/...`
- Test that `--cookie-db /path/to/Chrome/.../Cookies --browser auto` attempts Chrome/Chromium keychain services instead of none.
- Test that an unknown explicit Chromium DB path with `--browser auto` still attempts the fallback Chromium service order.

## Suggested order

1. Fix the Swift streaming regression first because it affects live `--stream` behavior and can cause hangs.
2. Fix WAL-aware cookie DB reading next because it can silently miss fresh auth cookies while browsers are open.
3. Fix explicit cookie-store browser inference last, then run the cookie extractor checks together because items 2 and 3 touch the same script.

## Final validation checklist

- Swift streaming tests pass.
- Cookie extractor tests pass, including WAL-mode and explicit-path cases.
- `swift test` passes.
- A manual `--stream` run yields tokens incrementally.
- A manual cookie extraction against an open Chromium-family browser can find required Grok auth cookies when present.
