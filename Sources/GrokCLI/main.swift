import ArgumentParser
import Foundation
import GrokClient
import Rainbow

// Shared options for Grok commands
struct GrokCommandOptions: ParsableArguments {
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning: Bool = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch: Bool = false
    
    @Flag(name: .long, help: "Disable real-time data (no web or x search)")
    var noSearch: Bool = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output")
    var markdown: Bool = false
    
    @Flag(name: .long, help: "Show debug information")
    var debug: Bool = false
    
    @Flag(name: .long, help: "Disable custom instructions for the assistant")
    var noCustomInstructions: Bool = false
    
    @Flag(name: .customLong("private"), help: "Enable private mode (conversations will not be saved)")
    var privateMode: Bool = false
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
    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool) {
        let personality = GrokCLIApp.shared.getCurrentPersonality()
        let personalityText = personality == .none ? "" : personality.displayName.yellow + " | "
        
        print("Chat mode".cyan + " | " + 
              (currentReasoning ? "Reasoning".green + " | " : "") + 
              (currentDeepSearch ? "DeepSearch".green + " | " : "") + 
              personalityText +
              (currentNoSearch ? "No Search".red : "Realtime".green) + " | " + 
              (currentPrivate ? "Private".red : "Saved".blue))
    }
    
    // Print the current settings status line
    func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool) {
        let personality = GrokCLIApp.shared.getCurrentPersonality()
        let personalityText = personality == .none ? "" : personality.displayName.yellow + " | "
        
        print("Chat mode".cyan + " | " + 
              // hidden for now due to API limitations that will likely be lifted soon
              // (currentNoCustomInstructions ? "Custom instruction: OFF (using defaults)".blue : "Custom instruction: ON".yellow) + " | " + 
              (currentReasoning ? "Reasoning".green + " | " : "") + 
              (currentDeepSearch ? "DeepSearch".green + " | " : "") + 
              personalityText +
              (currentNoSearch ? "No Search".red : "Realtime".green) + " | " + 
              (currentPrivate ? "Private".red : "Saved".blue))
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
    
    // Show personality selection menu
    private static func showPersonalityMenu(app: GrokCLIApp) -> GrokClient.PersonalityType {
        let currentPersonality = app.getCurrentPersonality()
        
        print("\n\("Select a Personality:".cyan.bold)")
        print("Current: \(currentPersonality.displayName.green)\n")
        
        // Display all personality options
        for (index, personality) in GrokClient.PersonalityType.allCases.enumerated() {
            let marker = personality == currentPersonality ? "● " : "  "
            print("\(marker)\(index + 1). \(personality.displayName.yellow): \(personality.description)")
        }
        
        print("\nEnter a number (1-\(GrokClient.PersonalityType.allCases.count)) or press Enter to keep current: ".cyan, terminator: "")
        
        // Get user selection
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), 
           !input.isEmpty,
           let selection = Int(input),
           selection >= 1 && selection <= GrokClient.PersonalityType.allCases.count {
            return GrokClient.PersonalityType.allCases[selection - 1]
        }
        
        // Return current personality if no valid selection
        return currentPersonality
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
        let formatter = OutputFormatter(useMarkdown: options.markdown)
        
        guard !messageWords.isEmpty else {
            print("Error: Please provide a message to send".red)
            return
        }
        
        let message = messageWords.joined(separator: " ")
        
        // Debug output
        if options.debug {
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
                enableReasoning: options.reasoning,
                enableDeepSearch: options.deepSearch,
                disableSearch: options.noSearch,
                customInstructions: options.noCustomInstructions ? Self.defaultCustomInstructions : GrokCLI.getCustomInstructions(),
                temporary: options.privateMode
            )
            
            // Display the response
            formatter.printResponse(
                response,
                conversationId: app.getCurrentConversationId(),
                responseId: app.getLastResponseId(),
                debug: options.debug,
                webSearchResults: app.getLastWebSearchResults(),
                xposts: app.getLastXPosts()
            )
        } catch {
            app.handleError(error, debug: options.debug)
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
            
            do {
                let app = GrokCLIApp.shared
                let credentialsPath = try await app.generateCredentials()
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
    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool) {
        let personality = GrokCLIApp.shared.getCurrentPersonality()
        let personalityText = personality == .none ? "" : personality.displayName.yellow + " | "
        
        print("Chat mode".cyan + " | " + 
              // hidden for now due to API limitations that will likely be lifted soon
              //(currentNoCustomInstructions ? "Custom instruction: OFF (using defaults)".blue : "Custom  instruction: ON".yellow) + " | " + 
              (currentReasoning ? "Reasoning".green + " | " : "") + 
              (currentDeepSearch ? "DeepSearch".green + " | " : "") + 
              personalityText +
              (currentNoSearch ? "No Search".red : "Realtime".green) + " | " + 
              (currentPrivate ? "Private".red : "Saved".blue))
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
        
        // Check if first argument is a recognized command
        let recognizedCommands = ["message", "auth", "help", "list"]
        
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
            try await handleAuthCommand(args: remainingArgs)
        case "list":
            try await handleListCommand(args: remainingArgs)
        case "help":
            showHelp()
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
        var enableNoCustomInstructions = false
        var enableNoSearch = false
        var enablePrivate = false
        
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
            } else if arg == "--no-custom-instructions" {
                enableNoCustomInstructions = true
            } else if arg == "--no-search" {
                enableNoSearch = true
            } else if arg == "--private" {
                enablePrivate = true
            } else {
                initialMessage.append(arg)
            }
        }
        
        let app = GrokCLIApp.shared
        app.setDebugMode(enableDebug)
        
        // Reset conversation ID when starting a new chat session
        app.resetConversation()
        
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
            app.handleError(error, debug: enableDebug)
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
                    disableSearch: enableNoSearch,
                    customInstructions: enableNoCustomInstructions ? ChatCommand.defaultCustomInstructions : GrokCLI.getCustomInstructions(),
                    temporary: enablePrivate
                )
                
                // Format and display the response
                formatter.printResponse(
                    response,
                    conversationId: app.getCurrentConversationId(),
                    responseId: app.getLastResponseId(),
                    debug: enableDebug,
                    webSearchResults: app.getLastWebSearchResults(),
                    xposts: app.getLastXPosts()
                )
            } catch {
                app.handleError(error, debug: enableDebug)
                return
            }
        }
        
        print("Connected to Grok! Type 'quit' to exit, 'new' to start a new thread, 'help' for commands.".green)
        printSettingsStatus(currentReasoning: enableReasoning, currentDeepSearch: enableDeepSearch, currentNoCustomInstructions: enableNoCustomInstructions, currentNoSearch: enableNoSearch, currentPrivate: enablePrivate)
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
                // Reset conversation ID when exiting
                app.resetConversation()
                print("Goodbye!".cyan)
                continue
                
            case _ where input.hasPrefix("/new"):
                app.resetConversation()
                print("Started a new conversation thread.".yellow)
                if let conversationId = app.getCurrentConversationId() {
                    print("Conversation ID: \(conversationId)".cyan)
                }
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                continue
                
            case _ where input.hasPrefix("/quit"):
                isRunning = false
                // Reset conversation ID when exiting
                app.resetConversation()
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
                
            case _ where input.hasPrefix("/realtime"):
                currentNoSearch = !currentNoSearch
                print("Real-time data: \(currentNoSearch ? "DISABLED".red : "ENABLED".green)")
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                continue
                
            case _ where input.hasPrefix("/custom"):
                currentNoCustomInstructions = !currentNoCustomInstructions  // Toggle current state
                print(currentNoCustomInstructions ? "Custom instructions disabled (using defaults)".blue : "Custom instructions enabled".yellow)
                continue
                
            case _ where input.hasPrefix("/private"):
                currentPrivate = !currentPrivate
                print("Private mode: \(currentPrivate ? "ENABLED".green : "DISABLED".red)")
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                continue
            
            case _ where input.hasPrefix("/personality"):
                // Display personality selection menu
                let selectedPersonality = GrokCLI.showPersonalityMenu(app: app)
                
                // Reset conversation when changing personality
                if selectedPersonality != app.getCurrentPersonality() {
                    app.setPersonality(selectedPersonality)
                    app.resetConversation()
                    print("Personality set to: \(selectedPersonality.displayName.green)")
                    print("Started a new conversation with the selected personality.")
                }
                
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                continue
                
            case _ where input.hasPrefix("/help"):
                formatter.printHelp()
                continue
                
            case _ where input.hasPrefix("/list"):
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
                    app.handleError(error, debug: enableDebug)
                    continue
                }
                
            case _ where input.hasPrefix("/reset-conversation"):
                app.resetConversation()
                print("Conversation reset. Starting a new conversation.".yellow)
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                continue
                
            case _ where input.hasPrefix("/edit-instructions"):
                if currentNoCustomInstructions {
                    print("Please enable custom instructions first using '/custom' or 'custom on'".yellow)
                    continue
                }
                GrokCLI.editCustomInstructions()
                continue
                
            case _ where input.hasPrefix("/reset-instructions"):
                GrokCLI.resetCustomInstructions()
                print("Custom instructions reset to defaults".yellow)
                continue
                
            case _ where input.hasPrefix("/special"):
                // Start a new private thread
                app.resetConversation()
                print("Started a new special mode conversation thread.".red.bold)
                print("Special mode activated.".red.bold)
                currentPrivate = true
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                
                print("Thinking...".blue)
                
                do {
                    // Send the hidden mode message to Grok
                    let response = try await app.query(
                        message: ChatCommand.hiddenMode,
                        enableReasoning: false,
                        enableDeepSearch: false,
                        disableSearch: false,
                        customInstructions: "",
                        temporary: true
                    )
                    
                    // Format and display the response
                    formatter.printResponse(
                        response,
                        conversationId: app.getCurrentConversationId(),
                        responseId: app.getLastResponseId(),
                        debug: false,
                        webSearchResults: app.getLastWebSearchResults(),
                        xposts: app.getLastXPosts()
                    )
                } catch {
                    app.handleError(error, debug: enableDebug)
                    continue
                }
                
            
            case "exit", "quit":
                isRunning = false
                // Reset conversation ID when exiting
                app.resetConversation()
                print("Goodbye!".cyan)
                continue
                
            case "help":
                formatter.printHelp()
                continue

            /* 
            fairly certain these are not needed

            case "new conversation", "new-conversation", "reset conversation", "reset-conversation":
                app.resetConversation()
                print("Conversation reset. Starting a new conversation.".yellow)
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                continue
                
            case "new":
                app.resetConversation()
                print("Started a new conversation thread.".yellow)
                if let conversationId = app.getCurrentConversationId() {
                    print("Conversation ID: \(conversationId)".cyan)
                }
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
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

            case "realtime on":
                currentNoSearch = false
                print("Realtime enabled".green)
                continue
                
            case "realtime off":
                currentNoSearch = true
                print("Realtime disabled".red)
                continue
                
            case "custom on":
                currentNoCustomInstructions = false
                print("Custom instructions enabled".yellow)
                continue
                
            case "custom off":
                currentNoCustomInstructions = true
                print("Custom instructions disabled (using defaults)".blue)
                continue
                
            case "private on":
                // If we have an existing conversation, start a new one when switching to private mode
                if currentPrivate == false && app.getCurrentConversationId() != nil {
                    app.resetConversation()
                    print("Started a new private conversation thread.".yellow)
                    currentPrivate = true
                    printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
                }
                currentPrivate = true
                print("Private mode enabled".yellow)
                print("Your conversations will not be saved.".yellow)
                continue
                
            case "private off":
                currentPrivate = false
                print("Private mode disabled".blue)
                continue

            */
                
            case "/clear", "/cls":
                formatter.clearScreen()
                printSettingsStatus(currentReasoning: currentReasoning, currentDeepSearch: currentDeepSearch, currentNoCustomInstructions: currentNoCustomInstructions, currentNoSearch: currentNoSearch, currentPrivate: currentPrivate)
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
                    disableSearch: currentNoSearch,
                    customInstructions: currentNoCustomInstructions ? ChatCommand.defaultCustomInstructions : GrokCLI.getCustomInstructions(),
                    temporary: currentPrivate
                )
                
                // Format and display the response
                formatter.printResponse(
                    response,
                    conversationId: app.getCurrentConversationId(),
                    responseId: app.getLastResponseId(),
                    debug: currentNoCustomInstructions ? false : enableDebug,
                    webSearchResults: app.getLastWebSearchResults(),
                    xposts: app.getLastXPosts()
                )
            } catch {
                app.handleError(error, debug: enableDebug)
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
        var enableNoSearch = false
        var enablePrivate = false
        
        for arg in args {
            if arg == "--reasoning" {
                enableReasoning = true
            } else if arg == "--deep-search" {
                enableDeepSearch = true
            } else if arg == "--markdown" || arg == "-m" {
                enableMarkdown = true
            } else if arg == "--debug" {
                enableDebug = true
            } else if arg == "--no-search" {
                enableNoSearch = true
            } else if arg == "--private" {
                enablePrivate = true
            } else {
                message.append(arg)
            }
        }
        
        // Join message words
        let messageText = message.joined(separator: " ")
        
        // Execute the command
        print("Calling Grok API...".cyan)
        
        if enableDebug {
            print("Debug: Message = \"\(messageText)\"")
            print("Debug: Reasoning = \(enableReasoning)")
            print("Debug: DeepSearch = \(enableDeepSearch)")
            print("Debug: Realtime disabled = \(enableNoSearch)")
            print("Debug: Markdown = \(enableMarkdown)")
        }
        
        let app = GrokCLIApp.shared
        app.setDebugMode(enableDebug)
        
        // For single message commands, always reset the conversation
        app.resetConversation()
        
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
                disableSearch: enableNoSearch,
                customInstructions: ChatCommand.defaultCustomInstructions,
                temporary: enablePrivate
            )
            
            // Display response
            formatter.printResponse(
                response,
                conversationId: app.getCurrentConversationId(),
                responseId: app.getLastResponseId(),
                debug: enableDebug,
                webSearchResults: app.getLastWebSearchResults(),
                xposts: app.getLastXPosts()
            )
        } catch {
            app.handleError(error, debug: enableDebug)
        }
    }
    
    // Handle the auth command
    static func handleAuthCommand(args: [String]) async throws {
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
                let credentialsPath = try await app.generateCredentials()
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
        
         ██████╗ ██████╗  ██████╗ ██╗  ██╗
        ██╔════╝ ██╔══██╗██╔═══██╗██║ ██╔╝
        ██║  ███╗██████╔╝██║   ██║█████╔╝ 
        ██║   ██║██╔══██╗██║   ██║██╔═██╗ 
        ╚██████╔╝██║  ██║╚██████╔╝██║  ██╗
         ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝
        
        Grok3 up in your terminal
        
        Usage: grok [command] [options]
        
        Running just 'grok' with no commands starts an interactive chat session.
        
        Commands:
          message <text>    - Send a message to Grok and exit
          auth              - Authentication commands
          list              - List and manage saved conversations
          help              - Show help information
        
        App Options:
          --reasoning       - Enable reasoning mode for step-by-step explanations
          --deep-search     - Enable deep search for more comprehensive answers
          --no-search       - Disable real-time data (no web or x search)
          --markdown        - Use markdown formatting in output
          --debug           - Show debug information
          --private         - Enable private mode (conversations will not be saved)
        
        Chat Commands:
          /new              - Start a new conversation
          /list             - List and load past conversations
          /reason           - Toggle reasoning mode
          /search           - Toggle deep search mode
          /realtime         - Toggle real-time data on/off
          /private          - Toggle private mode (conversations not saved)
          /clear            - Clear the current screen 
          /quit             - Exit the app
        
        Notes:
          - In chat mode, conversation context is maintained between messages
          - Use '/new' to start a new conversation thread
          - Use 'exit', '/exit', 'quit', '/quit' to exit the app
          - The message command always starts a new conversation without context
        
        Examples:
          grok                                      - Start interactive chat mode
          grok Hello                                - Start chat with initial message "Hello"
          grok message Hello, how are you today?    - Send a message and exit
          grok auth generate                        - Generate new credentials from browser cookies
          grok list                                 - List and select from saved conversations
        """.green.bold)
    }

    // Handle the list command
    static func handleListCommand(args: [String]) async throws {
        let app = GrokCLIApp.shared
        // let formatter = OutputFormatter(useMarkdown: false)
        
        // Parse options
        var enableDebug = false
        
        for arg in args {
            if arg == "--debug" {
                enableDebug = true
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
            
            if enableDebug {
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
                
                if enableDebug {
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
            app.handleError(error, debug: enableDebug)
        }
    }
    
    // Show personality selection menu
    static func showPersonalityMenu(app: GrokCLIApp) -> GrokClient.PersonalityType {
        let currentPersonality = app.getCurrentPersonality()
        
        print("\n\("Select a Personality:".cyan.bold)")
        print("Current: \(currentPersonality.displayName.green)\n")
        
        // Display all personality options
        for (index, personality) in GrokClient.PersonalityType.allCases.enumerated() {
            let marker = personality == currentPersonality ? "● " : "  "
            print("\(marker)\(index + 1). \(personality.displayName.yellow): \(personality.description)")
        }
        
        print("\nEnter a number (1-\(GrokClient.PersonalityType.allCases.count)) or press Enter to keep current: ".cyan, terminator: "")
        
        // Get user selection
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), 
           !input.isEmpty,
           let selection = Int(input),
           selection >= 1 && selection <= GrokClient.PersonalityType.allCases.count {
            return GrokClient.PersonalityType.allCases[selection - 1]
        }
        
        // Return current personality if no valid selection
        return currentPersonality
    }
}

// removed from app options for now
// --no-custom-instructions - Disable custom instructions

//  removed from slash commands
// /reset-conversation - Clear the current conversation context
//  /custom           - Toggle custom instructions

// Utilities

// Output formatting
class OutputFormatter {
    private let useMarkdown: Bool
    
    init(useMarkdown: Bool = false) {
        self.useMarkdown = useMarkdown
    }
    
    func printResponse(_ response: String, conversationId: String? = nil, responseId: String? = nil, debug: Bool = false, webSearchResults: [WebSearchResult]? = nil, xposts: [XPost]? = nil) {
        print("\n" + "Grok:".green.bold)
        
        if useMarkdown {
            // Simple markdown formatting
            printMarkdown(response)
        } else {
            print(response)
        }
        
        // Show sources information if available
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
        
        // Print conversation and response IDs if in debug mode
        if debug, let conversationId = conversationId, let responseId = responseId {
            print("\n" + "Debug Info:".cyan)
            print("Conversation ID: \(conversationId)".cyan)
            print("Response ID: \(responseId)".cyan)
        }
        
        print("")  // Empty line after response
    }
    
    func printError(_ message: String) {
        print(message.red)
    }
    
    func printHelp() {
        print("""
        
        \("Basic Commands:".cyan.bold)
        - \("new".yellow): Start a new conversation thread
        - \("help".yellow): Show this help message
        - \("quit".yellow): Exit the app
        
        \("Slash Commands:".cyan.bold)
        - \("/new".yellow): Start a new conversation thread
        - \("/list".yellow): List and load past conversations
        - \("/reason".yellow): Toggle reasoning mode on/off
        - \("/search".yellow): Toggle deep search on/off
        - \("/realtime".yellow): Toggle real-time data on/off
        - \("/private".yellow): Toggle private mode on/off 
        - \("/personality".yellow): Choose Grok personality
        - \("/clear".yellow): Clear the screen
        - \("/quit".yellow): Exit the app
        
        \("Modes:".cyan.bold)
        - \("Reasoning".yellow): Enables Grok reasoning model for hard problems
        - \("DeepSearch".yellow): Conduct in-depth analysis with research agent
        - \("Realtime".yellow): Enables real-time data from web and X search
        - \("Private Mode".yellow): When enabled, conversations will not be saved
        - \("Personality".yellow): Interact with different Grok personalities
        
        """)
    }

    // temporarily hidden from slash commands 
    
    // - \("/custom".yellow): Toggle custom instructions
    // - \("/edit-instructions".yellow): Edit custom instructions
    // - \("/reset-instructions".yellow): Reset custom instructions to defaults

    // temporarily hidden from modes

    //- \("Conversation Threading".yellow): Messages maintain context within the current conversation
    // - \("Custom Instructions".yellow): Enables/disables custom instructions for the assistant
    
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
    internal var history: [String] = []
    internal var historyIndex = 0
    
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
    private var currentConversationId: String?
    private var lastResponseId: String?
    private var lastWebSearchResults: [WebSearchResult]?
    private var lastXPosts: [XPost]?
    private var currentPersonality: GrokClient.PersonalityType = .none
    
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
    
    // Centralized error handling method
    func handleError(_ error: Error, debug: Bool) {
        print("Error: \(error.localizedDescription)".red)
        if debug {
            print("Debug: Error details: \(error)".cyan)
            print("Debug: Error type: \(type(of: error))".cyan)
        }
        if case .invalidCredentials = error as? GrokError {
            print("Please run 'grok auth' to set up your credentials.".yellow)
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
        do {
            // 1. Try to load cookies directly from the file
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
            
            // 2. Try the auto-loaded cookies from GrokCookies.swift if available
            if isDebug {
                print("Debug: Trying to initialize with auto cookies...")
            }
            
            do {
                client = try GrokClient.withAutoCookies(isDebug: isDebug)
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
                    client = try GrokClient.fromJSONFile(at: savedCredentialsPath, isDebug: isDebug)
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
    func query(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, disableSearch: Bool = false, customInstructions: String = "", temporary: Bool = false, personalityType: GrokClient.PersonalityType? = nil) async throws -> String {
        let personality = personalityType ?? currentPersonality
        
        if isDebug {
            print("Debug: Sending message to Grok:")
            print("Debug: - Message: \(message)")
            print("Debug: - Reasoning: \(enableReasoning)")
            print("Debug: - Deep Search: \(enableDeepSearch)")
            print("Debug: - Disable Search: \(disableSearch)")
            print("Debug: - Custom Instructions: \(customInstructions.isEmpty ? "None" : "Enabled")")
            print("Debug: - Private Mode: \(temporary ? "ON" : "OFF")")
            print("Debug: - Personality: \(personality.displayName)")
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
            print("Debug: Client initialized, sending message...")
        }
        
        do {
            if let conversationId = currentConversationId {
                // Continue existing conversation
                let (responseMessage, newResponseId, webSearchResults, xposts) = try await client.continueConversation(
                    conversationId: conversationId,
                    parentResponseId: lastResponseId,
                    message: message,
                    enableReasoning: enableReasoning,
                    enableDeepSearch: enableDeepSearch,
                    disableSearch: disableSearch,
                    customInstructions: customInstructions,
                    temporary: temporary,
                    personalityType: personality
                )
                
                // Save the latest response ID and additional data
                self.lastResponseId = newResponseId
                self.lastWebSearchResults = webSearchResults
                self.lastXPosts = xposts
                
                if isDebug {
                    print("Debug: Response received for conversation \(conversationId), length: \(responseMessage.count) characters")
                    print("Debug: New Response ID: \(newResponseId)")
                    print("Debug: Web Search Results: \(webSearchResults?.count ?? 0)")
                    print("Debug: X Posts: \(xposts?.count ?? 0)")
                }
                
                return responseMessage
            } else {
                // Start new conversation
                let conversationResponse = try await client.sendMessage(
                    message: message,
                    enableReasoning: enableReasoning,
                    enableDeepSearch: enableDeepSearch,
                    disableSearch: disableSearch,
                    customInstructions: customInstructions,
                    temporary: temporary,
                    personalityType: personality
                )
                
                // Save conversation ID, response ID, and additional data
                self.currentConversationId = conversationResponse.conversationId
                self.lastResponseId = conversationResponse.responseId
                self.lastWebSearchResults = conversationResponse.webSearchResults
                self.lastXPosts = conversationResponse.xposts
                
                if isDebug {
                    print("Debug: Response received, length: \(conversationResponse.message.count) characters")
                    print("Debug: Conversation ID: \(conversationResponse.conversationId)")
                    print("Debug: Response ID: \(conversationResponse.responseId)")
                    print("Debug: Web Search Results: \(conversationResponse.webSearchResults?.count ?? 0)")
                    print("Debug: X Posts: \(conversationResponse.xposts?.count ?? 0)")
                }
                
                return conversationResponse.message
            }
        } catch {
            if isDebug {
                print("Debug: Error sending message: \(error.localizedDescription)")
            }
            throw error
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
    }
    
    // Generate new credentials using cookie extractor
    func generateCredentials() async throws -> String {
        // Return path to generated credentials
        return try await configManager.runCookieExtractor()
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
    func runCookieExtractor() async throws -> String {
        try ensureConfigDirectoryExists()
        
        // Determine path to cookie_extractor.py
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()
        
        // Default location for cookie_extractor.py
        let extractorPath = executableDir.appendingPathComponent("cookie_extractor.py").path
        
        // If the extractor doesn't exist, download it
        if !fileManager.fileExists(atPath: extractorPath) {
            print("Downloading cookie extractor script...".cyan)
            
            // URL for the cookie extractor script
            guard let url = URL(string: "https://raw.githubusercontent.com/klu-ai/swift-grok/refs/heads/main/Scripts/cookie_extractor.py") else {
                throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid URL for cookie extractor script"
                ])
            }
            
            // Download the script
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to download cookie extractor script"
                ])
            }
            
            // Save the script
            try data.write(to: URL(fileURLWithPath: extractorPath))
            print("Cookie extractor script downloaded successfully".green)
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