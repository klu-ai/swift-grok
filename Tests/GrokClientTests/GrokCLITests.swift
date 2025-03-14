import XCTest
@testable import GrokCLI

final class GrokCLITests: XCTestCase {
    // MARK: - Command Parsing Tests
    
    func testChatCommandParsing() throws {
        let args = ["chat", "--reasoning", "--deep-search", "Hello, Grok!"]
        let command = try ChatCommand.parse(args)
        
        XCTAssertTrue(command.reasoning)
        XCTAssertTrue(command.deepSearch)
        XCTAssertFalse(command.markdown)
        XCTAssertFalse(command.debug)
        XCTAssertFalse(command.noCustomInstructions)
        XCTAssertEqual(command.initialMessage.joined(separator: " "), "Hello, Grok!")
    }
    
    func testChatCommandWithMarkdown() throws {
        let args = ["chat", "-m", "--debug", "Test message"]
        let command = try ChatCommand.parse(args)
        
        XCTAssertTrue(command.markdown)
        XCTAssertTrue(command.debug)
        XCTAssertEqual(command.initialMessage.joined(separator: " "), "Test message")
    }
    
    func testCustomInstructionsManagement() {
        // Test default instructions
        XCTAssertFalse(ChatCommand.defaultCustomInstructions.isEmpty)
        
        // Test saving and retrieving custom instructions
        let testInstructions = "Test custom instructions"
        UserDefaults.standard.set(testInstructions, forKey: "com.grok.cli.customInstructions")
        XCTAssertEqual(ChatCommand.getCustomInstructions(), testInstructions)
        
        // Test resetting instructions
        ChatCommand.resetCustomInstructions()
        XCTAssertEqual(ChatCommand.getCustomInstructions(), ChatCommand.defaultCustomInstructions)
    }
    
    // MARK: - Output Formatting Tests
    
    func testOutputFormatterPlainText() {
        let formatter = OutputFormatter(useMarkdown: false)
        let response = "This is a test response"
        formatter.printResponse(response)
    }
    
    func testOutputFormatterMarkdown() {
        let formatter = OutputFormatter(useMarkdown: true)
        let markdown = """
        # Header
        **Bold text**
        ```swift
        let x = 1
        ```
        - List item 1
        - List item 2
        > Quote
        """
        formatter.printResponse(markdown)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorFormatting() {
        let formatter = OutputFormatter(useMarkdown: false)
        let error = "Test error message"
        formatter.printError(error)
    }
    
    // MARK: - Input Reader Tests
    
    func testInputReaderHistory() {
        let reader = InputReader()
        
        // Test adding to history
        let inputs = ["first", "second", "third"]
        for input in inputs {
            _ = reader.readLine(input: input)
        }
        
        // Test history navigation
        XCTAssertEqual(reader.getPreviousCommand(), "third")
        XCTAssertEqual(reader.getPreviousCommand(), "second")
        XCTAssertEqual(reader.getNextCommand(), "third")
    }
    
    // MARK: - Command Line Argument Tests
    
    func testCommandLineArgumentParsing() {
        let args = ["grok", "chat", "--reasoning", "Hello"]
        let command = args[0].lowercased()
        let remainingArgs = Array(args.dropFirst())
        
        XCTAssertEqual(command, "grok")
        XCTAssertEqual(remainingArgs, ["chat", "--reasoning", "Hello"])
    }
    
    func testRecognizedCommands() {
        let recognizedCommands = ["message", "auth", "help", "chat"]
        let validCommand = "chat"
        let invalidCommand = "invalid"
        
        XCTAssertTrue(recognizedCommands.contains(validCommand))
        XCTAssertFalse(recognizedCommands.contains(invalidCommand))
    }
}

// Helper extension for testing InputReader
extension InputReader {
    func readLine(input: String) -> String? {
        history.append(input)
        historyIndex = history.count
        return input
    }
} 