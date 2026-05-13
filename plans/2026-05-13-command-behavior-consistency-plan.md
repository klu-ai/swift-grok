# Command Behavior Consistency Fix Plan

Date: 2026-05-13

## Execution Result

Completed on 2026-05-13.

- CLI and interactive help/error behavior was implemented and covered by E2E tests.
- Proxy docs/scripts and model endpoint coverage were aligned with the current `proxy` product.
- Duplicate proxy route registration was removed.
- Verification passed with:
  - `swift build`
  - `swift test --filter GrokCLIE2ETests`
  - `swift test --filter GrokProxyTests`
  - `swift test`

## Objective

Make CLI, interactive chat commands, proxy command docs, and tests consistent across all command surfaces discovered in the command-behavior audit.

The plan targets user-facing issues found in `grok`, interactive slash/bare commands, command help/error routing, docs, scripts, and proxy command documentation. It does not change Grok API behavior except where needed to make command parsing and user feedback consistent.

## Success Criteria

- `grok <group> help`, `grok <group> --help`, and interactive `/<group> help` display help as normal output, not as `Error: ...`, for all command groups.
- `chat` and `message` have intentional help behavior. `grok chat --help` and `grok message --help` do not accidentally send `--help` as a Grok message.
- Subcommand-level help such as `grok tasks create --help` and `/files list --help` is either supported consistently or explicitly rejected with a plain usage/help response.
- Empty interactive commands have documented, intentional behavior:
  - list-oriented groups list by default.
  - picker/menu commands open pickers by default.
  - differences such as `/workspace` versus `/workspaces` are documented and tested.
- Unsupported command aliases such as `agents show`, `agents create`, and `agents delete` behave consistently in CLI and interactive slash mode, with clear user-facing messaging.
- Exit-status behavior is made intentional and tested or documented. Parser and usage failures should either return non-zero in top-level CLI mode or be explicitly documented as status `0`; the recommended fix is non-zero for top-level CLI parse errors while interactive mode continues.
- README, built-in help, proxy docs, Docker docs, and scripts match the actual products and behavior.
- E2E tests cover the fixed behavior for CLI and scripted interactive mode, and proxy tests cover `/v1/models`, `/models`, basic request validation, and command startup/documented paths where practical.

## Current-State Findings

### Completed Discovery

- [x] `Sources/GrokCLI/main.swift` contains the executable entry point and calls `GrokCLI.main()`.
- [x] The live CLI dispatcher is the manual switch in `Sources/GrokCLI/GrokCLI.swift`, not the `ArgumentParser` command tree.
- [x] Recognized top-level CLI commands are declared in `GrokCLI.main()`: `chat`, `message`, `auth`, `help`, `list`, `models`, `modes`, `agents`, `tasks`, `skills`, `workspaces`, `workspace`, `files`, `test`.
- [x] Unknown top-level CLI words become an initial interactive chat message.
- [x] Interactive command routing is defined by `interactiveCommand(from:)`, `isBareInteractiveCommand(_:)`, and the switch inside `handleChatCommand`.
- [x] Errors are generally printed through `GrokCLIApp.handleError`, which prefixes `Error: ` and may attempt auth refresh for auth-like errors.
- [x] Existing CLI E2E tests passed in the prior audit with `swift test --skip-build --filter GrokCLIE2ETests`.

### Relevant Files

