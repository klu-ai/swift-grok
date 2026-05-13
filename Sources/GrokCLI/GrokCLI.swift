import ArgumentParser
import Foundation
import GrokClient
import Rainbow
#if os(Linux)
import Glibc
private let stdinFileDescriptor = STDIN_FILENO
private let stdoutFileDescriptor = STDOUT_FILENO
#else
import Darwin
private let stdinFileDescriptor = STDIN_FILENO
private let stdoutFileDescriptor = STDOUT_FILENO
#endif

#if os(Linux)
private func processExit(_ code: Int32) -> Never {
    Glibc.exit(code)
}
#else
private func processExit(_ code: Int32) -> Never {
    Darwin.exit(code)
}
#endif

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

private extension GrokWorkspace {
    var cliResolvedId: String? {
        workspaceId ?? id
    }

    var cliDisplayName: String {
        name ?? title ?? cliResolvedId ?? "Untitled workspace"
    }
}

private extension GrokAsset {
    var cliDisplayName: String {
        fileName ?? name ?? resolvedId ?? "Untitled file"
    }
}

enum OutputFormat: Equatable {
    case markdown
    case raw

    static let defaultFormat: OutputFormat = .markdown

    var statusName: String {
        switch self {
        case .markdown:
            return "MD Formatted"
        case .raw:
            return "Raw Output"
        }
    }

    var description: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .raw:
            return "Raw"
        }
    }

    static func resolve(_ rawValue: String) -> OutputFormat? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "md", "markdown":
            return .markdown
        case "raw", "plain", "text":
            return .raw
        default:
            return nil
        }
    }
}

// Shared options for Grok commands
struct GrokCommandOptions: ParsableArguments {
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning: Bool = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch: Bool = false
    
    @Flag(name: .long, help: "Disable real-time data (no web or x search)")
    var noSearch: Bool = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output (default)")
    var markdown: Bool = false

    @Flag(name: .long, help: "Show raw Markdown text in output")
    var raw: Bool = false

    @Option(name: .long, help: "Output format: md or raw")
    var format: String?
    
    @Flag(name: .long, help: "Show debug information")
    var debug: Bool = false
    
    @Flag(name: .long, help: "Disable custom instructions for the assistant")
    var noCustomInstructions: Bool = false
    
    @Flag(name: .customLong("private"), help: "Enable private mode (conversations will not be saved)")
    var privateMode: Bool = false
    
    @Flag(name: .long, help: "Enable streaming responses")
    var stream: Bool = true

    @Option(name: [.customLong("model"), .customLong("mode")], help: "Web mode to use: auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId")
    var model: String?

    func resolvedOutputFormat() throws -> OutputFormat {
        if let format {
            guard let resolved = OutputFormat.resolve(format) else {
                throw GrokError.apiError("Invalid --format value: \(format). Use md or raw.")
            }
            return resolved
        }

        if raw {
            return .raw
        }

        return .markdown
    }
}

// ChatCommand: Interactive chat session with Grok
struct ChatCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive chat session with Grok"
    )
    
    // Default custom instructions for the assistant
    static let defaultCustomInstructions = """
    You are a highly capable, thoughtful, and precise assistant. Your goal is to deeply understand the user's intent, ask clarifying questions when needed, think step-by-step through complex problems, provide clear and accurate answers, and proactively anticipate helpful follow-up information. Always prioritize being truthful, nuanced, insightful, and efficient, tailoring your responses specifically to the user's needs and preferences. If conversational dialogue, be more human. when possible, use brevity.
    """

    static let hiddenMode = """
    You are a highly capable, thoughtful, and precise assistant. Your goal is to deeply understand the user's intent, ask clarifying questions when needed, think step-by-step through complex problems, provide clear and accurate answers, and proactively anticipate helpful follow-up information. Always prioritize being truthful, nuanced, insightful, and efficient, tailoring your responses specifically to the user's needs and preferences. If conversational dialogue, be more human. when possible, use brevity.
    """
    
    // User preferences key for custom instructions
    private static let customInstructionsKey = "com.grok.cli.customInstructions"
    
    // Get custom instructions from user preferences or defaults
    internal static func getCustomInstructions() -> String {
        if let saved = UserDefaults.standard.string(forKey: customInstructionsKey) {
            return saved
        }
        return defaultCustomInstructions
    }
    
    // Save custom instructions to user preferences
    internal static func saveCustomInstructions(_ instructions: String) {
        UserDefaults.standard.set(instructions, forKey: customInstructionsKey)
    }
    
    // Reset custom instructions to defaults
    internal static func resetCustomInstructions() {
        UserDefaults.standard.removeObject(forKey: customInstructionsKey)
    }
    
    @OptionGroup var options: GrokCommandOptions
    
    @Argument(parsing: .remaining, help: "Optional initial message to send to Grok")
    var initialMessage: [String] = []
    
    // Print the current settings status line
    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode()) {
        let personality = GrokCLIApp.shared.getCurrentPersonality()
        let personalityText = personality == .none ? "" : personality.displayName.yellow + " | "
        
        print("Chat mode".cyan + " | " + 
              "Model: \(currentMode.displayName)".yellow + " | " +
              (currentReasoning ? "Reasoning".green + " | " : "") + 
              (currentDeepSearch ? "DeepSearch".green + " | " : "") + 
              personalityText +
              (currentNoSearch ? "No Search".red : "Realtime".green) + " | " + 
              (currentPrivate ? "Private".red : "Saved".blue) + " | " +
              (currentStream ? "Streaming".green : "Not Streaming".red) + " | " +
              currentFormat.statusName.yellow)
    }
    
    // Print the current settings status line
    func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode()) {
        let personality = GrokCLIApp.shared.getCurrentPersonality()
        let personalityText = personality == .none ? "" : personality.displayName.yellow + " | "
        
        print("Chat mode".cyan + " | " + 
              (currentNoCustomInstructions ? "No Custom Instructions".blue : "Custom Instructions".green) + " | " + 
              "Model: \(currentMode.displayName)".yellow + " | " +
              (currentReasoning ? "Reasoning".green + " | " : "") + 
              (currentDeepSearch ? "DeepSearch".green + " | " : "") + 
              personalityText +
              (currentNoSearch ? "No Search".red : "Realtime".green) + " | " + 
              (currentPrivate ? "Private".red : "Saved".blue) + " | " +
              (currentStream ? "Stream".green : "Not Streaming".red) + " | " +
              currentFormat.statusName.yellow)
    }
    
    // Edit custom instructions in an interactive mode
    private func editCustomInstructions() {
        print("\n\("Editing Custom Instructions".cyan.bold)")
        print("Type your instructions below. Press Ctrl+D (Unix) or Ctrl+Z (Windows) followed by Enter to save.")
        print("Press Ctrl+C to cancel.")
        print("\n\(GrokCLI.getCustomInstructions().yellow)")
        print("\nEnter new instructions:".cyan)
        
        var lines: [String] = []
        while let line = readLine() {
            lines.append(line)
        }
        
        let newInstructions = lines.joined(separator: "\n")
        if !newInstructions.isEmpty {
            GrokCLI.saveCustomInstructions(newInstructions)
            print("\nCustom instructions saved successfully!".green)
        } else {
            print("\nNo changes made.".yellow)
        }
    }
    
    // Deprecated compatibility shim for the old personality selection menu.
    private static func showPersonalityMenu(app: GrokCLIApp) -> GrokClient.PersonalityType {
        print(GrokCLI.personalityDeprecationMessage.yellow)
        print("Use custom instructions for explicit custom behavior.".blue)
        return .none
    }
}

// MessageCommand: Send a single message without interactive mode
struct MessageCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "message",
        abstract: "Send a single message to Grok and get a response"
    )
    
    // Default custom instructions for the assistant
    static let defaultCustomInstructions = ChatCommand.defaultCustomInstructions
    
    @OptionGroup var options: GrokCommandOptions
    
    @Argument(parsing: .remaining, help: "The message to send")
    var messageWords: [String]
    
    func run() async throws {
        let app = GrokCLIApp.shared
        app.setDebugMode(options.debug)
        let selectedMode = GrokMode.resolve(options.model)
        app.setCurrentMode(selectedMode)
        let formatter = OutputFormatter(format: try options.resolvedOutputFormat())
        
        guard !messageWords.isEmpty else {
            print("Error: Please provide a message to send".red)
            return
        }
        
        let message = messageWords.joined(separator: " ")
        
        // Debug output
        if options.debug {
            print("Debug: Sending message: \"\(message)\"")
            print("Debug: Streaming: \(options.stream)")
            print("Debug: Model: \(selectedMode.displayName) (\(selectedMode.id))")
        }
        
        // Initialization message
        print("Calling Grok API...".cyan)
        print("Sending: \(message)".cyan)
        
        do {
            // Try to initialize the client
            _ = try app.initializeClient()
            
            let stream = try await app.msg(
                message: message,
                enableReasoning: options.reasoning,
                enableDeepSearch: options.deepSearch,
                disableSearch: options.noSearch,
                customInstructions: options.noCustomInstructions ? "" : GrokCLI.getCustomInstructions(),
                temporary: options.privateMode,
                mode: selectedMode,
                workspaceIds: app.getCurrentWorkspaceIds(),
                streamOutput: options.stream
            )
            
            formatter.printThinkingStatus()
            
            if options.stream {
                try await formatter.printStreamingResponse(stream)
            } else {
                var finalResponse: ConversationResponse?
                for try await response in stream {
                    if response.isFinal {
                        finalResponse = response
                        break
                    }
                }
                if let response = finalResponse {
                    formatter.printResponse(
                        response.message,
                        conversationId: app.getCurrentConversationId(),
                        responseId: app.getLastResponseId(),
                        debug: options.debug,
                        webSearchResults: response.webSearchResults,
                        xposts: response.xposts
                    )
                }
            }
        } catch {
            await app.handleError(error, debug: options.debug)
        }
    }
}

// AuthCommand: Manage authentication credentials
struct AuthCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage Grok authentication credentials",
        subcommands: [Generate.self, Import.self]
    )
    
    struct Generate: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "generate",
            abstract: "Generate new credentials by extracting cookies from your browser"
        )
        
        func run() async throws {
            print("Extracting credentials from browser...".cyan)
            fflush(stdout)
            
            do {
                let app = GrokCLIApp.shared
                let credentialsPath = try await app.generateCredentials()
                print("Successfully generated credentials!".green)
                print("Saved to: \(credentialsPath)".cyan)
            } catch {
                print("Error generating credentials: \(error.localizedDescription)".red)
                print("Please make sure you're logged in to Grok in your browser.".yellow)
                processExit(1)
            }
        }
    }
    
    struct Import: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Import credentials from a JSON file"
        )
        
        @Argument(help: "Path to the JSON credentials file")
        var path: String
        
        func run() throws {
            print("Importing credentials from \(path)...".cyan)
            
            do {
                let app = GrokCLIApp.shared
                try app.saveCredentials(from: path)
                print("Successfully imported credentials!".green)
            } catch {
                print("Error importing credentials: \(error.localizedDescription)".red)
                print("Please make sure the file exists and contains valid credentials.".yellow)
            }
        }
    }
}

// TestCommand: Simple test command for debugging
struct TestCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Simple test command for debugging"
    )
    
    @Argument(parsing: .remaining, help: "Optional test message")
    var message: [String] = []
    
    func run() async throws {
        print("Test command executed successfully!")
        
        if !message.isEmpty {
            let msgText = message.joined(separator: " ")
            print("Message provided: \"\(msgText)\"")
        } else {
            print("No message provided.")
        }
    }
}

// Main GrokCLI command
struct GrokCLI {
    // User preferences key for custom instructions
    private static let customInstructionsKey = "com.grok.cli.customInstructions"
    
    // Get custom instructions from user preferences or defaults
    static func getCustomInstructions() -> String {
        if let saved = UserDefaults.standard.string(forKey: customInstructionsKey) {
            return saved
        }
        return ChatCommand.defaultCustomInstructions
    }
    
    // Save custom instructions to user preferences
    static func saveCustomInstructions(_ instructions: String) {
        UserDefaults.standard.set(instructions, forKey: customInstructionsKey)
    }
    
    // Reset custom instructions to defaults
    static func resetCustomInstructions() {
        UserDefaults.standard.removeObject(forKey: customInstructionsKey)
    }
    
    // Edit custom instructions in an interactive mode
    static func editCustomInstructions() {
        print("\n\("Editing Custom Instructions".cyan.bold)")
        print("Type your instructions below. Press Ctrl+D (Unix) or Ctrl+Z (Windows) followed by Enter to save.")
        print("Press Ctrl+C to cancel.")
        print("\n\(getCustomInstructions().yellow)")
        print("\nEnter new instructions:".cyan)
        
        var lines: [String] = []
        while let line = readLine() {
            lines.append(line)
        }
        
        let newInstructions = lines.joined(separator: "\n")
        if !newInstructions.isEmpty {
            saveCustomInstructions(newInstructions)
            print("\nCustom instructions saved successfully!".green)
        } else {
            print("\nNo changes made.".yellow)
        }
    }
    
