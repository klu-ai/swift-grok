# Grok PATH Command Hill-Climb Plan

## Objective

Exercise the installed `grok` command from `PATH` across direct commands, interactive commands, scripting/JSON flows, and complex scenarios; record all findings; fix confirmed bugs; and keep iterating until the audited command surface is green.

## Success Criteria

- [x] Test the installed `grok` binary, not only the package build artifact.
- [x] Cover direct command permutations.
- [x] Cover interactive slash-command permutations.
- [x] Cover scripting-focused JSON, quiet, stdin, prompt-file, and exit-code permutations.
- [x] Cover complex multi-step scenarios.
- [x] Use only mock servers and disposable resources for destructive command coverage.
- [x] Record findings and fix decisions in this plan file.
- [x] Run full package tests after all patches.
- [x] Run build and install so the fixed CLI is available from `PATH`.
- [x] Re-run the installed PATH harness after install and confirm zero failures.

## Safety Rule For Delete Tests

Never test delete commands against existing personal account threads. Delete coverage must use one of these safe targets:

- Mock-server conversations only.
- Disposable test threads created inside the same test run, with IDs such as `conv-safe-delete-*` or `conv-test-*`.
- A freshly created live throwaway thread only if a future manual live test explicitly requires it.

No live delete was performed during this audit.

## Current-State Findings

### Workstream A: Direct Top-Level Commands

- [x] Covered `help`, `--help`, `models`, `modes`, `auth`, `chat`, `message`, `list`, `test`, unknown command fallback, and global option edges.
- [x] Found that top-level `grok --version` was not reserved and could fall through to the bare-message chat path.
- [x] Found that `grok models --help` loaded modes before printing help.
- [x] Found `grok test --help` was treated as a test message.
- [x] Found `grok agents show --json` emitted duplicated `Usage: Usage: ...`.
- [x] Found utility parse errors in JSON mode used `api_error` instead of `usage_error`.

### Workstream B: Message And Chat Commands

- [x] Covered `message`, bare message fallback, `chat`, stdin, prompt files, audio, model flags, output formats, streaming, quiet, JSON, and bad-option cases.
- [x] Found `grok chat --json` and `grok chat --format=json` returned JSON command `"message"` instead of `"chat"`.
- [x] Found non-JSON `grok chat --stdin` and `grok chat --prompt-file` treated unsupported options as message text.
- [x] Accepted current interactive EOF behavior as not a confirmed bug: `grok chat` with empty piped stdin exits cleanly because it is the interactive command with no initial message.

### Workstream C: Interactive Slash Commands

- [x] Covered `/help`, `/new`, `/model`, `/mode`, `/models`, `/resume`, `/tasks`, `/skills`, `/agents`, `/workspaces`, `/files`, `/attach`, `/private`, `/stream`, `/auth`, and `/delete` through mock-backed scripts.
- [x] Confirmed `/delete` only hit mock endpoint `DELETE /rest/app-chat/conversations/soft/<id>` in the audit.
- [x] Accepted raw mode IDs in `/model <id>` as intentional because the CLI supports raw Grok mode IDs.
- [x] Accepted `/private off` continuing the same current thread as a product decision rather than a confirmed implementation bug.

### Workstream D: Scripting Contract

- [x] Covered JSON envelopes, NDJSON streams, quiet mode, exit codes, stdin, prompt-file, auth JSON, resource JSON, and parse failures.
- [x] Main scripting probes passed after fixes.
- [x] Confirmed JSON/human banners are separated in existing tests.

### Workstream E: Audio, Auth, Files, And Resources

- [x] Found `auth import --quiet` was order-sensitive and did not fully honor quiet output.
- [x] Found `auth generate --quiet` still printed human status/success lines.
- [x] Found `chat --audio --json` returned command `"message"` through the chat alias.
- [x] Found `transcribe` printed progress before local validation errors.
- [x] Found `files upload --json` missing-path errors used JSON code `api_error`.
- [x] Found `list delete --json` makes a modes preflight call before delete; recorded as a later optimization candidate, not a failing bug.

### Workstream F: Complex Scenarios

- [x] Covered multi-command interactive flows with mock task/resource data and disposable delete IDs.
- [x] Found streaming model-access errors could render as `ThinkingError: ...` without a clean status boundary.
- [x] Confirmed complex mock scenarios exited successfully after fixes.

## Fixed Bugs In This Patch Set

- [x] Reserved top-level `--version` and `-v` so they print static version text without calling the chat fallback.
- [x] Changed `models --help` / `modes --help` to print help from static known modes without API preflight.
- [x] Added `grok test --help` handling.
- [x] Removed duplicated `Usage:` prefix from agent show/edit parse errors.
- [x] Returned `usage_error` for JSON parse errors in agents, files, and skills commands.
- [x] Made `auth import --quiet` order-insensitive and silent on success.
- [x] Made `auth generate --quiet` silent on success and suppress extractor output.
- [x] Preserved `"chat"` as the JSON command name for chat alias success and usage-error envelopes.
- [x] Rejected non-JSON `chat --stdin` and `chat --prompt-file` with usage errors instead of sending them as chat text.
- [x] Mapped transcribe local usage/input failures to exit code 2.
- [x] Validated transcribe local input before printing `Transcribing audio...`.
- [x] Cleared transient `Thinking` status before printing errors.

