# High Quality CLI CUI and HUD Implementation Plan

## Objective

Implement a more highly designed interactive terminal experience for the Swift `grok` CLI by adding a stable session HUD, unified command discovery, activity-aware streaming feedback, fuzzy pickers, and a consistent transcript design system while preserving the current scriptable `--json`, `--raw`, and `--quiet` behavior.

## Success Criteria

- [ ] Interactive `grok` sessions show a compact, stable, project-first HUD before each prompt with no key/value colon labels, no permanent command cheat sheet, and only non-default state.
- [ ] `/help`, slash completion, command suggestions, typo hints, and command examples are generated from one command registry.
- [ ] Streaming responses render a clean transcript with stable `Grok:` answer headers and a per-turn activity timeline for thinking/search/tool events.
- [ ] Model, workspace, file, and conversation selection use one reusable fuzzy picker with previews and keyboard hints.
- [ ] Terminal colors and labels come from semantic style helpers rather than scattered ad hoc `.cyan`, `.yellow`, `.green`, `.red`.
- [ ] Existing JSON/quiet/raw outputs remain script-safe and do not receive HUD or decorative CUI output.
- [ ] Tests cover pure renderers, parser behavior, command registry drift, E2E interactive flows, and scriptable output boundaries.
- [ ] After implementation, run build and install so the user can test `grok` from PATH.

## Current-State Findings

- [x] `Sources/GrokCLI/Interactive/InteractiveSession.swift` owns the main chat loop, startup status, slash command switch, settings prints, and message dispatch.
- [x] `Sources/GrokCLI/Interactive/InputReader.swift` already supports raw mode, history, cursor movement, `/` suggestions, Tab completion, prefilled input, and non-TTY fallback.
- [x] `Sources/GrokCLI/Interactive/InteractiveCommandSpecs.swift` contains completion metadata but is still separate from the full help strings in `HelpText.swift` and `OutputFormatter.printHelp()`.
- [x] `Sources/GrokCLI/Interactive/ChatCommand.swift` has a separate `printSettingsStatus(...)` path, so status/HUD wording can drift unless it is folded into the shared renderer.
- [x] `Sources/GrokCLI/Core/TopLevelRouter.swift` recognizes top-level entries such as `modes`, `workspace`, and `test`; the command registry must cover top-level help as well as interactive slash help.
- [x] `Sources/GrokCLI/Interactive/InteractiveModelCommands.swift` has a bespoke raw-mode arrow picker for model selection.
- [x] `Sources/GrokCLI/Interactive/InteractiveMenus.swift` has simple numbered workspace/file pickers.
- [x] `Sources/GrokCLI/Presentation/OutputFormatter.swift` renders `Thinking`, `Grok:`, markdown, tables, sources, and interactive help.
- [x] `Sources/GrokCLI/Presentation/GrokStreamMarkupParser.swift` converts Grok internal tags and tool cards into `.text` and `.trace(String)` display events.
- [x] `Sources/GrokCLI/Core/CLIIO.swift` has `TransientStatusLine`, TTY detection, stdout/stderr routing, and prompt-file/stdin helpers.
- [x] `Sources/GrokCLI/Commands/MessageCommand.swift` preserves separate human, JSON, and quiet stream paths. JSON stream already emits request/progress/trace/final events.
- [x] `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift` includes E2E interactive coverage, help assertions, markdown formatter tests, quiet/raw/scriptable assertions, and a mock server.
- [x] `Package.swift` already depends on `Rainbow`; no new dependency is required for the first implementation.
- [x] `Scripts/install_cli.sh` builds and installs the release `grok` binary. This should be the post-plan execution install gate.

Useful discovery commands:

```sh
rg -n "InputReader|OutputFormatter|GrokStreamMarkupParser|CommandSpec|TransientStatus" Sources/GrokCLI Tests
rg -n "audio|transcribe|audio-send" Sources/GrokCLI README.md Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift
swift test --filter GrokCLIE2ETests
```

## Target User Experience

### First Interactive Screen

```text
Connected to SuperGrok! Use / for commands, or type help.

Grok > Model Fast | MD

> 
```

### HUD After Workspace and Attachment Changes

```text
Research Notes > Model Expert | MD | 2 files

> summarize the attached notes
```

### HUD With Non-Default State

```text
Research Notes > Private | Model Expert | MD | Stream off | 2 files

> 
```

### HUD With Rate-Limit Warning

```text
Research Notes > Model Expert | MD | 2 files
Limit > 2 left | reset 14m

> 
```

### State Change Confirmations

```text
model expert
workspace Research Notes
attached 2 files
private on

Research Notes > Private | Model Expert | MD | 2 files
> 
```

HUD design rules:

- Put project/workspace first because it organizes chats and can influence responses more than model choice.
- Preserve the current visual spirit: bright connection line, colored `>` prompt, cyan/blue status label, yellow model/format emphasis, and a clear pipe-separated status rhythm.
- Use `Project > ...` rather than `Settings > ...` when a project is selected; use `Grok > ...` when no project is selected.
- Keep the model secondary and short with `Model Fast` or `Model Expert`, not `model:expert`.
- Keep `MD` visible because it is part of the current clean status language and tells the user how responses will render.
- Omit defaults that add little value, especially `Private off`, `Stream on`, no files, and new conversation.
- Show the second HUD line only for warnings or genuinely actionable state, such as `Limit > 2 left | reset 14m`.
- Keep slash command hints in completion/help surfaces, not in the resting prompt chrome.

### Command Suggestions

```text
> /wo

  /workspace          Choose the project for new chats
> /workspaces         List or manage workspaces
  /workspace select   Choose the project for new chats

tab complete  arrows select  enter run
```

### Typo Hint

```text
Unknown command /wrkspace
Did you mean /workspace
Run /help for commands
```

### Activity Timeline During Streaming

```text
Grok:

[thinking] reading the prompt
[search] swift terminal raw mode cursor redraw
[search] complete in 1.2s

The cleanest path is to isolate prompt chrome from transcript rendering...
```

### Fuzzy Picker

```text
Select model
query: exp

> Expert                expert
  Heavy                 grok-heavy
  Grok 4.3 beta         grok-420-computer-use-sa

preview
Expert reasoning model for deeper implementation work.

enter choose | tab insert id | esc cancel
```

