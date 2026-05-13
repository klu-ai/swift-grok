# Speech-to-Text Audio Input Plan

Date: 2026-05-14

Execution status: implemented and verified on 2026-05-14. Fresh verification included `swift build`, focused client/CLI/proxy tests, full `swift test`, `Scripts/install_cli.sh --user`, and installed CLI help checks for `grok message --audio`, `grok chat --audio`, and `grok transcribe`.

## Objective

Implement speech-to-text support across the Swift Grok client, Grok CLI, and OpenAI-compatible Vapor proxy so audio files can be transcribed through Grok's `/rest/voice/speech-to-text` endpoint and then used naturally as chat input.

The intended product behavior is:

- Non-interactive CLI audio input is transcribed and automatically sent as a message to Grok for a normal assistant response.
- Interactive CLI audio input can populate the editable prompt text field before sending, with an immediate-send variant available.
- The Swift client exposes a reusable speech-to-text API for callers.
- The proxy exposes an OpenAI-compatible `POST /v1/audio/transcriptions` endpoint, converting multipart file input to the Grok JSON/base64 contract.
- Tests and docs cover request shape, CLI behavior, proxy behavior, and safety around large base64 payloads.

## Success Criteria

- `GrokClient` can call `POST /rest/voice/speech-to-text` using existing auth/session machinery and parse the transcript.
- The Grok API request body uses JSON with:
  - `audioBase64`: raw base64 audio bytes, not a data URL.
  - `audioFormat`: extension-style format such as `webm`, `wav`, `mp3`, `m4a`, `ogg`, or `flac`.
  - `refinementLevel`: defaulting to `REFINEMENT_LEVEL_POLISH` unless the caller overrides it.
- `grok message --audio path/to/audio.webm` transcribes the file and sends the transcript as the message automatically.
- `grok chat --audio path/to/audio.webm` uses the same transcription path for the initial message.
- Interactive `/audio path/to/audio.webm` transcribes and pre-fills the editable input buffer; `/audio-send path/to/audio.webm` transcribes and sends immediately.
- `grok transcribe path/to/audio.webm` is available for transcript-only usage and debugging.
- CLI JSON and streaming JSON include transcript metadata without changing existing assistant event semantics.
- Proxy clients can call `POST /v1/audio/transcriptions` with multipart `file` and get an OpenAI-style `{ "text": "..." }` response.
- Audio/base64 bodies are not dumped in debug cURL output or verbose proxy logs.
- Unit, E2E, and proxy tests cover happy paths, validation failures, response parsing variants, and body/logging risks.

## Current-State Findings

### Commands Run During Discovery

- [x] `rg -n "enum RestNamespace|func normalizedBaseURLs|func makeRequest|func jsonObject|func validateHTTPResponse|func uploadFile|func curlRepresentation|firstString|firstDictionary|makeFileUploadResponse" Sources/GrokClient/GrokClient.swift`
- [x] `rg -n "handleMessageCommand|handleChatCommand|InputReader|recognizedCommands|messageRequestJSON|OutputFormat|func msg|struct GrokCommandOptions|enum OutputFormat" Sources/GrokCLI`
- [x] `rg -n "ChatCompletionsController|GrokConfiguration|defaultMaxBodySize|routes|ModelsResponse|ChatCompletionRequest|configure|/v1/chat/completions|models" Sources/GrokProxy`
- [x] `rg -n "MockGrokServer|TestEnvironment|GROK_BASE_URL|conversations/new|upload-file|VaporTesting|testMessage|message --|json|stream|configure\\(|ChatCompletionsController|Models" Tests README.md PROXY_README.md Scripts Package.swift`
- [x] Targeted `nl -ba ... | sed -n ...` reads for the files and line ranges listed below.

### Grok API Contract From Captured Browser Request

- [x] The server endpoint is `POST https://grok.com/rest/voice/speech-to-text`.
- [x] The request uses `Content-Type: application/json`.
- [x] The request body shape is:

```json
{
  "audioBase64": "raw-base64-audio",
  "audioFormat": "webm",
  "refinementLevel": "REFINEMENT_LEVEL_POLISH"
}
```