    // Print the current settings status line
    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode()) {
        let personality = GrokCLIApp.shared.getCurrentPersonality()
        let personalityText = personality == .none ? "" : personality.displayName.yellow + " | "
        
        print("Chat mode".cyan + " | " + 
              (currentNoCustomInstructions ? "No Custom Instructions".blue : "Custom Instructions".green) + " | " + 
              "Model: \(currentMode.displayName)".yellow + " | " +
              (currentReasoning ? "Reasoning".green + " | " : "") + 
              (currentDeepSearch ? "DeepSearch".green + " | " : "") + 
              personalityText +
              (currentNoSearch ? "No Search".red : "Realtime".green) + " | " + 
              (currentPrivate ? "Private".red : "Saved".blue) + " | " +
              (currentStream ? "Stream".green : "No Stream".red) + " | " +
              currentFormat.statusName.yellow)
    }

    static func printAvailableModels(currentMode: GrokMode? = nil) {
        if let currentMode {
            print("Current model: \(currentMode.displayName) (\(currentMode.id))".cyan)
        }
        print("Available web modes:".cyan)
        for (index, mode) in GrokMode.knownModes.enumerated() {
            let marker = mode.id == currentMode?.id ? "✓ " : "  "
            let detail = mode.summary.isEmpty ? "" : " - \(mode.summary)"
            print("\(marker)\(index + 1). \(mode.displayName)".yellow + " (\(mode.id))\(detail)")
        }
        print("You can also pass a raw web modeId with --model.".blue)
    }

    static func exit(with code: Int32) -> Never {
        processExit(code)
    }

    static func isHelpArgument(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized == "help" || normalized == "-h" || normalized == "--help"
    }

    static func containsHelpArgument(_ args: [String]) -> Bool {
        args.contains { isHelpArgument($0) }
    }

    static func printChatUsage() {
        print("""
        Usage: grok chat [options] [initial message...]

        Starts interactive chat mode. If an initial message is supplied, Grok sends it first and then keeps the prompt open.

        Options:
          --reasoning                 Enable reasoning mode
          --deep-search               Enable deep search
          --no-search                 Disable real-time web/X data
          --markdown, -m              Use markdown formatting in output
          --raw                       Show raw Markdown text in output
          --format <md|raw>           Choose output format
          --debug                     Show debug information
          --no-custom-instructions    Disable stored custom instructions
          --private                   Do not save the conversation
          --stream                    Stream responses
          --model, --mode <mode>      Use auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId
        """)
    }

    static func printMessageUsage() {
        print("""
        Usage: grok message [options] <message...>

        Sends one message to Grok and exits.

        Options:
          --reasoning                 Enable reasoning mode
          --deep-search               Enable deep search
          --no-search                 Disable real-time web/X data
          --markdown, -m              Use markdown formatting in output
          --raw                       Show raw Markdown text in output
          --format <md|raw>           Choose output format
          --debug                     Show debug information
          --no-custom-instructions    Disable stored custom instructions
          --private                   Do not save the conversation
          --stream                    Stream responses
          --model, --mode <mode>      Use auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId
        """)
    }

    static func printListUsage() {
        print("""
        Usage: grok list [--debug]

        Lists saved conversations and optionally loads one by number.
        """)
    }

    static func printModelsUsage() {
        print("Usage: grok models")
    }

    enum InteractiveModelCommand {
        case select
        case set(String)
    }

    struct InteractiveCommand {
        let name: String
        let hasSlash: Bool
        let remainder: String

        var isExact: Bool {
            remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func arguments() throws -> [String] {
            try GrokCLI.splitCommandArguments(remainder)
        }
    }

    struct CommandSpec {
        let command: String
        let aliases: [String]
        let description: String
    }

    static let interactiveCommandSpecs: [CommandSpec] = [
        CommandSpec(command: "/new", aliases: [], description: "Start a new conversation thread"),
        CommandSpec(command: "/help", aliases: [], description: "Show interactive command help"),
        CommandSpec(command: "/exit", aliases: ["/quit"], description: "Exit the app"),
        CommandSpec(command: "/list", aliases: [], description: "List and load saved conversations"),
        CommandSpec(command: "/model", aliases: ["/mode", "/models", "/modes"], description: "Switch the active model or open the model picker"),
        CommandSpec(command: "/reason", aliases: ["/reasoning"], description: "Toggle reasoning mode"),
        CommandSpec(command: "/search", aliases: ["/deepsearch"], description: "Toggle deep search mode"),
        CommandSpec(command: "/realtime", aliases: [], description: "Toggle real-time web/X data"),
        CommandSpec(command: "/stream", aliases: [], description: "Toggle streaming responses"),
        CommandSpec(command: "/format", aliases: ["/md", "/markdown", "/raw"], description: "Toggle Markdown/Raw output"),
        CommandSpec(command: "/private", aliases: [], description: "Toggle private mode"),
        CommandSpec(command: "/custom-instructions", aliases: ["/custom"], description: "Toggle custom instructions"),
        CommandSpec(command: "/personality", aliases: [], description: "Deprecated Grok 3 personality presets"),
        CommandSpec(command: "/attach", aliases: [], description: "Browse files and attach one to following messages"),
        CommandSpec(command: "/attach upload <path>", aliases: [], description: "Upload a local file and attach it"),
        CommandSpec(command: "/attach clear", aliases: [], description: "Remove all attached files"),
        CommandSpec(command: "/files", aliases: [], description: "List or upload assets"),
        CommandSpec(command: "/workspaces", aliases: ["/workspace"], description: "List or manage workspaces"),
        CommandSpec(command: "/workspace select", aliases: ["/workspaces select"], description: "Choose the project for new chats"),
        CommandSpec(command: "/tasks", aliases: [], description: "Manage tasks"),
        CommandSpec(command: "/skills", aliases: [], description: "List Grok skills"),
        CommandSpec(command: "/agents", aliases: [], description: "Manage agent personalities"),
        CommandSpec(command: "/auth", aliases: [], description: "Generate or import credentials"),
        CommandSpec(command: "/reset-conversation", aliases: [], description: "Clear the current conversation context"),
        CommandSpec(command: "/edit-instructions", aliases: [], description: "Edit stored custom instructions"),
        CommandSpec(command: "/reset-instructions", aliases: [], description: "Reset custom instructions to defaults"),
        CommandSpec(command: "/clear", aliases: ["/cls"], description: "Clear the screen"),
        CommandSpec(command: "/special", aliases: [], description: "Start a private special-mode conversation")
    ]

    static let authBrowserNames: Set<String> = [
        "auto", "safari", "atlas", "chrome", "firefox", "chromium", "brave", "edge", "arc"
    ]

    static let personalityDeprecationMessage = "Grok 3 server-side personality presets are deprecated and are no longer sent to Grok 4."

    static func interactiveCommand(from input: String) -> InteractiveCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let hasSlash = trimmed.hasPrefix("/")
        let commandText = hasSlash ? String(trimmed.dropFirst()) : trimmed
        guard !commandText.isEmpty else {
            return nil
        }

        var commandEnd = commandText.startIndex
        while commandEnd < commandText.endIndex, !commandText[commandEnd].isWhitespace {
            commandEnd = commandText.index(after: commandEnd)
        }

        let name = String(commandText[..<commandEnd]).lowercased()
        let remainder = String(commandText[commandEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let command = InteractiveCommand(name: name, hasSlash: hasSlash, remainder: remainder)

        if hasSlash {
            return command
        }

        return isBareInteractiveCommand(command) ? command : nil
    }

    static func isBareInteractiveCommand(_ command: InteractiveCommand) -> Bool {
        let exactCommands: Set<String> = [
            "exit", "quit", "help", "new", "personality", "list",
            "clear", "cls", "reset-conversation", "edit-instructions",
            "reset-instructions", "special"
        ]
        if exactCommands.contains(command.name) {
            return command.isExact
        }

        let modelCommands: Set<String> = ["model", "models", "mode", "modes"]
        if modelCommands.contains(command.name) {
            return command.isExact || command.remainder.split(whereSeparator: { $0.isWhitespace }).count == 1
        }

        let toggleCommands: Set<String> = [
            "reason", "reasoning", "search", "deepsearch",
            "realtime", "custom", "custom-instructions", "private", "stream",
            "md", "markdown", "raw"
        ]
        if toggleCommands.contains(command.name) {
            guard !command.isExact else {
                return true
            }
            let parts = command.remainder.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 1 else {
                return false
            }
            return toggleWords.contains(parts[0].lowercased())
        }

        if command.name == "format" {
            guard !command.isExact else {
                return true
            }
            let parts = command.remainder.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 1 else {
                return false
            }
            return OutputFormat.resolve(String(parts[0])) != nil
        }

        let groupSubcommands: [String: Set<String>] = [
            "auth": Set(["generate", "import", "help", "-h", "--help"]).union(authBrowserNames),
            "tasks": ["list", "create", "archive", "help", "-h", "--help", "--json", "--debug"],
            "skills": ["list", "mine", "user", "help", "-h", "--help", "--json", "--debug"],
            "agents": ["list", "set", "clear", "sync-custom", "help", "-h", "--help", "--replace", "--json", "--debug"],
            "workspaces": ["list", "create", "add-conversation", "delete", "remove", "conversation", "select", "help", "-h", "--help", "--json", "--debug"],
            "workspace": ["list", "create", "add-conversation", "delete", "remove", "conversation", "select", "help", "-h", "--help", "--json", "--debug"],
            "files": ["list", "upload", "help", "-h", "--help", "--json", "--debug"],
            "attach": ["list", "upload", "clear"]
        ]

        guard let allowedSubcommands = groupSubcommands[command.name] else {
            return false
        }
        guard let firstArg = command.remainder.split(whereSeparator: { $0.isWhitespace }).first else {
            return true
        }
        if command.name == "auth", firstArg.hasPrefix("-") {
            return true
        }
        return allowedSubcommands.contains(firstArg.lowercased())
    }

    static let toggleWords: Set<String> = [
        "on", "off", "enable", "enabled", "disable", "disabled", "true", "false"
    ]

    static func resolveToggle(current: Bool, args: [String], usage: String) throws -> Bool {
        guard args.count <= 1 else {
            throw GrokError.apiError("Usage: \(usage) [on|off]")
        }
        guard let rawValue = args.first?.lowercased() else {
            return !current
        }

        switch rawValue {
        case "on", "enable", "enabled", "true":
            return true
        case "off", "disable", "disabled", "false":
            return false
        default:
            throw GrokError.apiError("Usage: \(usage) [on|off]")
        }
    }

    static func resolveOutputFormatCommand(command: String, current: OutputFormat, args: [String], usage: String) throws -> OutputFormat {
        let normalizedCommand = command.lowercased()

        switch normalizedCommand {
        case "format":
            guard args.count <= 1 else {
                throw GrokError.apiError("Usage: \(usage) [md|raw]")
            }
            guard let rawValue = args.first else {
                return current == .markdown ? .raw : .markdown
            }
            guard let format = OutputFormat.resolve(rawValue) else {
                throw GrokError.apiError("Usage: \(usage) [md|raw]")
            }
            return format
        case "md", "markdown":
            let markdownEnabled = try resolveToggle(current: current == .markdown, args: args, usage: usage)
            return markdownEnabled ? .markdown : .raw
        case "raw":
            let rawEnabled = try resolveToggle(current: current == .raw, args: args, usage: usage)
            return rawEnabled ? .raw : .markdown
        default:
            throw GrokError.apiError("Usage: \(usage) [md|raw]")
        }
    }

    static func splitCommandArguments(_ input: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var currentStarted = false
        var quote: Character?
        var escaping = false

        for character in input {
            if escaping {
                current.append(character)
                currentStarted = true
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                currentStarted = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                    currentStarted = true
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                currentStarted = true
                continue
            }

            if character.isWhitespace {
                if currentStarted {
                    args.append(current)
                    current = ""
                    currentStarted = false
                }
                continue
            }

            current.append(character)
            currentStarted = true
        }

        if escaping {
            current.append("\\")
        }

        if let quote {
            throw GrokError.apiError("Unclosed \(quote) quote in command")
        }

        if currentStarted {
            args.append(current)
        }

        return args
    }

    static func interactiveModelCommand(from input: String) -> InteractiveModelCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first?.lowercased() else {
            return nil
        }

        let normalizedCommand = command.hasPrefix("/") ? String(command.dropFirst()) : command
        guard ["model", "models", "mode", "modes"].contains(normalizedCommand) else {
            return nil
        }

        guard parts.count > 1 else {
            return .select
        }

        let requestedMode = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return requestedMode.isEmpty ? .select : .set(requestedMode)
    }

    static func promptForModelSelection(currentMode: GrokMode) -> GrokMode? {
        printAvailableModels(currentMode: currentMode)
        print("Select model number/name, or press Enter to keep current: ".cyan, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return nil
        }

        if let selection = Int(input), selection >= 1, selection <= GrokMode.knownModes.count {
            return GrokMode.knownModes[selection - 1]
        }

        return GrokMode.resolve(input)
    }

    static func showWorkspacePicker(app: GrokCLIApp) async throws {
        let client = try app.initializeClient()
        let workspaces = try await client.listWorkspaces(pageSize: 50)
        guard !workspaces.isEmpty else {
            print("No workspaces found.".yellow)
            return
        }

        if let current = app.getCurrentWorkspace() {
            print("Current workspace: \(current.cliDisplayName)".cyan)
        }

        print("Select workspace:".cyan.bold)
        print("0. None")
        for (index, workspace) in workspaces.enumerated() {
            print("\(index + 1). \(workspace.cliDisplayName) \(workspace.cliResolvedId ?? "")".yellow)
        }
        print("> ".green, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let selection = Int(input),
              selection >= 0,
              selection <= workspaces.count else {
            print("Invalid selection.".red)
            return
        }

        if selection == 0 {
            app.setCurrentWorkspace(nil)
            app.resetConversation()
            print("Workspace cleared. New chats will not be project-scoped.".yellow)
            return
        }

        let workspace = workspaces[selection - 1]
        app.setCurrentWorkspace(workspace)
        app.resetConversation()
        print("Workspace set to: \(workspace.cliDisplayName)".green)
    }

    static func showAttachmentPicker(app: GrokCLIApp) async throws {
        let client = try app.initializeClient()
        let assets = try await client.listAssets(pageSize: 25)
        guard !assets.isEmpty else {
            print("No files found.".yellow)
            return
        }

        print("Select file to attach:".cyan.bold)
        for (index, asset) in assets.enumerated() {
            print("\(index + 1). \(asset.cliDisplayName) \(asset.resolvedId ?? "")".yellow)
        }
        print("> ".green, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let selection = Int(input),
              selection >= 1,
              selection <= assets.count else {
            print("Invalid selection.".red)
            return
        }

        let asset = assets[selection - 1]
        guard let fileId = asset.resolvedId else {
            print("Selected file has no usable attachment ID.".red)
            return
        }

        app.addAttachedFileId(fileId)
        print("Attached: \(asset.cliDisplayName)".green)
    }

    static func uploadAndAttachFile(path: String, app: GrokCLIApp) async throws {
        let client = try app.initializeClient()
        let response = try await client.uploadFile(at: path)
        guard let fileId = response.uploadedFileId else {
            throw GrokError.apiError("Uploaded file response did not include an attachment ID")
        }

        app.addAttachedFileId(fileId)
        print("Uploaded and attached: \(response.fileName ?? URL(fileURLWithPath: path).lastPathComponent)".green)
        print("File ID: \(fileId)".cyan)
    }

    static func attachUploadPath(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "/attach upload"
        let lowercased = trimmed.lowercased()
        guard lowercased == prefix || lowercased.hasPrefix(prefix + " ") else {
            return nil
        }

        let pathStart = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let rawPath = trimmed[pathStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return stripMatchingQuotes(rawPath)
    }

    static func stripMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return value
        }
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    static func applyModelOption(_ arg: String, nextValue: String?) -> (mode: GrokMode?, consumedNext: Bool, missingValue: Bool) {
        if arg == "--model" || arg == "--mode" {
            guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (nil, false, true)
            }
            return (GrokMode.resolve(nextValue), true, false)
        }

        if let value = arg.removingPrefix("--model=") ?? arg.removingPrefix("--mode=") {
            return (GrokMode.resolve(value), false, value.isEmpty)
        }

        return (nil, false, false)
    }

    static func applyOutputFormatOption(_ arg: String, nextValue: String?) -> (format: OutputFormat?, consumedNext: Bool, missingValue: Bool, invalidValue: String?) {
        if arg == "--raw" {
            return (.raw, false, false, nil)
        }

        if arg == "--markdown" || arg == "-m" {
            return (.markdown, false, false, nil)
        }

        if arg == "--format" {
            guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (nil, false, true, nil)
            }
            guard let format = OutputFormat.resolve(nextValue) else {
                return (nil, false, false, nextValue)
            }
            return (format, true, false, nil)
        }

        if let value = arg.removingPrefix("--format=") {
            guard !value.isEmpty else {
                return (nil, false, true, nil)
            }
            guard let format = OutputFormat.resolve(value) else {
                return (nil, false, false, value)
            }
            return (format, false, false, nil)
        }

        return (nil, false, false, nil)
    }
    
    static func main() async throws {
        // Simple command-line argument parsing
        let arguments = Array(CommandLine.arguments.dropFirst()) // Drop the executable name
        
        if arguments.isEmpty {
            // No arguments provided, start interactive chat mode
            try await handleChatCommand(args: [])
            return
        }
        
        let command = arguments[0].lowercased() // Convert to lowercase for case-insensitive comparison
        let remainingArgs = Array(arguments.dropFirst())

        if command == "--help" || command == "-h" {
            showHelp()
            return
        }
        
        // Check if first argument is a recognized command
        let recognizedCommands = ["chat", "message", "auth", "help", "list", "models", "modes", "agents", "tasks", "skills", "workspaces", "workspace", "files", "test"]
        
        // If not a recognized command, treat all arguments as an initial message for chat
        if !recognizedCommands.contains(command) {
            try await handleChatCommand(args: arguments)
            return
        }
        
        // Process the command
        switch command {
        case "chat":
            try await handleChatCommand(args: remainingArgs, exitOnParseError: true)
        case "message":
            try await handleMessageCommand(args: remainingArgs, exitOnError: true)
        case "auth":
            try await handleAuthCommand(
                args: remainingArgs,
                exitOnGenerateFailure: true,
                exitOnUsageError: true,
                exitOnImportFailure: true
            )
        case "list":
            try await handleListCommand(args: remainingArgs, exitOnError: true)
        case "models", "modes":
            if containsHelpArgument(remainingArgs) {
                printModelsUsage()
            }
            printAvailableModels(currentMode: GrokCLIApp.shared.getCurrentMode())
        case "agents":
            try await handleAgentsCommand(args: remainingArgs, exitOnError: true)
        case "tasks":
            try await handleTasksCommand(args: remainingArgs, exitOnError: true)
        case "skills":
            try await handleSkillsCommand(args: remainingArgs, exitOnError: true)
        case "workspaces", "workspace":
            try await handleWorkspacesCommand(args: remainingArgs, exitOnError: true)
        case "files":
            try await handleFilesCommand(args: remainingArgs, exitOnError: true)
        case "test":
            var command = TestCommand()
            command.message = remainingArgs
            try await command.run()
        case "help":
            showHelp()
        default:
            print("Unknown command: \(command)")
            print("Run 'grok help' for usage information.")
        }
    }
    
    // Handle the chat command for interactive sessions
    static func handleChatCommand(args: [String], exitOnParseError: Bool = false) async throws {
        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printChatUsage()
            return
        }

        // Parse options
        var initialMessage: [String] = []
        var enableReasoning = false
        var enableDeepSearch = false
        var outputFormat = OutputFormat.defaultFormat
        var enableDebug = false
        var enableNoCustomInstructions = false
        var enableNoSearch = false
        var enablePrivate = false
        var enableStream = true
        var selectedMode = GrokMode.defaultMode
        
        // Parse all arguments
        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil
            let modelOption = applyModelOption(arg, nextValue: nextValue)

            if modelOption.missingValue {
                print("Error: \(arg) requires a model value".red)
                if exitOnParseError {
                    exit(with: 2)
                }
                return
            } else if let mode = modelOption.mode {
                selectedMode = mode
                index += modelOption.consumedNext ? 2 : 1
                continue
            }

            let outputFormatOption = applyOutputFormatOption(arg, nextValue: nextValue)
            if outputFormatOption.missingValue {
                print("Error: \(arg) requires a format value".red)
                if exitOnParseError {
                    exit(with: 2)
                }
                return
            } else if let invalidValue = outputFormatOption.invalidValue {
                print("Error: Invalid output format '\(invalidValue)'. Use md or raw.".red)
                if exitOnParseError {
                    exit(with: 2)
                }
                return
            } else if let format = outputFormatOption.format {
                outputFormat = format
                index += outputFormatOption.consumedNext ? 2 : 1
                continue
            }

            if arg == "--reasoning" {
                enableReasoning = true
            } else if arg == "--deep-search" {
                enableDeepSearch = true
            } else if arg == "--debug" {
                enableDebug = true
            } else if arg == "--no-custom-instructions" {
                enableNoCustomInstructions = true
            } else if arg == "--no-search" {
                enableNoSearch = true
            } else if arg == "--private" {
                enablePrivate = true
            } else if arg == "--stream" {
                enableStream = true
            } else {
                initialMessage.append(arg)
            }
            index += 1
        }
        
        let app = GrokCLIApp.shared
        app.setDebugMode(enableDebug)
        app.setCurrentMode(selectedMode)
        
        // Reset conversation ID when starting a new chat session
        app.resetConversation()
        
        var formatter = OutputFormatter(format: outputFormat)
        let inputReader = InputReader()
        
        // Initialization message
        print("Calling Grok API...".cyan)
        
        if enableDebug {
            print("Debug: initialMessage = \(initialMessage)")
            print("Debug: Streaming = \(enableStream)")
            print("Debug: Output Format = \(outputFormat.description)")
            print("Debug: Model = \(selectedMode.displayName) (\(selectedMode.id))")
        }
        
        // Try to initialize the client to check authentication before starting.
        // If credentials are missing or expired, stay in interactive mode so
        // `/auth` and `/auth import` can repair the session in place.
        var canSendInitialMessage = true
        do {
            _ = try app.initializeClient()
            print("Authentication successful".green)
        } catch {
            let recovered = await app.handleError(error, debug: enableDebug)
            if recovered {
                do {
                    _ = try app.initializeClient()
                    print("Authentication successful".green)
                } catch {
                    canSendInitialMessage = false
                    _ = await app.handleError(error, debug: enableDebug)
                }
            } else if app.isAuthenticationError(error) {
                canSendInitialMessage = false
                print("Interactive mode is still available. Run '/auth' or '/auth import <file>' to refresh credentials.".yellow)
            } else {
                return
            }
        }
        
        // If there's an initial message, send it immediately
        if !initialMessage.isEmpty && !canSendInitialMessage {
            print("Initial message was not sent because authentication is not ready.".yellow)
            print("After auth succeeds, send it again from the prompt.".yellow)
        } else if !initialMessage.isEmpty {
            let message = initialMessage.joined(separator: " ")
            print("Sending message: \(message)".cyan)
            
            do {
                let stream = try await app.msg(
                    message: message,
                    enableReasoning: enableReasoning,
                    enableDeepSearch: enableDeepSearch,
                    disableSearch: enableNoSearch,
                    customInstructions: enableNoCustomInstructions ? "" : GrokCLI.getCustomInstructions(),
                    temporary: enablePrivate,
                    mode: selectedMode,
                    workspaceIds: app.getCurrentWorkspaceIds(),
                    streamOutput: enableStream
                )
                
                formatter.printThinkingStatus()
                
                if enableStream {
                    try await formatter.printStreamingResponse(stream)
                } else {
                    var finalResponse: ConversationResponse?
                    for try await response in stream {
                        if response.isFinal {
                            finalResponse = response
                            break
                        }
                    }
                    if let response = finalResponse {
                        formatter.printResponse(
                            response.message,
                            conversationId: app.getCurrentConversationId(),
                            responseId: app.getLastResponseId(),
                            debug: enableDebug,
                            webSearchResults: response.webSearchResults,
                            xposts: response.xposts
                        )
                    }
                }
            } catch {
                _ = await app.handleError(error, debug: enableDebug)
                if !app.isAuthenticationError(error) {
                    return
                }
            }
        }
        
        if canSendInitialMessage {
        print("Connected to Grok! Type 'exit' to exit, 'new' to start a new thread, 'help' for commands.".green)
        } else {
            print("Interactive mode ready. Authenticate with '/auth' or '/auth import <file>' before sending messages.".yellow)
        }
        printSettingsStatus(currentReasoning: enableReasoning, currentDeepSearch: enableDeepSearch, currentNoCustomInstructions: enableNoCustomInstructions, currentNoSearch: enableNoSearch, currentPrivate: enablePrivate, currentStream: enableStream, currentFormat: outputFormat)
        if let workspace = app.getCurrentWorkspace() {
            print("Workspace: \(workspace.cliDisplayName)".cyan)
        }
        if !app.getAttachedFileIds().isEmpty {
            print("Attached files: \(app.getAttachedFileIds().count)".cyan)
        }
        if let conversationId = app.getCurrentConversationId() {
            print("Conversation ID: \(conversationId)".cyan)
        }
        print("\nEnter your message:".cyan)
        
        // Main chat loop
        var isRunning = true
        var currentReasoning = enableReasoning
        var currentDeepSearch = enableDeepSearch
        var currentNoCustomInstructions = enableNoCustomInstructions
        var currentNoSearch = enableNoSearch
        var currentPrivate = enablePrivate
        var currentStream = enableStream
        var currentMode = selectedMode
        var currentFormat = outputFormat
        
        while isRunning {
            // Get user input
            guard let input = inputReader.readLine(prompt: "> ") else { break }
            let trimmedInput = input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let interactiveCommand = GrokCLI.interactiveCommand(from: input)
            let interactiveArgs: [String]
            do {
                interactiveArgs = try interactiveCommand?.arguments() ?? []
            } catch {
                await app.handleError(error, debug: enableDebug)
                continue
            }
            
            // Process commands
            switch interactiveCommand?.name {
            case .some("exit"), .some("quit"):
                isRunning = false
                // Reset conversation ID when exiting
                app.resetConversation()
                print("Goodbye!".cyan)
                continue
                
            case .some("new"):
                app.resetConversation()
                print("Started a new conversation thread.".yellow)
                if let workspace = app.getCurrentWorkspace() {
                    print("Workspace: \(workspace.cliDisplayName)".cyan)
                }
                if let conversationId = app.getCurrentConversationId() {
                    print("Conversation ID: \(conversationId)".cyan)
                }
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue
                
            case .some("reason"), .some("reasoning"):
                do {
                    currentReasoning = try GrokCLI.resolveToggle(current: currentReasoning, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/reason" : "reason")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print(currentReasoning ? "Reasoning mode enabled".yellow : "Reasoning mode disabled".blue)
                continue
                
            case .some("search"), .some("deepsearch"):
                do {
                    currentDeepSearch = try GrokCLI.resolveToggle(current: currentDeepSearch, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/search" : "search")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print(currentDeepSearch ? "Deep search enabled".yellow : "Deep search disabled".blue)
                continue
                
            case .some("realtime"):
                do {
                    let realtimeEnabled = try GrokCLI.resolveToggle(current: !currentNoSearch, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/realtime" : "realtime")
                    currentNoSearch = !realtimeEnabled
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Real-time data: \(currentNoSearch ? "DISABLED".red : "ENABLED".green)")
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue
                
            case .some("custom"), .some("custom-instructions"):
                do {
                    let customInstructionsEnabled = try GrokCLI.resolveToggle(current: !currentNoCustomInstructions, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/custom" : "custom")
                    currentNoCustomInstructions = !customInstructionsEnabled
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print(currentNoCustomInstructions ? "Custom instructions disabled".blue : "Custom instructions enabled".yellow)
                continue
                
            case .some("private"):
                do {
                    let previousPrivate = currentPrivate
                    currentPrivate = try GrokCLI.resolveToggle(current: currentPrivate, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/private" : "private")
                    if currentPrivate, !previousPrivate, app.getCurrentConversationId() != nil {
                        app.resetConversation()
                        print("Started a new private conversation thread.".yellow)
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Private mode: \(currentPrivate ? "ENABLED".green : "DISABLED".red)")
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue
                
            case .some("stream"):
                do {
                    currentStream = try GrokCLI.resolveToggle(current: currentStream, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/stream" : "stream")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Streaming: \(currentStream ? "ENABLED".green : "DISABLED".red)")
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue

            case .some("format"), .some("md"), .some("markdown"), .some("raw"):
                do {
                    let usagePrefix = interactiveCommand?.hasSlash == true ? "/\(interactiveCommand?.name ?? "format")" : (interactiveCommand?.name ?? "format")
                    currentFormat = try GrokCLI.resolveOutputFormatCommand(
                        command: interactiveCommand?.name ?? "format",
                        current: currentFormat,
                        args: interactiveArgs,
                        usage: usagePrefix
                    )
                    formatter = OutputFormatter(format: currentFormat)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Output format: \(currentFormat.description)".green)
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue

            case .some("model"), .some("models"), .some("mode"), .some("modes"):
                let modelCommand = interactiveModelCommand(from: input)
                switch modelCommand {
                case .some(.select):
                    guard let selectedMode = promptForModelSelection(currentMode: currentMode) else {
                        continue
                    }
                    currentMode = selectedMode
                case .some(.set(let requestedMode)):
                    if requestedMode.lowercased() == "list" {
                        printAvailableModels(currentMode: currentMode)
                        continue
                    }
                    currentMode = GrokMode.resolve(requestedMode)
                case .none:
                    continue
                }
                app.setCurrentMode(currentMode)
                print("Model set to: \(currentMode.displayName) (\(currentMode.id))".green)
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat, currentMode: currentMode)
                continue
            
            case .some("personality"):
                guard interactiveArgs.isEmpty else {
                    print("Usage: /personality".red)
                    continue
                }

                if app.getCurrentPersonality() != .none {
                    app.setPersonality(.none)
                    app.resetConversation()
                    print("Cleared deprecated personality preset.")
                }
                print(GrokCLI.personalityDeprecationMessage.yellow)
                print("Use /edit-instructions or /custom-instructions for explicit custom behavior.".blue)
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue
                
            case .some("help"):
                formatter.printHelp()
                continue
                
            case .some("list"):
                guard interactiveArgs.isEmpty else {
                    print("Usage: /list".red)
                    continue
                }
                do {
                    if app.getDebugMode() {
                        print("Debug: Attempting to list conversations...")
                    }
                    
                    let client = try app.initializeClient()
                    
                    if app.getDebugMode() {
                        print("Debug: Client initialized successfully")
                        print("Debug: Calling listConversations API endpoint...")
                    }
                    
                    let conversations = try await client.listConversations()
                    
                    if app.getDebugMode() {
                        print("Debug: Retrieved \(conversations.count) conversations")
                    }
                    
                    if conversations.isEmpty {
                        print("No conversations found.".yellow)
                        continue
                    }
                    print("Available conversations:".cyan)
                    for (index, conversation) in conversations.enumerated() {
                        print("\(index + 1). \(conversation.title)")
                    }
                    print("Select a conversation by number: ", terminator: "")
                    if let selection = readLine(), let number = Int(selection), number > 0, number <= conversations.count {
                        let selected = conversations[number - 1]
                        
                        if app.getDebugMode() {
                            print("Debug: Selected conversation ID: \(selected.conversationId)")
                            print("Debug: Selected conversation title: \(selected.title)")
                            print("Debug: Loading conversation responses...")
                        }
                        
                        print("\nLoading conversation \"\(selected.title)\"...".green)
                        let responses = try await app.loadConversation(conversationId: selected.conversationId)
                        
                        if app.getDebugMode() {
                            print("Debug: Loaded \(responses.count) responses")
                        }
                        
                        print("\n\(selected.title)\n".green)
                        if responses.isEmpty {
                            print("This conversation has no messages yet.".yellow)
                        } else {
                            //print("Conversation history:".cyan)
                            for response in responses {
                                let sender = response.sender == "human" ? "User".magenta : "Grok".cyan
                                print("\(sender)\n\(response.message)\n")
                            }
                        }
                    } else {
                        print("Invalid selection.".red)
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                
            case .some("tasks"):
                do {
                    try await GrokCLI.handleTasksCommand(args: interactiveArgs)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("skills"):
                do {
                    try await GrokCLI.handleSkillsCommand(args: interactiveArgs)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("agents"):
                do {
                    try await GrokCLI.handleAgentsCommand(args: interactiveArgs)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("auth"):
                do {
                    try await GrokCLI.handleAuthCommand(args: interactiveArgs)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("workspaces"), .some("workspace"):
                do {
                    let shouldSelectWorkspace =
                        interactiveCommand?.name == "workspace" && (interactiveArgs.isEmpty || interactiveArgs.first?.lowercased() == "select") ||
                        interactiveCommand?.name == "workspaces" && interactiveArgs.first?.lowercased() == "select"
                    if shouldSelectWorkspace, interactiveArgs.count > 1 {
                        throw GrokError.apiError("Usage: /workspace select")
                    }
                    if shouldSelectWorkspace {
                        try await GrokCLI.showWorkspacePicker(app: app)
                    } else {
                        try await GrokCLI.handleWorkspacesCommand(args: interactiveArgs)
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("files"):
                do {
                    let commandArgs = interactiveArgs.isEmpty ? ["list"] : interactiveArgs
                    try await GrokCLI.handleFilesCommand(args: commandArgs)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("attach"):
                do {
                    if interactiveArgs.first?.lowercased() == "upload" {
                        guard interactiveArgs.count == 2, !interactiveArgs[1].isEmpty else {
                            throw GrokError.apiError("Usage: /attach upload <path>")
                        }
                        try await GrokCLI.uploadAndAttachFile(path: interactiveArgs[1], app: app)
                    } else {
                        if interactiveArgs.isEmpty || interactiveArgs.first?.lowercased() == "list" {
                            guard interactiveArgs.count <= 1 else {
                                throw GrokError.apiError("Usage: /attach")
                            }
                            try await GrokCLI.showAttachmentPicker(app: app)
                        } else if interactiveArgs.first?.lowercased() == "clear" {
                            guard interactiveArgs.count == 1 else {
                                throw GrokError.apiError("Usage: /attach clear")
                            }
                            app.clearAttachedFiles()
                            print("Cleared attached files.".yellow)
                        } else if let fileId = interactiveArgs.first {
                            guard interactiveArgs.count == 1 else {
                                throw GrokError.apiError("Usage: /attach <fileId>")
                            }
                            app.addAttachedFileId(fileId)
                            print("Attached file ID: \(fileId)".green)
                        }
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("reset-conversation"):
                app.resetConversation()
                print("Conversation reset. Starting a new conversation.".yellow)
                if let workspace = app.getCurrentWorkspace() {
                    print("Workspace: \(workspace.cliDisplayName)".cyan)
                }
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue
                
            case .some("edit-instructions"):
                if currentNoCustomInstructions {
                    print("Please enable custom instructions first using '/custom' or 'custom on'".yellow)
                    continue
                }
                GrokCLI.editCustomInstructions()
                continue
                
            case .some("reset-instructions"):
                GrokCLI.resetCustomInstructions()
                print("Custom instructions reset to defaults".yellow)
                continue
                
            case .some("special"):
                // Start a new private thread
                app.resetConversation()
                print("Started a new special mode conversation thread.".red.bold)
                print("Special mode activated.".red.bold)
                currentPrivate = true
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                
                do {
                    let stream = try await app.msg(
                        message: ChatCommand.hiddenMode,
                        enableReasoning: false,
                        enableDeepSearch: false,
                        disableSearch: false,
                        customInstructions: "",
                        temporary: true,
                        mode: currentMode,
                        fileAttachments: app.getAttachedFileIds(),
                        workspaceIds: app.getCurrentWorkspaceIds(),
                        streamOutput: currentStream
                    )
                    formatter.printThinkingStatus()
                    
                    if currentStream {
                        try await formatter.printStreamingResponse(stream)
                    } else {
                        var finalResponse: ConversationResponse?
                        for try await response in stream {
                            if response.isFinal {
                                finalResponse = response
                                break
                            }
                        }
                        if let response = finalResponse {
                            formatter.printResponse(
                                response.message,
                                conversationId: app.getCurrentConversationId(),
                                responseId: app.getLastResponseId(),
                                debug: false,
                                webSearchResults: response.webSearchResults,
                                xposts: response.xposts
                            )
                        }
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                
            
            case .some("clear"), .some("cls"):
                formatter.clearScreen()
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate, currentStream: currentStream, currentFormat: currentFormat)
                continue

            case .some(let unknown) where interactiveCommand?.hasSlash == true:
                print("Unknown command: /\(unknown)".red)
                print("Run /help for commands.".yellow)
                continue
                
            case .none where trimmedInput.isEmpty:
                continue
                
            default:
                // Process as message to Grok
                break
            }
            
            // show thinking indicator
            do {
                let pendingFileAttachments = app.getAttachedFileIds()
                formatter.printThinkingStatus()
                let stream = try await app.msg(
                    message: input,
                    enableReasoning: currentReasoning,
                    enableDeepSearch: currentDeepSearch,
                    disableSearch: currentNoSearch,
                    customInstructions: currentNoCustomInstructions ? "" : GrokCLI.getCustomInstructions(),
                    temporary: currentPrivate,
                    mode: currentMode,
                    fileAttachments: pendingFileAttachments,
                    workspaceIds: app.getCurrentWorkspaceIds(),
                    streamOutput: currentStream
                )
                
                if currentStream {
                    try await formatter.printStreamingResponse(stream)
                } else {
                    var finalResponse: ConversationResponse?
                    for try await response in stream {
                        if response.isFinal {
                            finalResponse = response
                            break
                        }
                    }
                    if let response = finalResponse {
                        formatter.printResponse(
                            response.message,
                            conversationId: app.getCurrentConversationId(),
                            responseId: app.getLastResponseId(),
                            debug: enableDebug,
                            webSearchResults: response.webSearchResults,
                            xposts: response.xposts
                        )
                    }
                }
                if !pendingFileAttachments.isEmpty {
                    app.clearAttachedFiles()
                }
            } catch {
                await app.handleError(error, debug: enableDebug)
            }
        }
    
    }
    
    // Handle the message command
    static func handleMessageCommand(args: [String], exitOnError: Bool = false) async throws {
        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printMessageUsage()
            return
        }

        guard !args.isEmpty else {
            print("Error: Please provide a message to send".red)
            if exitOnError {
                exit(with: 2)
            }
            return
        }
        
        // Parse options (very simple for now)
        var message: [String] = []
        var enableReasoning = false
        var enableDeepSearch = false
        var outputFormat = OutputFormat.defaultFormat
        var enableDebug = false
        var enableNoSearch = false
        var enableNoCustomInstructions = false
        var enablePrivate = false
        var enableStream = false  // Default to non-streaming for message command
        var selectedMode = GrokMode.defaultMode
        
        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil
            let modelOption = applyModelOption(arg, nextValue: nextValue)

            if modelOption.missingValue {
                print("Error: \(arg) requires a model value".red)
                if exitOnError {
                    exit(with: 2)
                }
                return
            } else if let mode = modelOption.mode {
                selectedMode = mode
                index += modelOption.consumedNext ? 2 : 1
                continue
            }

            let outputFormatOption = applyOutputFormatOption(arg, nextValue: nextValue)
            if outputFormatOption.missingValue {
                print("Error: \(arg) requires a format value".red)
                if exitOnError {
                    exit(with: 2)
                }
                return
            } else if let invalidValue = outputFormatOption.invalidValue {
                print("Error: Invalid output format '\(invalidValue)'. Use md or raw.".red)
                if exitOnError {
                    exit(with: 2)
                }
                return
            } else if let format = outputFormatOption.format {
                outputFormat = format
                index += outputFormatOption.consumedNext ? 2 : 1
                continue
            }

            if arg == "--reasoning" {
                enableReasoning = true
            } else if arg == "--deep-search" {
                enableDeepSearch = true
            } else if arg == "--debug" {
                enableDebug = true
            } else if arg == "--no-custom-instructions" {
                enableNoCustomInstructions = true
            } else if arg == "--no-search" {
                enableNoSearch = true
            } else if arg == "--private" {
                enablePrivate = true
            } else if arg == "--stream" {
                enableStream = true
            } else {
                message.append(arg)
            }
            index += 1
        }
        
        // Join message words
        let messageText = message.joined(separator: " ")
        guard !messageText.isEmpty else {
            print("Error: Please provide a message to send".red)
            if exitOnError {
                exit(with: 2)
            }
            return
        }
        
        // Execute the command
        print("Calling Grok API...".cyan)
        
        if enableDebug {
            print("Debug: Message = \"\(messageText)\"")
            print("Debug: Reasoning = \(enableReasoning)")
            print("Debug: DeepSearch = \(enableDeepSearch)")
            print("Debug: Realtime disabled = \(enableNoSearch)")
            print("Debug: Output Format = \(outputFormat.description)")
            print("Debug: Streaming = \(enableStream)")
            print("Debug: Model = \(selectedMode.displayName) (\(selectedMode.id))")
            print("Debug: Custom Instructions = \(enableNoCustomInstructions ? "OFF" : "ON")")
        }
        
        let app = GrokCLIApp.shared
        app.setDebugMode(enableDebug)
        app.setCurrentMode(selectedMode)
        
        // For single message commands, always reset the conversation
        app.resetConversation()
        
        let formatter = OutputFormatter(format: outputFormat)
        
        print("Sending: \(messageText)".cyan)
        formatter.printThinkingStatus()
        
        do {
            // Initialize client
            _ = try app.initializeClient()
            
            // Send message
            let stream = try await app.msg(
                message: messageText,
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                disableSearch: enableNoSearch,
                customInstructions: enableNoCustomInstructions ? "" : ChatCommand.defaultCustomInstructions,
                temporary: enablePrivate,
                mode: selectedMode,
                workspaceIds: app.getCurrentWorkspaceIds(),
                streamOutput: enableStream
            )
            
            if enableStream {
                // If streaming is enabled, print each chunk as it comes in
                try await formatter.printStreamingResponse(stream)
            } else {
                // If streaming is disabled, collect the responses and only show the final one
                var finalResponse: ConversationResponse?
                for try await response in stream {
                    if response.isFinal {
                        finalResponse = response
                        break
                    }
                }
                
                if let response = finalResponse {
                    // Display response
                    formatter.printResponse(
                        response.message,
                        conversationId: app.getCurrentConversationId(),
                        responseId: app.getLastResponseId(),
                        debug: enableDebug,
                        webSearchResults: response.webSearchResults,
                        xposts: response.xposts
                    )
                }
            }
        } catch {
            await app.handleError(error, debug: enableDebug)
            if exitOnError {
                exit(with: 1)
            }
        }
    }
    
    // Handle the auth command
    static func handleAuthCommand(
        args: [String],
        exitOnGenerateFailure: Bool = false,
        exitOnUsageError: Bool = false,
        exitOnImportFailure: Bool = false
    ) async throws {
        let args = normalizedAuthArgs(args)

        if args.first?.lowercased() == "help" || args.first == "-h" || args.first == "--help" {
            printAuthUsage()
            return
        }
        
        let subCommand = args.first?.lowercased() ?? "generate"
        let app = GrokCLIApp.shared
        
        switch subCommand {
        case "generate":
            if containsHelpArgument(Array(args.dropFirst())) {
                printAuthGenerateUsage()
                return
            }
            await generateAuthCredentials(
                app: app,
                args: args.isEmpty ? [] : Array(args.dropFirst()),
                exitOnFailure: exitOnGenerateFailure
            )
            
        case "import":
            if containsHelpArgument(Array(args.dropFirst())) {
                printAuthImportUsage()
                return
            }
            guard args.count > 1 else {
                print("Error: Please provide a path to the credentials file".red)
                if exitOnUsageError {
                    exit(with: 2)
                }
                return
            }
            
            let path = args[1]
            print("Importing credentials from \(path)...".cyan)
            
            do {
                try app.saveCredentials(from: path)
                print("Successfully imported credentials!".green)
            } catch {
                print("Error importing credentials: \(error.localizedDescription)".red)
                print("Please make sure the file exists and contains valid credentials.".yellow)
                if exitOnImportFailure {
                    exit(with: 1)
                }
            }
            
        default:
            if subCommand.hasPrefix("-") {
                await generateAuthCredentials(
                    app: app,
                    args: args,
                    exitOnFailure: exitOnGenerateFailure
                )
            } else {
                print("Unknown auth command: \(subCommand)".red)
                print("Run 'grok auth help' for available auth commands.".yellow)
                if exitOnUsageError {
                    exit(with: 2)
                }
            }
        }
    }

    static func normalizedAuthArgs(_ args: [String]) -> [String] {
        guard let first = args.first else {
            return args
        }

        let browser = first.lowercased()
        guard authBrowserNames.contains(browser) else {
            return args
        }

        return ["generate", "--browser", browser] + Array(args.dropFirst())
    }

    static func generateAuthCredentials(app: GrokCLIApp, args: [String], exitOnFailure: Bool) async {
        print("Extracting credentials from browser...".cyan)
        fflush(stdout)
        do {
            let credentialsPath = try await app.generateCredentials(args: args)
            print("Successfully generated credentials!".green)
            print("Saved to: \(credentialsPath)".cyan)
        } catch {
            print("Error generating credentials: \(error.localizedDescription)".red)
            print("Please make sure you're logged in to Grok in your browser.".yellow)
            if exitOnFailure {
                processExit(1)
            }
        }
    }

    static func printAuthUsage() {
        print("Auth commands:".cyan)
        print("  auth          - Generate new credentials from browser cookies")
        print("  generate      - Generate new credentials from browser cookies")
        print("  safari        - Generate credentials from Safari")
        print("  chrome        - Generate credentials from Chrome")
        print("  <browser>     - Browser shortcut: auto, safari, atlas, chrome, firefox, chromium, brave, edge, arc")
        print("  import <file> - Import credentials from a JSON file")
    }

    static func printAuthGenerateUsage() {
        print("""
        Usage: grok auth generate [--browser <name>] [--quiet]

        Generates credentials from browser cookies.
        Browser shortcuts: auto, safari, atlas, chrome, firefox, chromium, brave, edge, arc
        """)
    }

    static func printAuthImportUsage() {
        print("""
        Usage: grok auth import <file>

        Imports credentials from a JSON file.
        """)
    }
    
    // Show help information
    static func showHelp() {
        print("""
        
         ██████╗ ██████╗  ██████╗ ██╗  ██╗
        ██╔════╝ ██╔══██╗██╔═══██╗██║ ██╔╝
        ██║  ███╗██████╔╝██║   ██║█████╔╝ 
        ██║   ██║██╔══██╗██║   ██║██╔═██╗ 
        ╚██████╔╝██║  ██║╚██████╔╝██║  ██╗
         ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝
        
        Grok 4 up in your terminal
        
        Usage: grok [command] [options]
        
        Running just 'grok' with no commands starts an interactive chat session.
        
        Commands:
          chat              - Start an interactive chat session
          message <text>    - Send a message to Grok and exit
          auth              - Authentication commands
          list              - List and manage saved conversations
          models            - Show available Grok web modes
          agents            - Manage Grok multi-agent personalities
          tasks             - List, create, and archive Grok tasks
          skills            - List Grok skills and your enabled skills
          workspaces        - List, create, inspect, and delete Grok workspaces
          files             - Upload and list Grok assets
          help              - Show help information
        
        App Options:
          --reasoning       - Enable reasoning mode for step-by-step explanations
          --deep-search     - Enable deep search for more comprehensive answers
          --no-search       - Disable real-time data (no web or x search)
          --markdown, -m    - Use markdown formatting in output (default)
          --raw             - Show raw Markdown text in output
          --format <md|raw> - Choose output format
          --debug           - Show debug information
          --no-custom-instructions - Disable stored custom instructions
          --private         - Enable private mode (conversations will not be saved)
          --stream          - Stream responses as they are generated
          --model <mode>    - Use auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId
        
        Chat Commands:
          /new              - Start a new conversation
          /help             - Show interactive command help
          /list             - List and load past conversations
          /tasks            - List or manage tasks
          /agents           - List or manage agent personalities
          /skills           - List Grok skills
          /workspaces       - List or manage workspaces
          /files            - List files/assets
          /auth             - Refresh browser credentials
          /auth help        - Show auth commands
          /agents help      - Show agent management usage
          /tasks help       - Show task command usage
          /skills help      - Show skills command usage
          /workspaces help  - Show workspace command usage
          /files help       - Show file command usage
          /workspace        - Choose the project for new chats
          /workspace select - Choose the project for new chats
          /attach           - Browse files and attach one to following messages
          /attach upload    - Upload a local file and attach it
          /attach clear     - Remove all attached files
          /reason [on|off]  - Toggle reasoning mode
          /reasoning        - Alias for /reason
          /search [on|off]  - Toggle deep search mode
          /deepsearch       - Alias for /search
          /realtime [on|off] - Toggle real-time data on/off
          /model <mode>     - Switch model for following messages
          /mode, /models    - Model command aliases
          models <mode>     - Common commands also work without the slash
          /format [md|raw]  - Toggle or choose Markdown/Raw output
          /md, /markdown    - Enable Markdown output
          /raw [on|off]     - Toggle raw Markdown output
          /private [on|off] - Toggle private mode (conversations not saved)
          /stream [on|off]  - Toggle streaming responses
          /custom-instructions [on|off] - Toggle custom instructions
          /edit-instructions - Edit stored custom instructions
          /reset-instructions - Reset custom instructions to defaults
          /reset-conversation - Clear the current conversation context
          /personality      - Deprecated Grok 3 personality presets
          /special          - Start a private special-mode conversation
          /clear            - Clear the current screen
          /cls              - Alias for /clear
          /exit, /quit      - Exit the app
        
        Notes:
          - In chat mode, conversation context is maintained between messages
          - Use '/new' to start a new conversation thread
          - Use 'exit' or '/exit' to exit the app
          - The message command always starts a new conversation without context
        
        Examples:
          grok                                      - Start interactive chat mode
          grok Hello                                - Start chat with initial message "Hello"
          grok message Hello, how are you today?    - Send a message and exit
          grok message --model expert Explain this  - Send a message using Expert
          grok auth                                 - Generate new credentials from browser cookies
          grok models                               - Show available web modes
          grok agents list                          - List built-in agent IDs
          grok agents set 0 --instructions "Answer briefly."
                                                    - Set agent 0 instructions
          grok agents sync-custom                   - Copy old custom instructions to agent 0
          Agent 0 uses the old custom-instructions role.
          grok tasks                                - List tasks
          grok skills                               - List skills
          grok workspaces                           - List workspaces
          grok workspaces delete <workspaceId>      - Delete a workspace
          grok files list                           - List recent assets
          grok list                                 - List and select from saved conversations
        """.green.bold)
    }

    // Handle the list command
    static func handleListCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        // let formatter = OutputFormatter(useMarkdown: false)
        
        // Parse options
        var enableDebug = false
        
        for arg in args {
            if isHelpArgument(arg) {
                printListUsage()
                return
            } else if arg == "--debug" {
                enableDebug = true
            } else {
                print("Error: Unknown option for list: \(arg)".red)
                printListUsage()
                if exitOnError {
                    exit(with: 2)
                }
                return
            }
        }
        
        app.setDebugMode(enableDebug)
        
        print("Fetching your saved conversations...".cyan)
        
        do {
            if enableDebug {
                print("Debug: Attempting to list conversations...")
            }
            
            let client = try app.initializeClient()
            
            if enableDebug {
                print("Debug: Client initialized successfully")
                print("Debug: Calling listConversations API endpoint...")
            }
            
            let conversations = try await client.listConversations()
            
            if app.getDebugMode() {
                print("Debug: Retrieved \(conversations.count) conversations")
            }
            
            if conversations.isEmpty {
                print("No conversations found.".yellow)
                return
            }
            
            print("Available conversations:".cyan)
            for (index, conversation) in conversations.enumerated() {
                print("\(index + 1). \(conversation.title)")
            }
            
            print("Select a conversation by number (or press Enter to exit): ", terminator: "")
            if let selection = readLine(), !selection.isEmpty, let number = Int(selection), number > 0, number <= conversations.count {
                let selected = conversations[number - 1]
                
                if enableDebug {
                    print("Debug: Selected conversation ID: \(selected.conversationId)")
                    print("Debug: Selected conversation title: \(selected.title)")
                    print("Debug: Loading conversation responses...")
                }
                
                print("\nLoading conversation \"\(selected.title)\"...".green)
                let responses = try await app.loadConversation(conversationId: selected.conversationId)
                
                if app.getDebugMode() {
                    print("Debug: Loaded \(responses.count) responses")
                }
                
                print("\n\(selected.title)\n".green)
                if responses.isEmpty {
                    print("This conversation has no messages yet.".yellow)
                } else {
                    //print("Conversation history:".cyan)
                    for response in responses {
                        let sender = response.sender == "human" ? "User".magenta : "Grok".cyan
                        print("\(sender)\n\(response.message)\n")
                    }
                }
            } else {
                if enableDebug {
                    print("Debug: User exited selection or provided invalid input")
                }
            }
        } catch {
            await app.handleError(error, debug: enableDebug)
            if exitOnError {
                exit(with: 1)
            }
        }
    }
    
    // Deprecated compatibility shim for the old personality selection menu.
    static func showPersonalityMenu(app: GrokCLIApp) -> GrokClient.PersonalityType {
        print(personalityDeprecationMessage.yellow)
        print("Use custom instructions for explicit custom behavior.".blue)
        return .none
    }
}

// removed from app options for now
// --no-custom-instructions - Disable custom instructions

//  removed from slash commands
// /reset-conversation - Clear the current conversation context
//  /custom           - Toggle custom instructions

// Utilities

private enum StreamDisplayEvent {
    case text(String)
    case trace(String)
}

private final class GrokStreamMarkupParser {
    private let hiddenPreamble = "Thinking about your request"
    private let hidesHiddenPreamble: Bool
    private var buffer = ""
    private var emittedTraceLines = Set<String>()

    init(hidesHiddenPreamble: Bool = true) {
        self.hidesHiddenPreamble = hidesHiddenPreamble
    }

    func consume(_ chunk: String) -> [StreamDisplayEvent] {
        buffer += chunk
        return drain(final: false)
    }

    func finish() -> [StreamDisplayEvent] {
        drain(final: true)
    }

    var hasPendingContent: Bool {
        !buffer.isEmpty
    }

    private func drain(final: Bool) -> [StreamDisplayEvent] {
        var events: [StreamDisplayEvent] = []

        while !buffer.isEmpty {
            if hidesHiddenPreamble && buffer.hasPrefix(hiddenPreamble) {
                buffer.removeFirst(hiddenPreamble.count)
                continue
            }

            if hidesHiddenPreamble && !final && hiddenPreamble.hasPrefix(buffer) {
                break
            }

            guard let tagStart = buffer.firstIndex(of: "<") else {
                appendVisibleText(buffer, to: &events)
                buffer.removeAll(keepingCapacity: true)
                break
            }

            if tagStart > buffer.startIndex {
                let text = String(buffer[..<tagStart])
                appendVisibleText(text, to: &events)
                buffer.removeSubrange(..<tagStart)
                continue
            }

            if buffer.hasPrefix("<xai:tool_usage_card>") {
                if consumeToolUsageCard(to: &events) {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            if buffer.hasPrefix("<grok:render") {
                if consumeRenderDirective() {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            if buffer.hasPrefix("<xai:") || buffer.hasPrefix("</xai:") || buffer.hasPrefix("<grok:") || buffer.hasPrefix("</grok:") {
                if consumeInternalTag() {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            if !final && buffer.count == 1 {
                break
            }

            appendVisibleText("<", to: &events)
            buffer.removeFirst()
        }

        return events
    }

    private func consumeToolUsageCard(to events: inout [StreamDisplayEvent]) -> Bool {
        let closeTag = "</xai:tool_usage_card>"
        guard let closeRange = buffer.range(of: closeTag) else {
            return false
        }

        let blockEnd = closeRange.upperBound
        let block = String(buffer[..<blockEnd])
        buffer.removeSubrange(..<blockEnd)

        guard let traceLine = summarizeToolUsageCard(block), !emittedTraceLines.contains(traceLine) else {
            return true
        }

        emittedTraceLines.insert(traceLine)
        events.append(.trace(traceLine))
        return true
    }

    private func consumeRenderDirective() -> Bool {
        let closeTag = "</grok:render>"
        guard let closeRange = buffer.range(of: closeTag) else {
            return false
        }
        buffer.removeSubrange(..<closeRange.upperBound)
        return true
    }

    private func consumeInternalTag() -> Bool {
        guard let tagEnd = buffer.firstIndex(of: ">") else {
            return false
        }
        buffer.removeSubrange(...tagEnd)
        return true
    }

    private func appendVisibleText(_ text: String, to events: inout [StreamDisplayEvent]) {
        let cleaned = hidesHiddenPreamble ? text.replacingOccurrences(of: hiddenPreamble, with: "") : text
        guard !cleaned.isEmpty else { return }
        events.append(.text(cleaned))
    }

    private func summarizeToolUsageCard(_ block: String) -> String? {
        let toolName = xmlValue(named: "xai:tool_name", in: block) ?? "tool"
        let argsText = xmlValue(named: "xai:tool_args", in: block).map(stripCDATA)
        let args = argsText.flatMap(jsonDictionary)

        switch toolName {
        case "web_search":
            if let query = stringValue(args, key: "query") {
                return "Search: \(compact(query))"
            }
            return "Search"
        case "x_search":
            if let query = stringValue(args, key: "query") {
                return "Search X: \(compact(query))"
            }
            return "Search X"
        case "code_execution", "code":
            let code = stringValue(args, key: "code") ?? argsText ?? ""
            return "Thinking: \(summarizeCode(code))"
        default:
            let displayName = toolName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            if let query = stringValue(args, key: "query") {
                return "\(displayName): \(compact(query))"
            }
            return displayName
        }
    }

    private func xmlValue(named tagName: String, in text: String) -> String? {
        let openTag = "<\(tagName)>"
        let closeTag = "</\(tagName)>"
        guard let openRange = text.range(of: openTag),
              let closeRange = text.range(of: closeTag, range: openRange.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[openRange.upperBound..<closeRange.lowerBound])
    }

    private func stripCDATA(_ value: String) -> String {
        var stripped = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("<![CDATA[") {
            stripped.removeFirst("<![CDATA[".count)
        }
        if stripped.hasSuffix("]]>") {
            stripped.removeLast("]]>".count)
        }
        return stripped
    }

    private func jsonDictionary(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func stringValue(_ dictionary: [String: Any]?, key: String) -> String? {
        guard let value = dictionary?[key] else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private func summarizeCode(_ code: String) -> String {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                let comment = trimmed.drop(while: { $0 == "#" || $0 == " " })
                if !comment.isEmpty {
                    return compact(String(comment))
                }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return compact(trimmed)
            }
        }

        return "working through the problem"
    }

    private func compact(_ text: String, limit: Int = 140) -> String {
        let compacted = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard compacted.count > limit else {
            return compacted
        }

        let endIndex = compacted.index(compacted.startIndex, offsetBy: limit - 1)
        return "\(compacted[...endIndex])..."
    }
}

// Output formatting
class OutputFormatter {
    var format: OutputFormat

    private var useMarkdown: Bool {
        format == .markdown
    }

    private var markdownBuffer = ""
    private var markdownInCodeBlock = false
    private var pendingTableLines: [String] = []
    private var transientStatusActive = false
    
    init(format: OutputFormat = .defaultFormat) {
        self.format = format
    }

    convenience init(useMarkdown: Bool) {
        self.init(format: useMarkdown ? .markdown : .raw)
    }

    func flushBuffer(resetMarkdownState: Bool = false) {
        guard useMarkdown else { return }

        flushCompleteMarkdownLines()
        if !markdownBuffer.isEmpty {
            printMarkdownLine(markdownBuffer)
            markdownBuffer = ""
        }
        flushPendingTable()
        if resetMarkdownState {
            markdownInCodeBlock = false
        }
        fflush(stdout)
    }

    func printThinkingStatus() {
        clearTransientStatus()
        print("Thinking".blue, terminator: "")
        transientStatusActive = true
        fflush(stdout)
    }

    func printStreamingResponse(_ stream: AsyncThrowingStream<ConversationResponse, Error>) async throws {
        let answerParser = GrokStreamMarkupParser()
        let thinkingParser = GrokStreamMarkupParser(hidesHiddenPreamble: false)
        var printedText = false
        var printedTrace = false
        var finalResponse: ConversationResponse?
        var sawNonFinalEvent = false
        var pendingAnswerEvents: [StreamDisplayEvent] = []

        func renderTraceLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            clearTransientStatus()
            if printedText {
                return
            }
            printedTrace = true
            let quotedLine = "> \(trimmed)"
            if trimmed.hasPrefix("Thinking:") {
                print(quotedLine.blue)
            } else {
                print(quotedLine.cyan)
            }
            fflush(stdout)
        }

        func traceLines(from events: [StreamDisplayEvent]) -> [String] {
            events.flatMap { event -> [String] in
                switch event {
                case .trace(let line):
                    return [line]
                case .text(let text):
                    return text
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        }

        func renderAnswerEvent(_ event: StreamDisplayEvent) {
            switch event {
            case .trace(let line):
                renderTraceLine(line)
            case .text(let text):
                renderText(text)
            }
        }

        func renderText(_ text: String) {
            guard !text.isEmpty else { return }
            clearTransientStatus()
            if !printedText {
                let prefix = printedTrace ? "\n" : ""
                print(prefix + "Grok:".green.bold)
                printedText = true
            }
            if useMarkdown {
                printMarkdownChunk(text)
            } else {
                print(text, terminator: "")
            }
            fflush(stdout)
        }

        func releasePendingAnswerIfReady(force: Bool = false) {
            guard !pendingAnswerEvents.isEmpty else { return }
            guard force || !thinkingParser.hasPendingContent else { return }

            let events = pendingAnswerEvents
            pendingAnswerEvents.removeAll()
            events.forEach(renderAnswerEvent)
        }

        func handleAnswerEvents(_ events: [StreamDisplayEvent]) {
            guard !events.isEmpty else { return }
            if !printedText && (thinkingParser.hasPendingContent || !pendingAnswerEvents.isEmpty) {
                pendingAnswerEvents.append(contentsOf: events)
                releasePendingAnswerIfReady()
                return
            }

            for event in events {
                renderAnswerEvent(event)
            }
        }

        func handleThinking(_ text: String) {
            let lines = traceLines(from: thinkingParser.consume(text))
            guard !lines.isEmpty else { return }
            for line in lines {
                renderTraceLine(line)
            }
            releasePendingAnswerIfReady()
        }

        for try await response in stream {
            if response.isSoftStop && response.message.isEmpty {
                continue
            }

            if response.isFinal {
                finalResponse = response
                if !sawNonFinalEvent && !printedText {
                    handleAnswerEvents(answerParser.consume(response.message))
                }
            } else if response.isThinking {
                sawNonFinalEvent = true
                handleThinking(response.message)
            } else {
                sawNonFinalEvent = true
                handleAnswerEvents(answerParser.consume(response.message))
            }
        }

        handleAnswerEvents(answerParser.finish())
        for line in traceLines(from: thinkingParser.finish()) {
            renderTraceLine(line)
        }
        releasePendingAnswerIfReady(force: true)

        clearTransientStatus()
        if printedText {
            flushBuffer(resetMarkdownState: true)
            print("")
        } else if transientStatusActive {
            print("")
        }

        if let finalResponse {
            printSources(webSearchResults: finalResponse.webSearchResults, xposts: finalResponse.xposts)
        }
    }

    private func clearTransientStatus() {
        guard transientStatusActive else { return }
        print("\r\u{001B}[2K", terminator: "")
        transientStatusActive = false
    }
    
    func printResponse(_ response: String, conversationId: String? = nil, responseId: String? = nil, debug: Bool = false, webSearchResults: [WebSearchResult]? = nil, xposts: [XPost]? = nil) {
        clearTransientStatus()
        print("\n" + "Grok:".green.bold)
        
        if useMarkdown {
            markdownBuffer = ""
            markdownInCodeBlock = false
            pendingTableLines.removeAll()
            printMarkdown(response)
            markdownInCodeBlock = false
            pendingTableLines.removeAll()
        } else {
            print(response)
        }
        
        let webSearchCount = webSearchResults?.count ?? 0
        let xpostsCount = xposts?.count ?? 0
        
        if webSearchCount > 0 || xpostsCount > 0 {
            print("\n" + "Sources:".cyan)
            if webSearchCount > 0 {
                print("Web search results: \(webSearchCount)".yellow)
            }
            if xpostsCount > 0 {
                print("X posts: \(xpostsCount)".yellow)
            }
        }
        
        if debug, let conversationId = conversationId, let responseId = responseId {
            print("\n" + "Debug Info:".cyan)
            print("Conversation ID: \(conversationId)".cyan)
            print("Response ID: \(responseId)".cyan)
        }
        
        print("")
        fflush(stdout)
    }
    
    func printStreamingChunk(_ chunk: String, isFirst: Bool, isLast: Bool) {
        clearTransientStatus()
        if isFirst {
            print("\n" + "Grok:".green.bold, terminator: "")
        }
        
        if useMarkdown {
            printMarkdownChunk(chunk)
            if isLast {
                flushBuffer(resetMarkdownState: true)
            }
        } else {
            print(chunk, terminator: "")
        }
        
        if isLast {
            let webSearchCount = GrokCLIApp.shared.getLastWebSearchResults()?.count ?? 0
            let xpostsCount = GrokCLIApp.shared.getLastXPosts()?.count ?? 0
            
            if webSearchCount > 0 || xpostsCount > 0 {
                print("\n" + "Sources:".cyan)
                if webSearchCount > 0 {
                    print("Web search results: \(webSearchCount)".yellow)
                }
                if xpostsCount > 0 {
                    print("X posts: \(xpostsCount)".yellow)
                }
            }
            
            print("")
        }
        
        fflush(stdout)
    }
    
    func printChunk(_ chunk: String, isFirst: Bool) {
        clearTransientStatus()
        if isFirst {
            print("\n" + "Grok:".green.bold, terminator: "")
        }
        if useMarkdown {
            printMarkdownChunk(chunk)
        } else {
            print(chunk, terminator: "")
        }
        fflush(stdout)
    }
    
    func printSources(webSearchResults: [WebSearchResult]?, xposts: [XPost]?) {
        clearTransientStatus()
        flushBuffer(resetMarkdownState: true)

        let webSearchCount = webSearchResults?.count ?? 0
        let xpostsCount = xposts?.count ?? 0
        if webSearchCount > 0 || xpostsCount > 0 {
            print("\n" + "Sources:".cyan)
            if webSearchCount > 0 {
                print("Web search results: \(webSearchCount)".yellow)
            }
            if xpostsCount > 0 {
                print("X posts: \(xpostsCount)".yellow)
            }
        }
        print("")
    }
    
    func printError(_ message: String) {
        print(message.red)
    }
    
    func printHelp() {
        print("""
        
        \("Basic Commands:".cyan.bold)
        - \("new".yellow): Start a new conversation thread
        - \("help".yellow): Show this help message
        - \("exit".yellow): Exit the app
        
        \("Slash Commands:".cyan.bold)
        - \("/new".yellow): Start a new conversation thread
        - \("/help".yellow): Show this help message
        - \("/list".yellow): List and load past conversations
        - \("/tasks".yellow): List or manage tasks
        - \("/agents".yellow): List or manage agent personalities
        - \("/skills".yellow): List Grok skills
        - \("/auth".yellow): Refresh browser credentials
        - \("/workspaces".yellow): List or manage workspaces
        - \("/workspace".yellow): Choose the project for new chats
        - \("/files".yellow): List files/assets
        - \("/auth help".yellow): Show auth commands
        - \("/agents help".yellow): Show agent management usage
        - \("/tasks help".yellow): Show task command usage
        - \("/skills help".yellow): Show skills command usage
        - \("/workspaces help".yellow): Show workspace command usage
        - \("/files help".yellow): Show file command usage
        - \("/workspace select".yellow): Choose the project for new chats
        - \("/attach".yellow): Browse files and attach one to following messages
        - \("/attach upload <path>".yellow): Upload a local file and attach it
        - \("/attach clear".yellow): Remove all attached files
        - \("/reason [on|off]".yellow): Toggle reasoning mode on/off
        - \("/reasoning [on|off]".yellow): Alias for /reason
        - \("/search [on|off]".yellow): Toggle deep search on/off
        - \("/deepsearch [on|off]".yellow): Alias for /search
        - \("/realtime [on|off]".yellow): Toggle real-time data on/off
        - \("/model <mode>".yellow): Switch web model/mode
        - \("/mode, /models, /modes".yellow): Model command aliases
        - \("models <mode>".yellow): Common commands also work without the slash
        - \("/format [md|raw]".yellow): Toggle or choose Markdown/Raw output
        - \("/md, /markdown".yellow): Enable Markdown output
        - \("/raw [on|off]".yellow): Toggle raw Markdown output
        - \("/private [on|off]".yellow): Toggle private mode on/off
        - \("/stream [on|off]".yellow): Toggle streaming responses on/off
        - \("/personality".yellow): Deprecated Grok 3 personality presets
        - \("/custom-instructions [on|off]".yellow): Toggle custom instructions
        - \("/custom [on|off]".yellow): Alias for /custom-instructions
        - \("/edit-instructions".yellow): Edit custom instructions
        - \("/reset-instructions".yellow): Reset custom instructions to defaults
        - \("/reset-conversation".yellow): Clear the current conversation context
        - \("/special".yellow): Start a private special-mode conversation
        - \("/clear".yellow): Clear the screen
        - \("/cls".yellow): Alias for /clear
        - \("/exit, /quit".yellow): Exit the app
        
        \("Defaults:".cyan.bold)
        - \("/agents, /tasks, /skills, /workspaces, /files".yellow): List by default
        - \("/workspace, /attach, /model".yellow): Open a picker by default
        - Unknown slash commands show an error; unknown bare text is sent as chat
        
        \("Modes:".cyan.bold)
        - \("Reasoning".yellow): Enables Grok reasoning model for hard problems
        - \("DeepSearch".yellow): Conduct in-depth analysis with research agent
        - \("Realtime".yellow): Enables real-time data from web and X search
        - \("Model".yellow): auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId
        - \("Private Mode".yellow): When enabled, conversations will not be saved
        - \("Streaming".yellow): Displays responses as they are generated
        - \("Output Format".yellow): Markdown is default; Raw preserves source Markdown
        - \("Personality".yellow): Deprecated; use custom instructions instead
        - \("Custom Instructions".yellow): Enables/disables custom personality for the assistant
        - \("Agent 0".yellow): Uses the old custom-instructions role
        
        """)
    }

    // temporarily hidden from slash commands 
    
    // - \("/custom".yellow): Toggle custom instructions
    // 
    // 

    // temporarily hidden from modes

    //- \("Conversation Threading".yellow): Messages maintain context within the current conversation
    // 
    
    func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }
    
    private func printMarkdownChunk(_ chunk: String) {
        markdownBuffer += chunk
        flushCompleteMarkdownLines()
    }

    private func flushCompleteMarkdownLines() {
        while let newlineIndex = markdownBuffer.firstIndex(of: "\n") {
            var line = String(markdownBuffer[..<newlineIndex])
            if line.last == "\r" {
                line.removeLast()
            }
            printMarkdownLine(line)
            markdownBuffer.removeSubrange(...newlineIndex)
        }
    }

    // Simple markdown formatter
    private func printMarkdown(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            printMarkdownLine(String(line))
        }
        flushPendingTable()
    }

    private func printMarkdownLine(_ lineStr: String) {
        if !markdownInCodeBlock {
            if isPotentialTableLine(lineStr) {
                pendingTableLines.append(lineStr)
                return
            }
            flushPendingTable()
        }

        renderMarkdownLine(lineStr)
    }

    private func renderMarkdownLine(_ lineStr: String) {
        if lineStr.hasPrefix("```") {
            markdownInCodeBlock.toggle()
            print(lineStr.magenta)
            return
        }

        if markdownInCodeBlock {
            print(lineStr.blue)
            return
        }

        if let heading = markdownHeading(in: lineStr) {
            switch heading.level {
            case 1:
                print(formatInlineMarkdown(heading.text).magenta.bold)
            case 2:
                print(formatInlineMarkdown(heading.text).cyan.bold)
            default:
                print(formatInlineMarkdown(heading.text).cyan)
            }
            return
        }

        if isHorizontalRule(lineStr) {
            print(String(repeating: "-", count: 48).magenta)
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^(\s*)([-*+])\s+\[([ xX])\]\s+(.*)$"#) {
            let checkbox = captures[3].lowercased() == "x" ? "☑" : "☐"
            print("\(captures[1])\(checkbox) \(formatInlineMarkdown(captures[4]))")
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^(\s*)(\d+[.)])\s+(.*)$"#) {
            print("\(captures[1])\(captures[2]) \(formatInlineMarkdown(captures[3]))")
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^(\s*)([-*+])\s+(.*)$"#) {
            print("\(captures[1])• \(formatInlineMarkdown(captures[3]))")
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^\s*>\s?(.*)$"#) {
            print(("> " + formatInlineMarkdown(captures[1])).green)
            return
        }

        print(formatInlineMarkdown(lineStr))
    }

    private func markdownHeading(in line: String) -> (level: Int, text: String)? {
        guard let captures = firstMatch(line, pattern: #"^(#{1,3})\s+(.+)$"#) else {
            return nil
        }
        return (captures[1].count, captures[2])
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 3 else {
            return false
        }
        return compact.allSatisfy { $0 == "-" } ||
            compact.allSatisfy { $0 == "*" } ||
            compact.allSatisfy { $0 == "_" }
    }

    private func formatInlineMarkdown(_ input: String) -> String {
        var protected: [String] = []
        var text = input

        func protect(_ value: String) -> String {
            let token = "GROKMDTOKEN\(protected.count)PLACEHOLDER"
            protected.append(value)
            return token
        }

        text = replaceMatches(in: text, pattern: #"`([^`]+)`"#) { captures in
            protect(captures[1].cyan)
        }
        text = replaceMatches(in: text, pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#) { captures in
            let alt = captures[1].isEmpty ? "image" : captures[1]
            return protect("Image: \(alt) (\(captures[2]))".cyan)
        }
        text = replaceMatches(in: text, pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#) { captures in
            protect("\(captures[1].cyan) (\(captures[2]))")
        }
        text = replaceMatches(in: text, pattern: #"~~(.+?)~~"#) { captures in
            captures[1]
        }
        text = replaceMatches(in: text, pattern: #"\*\*\*(.+?)\*\*\*"#) { captures in
            captures[1].bold.italic
        }
        text = replaceMatches(in: text, pattern: #"\*\*(.+?)\*\*"#) { captures in
            captures[1].bold
        }
        text = replaceMatches(in: text, pattern: #"__(.+?)__"#) { captures in
            captures[1].bold
        }
        text = replaceMatches(in: text, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#) { captures in
            captures[1].italic
        }
        text = replaceMatches(in: text, pattern: #"(?<!_)_([^_\n]+)_(?!_)"#) { captures in
            captures[1].italic
        }

        for (index, value) in protected.enumerated() {
            text = text.replacingOccurrences(of: "GROKMDTOKEN\(index)PLACEHOLDER", with: value)
        }
        return text
    }

    private enum TableAlignment {
        case left
        case right
        case center
    }

    private func isPotentialTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("|")
    }

    private func flushPendingTable() {
        guard !pendingTableLines.isEmpty else {
            return
        }

        let lines = pendingTableLines
        pendingTableLines.removeAll()

        guard lines.count >= 2,
              let header = parseTableRow(lines[0]),
              let alignments = parseTableSeparator(lines[1]) else {
            lines.forEach(renderMarkdownLine)
            return
        }

        let bodyRows = lines.dropFirst(2).compactMap(parseTableRow)
        let columnCount = max(
            header.count,
            alignments.count,
            bodyRows.map(\.count).max() ?? 0
        )
        guard columnCount > 0 else {
            lines.forEach(renderMarkdownLine)
            return
        }

        let normalizedAlignments = normalizedTableRow(alignments.map { $0 }, count: columnCount, defaultValue: .left)
        let formattedHeader = normalizedTableRow(header, count: columnCount).map(formatInlineMarkdown)
        let formattedRows = bodyRows.map { row in
            normalizedTableRow(row, count: columnCount).map(formatInlineMarkdown)
        }
        let widths = tableColumnWidths(rows: [formattedHeader] + formattedRows, columnCount: columnCount)

        print(renderTableRow(formattedHeader, widths: widths, alignments: normalizedAlignments))
        print(renderTableSeparator(widths: widths, alignments: normalizedAlignments))
        for row in formattedRows {
            print(renderTableRow(row, widths: widths, alignments: normalizedAlignments))
        }
    }

    private func parseTableRow(_ line: String) -> [String]? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else {
            return nil
        }
        if trimmed.first == "|" {
            trimmed.removeFirst()
        }
        if trimmed.last == "|" {
            trimmed.removeLast()
        }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func parseTableSeparator(_ line: String) -> [TableAlignment]? {
        guard let cells = parseTableRow(line), !cells.isEmpty else {
            return nil
        }
        var alignments: [TableAlignment] = []
        for cell in cells {
            let normalized = cell.replacingOccurrences(of: " ", with: "")
            let dashCount = normalized.filter { $0 == "-" }.count
            guard dashCount >= 1,
                  normalized.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }
            if normalized.hasPrefix(":"), normalized.hasSuffix(":") {
                alignments.append(.center)
            } else if normalized.hasSuffix(":") {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        return alignments
    }

    private func normalizedTableRow<T>(_ row: [T], count: Int, defaultValue: T) -> [T] {
        guard row.count < count else {
            return Array(row.prefix(count))
        }
        return row + Array(repeating: defaultValue, count: count - row.count)
    }

    private func normalizedTableRow(_ row: [String], count: Int) -> [String] {
        normalizedTableRow(row, count: count, defaultValue: "")
    }

    private func tableColumnWidths(rows: [[String]], columnCount: Int) -> [Int] {
        (0..<columnCount).map { column in
            rows.map { row in
                visibleLength(row[column])
            }.max() ?? 0
        }
    }

    private func renderTableRow(_ row: [String], widths: [Int], alignments: [TableAlignment]) -> String {
        let cells = row.enumerated().map { index, cell in
            " " + padded(cell, width: widths[index], alignment: alignments[index]) + " "
        }
        return "|" + cells.joined(separator: "|") + "|"
    }

    private func renderTableSeparator(widths: [Int], alignments: [TableAlignment]) -> String {
        let cells = widths.enumerated().map { index, width in
            let dashes = String(repeating: "-", count: max(width, 3) + 2)
            switch alignments[index] {
            case .left:
                return dashes
            case .right:
                return String(dashes.dropLast()) + ":"
            case .center:
                return ":" + String(dashes.dropFirst().dropLast()) + ":"
            }
        }
        return "|" + cells.joined(separator: "|") + "|"
    }

    private func padded(_ value: String, width: Int, alignment: TableAlignment) -> String {
        let missing = max(0, width - visibleLength(value))
        switch alignment {
        case .left:
            return value + String(repeating: " ", count: missing)
        case .right:
            return String(repeating: " ", count: missing) + value
        case .center:
            let left = missing / 2
            let right = missing - left
            return String(repeating: " ", count: left) + value + String(repeating: " ", count: right)
        }
    }

    private func visibleLength(_ value: String) -> Int {
        stripANSI(value).count
    }

    private func stripANSI(_ value: String) -> String {
        let escape = "\u{001B}"
        return value.replacingOccurrences(
            of: "\(escape)\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }

    private func firstMatch(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        return captureGroups(from: match, in: text)
    }

    private func replaceMatches(in text: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else {
            return text
        }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            let captures = captureGroups(from: match, in: text)
            result.replaceSubrange(range, with: transform(captures))
        }
        return result
    }

    private func captureGroups(from match: NSTextCheckingResult, in text: String) -> [String] {
        (0..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else {
                return ""
            }
            return String(text[range])
        }
    }
}

// Input reading
class InputReader {
    internal var history: [String] = []
    internal var historyIndex = 0
    private let commandSpecs: [GrokCLI.CommandSpec]
    private var previousRenderedLines = 0
    private var selectedSuggestionIndex: Int?
    private let maxSuggestions = 32

    init(commandSpecs: [GrokCLI.CommandSpec] = GrokCLI.interactiveCommandSpecs) {
        self.commandSpecs = commandSpecs
    }
    
    func readLine(prompt: String = "") -> String? {
        guard isatty(stdinFileDescriptor) == 1, isatty(stdoutFileDescriptor) == 1 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine()
        }

        var originalTermios = termios()
        guard tcgetattr(stdinFileDescriptor, &originalTermios) == 0 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine()
        }

        var rawTermios = originalTermios
        rawTermios.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &rawTermios.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }

        guard tcsetattr(stdinFileDescriptor, TCSANOW, &rawTermios) == 0 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine()
        }

        defer {
            tcsetattr(stdinFileDescriptor, TCSANOW, &originalTermios)
            clearRenderedBlock()
        }

        var buffer = ""
        var cursorIndex = 0
        selectedSuggestionIndex = nil
        historyIndex = history.count
        render(prompt: prompt, buffer: buffer, cursorIndex: cursorIndex)

        while true {
            guard let byte = readByte() else {
                return nil
            }

            switch byte {
            case 3:
                print("^C")
                processExit(130)
            case 4:
                if buffer.isEmpty {
                    print("")
                    return nil
                }
            case 21:
                buffer = ""
                cursorIndex = 0
                selectedSuggestionIndex = nil
            case 9:
                applyCompletion(buffer: &buffer, cursorIndex: &cursorIndex)
            case 10, 13:
                if let shouldSubmit = acceptSelectedSuggestion(buffer: &buffer, cursorIndex: &cursorIndex) {
                    if shouldSubmit {
                        commitLine(prompt: prompt, buffer: buffer)
                        addToHistory(buffer)
                        return buffer
                    }
                    render(prompt: prompt, buffer: buffer, cursorIndex: cursorIndex)
                    continue
                }
                commitLine(prompt: prompt, buffer: buffer)
                addToHistory(buffer)
                return buffer
            case 27:
                handleEscapeSequence(buffer: &buffer, cursorIndex: &cursorIndex)
            case 127, 8:
                if cursorIndex > 0 {
                    let index = buffer.index(buffer.startIndex, offsetBy: cursorIndex - 1)
                    buffer.remove(at: index)
                    cursorIndex -= 1
                    selectedSuggestionIndex = nil
                }
            default:
                if byte >= 32 {
                    let scalar = UnicodeScalar(Int(byte))!
                    let index = buffer.index(buffer.startIndex, offsetBy: cursorIndex)
                    buffer.insert(Character(scalar), at: index)
                    cursorIndex += 1
                    selectedSuggestionIndex = nil
                }
            }

            render(prompt: prompt, buffer: buffer, cursorIndex: cursorIndex)
        }
    }

    private func readFallbackLine() -> String? {
        guard let input = Swift.readLine() else {
            return nil
        }
        addToHistory(input)
        return input
    }

    private func addToHistory(_ input: String) {
        guard !input.isEmpty else { return }
        history.append(input)
        historyIndex = history.count
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let count = read(stdinFileDescriptor, &byte, 1)
        return count == 1 ? byte : nil
    }

    private func handleEscapeSequence(buffer: inout String, cursorIndex: inout Int) {
        guard let first = readByte(), first == UInt8(ascii: "["),
              let second = readByte() else {
            return
        }

        switch second {
        case UInt8(ascii: "A"):
            if moveSuggestionSelection(delta: -1, buffer: buffer) {
                return
            }
            if let previous = getPreviousCommand() {
                buffer = previous
                cursorIndex = buffer.count
            }
        case UInt8(ascii: "B"):
            if moveSuggestionSelection(delta: 1, buffer: buffer) {
                return
            }
            if let next = getNextCommand() {
                buffer = next
            } else {
                historyIndex = history.count
                buffer = ""
            }
            cursorIndex = buffer.count
        case UInt8(ascii: "C"):
            cursorIndex = min(cursorIndex + 1, buffer.count)
        case UInt8(ascii: "D"):
            cursorIndex = max(cursorIndex - 1, 0)
        default:
            break
        }
    }

    private func applyCompletion(buffer: inout String, cursorIndex: inout Int) {
        let suggestions = suggestions(for: buffer)
        guard !suggestions.isEmpty else { return }

        if let selectedSuggestion = selectedSuggestion(in: suggestions) {
            apply(suggestion: selectedSuggestion, to: &buffer, cursorIndex: &cursorIndex)
            return
        }

        if suggestions.count == 1 {
            apply(suggestion: suggestions[0], to: &buffer, cursorIndex: &cursorIndex)
            return
        }

        let sharedPrefix = longestCommonPrefix(suggestions.map(\.insertText))
        if sharedPrefix.count > buffer.count {
            buffer = sharedPrefix
            cursorIndex = buffer.count
        }
    }

    private func moveSuggestionSelection(delta: Int, buffer: String) -> Bool {
        let suggestions = suggestions(for: buffer)
        guard !suggestions.isEmpty else {
            selectedSuggestionIndex = nil
            return false
        }

        let currentIndex = selectedSuggestionIndex ?? (delta > 0 ? -1 : suggestions.count)
        let nextIndex = (currentIndex + delta + suggestions.count) % suggestions.count
        selectedSuggestionIndex = nextIndex
        return true
    }

    private func acceptSelectedSuggestion(buffer: inout String, cursorIndex: inout Int) -> Bool? {
        let suggestions = suggestions(for: buffer)
        guard let selectedSuggestion = selectedSuggestion(in: suggestions) else {
            return nil
        }
        let shouldSubmit = !selectedSuggestion.requiresArgument
        apply(
            suggestion: selectedSuggestion,
            to: &buffer,
            cursorIndex: &cursorIndex,
            appendingTrailingSpace: !shouldSubmit
        )
        selectedSuggestionIndex = nil
        return shouldSubmit
    }

    private func selectedSuggestion(in suggestions: [Suggestion]) -> Suggestion? {
        guard let selectedSuggestionIndex,
              suggestions.indices.contains(selectedSuggestionIndex) else {
            return nil
        }
        return suggestions[selectedSuggestionIndex]
    }

    private func apply(
        suggestion: Suggestion,
        to buffer: inout String,
        cursorIndex: inout Int,
        appendingTrailingSpace: Bool = true
    ) {
        buffer = suggestion.insertText
        if appendingTrailingSpace, !buffer.hasSuffix(" ") {
            buffer += " "
        }
        cursorIndex = buffer.count
        selectedSuggestionIndex = nil
    }

    private struct Suggestion {
        let display: String
        let insertText: String
        let description: String
        let requiresArgument: Bool
    }

    private func suggestions(for buffer: String) -> [Suggestion] {
        guard buffer.hasPrefix("/") else { return [] }

        let normalizedInput = buffer.lowercased()
        var seen = Set<String>()
        var results: [Suggestion] = []

        for spec in commandSpecs {
            let canonical = spec.command

            if normalizedInput == "/", canonical.contains(" ") {
                continue
            }

            let allNames = [canonical] + spec.aliases
            let matches = allNames.contains { name in
                let normalizedName = name.lowercased()
                return normalizedName.hasPrefix(normalizedInput) ||
                    normalizedInput.hasPrefix(normalizedName + " ")
            }

            guard matches, seen.insert(canonical).inserted else {
                continue
            }

            results.append(Suggestion(
                display: canonical,
                insertText: insertionText(for: canonical),
                description: spec.description,
                requiresArgument: canonical.contains("<")
            ))
        }

        return results
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private func insertionText(for command: String) -> String {
        command
            .split(separator: " ")
            .prefix { !$0.hasPrefix("<") }
            .joined(separator: " ")
    }

    private func render(prompt: String, buffer: String, cursorIndex: Int) {
        clearRenderedBlock()

        let suggestions = suggestions(for: buffer)
        if let selectedSuggestionIndex, !suggestions.indices.contains(selectedSuggestionIndex) {
            self.selectedSuggestionIndex = nil
        }
        let promptText = prompt.green
        print("\(promptText)\(buffer)", terminator: "")

        if !suggestions.isEmpty {
            print("")
            let commandWidth = min(28, max(12, suggestions.map(\.display.count).max() ?? 12))
            for (index, suggestion) in suggestions.enumerated() {
                let paddedCommand = suggestion.display.padding(toLength: commandWidth, withPad: " ", startingAt: 0)
                let marker = index == selectedSuggestionIndex ? "> " : "  "
                let command = index == selectedSuggestionIndex ? paddedCommand.yellow.bold : paddedCommand.yellow
                let description = index == selectedSuggestionIndex ? suggestion.description.bold : suggestion.description
                print("\(marker)\(command) \(description)")
            }
        }

        previousRenderedLines = 1 + suggestions.count
        let linesUp = suggestions.isEmpty ? 0 : suggestions.count + 1
        if linesUp > 0 {
            print("\u{001B}[\(linesUp)A", terminator: "")
        }
        print("\r", terminator: "")
        let cursorColumn = visibleLength(prompt) + cursorIndex
        if cursorColumn > 0 {
            print("\u{001B}[\(cursorColumn)C", terminator: "")
        }
        fflush(stdout)
    }

    private func commitLine(prompt: String, buffer: String) {
        clearRenderedBlock()
        print("\(prompt.green)\(buffer)")
        fflush(stdout)
    }

    private func clearRenderedBlock() {
        guard previousRenderedLines > 0 else { return }
        print("\r", terminator: "")
        print("\u{001B}[J", terminator: "")
        previousRenderedLines = 0
    }

    private func visibleLength(_ string: String) -> Int {
        string.count
    }

    private func longestCommonPrefix(_ values: [String]) -> String {
        guard var prefix = values.first else { return "" }
        for value in values.dropFirst() {
            while !value.hasPrefix(prefix), !prefix.isEmpty {
                prefix.removeLast()
            }
        }
        return prefix
    }
    
    // Basic history functionality - to be expanded with arrow key navigation in the future
    func getPreviousCommand() -> String? {
        guard !history.isEmpty, historyIndex > 0 else {
            return nil
        }
        
        historyIndex -= 1
        return history[historyIndex]
    }
    
    func getNextCommand() -> String? {
        guard !history.isEmpty, historyIndex < history.count - 1 else {
            return nil
        }
        
        historyIndex += 1
        return history[historyIndex]
    }
}

// Main application logic
class GrokCLIApp {
    static let shared = GrokCLIApp()
    
    private var client: GrokClient?
    private let configManager = ConfigManager()
    private var isDebug = false
    private var currentConversationId: String?
    private var lastResponseId: String?
    private var lastWebSearchResults: [WebSearchResult]?
    private var lastXPosts: [XPost]?
    private var currentPersonality: GrokClient.PersonalityType = .none
    private var currentMode: GrokMode = .defaultMode
    private var currentWorkspace: GrokWorkspace?
    private var attachedFileIds: [String] = []
    
    private init() {}
    
    // Enable debug mode
    func setDebugMode(_ enabled: Bool) {
        isDebug = enabled
    }
    
    // Get current debug mode state
    func getDebugMode() -> Bool {
        return isDebug
    }
    
    // Reset the current conversation ID
    func resetConversation() {
        currentConversationId = nil
        lastResponseId = nil
        lastWebSearchResults = nil
        lastXPosts = nil
    }

    func getCurrentWorkspace() -> GrokWorkspace? {
        currentWorkspace
    }

    func setCurrentWorkspace(_ workspace: GrokWorkspace?) {
        currentWorkspace = workspace
    }

    func getCurrentWorkspaceIds() -> [String] {
        guard let workspaceId = currentWorkspace?.workspaceId ?? currentWorkspace?.id else {
            return []
        }
        return [workspaceId]
    }

    func getAttachedFileIds() -> [String] {
        attachedFileIds
    }

    func addAttachedFileId(_ fileId: String) {
        guard !attachedFileIds.contains(fileId) else {
            return
        }
        attachedFileIds.append(fileId)
    }

    func clearAttachedFiles() {
        attachedFileIds.removeAll()
    }
    
    // Get the current conversation ID
    func getCurrentConversationId() -> String? {
        return currentConversationId
    }
    
    // Get the last response ID
    func getLastResponseId() -> String? {
        return lastResponseId
    }
    
    // Get the last web search results
    func getLastWebSearchResults() -> [WebSearchResult]? {
        return lastWebSearchResults
    }
    
    // Get the last X posts
    func getLastXPosts() -> [XPost]? {
        return lastXPosts
    }
    
    // Get current personality
    func getCurrentPersonality() -> GrokClient.PersonalityType {
        return currentPersonality
    }
    
    // Set current personality
    func setPersonality(_ personalityType: GrokClient.PersonalityType) {
        self.currentPersonality = personalityType
    }

    // Get current Grok web mode
    func getCurrentMode() -> GrokMode {
        return currentMode
    }

    // Set current Grok web mode
    func setCurrentMode(_ mode: GrokMode) {
        self.currentMode = mode
    }
    
    // Centralized error handling method
    @discardableResult
    func handleError(_ error: Error, debug: Bool) async -> Bool {
        print("\r\u{001B}[2K", terminator: "")
        let displayMessage = userFriendlyErrorMessage(for: error)
        print("Error: \(displayMessage)".red)
        if debug {
            if displayMessage != error.localizedDescription {
                print("Debug: Raw error: \(error.localizedDescription)".cyan)
            }
            print("Debug: Error details: \(error)".cyan)
            print("Debug: Error type: \(type(of: error))".cyan)
        }

        guard isAuthenticationError(error) else {
            return false
        }

        client = nil
        print("Authentication failed. Your saved Grok browser cookies may have expired.".yellow)
        print("Trying to refresh credentials from your browser...".cyan)
        fflush(stdout)

        do {
            let credentialsPath = try await generateCredentials()
            print("Successfully refreshed credentials from browser.".green)
            print("Saved to: \(credentialsPath)".cyan)
            print("Retry your last message or command.".yellow)
            return true
        } catch {
            print("Automatic browser credential refresh failed: \(error.localizedDescription)".red)
            print("Please log in to Grok in your browser, then run 'auth' here or 'grok auth' from your shell.".yellow)
            return false
        }
    }

    private func userFriendlyErrorMessage(for error: Error) -> String {
        if let rateLimitMessage = rateLimitMessage(for: error) {
            return rateLimitMessage
        }
        return error.localizedDescription
    }

    private func rateLimitMessage(for error: Error) -> String? {
        let rawMessage = error.localizedDescription
        let normalized = rawMessage.lowercased()
        let isRateLimited =
            normalized.contains("http error: 429") ||
            normalized.contains("too many requests") && normalized.contains("\"code\":8")

        guard isRateLimited else {
            return nil
        }

        if let waitTime = waitTimeHint(in: rawMessage) {
            return "Message limit reached. Grok is rate limiting this account right now. Wait \(waitTime), then try again."
        }

        return "Message limit reached. Grok is rate limiting this account right now. Wait a few minutes, then try again. The Grok web app may show the exact reset time for your plan."
    }

    private func waitTimeHint(in message: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\bwait\s+(\d+)\s+(second|minute|hour)s?\b"#
        ) else {
            return nil
        }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let numberRange = Range(match.range(at: 1), in: message),
              let unitRange = Range(match.range(at: 2), in: message) else {
            return nil
        }

        let number = String(message[numberRange])
        let unit = String(message[unitRange]).lowercased()
        let suffix = number == "1" ? "" : "s"
        return "\(number) \(unit)\(suffix)"
    }

    func isAuthenticationError(_ error: Error) -> Bool {
        guard let grokError = error as? GrokError else {
            return false
        }

        switch grokError {
        case .invalidCredentials, .unauthorized:
            return true
        case .apiError(let message):
            let normalized = message.lowercased()
            return normalized.contains("http error: 401") ||
                normalized.contains("http error: 403") ||
                normalized.contains("unauthorized") ||
                normalized.contains("forbidden") ||
                normalized.contains("not authenticated")
        default:
            return false
        }
    }
    
    // Load cookies directly from GrokCookies.swift file
    internal func getCookiesFromFile() throws -> [String: String] {
        // Try to find GrokCookies.swift in standard locations
        let potentialPaths = ["./GrokCookies.swift", "../GrokCookies.swift", "../../GrokCookies.swift"]
        
        for path in potentialPaths {
            if FileManager.default.fileExists(atPath: path) {
                if isDebug {
                    print("Debug: Found GrokCookies.swift at \(path)")
                }
                
                // Read file content
                let fileContent = try String(contentsOfFile: path)
                
                // Very simple parser for Swift dictionary literals
                let cookieRegex = try NSRegularExpression(pattern: #""([^"]+)":\s*"([^"]+)""#)
                let cookies = cookieRegex.matches(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent)).reduce(into: [String: String]()) { result, match in
                    guard let keyRange = Range(match.range(at: 1), in: fileContent),
                          let valueRange = Range(match.range(at: 2), in: fileContent) else { return }
                    let key = String(fileContent[keyRange])
                    let value = String(fileContent[valueRange])
                    result[key] = value
                }
                
                if !cookies.isEmpty {
                    if isDebug {
                        print("Debug: Successfully extracted \(cookies.count) cookies from file")
                    }
                    return cookies
                }
            }
        }
        
        throw GrokError.invalidCredentials
    }
    
    // Initialize the Grok client using available authentication methods
    func initializeClient() throws -> GrokClient {
        if let existingClient = client {
            return existingClient
        }
        
        if isDebug {
            print("Debug: Attempting to initialize GrokClient...")
        }
        
        // Try different authentication methods in order of preference
        if let savedCredentialsPath = configManager.getSavedCredentialsPath() {
            if isDebug {
                print("Debug: Found saved credentials at \(savedCredentialsPath)")
            }
            do {
                client = try GrokClient.fromJSONFile(at: savedCredentialsPath, isDebug: isDebug)
                return client!
            } catch {
                if isDebug {
                    print("Debug: Saved credentials failed: \(error.localizedDescription)")
                }
            }
        }

        do {
            if isDebug {
                print("Debug: Trying to load cookies directly from GrokCookies.swift file...")
            }
            
            let cookies = try getCookiesFromFile()
            client = try GrokClient(cookies: cookies, isDebug: isDebug)
            return client!
        } catch {
            if isDebug {
                print("Debug: Could not load cookies from file: \(error.localizedDescription)")
            }
        }

        do {
            if isDebug {
                print("Debug: Trying to initialize with auto cookies...")
            }
            client = try GrokClient.withAutoCookies(isDebug: isDebug)
            return client!
        } catch {
            if isDebug {
                print("Debug: Auto cookies failed: \(error.localizedDescription)")
                print("Debug: No usable credentials found")
            }
            throw GrokError.invalidCredentials
        }
    }
    
    // Send a message and get a streaming response
    func msg(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, disableSearch: Bool = false, customInstructions: String = "", temporary: Bool = false, personalityType: GrokClient.PersonalityType? = nil, mode: GrokMode? = nil, fileAttachments: [String] = [], workspaceIds: [String] = [], disabledConnectorIds: [String] = [], streamOutput: Bool = true) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let personality = personalityType ?? currentPersonality
        let selectedMode = mode ?? currentMode
        currentMode = selectedMode
        
        if isDebug {
            print("Debug: Sending message to Grok:")
            print("Debug: - Message: \(message)")
            print("Debug: - Reasoning: \(enableReasoning)")
            print("Debug: - Deep Search: \(enableDeepSearch)")
            print("Debug: - Disable Search: \(disableSearch)")
            print("Debug: - Custom Instructions: \(customInstructions.isEmpty ? "None" : "Enabled")")
            print("Debug: - Private Mode: \(temporary ? "ON" : "OFF")")
            print("Debug: - Personality: \(personality.displayName)")
            print("Debug: - Model: \(selectedMode.displayName) (\(selectedMode.id))")
            print("Debug: - File Attachments: \(fileAttachments.count)")
            print("Debug: - Workspaces: \(workspaceIds.count)")
            print("Debug: - Stream Output: \(streamOutput ? "YES" : "NO")")
            if let conversationId = currentConversationId {
                print("Debug: - Conversation ID: \(conversationId)")
                if let responseId = lastResponseId {
                    print("Debug: - Parent Response ID: \(responseId)")
                }
            } else {
                print("Debug: - Starting new conversation")
            }
        }
        
        let client = try initializeClient()
        
        if isDebug {
            print("Debug: Client initialized, starting stream...")
        }
        
        // Handle both new conversations and continuing existing ones
        return AsyncThrowingStream<ConversationResponse, Error> { continuation in
            Task {
                do {
                    let stream: AsyncThrowingStream<ConversationResponse, Error>
                    if let conversationId = currentConversationId {
                        // For existing conversations, use continueConversation with streaming API
                        stream = try await client.continueConversation(
                            conversationId: conversationId,
                            parentResponseId: lastResponseId,
                            message: message,
                            enableReasoning: enableReasoning,
                            enableDeepSearch: enableDeepSearch,
                            disableSearch: disableSearch,
                            customInstructions: customInstructions,
                            temporary: temporary,
                            personalityType: personality,
                            modeId: selectedMode.id,
                            fileAttachments: fileAttachments,
                            workspaceIds: workspaceIds,
                            disabledConnectorIds: disabledConnectorIds
                        )
                    } else {
                        // For new conversations, use streamMessage
                        stream = try await client.streamMessage(
                            message: message,
                            enableReasoning: enableReasoning,
                            enableDeepSearch: enableDeepSearch,
                            disableSearch: disableSearch,
                            customInstructions: customInstructions,
                            temporary: temporary,
                            personalityType: personality,
                            modeId: selectedMode.id,
                            fileAttachments: fileAttachments,
                            workspaceIds: workspaceIds,
                            disabledConnectorIds: disabledConnectorIds
                        )
                    }
                    
                    // Forward all responses from the stream to our continuation
                    for try await response in stream {
                        if currentConversationId == nil {
                            currentConversationId = response.conversationId
                        }
                        lastResponseId = response.responseId
                        lastWebSearchResults = response.webSearchResults
                        lastXPosts = response.xposts
                        
                        if isDebug {
                            print("Debug: Stream chunk received, length: \(response.message.count) characters")
                            print("Debug: Conversation ID: \(response.conversationId)")
                            print("Debug: Response ID: \(response.responseId)")
                            print("Debug: Web Search Results: \(response.webSearchResults?.count ?? 0)")
                            print("Debug: X Posts: \(response.xposts?.count ?? 0)")
                        }
                        
                        continuation.yield(response)
                    }
                    continuation.finish()
                } catch {
                    if isDebug {
                        print("Debug: Error in msg: \(error.localizedDescription)")
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Loads a conversation by its ID and sets up context for continuing it
    /// - Parameter conversationId: The ID of the conversation to load
    /// - Returns: An array of Response objects containing the conversation history
    /// - Throws: Network, decoding, or API errors
    func loadConversation(conversationId: String) async throws -> [Response] {
        let client = try initializeClient()
        let responses = try await client.loadResponses(conversationId: conversationId)
        
        // Set conversation context
        self.currentConversationId = conversationId
        self.lastResponseId = responses.last?.responseId
        
        if isDebug {
            print("Debug: Loaded conversation \(conversationId) with \(responses.count) responses")
            if let lastId = lastResponseId {
                print("Debug: Last response ID: \(lastId)")
            } else {
                print("Debug: No responses in conversation")
            }
        }
        
        return responses
    }
    
    // Save credentials for future use
    func saveCredentials(from jsonPath: String) throws {
        try configManager.saveCredentialsPath(jsonPath)
        client = nil
    }
    
    // Generate new credentials using cookie extractor
    func generateCredentials(args: [String] = []) async throws -> String {
        // Return path to generated credentials
        let path = try await configManager.runCookieExtractor(extraArgs: args)
        client = nil
        return path
    }
}

// Configuration management
class ConfigManager {
    private let fileManager = FileManager.default
    
    // Get the config directory path
    private var configDirectory: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["GROK_CONFIG_DIR"],
           !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: configuredPath).expandingTildeInPath)
        }

        let homeDirectory = ProcessInfo.processInfo.environment["HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? fileManager.homeDirectoryForCurrentUser
        
        #if os(macOS)
        return homeDirectory.appendingPathComponent(".config/grok-cli")
        #else
        return homeDirectory.appendingPathComponent(".grok-cli")
        #endif
    }
    
    // Path for saved credentials
    private var credentialsPath: URL {
        return configDirectory.appendingPathComponent("credentials.json")
    }
    
    // Create config directory if it doesn't exist
    private func ensureConfigDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: configDirectory.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
    }
    
    // Get path to saved credentials if they exist
    func getSavedCredentialsPath() -> String? {
        return fileManager.fileExists(atPath: credentialsPath.path) ? credentialsPath.path : nil
    }
    
    // Save path to credentials
    func saveCredentialsPath(_ path: String) throws {
        try ensureConfigDirectoryExists()
        
        // Read the credentials file
        let sourceURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: sourceURL)
        let cookies = try JSONDecoder().decode([String: String].self, from: data)
        guard !cookies.isEmpty else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Credentials file did not contain any cookies"
            ])
        }
        
        // Save to the credentials path
        try data.write(to: credentialsPath)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath.path)
    }

    private func findCookieExtractor() -> String? {
        if let explicitPath = ProcessInfo.processInfo.environment["GROK_COOKIE_EXTRACTOR"],
           fileManager.fileExists(atPath: explicitPath) {
            return explicitPath
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        let candidates = [
            currentDir.appendingPathComponent("Scripts/cookie_extractor.py"),
            currentDir.appendingPathComponent("cookie_extractor.py"),
            executableDir.appendingPathComponent("cookie_extractor.py"),
            executableDir.appendingPathComponent("../Scripts/cookie_extractor.py").standardizedFileURL
        ]

        return candidates.first { fileManager.fileExists(atPath: $0.path) }?.path
    }

    private func validateSavedCredentials() throws {
        let data = try Data(contentsOf: credentialsPath)
        let cookies = try JSONDecoder().decode([String: String].self, from: data)
        guard !cookies.isEmpty else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cookie extractor produced an empty credentials file"
            ])
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath.path)
    }
    
    // Run the cookie extractor and return the path to generated credentials
    func runCookieExtractor(extraArgs: [String] = []) async throws -> String {
        try ensureConfigDirectoryExists()
        
        guard let extractorPath = findCookieExtractor() else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find cookie_extractor.py. Run from the swift-grok checkout or reinstall the CLI."
            ])
        }
        
        // Run the cookie extractor
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", extractorPath] + extraArgs + ["--format", "json", "--required", "--output", credentialsPath.path]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GrokCLI", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Cookie extraction failed with exit code \(process.terminationStatus)"
            ])
        }
        
        try validateSavedCredentials()
        
        return credentialsPath.path
    }
}