## Architecture Overview

Add small, testable presentation primitives instead of folding more logic into `InteractiveSession.swift`.

New files:

- `Sources/GrokCLI/Presentation/TerminalStyle.swift`
- `Sources/GrokCLI/Presentation/TerminalLayout.swift`
- `Sources/GrokCLI/Presentation/CLIHUDRenderer.swift`
- `Sources/GrokCLI/Presentation/ActivityTimelineRenderer.swift`
- `Sources/GrokCLI/Interactive/InteractiveCommandRegistry.swift`
- `Sources/GrokCLI/Interactive/InteractivePicker.swift`
- `Sources/GrokCLI/Interactive/FuzzyMatcher.swift`

Modified files:

- `Sources/GrokCLI/Runtime/ChatSessionState.swift`
- `Sources/GrokCLI/Runtime/GrokCLIApp.swift`
- `Sources/GrokCLI/Interactive/InputReader.swift`
- `Sources/GrokCLI/Interactive/ChatCommand.swift`
- `Sources/GrokCLI/Interactive/InteractiveSession.swift`
- `Sources/GrokCLI/Interactive/InteractiveCommandParser.swift`
- `Sources/GrokCLI/Interactive/InteractiveCommandSpecs.swift`
- `Sources/GrokCLI/Interactive/InteractiveModelCommands.swift`
- `Sources/GrokCLI/Interactive/InteractiveMenus.swift`
- `Sources/GrokCLI/Presentation/HelpText.swift`
- `Sources/GrokCLI/Presentation/OutputFormatter.swift`
- `Sources/GrokCLI/Presentation/GrokStreamMarkupParser.swift`
- `Sources/GrokCLI/Commands/MessageCommand.swift`
- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`

## Workstreams

### Workstream 1: Semantic Terminal Presentation

Ownership:

- Own `TerminalStyle.swift`, `TerminalLayout.swift`, and common text truncation/padding helpers.
- Do not modify command parsing or network behavior.

Todos:

- [ ] Add semantic terminal roles for brand, accent, muted, success, warning, error, command, selected, status, and transcript.
- [ ] Add terminal width detection with a safe default for non-TTY/test contexts.
- [ ] Add `truncateMiddle`, `truncateEnd`, and `stripANSI` helpers.
- [ ] Replace only new UI code with semantic roles first; leave broad existing color cleanup for later workstreams.
- [ ] Add pure unit-style tests through `GrokCLIE2ETests` capture helpers.

Exact Swift shape:

```swift
// Sources/GrokCLI/Presentation/TerminalStyle.swift
import Foundation
import Rainbow

enum TerminalRole {
    case brand
    case accent
    case muted
    case success
    case warning
    case error
    case command
    case selected
    case status
    case transcript
}

enum TerminalStyle {
    static func text(_ value: String, _ role: TerminalRole, bold: Bool = false) -> String {
        let colored: String
        switch role {
        case .brand:
            colored = value.green
        case .accent:
            colored = value.cyan
        case .muted:
            colored = value.blue
        case .success:
            colored = value.green
        case .warning:
            colored = value.yellow
        case .error:
            colored = value.red
        case .command:
            colored = value.yellow
        case .selected:
            colored = value.yellow
        case .status:
            colored = value.cyan
        case .transcript:
            colored = value
        }
        return bold ? colored.bold : colored
    }