- [x] The product should not hardcode the browser curl cookies or browser-only headers. It should reuse the existing authenticated `GrokClient` request path, which already handles cookies, request IDs, statsig ID, common headers, and debug output.
- [x] The upstream Grok speech endpoint receives JSON/base64, not multipart form data.

### Client Findings

- [x] `GrokClient.makeRequest(path:method:payload:namespace:)` centralizes headers, cookies, JSON encoding, request IDs, statsig ID, and debug cURL generation in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1023).
- [x] `RestNamespace.root` maps to `/rest`, while `RestNamespace.appChat` maps to `/rest/app-chat` in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:788).
- [x] URL assembly appends the provided path to the chosen namespace base URL in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1029).
- [x] The correct client call should therefore use `namespace: .root` with `path: "/voice/speech-to-text"`, producing `/rest/voice/speech-to-text`.
- [x] `jsonObject(for:)` already performs `session.data(for:)`, validates status, handles empty bodies, and wraps JSON parsing errors in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1127).
- [x] Flexible JSON parsing helpers already exist: `stringValue` in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1091), `anyCodableDictionary` in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1178), `firstDictionary` in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1206), and `firstString` in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1369).
- [x] Existing file upload convenience reads the whole file and base64-encodes it in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:2329), but it posts to `/upload-file` with keys `fileName`, `fileMimeType`, and `content`, so it should not be reused directly for STT.
- [x] Debug cURL currently includes request bodies in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:2475), which is unsafe for large `audioBase64` payloads.

### CLI Findings

- [x] There is no current audio, voice, or transcribe CLI surface. Top-level commands are listed in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:88), and interactive slash commands are listed in [InteractiveCommandSpecs.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Interactive/InteractiveCommandSpecs.swift:11).
- [x] `GrokCLI.main()` normalizes leading app flags and dispatches commands in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:153).
- [x] No-arg CLI opens interactive chat in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:157).
- [x] Unknown top-level text becomes chat, unless JSON mode is requested, in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:175).
- [x] Explicit `chat` and `message` dispatch happens in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:187).
- [x] `chat --json ...` delegates to the non-interactive message path in [InteractiveSession.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Interactive/InteractiveSession.swift:43).
- [x] `message` currently supports inline args, `--stdin`, and `--prompt-file` as mutually exclusive prompt sources in [MessageCommand.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/MessageCommand.swift:204).
- [x] `message` resolves the final `messageText` before calling `app.msg` in [MessageCommand.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/MessageCommand.swift:214).
- [x] `message` resets/new-conversation behavior is handled before sending in [MessageCommand.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/MessageCommand.swift:281).
- [x] The shared final text-to-chat boundary is `GrokCLIApp.msg` in [GrokCLIApp.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Runtime/GrokCLIApp.swift:319), which chooses continue-vs-new-conversation around [GrokCLIApp.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Runtime/GrokCLIApp.swift:353).
- [x] The interactive chat loop reads a line, parses slash commands, and sends ordinary input to `app.msg` in [InteractiveSession.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Interactive/InteractiveSession.swift:302) and [InteractiveSession.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Interactive/InteractiveSession.swift:611).
- [x] `InputReader.readLine(prompt:)` owns the editable buffer, cursor, history, and enter behavior in [InputReader.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Interactive/InputReader.swift:40), initializing an empty buffer around [InputReader.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Interactive/InputReader.swift:78).
- [x] JSON result and event envelopes already exist in [JSONOutput.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Presentation/JSONOutput.swift:12) and [JSONOutput.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Presentation/JSONOutput.swift:42).
- [x] Message JSON request metadata is built in [JSONOutput.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Presentation/JSONOutput.swift:333).
- [x] Streaming JSON starts with request/progress events and then assistant events in [MessageCommand.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/MessageCommand.swift:461).

### Proxy Findings

