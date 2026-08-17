# CLI Non-Interactive Image Generation Plan

Date: 2026-05-14

Execution status: plan only. No implementation, build, tests, install, or live Grok calls have been run for this request.

## Objective

Add scriptable, non-interactive text-to-image generation to the `grok` CLI using the Grok Imagine private WebSocket flow documented in `/Users/stephenwalker/Documents/Codex/2026-05-13/files-mentioned-by-the-user-screenshot-2/grok-imagine-api-guide.md`.

The first implementation should provide a top-level `grok image` command, with `grok images` as an alias, that:

- Accepts a text prompt from inline arguments, `--prompt-file`, or stdin.
- Opens the Grok Imagine WebSocket endpoint.
- Sends an `input_text` generation request with image options.
- Collects completed image frames.
- Prints URLs or saved file paths in script-friendly formats.
- Supports JSON output for automation.
- Leaves interactive chat, proxy image endpoints, image editing, video generation, and template pipelines out of scope.

## Success Criteria

- `grok image "a cinematic chrome airship over Bangkok at dusk"` generates image results and exits.
- `grok image --json ...` writes exactly one JSON result envelope to stdout on success, with no human banners.
- `grok image --raw --quiet ...` writes only generated image URLs or local output paths, one per line, to stdout.
- `grok image --prompt-file prompt.txt`, `cat prompt.txt | grok image --stdin`, and implicit piped stdin work consistently with `grok message`.
- `grok image --aspect-ratio 16:9 --count 4 --quality pro --resolution 2mp ...` maps to documented Imagine properties.
- `grok image --output ./images ...` downloads each completed image URL and writes deterministic local files.
- Usage errors exit with code `2`; API/WebSocket errors exit with code `1`.
- Cookie values are never printed in debug output or errors.
- Tests cover request envelope construction, response parsing, CLI routing, prompt-source validation, JSON/raw output, output-file behavior, and parse-error no-network behavior.
- After implementation is approved and completed later, run build, focused tests, full tests, install, and PATH smoke checks so the user can test the installed CLI.

## Current-State Findings

### Discovery Commands Run

- [x] `sed -n '1,220p' /Users/stephenwalker/Documents/Codex/2026-05-13/files-mentioned-by-the-user-screenshot-2/grok-imagine-api-guide.md`
- [x] `sed -n '221,520p' /Users/stephenwalker/Documents/Codex/2026-05-13/files-mentioned-by-the-user-screenshot-2/grok-imagine-api-guide.md`
- [x] `sed -n '521,980p' /Users/stephenwalker/Documents/Codex/2026-05-13/files-mentioned-by-the-user-screenshot-2/grok-imagine-api-guide.md`
- [x] `rg --files -g '!*DerivedData*'`
- [x] `sed -n '1,240p' AGENTS.md`
- [x] `sed -n '1,260p' Package.swift`
- [x] `sed -n '1,340p' Sources/GrokCLI/Core/TopLevelRouter.swift`
- [x] `sed -n '1,150p' Sources/GrokCLI/Presentation/HelpText.swift`
- [x] `sed -n '1,130p' Sources/GrokCLI/Presentation/JSONOutput.swift`
- [x] `sed -n '120,360p' Sources/GrokCLI/Commands/MessageCommand.swift`
- [x] `sed -n '1,260p' Sources/GrokCLI/Commands/FileCommands.swift`
- [x] `sed -n '1,180p' Sources/GrokCLI/Core/CLIIO.swift`
- [x] `sed -n '1,110p' Sources/GrokCLI/Parsing/OptionParsing.swift`
- [x] `sed -n '1440,1815p' Sources/GrokClient/GrokClient.swift`
- [x] `sed -n '3670,3745p' Sources/GrokClient/GrokClient.swift`
- [x] `sed -n '3370,3845p' Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- [x] `sed -n '1,180p' Tests/README.md`
- [x] Read-only sub-agent investigation: CLI command routing and output conventions.
- [x] Read-only sub-agent investigation: GrokClient auth/networking and Imagine WebSocket requirements.
- [x] Read-only sub-agent investigation: test, docs, build, and install conventions.

### Imagine API Findings

- [x] Text-to-image uses WebSocket `wss://grok.com/ws/imagine/listen`, not the existing streamed REST chat path.
- [x] Required auth uses the same browser cookies as the rest of the client; recommended request headers are `Origin: https://grok.com`, `Cookie`, `Content-Type: application/json`, `Accept: application/json`, and a browser-like `User-Agent`.
- [x] The request envelope is:

