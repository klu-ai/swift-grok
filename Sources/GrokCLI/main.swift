import ArgumentParser
import Foundation
import GrokClient
import Rainbow

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
    
    @Argument(parsing: .remaining, help: "Optional initial message to send to Grok")
    var initialMessage: [String] = []
    
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output")
    var markdown = false
    
    @Flag(name: .long, help: "Show debug information")
    var debug = false
    
    @Flag(name: .long, help: "Disable custom instructions for the assistant")
    var noCustomInstructions = false
    
    func run() async throws {
        let app = GrokCLIApp.shared
        app.setDebugMode(debug)
        
        let formatter = OutputFormatter(useMarkdown: markdown)
        let inputReader = InputReader()
        
        // Initialization message
        print("Calling Grok API...".cyan)
        
        if debug {
            print("Debug: initialMessage = \(initialMessage)")
        }
        
        // Try to initialize the client to check authentication before starting
        do {
            _ = try app.initializeClient()
            print("Authentication successful".green)
        } catch {
            print("Authentication Error: \(error.localizedDescription)".red)
            print("Please run 'grok auth' to set up your credentials.".yellow)
            return
        }
        
        // If there's an initial message, send it immediately
        if !initialMessage.isEmpty {
            let message = initialMessage.joined(separator: " ")
            print("Sending message: \(message)".cyan)
            print("Thinking...".blue)
            
            do {
                // Send the message to Grok
                let response = try await app.query(
                    message: message,
                    enableReasoning: reasoning,
                    enableDeepSearch: deepSearch,
                    customInstructions: noCustomInstructions ? "" : Self.defaultCustomInstructions
                )
                
                // Format and display the response
                formatter.printResponse(response)
                return
            } catch {
                formatter.printError("Error sending message: \(error.localizedDescription)")
                if debug {
                    print("Debug stack trace: \(error)")
                }
                return
            }
        }
        
        print("Connected to Grok! Type 'exit' to quit, 'help' for commands.".green)
        print("Chat mode".cyan + " | " + (reasoning ? "Reasoning: ON".yellow : "Reasoning: OFF".blue) + " | " + (deepSearch ? "Deep Search: ON".yellow : "Deep Search: OFF".blue))
        print("\nEnter your message:".cyan)
        
        // Main chat loop
        var isRunning = true
        var currentReasoning = reasoning
        var currentDeepSearch = deepSearch
        
        while isRunning {
            // Display prompt
            print("> ".green, terminator: "")
            
            // Get user input
            guard let input = inputReader.readLine() else { break }
            
            // Process commands
            switch input.lowercased() {
            // New slash commands
            case _ where input.hasPrefix("/exit"):
                isRunning = false
                print("Goodbye!".cyan)
                continue
                
            case _ where input.hasPrefix("/reason"):
                currentReasoning = !currentReasoning  // Toggle current state
                print(currentReasoning ? "Reasoning mode enabled".yellow : "Reasoning mode disabled".blue)
                continue
                
            case _ where input.hasPrefix("/search"), _ where input.hasPrefix("/deepsearch"):
                currentDeepSearch = !currentDeepSearch  // Toggle current state
                print(currentDeepSearch ? "Deep search enabled".yellow : "Deep search disabled".blue)
                continue
                
            // Keep existing commands for backward compatibility
            case "exit", "quit":
                isRunning = false
                print("Goodbye!".cyan)
                continue
                
            case "help":
                formatter.printHelp()
                continue
                
            case "reasoning on", "reason on":
                currentReasoning = true
                print("Reasoning mode enabled".yellow)
                continue
                
            case "reasoning off", "reason off":
                currentReasoning = false
                print("Reasoning mode disabled".blue)
                continue
                
            case "search on", "deepsearch on":
                currentDeepSearch = true
                print("Deep search enabled".yellow)
                continue
                
            case "search off", "deepsearch off":
                currentDeepSearch = false
                print("Deep search disabled".blue)
                continue
                
            case "clear", "cls":
                formatter.clearScreen()
                continue
                
            case "":
                continue
                
            default:
                // Process as message to Grok
                break
            }
            
            // Show "thinking" indicator
            print("Thinking...".blue)
            
            do {
                // Send the message to Grok
                let response = try await app.query(
                    message: input,
                    enableReasoning: currentReasoning,
                    enableDeepSearch: currentDeepSearch,
                    customInstructions: noCustomInstructions ? "" : Self.defaultCustomInstructions
                )
                
                // Format and display the response
                formatter.printResponse(response)
            } catch {
                formatter.printError("Error: \(error.localizedDescription)")
                if debug {
                    print("Debug stack trace: \(error)")
                }
            }
        }
    }
}