- [x] `configure(_:)` sets a `10mb` body limit in [configure.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/configure.swift:26).
- [x] `configure(_:)` registers `routes(app)` and `GrokConfiguration.register(app)` in [configure.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/configure.swift:31).
- [x] `routes.swift` only has basic root/hello routes in [routes.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/routes.swift:3).
- [x] `GrokConfiguration.register` creates a concrete `ChatCompletionsController(grokClient:)` in [GrokConfiguration.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/Services/GrokConfiguration.swift:56).
- [x] Current OpenAI-compatible routes are only `POST /v1/chat/completions`, `GET /v1/models`, and `GET /models` in [ChatCompletionsController.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/Controllers/ChatCompletionsController.swift:14).
- [x] OpenAI model structs are centralized in [OpenAI.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/Models/OpenAI.swift:7).
- [x] Verbose proxy logging pretty-prints JSON request bodies in [VerboseLoggingMiddleware.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokProxy/Middleware/VerboseLoggingMiddleware.swift:45), which is a risk if JSON base64 audio is accepted.
- [x] There is no proxy client protocol/injection seam for successful tests today; existing proxy tests mostly avoid real Grok by testing validation failures in [GrokProxyTests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokProxyTests/GrokProxyTests.swift:55).

### Test And Documentation Findings

- [x] Client tests live in [GrokClientTests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokClientTests/GrokClientTests.swift:11).
- [x] `MockURLProtocol` supports static responses but does not capture outgoing request bodies or headers in [GrokClientTests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokClientTests/GrokClientTests.swift:548).
- [x] CLI E2E tests live in [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:12).
- [x] `TestEnvironment` sets `GROK_BASE_URL` for the CLI mock server in [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:1489).
- [x] `MockGrokServer.responseBody(for:)` handles mock routes in [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:1766).
- [x] The mock already handles `/rest/app-chat/upload-file` around [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:1849).
- [x] The CLI E2E request parser is JSON-oriented around [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:1962), which is fine for upstream Grok STT JSON but not enough for proxy multipart assertions.
- [x] Proxy tests live in [GrokProxyTests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokProxyTests/GrokProxyTests.swift:5).
- [x] README CLI usage starts around [README.md](/Users/stephenwalker/Code/klu/swift-grok/README.md:73), JSON docs around [README.md](/Users/stephenwalker/Code/klu/swift-grok/README.md:109), CLI examples around [README.md](/Users/stephenwalker/Code/klu/swift-grok/README.md:221), and proxy summary around [README.md](/Users/stephenwalker/Code/klu/swift-grok/README.md:275).
- [x] Proxy docs currently advertise chat/models but not audio around [PROXY_README.md](/Users/stephenwalker/Code/klu/swift-grok/PROXY_README.md:55).
- [x] Existing proxy verification scripts include [test_proxy_request.sh](/Users/stephenwalker/Code/klu/swift-grok/Scripts/test_proxy_request.sh:5), [test_proxy_streaming.sh](/Users/stephenwalker/Code/klu/swift-grok/Scripts/test_proxy_streaming.sh:8), and [test_proxy_models.sh](/Users/stephenwalker/Code/klu/swift-grok/Scripts/test_proxy_models.sh:5).

## Design Decisions

### Upstream Grok Request

- Use the captured browser contract as the source of truth:

```swift
let payload: [String: AnyCodable] = [
    "audioBase64": AnyCodable(audioBase64),
    "audioFormat": AnyCodable(audioFormat),
    "refinementLevel": AnyCodable(refinementLevel)
]
```

- Send it with:

```swift
let request = try makeRequest(
    path: "/voice/speech-to-text",
    payload: payload,
    namespace: .root
)
```

- The implementer should not include `/rest` in the path, because the `.root` namespace already maps to `/rest`.
- The implementer should not include browser cookies or browser-only headers from the captured curl. Existing client auth/cookie handling should be used.

### Client API

Add a small public response type and three public entry points:

```swift
public struct GrokSpeechToTextResponse: Sendable {
    public let text: String
    public let rawJSON: AnyCodable
}

public func speechToText(
    audioBase64: String,
    audioFormat: String,
    refinementLevel: String = "REFINEMENT_LEVEL_POLISH"
) async throws -> GrokSpeechToTextResponse

public func speechToText(
    audioData: Data,
    audioFormat: String,
    refinementLevel: String = "REFINEMENT_LEVEL_POLISH"
) async throws -> GrokSpeechToTextResponse

public func speechToText(
    at path: String,
    audioFormat: String? = nil,
    refinementLevel: String = "REFINEMENT_LEVEL_POLISH"
) async throws -> GrokSpeechToTextResponse
```

