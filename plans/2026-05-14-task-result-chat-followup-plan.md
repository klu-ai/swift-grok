# Task Result Chat Follow-Up Plan

## Objective

Make task selection a staged flow:

- Selecting a task first shows the task prompt/details.
- From that detail view, offer next actions to return to the task list, view the most recent task result, inspect prior task runs, or open a selected task run's chat for follow-up.
- Preserve script-friendly commands such as `grok tasks show <taskId> --json` and `grok tasks results <taskId> --json`.

## Success Criteria

- [x] `grok tasks select` and interactive `/tasks` no longer fetch and print the latest result immediately after selection.
- [x] The selected task detail view clearly shows the task prompt first.
- [x] The next action picker includes return/back and latest-result actions.
- [x] Viewing the latest result calls `GET /rest/tasks/results/{taskId}?limit=1` and handles empty, wrapped, array, and nested response shapes.
- [x] Viewing run history can show previous runs, not only the latest one.
- [x] Interactive mode can view the latest task response and paginate left/right through previous and next runs without leaving the task detail flow.
- [x] Run history shows human-readable timestamps, such as `Today (2026-05-14 08:30)` or `Last week (2026-05-07 08:30)`, whenever run timestamps are available.
- [x] Opening a result chat works for the latest run and for a selected previous run when that run includes enough conversation context.
- [x] End-to-end CLI verification proves a previous run, not the latest run, can be opened and queried on its correct thread.
- [x] If a task result cannot be opened in chat because required IDs are absent, the CLI reports exactly which API field is missing.
- [x] Existing non-interactive JSON output remains parseable and backwards compatible.
- [x] After implementation, run build and install so the finished CLI is available from `PATH`.

## Implementation Status

Completed on 2026-05-14.

- Implemented prompt-first task selection with next actions for latest result, run history, open result chat, back, and done.
- Added task run history display with relative-plus-exact timestamps.
- Added `grok tasks results <taskId|taskName> --limit N`.
- Added `grok tasks chat <taskId|taskName> --run latest|previous|N|RESULT_ID [--message <text>]`.
- Added `includeThreads=true` support for response-node loading.
- Added CLI chat seeding so the next message continues the selected task run's conversation and parent response.
- Added defensive response-node inference for live task results that include `conversationId` but omit `responseId`.
- Implemented interactive run paging with left/right arrows and `h`/`l` fallbacks. The first implementation pages within the fetched run window rather than lazy-loading beyond it.

Verification evidence:

- `swift build`
- `swift test` passed: 276 tests, 0 failures, plus the Swift Testing proxy suite.
- `Scripts/install_cli.sh --user` installed `/Users/stephenwalker/.local/bin/grok`.
- `command -v grok` resolved to `/Users/stephenwalker/.local/bin/grok`.
- Live smoke: `grok tasks results "XAI News Check and Prompt Output" --limit 5` showed latest plus previous runs with `Today (...)`, `Last week (...)`, and older date labels.
- Live smoke: latest run chat used the expected task-result conversation ID and parent response ID.
- Live smoke: previous run chat used a different previous-run conversation ID and parent response ID, then answered from the older May 7 result content.

## Sanitization Note

The source curls included live browser/session headers and cookies. This plan intentionally records only endpoint shapes, methods, path parameters, payload keys, and known response fields. Do not commit `Cookie`, `sso`, `sso-rw`, `cf_clearance`, `__cf_bm`, `x-userid`, Sentry baggage, Statsig IDs, or request trace IDs.

## Current-State Findings

