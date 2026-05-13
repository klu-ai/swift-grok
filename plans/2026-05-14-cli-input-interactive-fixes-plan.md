# CLI Input And Interactive Scripting Fix Plan

Date: 2026-05-14

## Objective

Fix the non-JSON input and interactive scripting gaps found during on-path `grok` CLI testing, without reworking the separate JSON-mode effort.

The target is to make long-running controller workflows practical through:

- clean stdin and prompt-file input for `grok message`
- answer-only stdout for scriptable raw output
- quieter, parseable piped chat transcripts where explicitly requested
- reliable continuation/resume behavior for long multi-step artifact generation
- documentation and tests that lock the new contracts

## Success Criteria

- `cat prompt.md | grok message --raw` sends the exact prompt content and exits successfully.
- `grok message --raw --prompt-file prompt.md` sends the exact file content and exits successfully.
- `grok message --raw --quiet <prompt>` writes only assistant answer text to stdout; progress, warnings, debug, and errors go to stderr.
- Existing human default output remains friendly and recognizable for terminal users.
- Piped chat can be used in a documented scripting mode without prompt/UI noise on stdout.
- Interactive resume after loading a saved conversation is covered by tests and preserves the correct parent response ID.
- Existing JSON mode behavior remains intact and is not retested as part of this work except for regression preservation.
- README and built-in help document the new input modes and stdout/stderr behavior.
- Verification passes with focused CLI tests, full Swift tests, build, and install so the on-path `grok` can be tested.

## Current-State Findings

### Discovery Completed

- [x] Reviewed the on-path CLI gap report at `test-runs/on-path-cli/2026-05-13-input-interactive-gap-report.md`.
- [x] Confirmed current installed/built behavior: `printf '...' | grok message --raw ...` fails with usage status `2`.
- [x] Confirmed current raw one-shot behavior prints human banners/status to stdout before the answer.
- [x] Confirmed `swift test --filter GrokCLIE2ETests/testMessageCommandDefaultsToMarkdownAndSupportsRawOutput` passes, but it does not assert stdout cleanliness.
- [x] Inspected the live top-level router and message/chat implementations.
- [x] Used sub-agent discovery for three independent areas: message input parsing, interactive transcript behavior, and test/docs coverage.
- [x] Closed completed sub-agents after collecting findings.

### Relevant Commands Used

