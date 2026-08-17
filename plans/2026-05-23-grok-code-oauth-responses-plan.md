# Grok Code OAuth Responses Harness Plan

Date: 2026-05-23
Status: Plan spec only, not executed

## Objective

Revive the Grok Code wing as a local coding harness powered by xAI OAuth and the Responses API. The implementation should use Grok Build 0.1 model behavior and GrokBuild-compatible tool shapes from `tmp_grokbuild.md`, while preserving the existing `grok chat`, `grok message`, and `proxy` behavior.

The old Grok Code attempt should not be restored as-is. It was disabled because Grok web tool calls run server-side. The new design should use local Responses API function calling: the model asks for a tool, the Swift CLI executes that tool locally, then the CLI submits `function_call_output` back to the same response chain.

## Success Criteria

- [ ] `grok code [options] [task...]` is available again and uses xAI OAuth mode only.
- [ ] `grok code` defaults to a Grok Build model when one is listed by `/v1/models`, with an explicit `--model` override.
- [ ] Code mode sends tool schemas through the OAuth Responses API instead of scraping JSON from assistant prose as the primary tool-call mechanism.
- [ ] Tool execution happens only on the local machine through Swift-owned tool implementations.
- [ ] The first shipped tool surface follows `tmp_grokbuild.md`: `run_terminal_cmd`, `read_file`, `grep`, `list_dir`, and `search_replace`.
- [ ] `search_replace` requires a prior local `read_file` result for the same file revision and rejects stale, no-match, and ambiguous multi-match edits.
- [ ] JSON and streaming JSON modes are machine-clean: no human HUD lines on stdout.
- [ ] Existing `grok message`, `grok chat`, OAuth media/file/STT flows, web-cookie flows, and `proxy` behavior do not regress.
- [ ] After implementation, run the required build and install gate so the user can test the finished `grok` from PATH.

## Non-Goals

- [ ] Do not revive account-level Grok web `/user-settings` mutation as the default agent-role mechanism.
- [ ] Do not route code mode through `GrokProxy`.
- [ ] Do not expand `/v1/chat/completions` into a local coding-agent protocol in this pass.
- [ ] Do not ship web search, MCP, memory, LSP, or recursive subagents in the first code-mode slice.
- [ ] Do not run build, tests, or install while producing this plan; those gates belong to implementation.

## Discovery Completed

- [x] Inspected current CodeMode files under `Sources/GrokCLI/CodeMode/**`.
- [x] Inspected disabled command routing in `Sources/GrokCLI/Core/TopLevelRouter.swift`.
- [x] Inspected OAuth auth and Responses transport in `Sources/GrokCLI/Runtime/GrokCLIApp+XAIOAuth.swift`, `XAIOAuthClient.swift`, and `XAIResponsesStreamParser.swift`.
- [x] Inspected proxy boundaries under `Sources/GrokProxy/**`.
- [x] Inspected the existing stale plan at `plans/2026-05-14-grok-code-harness-architecture-plan.md`.
- [x] Inspected `tmp_grokbuild.md` for prompt assembly, tool names, permission modes, and headless output options.
- [x] Used four focused subagents for CodeMode architecture, OAuth transport, GrokBuild tool shape, and proxy/testing implications.

Relevant discovery commands:

```sh
git status --short
rg --files -g 'AGENTS.md' -g 'tmp_grokbuild.md' -g 'Package.swift' -g '*.swift' -g '*.md' -g '*.sh'
rg -n "Grok Code is disabled|function_call|tool_call|local_action|XAIOAuth|responses|oauth" Sources Tests README.md PROXY_README.md plans tmp_grokbuild.md
nl -ba tmp_grokbuild.md | sed -n '620,980p'
nl -ba tmp_grokbuild.md | sed -n '1460,1535p'
nl -ba Sources/GrokCLI/Runtime/XAIOAuthClient.swift | sed -n '296,626p'
nl -ba Sources/GrokCLI/Runtime/XAIResponsesStreamParser.swift | sed -n '1,212p'
nl -ba Sources/GrokCLI/Core/TopLevelRouter.swift | sed -n '146,300p'
nl -ba Sources/GrokProxy/Controllers/ChatCompletionsController.swift | sed -n '1,260p'
```