## Workstreams For Future Parallel Re-Runs

The audit is divided so up to 6 agents can run at once. Each workstream owns its own temp config, mock server, and disposable IDs.

### Agent 1: Direct Commands

- [ ] Use the installed `grok` from `PATH`.
- [ ] Create temp `HOME`, `GROK_CONFIG_DIR`, and mock `GROK_BASE_URL`.
- [ ] Exercise top-level static commands and command aliases.
- [ ] Verify help/version commands make no network requests.
- [ ] Verify unknown-command fallback behavior is documented and does not mask reserved flags.

### Agent 2: Message And Chat

- [ ] Cover `message`, bare message fallback, and `chat`.
- [ ] Cover `--json`, `--format json`, `--stream`, `--quiet`, `--stdin`, `--prompt-file`, `--audio`, `--model`, and invalid options.
- [ ] Verify JSON command identity is stable for `message` versus `chat`.
- [ ] Verify usage failures exit 2 and do not call chat endpoints.

### Agent 3: Interactive Slash Commands

- [ ] Run scripted interactive sessions against a mock server.
- [ ] Cover slash commands, bare commands, typo suggestions, model switching, file attachment, task/resource commands, and conversation state transitions.
- [ ] Create a mock/disposable thread before testing delete.
- [ ] Verify delete requests target only that safe mock/disposable thread.

### Agent 4: Scripting Contract

- [ ] Cover shell-friendly JSON envelopes and NDJSON event streams.
- [ ] Cover quiet stdout/stderr behavior.
- [ ] Cover exit codes for usage errors, auth errors, API errors, and streaming errors.
- [ ] Verify no human banners leak into JSON stdout.

### Agent 5: Auth, Audio, Files, Resources

- [ ] Cover auth import/generate with quiet and JSON combinations.
- [ ] Cover transcribe local validation, stdin, missing files, unknown extensions, JSON, raw output, and exit codes.
- [ ] Cover files/skills/agents/tasks/workspaces parse and API paths.
- [ ] Verify JSON parse errors use `usage_error`.

### Agent 6: Complex Scenarios

- [ ] Compose multi-step flows that mix model changes, privacy toggles, file attachments, task inspection, list/delete, auth refresh, and streaming.
- [ ] Verify complex scenarios do not leak raw mock payloads or personal IDs.
- [ ] Verify transient status rendering does not merge with error output.
- [ ] Record any behavior that needs a product decision separately from confirmed bugs.

## Verification Gates

- [x] Focused regression slice:
  `swift test --filter GrokCLIE2ETests.testTopLevelStaticCommandsAndReservedEdges --filter GrokCLIE2ETests.testMessageJSONModeEmitsSingleResultEnvelopeWithoutHumanBanners --filter GrokCLIE2ETests.testChatAndMessageUsageErrorsReturnStatusTwo --filter GrokCLIE2ETests.testAuthImportAndGenerateCommands --filter GrokCLIE2ETests.testJSONModeErrorsAuthAndUtilityCommands --filter GrokCLIE2ETests.testInteractiveModelAccessErrorDoesNotRefreshCredentials --filter GrokCLIE2ETests.testTranscribeCommandUsageErrorsReturnStatusTwo`
- [x] Transcribe-specific recheck:
  `swift test --filter GrokCLIE2ETests.testTranscribeCommandUsageErrorsReturnStatusTwo`
- [x] Full package test:
  `swift test`
- [x] Install fixed CLI:
  `Scripts/install_cli.sh`
- [x] Re-run installed PATH harness:
  `python3 /tmp/grok_path_harness.py`

## Risks And Edge Cases

- Bare unknown command fallback is intentionally chat-friendly, but reserved global flags must stay reserved to avoid accidental API calls.
- `--quiet` should suppress human success/progress lines, but JSON mode must still write its machine-readable envelope.
- Clearing transient status before errors must not remove streaming answer text. The helper only clears an active status line.
- Transcribe now prevalidates file existence, size, and format before progress output; actual file read still happens in `resolveAudioInput`.
- Raw mode IDs can look like typos. This remains accepted behavior unless the command UX changes.
- `list delete --json` currently may load modes before deleting. Leave as optimization unless it causes user-visible latency or failure.

## Rollback Notes

- If chat JSON compatibility requires the older `"message"` command value, revert only the `jsonCommandName` plumbing and associated tests.
- If `auth --quiet` consumers expected success text, restore success output only for non-quiet mode and document quiet as machine-safe silence.
- If transcribe prevalidation proves too strict for special file paths, narrow `validateTranscribeAudioFormatBeforeProgress` to only unknown-format and empty-path checks.
- If status-line clearing affects terminal rendering, limit `clearTransientStatusBeforeError()` calls to the interactive default-send and message command paths.

## Final Completion Checklist

- [x] Direct command permutations audited.
- [x] Interactive command permutations audited.
- [x] Scripting permutations audited.
- [x] Complex scenarios audited.
- [x] Delete tests constrained to safe mock/disposable threads.
- [x] Findings saved in `plans/2026-05-14-grok-path-command-hillclimb-plan.md`.
- [x] Full tests passed.
- [x] Build/install completed.
- [x] Installed PATH harness passed with zero failures.