- `rg --files -g '!*build*' -g '!*.png' -g '!*.jpg'`
- `git status --short`
- `nl -ba Sources/GrokCLI/Commands/MessageCommand.swift`
- `nl -ba Sources/GrokCLI/Core/TopLevelRouter.swift`
- `nl -ba Sources/GrokCLI/Core/GrokCommandOptions.swift`
- `nl -ba Sources/GrokCLI/Parsing/OptionParsing.swift`
- `nl -ba Sources/GrokCLI/Parsing/ModelOptionParsing.swift`
- `nl -ba Sources/GrokCLI/Interactive/ChatCommand.swift`
- `nl -ba Sources/GrokCLI/Interactive/InteractiveSession.swift`
- `nl -ba Sources/GrokCLI/Interactive/InputReader.swift`
- `nl -ba Sources/GrokCLI/Interactive/InteractiveCommandParser.swift`
- `nl -ba Sources/GrokCLI/Presentation/OutputFormatter.swift`
- `nl -ba Sources/GrokCLI/Presentation/JSONOutput.swift`
- `nl -ba Sources/GrokCLI/Runtime/GrokCLIApp.swift`
- `nl -ba Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- `nl -ba Sources/GrokCLI/Presentation/HelpText.swift`
- `nl -ba Scripts/install_cli.sh`
- `.build/debug/grok message --help`
- `printf 'Reply exactly: STDINOK\n' | .build/debug/grok message --raw --no-custom-instructions --private`
- `.build/debug/grok message --raw --no-custom-instructions --private 'Reply exactly: OK'`
- `swift test --filter GrokCLIE2ETests/testMessageCommandDefaultsToMarkdownAndSupportsRawOutput`

### Code Findings

- [x] Live executable entry is `Sources/GrokCLI/main.swift` to `GrokCLI.main()` in `Sources/GrokCLI/Core/TopLevelRouter.swift`.
- [x] `TopLevelRouter.swift` routes `message` to `handleMessageCommand(args:exitOnError:)` in `Sources/GrokCLI/Commands/MessageCommand.swift`.
- [x] The `ArgumentParser` `MessageCommand` type exists, but the live route is the manual `handleMessageCommand` parser.
- [x] `handleMessageCommand` currently rejects empty args before option parsing, so stdin cannot be used as a fallback.
- [x] The live parser treats unrecognized tokens as message words and joins them with a single space.
- [x] `--raw`, `--markdown`, `--json`, and `--format` are parsed by `applyOutputFormatOption` in `Sources/GrokCLI/Parsing/ModelOptionParsing.swift`.
- [x] `OutputFormatter` prints `Thinking`, transient clear control codes, `Grok:`, trace/status lines, sources, debug info, and final blank lines to stdout.
- [x] `GrokCLIApp.handleError` prints errors, auth-refresh status, and debug details to stdout.
- [x] `InputReader.readLine(prompt:)` prints prompts to stdout even when stdin/stdout is not a TTY, then falls back to `Swift.readLine()`.
- [x] Existing JSON mode already suppresses human banners on stdout; preserve that behavior.
- [x] `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift` already supports piped stdin via `TestEnvironment.run(..., input:)` and captures stdout/stderr separately.
- [x] README and built-in help document JSON stdout cleanliness, but not stdin input, prompt files, quiet raw output, or clean piped chat scripting.

### Existing Worktree Notes

- [x] The worktree was dirty before this planning pass.
- [x] Existing modular CLI files under `Sources/GrokCLI/{Commands,Core,Interactive,Parsing,Presentation,Runtime}` appear to be part of ongoing local work.
- [x] Existing JSON-mode work and plans are present; this plan avoids duplicating that scope.

## Target Behavior

### Message Input Contract

`grok message` should resolve the prompt from exactly one source:

1. Message arguments.
2. `--prompt-file <path>` or `--prompt-file=<path>`.
3. Stdin, only when no message args and no prompt file are supplied and stdin is not a TTY.

Rules:

- Preserve newlines from prompt files and stdin exactly.
- Validate emptiness after trimming whitespace and newlines.
- Reject conflicting prompt sources with usage status `2`.
- Support `-` as a prompt-file value only if implementation wants an explicit stdin alias; if added, treat it as stdin and reject simultaneous piped fallback.
- Keep the current message-argument behavior for ordinary shell use.

### Output Contract

Keep human output as the default.

Add an explicit scripting mode:

- Preferred flag: `--quiet`.
- Scope: non-JSON `message` first; optionally piped `chat` after output infrastructure lands.
- In `message --raw --quiet`, stdout is assistant text only.
- Status, warnings, errors, debug, auth-refresh notices, `Calling Grok API`, `Sending`, `Thinking`, sources, and terminal control sequences go to stderr or are suppressed according to policy.
- `--quiet` without `--raw` can still render Markdown if desired, but the first implementation should prefer `--raw --quiet` as the documented scriptable text contract.

### Piped Chat Contract

Do not silently change normal interactive chat for terminal users.

For piped chat, choose one explicit path:

- Preferred: `grok chat --quiet --raw` suppresses prompts/status on stdout and emits assistant answers only.
- Keep slash-command effects and multiple input lines working.
- Exit commands still terminate the session.
- Errors go to stderr.

If this is too much for one pass, document that clean scripting should use `grok message --stdin/--prompt-file --quiet` and defer chat quiet mode behind tests.

### Continuation Contract

Long controller workflows should have a documented way to continue context:

- Existing interactive same-session follow-ups should continue to use `/responses`.
- Loading a conversation through `/list` and then sending a message should post to `/rest/app-chat/conversations/<conversationId>/responses`.
- The request should include the loaded latest response as `parentResponseId`.
- Scriptable one-shot resume can be deferred unless a simple flag is added, for example `grok message --conversation <id>`.

## Workstreams

These workstreams are divided so up to six agents can execute in parallel after approval. Each workstream has a narrow write scope. Agents should not revert unrelated local changes.

### Workstream 1: Prompt Source Resolution

Owner scope:

- `Sources/GrokCLI/Commands/MessageCommand.swift`
- `Sources/GrokCLI/Parsing/OptionParsing.swift`
- Optional new helper file under `Sources/GrokCLI/Parsing/`

Tasks:

- [x] Discover the live hook is `handleMessageCommand`, not the `ArgumentParser` command.
- [x] Discover the early empty-args guard blocks stdin fallback.
- [ ] Move the empty-message guard until after option parsing and prompt source resolution.
- [ ] Add parser support for `--prompt-file <path>` and `--prompt-file=<path>`.
- [ ] Add parser support for an optional explicit `--stdin` flag if the implementation wants opt-in stdin in addition to auto-pipe fallback.
- [ ] Add a helper, for example `PromptSourceResolver`, that returns:
  - resolved prompt string
  - source label for debug/metadata
  - usage errors for empty, missing, unreadable, or conflicting sources
- [ ] Read prompt-file contents with `String(contentsOfFile:)` or URL APIs and preserve internal newlines.
- [ ] Use existing tilde/path expansion patterns from `AgentCommands.swift` if available.
- [ ] Detect non-TTY stdin using the existing platform import pattern from `InputReader.swift`.
- [ ] Keep JSON-mode parsing and usage-error behavior intact, but do not expand this work into JSON feature design.
- [ ] Update `printMessageUsage()` to document stdin and `--prompt-file`.

Dependencies:

- Can start first.
- Coordinates with Workstream 2 for `--quiet` parsing because both touch message option parsing.
- Tests in Workstream 5 should land with or shortly after this.

Implementation notes:

- Recommended conflict rules:
  - message args plus `--prompt-file`: usage error
  - message args plus `--stdin`: usage error
  - `--prompt-file` plus `--stdin`: usage error
  - no args, no file, TTY stdin: current "Please provide a message" usage error
  - no args, no file, piped empty stdin: usage error
- Preserve exact stdin/file content for the API request, but use trimmed content for empty validation.

### Workstream 2: Output Policy And Quiet Raw Mode

Owner scope:

- `Sources/GrokCLI/Presentation/OutputFormatter.swift`
- `Sources/GrokCLI/Commands/MessageCommand.swift`
- `Sources/GrokCLI/Runtime/GrokCLIApp.swift`
- Optional new files under `Sources/GrokCLI/Core/` or `Sources/GrokCLI/Presentation/`

Tasks:

- [x] Discover all relevant non-JSON human output currently goes to stdout.
- [ ] Introduce a small output abstraction, for example:
  - `ConsoleOutput` with `stdout(_:)` and `stderr(_:)`
  - `OutputPolicy` with `.interactive`, `.human`, `.quietRaw`, `.json`
- [ ] Add `--quiet` parsing for `message`.
- [ ] In `message --raw --quiet`, suppress:
  - `Calling Grok API`
  - `Sending:`
  - `Thinking`
  - `Grok:`
  - terminal clear sequences
  - source count banners
  - trailing blank UI lines
- [ ] Route warnings and debug/status lines to stderr when quiet mode is active.
- [ ] Make errors print to stderr for quiet non-JSON commands.
- [ ] Ensure `NO_COLOR` and terminal color behavior remain unchanged for default human mode.
- [ ] Preserve current JSON stdout contract.
- [ ] Add tests for streaming and non-streaming quiet raw output if both are supported in this pass.

Dependencies:

- Depends lightly on Workstream 1 for shared option parsing if both add message flags.
- Workstream 3 should reuse the same output abstraction.
- Workstream 5 owns test assertions.

Implementation notes:

- Keep the first pass conservative: implement answer-only output for `message --raw --quiet` before trying to redesign every human output path.
- It is acceptable for default `--raw` without `--quiet` to keep current human headings if compatibility is preferred, but the plan recommends documenting `--raw --quiet` as the scriptable text mode.
- Avoid sending normal assistant answer text to stderr.

### Workstream 3: Piped Chat Cleanliness

Owner scope:

- `Sources/GrokCLI/Interactive/InteractiveSession.swift`
- `Sources/GrokCLI/Interactive/InputReader.swift`
- `Sources/GrokCLI/Interactive/ChatCommand.swift`
- `Sources/GrokCLI/Runtime/ChatSessionState.swift`
- `Sources/GrokCLI/Presentation/OutputFormatter.swift`

Tasks:

- [x] Discover `InputReader` prints prompts to stdout even for non-TTY input/output.
- [x] Discover `handleChatCommand` always prints startup/auth/status/prompt lines in non-JSON chat.
- [ ] Decide final first-pass behavior:
  - Option A: implement `chat --quiet --raw` as clean piped scripting mode.
  - Option B: leave chat human-first and document that scripts should use `message --stdin/--prompt-file --quiet`.
- [ ] If Option A is chosen, parse `--quiet` in `handleChatCommand`.
- [ ] Suppress `Enter your message:` and prompt output when quiet mode is active.
- [ ] Update `InputReader` so fallback/non-TTY reads do not print prompts when output is not a TTY or when policy is quiet.
- [ ] Ensure `/quit` and `/exit` do not write `Goodbye!` to stdout in quiet mode.
- [ ] Ensure quiet chat answer output is separated predictably between multiple responses.
- [ ] Keep default interactive chat output unchanged for TTY users.

Dependencies:

- Reuse Workstream 2 output policy.
- Tests in Workstream 5 should define the exact quiet transcript contract before implementation starts.

Implementation notes:

- If quiet chat prints multiple assistant answers to stdout, use a minimal delimiter contract such as one blank line between answers only if tests lock it.
- Do not add JSON-style structured events here; JSON scripting is separate work.

### Workstream 4: Continuation And Resume Semantics

Owner scope:

- `Sources/GrokCLI/Runtime/GrokCLIApp.swift`
- `Sources/GrokCLI/Commands/ListCommand.swift`
- `Sources/GrokCLI/Interactive/InteractiveSession.swift`
- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`