Keep `audioFormat` and `refinementLevel` string-based for the first implementation because the discovered endpoint uses raw string values and accepted enum values are not fully confirmed. Typed convenience enums can be added later without blocking the current integration.

### Audio Format Inference

Infer `audioFormat` from file extension for:

- `webm`
- `wav`
- `mp3`
- `m4a`
- `ogg`
- `flac`
- `mp4`
- `mpeg`
- `mpga`

If inference fails, require `--audio-format` in CLI/proxy or throw a clear client error in the path convenience API. Do not silently default unknown files to `webm`.

### Transcript Parsing

Parse response JSON flexibly. Try these in order:

- Top-level `text`
- Top-level `transcript`
- Top-level `message`
- Nested `data.text`
- Nested `data.transcript`
- Nested `result.text`
- Nested `result.transcript`

If no transcript is found, throw `GrokError.apiError` with enough response context to debug without including the full audio payload.

### CLI Behavior

Add audio as a prompt source, then convert it to text before the existing `app.msg(message:)` boundary.

Recommended top-level commands:

```bash
grok message --audio recording.webm
grok message --audio recording.webm --audio-format webm
grok message --audio - --audio-format webm
grok chat --audio recording.webm
grok transcribe recording.webm
grok transcribe recording.webm --json
```

Rules:

- `--audio <path>` is mutually exclusive with inline message args, `--stdin`, and `--prompt-file` in `message`.
- `--audio -` reads binary audio bytes from stdin and requires `--audio-format`.
- Non-interactive `message --audio` transcribes, then automatically sends the transcript as the chat message and prints the assistant response.
- `transcribe` only prints the transcript and does not create or continue a Grok chat.
- If the user supplies both an instruction and an audio file in the future, that should be added as a separate explicit mode such as `--audio-context` or `--with-audio`; do not overload the initial prompt-source implementation.

Recommended interactive commands:

```text
/audio path/to/audio.webm
/audio-send path/to/audio.webm
/transcribe path/to/audio.webm
```

Rules:

- `/audio` transcribes and pre-fills the editable input buffer with the transcript. The user can edit and press Enter to send.
- `/audio-send` transcribes and sends immediately through the existing chat path.
- `/transcribe` prints the transcript in the interactive session without sending it.
- Bare audio file paths should not be treated specially, because bare input is currently user chat text.

### CLI JSON Behavior

For non-streaming `--json`, include transcript metadata without changing the existing `grok.cli.result.v1` envelope:

```json
{
  "data": {
    "message": "assistant reply",
    "input": {
      "kind": "audio",
      "transcript": "transcribed user text",
      "audio": {
        "path": "recording.webm",
        "format": "webm",
        "refinementLevel": "REFINEMENT_LEVEL_POLISH"
      }
    },
    "request": {
      "stream": false
    }
  }
}
```

For streaming `--json`, emit a transcription event before the existing request/assistant events:

```json
{"event":"transcription","data":{"text":"transcribed user text","audio":{"path":"recording.webm","format":"webm"}}}
{"event":"request","data":{"message":"transcribed user text","input":{"kind":"audio"}}}
```

Keep existing assistant delta/final/done events unchanged.

### Proxy Behavior

Add a new `AudioTranscriptionsController: RouteCollection` and register it beside `ChatCompletionsController`.

Primary OpenAI-compatible route:

```http
POST /v1/audio/transcriptions
Content-Type: multipart/form-data
```

Supported fields:

- `file`: required audio file.
- `model`: required for OpenAI compatibility, but internally can be ignored or mapped to the default Grok mode.
- `response_format`: optional. Support `json` and `text` first.
- `prompt`: optional. Defer using it upstream unless Grok STT exposes a compatible field.
- `language`: optional. Validate and preserve in metadata if useful, but do not send upstream unless confirmed.
- `audio_format`: optional extension override for cases where filename/content-type inference fails.
- `refinement_level`: optional override for Grok `refinementLevel`.

Default response:

```json
{
  "text": "transcribed text"
}
```

Also support `response_format=text` by returning `text/plain`.

Optional non-standard JSON route support:

```json
{
  "audioBase64": "raw-base64-audio",
  "audioFormat": "webm",
  "refinementLevel": "REFINEMENT_LEVEL_POLISH",
  "model": "ignored-but-accepted"
}
```

This is useful for scripts and internal tests, but OpenAI SDK compatibility depends on multipart.

### Logging And Debug Safety

- Redact or summarize `audioBase64` in `GrokClient` debug cURL output.
- Redact or summarize JSON request fields named `audioBase64`, `content`, `data`, or `file` when verbose proxy logging is enabled.
- Keep multipart logs to byte counts and metadata only.
- Do not print full transcripts in logs unless the existing log level already prints user messages. Even then, preserve the same policy as chat text.

## Workstreams

These workstreams are designed for up to six parallel agents. Each workstream has a clear write boundary to reduce conflicts.

### Workstream 1: Client Speech-to-Text API

Ownership:

- [ ] `Sources/GrokClient/GrokClient.swift`
- [ ] Any new client model file under `Sources/GrokClient/` if the implementer chooses to split response types.

Tasks:

- [ ] Add `GrokSpeechToTextResponse` with `text` and `rawJSON`.
- [ ] Add `speechToText(audioBase64:audioFormat:refinementLevel:)`.
- [ ] Add `speechToText(audioData:audioFormat:refinementLevel:)`.
- [ ] Add `speechToText(at:audioFormat:refinementLevel:)`, including `~` expansion consistent with `uploadFile(at:)`.
- [ ] Add audio-format inference from extension.
- [ ] Validate empty audio, empty format, and unknown extension with clear errors.
- [ ] Use `makeRequest(path: "/voice/speech-to-text", namespace: .root)`.
- [ ] Use `jsonObject(for:)` for response handling.
- [ ] Parse flexible response shapes and throw `GrokError.apiError` if no transcript is present.
- [ ] Redact/truncate `audioBase64` in debug cURL output without breaking existing debug behavior for ordinary chat payloads.

Dependencies:

- None.

### Workstream 2: CLI Non-Interactive Audio Input

Ownership:

- [ ] `Sources/GrokCLI/Commands/MessageCommand.swift`
- [ ] `Sources/GrokCLI/Core/TopLevelRouter.swift`
- [ ] New helper file under `Sources/GrokCLI/Commands/` or `Sources/GrokCLI/Core/`, for example `AudioInputResolver.swift`.
- [ ] `Sources/GrokCLI/Presentation/JSONOutput.swift`

Tasks:

- [ ] Add `--audio <path>` to `message` option parsing.
- [ ] Add `--audio-format <format>` and `--refinement-level <level>`.
- [ ] Add `--audio -` support for binary stdin, requiring `--audio-format`.
- [ ] Treat `--audio` as a prompt source mutually exclusive with inline args, `--stdin`, and `--prompt-file`.
- [ ] Before `app.msg`, call `GrokClient.speechToText` and set `messageText` to the transcript.
- [ ] Preserve existing `message` conversation reset/new-message behavior.
- [ ] Add `chat --audio <path>` support by routing the initial chat prompt through the same resolver.
- [ ] Add a `transcribe` top-level command that prints only the transcript.
- [ ] Add JSON result metadata for audio-derived input.
- [ ] Add streaming JSON `transcription` event before existing request/assistant events.
- [ ] Ensure normal non-JSON `message --audio` prints only the assistant response, not an extra transcript line, unless a verbose flag is added later.

Dependencies:

- Depends on Workstream 1 client API.

### Workstream 3: CLI Interactive Audio Input And Prefill

Ownership:

- [ ] `Sources/GrokCLI/Interactive/InputReader.swift`
- [ ] `Sources/GrokCLI/Interactive/InteractiveSession.swift`
- [ ] `Sources/GrokCLI/Interactive/InteractiveCommandParser.swift`
- [ ] `Sources/GrokCLI/Interactive/InteractiveCommandSpecs.swift`
- [ ] `Sources/GrokCLI/Presentation/HelpText.swift`

Tasks:

- [ ] Add `InputReader.readLine(prompt:prefill:)`.
- [ ] Initialize the editable buffer with `prefill` and the cursor at the end.
- [ ] Preserve existing editing, history, completion, backspace, arrow, and Enter behavior.
- [ ] Add `/audio <path>` command to transcribe and prefill the input buffer.
- [ ] Add `/audio-send <path>` command to transcribe and immediately call the existing send path.
- [ ] Add `/transcribe <path>` command to print transcript only.
- [ ] Document the new slash commands in interactive help/specs.
- [ ] Decide non-TTY fallback: `/audio` should send immediately or print an explanatory error because prefill editing requires a TTY.

Dependencies:

- Depends on Workstream 1 client API.
- Should share the audio resolver logic from Workstream 2 where practical.

### Workstream 4: Proxy Audio Transcriptions Endpoint

Ownership:

- [ ] New `Sources/GrokProxy/Controllers/AudioTranscriptionsController.swift`
- [ ] `Sources/GrokProxy/Services/GrokConfiguration.swift`
- [ ] `Sources/GrokProxy/configure.swift`
- [ ] `Sources/GrokProxy/Models/OpenAI.swift` or new `Sources/GrokProxy/Models/OpenAIAudio.swift`
- [ ] `Sources/GrokProxy/Middleware/VerboseLoggingMiddleware.swift`

Tasks:

- [ ] Add request/response models for audio transcription.
- [ ] Add a narrow transcription service/protocol so proxy tests can inject a fake.
- [ ] Register `AudioTranscriptionsController` beside `ChatCompletionsController`.
- [ ] Implement `POST /v1/audio/transcriptions`.
- [ ] Parse multipart `file`, `model`, optional `response_format`, optional `audio_format`, optional `refinement_level`, optional `language`, and optional `prompt`.
- [ ] Infer audio format from filename/content-type when `audio_format` is absent.
- [ ] Convert multipart file bytes to raw base64 and call `GrokClient.speechToText`.
- [ ] Support optional JSON/base64 request body for scriptability.
- [ ] Return `{ "text": transcript }` for `json` or missing `response_format`.
- [ ] Return `text/plain` for `response_format=text`.
- [ ] Return OpenAI-style `400` for unsupported response formats such as `verbose_json`, `srt`, or `vtt` until implemented.
- [ ] Make body limit configurable with `GROK_PROXY_MAX_BODY_SIZE`, defaulting to an audio-safe value such as `50mb`.
- [ ] Redact audio/base64 fields in verbose JSON logging.

Dependencies:

- Depends on Workstream 1 client API.

### Workstream 5: Tests

Ownership:

- [ ] `Tests/GrokClientTests/GrokClientTests.swift`
- [ ] `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- [ ] `Tests/GrokProxyTests/GrokProxyTests.swift`
- [ ] Any new test helpers under `Tests/`

Tasks:

- [ ] Extend `MockURLProtocol` to capture outgoing requests safely.
- [ ] Add client tests for `/rest/voice/speech-to-text` URL construction.
- [ ] Add client tests for exact JSON keys `audioBase64`, `audioFormat`, and `refinementLevel`.
- [ ] Add client tests proving no chat-only payload fields are present.
- [ ] Add client tests for response variants: top-level `text`, top-level `transcript`, nested `data.text`, and nested `result.text`.
- [ ] Add client tests for missing transcript and non-2xx errors.
- [ ] Add client tests for file path convenience, base64 encoding, and unknown extension handling.
- [ ] Add CLI mock server case for `/rest/voice/speech-to-text`.
- [ ] Add CLI E2E test for `message --audio file` sending transcript as chat message.
- [ ] Add CLI E2E test for prompt-source conflicts.
- [ ] Add CLI E2E test for `message --audio file --json` transcript metadata.
- [ ] Add CLI E2E test for `message --audio file --stream --json` transcription event ordering and monotonic sequence numbers.
- [ ] Add CLI E2E test for `chat --audio file`.
- [ ] Add CLI tests for `transcribe file` and `transcribe file --json`.
- [ ] Add interactive or unit-level tests for `InputReader` prefill editing.
- [ ] Add proxy tests for missing file/model, unsupported format, invalid base64, and content-type validation.
- [ ] Add proxy tests for multipart happy path using injected fake transcriber.
- [ ] Add proxy tests for JSON/base64 happy path if that extension is implemented.
- [ ] Add proxy tests for `response_format=json` and `response_format=text`.
- [ ] Add test coverage that verbose logging/debug cURL does not include full base64 audio.

Dependencies:

- Depends on Workstreams 1-4 as those surfaces land.
- Can begin by adding request-capture helpers before product implementation is complete.

### Workstream 6: Docs, Scripts, And Manual Verification

Ownership:

- [ ] `README.md`
- [ ] `PROXY_README.md`
- [ ] `DOCKER.md`
- [ ] New `Scripts/test_proxy_transcription.sh`
- [ ] Any release notes or examples file if present.

Tasks:

- [ ] Document Swift client speech-to-text methods.
- [ ] Document CLI non-interactive usage: `message --audio`, `chat --audio`, and `transcribe`.
- [ ] Document interactive usage: `/audio`, `/audio-send`, and `/transcribe`.
- [ ] Document that non-interactive audio input automatically sends the transcript for a Grok response.
- [ ] Document `--audio -` binary stdin and the requirement for `--audio-format`.
- [ ] Document proxy `POST /v1/audio/transcriptions`.
- [ ] Provide proxy curl example with multipart:

```bash
curl http://127.0.0.1:8080/v1/audio/transcriptions \
  -F file=@recording.webm \
  -F model=grok \
  -F response_format=json