- `Sources/GrokCLI/main.swift`: executable entry point.
- `Sources/GrokCLI/GrokCLI.swift`: top-level CLI dispatch, interactive routing, chat/message/auth/list/models/help, output formatter, central error handling.
- `Sources/GrokCLI/AgentCommands.swift`: agent command parser, help handling, mutation commands, JSON output.
- `Sources/GrokCLI/TaskSkillCommands.swift`: tasks and skills parsers, help-as-error behavior.
- `Sources/GrokCLI/WorkspaceCommands.swift`: workspace parser, help-as-error behavior.
- `Sources/GrokCLI/FileCommands.swift`: file parser, help-as-error behavior.
- `Sources/GrokProxy/entrypoint.swift`: proxy executable command registration.
- `Sources/GrokProxy/Services/Commands/ServeCommand.swift`: custom proxy `serve` command options.
- `Sources/GrokProxy/Services/GrokConfiguration.swift`: proxy credential loading.
- `Sources/GrokProxy/Models/OpenAI.swift`: `/v1/models` model response.
- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`: primary CLI and scripted interactive coverage.
- `Tests/GrokProxyTests/GrokProxyTests.swift`: thin proxy coverage currently limited mainly to `/hello`.
- `README.md`, `PROXY_README.md`, `DOCKER.md`, `Scripts/run_proxy_verbose.sh`, `Scripts/setup_proxy.sh`, `docker-compose.yml`, `Dockerfile`, `docker-entrypoint.sh`: docs and operational scripts.

### Current Command Issues

- `tasks help`, `skills help`, `workspaces help`, and `files help` throw `GrokError.apiError(usage)` and print as `Error: <usage>`.
- `agents help` is already a first-class help action and returns before client initialization.
- `auth help` is normal output and does not use the error path.
- `chat --help` and `message --help` are treated as message text.
- `tasks create --help`, `workspaces create --help`, `files list --help`, and similar subcommand help cases are usually treated as unknown options or extra args.
- `grok list --help` ignores `--help` and still lists conversations.
- `models --help` ignores the argument and prints the model list.
- CLI parse and usage errors are usually caught, printed, and then process exits `0`.
- Slash interactive commands route more aggressively than bare commands:
  - `/tasks nope` reaches the parser and prints an error.
  - `tasks nope` becomes chat text.
- Unknown slash commands fall through to chat instead of reporting unknown slash command.
- `/agents` lists agent customizations; there is no `/agents` interactive menu analogous to `/personality`.
- `/workspace` opens a picker, while `/workspaces` lists. This is intentional-looking but under-documented.
- README calls `grok how tall is the moon` a one-off question, but the code sends it as an initial interactive chat message and keeps the prompt open.
- `--stream` and `--no-custom-instructions` are implemented and tested but missing from README and some built-in help surfaces.
- Proxy docs mention stale commands and model IDs:
  - `PROXY_README.md` uses `swift run` and `swift run App --verbose`, but the package product is `proxy`.
  - Proxy model examples list legacy OpenAI/Grok IDs instead of `GrokMode.knownModes`.
  - Proxy credential path docs and scripts disagree with `GrokConfiguration`.
  - Docker docs describe `GENERATE_CREDENTIALS` and `docker-entrypoint.sh`, but the Dockerfile currently enters `./proxy`.
- Proxy endpoint tests do not cover `/v1/models`, `/models`, `/v1/chat/completions`, streaming shape, credential loading, or verbose/startup behavior.

### Discovery Commands Already Used

- `rg --files`
- `git status --short`
- `rg -n "case |func |struct |enum |throw |Help|help|usage|/agents|/personality|Command" Sources/GrokCLI Tests/GrokCLIE2ETests README.md PROXY_README.md DOCKER.md`
- `nl -ba Sources/GrokCLI/GrokCLI.swift`
- `nl -ba Sources/GrokCLI/AgentCommands.swift`
- `nl -ba Sources/GrokCLI/TaskSkillCommands.swift`
- `nl -ba Sources/GrokCLI/WorkspaceCommands.swift`
- `nl -ba Sources/GrokCLI/FileCommands.swift`
- `nl -ba Sources/GrokProxy/Services/Commands/ServeCommand.swift`
- `nl -ba Sources/GrokProxy/entrypoint.swift`
- `nl -ba Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- `rg -n "grok (chat|message|auth|list|models|modes|agents|tasks|skills|workspaces|workspace|files|help|test)|/agents|/personality|/tasks|/skills|/workspaces|/files|/auth|Usage: grok|Commands:" README.md PROXY_README.md DOCKER.md Sources -g '!GrokCLI.swift'`
- `swift test --skip-build --filter GrokCLIE2ETests`

## Target Behavior

### Help Semantics

Use these rules across command surfaces:

- Top-level help:
  - `grok help`, `grok --help`, `grok -h` print global CLI help.
- Group help:
  - `grok agents help`, `grok tasks help`, `grok skills help`, `grok workspaces help`, `grok files help`, and `grok auth help` print group help without `Error:`.
  - `/<group> help` does the same in interactive mode.
- Group flag help:
  - `grok agents --help`, `grok tasks --help`, `grok skills --help`, `grok workspaces --help`, `grok files --help`, and `grok auth --help` print group help without calling the API.
  - `/<group> --help` does the same in interactive mode.