// QueryCommand: One-off query to Grok
struct QueryCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Send a one-off query to Grok and get the response"
    )
    
    // Default custom instructions for the assistant
    static let defaultCustomInstructions = ChatCommand.defaultCustomInstructions
    
    @Argument(help: "The question or prompt to send to Grok")
    var prompt: [String]
    
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output")
    var markdown = false
    
    @Flag(name: .long, help: "Show debug information")
    var debug = false
    
    @Flag(name: .long, help: "Disable custom instructions for the assistant")
    var noCustomInstructions = false
    
    func run() async throws {
        guard !prompt.isEmpty else {
            print("Error: Please provide a prompt to send to Grok".red)
            return
        }
        
        let message = prompt.joined(separator: " ")
        let app = GrokCLIApp.shared
        app.setDebugMode(debug)
        
        let formatter = OutputFormatter(useMarkdown: markdown)
        
        // Show "thinking" indicator
        print("Thinking...".blue)
        
        do {
            // Send the message to Grok
            let response = try await app.query(
                message: message,
                enableReasoning: reasoning,
                enableDeepSearch: deepSearch,
                customInstructions: noCustomInstructions ? "" : Self.defaultCustomInstructions
            )
            
            // Format and display the response
            formatter.printResponse(response)
        } catch {
            formatter.printError("Error: \(error.localizedDescription)")
            if debug {
                print("Debug stack trace: \(error)")
            }
        }
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
    
    @Argument(parsing: .remaining, help: "The message to send")
    var messageWords: [String]
    
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output")
    var markdown = false
    
    @Flag(name: .long, help: "Show debug information")
    var debug = false
    
    @Flag(name: .long, help: "Disable custom instructions for the assistant")
    var noCustomInstructions = false
    
    func run() async throws {
        let app = GrokCLIApp.shared
        app.setDebugMode(debug)
        let formatter = OutputFormatter(useMarkdown: markdown)
        
        guard !messageWords.isEmpty else {
            print("Error: Please provide a message to send".red)
            return
        }
        
        let message = messageWords.joined(separator: " ")
        
        // Debug output
        if debug {
            print("Debug: Sending message: \"\(message)\"")
        }
        
        // Initialization message
        print("Calling Grok API...".cyan)
        print("Sending: \(message)".cyan)
        print("Thinking...".blue)
        
        do {
            // Try to initialize the client
            _ = try app.initializeClient()
            
            // Send the message
            let response = try await app.query(
                message: message,
                enableReasoning: reasoning,
                enableDeepSearch: deepSearch,
                customInstructions: noCustomInstructions ? "" : Self.defaultCustomInstructions
            )
            
            // Display the response
            formatter.printResponse(response)
        } catch {
            formatter.printError("Error: \(error.localizedDescription)")
            if debug {
                print("Debug stack trace: \(error)")
            }
            formatter.printError("Please run 'grok auth' to set up your credentials.")
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
        
        func run() throws {
            print("Extracting credentials from browser...".cyan)
            
            do {
                let app = GrokCLIApp.shared
                let credentialsPath = try app.generateCredentials()
                print("Successfully generated credentials!".green)
                print("Saved to: \(credentialsPath)".cyan)
            } catch {
                print("Error generating credentials: \(error.localizedDescription)".red)
                print("Please make sure you're logged in to Grok in your browser.".yellow)
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
@main
struct GrokCLI {
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
        
        // Check if first argument is a recognized command
        let recognizedCommands = ["message", "auth", "help", "chat"]
        
        // If not a recognized command, treat all arguments as an initial message for chat
        if !recognizedCommands.contains(command) {
            try await handleChatCommand(args: arguments)
            return
        }
        
        // Process the command
        switch command {
        case "message":
            try await handleMessageCommand(args: remainingArgs)
        case "auth":
            try handleAuthCommand(args: remainingArgs)
        case "help":
            showHelp()
        case "chat":
            try await handleChatCommand(args: remainingArgs)
        default:
            print("Unknown command: \(command)")
            print("Run 'grok help' for usage information.")
        }
    }
    
    // Handle the chat command for interactive sessions
    static func handleChatCommand(args: [String]) async throws {
        // Parse options
        var initialMessage: [String] = []
        var enableReasoning = false
        var enableDeepSearch = false
        var enableMarkdown = false
        var enableDebug = false
        
        // Parse all arguments
        for arg in args {
            if arg == "--reasoning" {
                enableReasoning = true
            } else if arg == "--deep-search" {
                enableDeepSearch = true
            } else if arg == "--markdown" || arg == "-m" {
                enableMarkdown = true
            } else if arg == "--debug" {
                enableDebug = true
            } else {
                initialMessage.append(arg)
            }
        }
        
        let app = GrokCLIApp.shared
        app.setDebugMode(enableDebug)
        
        let formatter = OutputFormatter(useMarkdown: enableMarkdown)
        let inputReader = InputReader()
        
        // Initialization message
        print("Calling Grok API...".cyan)
        
        if enableDebug {
            print("Debug: initialMessage = \(initialMessage)")
        }
        
        // Try to initialize the client to check authentication before starting
        do {
            _ = try app.initializeClient()
            print("Authentication successful".green)
        } catch {
            print("Authentication Error: \(error.localizedDescription)".red)
            print("Please run 'grok auth' to set up your credentials.".yellow)
            return
        }
        
        // If there's an initial message, send it immediately
        if !initialMessage.isEmpty {
            let message = initialMessage.joined(separator: " ")
            print("Sending message: \(message)".cyan)
            print("Thinking...".blue)
            
            do {
                // Send the message to Grok
                let response = try await app.query(
                    message: message,
                    enableReasoning: enableReasoning,
                    enableDeepSearch: enableDeepSearch,
                    customInstructions: ""
                )
                
                // Format and display the response
                formatter.printResponse(response)
            } catch {
                formatter.printError("Error sending message: \(error.localizedDescription)")
                if enableDebug {
                    print("Debug stack trace: \(error)")
                }
                return
            }
        }
        
        print("Connected to Grok! Type 'exit' to quit, 'help' for commands.".green)
        print("Chat mode".cyan + " | " + (enableReasoning ? "Reasoning: ON".yellow : "Reasoning: OFF".blue) + " | " + (enableDeepSearch ? "Deep Search: ON".yellow : "Deep Search: OFF".blue))
        print("\nEnter your message:".cyan)
        
        // Main chat loop
        var isRunning = true
        var currentReasoning = enableReasoning
        var currentDeepSearch = enableDeepSearch
        
        while isRunning {
            // Display prompt
            print("> ".green, terminator: "")
            
            // Get user input
            guard let input = inputReader.readLine() else { break }
            
            // Process commands
            switch input.lowercased() {
            // New slash commands
            case _ where input.hasPrefix("/exit"):
                isRunning = false
                print("Goodbye!".cyan)
                continue
                
            case _ where input.hasPrefix("/reason"):
                currentReasoning = !currentReasoning  // Toggle current state
                print(currentReasoning ? "Reasoning mode enabled".yellow : "Reasoning mode disabled".blue)
                continue
                
            case _ where input.hasPrefix("/search"), _ where input.hasPrefix("/deepsearch"):
                currentDeepSearch = !currentDeepSearch  // Toggle current state
                print(currentDeepSearch ? "Deep search enabled".yellow : "Deep search disabled".blue)
                continue
                
            // Keep existing commands for backward compatibility
            case "exit", "quit":
                isRunning = false
                print("Goodbye!".cyan)
                continue
                
            case "help":
                formatter.printHelp()
                continue
                
            case "reasoning on", "reason on":
                currentReasoning = true
                print("Reasoning mode enabled".yellow)
                continue
                
            case "reasoning off", "reason off":
                currentReasoning = false
                print("Reasoning mode disabled".blue)
                continue
                
            case "search on", "deepsearch on":
                currentDeepSearch = true
                print("Deep search enabled".yellow)
                continue
                
            case "search off", "deepsearch off":
                currentDeepSearch = false
                print("Deep search disabled".blue)
                continue
                
            case "clear", "cls":
                formatter.clearScreen()
                continue
                
            case "":
                continue
                
            default:
                // Process as message to Grok
                break
            }
            
            // Show "thinking" indicator
            print("Thinking...".blue)
            
            do {
                // Send the message to Grok
                let response = try await app.query(
                    message: input,
                    enableReasoning: currentReasoning,
                    enableDeepSearch: currentDeepSearch,
                    customInstructions: ""
                )
                
                // Format and display the response
                formatter.printResponse(response)
            } catch {
                formatter.printError("Error: \(error.localizedDescription)")
                if enableDebug {
                    print("Debug stack trace: \(error)")
                }
            }
        }
    }
    
    // Handle the message command
    static func handleMessageCommand(args: [String]) async throws {
        guard !args.isEmpty else {
            print("Error: Please provide a message to send".red)
            return
        }
        
        // Parse options (very simple for now)
        var message: [String] = []
        var enableReasoning = false
        var enableDeepSearch = false
        var enableMarkdown = false
        var enableDebug = false
        
        for arg in args {
            if arg == "--reasoning" {
                enableReasoning = true
            } else if arg == "--deep-search" {
                enableDeepSearch = true
            } else if arg == "--markdown" || arg == "-m" {
                enableMarkdown = true
            } else if arg == "--debug" {
                enableDebug = true
            } else {
                message.append(arg)
            }
        }
        
        // Join message words
        let messageText = message.joined(separator: " ")
        
        // Execute the command
        print("Initializing Grok CLI...".cyan)
        
        if enableDebug {
            print("Debug: Message = \"\(messageText)\"")
            print("Debug: Reasoning = \(enableReasoning)")
            print("Debug: DeepSearch = \(enableDeepSearch)")
            print("Debug: Markdown = \(enableMarkdown)")
        }
        
        let app = GrokCLIApp.shared
        app.setDebugMode(enableDebug)
        let formatter = OutputFormatter(useMarkdown: enableMarkdown)
        
        print("Sending: \(messageText)".cyan)
        print("Thinking...".blue)
        
        do {
            // Initialize client
            _ = try app.initializeClient()
            
            // Send message
            let response = try await app.query(
                message: messageText,
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                customInstructions: ""
            )
            
            // Display response
            formatter.printResponse(response)
        } catch {
            if enableDebug {
                print("Debug: Error: \(error)")
            }
            print("Error: \(error.localizedDescription)".red)
            print("Please run 'grok auth' to set up your credentials.".yellow)
        }
    }
    
    // Handle the auth command
    static func handleAuthCommand(args: [String]) throws {
        if args.isEmpty {
            print("Auth commands:".cyan)
            print("  generate     - Generate new credentials from browser cookies")
            print("  import <file> - Import credentials from a JSON file")
            return
        }
        
        let subCommand = args[0]
        let app = GrokCLIApp.shared
        
        switch subCommand {
        case "generate":
            print("Extracting credentials from browser...".cyan)
            do {
                let credentialsPath = try app.generateCredentials()
                print("Successfully generated credentials!".green)
                print("Saved to: \(credentialsPath)".cyan)
            } catch {
                print("Error generating credentials: \(error.localizedDescription)".red)
                print("Please make sure you're logged in to Grok in your browser.".yellow)
            }
            
        case "import":
            guard args.count > 1 else {
                print("Error: Please provide a path to the credentials file".red)
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
            }
            
        default:
            print("Unknown auth command: \(subCommand)".red)
            print("Run 'grok auth' for available auth commands.".yellow)
        }
    }
    
    // Show help information
    static func showHelp() {
        print("""
        Grok CLI - Interact with Grok AI from your terminal
        
        Usage: grok [command] [options]
        
        Running just 'grok' with no commands starts an interactive chat session.
        
        Commands:
          message <text>    - Send a message to Grok and exit
          chat [text]       - Start an interactive chat session (optional initial message)
          auth              - Authentication commands
          help              - Show help information
        
        Message/Chat Options:
          --reasoning       - Enable reasoning mode for step-by-step explanations
          --deep-search     - Enable deep search for more comprehensive answers
          -m, --markdown    - Use markdown formatting in output
          --debug           - Show debug information
        
        Examples:
          grok              - Start interactive chat mode
          grok Hello        - Start chat with initial message "Hello"
          grok message Hello, how are you today?
          grok chat What is quantum computing? --reasoning
          grok auth generate
        """)
    }
}

// Utilities

// Output formatting
class OutputFormatter {
    private let useMarkdown: Bool
    
    init(useMarkdown: Bool = false) {
        self.useMarkdown = useMarkdown
    }
    
    func printResponse(_ response: String) {
        print("\n" + "Grok:".green.bold)
        
        if useMarkdown {
            // Simple markdown formatting
            printMarkdown(response)
        } else {
            print(response)
        }
        
        print("")  // Empty line after response
    }
    
    func printError(_ message: String) {
        print(message.red)
    }
    
    func printHelp() {
        print("""
        
        \("Available Commands:".cyan.bold)
        - \("exit".yellow) or \("/exit".yellow): Exit the chat session
        - \("help".yellow): Show this help message
        - \("reasoning on/off".yellow) or \("/reason".yellow): Toggle reasoning mode
        - \("search on/off".yellow) or \("/search".yellow): Toggle deep search
        - \("clear".yellow): Clear the screen
        
        \("Slash Commands:".cyan.bold)
        - \("/exit".yellow): Exit chat mode
        - \("/reason".yellow): Toggle reasoning mode on/off
        - \("/search".yellow) or \("/deepsearch".yellow): Toggle deep search on/off
        
        \("Modes:".cyan.bold)
        - \("Reasoning".yellow): Enables step-by-step explanations
        - \("Deep Search".yellow): Enables more comprehensive answers using web search
        
        """)
    }
    
    func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }
    
    // Simple markdown formatter
    private func printMarkdown(_ text: String) {
        // Split into lines for processing
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        
        // Process line by line
        var inCodeBlock = false
        for line in lines {
            let lineStr = String(line)
            
            // Code blocks
            if lineStr.hasPrefix("```") {
                inCodeBlock = !inCodeBlock
                print(inCodeBlock ? "```".magenta : "```".magenta)
                continue
            }
            
            if inCodeBlock {
                // In code block - print with special formatting
                print(lineStr.blue)
            } else if lineStr.hasPrefix("# ") {
                // H1 header
                print(lineStr.replacingOccurrences(of: "# ", with: "").magenta.bold)
            } else if lineStr.hasPrefix("## ") {
                // H2 header
                print(lineStr.replacingOccurrences(of: "## ", with: "").magenta)
            } else if lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ") {
                // List item
                print(lineStr.replacingOccurrences(of: "- ", with: "• ").replacingOccurrences(of: "* ", with: "• "))
            } else if lineStr.hasPrefix(">") {
                // Block quote
                print(lineStr.green)
            } else {
                // Regular text - look for inline formatting
                var formattedLine = lineStr
                
                // Bold - manually look for patterns
                if formattedLine.contains("**") {
                    let parts = formattedLine.components(separatedBy: "**")
                    if parts.count > 1 {
                        var newLine = ""
                        for (index, part) in parts.enumerated() {
                            if index % 2 == 0 {
                                // Outside bold
                                newLine += part
                            } else {
                                // Inside bold
                                newLine += part.bold
                            }
                        }
                        formattedLine = newLine
                    }
                }
                
                // Italic - manually look for patterns
                if formattedLine.contains("*") {
                    let parts = formattedLine.components(separatedBy: "*")
                    if parts.count > 1 {
                        var newLine = ""
                        for (index, part) in parts.enumerated() {
                            if index % 2 == 0 {
                                // Outside italic
                                newLine += part
                            } else {
                                // Inside italic
                                newLine += part.italic
                            }
                        }
                        formattedLine = newLine
                    }
                }
                
                print(formattedLine)
            }
        }
    }
}

// Input reading
class InputReader {
    private var history: [String] = []
    private var historyIndex = 0
    
    func readLine() -> String? {
        guard let input = Swift.readLine() else {
            return nil
        }
        
        if !input.isEmpty {
            history.append(input)
            historyIndex = history.count
        }
        
        return input
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
    
    private init() {}
    
    // Enable debug mode
    func setDebugMode(_ enabled: Bool) {
        isDebug = enabled
    }
    
    // Load cookies directly from GrokCookies.swift file
    private func getCookiesFromFile() throws -> [String: String] {
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
        do {
            // 1. Try to load cookies directly from the file
            if isDebug {
                print("Debug: Trying to load cookies directly from GrokCookies.swift file...")
            }
            
            let cookies = try getCookiesFromFile()
            client = try GrokClient(cookies: cookies)
            return client!
        } catch {
            if isDebug {
                print("Debug: Could not load cookies from file: \(error.localizedDescription)")
            }
            
            // 2. Try the auto-loaded cookies from GrokCookies.swift if available
            if isDebug {
                print("Debug: Trying to initialize with auto cookies...")
            }
            
            do {
                client = try GrokClient.withAutoCookies()
                return client!
            } catch {
                if isDebug {
                    print("Debug: Auto cookies failed: \(error.localizedDescription)")
                    print("Debug: Trying with saved credentials...")
                }
                
                // 3. Try loading from saved JSON credentials
                if let savedCredentialsPath = configManager.getSavedCredentialsPath() {
                    if isDebug {
                        print("Debug: Found saved credentials at \(savedCredentialsPath)")
                    }
                    client = try GrokClient.fromJSONFile(at: savedCredentialsPath)
                    return client!
                }
                
                if isDebug {
                    print("Debug: No saved credentials found")
                }
                
                // 4. If all else fails, throw authentication error
                throw GrokError.invalidCredentials
            }
        }
    }
    
    // Send a single message and get response
    func query(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, customInstructions: String = "") async throws -> String {
        if isDebug {
            print("Debug: Sending message to Grok:")
            print("Debug: - Message: \(message)")
            print("Debug: - Reasoning: \(enableReasoning)")
            print("Debug: - Deep Search: \(enableDeepSearch)")
            print("Debug: - Custom Instructions: \(customInstructions.isEmpty ? "None" : "Enabled")")
        }
        
        let client = try initializeClient()
        
        if isDebug {
            print("Debug: Client initialized, sending message...")
        }
        
        do {
            let response = try await client.sendMessage(
                message: message,
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                customInstructions: customInstructions
            )
            
            if isDebug {
                print("Debug: Response received, length: \(response.count) characters")
            }
            
            return response
        } catch {
            if isDebug {
                print("Debug: Error sending message: \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    // Save credentials for future use
    func saveCredentials(from jsonPath: String) throws {
        try configManager.saveCredentialsPath(jsonPath)
    }
    
    // Generate new credentials using cookie extractor
    func generateCredentials() throws -> String {
        // Return path to generated credentials
        return try configManager.runCookieExtractor()
    }
}

// Configuration management
class ConfigManager {
    private let fileManager = FileManager.default
    
    // Get the config directory path
    private var configDirectory: URL {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        
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
        
        // Save to the credentials path
        try data.write(to: credentialsPath)
    }
    
    // Run the cookie extractor and return the path to generated credentials
    func runCookieExtractor() throws -> String {
        try ensureConfigDirectoryExists()
        
        // Determine path to cookie_extractor.py
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()
        
        // Possible locations for cookie_extractor.py
        let possiblePaths = [
            executableDir.appendingPathComponent("cookie_extractor.py").path,
            executableDir.appendingPathComponent("../Resources/cookie_extractor.py").path,
            "./cookie_extractor.py"
        ]
        
        var extractorPath: String?
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                extractorPath = path
                break
            }
        }
        
        guard let extractorPath = extractorPath else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find cookie_extractor.py. Make sure it's in the same directory."
            ])
        }
        
        // Output path for the JSON credentials
        let outputPath = configDirectory.appendingPathComponent("extracted_cookies.json").path
        
        // Run the cookie extractor
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", extractorPath, "--format", "json", "--required", "--output", outputPath]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GrokCLI", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Cookie extraction failed with exit code \(process.terminationStatus)"
            ])
        }
        
        // Also copy the credentials to our standard location
        try saveCredentialsPath(outputPath)
        
        return outputPath
    }
} 