Tasks:

- [x] Discover same-session chat follow-up is already tested after an initial message.
- [x] Discover `GrokCLIApp.loadConversation(conversationId:)` sets `currentConversationId` and `lastResponseId` from loaded responses.
- [ ] Add or confirm tests for `/list`, selecting a conversation, then sending a follow-up.
- [ ] Assert follow-up request uses `/rest/app-chat/conversations/conv-e2e/responses`.
- [ ] Assert follow-up request body includes `parentResponseId == resp-e2e` when loaded history provides that latest response.
- [ ] If a one-shot resume flag is desired, design it separately as `grok message --conversation <id> <prompt>` or defer to a later plan.
- [ ] Document current supported resume workflow.

Dependencies:

- Can proceed in parallel with Workstreams 1 and 2.
- Does not depend on quiet output unless the tests combine resume with quiet mode.

Implementation notes:

- The current code likely already supports this through `loadConversation`; the first task may be mostly coverage.
- Treat any bug found here as higher priority because it directly affects long multi-step generation reliability.

### Workstream 5: E2E And Unit Coverage

Owner scope:

- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- Optional new test helper files under `Tests/GrokCLIE2ETests/`
- Optional unit-test additions for output/input helper types

Tasks:

- [x] Discover `TestEnvironment.run(..., input:)` already supports stdin pipes.
- [x] Discover test harness captures stdout and stderr separately.
- [ ] Add `testMessageReadsPromptFromStdinWhenNoArgs`:
  - run `grok message --raw --quiet` with `input: "stdin prompt\nsecond line\n"`
  - assert status `0`
  - assert mock request message preserves newlines
  - assert stdout contains only mock answer text
