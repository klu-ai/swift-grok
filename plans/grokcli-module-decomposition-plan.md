# GrokCLI Module Decomposition Plan

## Goal

Split `Sources/GrokCLI/GrokCLI.swift` into focused Swift files that make the CLI easier to extend, test, and review without changing user-facing behavior in the first pass.

The immediate target is file-level modularity inside the existing `GrokCLI` SwiftPM target. Do not create new SwiftPM targets yet. The code is still changing quickly, and a target split would add package wiring before the boundaries have settled.

## Execution Baseline Update

Updated on 2026-05-13 before execution.

- [x] Re-checked current repo state after the latest commit with `git status --short`.
- [x] Confirmed tracked source files are clean before decomposition; unrelated untracked files remain at `Scripts/__pycache__/` and `credentials-old.json`.
- [x] Confirmed `Sources/GrokCLI/GrokCLI.swift` still contains the router, interactive chat loop, output formatter, input reader, runtime app state, config manager, auth/list/message/test command handling, and parser helpers.
- [x] Confirmed existing flat command files remain present at `Sources/GrokCLI/AgentCommands.swift`, `Sources/GrokCLI/FileCommands.swift`, `Sources/GrokCLI/TaskSkillCommands.swift`, and `Sources/GrokCLI/WorkspaceCommands.swift`.
- [x] Confirmed the planned nested directories under `Sources/GrokCLI/Core`, `Sources/GrokCLI/Runtime`, `Sources/GrokCLI/Interactive`, `Sources/GrokCLI/Commands`, `Sources/GrokCLI/Parsing`, and `Sources/GrokCLI/Presentation` do not exist yet.
- [x] Confirmed `Sources/GrokCLI/TaskSkillCommands.swift` still combines task and skill behavior and must be split.
- [x] Confirmed `Package.swift` already includes the `GrokCLIE2ETests` target and no package target split is needed for this work.

## Execution Results

Completed on 2026-05-13.

- [x] Created the planned CLI directories under `Sources/GrokCLI/Core`, `Sources/GrokCLI/Runtime`, `Sources/GrokCLI/Interactive`, `Sources/GrokCLI/Commands`, `Sources/GrokCLI/Parsing`, and `Sources/GrokCLI/Presentation`.
- [x] Replaced the flat `Sources/GrokCLI/GrokCLI.swift` monolith with focused files. `Sources/GrokCLI/Core/GrokCLI.swift` is now only the root namespace.
- [x] Moved top-level routing into `Sources/GrokCLI/Core/TopLevelRouter.swift`.
- [x] Moved runtime state and credential/config handling into `Sources/GrokCLI/Runtime/GrokCLIApp.swift`, `Sources/GrokCLI/Runtime/ConfigManager.swift`, and `Sources/GrokCLI/Runtime/CustomInstructions.swift`.
- [x] Added and adopted `Sources/GrokCLI/Runtime/ChatSessionState.swift` in the interactive chat loop.
- [x] Moved interactive parsing, command specs, model commands, menus, input handling, and session routing into `Sources/GrokCLI/Interactive/`.
- [x] Moved auth, message, list, test, agents, files, workspaces, tasks, and skills into `Sources/GrokCLI/Commands/`.
- [x] Split `TaskSkillCommands.swift` into `Sources/GrokCLI/Commands/TaskCommands.swift` and `Sources/GrokCLI/Commands/SkillCommands.swift`; removed the old combined file.
- [x] Centralized command option parsing in `Sources/GrokCLI/Parsing/OptionParsing.swift`.
- [x] Centralized row, summary, and JSON presentation helpers in `Sources/GrokCLI/Presentation/RowFormatting.swift`.
- [x] Moved streaming markup parsing and output rendering into `Sources/GrokCLI/Presentation/GrokStreamMarkupParser.swift`, `Sources/GrokCLI/Presentation/OutputFormatter.swift`, and `Sources/GrokCLI/Presentation/OutputFormatter+Tables.swift`.
- [x] Shared conversation list selection between top-level `grok list` and interactive `/list` via `GrokCLI.listAndSelectConversation(...)`.
- [x] Verified no CLI Swift source file is above 700 lines; the largest is `Sources/GrokCLI/Interactive/InteractiveSession.swift`.
- [x] Verification passed: `swift build --product grok`, `swift test --filter GrokCLIE2ETests`, `swift test`, `git diff --check`, and `Scripts/install_cli.sh`.
- [x] Installed binary smoke checks passed for `/Users/stephenwalker/.local/bin/grok --help`, `models`, `test hello`, and command help for `tasks`, `skills`, `agents`, `workspaces`, and `files`.

