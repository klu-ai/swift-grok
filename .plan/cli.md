# GrokCLI Implementation Plan

## Overview

The GrokCLI is a command-line interface tool that leverages the GrokClient Swift library to enable users to interact with Grok AI from their terminal. This document outlines the design, architecture, and implementation details for creating an effective CLI tool.

## Design Approaches

I've considered five distinct approaches for implementing the GrokCLI:

### Approach 1: Swift Package-based CLI Tool
- **Description**: A standalone Swift executable that's part of the existing Swift package
- **Implementation**: Uses ArgumentParser to handle CLI arguments and options
- **Pros**: Consistent with existing Swift codebase, native performance, easier dependency management
- **Cons**: Requires Swift runtime, more complex to distribute to non-developers

### Approach 2: Python Script Wrapper
- **Description**: A Python script that wraps the Swift library using subprocess calls to a compiled binary
- **Implementation**: Uses the Python `argparse` library for command-line arguments, calls a small Swift helper
- **Pros**: Leverages existing Python infrastructure from cookie extractor, easier cross-platform distribution
- **Cons**: Introduces another language dependency, performance overhead from subprocess calls

### Approach 3: Shell Script with Compiled Binary
- **Description**: A shell script wrapper around a pre-compiled Swift binary
- **Implementation**: Shell script handles arguments and environment setup, calls the binary
- **Pros**: Familiar Unix-style interface, good for scripting integration
- **Cons**: Limited cross-platform compatibility, harder to maintain complex logic

### Approach 4: Standalone Executable with Embedded Authentication
- **Description**: A single-file binary with built-in authentication logic
- **Implementation**: Fully self-contained executable with cookie extraction functionality built in
- **Pros**: Simpler user experience, no need for separate cookie extraction
- **Cons**: Security concerns with embedded credentials, larger binary size

### Approach 5: Web-based CLI with Terminal UI
- **Description**: A terminal UI application using a library like SwiftTUI
- **Implementation**: Rich terminal interface with input handling and formatted output
- **Pros**: Enhanced user experience with features like history scrolling, markdown rendering
- **Cons**: More complex to implement, potential compatibility issues with different terminals

## Approach Ranking

1. **Approach 1: Swift Package-based CLI Tool** (Recommended)
   - Best fits the existing architecture
   - Maintains language consistency
   - Leverages Swift's performance and type safety
   - Easiest to maintain alongside the main client library

2. **Approach 5: Web-based CLI with Terminal UI**
   - Provides the best user experience
   - More complex implementation but with significant benefits
   - Good fit for AI interactions that may include rich text

3. **Approach 2: Python Script Wrapper**
   - Builds on existing Python infrastructure
   - Good for cross-platform scenarios
   - Easier for some users to modify and extend

4. **Approach 3: Shell Script with Compiled Binary**
   - Simple implementation
   - Good Unix philosophy
   - Limited in functionality

5. **Approach 4: Standalone Executable with Embedded Authentication**
   - Simplest user experience but with security tradeoffs
   - Hardest to maintain and update

## Selected Approach: Swift Package-based CLI Tool

After careful consideration, the Swift Package-based CLI Tool (Approach 1) provides the best balance of consistency, performance, and maintainability. It keeps the entire project in Swift, leverages the existing package structure, and provides a native experience.

## Detailed Implementation Plan

### 1. Files and Locations

#### New Files:
- `Sources/GrokCLI/main.swift` - Main entry point for the CLI
- `Sources/GrokCLI/GrokCLIApp.swift` - Core application logic
- `Sources/GrokCLI/Commands/` - Directory for command implementations
  - `Sources/GrokCLI/Commands/ChatCommand.swift` - Interactive chat command
  - `Sources/GrokCLI/Commands/QueryCommand.swift` - Single query command
  - `Sources/GrokCLI/Commands/AuthCommand.swift` - Authentication management
- `Sources/GrokCLI/Utilities/` - Directory for helper utilities
  - `Sources/GrokCLI/Utilities/OutputFormatter.swift` - Terminal output formatting
  - `Sources/GrokCLI/Utilities/InputReader.swift` - Input handling
  - `Sources/GrokCLI/Utilities/ConfigManager.swift` - Configuration management

#### Modified Files:
- `Package.swift` - Update to include the new GrokCLI product and its dependencies

### 2. Code Modifications

#### Package.swift Updates:
```swift
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "GrokClient",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "GrokClient",
            targets: ["GrokClient"]),
        .executable(
            name: "GrokCLI",
            targets: ["GrokCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "GrokClient",
            dependencies: []),
        .executableTarget(
            name: "GrokCLI",
            dependencies: [
                "GrokClient",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Rainbow"
            ]),
        .testTarget(
            name: "GrokClientTests",
            dependencies: ["GrokClient"]),
    ],
    swiftLanguageVersions: [.v5]
)
```

#### Main Entry Point (Sources/GrokCLI/main.swift):
```swift
import ArgumentParser
import Foundation
import GrokClient
import Rainbow

@main
struct GrokCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "grok",
        abstract: "Interact with Grok AI from your terminal",
        version: "1.0.0",
        subcommands: [
            ChatCommand.self,
            QueryCommand.self,
            AuthCommand.self
        ],
        defaultSubcommand: ChatCommand.self
    )
}

// Run the CLI
GrokCLI.main()
```