    static func token(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
```

```swift
// Sources/GrokCLI/Presentation/TerminalLayout.swift
import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum TerminalLayout {
    static func columns(default fallback: Int = 80) -> Int {
        guard GrokCLI.stdoutIsTTY() else { return fallback }

        var size = winsize()
        let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        guard result == 0, size.ws_col > 0 else { return fallback }
        return Int(size.ws_col)
    }

    static func stripANSI(_ value: String) -> String {
        let escape = "\u{001B}"
        return value.replacingOccurrences(
            of: "\(escape)\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }

    static func visibleLength(_ value: String) -> Int {
        stripANSI(value).count
    }

    static func truncateEnd(_ value: String, width: Int) -> String {
        guard width > 0 else { return "" }
        guard visibleLength(value) > width else { return value }
        guard width > 3 else { return String(value.prefix(width)) }
        return String(value.prefix(width - 3)) + "..."
    }

    static func truncateMiddle(_ value: String, width: Int) -> String {
        guard width > 0 else { return "" }
        guard visibleLength(value) > width else { return value }
        guard width > 5 else { return truncateEnd(value, width: width) }
        let leftCount = (width - 3) / 2
        let rightCount = width - 3 - leftCount
        return String(value.prefix(leftCount)) + "..." + String(value.suffix(rightCount))
    }
}
```

## Workstream 2: Sticky Session HUD

Ownership:

- Own `CLIHUDRenderer.swift`, `ChatSessionState` HUD fields, and `InputReader` prompt frame integration.
- Avoid changing command semantics.

Todos:

- [ ] Add `CLIHUDState` as a pure value snapshot.
- [ ] Add `CLIHUDRenderer.lines(state:width:)`.
- [ ] Preserve the current clear, colorful terminal style: green connection success, cyan/blue label before `>`, yellow highlighted model/format segments, and green prompt.
- [ ] Render project/workspace as the first HUD label, using `Research Notes > ...`; fall back to `Grok > ...` when no project is selected.
- [ ] Omit default state from the resting HUD: stream on, private off, no attachments, and new conversation.
- [ ] Avoid key/value colon labels in the HUD. Prefer readable segments such as `Research Notes > Model Expert | MD | 2 files`.
- [ ] Keep command hints out of the resting HUD. They should appear in slash completion, picker footers, and `/help`.
- [ ] Render a second HUD line only for warnings or genuinely actionable state, such as `Limit > 2 left | reset 14m`.
- [ ] Revise the recent rate-limit status plumbing so the HUD receives an already-clean warning line or structured remaining/reset fields. Do not parse old status prose inside the renderer.
- [ ] Let `InputReader` accept `hudProvider: (() -> [String])?`.
- [ ] Render HUD above the prompt and suggestions in TTY mode.
- [ ] Ensure HUD is not printed for `--quiet`, JSON, or non-TTY fallback.
- [ ] Replace startup multi-line state dumps with the HUD, preserving essential status messages.
- [ ] Remove duplicated settings-status rendering by routing both `InteractiveSession.swift` and `ChatCommand.swift` through `CLIHUDRenderer` or one shared status renderer.
- [ ] Update command handlers to redraw HUD after state changes.

Exact Swift shape:

```swift
// Sources/GrokCLI/Presentation/CLIHUDRenderer.swift
import Foundation
import GrokClient

struct CLIHUDState: Equatable {
    var modelName: String
    var workspaceName: String?
    var privateMode: Bool
    var stream: Bool
    var outputFormat: OutputFormat
    var attachedFileCount: Int
    var rateLimitWarning: String? = nil
}

enum CLIHUDRenderer {
    static func state(from chatState: ChatSessionState, app: GrokCLIApp) -> CLIHUDState {
        CLIHUDState(
            modelName: chatState.mode.displayName,
            workspaceName: app.getCurrentWorkspace()?.cliDisplayName,
            privateMode: chatState.privateMode,
            stream: chatState.stream,
            outputFormat: chatState.outputFormat,
            attachedFileCount: app.getAttachedFileIds().count,
            rateLimitWarning: chatState.rateLimitStatus
        )
    }

    static func lines(state: CLIHUDState, width: Int = TerminalLayout.columns()) -> [String] {
        let label = state.workspaceName ?? "Grok"
        var segments: [String] = []

        if state.privateMode {
            segments.append("Private")
        }

        segments.append("Model \(state.modelName)")
        segments.append(state.outputFormat.statusName)

        if !state.stream {
            segments.append("Stream off")
        }

        if state.attachedFileCount > 0 {
            segments.append(state.attachedFileCount == 1 ? "1 file" : "\(state.attachedFileCount) files")
        }

        let status = "\(label) > \(segments.joined(separator: " | "))"
        var lines = [TerminalLayout.truncateEnd(colorStatusLine(status, label: label), width: width)]

        if let warning = state.rateLimitWarning, !warning.isEmpty {
            let line = "Limit > \(warning)"
            lines.append(TerminalStyle.text(TerminalLayout.truncateEnd(line, width: width), .warning))
        }

        return lines
    }

    private static func colorStatusLine(_ line: String, label: String) -> String {
        // Keep this close to the current "Settings > Model: Fast | MD" feel:
        // colored label, colored chevron, highlighted value segments.
        let prefix = "\(label) > "
        guard line.hasPrefix(prefix) else {
            return TerminalStyle.text(line, .status)
        }
        let rest = String(line.dropFirst(prefix.count))
        return TerminalStyle.text(label, .status)
            + " > ".cyan
            + rest.yellow
    }
}
```

`InputReader` constructor addition:

```swift
final class InputReader {
    private let hudProvider: (() -> [String])?

    init(
        commandSpecs: [GrokCLI.CommandSpec] = GrokCLI.interactiveCommandSpecs,
        showsPromptWhenNotTTY: Bool = true,
        hudProvider: (() -> [String])? = nil
    ) {
        self.commandSpecs = commandSpecs
        self.showsPromptWhenNotTTY = showsPromptWhenNotTTY
        self.hudProvider = hudProvider
    }
}
```

`InputReader.render` outline:

```swift
private func render(prompt: String, buffer: String, cursorIndex: Int) {
    clearRenderedBlock()

    let hudLines = hudProvider?() ?? []
    for line in hudLines {
        print(line)
    }

    let suggestions = suggestions(for: buffer)
    print("\(prompt.green)\(buffer)", terminator: "")

    if !suggestions.isEmpty {
        print("")
        renderSuggestions(suggestions)
    }

    previousRenderedLines = hudLines.count + 1 + suggestions.count + (suggestions.isEmpty ? 0 : 1)
    let linesUp = previousRenderedLines - 1
    if linesUp > 0 {
        print("\u{001B}[\(linesUp)A", terminator: "")
    }
    print("\r", terminator: "")
    let cursorColumn = TerminalLayout.visibleLength(prompt) + cursorIndex
    if cursorColumn > 0 {
        print("\u{001B}[\(cursorColumn)C", terminator: "")
    }
    fflush(stdout)
}
```

`InteractiveSession` integration:

```swift
var state = ChatSessionState(...)

let inputReader = InputReader(showsPromptWhenNotTTY: !enableQuiet) {
    guard !enableQuiet, GrokCLI.stdinIsTTY(), GrokCLI.stdoutIsTTY() else { return [] }
    let hudState = CLIHUDRenderer.state(from: state, app: app)
    return CLIHUDRenderer.lines(state: hudState)
}
```

Important: the closure captures `state`; create the `InputReader` after `state` exists or wrap it in a reference type:

```swift
final class InteractiveRenderState {
    var chatState: ChatSessionState

    init(chatState: ChatSessionState) {
        self.chatState = chatState
    }
}
```

Preferred integration:

```swift
let renderState = InteractiveRenderState(chatState: state)
let inputReader = InputReader(showsPromptWhenNotTTY: !enableQuiet) {
    guard !enableQuiet, GrokCLI.stdinIsTTY(), GrokCLI.stdoutIsTTY() else { return [] }
    return CLIHUDRenderer.lines(
        state: CLIHUDRenderer.state(from: renderState.chatState, app: app)
    )
}
```

Every state mutation must update both `state` and `renderState.chatState`:

```swift
state.stream = try GrokCLI.resolveToggle(...)
renderState.chatState = state
print("Streaming: \(state.stream ? "ENABLED".green : "DISABLED".red)")
```

## Workstream 3: Unified Command Registry and Help

Ownership:

- Own `InteractiveCommandRegistry.swift`, `InteractiveCommandSpecs.swift`, top-level help metadata, interactive help generation, suggestions, and typo hints.
- Do not change handlers beyond switching metadata lookups.

Todos:

- [ ] Replace `CommandSpec` with richer registry metadata. Prefer a tree-shaped registry that can represent top-level commands, aliases, nested interactive commands, grouped help paths, and hidden/internal commands.
- [ ] Generate `interactiveCommandSpecs` from `InteractiveCommandRegistry.visibleCommands` or `CommandRegistry.flattened(for: .interactive)`.
- [ ] Generate `OutputFormatter.printHelp()`, top-level human help, and JSON help command lists from the same registry.
- [ ] Add categories: session, model, files, workspace, library, auth, audio, utility.
- [ ] Add `nearestCommand` and typo hint logic for slash commands.
- [ ] Move suggestion matching into a testable internal function.
- [ ] Keep aliases and bare command rules compatible.
- [ ] Add tests ensuring `modes`, `workspace`, and `test` stay represented in human and JSON help surfaces.

Exact Swift shape:

The flat `InteractiveCommandSpec` shape below is the smallest compatible migration. For highest quality, implement it as a tree by adding `scope`, `hidden`, and `children` fields before wiring help generation:

```swift
enum CommandScope {
    case topLevel
    case interactive
}

struct CommandNode {
    let command: String
    let aliases: [String]
    let usage: String
    let description: String
    let category: GrokCLI.InteractiveCommandCategory
    let scope: CommandScope
    let acceptsBare: Bool
    let requiresArgument: Bool
    let hidden: Bool
    let children: [CommandNode]
}
```

```swift
// Sources/GrokCLI/Interactive/InteractiveCommandRegistry.swift
import Foundation

extension GrokCLI {
    enum InteractiveCommandCategory: String, CaseIterable {
        case session = "Session"
        case model = "Model"
        case files = "Files"
        case workspace = "Workspace"
        case library = "Library"
        case auth = "Auth"
        case audio = "Audio"
        case utility = "Utility"
    }

    struct InteractiveCommandSpec: Equatable {
        let command: String
        let aliases: [String]
        let usage: String
        let description: String
        let category: InteractiveCommandCategory
        let acceptsBare: Bool
        let requiresArgument: Bool

        var allNames: [String] {
            [command] + aliases
        }

        var insertionText: String {
            command
                .split(separator: " ")
                .prefix { !$0.hasPrefix("<") && !$0.hasPrefix("[") }
                .joined(separator: " ")
        }
    }

    enum InteractiveCommandRegistry {
        static let visibleCommands: [InteractiveCommandSpec] = [
            InteractiveCommandSpec(command: "/new", aliases: [], usage: "/new", description: "Start a new conversation thread", category: .session, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/help", aliases: [], usage: "/help", description: "Show interactive command help", category: .utility, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/exit", aliases: ["/quit"], usage: "/exit", description: "Exit the app", category: .session, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/list", aliases: [], usage: "/list", description: "List and load saved conversations", category: .session, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/model", aliases: ["/mode", "/models", "/modes"], usage: "/model [mode|list]", description: "Switch the active model or open the model picker", category: .model, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/reason", aliases: ["/reasoning"], usage: "/reason [on|off]", description: "Toggle reasoning mode", category: .model, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/stream", aliases: [], usage: "/stream [on|off]", description: "Toggle streaming responses", category: .model, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/format", aliases: ["/md", "/markdown", "/raw"], usage: "/format [md|raw]", description: "Toggle Markdown or raw output", category: .model, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/private", aliases: [], usage: "/private [on|off]", description: "Toggle private mode", category: .session, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/attach", aliases: [], usage: "/attach [fileId|clear|upload <path>]", description: "Attach files to following messages", category: .files, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/attach upload <path>", aliases: [], usage: "/attach upload <path>", description: "Upload a local file and attach it", category: .files, acceptsBare: true, requiresArgument: true),
            InteractiveCommandSpec(command: "/audio <path>", aliases: [], usage: "/audio <path>", description: "Transcribe audio, edit the text, then send", category: .audio, acceptsBare: false, requiresArgument: true),
            InteractiveCommandSpec(command: "/audio-send <path>", aliases: [], usage: "/audio-send <path>", description: "Transcribe audio and send immediately", category: .audio, acceptsBare: false, requiresArgument: true),
            InteractiveCommandSpec(command: "/transcribe <path>", aliases: [], usage: "/transcribe <path>", description: "Transcribe audio and print the text", category: .audio, acceptsBare: false, requiresArgument: true),
            InteractiveCommandSpec(command: "/workspaces", aliases: ["/workspace"], usage: "/workspace [select|list|create|delete]", description: "List or manage workspaces", category: .workspace, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/workspace select", aliases: ["/workspaces select"], usage: "/workspace select", description: "Choose the project for new chats", category: .workspace, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/files", aliases: [], usage: "/files [list|upload|delete]", description: "List or upload assets", category: .files, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/tasks", aliases: [], usage: "/tasks [list|create|archive]", description: "Manage tasks", category: .library, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/skills", aliases: [], usage: "/skills [list|mine|user]", description: "List Grok skills", category: .library, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/agents", aliases: [], usage: "/agents [list|show|edit|set]", description: "Manage agent settings", category: .library, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/auth", aliases: [], usage: "/auth [generate|import|help]", description: "Generate or import credentials", category: .auth, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/reset-conversation", aliases: [], usage: "/reset-conversation", description: "Clear the current conversation context", category: .session, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/clear", aliases: ["/cls"], usage: "/clear", description: "Clear the screen", category: .utility, acceptsBare: true, requiresArgument: false),
            InteractiveCommandSpec(command: "/special", aliases: [], usage: "/special", description: "Start a private special-mode conversation", category: .session, acceptsBare: true, requiresArgument: false)
        ]

        static func spec(named name: String) -> InteractiveCommandSpec? {
            let slashName = name.hasPrefix("/") ? name : "/\(name)"
            return visibleCommands.first { spec in
                spec.allNames.contains { $0.lowercased() == slashName.lowercased() }
            }
        }
    }
}
```

Compatibility adapter:

```swift
extension GrokCLI {
    typealias CommandSpec = InteractiveCommandSpec

    static var interactiveCommandSpecs: [CommandSpec] {
        InteractiveCommandRegistry.visibleCommands
    }
}
```

Typo hint:

```swift
extension GrokCLI.InteractiveCommandRegistry {
    static func nearestCommand(to rawInput: String) -> GrokCLI.InteractiveCommandSpec? {
        let input = rawInput.hasPrefix("/") ? rawInput.lowercased() : "/\(rawInput.lowercased())"
        let commandToken = input.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? input

        return visibleCommands
            .flatMap { spec in spec.allNames.map { (spec, editDistance(commandToken, $0.lowercased())) } }
            .filter { _, distance in distance <= 2 }
            .sorted { lhs, rhs in lhs.1 < rhs.1 }
            .first?
            .0
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dp[i][0] = i }
        for j in 0...b.count { dp[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
                }
            }
        }
        return dp[a.count][b.count]
    }
}
```

Unknown slash command handling:

```swift
case .some(let unknown) where interactiveCommand?.hasSlash == true:
    print("Unknown command: /\(unknown)".red)
    if let suggestion = GrokCLI.InteractiveCommandRegistry.nearestCommand(to: unknown) {
        print("Did you mean: \(suggestion.insertionText)".yellow)
    }
    print("Run /help for commands.".yellow)
    continue
```

Generated help:

```swift
func printHelp() {
    print("")
    print(TerminalStyle.text("Basic Commands:", .accent, bold: true))
    print("- \(TerminalStyle.text("new", .command)): Start a new conversation thread")
    print("- \(TerminalStyle.text("help", .command)): Show this help message")
    print("- \(TerminalStyle.text("exit", .command)): Exit the app")

    print("")
    print(TerminalStyle.text("Slash Commands:", .accent, bold: true))
    for category in GrokCLI.InteractiveCommandCategory.allCases {
        let commands = GrokCLI.InteractiveCommandRegistry.visibleCommands.filter { $0.category == category }
        guard !commands.isEmpty else { continue }
        print(TerminalStyle.text(category.rawValue + ":", .muted, bold: true))
        for spec in commands {
            let command = TerminalStyle.text(spec.usage, .command)
            print("- \(command): \(spec.description)")
        }
    }
    print("")
}
```

## Workstream 4: Activity Timeline and Transcript Rendering

Ownership:

- Own `ActivityTimelineRenderer.swift`, `StreamDisplayEvent` additions, parser updates, and `OutputFormatter` streaming render changes.
- Preserve quiet and JSON behavior.

Todos:

- [ ] Add `ToolActivityEvent`.
- [ ] Extend `StreamDisplayEvent` with `.activity(ToolActivityEvent)` while keeping `.trace(String)` for compatibility during migration.
- [ ] Introduce a normalized stream event layer so human rendering, quiet output, and NDJSON emission consume the same taxonomy instead of independently inferring lifecycle state.
- [ ] Parse tool cards into structured events.
- [ ] Render activity rows before answer text when available.
- [ ] Show stable statuses: `thinking`, `search`, `code`, `tool`, `complete`, `error` where data exists.
- [ ] Update JSON stream handling so `.activity` emits `progress` and `trace` events without changing existing event names.
- [ ] Keep quiet output ignoring trace/activity events.
- [ ] Add tests for parser and output format.

Exact Swift shape:

```swift
// Sources/GrokCLI/Presentation/ActivityTimelineRenderer.swift
import Foundation

enum ToolActivityKind: String, Codable {
    case thinking
    case search
    case code
    case tool
}

enum ToolActivityStatus: String, Codable {
    case observed
    case running
    case complete
    case error
}

struct ToolActivityEvent: Equatable, Codable {
    let kind: ToolActivityKind
    let label: String
    let detail: String?
    let status: ToolActivityStatus
    let elapsedMilliseconds: Int?

    var traceText: String {
        if let detail, !detail.isEmpty {
            return "\(label): \(detail)"
        }
        return label
    }
}

enum ActivityTimelineRenderer {
    static func render(_ event: ToolActivityEvent, width: Int = TerminalLayout.columns()) -> String {
        let status = event.status == .complete ? "complete" : event.kind.rawValue
        let elapsed = event.elapsedMilliseconds.map { " in \(formatMilliseconds($0))" } ?? ""
        let detail = event.detail.map { " " + $0 } ?? ""
        let raw = "[\(status)]\(elapsed)\(detail)"
        return TerminalStyle.text(TerminalLayout.truncateEnd(raw, width: width), .muted)
    }

    private static func formatMilliseconds(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        return String(format: "%.1fs", seconds)
    }
}
```

`StreamDisplayEvent` update:

```swift
enum StreamDisplayEvent {
    case text(String)
    case trace(String)
    case activity(ToolActivityEvent)
}
```

Parser update:

```swift
private func consumeToolUsageCard(to events: inout [StreamDisplayEvent]) -> Bool {
    let closeTag = "</xai:tool_usage_card>"
    guard let closeRange = buffer.range(of: closeTag) else {
        return false
    }

    let blockEnd = closeRange.upperBound
    let block = String(buffer[..<blockEnd])
    buffer.removeSubrange(..<blockEnd)

    guard let activity = toolActivity(from: block) else {
        return true
    }
    guard !emittedTraceLines.contains(activity.traceText) else {
        return true
    }

    emittedTraceLines.insert(activity.traceText)
    events.append(.activity(activity))
    events.append(.trace(activity.traceText))
    return true
}

private func toolActivity(from block: String) -> ToolActivityEvent? {
    let toolName = xmlValue(named: "xai:tool_name", in: block) ?? "tool"
    let argsText = xmlValue(named: "xai:tool_args", in: block).map(stripCDATA)
    let args = argsText.flatMap(jsonDictionary)

    switch toolName {
    case "web_search":
        return ToolActivityEvent(
            kind: .search,
            label: "Search",
            detail: stringValue(args, key: "query").map(compact),
            status: .observed,
            elapsedMilliseconds: nil
        )
    case "x_search":
        return ToolActivityEvent(
            kind: .search,
            label: "Search X",
            detail: stringValue(args, key: "query").map(compact),
            status: .observed,
            elapsedMilliseconds: nil
        )
    case "code_execution", "code":
        let code = stringValue(args, key: "code") ?? argsText ?? ""
        return ToolActivityEvent(
            kind: .code,
            label: "Code",
            detail: summarizeCode(code),
            status: .observed,
            elapsedMilliseconds: nil
        )
    default:
        return ToolActivityEvent(
            kind: .tool,
            label: toolName.replacingOccurrences(of: "_", with: " ").capitalized,
            detail: stringValue(args, key: "query").map(compact),
            status: .observed,
            elapsedMilliseconds: nil
        )
    }
}
```

`OutputFormatter.printStreamingResponse` rendering addition:

```swift
func renderActivity(_ event: ToolActivityEvent) {
    clearTransientStatus()
    if printedText {
        return
    }
    printedTrace = true
    print(ActivityTimelineRenderer.render(event))
    fflush(stdout)
}

func renderAnswerEvent(_ event: StreamDisplayEvent) {
    switch event {
    case .trace(let line):
        renderTraceLine(line)
    case .activity(let activity):
        renderActivity(activity)
    case .text(let text):
        renderText(text)
    }
}
```

Prevent duplicate display when both `.activity` and `.trace` are emitted:

```swift
func renderAnswerEvent(_ event: StreamDisplayEvent) {
    switch event {
    case .activity(let activity):
        renderActivity(activity)
    case .trace:
        return
    case .text(let text):
        renderText(text)
    }
}
```

JSON stream compatibility:

```swift
case .activity(let activity):
    try printJSONEvent(sequence: sequence, event: "progress", data: AnyCodable([
        "kind": AnyCodable(activity.kind.rawValue),
        "status": AnyCodable(activity.status.rawValue),
        "text": AnyCodable(activity.traceText)
    ]))
    sequence += 1
    try printJSONEvent(sequence: sequence, event: "trace", data: AnyCodable([
        "kind": AnyCodable(activity.kind.rawValue),
        "text": AnyCodable(activity.traceText)
    ]))
    sequence += 1
```

Quiet path stays text-only:

```swift
for event in events {
    guard case .text(let text) = event, !text.isEmpty else {
        continue
    }
    CLIOutput.stdout(text, terminator: "")
}
```

## Workstream 5: Reusable Fuzzy Picker

Ownership:

- Own `InteractivePicker.swift` and `FuzzyMatcher.swift`.
- Replace model picker first, then workspace/file/conversation pickers.
- Preserve non-TTY numbered fallback.

Todos:

- [ ] Implement `PickerItem` and `InteractivePicker`.
- [ ] Implement fuzzy scoring as pure functions.
- [ ] Add raw-mode rendering with query, visible rows, preview, and keyboard hints.
- [ ] Support up/down, `j/k`, backspace, printable input, Enter, Tab optional action, Esc/q cancel.
- [ ] Refactor `promptForModelSelectionWithArrows` to use `InteractivePicker`.
- [ ] Refactor `showWorkspacePicker`, `showAttachmentPicker`, and `listAndSelectConversation` to use picker when TTY.
- [ ] Keep text-number fallback for non-TTY test/script contexts.

Exact Swift shape:

```swift
// Sources/GrokCLI/Interactive/InteractivePicker.swift
import Foundation

struct PickerItem: Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let previewLines: [String]
}

enum PickerResult: Equatable {
    case selected(PickerItem)
    case alternate(PickerItem)
    case cancelled
}

final class InteractivePicker {
    private let title: String
    private let items: [PickerItem]
    private let alternateHint: String?