- [x] `Sources/GrokClient/Endpoints/GrokClient+Tasks.swift` already has `taskResultsResponse(taskId:limit:)`, `taskResults(taskId:limit:)`, and `latestTaskResult(taskId:)`.
- [x] `taskResultsResponse(taskId:limit:)` already accepts a custom `limit`, so previous runs can be requested by using a limit greater than `1`.
- [x] `Sources/GrokClient/Models/TaskModels.swift` already models `GrokTaskResult.conversationId` and `GrokTaskResult.responseId`.
- [x] `Sources/GrokClient/Parsers/GrokTaskParser.swift` already accepts result IDs, task IDs, conversation IDs, response IDs, status, message text, and nested `modelResponse.message`.
- [x] `Sources/GrokClient/Endpoints/GrokClient+Conversations.swift` already has `loadResponses(conversationId:specificResponseIds:)`.
- [x] `Sources/GrokClient/Endpoints/GrokClient+Conversations.swift` already has `getResponseNodes(conversationId:)`, but it does not yet expose the observed `includeThreads=true` query option.
- [x] `Sources/GrokClient/Endpoints/GrokClient+Chat.swift` already has `continueConversation(conversationId:parentResponseId:message:options:)`.
- [x] `Sources/GrokCLI/Runtime/GrokCLIApp.swift` already continues existing conversations by using `currentConversationId` and `lastResponseId`.
- [x] `Sources/GrokCLI/Commands/TaskCommands.swift` currently fetches the latest task result immediately for `.select`, `.show`, and interactive `/tasks`.
- [x] `Sources/GrokCLI/Commands/TaskCommands.swift` currently prints prompt and latest result together in `printTaskDetail`.
- [x] `Tests/GrokClientTests/GrokClientTests.swift` already verifies `GET /rest/tasks/results/{taskId}?limit=1`.
- [x] `Tests/GrokClientTests/GrokClientFactoryTests.swift` already verifies nested task result message extraction.

Relevant discovery commands:

```sh
rg -n "taskResultsResponse|latestTaskResult|loadResponses|getConversationV2|continueConversation" Sources/GrokClient Sources/GrokCLI Tests/GrokClientTests
rg -n "case \\.select|handleInteractiveTasksCommand|selectTask\\(|printTaskDetail|taskSelectUsage" Sources/GrokCLI/Commands/TaskCommands.swift Sources/GrokCLI/Interactive/InteractiveSession.swift
```

## API Documentation

### Latest Task Result

Known from the captured curl and current implementation.

```http
GET /rest/tasks/results/{taskId}?limit=1
Accept: */*
Cookie: <authenticated Grok browser/session cookies>
```

Current client method:

```swift
try await client.latestTaskResult(taskId: taskId)
```

Known response shapes handled today:

```json
{
  "results": [
    {
      "taskResultId": "result-1",
      "taskId": "task-123",
      "conversationId": "conv-123",
      "responseId": "resp-123",
      "summary": "Result text",
      "status": "COMPLETE"
    }
  ]
}
```

```json
{
  "data": {
    "id": "result-single",
    "task_id": "task-single",
    "conversation_id": "conv-single",
    "response_id": "resp-single",
    "output": "Result text"
  }
}
```

Accepted field variants:

- Result ID: `taskResultId`, `task_result_id`, `resultId`, `result_id`, `id`
- Task ID: `taskId`, `task_id`
- Conversation ID: `conversationId`, `conversation_id`
- Response ID: `responseId`, `response_id`
- Display text: `summary`, `message`, `content`, `output`, `text`, `result`, or nested `modelResponse.message`
- Status: `status`, `state`

### Task Run History

Known from the captured latest-result curl, existing client signature, and later task-thread captures.

```http
GET /rest/tasks/results/{taskId}?limit={count}
Accept: */*
Cookie: <authenticated Grok browser/session cookies>
```

Current client method:

```swift
try await client.taskResults(taskId: taskId, limit: count)
```

Use cases:

- `limit=1`: fetch the latest run.
- `limit>1`: fetch enough recent runs for a run picker, including previous runs.

Implementation notes:

- Preserve raw result JSON for every run.
- Sort/display runs using explicit timestamps when present; otherwise preserve API order and label rows by ordinal such as latest, previous, and older.
- Each run should carry, when available, `conversationId`, `responseId`, result/run ID, status, raw timestamp, human-readable timestamp label, and summary text.
- Timestamp labels should combine a friendly relative phrase with the exact timestamp, for example `Today (2026-05-14 08:30)`, `Yesterday (2026-05-13 08:30)`, `Last week (2026-05-07 08:30)`, or `May 1 (2026-05-01 08:30)`.
- The CLI needs a run-selection path so a user can choose a previous run and open that run's thread, not only the latest run.