- Subcommand help:
  - Support first-class help for subcommands with options:
    - `tasks create --help`
    - `tasks archive --help`
    - `skills list --help`
    - `skills mine --help`
    - `agents set --help`
    - `agents clear --help`
    - `agents sync-custom --help`
    - `workspaces create --help`
    - `workspaces add-conversation --help`
    - `workspaces delete --help`
    - `workspaces conversation --help`
    - `files list --help`
    - `files upload --help`
  - Print normal usage, not an error, and do not initialize the client.
- Chat/message help:
  - `grok chat --help` prints chat usage and exits.
  - `grok message --help` prints message usage and exits.
  - Preserve `grok --help` and `grok help` behavior.

### Error Semantics

- Top-level CLI parse/usage errors should return non-zero. Recommended status: `2`.
- Runtime/API errors should return non-zero in top-level CLI mode when the command cannot complete. Recommended status: `1`.
- Interactive command errors should print the error and continue the chat loop.
- Auth refresh behavior should remain unchanged for auth-like errors.
- Plain help should not be treated as an error and should return `0`.
- Unknown slash commands should either:
  - Preferably print `Unknown command: /name` and continue, with a hint to run `/help`.
  - Or remain as chat messages only if explicitly documented and tested.
- Bare commands should keep the current conservative behavior to avoid capturing ordinary chat text, but the supported bare command set should be documented.

### Empty Interactive Behavior

- Keep list defaults:
  - `/agents`: list agents.
  - `/tasks`: list tasks.
  - `/skills`: list skills.
  - `/workspaces`: list workspaces.
  - `/files`: list files.
- Keep picker/menu defaults:
  - `/personality`: open personality menu.
  - `/workspace`: open workspace picker.
  - `/attach`: open file picker.
  - `/model`, `/mode`, `/models`, `/modes`: open model picker.
- Document the difference between `/workspace` and `/workspaces`.
- Do not add an `/agents` menu in this change unless explicitly requested later. Instead, clarify that `/agents` is a management/list group, while `/personality` is a local picker.

## Workstreams

These can be assigned to up to six parallel agents. Write scopes are intentionally disjoint.

### Workstream 1: CLI Help And Error Control

Owner scope:

- `Sources/GrokCLI/GrokCLI.swift`
- Shared CLI helper types/functions if added in `Sources/GrokCLI/GrokCLI.swift`

Tasks:

- [ ] Add a small command-result or exit-status mechanism for top-level CLI handlers so usage/runtime failures can return non-zero without breaking interactive mode.
- [ ] Decide implementation shape:
  - Preferred: introduce a lightweight `CLIUsageError` / `CLIHelp` path or handler return enum rather than abusing `GrokError.apiError` for help.
  - Keep API/runtime `GrokError` behavior compatible with `handleError`.
- [ ] Update `GrokCLI.main()` to call top-level handlers in a way that can exit non-zero for top-level parse errors.
- [ ] Add explicit `grok chat --help` and `grok chat -h` handling before message parsing.
- [ ] Add explicit `grok message --help` and `grok message -h` handling before message parsing.
- [ ] Add explicit `grok list --help` and `grok list -h` handling.
- [ ] Decide and implement `models --help` behavior:
  - Recommended: print the model list plus a one-line usage, because the command has no subcommands.
- [ ] Preserve unknown top-level words as initial chat messages.
- [ ] Ensure `handleError` remains the central runtime/API error presenter.

Dependencies:

- Coordinate with Workstream 2 so group parsers can signal help without using API errors.
- Coordinate with Workstream 6 for expected exit codes.

Implementation notes:

- `processExit(_:)` already exists in `GrokCLI.swift`.
- Be careful with tests that currently assert status `0` for invalid cases. Those tests must be intentionally updated in Workstream 6 if non-zero parse status is adopted.

### Workstream 2: Group Parser Help Consistency

Owner scope:

- `Sources/GrokCLI/AgentCommands.swift`
- `Sources/GrokCLI/TaskSkillCommands.swift`
- `Sources/GrokCLI/WorkspaceCommands.swift`
- `Sources/GrokCLI/FileCommands.swift`

Tasks:

- [ ] Replace help-as-error behavior in tasks, skills, workspaces, and files with first-class help actions or normal early returns.
- [ ] Keep agents help as normal output, but align its structure with the other groups.
- [ ] Add subcommand usage strings where missing:
  - tasks list/create/archive
  - skills list/mine/user
  - agents list/set/clear/sync-custom
  - workspaces list/create/add-conversation/delete/conversation
  - files list/upload
