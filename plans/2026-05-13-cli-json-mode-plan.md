# CLI JSON Mode Plan

Date: 2026-05-13

## Objective

Add a coherent JSON mode to the `grok` CLI so shell scripts can call commands and receive deterministic, parseable output with stable exit codes.

This plan is intentionally a review spec, not an implementation. It documents the current command surface, current return/output behavior, the recommended JSON contract, and parallel workstreams that another agent can execute without redoing discovery.

## Success Criteria

- `grok message --json <text>` and `grok message --format json <text>` print only valid JSON to stdout on success.
- `grok message --stream --json <text>` prints newline-delimited JSON events to stdout, one valid JSON object per line.
- Resource commands that already accept `--json` keep scriptability but move behind one stable CLI schema, with raw API payloads preserved under `data.raw`.
- `models`, `list`, `auth`, `test`, and supported help paths gain JSON behavior or explicitly documented human-only behavior.
- JSON mode never mixes human banners, colors, prompts, transient status text, or markdown formatting into stdout.
- JSON mode failures return non-zero and emit a parseable error object when the CLI can determine that JSON was requested.
- Human output remains backward-compatible unless the implementation notes below explicitly call out a chosen migration.
- E2E tests cover every command group and every JSON/human/stream/error permutation listed in this plan.
- README, built-in help, and release notes document the stable JSON contract and examples.
- After implementation, verification passes with:
  - `swift build --product grok`
  - `swift test --filter GrokCLIE2ETests`
  - `swift test`
  - `git diff --check`
  - `Scripts/install_cli.sh`

## Review Decisions

These are the main choices to approve before implementation:

- Recommended flag contract:
  - `--json` means "emit CLI JSON envelope".
  - `--format json` is accepted as an alias where `--format` already exists.
  - `--format md|raw` stays human answer rendering, not machine mode.
  - Add `--api-json` only for resource commands that need raw Grok API passthrough compatibility.
- Recommended stream contract:
  - Non-streaming JSON prints one `grok.cli.result.v1` object.
  - Streaming JSON prints NDJSON `grok.cli.event.v1` events.
- Recommended interactive boundary:
  - `grok chat --json` and interactive `/format json` are not in scope for the first implementation because prompts and long-running sessions are not naturally scriptable.
  - The CLI should print a usage error telling users to use `grok message --json`.
- Recommended `list` behavior:
  - `grok list --json` should list conversations and exit without prompting.
  - Add `grok list --conversation <conversationId> --json` to fetch history by ID, using the existing `loadConversation` path.
- Recommended compatibility stance:
  - Human output stays unchanged.
  - Existing resource `--json` tests should be updated to assert the new envelope and `data.raw`, not raw root-level API payloads.

## Current-State Findings

### Repository State

- [x] The worktree was already dirty before this planning pass. The current filesystem has a modularized CLI under `Sources/GrokCLI/{Commands,Core,Interactive,Parsing,Presentation,Runtime}` plus deleted old flat files in git status.
- [x] This plan targets the current filesystem state, not the deleted legacy flat files.
- [x] No implementation files were intentionally changed for this plan.

### Entry Points And Routing

- [x] `Sources/GrokCLI/main.swift` calls `try await GrokCLI.main()`.
- [x] The real top-level router is `GrokCLI.main()` in `Sources/GrokCLI/Core/TopLevelRouter.swift`.
- [x] Top-level command matching is case-insensitive.
- [x] No args starts interactive chat.
- [x] Unknown top-level text routes to `handleChatCommand(args:)` as an initial chat message.
- [x] `ArgumentParser` command structs exist for some commands, but the live `grok` route is mostly the custom manual parser.

### Output And Error Handling

- [x] Human response rendering lives in `Sources/GrokCLI/Presentation/OutputFormatter.swift`.
- [x] JSON helper `printPrettyJSON` lives in `Sources/GrokCLI/Presentation/RowFormatting.swift`.
- [x] Current `--json` support is partial:
  - agents, tasks, skills, workspaces, and files have local `--json` flags.
  - message, chat, list, auth, models, help, and test do not have a unified JSON mode.
- [x] Current CLI output uses stdout for human text, JSON, debug text, prompts, and errors. No dedicated stderr abstraction exists.
- [x] `GrokCLIApp.handleError` in `Sources/GrokCLI/Runtime/GrokCLIApp.swift` centralizes runtime/API error presentation and may attempt automatic auth refresh for auth-like failures.
- [x] Direct top-level parse/usage failures generally exit `2`; runtime/API failures generally exit `1`; raw interactive Ctrl-C exits `130`.

### Tests And Build

