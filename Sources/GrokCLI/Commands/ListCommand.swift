import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleListCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let jsonRequested = isJSONRequested(args)

        var remainingArgs = args
        let enableJSON: Bool
        do {
            enableJSON = try CLIOptionParsing.removeJSONOutputOptions(from: &remainingArgs)
        } catch {
            if jsonRequested {
                printJSONError(command: "list", error: error, exitCode: 2)
            } else {
                await app.handleError(error, debug: args.contains("--debug"))
            }
            if exitOnError {
                exit(with: 2)
            }
            return
        }

        // Parse options
        var enableDebug = false
        var conversationId: String?

        var index = 0
        while index < remainingArgs.count {
            let arg = remainingArgs[index]
            if isHelpArgument(arg) {
                printListUsage()
                return
            } else if arg == "--debug" {
                enableDebug = true
            } else if arg == "--conversation" {
                guard index + 1 < remainingArgs.count, !remainingArgs[index + 1].hasPrefix("--") else {
                    if jsonRequested {
                        printJSONError(command: "list", message: "--conversation requires a conversation ID", code: "usage_error", exitCode: 2)
                    } else {
                        print("Error: --conversation requires a conversation ID".red)
                    }
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                conversationId = remainingArgs[index + 1]
                index += 1
            } else if arg.hasPrefix("--conversation=") {
                let inlineId = String(arg.dropFirst("--conversation=".count))
                guard !inlineId.isEmpty else {
                    if jsonRequested {
                        printJSONError(command: "list", message: "--conversation requires a conversation ID", code: "usage_error", exitCode: 2)
                    } else {
                        print("Error: --conversation requires a conversation ID".red)
                    }
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                conversationId = inlineId
            } else {
                if jsonRequested {
                    printJSONError(command: "list", message: "Unknown option for list: \(arg)", code: "usage_error", exitCode: 2)
                } else {
                    print("Error: Unknown option for list: \(arg)".red)
                    printListUsage()
                }
                if exitOnError {
                    exit(with: 2)
                }
                return
            }
            index += 1
        }

        app.setDebugMode(enableDebug && !enableJSON)

        if enableJSON {
            do {
                _ = try app.initializeClient()
                if let conversationId {
                    let responses = try await app.loadConversation(conversationId: conversationId)
                    try printJSONResult(
                        command: "list",
                        subcommand: "conversation",
                        category: "conversation_history",
                        data: AnyCodable(conversationHistoryJSON(conversationId: conversationId, responses: responses)),
                        debug: enableDebug
                    )
                } else {
                    let client = try app.initializeClient()
                    let conversations = try await client.listConversations()
                    try printJSONResult(
                        command: "list",
                        category: "conversation_list",
                        data: AnyCodable(conversationsJSON(conversations)),
                        debug: enableDebug
                    )
                }
            } catch {
                printJSONError(command: "list", error: error, exitCode: 1, debug: enableDebug)
                if exitOnError {
                    exit(with: 1)
                }
            }
            return
        }

        print("Fetching your saved conversations...".cyan)

        do {
            try await listAndSelectConversation(
                app: app,
                debug: enableDebug,
                selectionPrompt: "Select a conversation by number (or press Enter to exit): ",
                allowsEmptySelection: true
            )
        } catch {
            await app.handleError(error, debug: enableDebug)
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    static func listAndSelectConversation(
        app: GrokCLIApp,
        debug: Bool,
        selectionPrompt: String,
        allowsEmptySelection: Bool,
        invalidSelectionMessage: String? = nil,
        readSelection: ((String) -> String?)? = nil
    ) async throws {
        if debug {
            print("Debug: Attempting to list conversations...")
        }

        let client = try app.initializeClient()

        if debug {
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

        let selection: String?
        if let readSelection {
            selection = readSelection(selectionPrompt)
        } else {
            print(selectionPrompt, terminator: "")
            selection = readLine()
        }
        guard let selection else {
            if debug {
                print("Debug: User exited selection or provided invalid input")
            }
            return
        }

        if allowsEmptySelection, selection.isEmpty {
            if debug {
                print("Debug: User exited selection or provided invalid input")
            }
            return
        }

        guard let number = Int(selection), number > 0, number <= conversations.count else {
            if let invalidSelectionMessage {
                print(invalidSelectionMessage.red)
            } else if debug {
                print("Debug: User exited selection or provided invalid input")
            }
            return
        }

        let selected = conversations[number - 1]

        if debug {
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
            for response in responses {
                let sender = response.sender == "human" ? "User".magenta : "Grok".cyan
                print("\(sender)\n\(response.message)\n")
            }
        }
    }

}