- [ ] Add `testMessageReadsPromptFromPromptFile`:
  - create `prompt.md` in `environment.scratchURL`
  - run `grok message --raw --quiet --prompt-file <path>`
  - assert exact file content is sent
- [ ] Add usage tests:
  - `grok message --prompt-file`
  - `grok message --prompt-file missing.md`
  - `grok message --prompt-file prompt.md inline text`
  - piped empty stdin
- [ ] Add `testMessageRawQuietKeepsStdoutAnswerOnly`:
  - assert no ANSI escapes
  - assert no `Calling Grok API`
  - assert no `Sending:`
  - assert no `Thinking`
  - assert no `Grok:`
  - assert no `Sources:`
- [ ] Add streaming quiet raw test if streaming quiet is implemented.
- [ ] Add piped chat quiet test if Workstream 3 Option A is chosen.
- [ ] Add resume-after-list test:
  - input `/list\n1\ncontinue loaded thread\n/quit\n`
  - assert follow-up request path and parent response ID.
- [ ] Add unit tests for `InputReader` prompt suppression if a testable TTY abstraction is introduced.
- [ ] Add unit tests for `OutputFormatter` answer-only rendering if an output sink abstraction is introduced.
- [ ] Keep existing JSON tests passing but do not add new JSON scripting tests for this plan.