## Pre-Execution Shape

Before this decomposition, the CLI target mixed several concerns:

- Top-level command routing
- Interactive chat loop routing
- Interactive command parsing
- Prompt menus and pickers
- Model switching
- Custom instruction storage
- Terminal input and tab completion
- Output formatting and stream markup parsing
- API session state
- Credential storage and cookie extraction
- Command-specific parsing for tasks, skills, agents, files, and workspaces

`Sources/GrokCLI/GrokCLI.swift` was the main pressure point. It contained the core router, the chat loop, stream rendering, terminal input, app state, config management, and assorted helpers.

## Target Directory Structure

```text
Sources/GrokCLI/
  main.swift

  Core/
    GrokCLI.swift
    GrokCommandOptions.swift
    TopLevelRouter.swift
    CLIModelExtensions.swift

  Runtime/
    GrokCLIApp.swift
    ConfigManager.swift
    ChatSessionState.swift

  Interactive/
    InteractiveSession.swift
    InteractiveCommandParser.swift
    InteractiveCommandSpecs.swift
    InteractiveModelCommands.swift
    InteractiveMenus.swift
    InputReader.swift

  Commands/
    MessageCommand.swift
    AuthCommand.swift
    TestCommand.swift
    ListCommand.swift
    AgentCommands.swift
    TaskCommands.swift
    SkillCommands.swift
    WorkspaceCommands.swift
    FileCommands.swift

  Parsing/
    ShellArgumentSplitter.swift
    OptionParsing.swift
    ModelOptionParsing.swift

  Presentation/
    OutputFormatter.swift
    GrokStreamMarkupParser.swift
    RowFormatting.swift
    HelpText.swift
```

SwiftPM compiles source files recursively inside a target, so this structure should not require package manifest changes.

## File Responsibilities

### `Core/GrokCLI.swift`

Owns only the root namespace and the tiny entry point surface.

Keep:

- `struct GrokCLI`
- minimal `main()` forwarding if needed
- public static wrappers that must remain stable during migration

Move out:

- command dispatch
- interactive chat loop
- app state
- config management
- output rendering
- parsing helpers

End state: this file should be small enough to understand in one screen.

### `Core/GrokCommandOptions.swift`

Owns common top-level command flags.

Move here:

- `GrokCommandOptions`
- shared flag definitions for reasoning, deep search, markdown, debug, private mode, streaming, and model/mode selection

Do not put parsing behavior here. Keep it as a data container for argument-parser compatible options.

### `Core/TopLevelRouter.swift`

Owns shell invocation routing.

Move here:

- recognized top-level command list
- fallback-to-chat behavior for `grok how tall is the moon`
- `chat`, `message`, `auth`, `list`, `models`, `agents`, `tasks`, `skills`, `workspaces`, `files`, and `test` dispatch
- top-level help dispatch

This file should answer: “When the process starts, what command are we running?”

### `Core/CLIModelExtensions.swift`

Owns CLI-specific display helpers for API models.

Move here:

- `GrokWorkspace.cliResolvedId`
- `GrokWorkspace.cliDisplayName`
- `GrokAsset.cliDisplayName`
- any future CLI-only computed properties for client DTOs

Avoid adding business logic here. This is just display and ID convenience.

### `Runtime/GrokCLIApp.swift`

Owns in-memory CLI state and API access.

Move here:

- `GrokCLIApp`
- debug mode state
- current conversation state
- current personality
- current model
- current workspace
- attached file IDs
- `initializeClient()`
- `msg(...)`
- `loadConversation(conversationId:)`
- `saveCredentials(from:)`
- `generateCredentials(args:)`
- authentication error detection

This file should be the only object that combines CLI state with `GrokClient`.

### `Runtime/ConfigManager.swift`

Owns credential path management and cookie extractor execution.

Move here:

- `ConfigManager`
- config directory resolution
- credential file save/load path
- cookie extractor lookup
- cookie extractor process execution
- saved credential validation

Keep this file careful about not printing secrets.

### `Runtime/ChatSessionState.swift`

Add a new value type for mutable interactive settings.

Suggested shape:

```swift
struct ChatSessionState {
    var reasoning: Bool
    var deepSearch: Bool
    var noCustomInstructions: Bool
    var noSearch: Bool
    var privateMode: Bool
    var stream: Bool
    var mode: GrokMode
}
```