```json
{
  "type": "conversation.item.create",
  "timestamp": 1778680000000,
  "item": {
    "type": "message",
    "content": [
      {
        "requestId": "uuid",
        "text": "prompt",
        "type": "input_text",
        "properties": {}
      }
    ]
  }
}
```

- [x] New image generation uses content `type: "input_text"` with properties such as `section_count`, `is_kids_mode`, `enable_nsfw`, `skip_upsampler`, `enable_side_by_side`, `is_initial`, `aspect_ratio`, `enable_pro`, `resolution_name`, and optionally `image_model_name`.
- [x] Completed image frames include fields such as `request_id`, `order`, `type: "image"`, `current_status: "completed"`, `percentage_complete`, `id`, `image_id`, `url`, `prompt`, `full_prompt`, `width`, `height`, `model_name`, `moderated`, and `job_id`.
- [x] Error frames use `type: "error"` with `err_code` and `err_message`; observed codes include `image_query_rejected` and `rate_limit_exceeded`.
- [x] The guide warns these are private app endpoints, so names and payloads can change without notice.

### Client Findings

- [x] `GrokClient` already stores `baseURL`, `rootBaseURL`, `webBaseURL`, `cookies`, `session`, common browser-ish headers, and debug state in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1440).
- [x] `cookieHeader` builds a stable cookie header from stored credentials in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1484). It is private, so the WebSocket implementation should live in `GrokClient` or expose a narrow internal helper.
- [x] `normalizedBaseURLs` derives `webBaseURL` from `GROK_BASE_URL` or `https://grok.com/rest` in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1534). This should be the source for `wss://.../ws/imagine/listen`, with `http` mapped to `ws` for tests.
- [x] `makeRequest` centralizes REST headers, cookies, JSON payloads, request IDs, statsig IDs, and redacted debug cURL in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:1708). Reuse its header/cookie concepts, but do not force WebSocket through REST URL construction.
- [x] Existing streamed REST parsing starts at [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:3678), but Imagine text-to-image frames are WebSocket JSON messages.
- [x] `ConversationResponse` only models text, conversation IDs, web search results, X posts, and final/thinking state in [GrokClient.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokClient.swift:391). Do not try to parse Imagine output through this text-chat model.
- [x] `Package.swift` has no WebSocket dependency and `GrokClient` depends on Foundation only in [Package.swift](/Users/stephenwalker/Code/klu/swift-grok/Package.swift:36). Prefer `URLSessionWebSocketTask` before adding dependencies.

### CLI Findings

- [x] The CLI entrypoint is `try await GrokCLI.main()` in [main.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/main.swift:1).
- [x] Top-level command recognition is hand-written in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:144). A new command must be recognized or `image` will be treated as chat text.
- [x] Leading top-level option normalization supports known flags/value options before the command in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:155).
- [x] Unknown commands become chat, or message when JSON is requested, in [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:267).
- [x] Command dispatch happens in the switch starting at [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:279).
- [x] Human help lists top-level commands, options, scriptable text behavior, and examples in [HelpText.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Presentation/HelpText.swift:31).
- [x] JSON output uses the stable `grok.cli.result.v1` and `grok.cli.event.v1` schemas in [JSONOutput.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Presentation/JSONOutput.swift:12).
- [x] Prompt-source behavior for `message` validates mutual exclusivity and supports inline args, `--prompt-file`, `--stdin`, and implicit piped stdin in [MessageCommand.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/MessageCommand.swift:272).
- [x] Shared stdin and prompt-file helpers already exist in [CLIIO.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/CLIIO.swift:102).
- [x] JSON option parsing helpers support `--json`, `--format json`, and `--format=json` in [OptionParsing.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Parsing/OptionParsing.swift:11).
- [x] `files` is the best local command pattern for a new hand-parsed command: `handleFilesCommand`, a private parsed-command model, clear usage errors, JSON mode, and exit handling in [FileCommands.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/FileCommands.swift:6).

### Test And Verification Findings