- [ ] Add helper functions to detect `help`, `-h`, and `--help` at group and subcommand level.
- [ ] Ensure help requests do not initialize the Grok client.
- [ ] Ensure `--json`, `--debug`, and group-specific flags such as `--replace` do not swallow help in surprising ways.
- [ ] For unsupported agent verbs (`show`, `get`, `create`, `add`, `delete`, `remove`), print a clear unknown-command error plus the group usage.
- [ ] Decide whether `grok agents show <id>` should be added as an alias for listing one agent:
  - Recommended for this pass: do not add new API behavior; only clarify command boundaries.

Dependencies:

- Depends on Workstream 1 for final top-level error/exit behavior.
- Tests in Workstream 6 should lock in exact output snippets.

Implementation notes:

- Existing parsers currently remove flags globally before looking at the first command. Preserve that for compatibility unless it conflicts with `--help`.
- Consider returning `.help(String)` or `.usage(String)` parser actions rather than throwing.
- Keep `--json` output behavior for real API actions unchanged.

### Workstream 3: Interactive Router And UX Semantics

Owner scope:

- `Sources/GrokCLI/GrokCLI.swift`, specifically:
  - `interactiveCommand(from:)`
  - `isBareInteractiveCommand(_:)`
  - `splitCommandArguments(_:)`
  - interactive command switch inside `handleChatCommand`
  - `OutputFormatter.printHelp()`

Tasks:

- [ ] Decide unknown slash command behavior.
  - Recommended: unknown slash commands should print `Unknown command: /name` and continue, rather than being sent to Grok.
  - Preserve bare unknown text as chat text.
- [ ] Keep supported bare command behavior conservative.
- [ ] Document and test that bare `tasks nope` remains chat text unless the user uses `/tasks`.
- [ ] Ensure `/agents help`, `/tasks help`, `/skills help`, `/workspaces help`, `/files help`, and `/auth help` all show normal help and continue.
- [ ] Ensure `/personality` remains a menu and `/agents` remains list/manage, with help text explaining the difference.
- [ ] Ensure `/workspace` picker and `/workspaces` list behavior remains intentional and documented.
- [ ] Add interactive help entries for:
  - `/stream [on|off]`
  - `/custom-instructions [on|off]`
  - `/workspace` versus `/workspaces`
  - `/agents help`
  - `/tasks help`
  - `/skills help`
  - `/files help`
  - `/workspaces help`
- [ ] Make usage errors from interactive commands not trigger top-level non-zero exit.

Dependencies:

- Depends on Workstream 2 for group help results.
- Coordinate with Workstream 6 for scripted interactive tests.

Implementation notes:

- Avoid capturing normal prose like `model this should remain chat`; existing tests cover this.
- If changing unknown slash behavior, update tests that may currently treat unknown slash input as a chat message. Existing E2E checks `/taskslater should be chat`, which is a slash unknown and would need an intentional decision.

### Workstream 4: CLI Documentation And Built-In Help

Owner scope:

- `README.md`
- `Sources/GrokCLI/GrokCLI.swift` help text only

Tasks:

- [ ] Fix README language around `grok how tall is the moon`:
  - Either call it "start chat with an initial message" or change code later to make it truly one-off. Recommended for this plan: update docs to match current behavior.
- [ ] Ensure README documents `grok message` as the true one-off command.
- [ ] Add `--stream` and `--no-custom-instructions` to README useful options and built-in global help.
- [ ] Add `grok chat --help` and `grok message --help` examples if implemented.
- [ ] Document empty interactive command behavior:
  - `/agents`, `/tasks`, `/skills`, `/workspaces`, `/files` list.
  - `/personality`, `/workspace`, `/attach`, `/model` open pickers.
- [ ] Document `/agents` versus `/personality`:
  - `/agents` manages server-side fixed agent customizations.
  - `/personality` changes local chat personality for the current session.
- [ ] Document supported bare interactive commands and the slash command recommendation for command groups.
- [ ] Document exit-status behavior once Workstream 1 decides it.

Dependencies:

- Should land after Workstreams 1 to 3 settle exact behavior.

Implementation notes:

- Keep docs concise but complete.
- Do not mention internal Codex/subagent work in docs or git metadata.

### Workstream 5: Proxy Docs, Scripts, And Runtime Alignment