Then add computed helpers:

- `customInstructionsEnabled`
- `realtimeEnabled`
- `workspaceIds(app:)` if useful

This removes six-boolean parameter lists from status printing, routing, and message sending.

### `Interactive/InteractiveSession.swift`

Owns the interactive chat lifecycle.

Move here:

- `handleChatCommand(args:)`
- authentication preflight before the prompt
- initial message send
- main prompt loop
- routing from parsed interactive commands to command handlers
- message submission from interactive mode

The long switch inside the chat loop should live here, but it should delegate as much as possible to focused handlers.

### `Interactive/InteractiveCommandParser.swift`

Owns parsing input lines into interactive commands.

Move here:

- `InteractiveCommand`
- `interactiveCommand(from:)`
- `isBareInteractiveCommand(_:)`
- bare command allowlists
- command boundary handling
- slash stripping
- case normalization
- toggle word detection if it stays parser-owned

This file decides whether an input line is a command or a chat message. It should not execute commands.

### `Interactive/InteractiveCommandSpecs.swift`

Owns tab-completion metadata.

Move here:

- `CommandSpec`
- `interactiveCommandSpecs`
- any future command descriptions for autocomplete

Long-term, this file should become the single source of truth for interactive help and completion. For the first pass, just move it.

### `Interactive/InteractiveModelCommands.swift`

Owns interactive model selection.

Move here:

- `InteractiveModelCommand`
- `interactiveModelCommand(from:)`
- `/model`, `/models`, `/mode`, `/modes` interpretation
- `printAvailableModels(currentMode:)` if it remains tied to model routing
- model picker integration with `InteractiveMenus`

Keep raw web mode ID support here.

### `Interactive/InteractiveMenus.swift`

Owns user selection prompts.

Move here:

- model selection menu, if not kept in model commands
- workspace picker
- attachment picker
- personality picker

This file should contain blocking prompt flows that require user selection.

### `Interactive/InputReader.swift`

Owns terminal input.

Move here:

- `InputReader`
- raw terminal mode setup
- arrow keys
- history
- tab completion rendering
- fallback `readLine()`
- `processExit(...)` helper and platform fd constants if they are only used by input handling

This file should not know about Grok API behavior.

### `Commands/MessageCommand.swift`

Owns one-shot message mode.

Move here:

- `MessageCommand`
- `handleMessageCommand(args:)`
- one-shot message option parsing that is not generic enough for `Parsing/`

Future improvement: unify this with the chat initial-message path after the file split is stable.

### `Commands/AuthCommand.swift`

Owns auth commands.

Move here:

- `AuthCommand`
- `handleAuthCommand(args:exitOnGenerateFailure:)`
- `printAuthUsage()`

Auth should call `GrokCLIApp` and `ConfigManager`; it should not own credential storage details.

### `Commands/TestCommand.swift`

Owns diagnostic test command.

Move here:

- `TestCommand`

Keep this isolated because it is a diagnostic affordance, not core app flow.

### `Commands/ListCommand.swift`

Owns conversation listing and loading.

Move here:

- `handleListCommand(args:)`
- the conversation picker currently embedded in interactive `/list`

Target extraction:

```swift
static func listAndSelectConversation(app: GrokCLIApp, debug: Bool) async throws
```

Then both top-level `grok list` and interactive `/list` can reuse it.

### `Commands/AgentCommands.swift`

Keep the current agent command surface here.

Owns:

- `handleAgentsCommand(args:)`
- agent customization parsing
- agent customization merging
- agent ID validation
- agent instruction file reading
- agent display output
- agent usage text

Later cleanup: move generic option parsing and JSON/row printing out.

### `Commands/TaskCommands.swift`

Split this out from `TaskSkillCommands.swift`.

Owns:

- `handleTasksCommand(args:)`
- `TaskAction`
- `ParsedTaskCommand`
- `TaskCreateOptions`
- task-specific parsing
- task-specific usage text
- task display summaries

### `Commands/SkillCommands.swift`

Split this out from `TaskSkillCommands.swift`.

Owns:

- `handleSkillsCommand(args:)`
- `SkillsAction`
- `ParsedSkillsCommand`
- skill-specific parsing
- skill-specific usage text
- skill display summaries

### `Commands/WorkspaceCommands.swift`

Keep workspace command behavior here.

Owns:

- `handleWorkspacesCommand(args:)`
- workspace list/create/add/delete/conversation parsing
- workspace-specific usage text
- workspace summary display

Later cleanup: move shared JSON and row helpers out.

### `Commands/FileCommands.swift`

Keep file and asset command behavior here.

Owns:

- `handleFilesCommand(args:)`
- file upload parsing
- file list parsing
- MIME inference
- file/asset usage text
- asset summary display

### `Parsing/ShellArgumentSplitter.swift`

Owns shell-like splitting for interactive commands.

Move here:

- `splitCommandArguments(_:)`
- quote handling
- backslash escaping
- unclosed quote errors

This should be covered by direct unit tests because many interactive commands depend on it.

### `Parsing/OptionParsing.swift`

Create a shared helper for repeated command option parsing.

Current duplicate patterns:

- `removeFlag`
- `removeAgentFlag`
- `removeWorkspaceFlag`
- `removeFilesFlag`
- `optionNameAndValue`
- `agentOptionNameAndValue`
- `workspaceOptionNameAndValue`
- `filesOptionNameAndValue`
- `readOptionValue`
- `readAgentOptionValue`
- `readWorkspaceOptionValue`
- `readFilesOptionValue`

Suggested helper:

```swift
enum CLIOptionParsing {
    static func removeFlag(_ flag: String, from args: inout [String]) -> Bool
    static func nameAndValue(_ arg: String) -> (name: String, inlineValue: String?)
    static func readValue(_ inlineValue: String?, args: [String], index: Int, option: String) throws -> (String, Int)
}
```

Do this after the file move. First isolate files, then de-duplicate.

### `Parsing/ModelOptionParsing.swift`

Owns `--model` and `--mode` option parsing.

Move here:

- `applyModelOption(_:, nextValue:)`

Potential improved shape:

```swift
enum ModelOptionParsing {
    static func parse(_ arg: String, nextValue: String?) -> ModelOptionResult
}
```

### `Presentation/OutputFormatter.swift`

Owns terminal response rendering.

Move here:

- `OutputFormatter`
- response printing
- streaming response rendering
- markdown-ish formatting
- sources display
- terminal clear

Do not keep the stream markup parser nested in this file after the split.

### `Presentation/GrokStreamMarkupParser.swift`

Owns cleanup and summarization of Grok stream markup.

Move here:

- `StreamDisplayEvent`
- `GrokStreamMarkupParser`
- tool card summarization
- hidden preamble removal
- internal XML tag stripping
- render directive stripping

This is a good candidate for focused tests because it is easy to break while changing output behavior.

### `Presentation/RowFormatting.swift`

Owns shared table-ish row and summary helpers.

Move here:

- JSON pretty printing
- labeled summary printing
- JSON-backed value extraction helpers
- status and schedule formatting helpers

This should replace repeated summary helpers over time, but avoid making it too clever in the first migration.

### `Presentation/HelpText.swift`

Owns user-facing help strings.

Move here:

- top-level help
- interactive help
- command usage snippets if they are broad

Command-specific usage can stay in command files when it is tightly coupled to parser behavior.

## Migration Strategy

### Phase 0: Safety Baseline

Before moving files:

- Run `swift test`.
- Run a top-level smoke check:
  - `grok --help`
  - `grok models`
  - `grok test hello`
- Run an interactive smoke check with fake credentials if available.
- Capture current `git status --short` so unrelated worktree changes are visible.

No behavior changes in this phase.

### Step 1: Move Pure Presentation Code

Move first because it has minimal dependency on command routing.

Create:

- `Presentation/GrokStreamMarkupParser.swift`
- `Presentation/OutputFormatter.swift`

Move:

- `StreamDisplayEvent`
- `GrokStreamMarkupParser`
- `OutputFormatter`

Expected fixes:

- Add imports: `Foundation`, `GrokClient`, `Rainbow`
- Adjust private access if needed

Verify:

- `swift build --product grok`
- existing streaming formatter tests if any

### Phase 2: Move Terminal Input

Create:

- `Interactive/InputReader.swift`

Move:

- `InputReader`
- `processExit(...)`
- stdin/stdout fd constants if only used by `InputReader`

Expected fixes:

- Add platform imports: `Darwin` or `Glibc`
- Ensure tab completion can still see `GrokCLI.CommandSpec`

Verify:

- `swift build --product grok`
- interactive command autocomplete still compiles

### Phase 3: Move Runtime State