- [x] `Tests/README.md` says package tests require no Grok account and use mocks/local servers in [Tests/README.md](/Users/stephenwalker/Code/klu/swift-grok/Tests/README.md:7).
- [x] The standard Swift test commands are documented in [Tests/README.md](/Users/stephenwalker/Code/klu/swift-grok/Tests/README.md:13).
- [x] CLI E2E tests run the built `grok` executable with `GROK_BASE_URL` pointed at a local mock server in [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:3411).
- [x] The local mock server is currently plain HTTP over `NWListener`, records JSON HTTP requests, and dispatches REST paths in [GrokCLIE2ETests.swift](/Users/stephenwalker/Code/klu/swift-grok/Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift:3524). It does not currently implement WebSocket upgrade/frames.
- [x] `Scripts/install_cli.sh` is the canonical install gate after implementation; it builds release product `grok` and installs the CLI in [install_cli.sh](/Users/stephenwalker/Code/klu/swift-grok/Scripts/install_cli.sh:1).
- [x] `Scripts/build.sh` is proxy-oriented, so this CLI-only plan should use explicit Swift build/test commands and `Scripts/install_cli.sh --user`.

## Product Scope

### In Scope

- [ ] Top-level `grok image` command.
- [ ] Top-level `grok images` alias.
- [ ] Text-to-image only through `wss://grok.com/ws/imagine/listen`.
- [ ] Prompt sources: inline args, `--prompt-file <path>`, `--stdin`, implicit piped stdin.
- [ ] Options: `--aspect-ratio`, `--count`, `--quality`, `--resolution`, `--model`, `--kids-mode`, `--nsfw/--no-nsfw`, `--skip-upsampler`, `--output`, `--json`, `--raw`, `--quiet`, `--debug`, `--timeout`.
- [ ] Human, raw quiet, and JSON result output.
- [ ] Optional image download to a local output directory.
- [ ] Tests and docs for the new CLI command and client API.

### Out Of Scope

- [ ] Interactive slash commands such as `/image`.
- [ ] OpenAI-compatible proxy image endpoints such as `/v1/images/generations`.
- [ ] Image editing through `/rest/app-chat/conversations/new`.
- [ ] Video generation/editing.
- [ ] Template pipeline execution.
- [ ] Durable media post creation through `/rest/media/post/create` in the first cut.
- [ ] Adding a top-level `imagine` alias, because it would steal ordinary bare prompts that start with the verb "imagine".

## Proposed User Interface

### Commands

```bash
grok image "a cinematic chrome airship over Bangkok at dusk"
grok images --count 4 --aspect-ratio 16:9 "architectural concept art, museum interior"
grok image --quality pro --resolution 2mp "soft light portrait, 35mm"
grok image --prompt-file prompt.txt --output ./images
cat prompt.txt | grok image --stdin --json
grok image --raw --quiet "single URL per line"
```

### Options

- `--json`, `--format json`: print a `grok.cli.result.v1` success/error envelope.
- `--raw`: print raw URL/path lines instead of labeled human output.
- `--quiet`: suppress progress/status; with `--raw`, stdout contains only generated URL/path lines.
- `--debug`: print sanitized debug details to stderr or normal human output, never cookies.
- `--stdin`: read prompt from stdin.
- `--prompt-file <path>`: read UTF-8 prompt file.
- `--count <n>`: desired number of completed images to collect. Start with allowed range `1...4`, default `2`, and document that Grok may return fewer if moderated or errored.
- `--aspect-ratio <ratio>`: pass documented string values such as `1:1`, `2:3`, `3:2`, `9:16`, `16:9`. Default `2:3` to match the guide.
- `--quality <standard|pro>`: standard maps `enable_pro: false`; pro maps `enable_pro: true` and defaults `skip_upsampler: true` unless explicitly overridden.
- `--resolution <name>`: pass through documented values such as `2mp` for pro/high-resolution paths.
- `--model <name>` / `--image-model <name>`: optional pass-through to `image_model_name`. Prefer `--image-model` in help to avoid confusing text chat `--model`.
- `--kids-mode`: set `is_kids_mode: true` and force `enable_nsfw: false`.
- `--nsfw`, `--no-nsfw`: explicit control for `enable_nsfw`; default `true` unless kids mode is enabled.
- `--skip-upsampler`, `--no-skip-upsampler`: explicit control for `skip_upsampler`.
- `--output <dir>`: download completed image URLs into the directory and print/save local file paths.
- `--timeout <seconds>`: overall generation timeout; default `120`.