#### Application Logic (Sources/GrokCLI/GrokCLIApp.swift):
```swift
import Foundation
import GrokClient

class GrokCLIApp {
    static let shared = GrokCLIApp()
    
    private var client: GrokClient?
    private let configManager = ConfigManager()
    
    private init() {}
    
    // Initialize the Grok client using available authentication methods
    func initializeClient() throws -> GrokClient {
        if let existingClient = client {
            return existingClient
        }
        
        // Try different authentication methods in order of preference
        do {
            // 1. Try the auto-loaded cookies from GrokCookies.swift if available
            return try GrokClient.withAutoCookies()
        } catch {
            // 2. Try loading from saved JSON credentials
            if let savedCredentialsPath = configManager.getSavedCredentialsPath() {
                return try GrokClient.fromJSONFile(at: savedCredentialsPath)
            }
            
            // 3. If all else fails, throw authentication error
            throw GrokError.invalidCredentials
        }
    }
    
    // Send a single message and get response
    func query(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false) async throws -> String {
        let client = try initializeClient()
        return try await client.sendMessage(
            message: message,
            enableReasoning: enableReasoning,
            enableDeepSearch: enableDeepSearch
        )
    }
    
    // Save credentials for future use
    func saveCredentials(from jsonPath: String) throws {
        try configManager.saveCredentialsPath(jsonPath)
    }
    
    // Generate new credentials using cookie extractor
    func generateCredentials() throws -> String {
        // Implementation depends on integrating with cookie_extractor.py
        // Return path to generated credentials
        return try configManager.runCookieExtractor()
    }
}
```

#### Chat Command Implementation (Sources/GrokCLI/Commands/ChatCommand.swift):
```swift
import ArgumentParser
import Foundation
import Rainbow

struct ChatCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive chat session with Grok"
    )
    
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output")
    var markdown = false
    
    mutating func run() throws {
        let app = GrokCLIApp.shared
        let formatter = OutputFormatter(useMarkdown: markdown)
        let inputReader = InputReader()
        
        // Initialization message
        print("Initializing Grok CLI...".cyan)
        
        do {
            // Try to initialize the client to check authentication before starting
            _ = try app.initializeClient()
            
            print("Connected to Grok! Type 'exit' to quit, 'help' for commands.".green)
            print("Chat mode".cyan + " | " + (reasoning ? "Reasoning: ON".yellow : "Reasoning: OFF".blue) + " | " + (deepSearch ? "Deep Search: ON".yellow : "Deep Search: OFF".blue))
            print("\nEnter your message:".cyan)
            
            // Main chat loop
            var isRunning = true
            while isRunning {
                // Display prompt
                print("> ".green, terminator: "")
                
                // Get user input
                guard let input = inputReader.readLine() else { break }
                
                // Process commands
                switch input.lowercased() {
                case "exit", "quit":
                    isRunning = false
                    print("Goodbye!".cyan)
                    continue
                    
                case "help":
                    formatter.printHelp()
                    continue
                    
                case "reasoning on", "reason on":
                    reasoning = true
                    print("Reasoning mode enabled".yellow)
                    continue
                    
                case "reasoning off", "reason off":
                    reasoning = false
                    print("Reasoning mode disabled".blue)
                    continue
                    
                case "search on", "deepsearch on":
                    deepSearch = true
                    print("Deep search enabled".yellow)
                    continue
                    
                case "search off", "deepsearch off":
                    deepSearch = false
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
                        enableReasoning: reasoning,
                        enableDeepSearch: deepSearch
                    )
                    
                    // Format and display the response
                    formatter.printResponse(response)
                } catch {
                    formatter.printError("Error: \(error.localizedDescription)")
                }
            }
        } catch {
            formatter.printError("Authentication Error: \(error.localizedDescription)")
            formatter.printError("Please run 'grok auth' to set up your credentials.")
        }
    }
}
```

#### Query Command Implementation (Sources/GrokCLI/Commands/QueryCommand.swift):
```swift
import ArgumentParser
import Foundation
import Rainbow

struct QueryCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Send a one-off query to Grok and get the response"
    )
    
    @Argument(help: "The question or prompt to send to Grok")
    var prompt: [String]
    
    @Flag(name: .long, help: "Enable reasoning mode for step-by-step explanations")
    var reasoning = false
    
    @Flag(name: .long, help: "Enable deep search for more comprehensive answers")
    var deepSearch = false
    
    @Flag(name: .shortAndLong, help: "Use markdown formatting in output")
    var markdown = false
    
    mutating func run() throws {
        guard !prompt.isEmpty else {
            print("Error: Please provide a prompt to send to Grok".red)
            return
        }
        
        let message = prompt.joined(separator: " ")
        let app = GrokCLIApp.shared
        let formatter = OutputFormatter(useMarkdown: markdown)
        
        // Show "thinking" indicator
        print("Thinking...".blue)
        
        do {
            // Send the message to Grok
            let response = try await app.query(
                message: message,
                enableReasoning: reasoning,
                enableDeepSearch: deepSearch
            )
            
            // Format and display the response
            formatter.printResponse(response)
        } catch {
            formatter.printError("Error: \(error.localizedDescription)")
            formatter.printError("Please run 'grok auth' to set up your credentials.")
        }
    }
}
```

