# CLI JSON Scripting Gaps Plan

Date: 2026-05-14

## Objective

Make `grok` JSON mode reliable enough for agent controllers to script non-interactive work, monitor long generations, compose multiple CLI calls, recover from errors, and assemble generated artifacts without reading human-oriented output.

Success means an agent can:

- [ ] Discover CLI capabilities without accidentally starting chat or sending a model request.
- [ ] Run every supported non-interactive command with stdout as valid JSON or valid NDJSON.
- [ ] Distinguish transport success from application success using both exit status and JSON fields.
- [ ] Stream progress, thinking/progress summaries, assistant deltas, final output, and errors as typed NDJSON events.
- [ ] Generate multi-file artifacts through a structured output path without scraping Markdown.
- [ ] Compose resource operations by passing returned IDs into later commands.
- [ ] Avoid accidental disclosure of private settings, instructions, cookies, or credentials.

## Black-Box Test Boundary

Discovery and testing were performed against the on-PATH CLI only. Source files, README files, tests, package metadata, and repository docs were not read.

Observed CLI path:

- `/Users/stephenwalker/.local/bin/grok`

Validation tools used:

- `jq` for JSON validation.
- Shell redirection to separate stdout and stderr.
- Temporary `/tmp` directories for generated artifacts.
- Local Python smoke tests for generated projects.

## Capability Model From the CLI Surface

The CLI is currently best modeled as four scriptable layers:

- **Message layer**: `grok message --json ...` returns one JSON result object; `grok message --stream --json ...` is intended to return NDJSON events.
- **Catalog layer**: `models`, `skills`, `agents`, `tasks`, `workspaces`, `files`, and `list` expose JSON list/detail shapes.
- **Mutation layer**: `agents set/clear`, `tasks create/archive`, `workspaces create/add-conversation/delete`, `files upload`, and `auth import/generate` expose JSON result envelopes.
- **Raw model-content layer**: generated content is still a string inside `data.message`; callers must parse or extract any nested JSON, Markdown, code fences, or base64 manifests themselves.

Common successful JSON envelope:

```json
{
  "ok": true,
  "schema": "grok.cli.result.v1",
  "category": "resource_list",
  "command": "models",
  "subcommand": "list",
  "meta": {
    "debug": false,
    "format": "json",
    "version": "1",
    "warnings": []
  },
  "data": {}
}
```

Common stream event envelope:

```json
{
  "schema": "grok.cli.event.v1",
  "sequence": 1,
  "event": "assistant_delta",
  "data": {}
}
```

## Compound Moves Proven

### Catalog Discovery

- [x] `grok models --json` returned valid JSON with current model and five available modes.
- [x] `grok models --format json` returned equivalent valid JSON.
- [x] `grok skills list --json`, `skills mine --json`, and `skills user --json` returned valid JSON.
- [x] `grok list --json` returned valid JSON with conversation summaries.
- [x] `grok list --conversation <conversationId> --json` returned valid `conversation_history` JSON with `data.responses`.

### Message Generation

- [x] `grok message --json --private ...` returned valid single-object JSON.
- [x] `grok message --format json --private ...` behaved like `--json`.
- [x] `grok message --stream --json --private ...` returned valid NDJSON in a successful case.
- [x] Explicit `--model fast` was reflected in `data.model`.
- [x] Invalid raw model IDs were accepted as custom mode IDs rather than rejected.

### Agent Mutation

- [x] Backed up agent 3 via `grok agents list --json`.
- [x] Ran `grok agents set 3 --instructions ... --json`.
- [x] Ran `grok agents set 3 --file ... --replace --json`.
- [x] Ran `grok agents clear 3 --replace --json`.
- [x] Restored agent 3 from the backed-up instructions.

Finding:

- `agents set` overwrote an existing agent even without `--replace`, so `--replace` does not currently provide an obvious safety gate.

### Task Mutation

- [x] `tasks create --json` created a task and returned a normalized ID.
- [x] `tasks archive <taskId> --json` archived the created task.
- [x] A date more than one year out returned a valid JSON API error.

Finding:

- Server error details are embedded as stringified JSON inside `error.message` and `error.rawMessage`.

### Workspace Mutation

- [x] `workspaces create --json` created a temporary workspace.
- [x] `workspaces add-conversation <workspaceId> <conversationId> --json` succeeded.
- [x] `workspaces conversation <conversationId> --json` returned valid JSON.
- [x] `workspaces delete <workspaceId> --json` cleaned up the temporary workspace.

Findings:

- Timestamp-like workspace names can be rejected as containing a phone number.
- `workspaces conversation` returned `data.raw.conversation` but no normalized workspace reference in the tested case.