### Output Shapes

Human success:

```text
Generated 2 images
Prompt: a cinematic chrome airship over Bangkok at dusk
1. https://...
2. https://...
```

Raw quiet success without `--output`:

```text
https://image-1
https://image-2
```

Raw quiet success with `--output ./images`:

```text
./images/grok-image-20260514-000001-1.jpg
./images/grok-image-20260514-000001-2.jpg
```

JSON success:

```json
{
  "schema": "grok.cli.result.v1",
  "ok": true,
  "command": "image",
  "subcommand": null,
  "category": "image_generation",
  "data": {
    "prompt": "a cinematic chrome airship over Bangkok at dusk",
    "requestId": "uuid",
    "request": {
      "aspectRatio": "2:3",
      "count": 2,
      "enableNsfw": true,
      "enablePro": false,
      "skipUpsampler": false,
      "resolutionName": null,
      "imageModelName": null
    },
    "images": [
      {
        "order": 0,
        "id": "image-or-post-id",
        "imageId": "image-id",
        "url": "https://...",
        "path": null,
        "width": 832,
        "height": 1248,
        "prompt": "original prompt",
        "fullPrompt": "expanded prompt",
        "modelName": "model",
        "moderated": false,
        "jobId": "job-id"
      }
    ]
  },
  "error": null,
  "meta": {
    "format": "json",
    "version": "1",
    "debug": false,
    "warnings": []
  }
}
```

## Architecture

### Client API

Add a new client file, preferably [Sources/GrokClient/GrokImagine.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokClient/GrokImagine.swift), with public models and a small WebSocket implementation.

Suggested public surface:

```swift
public struct GrokImagineOptions: Sendable, Codable {
    public var aspectRatio: String
    public var count: Int
    public var enableNsfw: Bool
    public var kidsMode: Bool
    public var skipUpsampler: Bool
    public var enablePro: Bool
    public var resolutionName: String?
    public var imageModelName: String?
    public var timeoutSeconds: TimeInterval
}

public struct GrokImagineImage: Sendable, Codable {
    public let requestId: String
    public let order: Int?
    public let id: String?
    public let imageId: String?
    public let url: String
    public let prompt: String?
    public let fullPrompt: String?
    public let width: Int?
    public let height: Int?
    public let modelName: String?
    public let moderated: Bool?
    public let jobId: String?
    public let rawJSON: AnyCodable
}

public enum GrokImagineEvent: Sendable {
    case progress(GrokImagineFrame)
    case image(GrokImagineImage)
}

public func streamImagineImages(
    prompt: String,
    options: GrokImagineOptions = .default
) -> AsyncThrowingStream<GrokImagineEvent, Error>

public func generateImages(
    prompt: String,
    options: GrokImagineOptions = .default
) async throws -> [GrokImagineImage]
```

Implementation notes:

- Build the WebSocket URL from `webBaseURL`: `https` to `wss`, `http` to `ws`, then append `/ws/imagine/listen`.
- Build a `URLRequest` with `Origin`, `Cookie`, `Content-Type`, `Accept`, and `User-Agent`.
- Use `URLSessionWebSocketTask` from Foundation unless compile testing proves a package dependency is necessary.
- Send the documented `conversation.item.create` envelope immediately after opening.
- Generate one `requestId` per CLI invocation and collect frames for that ID.
- Treat `type: "error"` frames as `GrokError.apiError` with a friendly message that includes `err_code` and `err_message`.
- Collect completed image frames until `options.count` images are complete or the stream ends/errors/times out.
- Deduplicate by `order` and/or `image_id` so repeated progress/completed frames do not duplicate output.
- Preserve each completed frame's raw JSON for future endpoint drift debugging.
- Cancel the WebSocket task when the stream terminates or timeout fires.

### Testable WebSocket Transport

`URLSessionWebSocketTask` is hard to mock with the current `MockURLProtocol` strategy. Add a narrow internal transport abstraction so client tests do not require a real Grok session:

```swift
protocol GrokImagineWebSocketTransport: Sendable {
    func connect(request: URLRequest) async throws -> GrokImagineSocket
}

protocol GrokImagineSocket: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func cancel()
}
```