### Load Specific Conversation Responses

Known from the captured curl and current implementation.

```http
POST /rest/app-chat/conversations/{conversationId}/load-responses
Content-Type: application/json
Cookie: <authenticated Grok browser/session cookies>

{
  "responseIds": ["response-id-1", "response-id-2"]
}
```

Current client method:

```swift
try await client.loadResponses(
    conversationId: conversationId,
    specificResponseIds: responseIds
)
```

Expected response shape:

```json
{
  "responses": [
    {
      "responseId": "response-id-1",
      "message": "Message text",
      "sender": "ASSISTANT",
      "createTime": "2026-05-13T21:58:08.392Z",
      "parentResponseId": "parent-response-id",
      "metadata": {}
    }
  ]
}
```

Interpretation: this endpoint loads existing response objects from an existing conversation. In the observed task click flow, Grok web loads two response IDs before the user's first follow-up in the task-derived thread.

### Response Nodes Including Threads

Known from the captured web click sequence. The existing client has the same endpoint without the query item.

```http
GET /rest/app-chat/conversations/{conversationId}/response-node?includeThreads=true
Cookie: <authenticated Grok browser/session cookies>
```

Proposed client update:

```swift
try await client.getResponseNodes(
    conversationId: conversationId,
    includeThreads: true
)
```

Use this after `conversations_v2` when opening a task-derived chat so the CLI can identify the thread response IDs the web app loads.

### Continue An Existing Chat

Known from current implementation, tests, and the captured follow-up after replying inside a thread that was based on a task result.

```http
POST /rest/app-chat/conversations/{conversationId}/responses
Content-Type: application/json
Cookie: <authenticated Grok browser/session cookies>

{
  "message": "Follow-up question",
  "parentResponseId": "response-id-to-continue-from",
  "...": "standard Grok web chat payload fields"
}
```

Sanitized live payload shape observed after replying to a task-based thread:

```json
{
  "message": "Follow-up text",
  "parentResponseId": "task-result-or-thread-response-id",
  "disableSearch": false,
  "enableImageGeneration": true,
  "imageAttachments": [],
  "returnImageBytes": false,
  "returnRawGrokInXaiRequest": false,
  "fileAttachments": [],
  "enableImageStreaming": true,
  "imageGenerationCount": 2,
  "forceConcise": false,
  "enableSideBySide": true,
  "sendFinalMetadata": true,
  "metadata": {
    "request_metadata": {}
  },
  "disableTextFollowUps": false,
  "isFromGrokFiles": false,
  "disableMemory": false,
  "forceSideBySide": false,
  "isAsyncChat": false,
  "skipCancelCurrentInflightRequests": false,
  "isRegenRequest": false,
  "disableSelfHarmShortCircuit": false,
  "collectionIds": [],
  "disabledConnectorIds": [],
  "deviceEnvInfo": {
    "darkModeEnabled": true,
    "devicePixelRatio": 2,
    "screenWidth": 1728,
    "screenHeight": 1117,
    "viewportWidth": 1728,
    "viewportHeight": 384
  },
  "modeId": "expert"
}
```

Current client method:

```swift
try await client.continueConversation(
    conversationId: conversationId,
    parentResponseId: responseId,
    message: message,
    options: options
)
```

This is enough to continue a task result's source conversation if the task result gives us both `conversationId` and `responseId`. The captured follow-up shows that once Grok web is in the task-derived conversation, deeper replies are normal conversation responses with `parentResponseId`.

### Conversation V2 With Task Result

Known from current implementation.

```http
GET /rest/app-chat/conversations_v2/{conversationId}?includeWorkspaces=true&includeTaskResult=true
Cookie: <authenticated Grok browser/session cookies>
```

Current client method:

```swift
try await client.getConversationV2(
    conversationId: conversationId,
    includeWorkspaces: true,
    includeTaskResult: true
)
```

This endpoint is part of the observed task-click and previous-run flow. It returns the conversation with task result context included; implementation should keep raw JSON and parse defensively for task result/run history.

Observed use cases:

- After selecting a task run, fetch the task-derived conversation with `includeTaskResult=true`.
- Use the raw JSON to locate task result context and, when available, all run references exposed for that task-derived conversation.
- For previous runs, use the run's response IDs with `load-responses` to fetch full details.

The current model only preserves raw JSON plus conversation ID, so implementation can start with raw JSON traversal and add typed fields later once live redacted response bodies are available.

### Previous Run Details

Known from the captured previous-run follow-up information.

To load the full details for a previous task run, Grok web posts the pair of response IDs for that run to `load-responses`:

```http
POST /rest/app-chat/conversations/{conversationId}/load-responses
Content-Type: application/json

{
  "responseIds": ["previous-run-thread-parent-response-id", "previous-run-result-response-id"]
}
```

Interpretation:

- `conversations_v2?includeTaskResult=true` and/or `response-node?includeThreads=true` provide the task-derived conversation context where run response IDs can be discovered.
- `load-responses` returns the full response bodies for a selected run.
- The first ID in the observed previous-run pair is the thread parent used for follow-up; the second ID is the run/result response body.
- For correctness, the implementation should store both IDs on the selected run context and continue with the parent ID, while showing the result body from the result ID.

### Observed Web Task-Click Sequence

This is the sanitized sequence observed when clicking a task in Grok web and landing in a chat with task context already attached:

1. List tasks:

```http
GET /rest/tasks
```

2. Fetch the latest result for the selected task:

```http
GET /rest/tasks/results/{taskId}?limit=1
```

For run history or previous-run selection, use a larger limit:

```http
GET /rest/tasks/results/{taskId}?limit={count}
```

3. Open the task-derived conversation with task result context:

```http
GET /rest/app-chat/conversations_v2/{conversationId}?includeWorkspaces=true&includeTaskResult=true
```

4. Refresh/list conversations for the sidebar:

```http
GET /rest/app-chat/conversations?pageSize=60
```

5. Fetch response nodes with thread data:

```http
GET /rest/app-chat/conversations/{conversationId}/response-node?includeThreads=true
```

6. Load the specific task-thread response bodies:

```http
POST /rest/app-chat/conversations/{conversationId}/load-responses
Content-Type: application/json

{
  "responseIds": ["thread-root-or-user-response-id", "task-result-response-id"]
}
```

For a previous run, use that previous run's response ID pair:

```json
{
  "responseIds": ["previous-run-thread-parent-response-id", "previous-run-result-response-id"]
}
```

7. Optionally refresh conversation/file context:

```http
GET /rest/app-chat/conversations_v2/{conversationId}?includeWorkspaces=true&includeTaskResult=true
GET /rest/conversations/files/list?conversationId={conversationId}&path=%2F
```

8. The first user query inside that task-derived thread posts to the normal responses endpoint. In the captured flow, `parentResponseId` was the first ID from the previous `load-responses` request:

```http
POST /rest/app-chat/conversations/{conversationId}/responses
Content-Type: application/json

{
  "message": "Follow-up question",
  "parentResponseId": "thread-root-or-user-response-id",
  "...": "standard Grok web chat payload fields"
}
```

## Do We Have Enough API Shape?

Enough for:

- [x] Showing a prompt-first task detail screen.
- [x] Fetching and showing the most recent result with `limit=1`.
- [x] Fetching multiple recent results by calling the same task results endpoint with `limit>1`.
- [x] Loading known response IDs from the result's conversation.
- [x] Continuing the result's existing conversation when `conversationId` and `responseId` are present.
- [x] Supporting the observed "go deeper from this task thread" behavior by seeding the CLI chat context to the task result conversation and posting the next message to `/responses` with `parentResponseId`.
- [x] Matching the observed web navigation shape: task list, latest result, task-result conversation V2, threaded response nodes, load specific responses, then continue via `/responses`.
- [x] Supporting previous-run follow-up in principle: select a non-latest run, load that run's response pair, seed the chat with the run's parent response, then continue via `/responses`.

Not fully proven for:

- [ ] The exact JSON bodies returned by `GET /rest/tasks/results/{taskId}?limit>1`, `GET /conversations_v2?includeTaskResult=true`, and `GET /response-node?includeThreads=true`; implementation should preserve raw JSON and parse defensively unless live redacted bodies are captured.
- [ ] The semantic meaning of the two loaded response IDs. The captured first follow-up uses the first loaded ID as `parentResponseId`, so implementation should prefer the web-observed parent if it can identify it from nodes, and fall back with a clear diagnostic.

Decision: implementation can proceed for an "Open result chat" feature that opens the task-derived conversation exactly enough for CLI use: fetch latest task result, inspect conversation V2 with task result context, fetch threaded response nodes, load the relevant response bodies, then set the active conversation and parent response so the next CLI message posts to `/responses`.

Additional API evidence that would improve tests, but should not block implementation:

- The JSON body returned by `GET /rest/tasks/results/{taskId}?limit>1`, with sensitive text redacted if needed but preserving field names and at least two runs.
- The JSON body returned by `GET /rest/app-chat/conversations_v2/{conversationId}?includeWorkspaces=true&includeTaskResult=true`, with messages/content redacted if needed but preserving task result/run keys and response IDs.
- The JSON body returned by `GET /rest/app-chat/conversations/{conversationId}/response-node?includeThreads=true`, with messages/content redacted if needed but preserving IDs, parent links, sender fields, and wrapper keys.

## Proposed UX

Task selection flow:

1. User runs `/tasks` or `grok tasks select`.
2. CLI opens the existing task picker.
3. After a task is selected, CLI prints the task prompt/details only.
4. CLI opens a next-action picker:
   - `Back to tasks`
   - `Show latest result`
   - `Show runs`
   - `Open result chat`
   - `Done`
5. `Show latest result` fetches `latestTaskResult(taskId:)`, prints it, then returns to the next-action picker.
6. `Show runs` fetches multiple runs, opens a run picker, and lets the user inspect or open a selected run.
7. `Open result chat` defaults to the latest result unless a specific run has been selected; it opens that run's task-derived conversation context, loads the threaded response context, seeds the interactive chat state, prints a short confirmation, and returns to the main chat prompt.

Interactive run viewer:

- After task selection, the user can choose `Show latest result` to enter a run viewer positioned on the latest run.
- The run viewer displays one run at a time: ordinal label such as `latest`, `previous`, or `older`, human-readable timestamp/status when available, summary/body, and whether chat context is available.
- Left/right arrow keys, and `h`/`l` as terminal-friendly fallbacks, move to previous or next runs.
- The viewer fetches more runs lazily when the user pages beyond the currently loaded window.
- The viewer offers actions for the currently visible run: open chat, copy/show IDs in debug output, return to task actions, or quit.
- Opening chat from the viewer must use the currently visible run's response ID pair, not always the latest run.

Non-interactive commands:

- Keep `grok tasks show <taskId>` as detail plus latest result unless explicitly changed later.
- Keep `grok tasks results <taskId>` as the direct latest-result command.
- Add or extend a script-friendly command for run history, for example `grok tasks results <taskId> --limit 10`.
- Consider adding `grok tasks chat <taskId> --run latest|previous|<resultId>` so smoke tests can open a previous run without driving the picker.

## Workstreams

### Workstream 1: Client/API Surface

Ownership: `Sources/GrokClient/Models/TaskModels.swift`, `Sources/GrokClient/Endpoints/GrokClient+Tasks.swift`, task parser tests.

- [ ] Add convenience fields or helpers for `GrokTaskResult` chat/run context if needed.
- [ ] Ensure `response_id` is covered by tests for singular and array results.
- [ ] Ensure `taskResults(taskId:limit:)` with `limit>1` preserves multiple runs and stable API ordering.
- [ ] Add parser coverage for captured live field names from the latest-result endpoint.
- [ ] Preserve raw JSON for fields the typed model does not yet understand.
- [ ] Add a small task-run context type for selected runs, including display label, result ID, conversation ID, thread parent response ID, result response ID, timestamp/status, and raw JSON.
- [ ] Add timestamp formatting helpers for run display that produce a relative label plus exact local timestamp.

### Workstream 2: Prompt-First Task Selection

