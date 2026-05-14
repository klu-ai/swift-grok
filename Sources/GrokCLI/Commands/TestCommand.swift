import ArgumentParser
import Foundation
import GrokClient

struct TestCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Simple test command for debugging"
    )

    @Argument(parsing: .remaining, help: "Optional test message")
    var message: [String] = []

    func run() async throws {
        if message.count == 1, let first = message.first, GrokCLI.isHelpArgument(first) {
            print("Usage: grok test [message...]")
            return
        }

        if GrokCLI.isJSONRequested(message) {
            let words = GrokCLI.removingJSONOutputArgs(message)
            let msgText = words.joined(separator: " ")
            try GrokCLI.printJSONResult(
                command: "test",
                category: "test_result",
                data: AnyCodable([
                    "provided": AnyCodable(!words.isEmpty),
                    "message": AnyCodable(msgText)
                ])
            )
            return
        }

        print("Test command executed successfully!")

        if !message.isEmpty {
            let msgText = message.joined(separator: " ")
            print("Message provided: \"\(msgText)\"")
        } else {
            print("No message provided.")
        }
    }
}