Dependencies:

- Should define expected contracts before Workstreams 1 to 3 finalize implementation.
- Some tests can be added as failing tests first if the executor prefers test-driven implementation.

Verification commands:

- [ ] `swift test --filter GrokCLIE2ETests/testMessageReadsPromptFromStdinWhenNoArgs`
- [ ] `swift test --filter GrokCLIE2ETests/testMessageReadsPromptFromPromptFile`
- [ ] `swift test --filter GrokCLIE2ETests/testMessageRawQuietKeepsStdoutAnswerOnly`
- [ ] `swift test --filter GrokCLIE2ETests`
- [ ] `swift test`

### Workstream 6: Documentation, Help, Build, And Install

Owner scope:

- `README.md`
- `Sources/GrokCLI/Presentation/HelpText.swift`
- `Sources/GrokCLI/Core/TopLevelRouter.swift`
- `Scripts/install_cli.sh` only if install instructions need adjustment

Tasks:

- [ ] Update global help to show:
  - `grok message --prompt-file prompt.md`
  - `cat prompt.md | grok message --raw --quiet`
  - `--quiet` behavior
- [ ] Update `printMessageUsage()` to document:
  - stdin fallback
  - `--prompt-file <path>`
  - `--quiet`
  - conflict rules at a high level
- [ ] Update README "Basic Usage" with stdin and prompt-file examples.
- [ ] Update README "Useful options" with `--quiet`.
- [ ] Document stdout/stderr contract:
  - human mode may print UI/status to stdout
  - JSON mode reserves stdout for JSON
  - raw quiet mode reserves stdout for answer text
- [ ] Document clean scripting recommendation:
  - prefer `grok message --raw --quiet --prompt-file prompt.md`
  - prefer stdin for generated prompts
  - use chat quiet mode only if Workstream 3 ships it
- [ ] Document resume workflow for long artifact generation.
- [ ] After implementation is complete, run build and install so the user can test the on-path CLI:
  - `swift build`
  - `swift test`
  - `Scripts/install_cli.sh --user`
  - `which grok`
  - `grok message --help`

Dependencies:

- Should wait until Workstreams 1 to 4 settle exact flags and behavior.
- Build/install is an execution gate, not part of this plan-writing pass.

Implementation notes:

- Keep docs free of internal agent/Codex references.
- Do not claim `chat --quiet` exists unless it is actually implemented and tested.

## Dependencies Between Workstreams

- Workstream 1 can begin immediately and unlocks stdin/prompt-file functionality.
- Workstream 2 should define the output policy before Workstream 3 implements quiet chat.
- Workstream 3 depends on Workstream 2 unless the team chooses to defer piped chat cleanup.
- Workstream 4 can proceed independently and may be mostly test coverage.
- Workstream 5 should write expected contracts early, then track each implementation workstream.
- Workstream 6 should land after flags and behavior are stable, and should finish with build/install after implementation.

## Concrete Implementation Sequence