    init(title: String, items: [PickerItem], alternateHint: String? = nil) {
        self.title = title
        self.items = items
        self.alternateHint = alternateHint
    }

    func run() -> PickerResult {
        guard GrokCLI.stdinIsTTY(), GrokCLI.stdoutIsTTY() else {
            return .cancelled
        }
        // Implementation mirrors InputReader raw-mode setup.
        // Keep the concrete raw termios code in this class, then delete
        // duplicate picker-specific raw loops from InteractiveModelCommands.
        return runRawMode()
    }

    private func filteredItems(query: String) -> [PickerItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (PickerItem, Int)? in
                let searchable = [item.title, item.subtitle, item.id].compactMap { $0 }.joined(separator: " ")
                guard let score = FuzzyMatcher.score(query: query, text: searchable) else { return nil }
                return (item, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
```

```swift
// Sources/GrokCLI/Interactive/FuzzyMatcher.swift
import Foundation

enum FuzzyMatcher {
    static func score(query: String, text: String) -> Int? {
        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        guard !q.isEmpty else { return 0 }

        var qi = 0
        var score = 0
        var previousMatch = -1

        for (index, char) in t.enumerated() where qi < q.count {
            if char == q[qi] {
                score += previousMatch == index - 1 ? 10 : 3
                if index == 0 || t[index - 1].isWhitespace || t[index - 1] == "-" || t[index - 1] == "_" {
                    score += 5
                }
                previousMatch = index
                qi += 1
            }
        }

        return qi == q.count ? score : nil
    }
}
```

Model picker conversion:

```swift
static func promptForModelSelection(currentMode: GrokMode) -> GrokMode? {
    guard stdinIsTTY(), stdoutIsTTY() else {
        return promptForModelSelectionByText(currentMode: currentMode)
    }

    let items = GrokMode.knownModes.map { mode in
        PickerItem(
            id: mode.id,
            title: mode.displayName,
            subtitle: mode.id,
            previewLines: mode.summary.isEmpty ? ["No summary available."] : [mode.summary]
        )
    }
    let picker = InteractivePicker(title: "Select model", items: items, alternateHint: "tab insert id")
    switch picker.run() {
    case .selected(let item), .alternate(let item):
        return GrokMode.resolve(item.id)
    case .cancelled:
        return nil
    }
}
```

Workspace picker conversion:

```swift
let items = workspaces.enumerated().map { index, workspace in
    PickerItem(
        id: workspace.cliResolvedId ?? "\(index)",
        title: workspace.cliDisplayName,
        subtitle: workspace.cliResolvedId,
        previewLines: [
            "ID: \(workspace.cliResolvedId ?? "unknown")",
            "Select this workspace for new chats."
        ]
    )
}
```

## Workstream 6: Verification, Build, Install, and Release Notes

Ownership:

- Own tests and final verification commands.
- Do not change production behavior except for testability hooks if required.

Todos:

- [ ] Add renderer tests for `CLIHUDRenderer`, `TerminalLayout`, and `ActivityTimelineRenderer`.
- [ ] Add command registry tests ensuring `/help` and suggestions include every visible command.
- [ ] Add typo hint tests for `/wrkspace`, `/modle`, `/attch`.
- [ ] Add fuzzy matcher tests for exact, acronym-ish, and no-match cases.
- [ ] Add parser tests for web search, X search, code execution, and unknown tools.
- [ ] Add E2E assertions that interactive HUD appears in normal interactive mode.
- [ ] Add E2E assertions that HUD does not appear in `--raw --quiet`, `--json`, or non-TTY message output.
- [ ] Run `swift test`.
- [ ] Run `Scripts/install_cli.sh --user` or the user's preferred install command.
- [ ] Smoke test installed binary with `grok help` and `grok models`.

Verification commands:

```sh
swift test
swift test --filter GrokCLIE2ETests
swift build -c release --product grok
Scripts/install_cli.sh --user
~/.local/bin/grok help
~/.local/bin/grok models
```

## Dependencies Between Workstreams

- Workstream 1 is a prerequisite for Workstreams 2, 4, and 5.
- Workstream 3 can run after Workstream 1 or in parallel if it avoids style integration until later.
- Workstream 4 can run in parallel with Workstream 3 once `TerminalStyle` exists.
- Workstream 5 can run in parallel with Workstream 4 but should land after `TerminalLayout`.
- Workstream 6 starts after the first implementation patches but should add some pure tests alongside each workstream.

Recommended parallel agent split:

- Agent 1 owns Workstream 1 and the style/layout tests.
- Agent 2 owns Workstream 2 and `InputReader` HUD integration.
- Agent 3 owns Workstream 3 and command registry/help/typo tests.
- Agent 4 owns Workstream 4 and streaming parser/timeline tests.
- Agent 5 owns Workstream 5 and picker/fuzzy tests.
- Agent 6 owns Workstream 6, E2E coverage, build/install verification, and final polish.

## Concrete Implementation Sequence

1. Add `TerminalStyle` and `TerminalLayout`.
2. Add pure tests for truncation, ANSI stripping, and semantic role output presence.
3. Add `CLIHUDState` and `CLIHUDRenderer`.
4. Add tests showing HUD output at 80 columns and truncated output at 40 columns.
5. Introduce `InteractiveRenderState` in `InteractiveSession`.
6. Inject `hudProvider` into `InputReader`.
7. Replace post-startup `printSettingsStatus`, workspace, attachment, and conversation lines with HUD rendering at the prompt.
8. Keep `printSettingsStatus` temporarily for non-interactive or explicit commands if needed, then delete only after tests prove no caller needs it.
9. Add `InteractiveCommandRegistry` while keeping `CommandSpec` adapter.
10. Move `InputReader.suggestions(for:)` to use registry metadata.
11. Generate interactive help from registry.
12. Add typo hints for unknown slash commands.
13. Add `ToolActivityEvent` and `ActivityTimelineRenderer`.
14. Extend `GrokStreamMarkupParser` to emit `.activity`.
15. Update `OutputFormatter.printStreamingResponse` to render activity events and avoid duplicate trace rows.
16. Update JSON stream handling for `.activity`.
17. Add `FuzzyMatcher` and `InteractivePicker`.
18. Convert model picker to `InteractivePicker`.
19. Convert workspace and file pickers to `InteractivePicker`.
20. Convert conversation picker to `InteractivePicker`.
21. Sweep color usage in touched code to semantic helpers.
22. Run focused tests.
23. Run full tests.
24. Build release.
25. Install release binary.
26. Smoke test installed binary.

## Test Plan Details

### New Pure Tests

Add tests near existing formatter tests in `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`.

```swift
func testHUDRendererShowsSessionStateAndTruncates() {
    let state = CLIHUDState(
        modelName: "Expert",
        workspaceName: "Research Notes",
        privateMode: false,
        stream: true,
        outputFormat: .markdown,
        attachedFileCount: 2,
        rateLimitWarning: nil
    )

    let wide = strippingANSI(CLIHUDRenderer.lines(state: state, width: 120).joined(separator: "\n"))
    XCTAssertContains(wide, "Research Notes > Model Expert | MD")
    XCTAssertContains(wide, "2 files")
    XCTAssertFalse(wide.contains("model:"))
    XCTAssertFalse(wide.contains("workspace:"))
    XCTAssertFalse(wide.contains("/ commands"))

    let narrow = strippingANSI(CLIHUDRenderer.lines(state: state, width: 32).joined(separator: "\n"))
    XCTAssertTrue(narrow.split(separator: "\n").allSatisfy { $0.count <= 32 })
}

func testHUDRendererShowsWarningLineOnlyWhenActionable() {
    var state = CLIHUDState(
        modelName: "Expert",
        workspaceName: "Research Notes",
        privateMode: false,
        stream: true,
        outputFormat: .markdown,
        attachedFileCount: 0,
        rateLimitWarning: nil
    )

    XCTAssertEqual(strippingANSI(CLIHUDRenderer.lines(state: state, width: 80).joined(separator: "\n")), "Research Notes > Model Expert | MD")

    state.rateLimitWarning = "2 left | reset 14m"
    let warned = strippingANSI(CLIHUDRenderer.lines(state: state, width: 80).joined(separator: "\n"))
    XCTAssertContains(warned, "Limit > 2 left | reset 14m")
}
```

```swift
func testCommandRegistryIncludesHelpCommandsAndTypoHints() {
    let commands = GrokCLI.InteractiveCommandRegistry.visibleCommands.map(\.command)
    XCTAssertContains(commands.joined(separator: "\n"), "/model")
    XCTAssertContains(commands.joined(separator: "\n"), "/audio-send")

    let suggestion = GrokCLI.InteractiveCommandRegistry.nearestCommand(to: "wrkspace")
    XCTAssertEqual(suggestion?.command, "/workspaces")
}
```

```swift
func testTopLevelHelpAndJSONHelpShareCommandSet() throws {
    let server = try MockGrokServer()
    let environment = try TestEnvironment(server: server)

    let help = try environment.run(["help"])
    XCTAssertContains(help.cleanOutput, "models")
    XCTAssertContains(help.cleanOutput, "modes")
    XCTAssertContains(help.cleanOutput, "workspace")
    XCTAssertContains(help.cleanOutput, "test")

    let json = try environment.run(["help", "--json"])
    XCTAssertContains(json.cleanOutput, #""models""#)
    XCTAssertContains(json.cleanOutput, #""modes""#)
    XCTAssertContains(json.cleanOutput, #""workspace""#)
    XCTAssertContains(json.cleanOutput, #""test""#)
}
```

```swift
func testFuzzyMatcherScoresSubsequenceMatches() {
    XCTAssertNotNil(FuzzyMatcher.score(query: "exp", text: "Expert expert"))
    XCTAssertNotNil(FuzzyMatcher.score(query: "wrk", text: "workspace Research Notes"))
    XCTAssertNil(FuzzyMatcher.score(query: "zzz", text: "workspace Research Notes"))
}
```

```swift
func testStreamParserEmitsStructuredToolActivity() {
    let parser = GrokStreamMarkupParser()
    let block = """
    <xai:tool_usage_card><xai:tool_name>web_search</xai:tool_name><xai:tool_args><![CDATA[{"query":"swift terminal UI"}]]></xai:tool_args></xai:tool_usage_card>
    """
    let events = parser.consume(block)

    XCTAssertTrue(events.contains {
        if case .activity(let activity) = $0 {
            return activity.kind == .search && activity.detail == "swift terminal UI"
        }
        return false
    })
}
```

### E2E Tests

Normal interactive mode should include HUD:

```swift
func testInteractiveHUDAppearsInTTYLikeSessionOutput() throws {
    let server = try MockGrokServer()
    let environment = try TestEnvironment(server: server)

    let run = try environment.run([], input: "/quit\n")

    XCTAssertEqual(run.status, 0)
    XCTAssertContains(run.cleanOutput, "Grok > Model")
    XCTAssertFalse(run.cleanOutput.contains("model:"))
    XCTAssertFalse(run.cleanOutput.contains("/ commands"))
}
```

Scriptable modes must stay clean:

```swift
func testQuietAndJSONDoNotEmitHUD() throws {
    let server = try MockGrokServer(finalMessage: "answer")
    let environment = try TestEnvironment(server: server)

    let quiet = try environment.run(["message", "--raw", "--quiet", "hello"])
    XCTAssertEqual(quiet.status, 0)
    XCTAssertFalse(quiet.cleanOutput.contains("Grok > Model"))
    XCTAssertFalse(quiet.cleanOutput.contains("model:"))
    assertAnswerOnlyStdout(quiet.stdout, equals: "answer")

    let json = try environment.run(["message", "--json", "hello"])
    XCTAssertEqual(json.status, 0)
    XCTAssertFalse(json.cleanOutput.contains("Grok > Model"))
    XCTAssertFalse(json.cleanOutput.contains("model:"))
    XCTAssertContains(json.cleanOutput, #""command""#)
}
```

Activity timeline:

```swift
func testStreamingToolActivityRendersTimelineRows() throws {
    let server = try MockGrokServer(streamTokens: [
        "<xai:tool_usage_card><xai:tool_name>web_search</xai:tool_name><xai:tool_args><![CDATA[{\"query\":\"swift cli hud\"}]]></xai:tool_args></xai:tool_usage_card>",
        "Final answer"
    ])
    let environment = try TestEnvironment(server: server)

    let run = try environment.run(["message", "--stream", "hello"])

    XCTAssertEqual(run.status, 0)
    XCTAssertContains(run.cleanOutput, "[search]")
    XCTAssertContains(run.cleanOutput, "swift cli hud")
    XCTAssertContains(run.cleanOutput, "Final answer")
}
```

## Risk Register

- Terminal redraw regressions: `InputReader` currently clears with `ESC[J` and counts rendered lines manually. HUD lines increase line accounting complexity. Mitigate with pure render line counts and manual smoke tests in a real terminal.
- Non-TTY output pollution: HUD must never print in `--quiet`, JSON, or piped modes. Mitigate with explicit E2E tests.
- Unicode width drift: existing code uses `.count`. Initial plan keeps ASCII UI and adds `TerminalLayout.visibleLength`; full East Asian width support can be a later improvement.
- Duplicate trace rows: parser may emit both `.activity` and `.trace` during migration. Mitigate in `OutputFormatter` by rendering only `.activity` in human mode and using `.trace` for JSON compatibility.
- Help drift: registry migration must remove or reduce duplicated manual lists. Keep a test that every registry command appears in interactive help output.
- Picker complexity: raw-mode picker can disrupt terminal settings if it exits early. Use `defer` for termios restore and cursor show, matching the current model picker.
- Snapshot brittleness: ANSI colors and terminal widths can make tests fragile. Strip ANSI and pass explicit widths to pure renderers.
- Conversation/source state ambiguity: current `ConversationResponse` has no token usage. Omit context and source state from the resting HUD until real usage exists; keep sources in the transcript after the answer.

## Rollback Notes

- `TerminalStyle` and `TerminalLayout` are additive and safe to leave in place.
- If HUD redraw is unstable, revert only the `InputReader` `hudProvider` integration and keep `CLIHUDRenderer` for future work.
- If command registry migration is too broad, keep the adapter and continue using `InteractiveCommandSpecs.swift` while landing typo hints separately.
- If activity events break stream output, keep `ToolActivityEvent` parsing behind human renderer only and preserve `.trace(String)` behavior.
- If fuzzy picker is unstable, land it first for `/model` only and leave workspace/file/list pickers on numbered selection.

## Final Completion Checklist

- [ ] User requirement: top five CUI/HUD improvements are implemented.
  Evidence: HUD, registry/help, activity timeline, fuzzy pickers, and semantic transcript style are present in `Sources/GrokCLI`.
- [ ] User requirement: high quality Swift code.
  Evidence: new presentation primitives are pure/testable, raw-mode terminal handling restores state with `defer`, and no scriptable output pollution exists.
- [ ] User requirement: exact CLI examples.
  Evidence: README or release notes include updated examples matching the ASCII mockups in this plan.
- [ ] Project requirement: after completing implementation, run build and install.
  Evidence: final execution log includes `swift test`, `swift build -c release --product grok`, `Scripts/install_cli.sh --user`, and installed binary smoke tests.
- [ ] Regression requirement: JSON/quiet/raw behavior unchanged.
  Evidence: existing E2E quiet/JSON tests pass plus new HUD absence tests pass.
- [ ] Usability requirement: terminal UI remains compact on narrow terminals.
  Evidence: pure renderer width tests and manual smoke at 80 and 40 columns.