#### Auth Command Implementation (Sources/GrokCLI/Commands/AuthCommand.swift):
```swift
import ArgumentParser
import Foundation
import Rainbow

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
        
        mutating func run() throws {
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
        
        mutating func run() throws {
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
```

#### Output Formatter (Sources/GrokCLI/Utilities/OutputFormatter.swift):
```swift
import Foundation
import Rainbow

class OutputFormatter {
    private let useMarkdown: Bool
    
    init(useMarkdown: Bool = false) {
        self.useMarkdown = useMarkdown
    }
    
    func printResponse(_ response: String) {
        print("\n" + "Grok:".green.bold)
        
        if useMarkdown {
            // Simple markdown formatting - a more robust implementation would use a markdown parser
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
        - \("exit".yellow): Exit the chat session
        - \("help".yellow): Show this help message
        - \("reasoning on/off".yellow): Toggle reasoning mode
        - \("search on/off".yellow): Toggle deep search
        - \("clear".yellow): Clear the screen
        
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
                // Blockquote
                print(lineStr.green)
            } else {
                // Regular text - look for inline formatting
                var formattedLine = lineStr
                
                // Bold
                formattedLine = formattedLine.replacingOccurrences(
                    of: #"\*\*(.+?)\*\*"#,
                    with: { match -> String in
                        let content = String(match.dropFirst(2).dropLast(2))
                        return content.bold
                    },
                    options: .regularExpression
                )
                
                // Italic
                formattedLine = formattedLine.replacingOccurrences(
                    of: #"\*(.+?)\*"#,
                    with: { match -> String in
                        let content = String(match.dropFirst().dropLast())
                        return content.italic
                    },
                    options: .regularExpression
                )
                
                print(formattedLine)
            }
        }
    }
}
```

#### Input Reader (Sources/GrokCLI/Utilities/InputReader.swift):
```swift
import Foundation

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
```

#### Config Manager (Sources/GrokCLI/Utilities/ConfigManager.swift):
```swift
import Foundation

class ConfigManager {
    private let fileManager = FileManager.default
    
    // Get the config directory path
    private var configDirectory: URL {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        
        #if os(macOS)
        return homeDirectory.appendingPathComponent(".config/grokcli")
        #else
        return homeDirectory.appendingPathComponent(".grokcli")
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
```

### 3. Data Structures and Interfaces

The implementation primarily uses existing data structures from the GrokClient library. New structures and interfaces include:

- **Command Hierarchy**: Using ArgumentParser's ParsableCommand protocol for defining commands
- **Configuration Storage**: Simple JSON-based storage for credentials and preferences
- **Input/Output Handling**: Custom utilities for terminal input and formatted output

### 4. Configuration Updates

Configuration is managed through the `ConfigManager` class, which:

1. Creates a `.config/grokcli` directory in the user's home folder
2. Stores credentials in `credentials.json`
3. Manages paths to required resources like the cookie extractor script

### 5. Architectural Considerations

#### Key Design Decisions:

1. **Command Structure**: Using a subcommand-based approach (chat, query, auth) provides a clean, extensible interface that follows Unix CLI conventions.

2. **Authentication Flow**: The CLI tries multiple authentication methods in sequence, starting with the most convenient (auto-loaded cookies) and falling back to more manual methods.

3. **Interactive vs. Single-Query Modes**: Supporting both interactive sessions and one-off queries makes the CLI useful for both human interaction and scripting.

4. **Output Formatting**: Optional markdown rendering enhances readability of Grok's responses, which often include formatted code, lists, and other rich text elements.

5. **Stateless Operation**: Each command execution is independent, maintaining Unix philosophy while allowing for credential persistence between runs.

#### Trade-offs and Considerations:

1. **Dependency on External Cookie Extraction**: The CLI still requires the Python-based cookie extractor, which introduces a cross-language dependency. A future enhancement could be to reimplement the cookie extraction in Swift.

2. **Terminal UI Limitations**: The implementation uses basic terminal capabilities for simplicity. A more advanced version might use a library like SwiftTUI for richer interaction.

3. **Asynchronous Support**: The implementation uses Swift's modern async/await pattern, which requires Swift 5.5+ and may limit compatibility with older systems.

4. **Distribution Complexity**: As a Swift executable, distribution requires compilation for each target platform. Future work could include packaging as a Homebrew formula or other package formats.

## Next Steps for Implementation

1. Create the directory structure and files as outlined
2. Implement the core functionality following the provided code samples
3. Test with different authentication scenarios
4. Add installation and usage documentation to the README

This implementation provides a solid foundation for a GrokCLI that balances ease of use with powerful features, while maintaining consistency with the existing Swift codebase. 