Current worktree note:

- [x] `git status --short` showed existing unrelated local changes before this plan was written:
  - `M Sources/GrokClient/GrokClientTransport.swift`
  - `M Tests/GrokClientTests/GrokClientRequestBuildingTests.swift`
  - `?? tmp_grokbuild.md`

## Current-State Findings

### Disabled CodeMode

- [x] `Sources/GrokCLI/Commands/CodeCommand.swift` is entirely commented out and starts with: `Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.`
- [x] `Sources/GrokCLI/CodeMode/**` contains useful dormant types, but those files are also commented out with the same disabled banner.
- [x] `Sources/GrokCLI/Core/TopLevelRouter.swift` keeps `code` in `disabledTopLevelCommands` and prints the disabled message instead of dispatching to `handleCodeCommand`.
- [x] `Sources/GrokCLI/Presentation/HelpText.swift` and `README.md` do not expose CodeMode as a live supported surface.

### Dormant Pieces Worth Reusing

- [x] Command parsing shape in `CodeCommand.swift` covers `grok code`, `restore`, `--prompt-file`, `--permission-mode`, `--max-turns`, `--agent-timeout-seconds`, JSON output, private mode, and dry-run settings.
- [x] `GrokCodeSession.swift` models session state, transcript path, task queue, turn loop, local tool execution, and context projection.
- [x] `GrokCodePermissionController.swift` has a usable policy split for read-only, plan, accept-edits, default, and bypass-style modes.
- [x] `GrokCodeTranscriptStore.swift` and `GrokCodeContextProjector.swift` are a good base for append-only session state and bounded model context.
- [x] `BuiltinTools.swift` contains local tool ideas, but the tool names and semantics should be realigned to GrokBuild.

### OAuth Transport

- [x] `GrokAuthMode.swift` separates web-cookie auth from `xai-oauth`.
- [x] `ConfigManager.swift` stores OAuth credentials separately as `xai-oauth.json`.
- [x] `GrokCLIApp+XAIOAuth.swift` handles credential refresh, `/v1/models`, `sendXAIOAuthMessage`, `streamXAIOAuthMessage`, OAuth upload/list/delete files, and STT.
- [x] `XAIOAuthClient.swift` calls `/v1/responses` with `model`, `input`, `store`, optional `previous_response_id`, optional `max_output_tokens`, and optional `stream`.
- [x] `XAIResponsesStreamParser.swift` parses text and reasoning deltas but does not parse function-call output items or function-call deltas.

### GrokBuild Contract From `tmp_grokbuild.md`

- [x] Prompt assembly should be layered: base prompt, tool fragments, project instructions, user rules, system override, agent profile, skills/agents/personas, memory, and runtime user info.
- [x] Initial tool names should match GrokBuild: `run_terminal_cmd`, `read_file`, `search_replace`, `grep`, and `list_dir`.
- [x] `search_replace` must require a prior file read and reject stale file revisions, no-match replacements, repeated matches unless `replace_all` is true, and unchanged replacements.
- [x] Permission rule prefixes to preserve for future compatibility: `Bash`, `Edit`, `Write`, `Read`, `Grep`, `WebFetch`, and `MCPTool`.
- [x] Headless output modes should map to plain, JSON, and streaming JSON.

### Proxy Boundary

- [x] `Package.swift` defines `grok` and `proxy` as separate executables.
- [x] `ChatCompletionsController.swift` is a stateless OpenAI-compatible chat endpoint and collapses the input to the last user message.
- [x] `OpenAI.swift` accepts only `system`, `user`, and `assistant` chat roles, not tool roles.
- [x] The proxy is the wrong home for local coding-agent transcript state, permission checks, local file edits, or subagent orchestration.

## Target Architecture

### High-Level Flow

```text
grok code task
  -> parse code invocation
  -> require or refresh xAI OAuth credential
  -> resolve model, preferring grok-build-0.1 or the first grok-build model
  -> create code session and transcript
  -> assemble prompt + project instructions + tool registry
  -> POST /v1/responses with tools
  -> parse response output
      -> assistant text: render/store
      -> function_call: execute local tool
  -> POST /v1/responses with previous_response_id + function_call_output
  -> repeat until final answer, max turns, user interrupt, or error
```