Use a production `URLSessionImagineWebSocketTransport` and a scripted fake transport in `GrokClientTests`. Keep the transport internal if possible; expose only a test initializer under `@testable` if needed.

### CLI Command

Add [Sources/GrokCLI/Commands/ImageCommand.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Commands/ImageCommand.swift) following the `files` command style.

Suggested shape:

- `handleImageCommand(args:exitOnError:)`.
- Private `ParsedImageCommand`.
- Private `ImageCommandOptions`.
- `parseImageCommand(args:)`.
- `resolveImagePrompt(...)`.
- `downloadGeneratedImages(...)`.
- `imageResultJSON(...)`.
- `reportImageUsageError(...)`.

Prompt-source rules:

- Inline prompt args, `--prompt-file`, and `--stdin` are mutually exclusive.
- If no inline args or prompt file are supplied and stdin is piped, read stdin automatically.
- Empty prompt after trimming is a usage error.
- `--prompt-file` read errors are usage errors with exit code `2`.

Output rules:

- JSON mode reserves stdout for the JSON envelope.
- Human progress and debug output must be suppressed in JSON mode.
- `--raw --quiet` writes only URL/path lines to stdout.
- Errors in quiet mode go to stderr unless JSON mode is active.
- Download progress, if any, must not pollute stdout in raw quiet mode.

### Routing And Help

Update:

- [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:144): add `"image"` and `"images"` to `recognizedTopLevelCommands`.
- [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:190): add reorderable flags `--stdin`, `--kids-mode`, `--nsfw`, `--no-nsfw`, `--skip-upsampler`, and `--no-skip-upsampler`; add value options `--aspect-ratio`, `--count`, `--quality`, `--resolution`, `--image-model`, `--output`, and `--timeout`.
- [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:225): add inline variants for the value options.
- [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:279): dispatch `"image"` and `"images"` to `handleImageCommand`.
- [TopLevelRouter.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Core/TopLevelRouter.swift:103): add `printImageUsage()`.
- [HelpText.swift](/Users/stephenwalker/Code/klu/swift-grok/Sources/GrokCLI/Presentation/HelpText.swift:31): list the command, scriptable examples, and basic option descriptions.
- [README.md](/Users/stephenwalker/Code/klu/swift-grok/README.md): add an "Image Generation" section near "Audio And Transcription".

## Parallel Workstreams

### Workstream 1: GrokClient Imagine Models And Transport

Ownership: `Sources/GrokClient/GrokImagine.swift`, any minimal additions to `Sources/GrokClient/GrokClient.swift`, and client test fakes in `Tests/GrokClientTests/GrokClientTests.swift`.

- [ ] Add `GrokImagineOptions`, `GrokImagineImage`, `GrokImagineFrame`, and `GrokImagineEvent`.
- [ ] Add a WebSocket URL builder that derives `wss/ws` URL from `webBaseURL`.
- [ ] Add an internal WebSocket transport protocol and production `URLSessionWebSocketTask` implementation.
- [ ] Add a test-only/scripted transport path without exposing broad public API.
- [ ] Build the documented `conversation.item.create` envelope with `input_text`.
- [ ] Map CLI/client options to Imagine properties.
- [ ] Parse progress, completed image, moderated, and error frames.
- [ ] Implement timeout and cancellation.
- [ ] Ensure debug output never logs raw cookies or full WebSocket headers.

### Workstream 2: CLI Command Parsing And Output

Ownership: `Sources/GrokCLI/Commands/ImageCommand.swift`, plus small helpers only if they are clearly shared with existing commands.

- [ ] Implement `handleImageCommand(args:exitOnError:)` following the `files` command style.
- [ ] Parse `--json`, `--format json`, `--raw`, `--quiet`, and `--debug`.
- [ ] Parse prompt sources and enforce mutual exclusivity.
- [ ] Parse image options and validate values/ranges.
- [ ] Resolve prompt from inline args, prompt file, explicit stdin, or implicit piped stdin.
- [ ] Call `GrokCLIApp.shared.initializeClient()` and `client.generateImages(...)`.
- [ ] Print human output with concise labels and result rows.
- [ ] Print raw quiet URL/path lines only.
- [ ] Print JSON result and JSON error envelopes with command `"image"` and category `"image_generation"`.
- [ ] Route quiet non-JSON errors to stderr.