Ownership: `Sources/GrokCLI/Commands/TaskCommands.swift`.

- [ ] Split task detail printing from result printing so selection can show prompt first.
- [ ] Add a task-next-action picker after selection.
- [ ] Implement `Back to tasks`, `Show latest result`, and `Done`.
- [ ] Implement `Show runs` with a run picker that includes latest and previous runs.
- [ ] Implement an interactive run viewer that starts at the latest response and pages left/right through previous and next runs.
- [ ] Support both arrow keys and `h`/`l` fallback keys for run paging, subject to existing terminal input capabilities.
- [ ] Avoid network calls for latest result until the user chooses `Show latest result` or `Open result chat`.
- [ ] Keep existing `grok tasks results <taskId>` behavior.
- [ ] Add a non-interactive way to target a previous run for verification, such as `--run previous` or `--result-id`.

### Workstream 3: Open Result Chat

Ownership: `Sources/GrokCLI/Runtime/GrokCLIApp.swift`, `Sources/GrokCLI/Commands/TaskCommands.swift`, interactive chat integration.

- [ ] Add a narrow app method to seed current chat context from a task result conversation.
- [ ] Use `conversationId` as the active conversation.
- [ ] Add `includeThreads: Bool = false` to `getResponseNodes(conversationId:)`.
- [ ] Fetch `getConversationV2(conversationId:includeWorkspaces:includeTaskResult:)` before seeding the chat so raw task context is available for diagnostics.
- [ ] Fetch `getResponseNodes(conversationId:includeThreads: true)` to mirror web task-thread loading.
- [ ] Load specific responses with `loadResponses(conversationId:specificResponseIds:)` to validate context and produce a preview.
- [ ] For a selected previous run, use that run's response ID pair with `loadResponses` rather than implicitly loading the latest run.
- [ ] Prefer the selected run's web-observed thread parent response ID when it is identifiable from the loaded nodes/responses; otherwise use the selected run's task result `responseId`.
- [ ] If no deterministic parent can be found, print a clear error listing the missing fields.
- [ ] Print a clear error if either required ID is missing.

### Workstream 4: Tests And Docs

Ownership: `Tests/GrokClientTests`, `Tests/GrokCLIE2ETests`, `README.md`, built-in help.

- [ ] Add unit tests for task result chat-context field decoding.
- [ ] Add CLI tests for prompt-first selection using mocked task/result responses.
- [ ] Add CLI tests for "show latest result" fetching only after selection action.
- [ ] Add CLI tests for listing multiple runs and selecting/opening a previous run.
- [ ] Add timestamp formatting tests for today, yesterday, last week, older same-year dates, and missing timestamp fallback.
- [ ] Add continuation tests proving the next message uses the task result conversation ID and response ID.
- [ ] Add continuation tests proving a previous run uses the previous run's response pair, not the latest run's IDs.
- [ ] Update README task examples.
- [ ] Update help text if new commands or picker wording are introduced.

## Dependencies

- Workstream 2 can start immediately because prompt-first selection mostly refactors CLI flow.
- Workstream 3 depends on Workstream 1 only if new result fields or helper APIs are needed.
- Workstream 4 should land with the implementation workstreams, not after the fact.
- Exact Grok-web parity depends on preserving the observed response-node/load-responses parent selection, with parser fallback until redacted JSON bodies are available.

## Concrete Implementation Steps

1. Refactor `printTaskDetail` into prompt/detail and optional latest-result rendering.
2. Change `.select` and interactive `/tasks` to print details without fetching the latest result.
3. Add a `TaskDetailAction` enum and picker loop.
4. Implement `Show latest result` by calling `latestResult(for:client:)` lazily.
5. Implement the interactive run viewer by calling `taskResults(taskId:limit:)` with an initial window, rendering the latest response first, and paging left/right through loaded or lazily fetched runs.
6. Implement `Show runs` by reusing the run viewer or by opening a run picker that can hand off to the same viewer.
7. Implement `Open result chat` for the selected/current visible run by validating `conversationId`, fetching `conversations_v2`, fetching threaded response nodes, loading the selected run's responses, selecting a deterministic continuation parent, and seeding app conversation state.
8. Add tests for task result ID decoding, multiple runs, run timestamp labels, `includeThreads=true`, load-responses payload ordering, previous-run payload ordering, run paging, and continuation parent selection.
9. Add tests or an E2E fixture for selected task action flow.
10. Update README/help text.
11. Run verification gates.
12. Install the CLI from the built artifact so the user can test from `PATH`.