Create:

- `Runtime/ConfigManager.swift`
- `Runtime/GrokCLIApp.swift`
- `Runtime/ChatSessionState.swift`

Move:

- `ConfigManager`
- `GrokCLIApp`
- add `ChatSessionState`

Do not rewrite the chat loop yet. Introduce `ChatSessionState` only if it is low-risk; otherwise add the file with the type and adopt it in a later phase.

Verify:

- `swift build --product grok`
- auth-related tests

### Phase 4: Move Core Helpers

Create:

- `Core/GrokCommandOptions.swift`
- `Core/CLIModelExtensions.swift`
- `Parsing/ModelOptionParsing.swift`

Move:

- `GrokCommandOptions`
- CLI display extensions for `GrokWorkspace` and `GrokAsset`
- `applyModelOption(_:, nextValue:)`
- `String.removingPrefix(_:)` if only used by model parsing

Verify:

- `swift build --product grok`
- top-level model option tests

### Phase 5: Move Interactive Parser and Specs

Create:

- `Interactive/InteractiveCommandParser.swift`
- `Interactive/InteractiveCommandSpecs.swift`
- `Parsing/ShellArgumentSplitter.swift`
- `Interactive/InteractiveModelCommands.swift`

Move:

- `InteractiveCommand`
- `CommandSpec`
- `interactiveCommandSpecs`
- `interactiveCommand(from:)`
- `isBareInteractiveCommand(_:)`
- `toggleWords`
- `resolveToggle(current:args:usage:)`
- `splitCommandArguments(_:)`
- `InteractiveModelCommand`
- `interactiveModelCommand(from:)`
- `printAvailableModels(currentMode:)`

Recommended tests to add or keep green:

- quote-aware splitting
- bare command boundary checks
- `model this should remain chat`
- `models list`
- `/models`
- `/mode expert`
- `/taskslater should be chat`

Verify:

- `swift test --filter GrokCLIE2ETests`

### Phase 6: Move Menus

Create:

- `Interactive/InteractiveMenus.swift`

Move:

- `promptForModelSelection(currentMode:)`
- `showWorkspacePicker(app:)`
- `showAttachmentPicker(app:)`
- `showPersonalityMenu(app:)`
- `uploadAndAttachFile(path:app:)` if kept as an interactive helper

Decision:

- If `uploadAndAttachFile` is reused only by interactive `/attach upload`, keep it here.
- If top-level `files upload` starts sharing it, move it to `Commands/FileCommands.swift` or a small file service later.

Verify:

- `swift build --product grok`
- interactive workspace and attach smoke tests

### Phase 7: Split Existing Command Files

Create:

- `Commands/TaskCommands.swift`
- `Commands/SkillCommands.swift`

Move from `TaskSkillCommands.swift`:

- task code to `TaskCommands.swift`
- skill code to `SkillCommands.swift`
- shared row helpers temporarily to whichever file still compiles, then move in Phase 8

Move existing files into `Commands/`:

- `AgentCommands.swift`
- `WorkspaceCommands.swift`
- `FileCommands.swift`

Delete:

- empty `TaskSkillCommands.swift` after the split

Verify:

- `swift build --product grok`
- `swift test --filter GrokCLIE2ETests`

### Phase 8: Extract Shared Command Presentation and Parsing

Create:

- `Parsing/OptionParsing.swift`
- `Presentation/RowFormatting.swift`

Move repeated helpers:

- flag removal
- option name/value parsing
- option value reading
- pretty JSON printing
- labeled summary printing
- JSON-backed value extraction
- status and schedule formatting helpers

Adopt gradually:

1. Tasks and skills first, because they already share helpers.
2. Files next.
3. Workspaces next.
4. Agents last, because agent instruction parsing has more custom behavior.

Verify:

- focused parser tests if added
- full `swift test`

### Phase 9: Extract List and Auth Commands

Create:

- `Commands/AuthCommand.swift`
- `Commands/ListCommand.swift`
- `Commands/MessageCommand.swift`
- `Commands/TestCommand.swift`

Move:

- `AuthCommand`
- `handleAuthCommand`
- `printAuthUsage`
- `handleListCommand`
- shared list-and-select conversation function
- `MessageCommand`
- `handleMessageCommand`
- `TestCommand`

Verify:

- `grok auth --help` or equivalent usage path
- `grok list` with mocked/e2e server
- `grok message ...`
- `grok test hello`