### Workstream 3: Output Downloads

Ownership: image download helper in `ImageCommand.swift` or a narrow new CLI helper file if it becomes large.

- [ ] Implement `--output <dir>` directory creation.
- [ ] Download each generated image URL with cookies only if needed; otherwise use plain URL fetch first and fall back to authenticated fetch if Grok rejects it.
- [ ] Infer file extension from response `Content-Type` or URL path; default to `.jpg` when unknown.
- [ ] Use deterministic filenames such as `grok-image-YYYYMMDD-HHMMSS-<order>.<ext>`.
- [ ] Avoid overwriting existing files; add a numeric suffix if needed.
- [ ] Surface download failures as command failures unless a future `--best-effort-download` option is intentionally added.
- [ ] Include local `path` in JSON image objects when files are written.

### Workstream 4: Router, Help, And Documentation

Ownership: `TopLevelRouter.swift`, `HelpText.swift`, `README.md`.

- [ ] Add command recognition and dispatch for `image` and `images`.
- [ ] Add reorderable top-level image flags/value options.
- [ ] Add `printImageUsage()` with examples and stdout contracts.
- [ ] Update top-level human help command list and examples.
- [ ] Confirm JSON help includes `image` and `images` through `recognizedTopLevelCommands`.
- [ ] Add README docs for image generation, options, prompt sources, output modes, examples, and private endpoint caveat.
- [ ] Do not update `PROXY_README.md` unless proxy image endpoints are explicitly added in a later request.

### Workstream 5: Client Tests

Ownership: `Tests/GrokClientTests/GrokClientTests.swift` and any local test support in that file.

- [ ] Test WebSocket URL derivation for `https://grok.com/rest`, `/rest`, `/rest/app-chat`, and local `http://127.0.0.1:<port>`.
- [ ] Test request headers include `Origin`, `Cookie`, `Accept`, `Content-Type`, and `User-Agent`.
- [ ] Test the sent envelope uses `conversation.item.create`, `input_text`, UUID `requestId`, prompt text, and mapped properties.
- [ ] Test completed frame parsing with all common fields.
- [ ] Test progress frames do not emit duplicate completed images.
- [ ] Test error frames map to friendly `GrokError.apiError`.
- [ ] Test timeout/cancellation closes the fake socket.
- [ ] Test options validation defaults and pro/quality mapping.

### Workstream 6: CLI E2E Tests

Ownership: `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`.

- [ ] Prefer testing CLI with an injectable fake Imagine transport environment variable if implementing a true local WebSocket server would be too much for E2E.
- [ ] Alternatively extend `MockGrokServer` with a minimal WebSocket upgrade and text-frame support for `/ws/imagine/listen`.
- [ ] Test `grok image --help` prints usage and does not call the network.
- [ ] Test inline prompt sends an Imagine request and prints generated URLs.
- [ ] Test `--json` output parses as one result envelope with no human banners.
- [ ] Test `--raw --quiet` output contains only URL/path lines.
- [ ] Test `--prompt-file` and implicit stdin prompt sources.
- [ ] Test mutual-exclusive prompt source errors exit `2` and make no network request.
- [ ] Test `--output` writes expected files and prints paths.
- [ ] Test WebSocket error frame exits `1` and prints a friendly message or JSON error.

## Dependencies Between Workstreams

- Workstream 2 depends on Workstream 1's public client API shape.
- Workstream 3 depends on Workstream 2's parsed options and Workstream 1's image result model.
- Workstream 4 can start once command names and option names are stable.
- Workstream 5 can run in parallel with Workstream 1 after the transport protocol is sketched.
- Workstream 6 can start after Workstream 2 has parsing/output shape and after Workstream 1 exposes a fakeable path.
- Build/install verification waits for all implementation and tests.

## Concrete Implementation Steps