Owner scope:

- `PROXY_README.md`
- `DOCKER.md`
- `Scripts/run_proxy_verbose.sh`
- `Scripts/setup_proxy.sh`
- `Dockerfile`
- `docker-compose.yml`
- `docker-entrypoint.sh`
- Potentially `Sources/GrokProxy/entrypoint.swift`
- Potentially `Sources/GrokProxy/Services/Commands/ServeCommand.swift`
- Potentially `Sources/GrokProxy/Services/GrokConfiguration.swift`

Tasks:

- [ ] Decide the canonical proxy launch command:
  - Recommended: `swift run proxy serve` for local dev.
  - Also document `swift run proxy serve --hostname 0.0.0.0 --port 8080 --verbose`.
- [ ] Verify whether `proxy` with no args uses Vapor default serve and whether custom `serve` shadows only named `serve`.
- [ ] If custom `ServeCommand` should be the canonical default, update `entrypoint.swift` accordingly or document the distinction.
- [ ] Fix `PROXY_README.md` command examples:
  - Replace `swift run` and `swift run App --verbose` with product-correct commands.
  - Replace stale model IDs with actual modes from `GrokMode.knownModes`.
- [ ] Fix credential path docs:
  - Align docs and scripts with actual `GrokConfiguration` behavior.
  - Choose one canonical local path. Recommended: repo-root `credentials.json` for proxy dev and `/app/credentials.json` for Docker.
- [ ] Fix `Scripts/setup_proxy.sh` if it writes credentials to the wrong relative path.
- [ ] Fix `Scripts/run_proxy_verbose.sh` so `--verbose` reaches the proxy serve command rather than SwiftPM.
- [ ] Resolve Docker entrypoint mismatch:
  - Either wire `docker-entrypoint.sh` into `Dockerfile`/compose if credential auto-generation is still supported.
  - Or remove/update docs that describe unsupported `GENERATE_CREDENTIALS` behavior.
- [ ] Keep CORS/routes docs aligned with actual endpoints:
  - `/`
  - `/hello`
  - `/v1/models`
  - `/models`
  - `/v1/chat/completions`

Dependencies:

- Tests in Workstream 6 should validate docs-sensitive proxy behavior where practical.

Implementation notes:

- Be careful not to break current Docker startup while fixing docs.
- If adopting `docker-entrypoint.sh`, verify file permissions and runtime availability inside the final image.

### Workstream 6: Tests And Verification

Owner scope:

- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- `Tests/GrokProxyTests/GrokProxyTests.swift`
- Test helpers in the same test files

Tasks:

- [ ] Update CLI tests for group help:
  - `grok agents help`
  - `grok tasks help`
  - `grok skills help`
  - `grok workspaces help`
  - `grok files help`
  - Assert no `Error:` prefix for help.
- [ ] Add tests for group `--help`:
  - `grok tasks --help`
  - `grok skills --help`
  - `grok workspaces --help`
  - `grok files --help`
- [ ] Add tests for subcommand help:
  - `tasks create --help`
  - `agents set --help`
  - `workspaces create --help`
  - `files upload --help`
- [ ] Add tests for `chat --help` and `message --help`.
- [ ] Add tests for `list --help` and `models --help`.
- [ ] Update tests for top-level parse error exit codes if Workstream 1 adopts non-zero exits.
- [ ] Add interactive tests:
  - `/tasks help`
  - `/skills help`
  - `/agents help`
  - `/workspaces help`
  - `/files help`
  - unknown slash command behavior
  - bare unknown command behavior remains chat text, if preserved.
- [ ] Add tests for `/workspace` picker versus `/workspaces` list.
- [ ] Add tests that help commands do not hit the mock Grok API.
- [ ] Add proxy tests:
  - `GET /v1/models`
  - `GET /models`
  - `POST /v1/chat/completions` missing messages returns bad request.
  - invalid role returns bad request.
  - no user message returns bad request.
  - Optional: basic non-streaming success with injected/mock Grok client if feasible.
  - Optional: streaming SSE shape if current test architecture can support it cheaply.
- [ ] Add script-level smoke checks if practical:
  - `Scripts/run_proxy_verbose.sh` command construction.
  - `Scripts/setup_proxy.sh` target path behavior.

Dependencies:

- Test updates depend on Workstreams 1 to 5.

Verification commands:

- [x] `swift test --filter GrokCLIE2ETests`
- [x] `swift test --filter GrokProxyTests`
- [x] `swift test`
- [x] Manual smoke for help-only commands:
  - `.build/debug/grok help`
  - `.build/debug/grok chat --help`
  - `.build/debug/grok message --help`
  - `.build/debug/grok tasks help`
  - `.build/debug/grok tasks create --help`
  - `.build/debug/grok skills help`
  - `.build/debug/grok agents help`
  - `.build/debug/grok workspaces help`
  - `.build/debug/grok files help`
  - `.build/debug/proxy serve --help`

## Dependencies Between Workstreams

- Workstream 1 should define the top-level error/exit mechanism before Workstreams 2 and 6 finalize output and status expectations.
- Workstream 2 can proceed in parallel with Workstream 1 if it returns normal help actions without changing exit behavior yet.
- Workstream 3 can proceed after Workstream 2 exposes normal help behavior for groups.
- Workstream 4 should wait for Workstreams 1 to 3 to settle exact CLI and interactive behavior.
- Workstream 5 can proceed mostly independently.
- Workstream 6 should trail all implementation work, but test scaffolding and expected matrix can be drafted immediately.

## Concrete Implementation Sequence

1. Introduce a shared distinction between help/usage output and errors.
2. Convert tasks, skills, workspaces, and files group help from thrown `GrokError.apiError` to normal output.
3. Add subcommand-level help strings and early help exits.
4. Add explicit help handling to `chat`, `message`, `list`, and `models`.
5. Decide and implement top-level non-zero exit behavior for parse/runtime errors.
6. Decide and implement unknown slash command behavior.
7. Update interactive help and global help text.
8. Update README for CLI behavior.
9. Fix proxy docs and scripts.
10. Add and update CLI E2E tests.
11. Add proxy endpoint tests.
12. Run focused tests, then full `swift test`.

## Risks And Edge Cases

- Changing exit codes can break downstream scripts that relied on status `0` for parser errors.
- Changing unknown slash commands from chat messages to errors can break users who intentionally send slash-prefixed text to Grok. Mitigation: document escaping or allow `//text` to send a literal slash message if needed.
- Help detection can accidentally swallow legitimate message text if applied too broadly to `chat` and `message`. Keep help checks exact and only before message parsing.
- Group-level global flag stripping can make `--help` ordering surprising. Add tests for both `grok tasks --help` and `grok tasks help`.
- Auth refresh is coupled to `handleError`; do not bypass it for real API errors.
- Proxy command behavior is partly owned by Vapor/ConsoleKit. Validate actual command behavior before changing docs or entrypoint semantics.
- Docker entrypoint changes can break image startup. Test container startup if Docker is available.

## Rollback Notes

- CLI parser/help changes are mostly isolated to `Sources/GrokCLI/*.swift`; revert those files if command behavior regresses.
- If non-zero exit code changes are too disruptive, keep normal help changes and defer exit code changes behind a documented compatibility decision.
- Proxy docs/script changes can be reverted independently from CLI changes.
- Docker entrypoint changes should be a separate commit or clearly separable patch if implemented, because they have operational blast radius.

## Final Completion Checklist

- [x] User requirement: fix help-as-error cases.
  - Evidence: `grok tasks help`, `grok skills help`, `grok workspaces help`, and `grok files help` print help without `Error:`.
- [x] User requirement: analyze and fix cases like `/agents` versus `/personality`.
  - Evidence: `/agents` and `/personality` behavior is documented in interactive help and README, with tests for both.
- [x] User requirement: cover all commands in CLI and interactive modes.
  - Evidence: `GrokCLIE2ETests` includes help, empty, invalid, and success-path cases for top-level, group, slash, and supported bare commands.
- [x] User requirement: fix docs mismatches.
  - Evidence: README no longer mislabels `grok <message>` as one-off, implemented flags are documented, proxy docs use correct product and model IDs.
- [x] User requirement: fix proxy command/docs issues.
  - Evidence: proxy docs/scripts match `Package.swift`, `entrypoint.swift`, `ServeCommand`, and `GrokConfiguration`; proxy tests cover model and validation endpoints.
- [x] User requirement: preserve confidence via verification.
  - Evidence: `swift test --filter GrokCLIE2ETests`, `swift test --filter GrokProxyTests`, and `swift test` pass or any environment blockers are documented.
