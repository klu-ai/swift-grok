# Test Commands

Run commands from the repository root unless noted.

## Swift Package Tests

Prerequisites:

- Swift 6 toolchain. Check with `swift --version`.
- macOS 14 or newer for CLI target assumptions and local audio command coverage.
- No Grok account, browser session, or saved credentials are required. Networked behavior is covered with URL protocol mocks, an in-process Vapor app, or a local mock Grok server.

Commands:

```bash
swift test
swift test --filter GrokClientTests
swift test --filter GrokProxyTests
swift test --filter GrokCLIE2ETests
```

Coverage:

- `GrokClientTests`: client model and response decoding, endpoint selection, request payloads, model aliases, speech-to-text helpers, stream parsing, and mocked client request paths.
- `GrokProxyTests`: in-process Vapor routes for `/hello`, `/v1/models`, `/models`, chat completion validation, audio transcription validation, response formats, and multipart audio conversion. These tests do not require a separately running proxy.
- `GrokCLIE2ETests`: the `grok` executable against a local mock Grok server, including top-level commands, interactive chat, JSON and NDJSON output, auth import/generation paths with fake extractors, audio/transcription flows, model selection, resource commands, formatting, and error handling.
- `AudioRecordingDeviceTests`: included in the CLI E2E test target and covers AVFoundation audio input argument formatting.

## Python Cookie Extractor Tests

Prerequisites:

- Python 3.
- No browser login is required.

Command:

```bash
python3 Tests/test_cookie_extractor.py
```

Coverage:

- Imports `Scripts/cookie_extractor.py` directly.
- Tests SQLite cookie database reading, including WAL sidecars and copy fallback behavior.
- Tests handling of invalid encrypted cookie text as bytes.
- Tests browser/profile inference from explicit cookie database paths.
- Tests macOS keychain service probing through mocked subprocess calls.

## Proxy Smoke Scripts

These scripts are manual smoke checks, not `swift test` suites. They require a running proxy and may call Grok through real credentials.

Prerequisites:

- `curl`.
- A running proxy on `http://127.0.0.1:8080` for the chat and model scripts. Start one with:

```bash
swift run proxy serve
```

- Valid proxy credentials, either by setting `GROK_COOKIES` to a JSON object of cookie key/value strings or by placing `credentials.json` in the proxy process working directory. `Scripts/setup_proxy.sh` can generate `credentials.json` from browser cookies when Python 3 and a logged-in browser session are available.
- `jq` for `./Scripts/test_proxy_models.sh`.
- A readable local audio file for `./Scripts/test_proxy_transcription.sh`.

Commands:

```bash
./Scripts/test_proxy_request.sh
./Scripts/test_proxy_streaming.sh
./Scripts/test_proxy_models.sh
./Scripts/test_proxy_transcription.sh <audio-file> [model]
```

Transcription-specific environment variables:

- `GROK_PROXY_URL`: overrides the proxy base URL for `test_proxy_transcription.sh`. Defaults to `http://127.0.0.1:8080`.
- `GROK_TRANSCRIPTION_MODEL`: overrides the transcription model when the command does not pass `[model]`. Defaults to `whisper-1`.

Coverage:

- `test_proxy_request.sh`: sends a non-streaming OpenAI-style chat completion request to `/v1/chat/completions`.
- `test_proxy_streaming.sh`: sends two streaming chat completion requests, prints the raw server-sent events, and fails if the stream does not include a terminal `finish_reason: "stop"` chunk followed by `data: [DONE]`.
- `test_proxy_models.sh`: calls `/v1/models` and `/models`, then formats both JSON responses with `jq`.
- `test_proxy_transcription.sh`: sends a multipart audio upload to `/v1/audio/transcriptions` and prints the transcription response.