```

- [ ] Document optional JSON/base64 proxy request if implemented.
- [ ] Add Docker notes for mounting audio files when testing proxy transcription in a container.
- [ ] Add `Scripts/test_proxy_transcription.sh` modeled after existing proxy scripts.
- [ ] Include supported audio formats and known limitations.

Dependencies:

- Can draft in parallel, but final examples should match implemented flags and route behavior.

## Concrete Implementation Steps

1. Client API
   - Add the response type and speech-to-text methods.
   - Add format inference helper.
   - Add flexible response parsing helper.
   - Add debug-body redaction for `audioBase64`.
   - Add focused client tests.

2. CLI resolver
   - Create a shared helper that resolves an audio source into `(transcript, metadata)`.
   - Support path input and `-` binary stdin.
   - Validate `audioFormat` and `refinementLevel`.
   - Keep this helper independent of message/chat state so it can be reused by `message`, `chat`, `transcribe`, and interactive commands.

3. Non-interactive CLI
   - Add `--audio`, `--audio-format`, and `--refinement-level` to `message`.
   - Add top-level `transcribe`.
   - Add `chat --audio` initial prompt handling.
   - Add JSON and streaming JSON metadata/events.
   - Update help text.
   - Add CLI E2E tests.

4. Interactive CLI
   - Add `InputReader` prefill support.
   - Wire `/audio`, `/audio-send`, and `/transcribe`.
   - Add interactive help/specs.
   - Add prefill tests.

5. Proxy
   - Add a transcription service/protocol and make `GrokClient` conform.
   - Add `AudioTranscriptionsController`.
   - Add multipart parsing and JSON/base64 optional parsing.
   - Add response format handling.
   - Add body-size configuration and logging redaction.
   - Add proxy tests.

6. Docs and scripts
   - Update README and proxy docs.
   - Add manual verification script.
   - Add Docker notes.

7. Verification and install
   - Run targeted tests first, then full test suite.
   - Run `swift build`.
   - Run the project install path used by this repo so the user can test the new CLI from their shell.
   - Run manual proxy transcription script against a local server with a tiny fixture audio file.

## Test And Verification Gates

Required automated gates:

- [x] `swift test --filter GrokClientTests`
- [x] `swift test --filter GrokCLIE2ETests`
- [x] `swift test --filter GrokProxyTests`
- [x] `swift test`
- [x] `swift build`

Required manual gates after implementation:

- [ ] `grok transcribe Tests/Fixtures/audio/sample.webm` prints only transcript.
- [ ] `grok message --audio Tests/Fixtures/audio/sample.webm` sends transcript and prints assistant response.
- [ ] `grok message --audio Tests/Fixtures/audio/sample.webm --json` emits a single valid result envelope with `data.input.kind == "audio"`.
- [ ] `grok message --audio Tests/Fixtures/audio/sample.webm --stream --json` emits `transcription` before assistant events.
- [ ] In interactive mode, `/audio Tests/Fixtures/audio/sample.webm` pre-fills the editable prompt.
- [ ] In interactive mode, `/audio-send Tests/Fixtures/audio/sample.webm` sends immediately.
- [ ] Local proxy accepts multipart transcription:

```bash
curl http://127.0.0.1:8080/v1/audio/transcriptions \
  -F file=@Tests/Fixtures/audio/sample.webm \
  -F model=grok \
  -F response_format=json