## Verification Gates

Do not run these for this documentation-only plan. Run them after implementation:

```sh
swift build
swift test
Scripts/install_cli.sh --user
grok tasks select
```

Manual smoke checks after install:

- [ ] Selecting a task shows the prompt first.
- [ ] Choosing `Show latest result` fetches and prints the newest result.
- [ ] Choosing `Show runs` lists at least latest and previous runs when the API returns them.
- [ ] Run rows/viewer include friendly timestamp labels with exact timestamps when timestamps exist.
- [ ] In interactive mode, left/right paging moves between runs and keeps the currently visible run as the target for `Open result chat`.
- [ ] Choosing `Back to tasks` returns to the list.
- [ ] Choosing `Open result chat` opens the task-derived conversation when IDs are present.
- [ ] The next chat message posts to `/rest/app-chat/conversations/{conversationId}/responses` with the web-observed thread parent when available, otherwise a deterministic task result parent.
- [ ] Starting a chat from a previous run uses the previous run's conversation/response IDs, not the latest run.
- [ ] Missing result IDs produce actionable errors.

## Risks And Rollback Notes

- Risk: the two response IDs loaded by web may not always be ordered the same way. Mitigation: prefer explicit parent/thread relationships from `response-node?includeThreads=true`, and report ambiguity.
- Risk: run order from `taskResults(limit>1)` may be newest-first or oldest-first depending on API shape. Mitigation: use timestamps when present; otherwise preserve API order and label as API order in diagnostics.
- Risk: terminal arrow-key handling may conflict with existing picker/input code. Mitigation: support `h`/`l` fallback keys and keep paging inside the run viewer only.
- Risk: latest task results may omit `conversationId` or `responseId`. Mitigation: report missing fields and keep `Show latest result` working.
- Risk: previous runs may require response ID pairs only visible from `conversations_v2` raw task result context. Mitigation: preserve raw JSON and add targeted extraction for response ID pairs.
- Risk: current typed response-node parsing may not preserve enough thread metadata. Mitigation: preserve raw JSON or add narrow metadata fields when implementing `includeThreads`.
- Risk: changing `grok tasks show` output could break scripts. Mitigation: keep non-interactive command behavior stable and confine the prompt-first staged flow to selection.
- Risk: picker loops can be awkward in non-TTY contexts. Mitigation: only use the next-action picker for interactive selection.
- Rollback: revert the selection-flow changes while keeping client/parser tests for task result response fields.

## Final Completion Checklist

- [ ] User requirement: selecting a task shows the prompt first.
  Evidence: CLI selection test and manual `grok tasks select` smoke.
- [ ] User requirement: next option can return/back.
  Evidence: picker test or manual smoke.
- [ ] User requirement: next option can show most recent result.
  Evidence: endpoint test confirms `GET /rest/tasks/results/{taskId}?limit=1`; CLI smoke prints the result.
- [ ] User requirement: previous task run can be selected and opened.
  Evidence: CLI smoke against `XAI News Check and Prompt Output` starts a thread from a previous run, not latest, and records the selected run IDs.
- [ ] User requirement: interactive mode can page through task runs.
  Evidence: manual or E2E interactive smoke shows latest response first, then left/right navigation across previous and next runs.
- [ ] User requirement: run timestamps are useful context.
  Evidence: run viewer/list displays friendly relative labels plus exact timestamps when timestamps are available.
- [ ] User requirement: option to go deeper in chat.
  Evidence: next chat message continues in the task-derived conversation using the thread parent selected from task result/response-node context.
- [ ] User requirement: API docs saved.
  Evidence: this plan file exists and contains sanitized endpoint docs.
- [ ] Project requirement: after implementation, build and install.
  Evidence: final implementation report includes `swift build`, `swift test`, and install results.