### New And Modified Files

Expected new files:

- [ ] `Sources/GrokCLI/CodeMode/GrokCodeInvocation.swift`
- [ ] `Sources/GrokCLI/CodeMode/GrokCodeSession.swift`
- [ ] `Sources/GrokCLI/CodeMode/GrokCodeSessionState.swift`
- [ ] `Sources/GrokCLI/CodeMode/GrokCodePromptAssembler.swift`
- [ ] `Sources/GrokCLI/CodeMode/GrokCodeResponsesAgent.swift`
- [ ] `Sources/GrokCLI/CodeMode/GrokCodeEvents.swift`
- [ ] `Sources/GrokCLI/CodeMode/GrokCodeToolSchemas.swift`
- [ ] `Sources/GrokCLI/CodeMode/Tools/GrokCodeTool.swift`
- [ ] `Sources/GrokCLI/CodeMode/Tools/GrokCodeToolRegistry.swift`
- [ ] `Sources/GrokCLI/CodeMode/Tools/GrokCodeToolExecutor.swift`
- [ ] `Sources/GrokCLI/CodeMode/Tools/GrokCodePermissionController.swift`
- [ ] `Sources/GrokCLI/CodeMode/Tools/GrokBuildBuiltinTools.swift`
- [ ] `Sources/GrokCLI/CodeMode/Transcript/GrokCodeTranscriptStore.swift`
- [ ] `Sources/GrokCLI/CodeMode/Transcript/GrokCodeMessageEnvelope.swift`
- [ ] `Sources/GrokCLI/Runtime/XAIOAuthResponsesToolModels.swift`

Expected modified files:

- [ ] `Sources/GrokCLI/Commands/CodeCommand.swift`
- [ ] `Sources/GrokCLI/Core/TopLevelRouter.swift`
- [ ] `Sources/GrokCLI/Presentation/HelpText.swift`
- [ ] `Sources/GrokCLI/Presentation/JSONOutput.swift`
- [ ] `Sources/GrokCLI/Runtime/XAIOAuthClient.swift`
- [ ] `Sources/GrokCLI/Runtime/XAIResponsesStreamParser.swift`
- [ ] `Sources/GrokCLI/Runtime/GrokCLIApp+XAIOAuth.swift`
- [ ] `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- [ ] `Tests/GrokClientTests` or new CLI-focused tests for OAuth response body construction
- [ ] `README.md` only after the feature is enabled enough to document honestly

## Workstreams

### Workstream 1: OAuth Responses Function Calling

Owner boundary:

- Own `Sources/GrokCLI/Runtime/XAIOAuthClient.swift`.
- Own `Sources/GrokCLI/Runtime/XAIResponsesStreamParser.swift`.
- Own new OAuth Responses model file(s).
- Do not touch local filesystem tools except for shared type names required by schemas.

Tasks:

- [ ] Add typed structures for Responses input items, output items, function calls, and function-call outputs.
- [ ] Extend `XAIOAuthClient.responseRequestBody(...)` or replace it with a typed body builder that supports:
  - [ ] `tools`
  - [ ] `tool_choice`
  - [ ] `parallel_tool_calls`
  - [ ] `previous_response_id`
  - [ ] `input` containing function-call outputs
  - [ ] `stream`
- [ ] Keep existing `grok message` request bodies byte-for-byte equivalent where possible when no tools are present.
- [ ] Decode non-streaming Responses output into:
  - [ ] final assistant text
  - [ ] one or more function-call requests
  - [ ] response ID
  - [ ] refusal/error metadata if present
- [ ] Extend streaming parsing to detect function-call events if xAI emits them in streaming mode.
- [ ] Add defensive parsing for both final full-response `output[]` function calls and streaming deltas.
- [ ] Add a helper such as `createResponseWithTools(...)`.
- [ ] Add a helper such as `continueResponseWithToolOutputs(...)`.
- [ ] Ensure OAuth refresh and endpoint validation behavior remain unchanged.

Dependencies:

- Can start immediately.
- Blocks Workstream 4.

### Workstream 2: Code Command And Session Shell

Owner boundary:

- Own `Sources/GrokCLI/Commands/CodeCommand.swift`.
- Own `Sources/GrokCLI/Core/TopLevelRouter.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeInvocation.swift`.
- Own session/event skeleton files, but not tool implementations.

Tasks:

- [ ] Uncomment or rewrite `CodeCommand.swift` as active code rather than preserving the old commented block.
- [ ] Register `code` in `recognizedTopLevelCommands`.
- [ ] Remove `code` from `disabledTopLevelCommands` once the implementation is behind an explicit experimental or OAuth-only gate.
- [ ] Parse:
  - [ ] `grok code [task...]`
  - [ ] `grok code --prompt-file <path>`
  - [ ] `grok code --json`
  - [ ] `grok code --format plain|json|streaming-json`
  - [ ] `grok code --model <model>`
  - [ ] `grok code --permission-mode <mode>`
  - [ ] `grok code --max-turns <n>`
  - [ ] `grok code --tools <csv>`
  - [ ] `grok code --disallowed-tools <csv>`
  - [ ] `grok code --rules <text|@file>`
  - [ ] `grok code --cwd <path>`
- [ ] Require OAuth mode or a saved OAuth credential. If not available, fail with a direct `grok auth oauth` instruction.
- [ ] Resolve default model by preferring:
  - [ ] exact `grok-build-0.1` if available
  - [ ] first returned model containing `grok-build`
  - [ ] explicit fallback only if the user supplied `--model`
- [ ] Add a session state object with session ID, cwd, model, auth mode, permission mode, active tools, transcript path, turn count, final answer, and failure state.
- [ ] Preserve existing JSON purity rules from message/chat commands.

Dependencies:

- Can start after Workstream 1 defines enough response types to compile, or with protocol stubs.

### Workstream 3: GrokBuild-Compatible Local Tools

Owner boundary:

- Own `Sources/GrokCLI/CodeMode/Tools/**`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeToolSchemas.swift`.
- Do not modify OAuth request/response transport except through shared schema types.

Initial tools:

- [ ] `read_file`
- [ ] `grep`
- [ ] `list_dir`
- [ ] `run_terminal_cmd`
- [ ] `search_replace`

Tasks:

- [ ] Define `GrokCodeTool` protocol with:
  - [ ] public tool name
  - [ ] JSON schema builder
  - [ ] required permission category
  - [ ] input decoder
  - [ ] validator
  - [ ] async executor
  - [ ] output cap behavior
- [ ] Define `GrokCodeToolRegistry` with tool allow/deny filtering.
- [ ] Define tool aliases for internal compatibility:
  - [ ] `bash` -> `run_terminal_cmd`
  - [ ] `grep_search` -> `grep`
  - [ ] old `shell` -> `run_terminal_cmd` only inside migration tests, not advertised
  - [ ] old `list_files` -> `list_dir` only inside migration tests, not advertised
- [ ] Implement `read_file` with GrokBuild field names:
  - [ ] `file_path`
  - [ ] `offset`
  - [ ] `limit`
  - [ ] `page_range` accepted but returns unsupported for PDFs in v0.1 unless implemented
  - [ ] `pdf_format` accepted but returns unsupported for PDFs in v0.1 unless implemented
- [ ] Make `read_file` line-oriented and include line numbers in output.
- [ ] Track a read token per file: path, normalized absolute path, size, mtime, and content hash.
- [ ] Implement `grep` by invoking `rg` when available and falling back to a Swift scanner only if needed.
- [ ] Implement `list_dir` with stable sorting, hidden-file behavior, and output limits.
- [ ] Implement `run_terminal_cmd` with:
  - [ ] `command`
  - [ ] `timeout_ms`
  - [ ] `explanation`
  - [ ] `is_background`
- [ ] Keep background command support out of v0.1 unless it can be made deterministic; return a clear unsupported result if deferred.
- [ ] Implement `search_replace` with:
  - [ ] `file_path`
  - [ ] `old_string`
  - [ ] `new_string`
  - [ ] `replace_all`
- [ ] Require prior `read_file` before `search_replace`.
- [ ] Reject `search_replace` if the file changed since the prior `read_file`.
- [ ] Reject no-match, multiple-match without `replace_all`, and identical old/new strings.
- [ ] Keep writes inside the selected workspace/cwd unless an explicit future flag allows absolute paths.

Dependencies:

- Can run in parallel with Workstreams 1 and 2.
- Blocks Workstream 4's live loop.

### Workstream 4: Local Tool Loop And Transcript

Owner boundary:

- Own `Sources/GrokCLI/CodeMode/GrokCodeSession.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeResponsesAgent.swift`.
- Own `Sources/GrokCLI/CodeMode/Transcript/**`.
- Coordinate with Workstreams 1 and 3 for transport/tool interfaces.

Tasks:

- [ ] Create an append-only transcript JSONL store.
- [ ] Store user prompt, assembled instructions checksum, model output, function calls, local tool results, errors, and final answer.
- [ ] Add a bounded context projector for follow-up turns.
- [ ] Implement the non-streaming loop first:
  - [ ] send initial response with tool schemas
  - [ ] collect function calls
  - [ ] execute allowed local tools
  - [ ] submit tool results with `previous_response_id`
  - [ ] repeat until no function calls remain
- [ ] Enforce one local result per function call ID.
- [ ] Preserve tool result ordering unless the model/API explicitly requests parallel execution.
- [ ] Default to serial tool execution for v0.1.
- [ ] Add max-turn and max-tool-call limits.
- [ ] Add interrupt handling that stops local command execution and records an interrupted state.
- [ ] Keep model final claims out of `finalAnswer` when there are pending unexecuted tool calls.
- [ ] Add transcript redaction for tokens, cookies, Authorization headers, and local credential paths where appropriate.

Dependencies:

- Requires usable pieces from Workstreams 1 and 3.

### Workstream 5: Prompt Assembly And UX Output

Owner boundary:

- Own `Sources/GrokCLI/CodeMode/GrokCodePromptAssembler.swift`.
- Own CodeMode rendering in `Sources/GrokCLI/Presentation/**` or a new `GrokCodeRenderer`.
- Own JSON result shape additions in `JSONOutput.swift`.

Tasks:

- [ ] Assemble prompt layers in this order:
  - [ ] fixed Grok Code base prompt
  - [ ] tool-use instructions generated from active tool registry
  - [ ] repo/project instructions from `AGENTS.md` files from repo root to cwd
  - [ ] user `--rules`, including `@file` support
  - [ ] runtime user info: date, cwd, workspace root, git branch, permission mode, tool limits
  - [ ] user task
- [ ] Avoid copying the full `tmp_grokbuild.md` prompt text; use it as shape guidance only.
- [ ] Do not include Codex references in user-facing command names, git attributes, or PR metadata.
- [ ] Plain output:
  - [ ] concise session header
  - [ ] tool call start/result lines
  - [ ] final assistant answer
  - [ ] error with recovery details
- [ ] JSON output:
  - [ ] one result envelope
  - [ ] session ID
  - [ ] model
  - [ ] final answer
  - [ ] transcript path
  - [ ] tool calls/results summary
  - [ ] errors
- [ ] Streaming JSON output:
  - [ ] NDJSON event per line
  - [ ] monotonic sequence number
  - [ ] event types: `session_started`, `assistant_delta`, `tool_call`, `tool_result`, `warning`, `error`, `completed`
  - [ ] no human HUD lines on stdout
- [ ] Update help text after the implementation is functional enough to test.
- [ ] Update README only after the feature should be discoverable.

Dependencies:

- Can begin with Workstream 2 and finish after Workstream 4 event types are stable.

### Workstream 6: Tests, Docs, And Install Gate

Owner boundary:

- Own new and modified tests under `Tests/**`.
- Own docs updates once implementation behavior is real.
- Own final verification and install.

Tasks:

- [ ] Add pure unit tests for command parsing.
- [ ] Add pure unit tests for prompt assembly order.
- [ ] Add pure unit tests for permission decisions.
- [ ] Add pure unit tests for each built-in tool.
- [ ] Add `search_replace` tests for:
  - [ ] no prior read
  - [ ] stale file
  - [ ] no match
  - [ ] multiple match without `replace_all`
  - [ ] successful single replace
  - [ ] successful replace all
- [ ] Add OAuth mock-server tests for:
  - [ ] initial `/v1/responses` body includes `tools`
  - [ ] model function-call output is decoded
  - [ ] function-call output is sent back with `previous_response_id`
  - [ ] final answer is emitted after tool loop completes
  - [ ] JSON mode has no human banners
  - [ ] streaming JSON mode emits ordered NDJSON events
- [ ] Add regression tests proving `grok message` OAuth request body does not include tools unless code mode is active.
- [ ] Add proxy no-regression tests or run existing proxy tests.
- [ ] Update `README.md` and `xai_oauth.md` with honest support matrix and known limitations.
- [ ] After implementation, run build and install so the user can test from PATH.

Dependencies:

- Tests can be added incrementally with each workstream.
- Final install runs only after implementation is complete.

## Implementation Sequence

### Phase 0: Confirm Function-Calling Wire Shape

- [ ] Verify the exact xAI Responses function-call request and response shapes from official docs or live mocked captures.
- [ ] Record accepted event names for streaming function calls.
- [ ] Add fixtures for at least one non-streaming function-call response and one final response.
- [ ] Decide whether v0.1 supports streaming function-call execution or falls back to non-streaming for tool loops.

Exit gate:

- [ ] A mocked OAuth Responses function-call fixture can be decoded without touching the filesystem.

### Phase 1: Transport And Model Types

- [ ] Add typed request/response models for tool-enabled Responses calls.
- [ ] Add body construction for tool-enabled calls.
- [ ] Add continuation call with function-call outputs.
- [ ] Add tests for request bodies and decoded outputs.
- [ ] Preserve existing `grok message` and media-generation behavior.

Exit gate:

- [ ] Mock server sees the expected `/v1/responses` body for a tool-enabled request.
- [ ] Existing OAuth message tests still pass in implementation verification.

### Phase 2: Tool Registry And Safe Local Tools

- [ ] Add tool protocol, registry, schema builder, and executor.
- [ ] Implement `read_file`, `grep`, `list_dir`, `run_terminal_cmd`, and `search_replace`.
- [ ] Add permission controller compatibility with GrokBuild mode names:
  - [ ] `default`
  - [ ] `acceptEdits`
  - [ ] `auto`
  - [ ] `dontAsk`
  - [ ] `bypassPermissions`
  - [ ] `plan`
- [ ] Map old internal modes only where needed for migration tests.

Exit gate:

- [ ] Tool unit tests pass, including stale edit protection.

### Phase 3: Code Session Loop

- [ ] Activate `grok code` command behind OAuth-only guard.
- [ ] Implement non-streaming session loop.
- [ ] Record transcript JSONL.
- [ ] Render plain and JSON final outputs.
- [ ] Add max-turn and max-tool-call guards.
- [ ] Add clean user-facing errors for missing OAuth credentials, no Grok Build model, unsupported tools, permission denial, and tool execution failure.

Exit gate:

- [ ] Mocked `grok code --json "read package"` can execute a `read_file` function call and return a final JSON result.

### Phase 4: Output Polish And Streaming JSON

- [ ] Add plain progress output.
- [ ] Add NDJSON streaming output.
- [ ] Ensure final response is not duplicated after streaming text deltas.
- [ ] Ensure no human progress leaks to stdout in JSON modes.
- [ ] Add renderer tests.

Exit gate:

- [ ] `grok code --format streaming-json ...` emits valid JSON per line in a mock test.

### Phase 5: Docs, Regression, Build, Install

- [ ] Update `README.md`.
- [ ] Update `xai_oauth.md`.
- [ ] Run focused tests.
- [ ] Run full tests if focused tests pass.
- [ ] Run build.
- [ ] Run install.
- [ ] Report exact commands and outcomes.

Exit gate:

- [ ] User can run the installed `grok code` from PATH.

## Test And Verification Gates

Implementation verification commands:

```sh
swift test --filter GrokClientTests
swift test --filter GrokCLIE2ETests
swift test --filter GrokProxyTests
swift test
swift build
Scripts/install_cli.sh --user
```

Focused command smoke tests after install:

```sh
grok code --help
grok code --json --model grok-build-0.1 "Inspect Package.swift and summarize the products."
grok code --format streaming-json --model grok-build-0.1 "List the top-level files and stop."
```

Mock test scenarios:

- [ ] Missing OAuth credential exits non-zero with `grok auth oauth` guidance.
- [ ] Saved OAuth credential refreshes before code-mode request if expiring.
- [ ] `/v1/models` selects `grok-build-0.1` by default when present.
- [ ] Code mode fails clearly if no Grok Build model is present and no explicit model was supplied.
- [ ] Tool schemas are present only for `grok code`, not `grok message`.
- [ ] `read_file` function call returns line-numbered output.
- [ ] `grep` uses stable match formatting.
- [ ] `list_dir` output is stable and capped.
- [ ] `run_terminal_cmd` obeys timeout.
- [ ] `search_replace` refuses stale edits.
- [ ] Function-call outputs are sent with the original call ID.
- [ ] Final answer is recorded only after all pending function calls have results.
- [ ] JSON output is one parseable JSON object.
- [ ] Streaming JSON output is parseable NDJSON.
- [ ] Proxy tests still pass unchanged.

## Risks And Mitigations

- [ ] Risk: xAI Responses function-call event names differ from OpenAI-style assumptions.
  - Mitigation: Phase 0 fixtures and official-doc verification before broad implementation.
- [ ] Risk: Grok Build model emits multiple parallel calls that conflict on files.
  - Mitigation: v0.1 executes serially by default and rejects unsafe parallel write calls.
- [ ] Risk: `search_replace` corrupts files due to stale context.
  - Mitigation: require prior `read_file` and content-hash/mtime verification.
- [ ] Risk: Existing OAuth message behavior regresses.
  - Mitigation: add tests proving tools are omitted outside code mode.
- [ ] Risk: Proxy behavior regresses due to shared model changes.
  - Mitigation: keep code mode in `GrokCLI`; run `GrokProxyTests`.
- [ ] Risk: JSON output gets polluted by progress text.
  - Mitigation: reuse existing JSON purity patterns from message/chat commands and add tests.
- [ ] Risk: Tool execution leaks credentials in transcript.
  - Mitigation: redact Authorization, Cookie, tokens, and known config paths before storage/output.
- [ ] Risk: User expects old web-agent role customization.
  - Mitigation: document that v0.1 uses per-request instructions and local tools; web settings scope is explicitly non-goal.

## Rollback Notes

- [ ] Keep all new behavior behind `grok code`; do not change default `grok` or `grok message` routing.
- [ ] If a late issue appears, move `code` back to `disabledTopLevelCommands` without touching OAuth message/chat paths.
- [ ] Keep tool-enabled Responses helpers separate from existing `sendXAIOAuthMessage` and `streamXAIOAuthMessage` until stable.
- [ ] Avoid persistent remote settings changes entirely, so rollback does not require account setting restoration.
- [ ] If docs are updated before launch and rollback happens, revert only the public CodeMode docs while keeping internal plan files.

## Final Completion Checklist

- [ ] User requirement: revive the code wing now that OAuth tool calls can run locally.
  - Evidence: `grok code` routes through OAuth Responses function calling and executes tools locally.
- [ ] User requirement: use `tmp_grokbuild.md` as the prompt/tool-shape source.
  - Evidence: implemented tool names and schemas match `tmp_grokbuild.md` for v0.1 tools.
- [ ] User requirement: choose the right path forward rather than restarting the old blocked path.
  - Evidence: implementation does not mutate Grok web user settings and does not use JSON-in-prose as the primary tool protocol.
- [ ] Repo requirement: after implementation task in an approved plan, run build and install.
  - Evidence: final implementation report includes `swift build` and `Scripts/install_cli.sh --user` output.
- [ ] Repo requirement: do not run build/tests/install for plan-only work.
  - Evidence: this plan file was created without running build, tests, or install.
- [ ] Safety requirement: preserve unrelated dirty worktree changes.
  - Evidence: implementation commits or diffs do not revert pre-existing changes in `GrokClientTransport.swift`, `GrokClientRequestBuildingTests.swift`, or `tmp_grokbuild.md`.