- [x] Primary CLI E2E coverage is in `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`.
- [x] Existing E2E tests cover help, message options, stream rendering, resource `--json`, interactive slash/bare routing, formatter behavior, and error exit codes.
- [x] Existing JSON tests cover resource groups only, not chat/message JSON output mode.
- [x] A runtime discovery pass successfully built locally with `swift build --skip-update --disable-automatic-resolution`.
- [x] `swift test --list-tests --skip-build --skip-update --disable-automatic-resolution` listed 48 Swift tests.
- [x] Canonical install path is `Scripts/install_cli.sh`, which builds release product `grok` and installs `grok` plus `cookie_extractor.py`.

### Discovery Commands Used

- [x] `pwd`
- [x] `git status --short`
- [x] `rg --files`
- [x] `find .. -name AGENTS.md -print`
- [x] `sed -n` reads across `Package.swift`, CLI source, tests, README, and prior plans
- [x] `rg -n "print\\(|--json|JSON|OutputFormatter|handle.*Command|printPrettyJSON|cleanOutput|stdout|stderr|status|exit" Sources/GrokCLI Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- [x] `swift build --skip-update --disable-automatic-resolution`
- [x] `swift run --skip-build --skip-update --disable-automatic-resolution grok --help`
- [x] `swift test --list-tests --skip-build --skip-update --disable-automatic-resolution`

## Command Surface Inventory

### Top-Level Commands

| Command | Aliases / Defaults | Current Args And Options | Current Return Shape | JSON Target |
| --- | --- | --- | --- | --- |
| `grok` | no args starts interactive chat | none | human interactive session | Human terminal session without command output |
| unknown top-level text | routes to chat initial message | `[options] [initial message...]` if options are understood by chat | human interactive session after initial response | Human-only; scripts should use `message` |
| `chat` | default command | `--reasoning`, `--deep-search`, `--no-search`, `--markdown`, `-m`, `--raw`, `--format md|raw`, `--debug`, `--no-custom-instructions`, `--private`, `--stream`, `--model|--mode <mode>`, initial message | status lines, optional initial response, then prompt | With JSON, send the initial message as one command result and exit |
| `message` | single-shot | same shared options as chat; message required | status lines, `Thinking`, `Grok:`, answer, source counts, optional debug IDs | Result JSON or NDJSON events |
| `auth` | no subcommand defaults to `generate`; browser shortcuts | `generate`, `import`, browser names | progress/success/error text | `auth_result` JSON |
| `list` | none | `--debug`; stdin selection prompt | conversation list, prompt, optional loaded history | `conversation_list`; optional `conversation_history` by ID |
| `models` | `modes` | help arg only | current model plus known modes | `model_list` JSON |
| `agents` | no args defaults list | subcommands below; `--json`, `--debug`, `--replace` | human rows or raw settings JSON | `resource_list` / `resource_mutation` envelope |
| `tasks` | no args defaults list | subcommands below; `--json`, `--debug` | human rows or task JSON | `resource_list` / `resource_mutation` envelope |
| `skills` | no args defaults list | subcommands below; `--json`, `--debug` | human rows or skill JSON | `resource_list` envelope |
| `workspaces` | `workspace`; no args defaults list | subcommands below; `--json`, `--debug` | human rows or raw response JSON | `resource_list` / `resource_mutation` envelope |
| `files` | no args defaults list | subcommands below; `--json`, `--debug` | human rows or raw response JSON | `resource_list` / `resource_mutation` envelope |
| `test` | hidden from global help | optional message words | debug text | `test_result` JSON |
| `help`, `-h`, `--help` | global help | none | human help | Optional `help` JSON for `grok help --json` |

### Shared Chat And Message Options

| Option | Current Values | Current Parser | JSON-Mode Requirement |
| --- | --- | --- | --- |
| `--reasoning` | bool | manual parser | Include in `meta.request.reasoning` |
| `--deep-search` | bool | manual parser | Include in `meta.request.deepSearch` |
| `--no-search` | bool | manual parser | Include in `meta.request.noSearch` |
| `--markdown`, `-m` | bool | manual parser | Human-only; invalid with `--json` only if conflicting clarity is preferred |
| `--raw` | bool | manual parser | Human-only; invalid with `--json` only if conflicting clarity is preferred |
| `--format` | `md`, `markdown`, `raw`, `plain`, `text` | `applyOutputFormatOption` | Add `json`; update all errors from `md or raw` to `md, raw, or json` |
| `--debug` | bool | manual parser | JSON stdout must stay valid; debug goes to stderr or `meta.debug` |
| `--no-custom-instructions` | bool | manual parser | Include in `meta.request.customInstructionsEnabled` |
| `--private` | bool | manual parser | Include in `meta.request.private` |
| `--stream` | bool; default true for `chat`, false for `message` | manual parser | With `--json`, select NDJSON events |
| `--model`, `--mode` | known aliases or raw mode ID | `applyModelOption` | Include resolved `{ id, displayName, summary }` |

### Auth Subcommands

| Command | Current Permutations | Current Return Shape | JSON Target |
| --- | --- | --- | --- |
| `grok auth` | defaults to generate | progress, success path | `auth_result` with `action: "generate"`, `credentialsPath`, `browser` if known |
| `grok auth generate` | `--browser <name>`, `--quiet`; pass-through extractor args also possible | progress, success path | same as above |
| `grok auth <browser>` | `auto`, `safari`, `atlas`, `chrome`, `firefox`, `chromium`, `brave`, `edge`, `arc` | normalized to generate | same as above with `browser` |
| `grok auth import <file>` | required path | progress, success or failure text | `auth_result` with `action: "import"`, `path`, `credentialsPath` if available |
| help paths | `auth help`, `auth --help`, subcommand help | human help | Optional `help` JSON |

### Agent Subcommands

| Command | Current Permutations | Current Return Shape | JSON Target |
| --- | --- | --- | --- |
| `agents`, `agents list` | `--json`, `--debug` | human rows or raw settings JSON | `resource_list`, `resource: "agent"`, `items`, `raw` |
| `agents set <agentId>` | `--instructions <text>` or `--file|--instructions-file <path>`, `--name <name>`, `--replace`, `--json`, `--debug`; agent ID `0...3` | human update summary or raw settings JSON | `resource_mutation`, `action: "set"`, `id`, `item`, `raw` |
| `agents clear <agentId>` | `--replace`, `--json`, `--debug` | human clear summary or raw settings JSON | `resource_mutation`, `action: "clear"`, `id`, `item`, `raw` |
| `agents sync-custom` | `--replace`, `--json`, `--debug` | human sync summary or raw settings JSON | `resource_mutation`, `action: "syncCustom"`, `id: 0`, `item`, `raw` |
| help paths | group and subcommand help | human help | Optional `help` JSON |

### Task Subcommands

| Command | Current Permutations | Current Return Shape | JSON Target |
| --- | --- | --- | --- |
| `tasks`, `tasks list` | `--json`, `--debug` | human rows or encoded `[GrokTask]` | `resource_list`, `resource: "task"`, `items`, `raw` where available |
| `tasks create` | `--prompt <text>` required; optional `--name`, `--date YYYY-MM-DD`, `--time HH:mm`, `--timezone TZ`, `--guideline`, `--model-mode`; defaults date/time/timezone | human create summary or encoded mutation response | `resource_mutation`, `action: "create"`, `item`, `raw` |
| `tasks archive <taskId>` | `--json`, `--debug` | human archive summary or encoded mutation response | `resource_mutation`, `action: "archive"`, `id`, `item`, `raw` |
| help paths | group and subcommand help | human help | Optional `help` JSON |

### Skill Subcommands

| Command | Current Permutations | Current Return Shape | JSON Target |
| --- | --- | --- | --- |
| `skills`, `skills list` | `--json`, `--debug` | human rows or encoded `[GrokSkill]` | `resource_list`, `resource: "skill"`, `scope: "available"`, `items`, `raw` where available |
| `skills mine` | alias of user skills | human rows or encoded `[GrokSkill]` | `resource_list`, `scope: "user"` |
| `skills user` | alias of `mine` | human rows or encoded `[GrokSkill]` | `resource_list`, `scope: "user"` |
| help paths | group and subcommand help | human help | Optional `help` JSON |

### Workspace Subcommands

| Command | Current Permutations | Current Return Shape | JSON Target |
| --- | --- | --- | --- |
| `workspaces`, `workspace`, `workspaces list` | `--json`, `--debug` | human rows or raw response JSON | `resource_list`, `resource: "workspace"`, `items`, `raw` |
| `workspaces create` | `--name <name>` required; optional `--icon`, `--personality`, `--model`; defaults icon/personality/model | human create summary or raw response JSON | `resource_mutation`, `action: "create"`, `item`, `raw` |
| `workspaces add-conversation <workspaceId> <conversationId>` | `--json`, `--debug` | human success text or raw response JSON | `resource_mutation`, `action: "addConversation"`, IDs, `raw` |
| `workspaces delete <workspaceId>` | `remove` alias | human success text or raw response JSON | `resource_mutation`, `action: "delete"`, `id`, `raw` |
| `workspaces conversation <conversationId>` | `--json`, `--debug` | summary or raw conversation response JSON | `conversation_detail`, `conversationId`, `workspaces`, `taskResult`, `raw` |
| help paths | group and subcommand help | human help | Optional `help` JSON |

### File Subcommands

| Command | Current Permutations | Current Return Shape | JSON Target |
| --- | --- | --- | --- |
| `files`, `files list` | `--page-size N`, `--json`, `--debug`; default page size 9 | human rows or raw response JSON | `resource_list`, `resource: "file"`, `items`, `pageSize`, `raw` |
| `files upload <path>` | optional `--mime`; MIME inferred from extension | human upload summary or raw response JSON | `resource_mutation`, `action: "upload"`, `id`, `item`, `raw` |
| help paths | group and subcommand help | human help | Optional `help` JSON |

### Interactive Commands

Interactive commands live in `Sources/GrokCLI/Interactive/InteractiveCommandParser.swift`, `InteractiveCommandSpecs.swift`, and `InteractiveSession.swift`.

Keep the long-running prompt human-first. JSON command output is produced by CLI invocations, not slash-command formatting.

| Interactive Surface | Current Behavior | JSON Decision |
| --- | --- | --- |
| `/format md|raw`, `/md`, `/markdown`, `/raw` | toggles human answer rendering | Do not add `/format json` yet; show usage recommending `grok message --json` |
| `/agents`, `/tasks`, `/skills`, `/workspaces`, `/files` | call the same group handlers and may accept `--json` today | In interactive mode, reject `--json` or allow human display only; stdout JSON inside a prompt is not script-friendly |
| `/workspace`, `/attach`, `/model` | open pickers | Human-only |
| `/auth` | runs auth in-session | Human-only |
| `/help` | human help | Human-only |
| unknown slash command | prints unknown command | Keep current tested behavior |
| unknown bare text | sent as chat message | Keep current behavior |

## Proposed JSON Contract

### Result Envelope

Use one envelope for non-streaming successful commands:

```json
{
  "schema": "grok.cli.result.v1",
  "ok": true,
  "command": "message",
  "category": "assistant_response",
  "data": {},
  "meta": {
    "format": "json",
    "version": "1",
    "debug": false,
    "warnings": []
  }
}
```

Required top-level fields:

- `schema`: stable schema identifier.
- `ok`: boolean success.
- `command`: normalized top-level command or command group.
- `subcommand`: optional normalized subcommand.
- `category`: stable result type.
- `data`: command-specific payload.
- `meta`: output metadata, request options, and non-sensitive diagnostics.

### Error Envelope

When JSON was requested and an error occurs after option parsing can detect that request:

```json
{
  "schema": "grok.cli.result.v1",
  "ok": false,
  "command": "message",
  "category": "error",
  "error": {
    "code": "usage_error",
    "message": "Invalid output format 'xml'. Use md, raw, or json.",
    "exitCode": 2,
    "recoverable": false
  },
  "meta": {
    "format": "json",
    "debug": false
  }
}
```

Recommended error codes:

- `usage_error` for parse/validation failures; exit `2`.
- `auth_error` for missing/expired credentials; exit `1` unless automatic refresh recovers.
- `api_error` for non-auth Grok API errors; exit `1`.
- `network_error` for transport failures; exit `1`.
- `decoding_error` for unparseable Grok responses; exit `1`.
- `interrupted` for Ctrl-C; exit `130`.

### Streaming Event Envelope

When `--stream --json` is requested, stdout should be NDJSON:

```json
{"schema":"grok.cli.event.v1","sequence":1,"event":"request","data":{"message":"hello","model":{"id":"fast","displayName":"Fast"}}}
{"schema":"grok.cli.event.v1","sequence":2,"event":"trace","data":{"kind":"thinking","text":"Thinking about your request"}}
{"schema":"grok.cli.event.v1","sequence":3,"event":"assistant_delta","data":{"text":"partial"}}
{"schema":"grok.cli.event.v1","sequence":4,"event":"assistant_final","data":{"message":"partial answer","conversationId":"conv-e2e","responseId":"resp-e2e"}}
```

Event requirements:

- Every line is a complete JSON object.
- `sequence` starts at 1 and increments.
- Human-only text such as `Thinking`, `Grok:`, colors, and markdown-rendered chunks must not appear.
- Final event includes the same assistant payload as non-streaming `assistant_response`.
- Runtime errors after some events emit one final `error` event and exit non-zero.

### Command Data Shapes

#### `assistant_response`

```json
{
  "message": "Mock final response",
  "conversationId": "conv-e2e",
  "responseId": "resp-e2e",
  "timestamp": null,
  "model": {
    "id": "fast",
    "displayName": "Fast",
    "summary": "Quick responses"
  },
  "sources": {
    "webSearchResults": [],
    "xposts": []
  },
  "request": {
    "reasoning": false,
    "deepSearch": false,
    "noSearch": false,
    "private": false,
    "stream": false,
    "customInstructionsEnabled": true,
    "workspaceIds": [],
    "fileAttachmentIds": []
  }
}
```

#### `model_list`

```json
{
  "currentModel": { "id": "fast", "displayName": "Fast", "summary": "Quick responses" },
  "models": [
    { "id": "auto", "displayName": "Auto", "summary": "Chooses Fast or Expert", "selected": false }
  ]
}
```

#### `conversation_list`

```json
{
  "conversations": [
    {
      "conversationId": "conv-e2e",
      "title": "Mock Conversation",
      "starred": false,
      "createTime": "2026-05-13T00:00:00Z",
      "modifyTime": "2026-05-13T00:00:00Z",
      "temporary": false,
      "mediaTypes": []
    }
  ],
  "nextPageToken": null
}
```

#### `conversation_history`

```json
{
  "conversationId": "conv-e2e",
  "responses": [
    {
      "responseId": "resp-user",
      "sender": "human",
      "message": "Loaded user response",
      "createTime": "2026-05-13T00:00:00Z",
      "parentResponseId": null
    }
  ]
}
```

#### `resource_list`

```json
{
  "resource": "task",
  "items": [],
  "raw": {}
}
```

#### `resource_mutation`

```json
{
  "resource": "workspace",
  "action": "create",
  "id": "workspace-1",
  "item": {},
  "raw": {}
}
```

#### `auth_result`

```json
{
  "action": "generate",
  "credentialsPath": "/Users/example/.config/grok-cli/credentials.json",
  "browser": "safari",
  "refreshed": false
}
```

#### `help`

```json
{
  "topic": "tasks",
  "usage": "grok tasks create --prompt <text> ...",
  "commands": [],
  "options": []
}
```

#### `test_result`

```json
{
  "message": "hello parser",
  "provided": true
}
```

## Implementation Workstreams

The user explicitly allows sub-agents for multi-threaded tasks. These workstreams are divided so up to six agents can work in parallel after the schema decisions are approved. Each workstream has a narrow write scope.

### Workstream 1: Output Mode And JSON Infrastructure

Owner scope:

- `Sources/GrokCLI/Core/GrokCommandOptions.swift`
- `Sources/GrokCLI/Parsing/ModelOptionParsing.swift`
- `Sources/GrokCLI/Presentation/RowFormatting.swift`
- New files under `Sources/GrokCLI/Presentation/` or `Sources/GrokCLI/Core/` for JSON output types

Tasks:

- [x] Discover current `OutputFormat` values and parsing helpers.
- [x] Confirm current JSON helper only pretty-prints arbitrary `Encodable` values.
- [ ] Replace or extend `OutputFormat` so answer rendering and machine output are not conflated.
- [ ] Add an output request type, for example `CLIOutputMode`, with `.human(format: .markdown|.raw)`, `.json`, and `.ndjson`.
- [ ] Add `CLIJSONEnvelope`, `CLIJSONError`, `CLIJSONEvent`, and command-specific payload structs.
- [ ] Add a writer abstraction that can:
  - write JSON result/event objects to stdout,
  - write debug/progress/errors to stderr in JSON mode,
  - preserve current stdout behavior in human mode.
- [ ] Update `applyOutputFormatOption` to accept `json` and return enough information for callers to select JSON mode.
- [ ] Add `--json` parsing helper usable by chat/message/list/models/auth/resource groups.
- [ ] Update invalid format messages to say `md, raw, or json`.
- [ ] Add a way to preserve raw API payloads under `data.raw` using existing `AnyCodable`.

Dependencies:

- Workstreams 2, 3, and 4 depend on these shared types.

### Workstream 2: Message, Chat Boundary, And Streaming Events

Owner scope:

- `Sources/GrokCLI/Commands/MessageCommand.swift`
- `Sources/GrokCLI/Interactive/InteractiveSession.swift`
- `Sources/GrokCLI/Presentation/OutputFormatter.swift`
- `Sources/GrokCLI/Presentation/GrokStreamMarkupParser.swift` only if needed for structured trace extraction

Tasks:

- [x] Discover `message` is the main scriptable command without JSON mode.
- [x] Discover `message` defaults non-streaming and `chat` defaults streaming.
- [ ] Add `--json` and `--format json` support to the live manual `handleMessageCommand` parser.
- [ ] Suppress human banners in message JSON mode:
  - no `Calling Grok API...`,
  - no `Sending: ...`,
  - no `Thinking`,
  - no `Grok:`,
  - no source-count prose,
  - no ANSI colors.
- [ ] For non-streaming JSON, collect final `ConversationResponse` and emit one `assistant_response` envelope.
- [ ] For streaming JSON, emit NDJSON events for request, trace/thinking/tool usage, assistant deltas, final response, sources, and errors.
- [ ] Preserve current human streaming behavior exactly where possible.
- [ ] Add explicit `chat --json` and `chat --format json` handling that returns usage error `2` and recommends `grok message --json`.
- [ ] Decide whether `grok --json hello` should be treated as chat usage error or unknown-top-level text; recommended: usage error only when the first arg is exactly `--json`.
- [ ] Ensure automatic auth refresh does not leak human text to stdout in JSON mode; progress can go stderr or become structured events.

Dependencies:

- Depends on Workstream 1 output infrastructure.
- Tests in Workstream 6 should lock the exact stdout contract.

### Workstream 3: Resource Command Normalization

Owner scope:

- `Sources/GrokCLI/Commands/AgentCommands.swift`
- `Sources/GrokCLI/Commands/TaskCommands.swift`
- `Sources/GrokCLI/Commands/SkillCommands.swift`
- `Sources/GrokCLI/Commands/WorkspaceCommands.swift`
- `Sources/GrokCLI/Commands/FileCommands.swift`

Tasks:

- [x] Discover existing resource `--json` behavior and inconsistencies.
- [ ] Replace direct `printPrettyJSON(...)` calls with centralized result-envelope emission.
- [ ] For list commands, emit `resource_list` with normalized `items` plus `raw` when available.
- [ ] For mutation commands, emit `resource_mutation` with `resource`, `action`, IDs, normalized `item`, and `raw`.
- [ ] Preserve useful parsed fields:
  - agents: `agentId`, `name`, `instructions`, instruction character count if helpful,
  - tasks: `taskId`, `id`, `name`, `prompt`, `isEnabled`, `schedule`,
  - skills: `skillId`, `id`, `name`, `title`, `status`, `description`,
  - workspaces: `workspaceId`, `id`, `name`, `title`, `icon`, `preferredModel`,
  - files: resolved ID, filename, MIME type.
- [ ] Add `--api-json` only if review chooses raw API compatibility outside the envelope.
- [ ] Ensure `--debug` in JSON mode does not add human debug lines to stdout.
- [ ] Keep help requests human by default unless Workstream 4 adds structured help JSON.
- [ ] Preserve current usage-error exit code `2` and runtime-error exit code `1`.

Dependencies:

- Depends on Workstream 1.
- Coordinate exact error envelope shape with Workstream 6.

### Workstream 4: Models, List, Auth, Test, Help, And Interactive Boundaries

Owner scope:

- `Sources/GrokCLI/Core/TopLevelRouter.swift`
- `Sources/GrokCLI/Commands/AuthCommand.swift`
- `Sources/GrokCLI/Commands/ListCommand.swift`
- `Sources/GrokCLI/Commands/TestCommand.swift`
- `Sources/GrokCLI/Interactive/InteractiveModelCommands.swift`
- `Sources/GrokCLI/Interactive/InteractiveCommandParser.swift`
- `Sources/GrokCLI/Interactive/InteractiveSession.swift`
- `Sources/GrokCLI/Presentation/HelpText.swift`

Tasks:

- [x] Discover `models`, `auth`, `list`, and `test` lack unified JSON mode.
- [x] Discover top-level help omits recognized aliases `modes`, `workspace`, and hidden `test`.
- [ ] Add `models --json` and `modes --json` returning `model_list`.
- [ ] Add `auth --json`, `auth generate --json`, browser shortcut `--json`, and `auth import --json` returning `auth_result`.
- [ ] Route auth progress/debug text away from stdout in JSON mode.
- [ ] Add `list --json` that lists conversations and exits without prompting.
- [ ] Add `list --conversation <conversationId> --json` for scriptable history loading.
- [ ] Add `test --json` returning `test_result`.
- [ ] Decide whether `help --json` is in scope:
  - minimum: document help as human-only,
  - better: add structured help for top-level and group help.
- [ ] Reject JSON mode inside interactive `/format`, `/agents --json`, `/tasks --json`, etc., or explicitly document that JSON output inside an interactive prompt is unsupported.
- [ ] Update top-level help wording so "App Options" does not imply every command accepts every option.
- [ ] Update help to mention `--json` and `--format json` across commands.

Dependencies:

- Depends on Workstream 1.
- Coordinate docs with Workstream 5.

### Workstream 5: Documentation And Release Notes

Owner scope:

- `README.md`
- `RELEASES.md`
- `Sources/GrokCLI/Presentation/HelpText.swift`
- Usage strings in command files
- Optional examples under `plans/` only if needed

Tasks:

- [x] Discover README currently documents `--raw` and `--format raw`, not JSON mode.
- [x] Discover built-in help currently says `--format <md|raw>`.
- [ ] Add README section "JSON And Scripting" with examples:
  - `grok message --json "hello" | jq .data.message`
  - `grok message --stream --json "hello" | jq -r 'select(.event=="assistant_delta") .data.text'`
  - `grok models --json`
  - `grok tasks list --json`
  - `grok list --json`
  - `grok auth generate --json`
- [ ] Document stdout/stderr contract:
  - stdout is valid JSON/NDJSON in JSON mode,
  - progress/debug goes stderr,
  - exit codes remain meaningful.
- [ ] Document schema stability and `schema` field.
- [ ] Document resource `data.raw` and any `--api-json` compatibility flag.
- [ ] Update built-in top-level help and command usage strings to include JSON aliases.
- [ ] Update interactive help to say JSON scripting is available from shell commands, not the prompt.
- [ ] Add a release note describing JSON mode and compatibility changes.

Dependencies:

- Depends on review decisions and should land after Workstreams 1-4 settle exact flags.

### Workstream 6: E2E Tests, Fixtures, Verification, And Install

Owner scope:

- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- Test helpers in the same file
- Optional focused unit tests for JSON envelope types if added

Tasks:

- [x] Discover existing E2E mock server already covers chat, resources, auth, files, rate limits, and interactive flows.
- [ ] Add JSON parsing helpers to `RunResult`, for example `jsonObject()` and `jsonLines()`.
- [ ] Add `message --json` test:
  - status `0`,
  - stdout parses as one JSON object,
  - `ok == true`,
  - `category == "assistant_response"`,
  - includes `message`, `conversationId`, `responseId`, model, sources,
  - excludes human banners and ANSI.
- [ ] Add `message --stream --json` test:
  - stdout splits into parseable JSON lines,
  - sequence increments,
  - includes trace/delta/final events,
  - excludes human stream rendering.
- [ ] Add `message --json` runtime-error test using existing rate-limit server:
  - status `1`,
  - stdout parses as error envelope,
  - no raw Grok error blob.
- [ ] Update invalid-format tests to expect `md, raw, or json`.
- [ ] Add `chat --json` rejection test, status `2`.
- [ ] Add `models --json` and `modes --json` tests.
- [ ] Add `list --json` no-prompt test.
- [ ] Add `list --conversation conv-e2e --json` history test.
- [ ] Add `auth import --json` and fake extractor `auth generate --json` tests.
- [ ] Update existing resource `--json` tests to assert envelopes and `data.raw`.
- [ ] Add `test --json` test.
- [ ] Add tests ensuring JSON mode sends debug/progress to stderr or suppresses it.
- [ ] Run verification:
  - `swift build --product grok`
  - `swift test --filter GrokCLIE2ETests`
  - `swift test`
  - `git diff --check`
  - `Scripts/install_cli.sh`

Dependencies:

- Test expectations depend on Workstreams 1-4.
- Full verification and install happen after implementation, not during plan review.

## Ordered Implementation Steps

1. Confirm review decisions for `--json` versus `--format json`, resource raw compatibility, stream NDJSON, and interactive scope.
2. Add shared output-mode parsing and JSON envelope/event types.
3. Add stdout/stderr writer abstraction with current human behavior preserved.
4. Implement `message --json` non-streaming.
5. Implement `message --stream --json` NDJSON.
6. Add explicit `chat` JSON rejection.
7. Normalize resource command JSON output through envelopes.
8. Implement `models --json`.
9. Implement `list --json` and `list --conversation <id> --json`.
10. Implement `auth --json` and route progress safely.
11. Implement `test --json`.
12. Decide and implement or document `help --json`.
13. Update interactive parser/help so slash-command formatting stays focused on `md` and `raw`.
14. Update README, built-in help, usage strings, and release notes.
15. Add and update E2E tests for every JSON path and error path.
16. Run full verification and installer.

## Test And Verification Gates

### Gate 1: Parser And Help

- `swift test --filter GrokCLIE2ETests/testTopLevelStaticCommandsAndReservedEdges`
- Add parser-specific JSON tests for `--json`, `--format json`, invalid combinations, and help text.

### Gate 2: Message JSON

- `grok message --json hello` stdout parses as one object.
- `grok message --format json hello` matches `--json`.
- `grok message --stream --json hello` stdout parses as NDJSON.
- `grok message --json --debug hello` stdout remains valid JSON.
- `grok message --json --format nope hello` emits error JSON and exits `2` if JSON intent is unambiguous.

### Gate 3: Resource JSON Matrix

- `grok agents list --json`
- `grok agents set 1 --instructions "x" --replace --json`
- `grok agents clear 1 --replace --json`
- `grok agents sync-custom --replace --json`
- `grok tasks list --json`
- `grok tasks create --prompt "x" --json`
- `grok tasks archive task-1 --json`
- `grok skills list --json`
- `grok skills mine --json`
- `grok skills user --json`
- `grok workspaces list --json`
- `grok workspaces create --name "x" --json`
- `grok workspaces add-conversation workspace-1 conv-e2e --json`
- `grok workspaces delete workspace-1 --json`
- `grok workspaces conversation conv-e2e --json`
- `grok files list --json`
- `grok files upload ./file.md --json`

### Gate 4: Other Commands

- `grok models --json`
- `grok modes --json`
- `grok list --json`
- `grok list --conversation conv-e2e --json`
- `grok auth import credentials.json --json`
- `grok auth generate --json` with fake extractor
- `grok auth safari --json` with fake extractor
- `grok test --json hello`
- Optional: `grok help --json`

### Gate 5: Full Verification

- `swift build --product grok`
- `swift test --filter GrokCLIE2ETests`
- `swift test`
- `git diff --check`
- `Scripts/install_cli.sh`

## Risks And Edge Cases

- Existing resource `--json` may already be used by scripts. Mitigation: preserve raw API payload under `data.raw`; consider `--api-json` if compatibility needs are strict.
- `chat` is interactive and currently starts by default for unknown top-level text. Making it JSON could mix prompt text with JSON. Mitigation: route JSON requests with an initial message through the one-shot message flow.
- Current output goes entirely to stdout. JSON mode must avoid human text on stdout. Mitigation: add writer abstraction before touching command handlers.
- Automatic auth refresh prints multiple human lines. Mitigation: make `handleError` JSON-aware or provide a JSON-mode error path that can also trigger refresh events safely.
- Streaming parser currently transforms hidden Grok markup into human trace lines. Mitigation: reuse parser logic but emit structured `trace` events instead of rendered text.
- Debug output currently comes from many locations. Mitigation: route app/debug printing through a shared sink in JSON mode, or suppress debug stdout when JSON is active.
- Help and usage errors may occur before full option parsing. Mitigation: pre-scan args for `--json` and `--format json` before deeper parsing.
- Pretty-printed JSON is easy to read but NDJSON must remain one object per line. Mitigation: result mode can pretty-print; event mode must not.
- Dates and default timezone in tasks use runtime `Date()` and fallback `Asia/Bangkok`. Mitigation: tests should pass explicit date/time/timezone for deterministic create cases.
- `AnyCodable` can encode arbitrary API payloads, but normalized fields should not depend on every raw response shape. Mitigation: keep `raw` plus best-effort normalized fields.

## Rollback Notes

- Keep human output code paths isolated from JSON output code paths.
- If resource envelope migration is too disruptive, rollback only resource groups to their old `printPrettyJSON` behavior and keep message/models/list/auth JSON.
- If streaming JSON becomes risky, ship non-streaming `message --json` first and make `--stream --json` a usage error until event tests are stable.
- If auth refresh JSON introduces regressions, ship JSON for explicit `auth generate/import` first and keep automatic refresh human-only.
- New JSON infrastructure should be additive files where possible so rollback can remove those files and parser branches cleanly.

## Final Completion Checklist

Map each user requirement to evidence after implementation:

- [ ] "add a json mode": `grok message --json`, `--format json`, and resource `--json` tests pass.
- [ ] "make the cli more scriptable": stdout contains only JSON/NDJSON in JSON mode; stderr handles progress/debug; exit codes are documented and tested.
- [ ] "analyze all commands": command matrix in this plan covers `chat`, `message`, `auth`, `list`, `models/modes`, `agents`, `tasks`, `skills`, `workspaces/workspace`, `files`, `test`, `help`, and interactive-only commands.
- [ ] "and sub commands": subcommand matrices cover auth, agents, tasks, skills, workspaces, and files.
- [ ] "what they return": current return shapes and target JSON categories are documented in the matrices.
- [ ] "all permutations": shared options, `--json`, `--format json`, stream/non-stream, debug, help, errors, interactive boundaries, and resource mutations are represented in test gates.
- [ ] "create a plan spec": this file exists under `plans/2026-05-13-cli-json-mode-plan.md`.
- [ ] Project convention: after implementation, build, full tests, diff check, and `Scripts/install_cli.sh` have been run.