### File Upload

- [x] `files upload <path> --mime text/plain --json` returned valid mutation JSON.
- [x] `files list --json --page-size 3` returned the uploaded file.

Finding:

- There is no visible `files delete` command, so scripted test assets cannot be cleaned up from the CLI.

### Auth

- [x] `auth import <bad-json-file> --json` returned valid JSON.
- [x] `auth generate --json` refreshed credentials in one workflow.

Findings:

- `auth import` accepted a deliberately non-credential JSON file as `ok: true`.
- `auth generate --json` emitted human progress lines before the JSON object on stdout, breaking strict JSON mode.

### Generated Python API Server Workflow

Artifact:

- `/tmp/grok-blackbox-api.3D5PA3`

Generated project:

- `/tmp/grok-blackbox-api.3D5PA3/generated_project/server.py`
- `/tmp/grok-blackbox-api.3D5PA3/generated_project/smoke_test.py`
- `/tmp/grok-blackbox-api.3D5PA3/generated_project/README.md`

Proof files:

- `/tmp/grok-blackbox-api.3D5PA3/transcript.jsonl`
- `/tmp/grok-blackbox-api.3D5PA3/grok_raw/`
- `/tmp/grok-blackbox-api.3D5PA3/decoded_manifest.json`
- `/tmp/grok-blackbox-api.3D5PA3/verification_results.json`

Flow:

- [x] Controller asked Grok CLI for architecture and file plan.
- [x] Controller asked Grok CLI for a strict base64 manifest schema.
- [x] Controller asked Grok CLI to generate a base64 manifest for a stdlib-only Python project.
- [x] Controller decoded files into `/tmp`.
- [x] `py_compile` passed for generated Python files.
- [x] Server booted locally.
- [x] `GET /v1/models` returned `200`.
- [x] `POST /v1/chat/completions` non-stream returned `200`.
- [x] `POST /v1/chat/completions` with `stream: true` returned `text/event-stream`, SSE `data:` chunks, and `data: [DONE]`.

Findings:

- The bounded stdlib target worked in three Grok CLI calls with no fix calls.
- Earlier unbounded code-generation attempts took too long or required auth recovery.
- Raw generated JSON was unreliable for multiline files; base64-per-file manifests were much more robust.
- Even with `--json`, generated manifest JSON is nested inside `data.message`, so the controller still needs a second parse.

### Feature-Length Screenplay Workflow

Artifact:

- `/tmp/grok-blackbox-screenplay.mdhdal`

Generated package:

- `/tmp/grok-blackbox-screenplay.mdhdal/the_quiet_orbit_screenplay_package.md`

Flow:

- [x] Generated premise.
- [x] Generated logline.
- [x] Generated one-page treatment.
- [x] Generated character list.
- [x] Generated character arcs and backstories.
- [x] Generated scene beat sheet.
- [x] Generated six scene batches covering scenes 1-36.
- [x] Assembled a screenplay package.

Counts:

- 14 total `grok message` calls.
- 12 main screenplay workflow calls.
- 13 of 13 non-stream JSON calls returned valid JSON.
- Final package: about 12,099 words, roughly 48 pages at 250 words/page.
- Script section: about 7,042 words, roughly 28 pages.
- Beat sheet: 36 scenes.

Findings:

- Decomposed long-form generation works as a controller pattern.
- `grok message` starts fresh each call, so the controller must manually pass forward context.
- A true 90-page screenplay requires continuation, batching, state, and completion tracking.
- Streaming JSON failed in one auth-error case by mixing a valid first NDJSON event with a pretty-printed multi-line JSON error.

## Gaps And Fix Plan

### 1. Enforce Stdout Purity In JSON Mode

Problem:

- `auth generate --json` printed human progress lines to stdout before the JSON object.
- Successful JSON mode should reserve stdout for machine-readable output only.

Tasks:

- [ ] Route all progress, banners, debug logs, browser-cookie status, and human notes to stderr when `--json` is active.
- [ ] Add regression tests that run every JSON command through `jq -e .`.
- [ ] Add regression tests that run stream commands through strict line-by-line JSON parsing.
- [ ] Make `meta.warnings` carry warnings instead of printing them.

### 2. Make Streaming JSON Valid In Success And Error Cases

Problem:

- Successful stream mode can emit valid NDJSON.
- A streaming auth error emitted mixed output: a valid event line followed by pretty multi-line JSON, breaking NDJSON consumers.

Tasks:

- [ ] Guarantee every stdout line in `--stream --json` is one complete JSON event.
- [ ] Emit stream errors as `event: "error"` NDJSON with structured `error` fields.
- [ ] Emit a terminal `event: "done"` or `event: "aborted"` so controllers know the stream ended intentionally.
- [ ] Include `ok: false` or equivalent status on terminal error events.

### 3. Emit Thinking And Progress Events For Steerability

Problem:

- Long workflows are hard to monitor. Controllers wait without knowing whether Grok is planning, generating, blocked, or nearly done.
- Multi-stage agent workflows would be much easier to steer if streaming JSON exposed thinking/progress summaries.

Tasks:

- [ ] Add typed stream events such as `request`, `thinking_delta`, `thinking_summary`, `assistant_delta`, `artifact_delta`, `tool_progress`, `warning`, `error`, and `assistant_final`.
- [ ] Keep any private chain-of-thought policy-safe by emitting summaries, phase labels, or progress notes rather than raw hidden reasoning.
- [ ] Include monotonic `sequence`, timestamps, request ID, conversation ID when available, and token/byte counters.
- [ ] Let controllers request verbosity with flags such as `--json-progress minimal|normal|verbose`.
- [ ] Include estimated phase names for long generations: `planning`, `drafting`, `revising`, `formatting`, `finalizing`.

### 4. Align Exit Codes With JSON Error Status

Problem:

- Some errors returned process exit `0` while the JSON body reported `ok: false` and `error.exitCode: 2`.
- Scripts must inspect both exit status and JSON body.

Tasks:

- [ ] Ensure all `ok: false` results exit non-zero.
- [ ] Ensure `error.exitCode` matches the process exit code.
- [ ] Add tests for unknown singular/plural commands such as `task`, `archive`, and `archives`.

### 5. Make Global Options Position-Independent Or Documented

Problem:

- `grok --json models` and `grok --json message ...` fell through to the chat JSON guard.
- `grok message ... --json` worked.

Tasks:

- [ ] Parse app options before and after command names consistently.
- [ ] If position independence is not desired, reject misplaced global options with a precise usage error naming the intended command.
- [ ] Update help examples to show exact supported option placement.

### 6. Normalize `--json` And `--format json` Support

Problem:

- `models --format json` and `message --format json` worked.
- `agents/tasks/workspaces/files ... --format json` returned valid JSON errors rather than behaving like `--json`.

Tasks:

- [ ] Either support `--format json` everywhere `--json` is supported or remove it from those command surfaces.
- [ ] Include `supportedFormats` in help or JSON capability discovery.
- [ ] Add parity tests for `--json` and `--format json`.

### 7. Provide A First-Class Artifact Output Mode

Problem:

- Generated files arrive as prose inside `data.message`.
- Raw JSON file manifests are unreliable when the model emits fences, commentary, or malformed multiline strings.
- Base64 manifests work better but are a prompt convention, not a CLI feature.

Tasks:

- [ ] Add `grok message --json --artifact manifest` or similar to request a strict machine artifact schema.
- [ ] Support `data.artifacts[]` with `path`, `mimeType`, `encoding`, `content`, `sha256`, and `bytes`.
- [ ] Allow `--output-dir <dir>` to write artifacts directly while still returning a JSON manifest.
- [ ] Emit partial artifact events in streaming mode for large files.
- [ ] Add validation errors when requested artifact schemas are not satisfied.

### 8. Add Stateful Conversation Continuation For Scripts

Problem:

- `grok message` starts a fresh conversation each call.
- Controllers must manually pass forward premise, treatment, scene plans, prior code, errors, and constraints.

Tasks:

- [ ] Add `grok message --conversation <id> --json ...` for continuation.
- [ ] Add `grok message --new --json ...` to explicitly start a new thread.
- [ ] Return durable conversation metadata in a consistent place.
- [ ] Support appending files/assets or prior artifacts to a continuation call.

### 9. Improve Structured Error Details

Problem:

- API errors often contain JSON encoded as a string inside `error.message`.
- Callers must second-parse server messages to find codes and details.

Tasks:

- [ ] Add `error.source`, `error.httpStatus`, `error.apiCode`, `error.apiMessage`, and `error.details`.
- [ ] Preserve raw strings separately without forcing callers to parse them.
- [ ] Mark retryable auth/rate/network cases with `recoverable: true`.

### 10. Validate Auth Import And Keep Auth JSON Clean

Problem:

- `auth import` accepted a non-credential JSON file as `ok: true`.
- `auth generate --json` violated stdout purity.

Tasks:

- [ ] Validate credential schema before writing or reporting success.
- [ ] Return `ok: false` for malformed credential files.
- [ ] Never print cookie extraction progress to stdout in JSON mode.
- [ ] Avoid exposing credential values in JSON output; paths and status are enough.