### Step 10: Extract Interactive Session and Top-Level Router

Create:

- `Interactive/InteractiveSession.swift`
- `Core/TopLevelRouter.swift`
- `Presentation/HelpText.swift`

Move:

- `handleChatCommand(args:)`
- top-level `main()` command dispatch
- `showHelp()`
- `OutputFormatter.printHelp()` text or interactive help text

End state:

- root `GrokCLI.swift` is tiny
- all command handling lives in `Commands/` or `Interactive/`
- all rendering lives in `Presentation/`
- all app state lives in `Runtime/`

Verify:

- full `swift test`
- installed smoke test if desired

## Dependency Rules After Split

Recommended dependency direction:

```text
Commands/      -> Runtime/, Parsing/, Presentation/, GrokClient
Interactive/   -> Runtime/, Commands/, Parsing/, Presentation/, GrokClient
Core/          -> Commands/, Interactive/, Runtime/, Presentation/
Runtime/       -> GrokClient
Presentation/  -> GrokClient only for DTO display where needed
Parsing/       -> Foundation only where possible
```

Avoid:

- `Runtime/` depending on `Interactive/`
- `Runtime/` depending on `Presentation/`
- `Parsing/` depending on `Runtime/`
- command files calling terminal raw-mode input directly

## Access Control Cleanup

During the move, keep access control permissive enough to compile. After each phase, tighten it.

Preferred rules:

- Use `private` inside a file only when the helper truly should not be reused.
- Use `fileprivate` only when needed for same-file extensions.
- Use default internal visibility for helpers shared across files in the same target.
- Avoid `public` in the CLI target unless required by tests or external modules.

## Testing Plan

### Build Gates

Run after every phase:

```sh
swift build --product grok
```

Run after parser, interactive, or command phases:

```sh
swift test --filter GrokCLIE2ETests
```

Run at the end:

```sh
swift test
git diff --check
```

### Behavior Smoke Tests

Top-level:

```sh
grok --help
grok models
grok test hello
grok chat --model expert "hello"
grok "how tall is the moon"
```

Interactive non-network smoke:

```sh
printf 'models list\nmode expert\n/help\n/quit\n' | grok
```

Command surfaces:

```sh
grok tasks --help
grok skills --help
grok agents --help
grok workspaces --help
grok files --help
```

Only run real network/API checks when valid credentials are available.

## Risk Areas

### Interactive command routing

The interactive router has subtle behavior around bare commands versus chat messages. Preserve tests for:

- `models list`
- `mode expert`
- `model this should remain chat`
- `/taskslater should be chat`
- quoted paths in `/attach upload`
- whitespace and case-insensitive slash commands

### Authentication refresh

`GrokCLIApp.handleError` currently clears the client and may try browser credential refresh. Moving this into `Runtime/` must preserve behavior and avoid printing cookie values.

### Stream rendering

`OutputFormatter` and `GrokStreamMarkupParser` strip Grok internal tags while preserving visible answer text and tool summaries. Keep this move mechanical first.

### Workspace and attachment state

Workspace selection resets conversation state. File attachments are consumed after a successful message. Preserve both behaviors.

## Definition of Done

- `GrokCLI.swift` is reduced to a small namespace or entry-point file.
- No single CLI source file remains above roughly 700 lines unless it has a clear reason.
- `TaskSkillCommands.swift` is split into task and skill files.
- Shared option parsing is centralized.
- Shared row/JSON presentation helpers are centralized.
- Interactive routing is isolated from top-level routing.
- `swift test` passes.
- `git diff --check` passes.
- Installed `grok` still supports:
  - bare prompt invocation
  - interactive chat
  - model switching
  - tasks
  - skills
  - agents
  - workspaces
  - file uploads and attachments
  - auth generate/import

## Recommended First Pull Request Scope

Keep the first PR mechanical:

1. Move presentation code.
2. Move input reader.
3. Move runtime app/config code.
4. Move parser/spec code.
5. Move command files into folders.

Do not de-duplicate option parsing in the same PR unless the mechanical move is already small and clean. A behavior-preserving file split is easier to review and easier to bisect.

## Recommended Second Pull Request Scope

Clean up duplication after the file boundaries exist:

1. Introduce `CLIOptionParsing`.
2. Introduce `RowFormatting`.
3. Adopt `ChatSessionState`.
4. Share conversation list selection between top-level and interactive mode.
5. Tighten access control.

This keeps architectural motion separate from behavior cleanup.