1. Create `Sources/GrokClient/GrokImagine.swift` with models, option defaults, and frame parsing helpers.
2. Add a small internal transport abstraction plus `URLSessionWebSocketTask` production transport.
3. Add `GrokClient.streamImagineImages(prompt:options:)` and `GrokClient.generateImages(prompt:options:)`.
4. Implement URL derivation from `webBaseURL` and test it before wiring CLI.
5. Implement the `conversation.item.create` envelope builder and tests.
6. Implement frame receive loop, completion collection, dedupe, timeout, error mapping, and cancellation.
7. Create `Sources/GrokCLI/Commands/ImageCommand.swift`.
8. Implement parsing, prompt-source resolution, option validation, and usage output.
9. Implement human, raw quiet, and JSON output.
10. Implement optional `--output` downloads.
11. Wire command recognition, leading option normalization, dispatch, and help.
12. Update README.
13. Add client unit tests.
14. Add CLI E2E tests with a fake transport or minimal WebSocket test server.
15. Run verification gates only after implementation is explicitly approved.

## Test And Verification Gates

Do not run these for the current plan-only request. Run them after implementation is approved and complete.

- [ ] `swift build`
- [ ] `swift test --filter GrokClientTests`
- [ ] `swift test --filter GrokCLIE2ETests`
- [ ] `swift test`
- [ ] `Scripts/install_cli.sh --user`
- [ ] Installed PATH smoke: `grok image --help`
- [ ] Installed PATH smoke: `grok image --json "test prompt"` with a fake/mock path if available, or a live credentialed run only when the user explicitly approves the live API call.
- [ ] Installed PATH smoke: `printf 'test prompt' | grok image --stdin --raw --quiet` with the same fake/mock/live constraint.

## Risks And Edge Cases

- Private endpoint drift: Grok can change WebSocket paths, frame fields, or property names without notice.
- Account gating: plan/subscription restrictions may appear as WebSocket error frames rather than HTTP status codes.
- Rate limits: can arrive as `rate_limit_exceeded` frames; map them into existing friendly rate-limit language where possible.
- Moderation: `moderated: true` may mean an image exists but should be reported as blocked or omitted based on product decision. First cut should include it in JSON with `moderated: true` and mark it in human output.
- Fewer results than requested: the service may return fewer completed images than `--count`; JSON should report actual images and warnings when partial.
- Duplicate frames: progress/completed frames can repeat; dedupe by `order`, `image_id`, or URL.
- Long-running jobs: use timeout and cancellation to avoid hanging non-interactive scripts.
- Cookie safety: never print cookies in debug, JSON, errors, saved filenames, or docs examples.
- Output download failures: failed downloads after successful generation need clear errors and should not silently produce partial success in the first cut.
- Filename safety: sanitize prompt-derived names if prompt snippets are ever used; recommended first cut uses timestamp/order only.
- Platform support: `URLSessionWebSocketTask` should be verified across supported Apple platforms; if Linux compile breaks, add conditional fallback or a lightweight dependency only after proving it is necessary.
- Top-level alias risk: adding `imagine` would break bare text prompts that begin with "imagine", so avoid that alias.

## Rollback Notes

- Revert router additions in `TopLevelRouter.swift` to remove command recognition and dispatch.
- Delete `ImageCommand.swift` to remove the CLI surface.
- Delete `GrokImagine.swift` and any narrow `GrokClient` initializer/helper additions if no other code depends on them.
- Remove README/help additions.
- Remove image-specific tests and any WebSocket mock support.
- No migration or persisted user data is introduced by this feature.
- Generated image output files are user-created artifacts; rollback should not delete files already written to user-specified output directories.

## Final Completion Checklist

- [ ] User requirement: "add image gen to the cli non interactive" maps to `grok image`/`grok images` text-to-image command implemented and documented.
- [ ] User requirement: use the referenced guide maps to WebSocket `wss://grok.com/ws/imagine/listen` request/response implementation based on the guide.
- [ ] Non-interactive requirement maps to no interactive slash command work in this plan.
- [ ] Scriptability requirement maps to `--json`, `--raw --quiet`, stdin, prompt file, exit-code, and stdout/stderr tests.
- [ ] Safety requirement maps to cookie redaction and no raw cookie logging tests.
- [ ] Test evidence maps to passing `GrokClientTests`, `GrokCLIE2ETests`, and full `swift test`.
- [ ] Install requirement maps to `Scripts/install_cli.sh --user` and installed CLI PATH smoke checks after implementation.
- [ ] Scope control maps to no proxy, image-edit, video, or template pipeline changes.