```

- [ ] Debug/verbose logs do not contain the full base64 audio body.
- [x] The final implementation branch has run the repo install step after build so the user can test from the installed path.

## Risks And Edge Cases

- Large recordings can exceed memory or body limits because the first implementation reads files into memory and base64 increases size by roughly one third.
- The captured endpoint may accept only some `audioFormat` values. Tests should use `webm` first because the captured curl used `webm`.
- The captured endpoint may return a response shape different from guessed transcript keys. Keep raw JSON in the response and make parsing extensible.
- `refinementLevel` values are not fully known. Default to the captured value `REFINEMENT_LEVEL_POLISH`, allow raw string override, and avoid premature enum restrictions.
- Debug cURL and verbose proxy logs could leak huge audio bodies or user speech content if not redacted.
- `--audio -` conflicts conceptually with existing text stdin. Keep it explicit and require `--audio-format`.
- Interactive prefill requires a TTY. Non-TTY fallback must not pretend the user can edit the transcript.
- Proxy OpenAI compatibility depends on multipart support. JSON/base64 is useful, but it is not enough for OpenAI SDK clients.
- Existing proxy success tests are hard without dependency injection; the proxy workstream must add a narrow fakeable transcription service.
- Adding body limit configuration can affect existing proxy behavior if defaults change too aggressively. Use an env var and document the default.

## Rollback Notes

- Client STT additions can be reverted independently if no existing API signatures are changed.
- CLI audio flags and `transcribe` command can be disabled by removing their router/help entries while leaving the client API intact.
- Interactive audio commands can be removed without affecting non-interactive CLI if the shared audio resolver remains.
- Proxy audio controller registration can be removed from `GrokConfiguration.register` to disable `/v1/audio/transcriptions` while keeping chat/models routes unchanged.
- Body size configuration should be backward compatible if the default remains documented and existing chat/model routes continue to pass tests.
- Redaction changes should be retained even if STT is rolled back, because they reduce risk for any future large payload.

## Final Completion Checklist

- [x] Requirement: "The server supports speech to text."
  - Evidence: `GrokClient.speechToText` calls `/rest/voice/speech-to-text` with the captured JSON contract and has request-shape tests.

- [x] Requirement: "What's the right way to implement this into the product so that it works."
  - Evidence: Client, CLI, proxy, tests, docs, and scripts are implemented as separate workstreams with shared client API and no duplicate Grok request logic.

- [x] Requirement: "Can the CLI take audio input?"
  - Evidence: `grok message --audio`, `grok chat --audio`, `grok transcribe`, `/audio`, `/audio-send`, and `/transcribe` are documented and tested.

- [x] Requirement: "How to input file into the API?"
  - Evidence: Client path/data helpers read audio bytes, base64-encode them, infer/accept audio format, and send JSON to Grok; proxy multipart converts `file` to the same base64 JSON request.

- [x] Requirement: "What does the API need as an input?"
  - Evidence: Docs and tests show `audioBase64`, `audioFormat`, and `refinementLevel` for Grok; proxy docs show multipart `file`, `model`, and optional `response_format` for OpenAI-compatible clients.

- [x] Requirement: "How to return the text to the text field in CLI?"
  - Evidence: `InputReader.readLine(prompt:prefill:)` preloads the transcript for `/audio`, allowing the user to edit before pressing Enter.

- [x] Requirement: "When not in interactive mode, the audio input should automatically be sent to the API for a response."
  - Evidence: `message --audio` and `chat --audio` transcribe first and then call the existing `app.msg(message:)` path automatically; transcript-only behavior is isolated to the explicit `transcribe` command.

- [x] Requirement: Build/install after implementation so user can test on path.
- Evidence: `swift build`, full tests, and the repo install path were run after implementation; installed CLI help was checked, and audio flows are covered by mocked E2E tests.