### 11. Add Safe Redaction For Sensitive Resource Lists

Problem:

- `agents list --json` includes full agent instruction text and raw settings.
- This is valid JSON but risky for logs, CI, and agent-to-agent reports.

Tasks:

- [ ] Add `--redact` default behavior for sensitive fields or a `--include-sensitive` opt-in.
- [ ] Replace long instruction bodies with lengths and hashes by default.
- [ ] Apply redaction to auth, preferences, custom instructions, cookies, and raw account settings.

### 12. Make Mutations Safer And More Predictable

Problem:

- `agents set` overwrote an existing agent without requiring `--replace`.
- File upload has no visible delete command.
- Workspace and task server validation rules surface only after API calls.

Tasks:

- [ ] Make `--replace` enforce overwrite intent or remove it from the interface.
- [ ] Add dry-run or validation mode for mutations.
- [ ] Add `files delete <id> --json`.
- [ ] Return normalized validation codes for task date limits and workspace name rules.

### 13. Add Capability Discovery

Problem:

- Agents currently scrape help text to infer JSON support and command shapes.

Tasks:

- [ ] Add `grok capabilities --json`.
- [ ] Include commands, subcommands, option placement, supported formats, schemas, mutation safety, and stream event types.
- [ ] Include schema versions and deprecation metadata, such as `--no-search` being ignored.

## Recommended Workstreams

### Workstream A: JSON Transport Contract

- [ ] Enforce stdout purity for all result commands.
- [ ] Enforce strict NDJSON for all stream paths.
- [ ] Align exit codes and `ok`.
- [ ] Add transport-level regression tests.

Ownership boundary:

- CLI command dispatch, output routing, JSON/NDJSON emitters, and exit-code handling.

### Workstream B: Streaming Observability

- [ ] Add thinking/progress summary events.
- [ ] Add terminal `done` and structured `error` events.
- [ ] Add phase/timing/token counters.
- [ ] Add stream tests for success, auth error, invalid prompt, and network failure.

Ownership boundary:

- Message streaming pipeline and event schema.

### Workstream C: Artifact Generation

- [ ] Add structured artifact output schema.
- [ ] Add direct output directory support.
- [ ] Add artifact hash/size validation.
- [ ] Add examples for codegen and long-form writing workflows.

Ownership boundary:

- `message` command response shaping, file writing, and schema validation.

### Workstream D: Resource API Consistency

- [ ] Normalize `--format json`.
- [ ] Normalize list/detail/mutation data shapes.
- [ ] Redact sensitive resource data by default.
- [ ] Add missing cleanup commands such as `files delete`.

Ownership boundary:

- `agents`, `tasks`, `workspaces`, `files`, `skills`, `models`, and `list` command families.

### Workstream E: Auth And Safety

- [ ] Validate auth import schema.
- [ ] Clean `auth generate --json` stdout.
- [ ] Avoid secret leakage.
- [ ] Mark recoverable auth errors consistently.

Ownership boundary:

- Auth command family and credential handling.

## Verification Gates

- [ ] `for cmd in ...; do $cmd | jq -e .; done` passes for every non-stream JSON command.
- [ ] Every `--stream --json` command passes line-by-line JSON parsing in success and failure cases.
- [ ] Every `ok: false` response exits non-zero.
- [ ] Every command advertised with `--format json` behaves like `--json`.
- [ ] `auth generate --json` emits zero non-JSON bytes on stdout.
- [ ] `auth import bad.json --json` returns `ok: false`.
- [ ] `agents list --json` does not expose full private instructions unless explicitly requested.
- [ ] A controller can generate, decode, boot, and smoke-test a Python OpenAI-compatible server without scraping Markdown.
- [ ] A controller can generate a long screenplay package with streamed progress events and resumable checkpoints.

## Rollback Notes

- Keep `grok.cli.result.v1` stable while adding optional fields.
- Add new stream event types without removing existing `assistant_delta` and `assistant_final`.
- If redaction changes default JSON output, provide `--include-sensitive` for advanced local users.
- If `--format json` parity is risky, document unsupported commands and return a precise usage error.

## Final Evidence Checklist

- [x] All testing used the installed CLI rather than source inspection.
- [x] Catalog JSON commands were validated.
- [x] Message JSON and NDJSON commands were validated.
- [x] Agent, task, workspace, file, and auth mutation paths were exercised.
- [x] A real generated Python OpenAI-compatible API server was produced by Grok CLI calls and smoke-tested locally.
- [x] A decomposed screenplay package workflow was produced by Grok CLI calls.
- [x] Gaps include the requested need for thinking/progress streaming in JSON mode.