1. Add failing E2E tests for stdin, prompt-file, and raw quiet stdout.
2. Add prompt source resolution to `handleMessageCommand`.
3. Add `--prompt-file` and optional `--stdin` parsing.
4. Pass stdin/file prompts through to `app.msg` without newline loss.
5. Add a minimal output policy for `message --raw --quiet`.
6. Route quiet status/errors to stderr and keep answer text on stdout.
7. Update help for `message` input and quiet output.
8. Add continuation-after-list test and fix only if it fails.
9. Decide whether `chat --quiet --raw` ships now or is deferred.
10. If shipping quiet chat, reuse the output policy and suppress non-TTY prompts/status.
11. Update README and global help.
12. Run focused E2E tests.
13. Run full `swift test`.
14. Run `swift build`.
15. Run `Scripts/install_cli.sh --user`.
16. Run on-path smoke checks with the installed `grok`.

## Test And Verification Gates

### Focused CLI Contracts

- [ ] `printf 'hello\nworld\n' | .build/debug/grok message --raw --quiet` sends `hello\nworld\n`.
- [ ] `.build/debug/grok message --raw --quiet --prompt-file prompt.md` sends file contents exactly.
- [ ] `.build/debug/grok message --raw --quiet --prompt-file prompt.md extra` exits `2`.
- [ ] `.build/debug/grok message --raw --quiet` with empty stdin exits `2`.
- [ ] `.build/debug/grok message --raw --quiet hello` prints only answer text to stdout.
- [ ] Quiet stderr may include progress/errors, but stdout must not contain UI banners or ANSI control sequences.

### Interactive Contracts

- [ ] Default `grok` interactive output still shows human-friendly startup, prompt, and status text.
- [ ] Piped `grok chat --raw --quiet`, if implemented, does not emit prompts/UI banners on stdout.
- [ ] `/list` plus selection plus follow-up posts to the selected conversation response endpoint.

### Regression Gates

- [ ] Existing JSON stdout cleanliness tests still pass.
- [ ] Existing human raw and markdown tests still pass or are updated only for intentional `--quiet` behavior.
- [ ] Existing interactive command routing tests still pass.
- [ ] `swift test --filter GrokCLIE2ETests`
- [ ] `swift test`
- [ ] `swift build`
- [ ] `Scripts/install_cli.sh --user`
- [ ] On-path smoke:
  - `which grok`
  - `grok message --help`
  - `printf 'Reply exactly: OK\n' | grok message --raw --quiet`
  - `tmp=$(mktemp); printf 'Reply exactly: OK\n' > "$tmp"; grok message --raw --quiet --prompt-file "$tmp"`

## Execution Audit

Completed on 2026-05-14.

- [x] Prompt source resolution shipped for inline args, `--stdin`, auto-piped stdin fallback, and `--prompt-file`.
- [x] `message --raw --quiet` shipped with answer-only stdout for non-streaming and streaming paths.
- [x] Quiet mode routes/suppresses UI, status, warnings, debug, errors, auth-refresh notices, thinking text, and terminal control sequences away from answer stdout.
- [x] `chat --raw --quiet` shipped for clean piped chat scripting.
- [x] `/list` selection followed by another chat message is covered by E2E tests and preserves the loaded parent response ID.
- [x] README and built-in help document stdin, prompt files, `--quiet`, and stdout/stderr contracts.
- [x] Focused CLI tests passed:
  - `swift test --filter GrokCLIE2ETests/testMessageRawQuietReadsMultilinePromptFromStdin`
  - `swift test --filter GrokCLIE2ETests/testMessageRawQuietPromptFileReadsExactContents`
  - `swift test --filter GrokCLIE2ETests/testMessagePromptInputUsageErrors`
  - `swift test --filter GrokCLIE2ETests/testMessageRawQuietInlineMessageEmitsCleanAnswerOnlyStdout`
  - `swift test --filter GrokCLIE2ETests/testChatRawQuietPipedInputCreatesThenContinuesConversation`
  - `swift test --filter GrokCLIE2ETests/testInteractiveListSelectionResumesConversationForFollowUp`
- [x] Full CLI E2E suite passed: `swift test --filter GrokCLIE2ETests` executed 35 tests with 0 failures.
- [x] Full package suite passed: `swift test` executed 58 XCTest cases and 3 Swift Testing proxy tests with 0 failures.
- [x] Build passed: `swift build`.
- [x] Install passed: `Scripts/install_cli.sh --user`.
- [x] On-path smoke passed:
  - `which grok` resolved to `/Users/stephenwalker/.local/bin/grok`
  - `grok message --help` documented the new flags and contracts
  - `printf 'Reply exactly: OK\n' | grok message --raw --quiet` printed only `OK`
  - `grok message --raw --quiet --prompt-file /tmp/grok-prompt-smoke.txt` printed only `OK`
  - `printf 'Reply exactly: OK\n' | grok message --raw` exited successfully
  - `printf 'Reply exactly: CHATOK\n/quit\n' | grok chat --raw --quiet` printed only `CHATOK`

## Risks And Edge Cases

- Auto-reading stdin could surprise users who run `grok message` in a non-TTY environment accidentally. Mitigation: only fallback to stdin when there are no message args and no prompt file.
- `--quiet` may be mistaken as "no output." Mitigation: document it as "suppress UI/status; answer remains on stdout."
- Moving errors to stderr in quiet mode changes scripting behavior. Mitigation: scope to explicit quiet mode first.
- Raw quiet streaming can be tricky because trace/thinking chunks and answer chunks share the same formatter today. Mitigation: suppress traces in quiet raw mode unless a later flag opts into them.
- Piped chat can produce multiple assistant answers. Mitigation: either defer quiet chat or define a strict delimiter contract.
- Prompt-file and stdin content may contain trailing newlines that matter to prompts. Mitigation: preserve exact content for sending, trim only for empty validation.
- TTY detection is platform-specific. Mitigation: reuse the existing `Darwin`/`Glibc` import pattern from `InputReader.swift`.
- Existing JSON-mode code has its own stdout contract. Mitigation: keep JSON paths untouched except where shared output helpers require careful regression tests.
- The worktree is already dirty. Mitigation: execution agents must avoid reverting unrelated changes and review touched files carefully.

## Rollback Notes

- If stdin fallback causes compatibility concern, keep `--prompt-file` and require explicit `--stdin` for pipe input.
- If quiet output abstraction becomes too broad, rollback to a narrow `message --raw --quiet` path and defer chat cleanup.
- If piped chat cleanup destabilizes interactive behavior, revert Workstream 3 and document `message --stdin/--prompt-file --quiet` as the supported scripting path.
- If continuation-after-list test fails in a way that requires risky runtime changes, ship input/output fixes first and leave resume as a separate patch.
- Docs can be reverted independently from source changes if flag names change during implementation.

## Final Completion Checklist

- [x] User requirement: fix issues from the on-path CLI input/interactive gap report.
  - Evidence: stdin, prompt-file, raw quiet stdout, piped chat decision, and continuation tests pass.
- [x] User requirement: avoid JSON scripting scope.
  - Evidence: plan preserves JSON behavior but adds no new JSON scripting tests or features.
- [x] User requirement: make long controller workflows practical.
  - Evidence: prompt-file/stdin inputs support large prompts without shell-argument quoting; raw quiet stdout supports clean assembly.
- [x] User requirement: support interactive/input versions of the app.
  - Evidence: message stdin/file input works; piped chat behavior is either cleaned and tested or explicitly documented as deferred.
- [x] Project requirement: create a plan spec under `plans/`.
  - Evidence: this file exists at `plans/2026-05-14-cli-input-interactive-fixes-plan.md`.
- [x] Project requirement: plan is detailed enough for another agent to execute.
  - Evidence: workstreams include ownership, tasks, dependencies, concrete steps, tests, risks, and rollback notes.
- [x] Project requirement after execution: build and install so the user can test on path.
  - Evidence after execution should include `swift build`, `swift test`, `Scripts/install_cli.sh --user`, and on-path smoke results.
