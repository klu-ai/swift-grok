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

        if let subcommand = remainingArgs.first?.lowercased(), subcommand == "delete" || subcommand == "remove" {
            try await handleListDeleteCommand(
                args: Array(remainingArgs.dropFirst()),
                enableJSON: enableJSON,
                jsonRequested: jsonRequested,
                exitOnError: exitOnError
            )
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
                allowsEmptySelection: true,
                outputFormat: .defaultFormat
            )
        } catch {
            await app.handleError(error, debug: enableDebug)
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    private static func handleListDeleteCommand(
        args: [String],
        enableJSON: Bool,
        jsonRequested: Bool,
        exitOnError: Bool
    ) async throws {
        let app = GrokCLIApp.shared
        var enableDebug = false
        var confirmed = false
        var conversationId: String?

        var index = 0
        while index < args.count {
            let arg = args[index]
            if isHelpArgument(arg) {
                printListDeleteUsage()
                return
            } else if arg == "--debug" {
                enableDebug = true
            } else if arg == "--yes" || arg == "-y" {
                confirmed = true
            } else if arg == "--conversation" {
                guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                    reportListDeleteUsageError("--conversation requires a conversation ID", jsonRequested: jsonRequested || enableJSON, exitOnError: exitOnError)
                    return
                }
                conversationId = args[index + 1]
                index += 1
            } else if arg.hasPrefix("--conversation=") {
                let inlineId = String(arg.dropFirst("--conversation=".count))
                guard !inlineId.isEmpty else {
                    reportListDeleteUsageError("--conversation requires a conversation ID", jsonRequested: jsonRequested || enableJSON, exitOnError: exitOnError)
                    return
                }
                conversationId = inlineId
            } else if arg.hasPrefix("-") {
                reportListDeleteUsageError("Unknown option for list delete: \(arg)", jsonRequested: jsonRequested || enableJSON, exitOnError: exitOnError)
                return
            } else if conversationId == nil {
                conversationId = arg
            } else {
                reportListDeleteUsageError("list delete accepts one conversation ID", jsonRequested: jsonRequested || enableJSON, exitOnError: exitOnError)
                return
            }

            index += 1
        }

        guard let conversationId, !conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reportListDeleteUsageError("list delete requires a conversation ID", jsonRequested: jsonRequested || enableJSON, exitOnError: exitOnError)
            return
        }

        guard confirmed else {
            reportListDeleteUsageError("list delete requires --yes", jsonRequested: jsonRequested || enableJSON, exitOnError: exitOnError)
            return
        }

        app.setDebugMode(enableDebug && !enableJSON)

        do {
            let client = try app.initializeClient()
            try await client.softDeleteConversation(conversationId: conversationId)
            if enableJSON {
                try printJSONResult(
                    command: "list",
                    subcommand: "delete",
                    category: "conversation_delete",
                    data: AnyCodable([
                        "action": AnyCodable("soft_delete"),
                        "conversationId": AnyCodable(conversationId),
                        "deleted": AnyCodable(true)
                    ]),
                    debug: enableDebug
                )
            } else {
                print("Deleted conversation \(conversationId).".yellow)
            }
        } catch {
            if enableJSON || jsonRequested {
                printJSONError(command: "list", subcommand: "delete", error: error, exitCode: 1, debug: enableDebug)
            } else {
                await app.handleError(error, debug: enableDebug)
            }
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    private static func reportListDeleteUsageError(_ message: String, jsonRequested: Bool, exitOnError: Bool) {
        if jsonRequested {
            printJSONError(command: "list", subcommand: "delete", message: message, code: "usage_error", exitCode: 2)
        } else {
            print("Error: \(message)".red)
            printListDeleteUsage()
        }
        if exitOnError {
            exit(with: 2)
        }
    }

    private static func printListDeleteUsage() {
        print("""
        Usage: grok list delete <conversationId> --yes [--json|--format json] [--debug]

        Soft-deletes one saved conversation by ID.
        """)
    }

    static func listAndSelectConversation(
        app: GrokCLIApp,
        debug: Bool,
        selectionPrompt: String,
        allowsEmptySelection: Bool,
        outputFormat: OutputFormat = .defaultFormat,
        invalidSelectionMessage: String? = nil,
        pageSize: Int = 100,
        searchQuery: String? = nil,
        liveSearch: Bool = false,
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

        let conversations = try await client.listConversations(pageSize: pageSize, searchQuery: searchQuery)

        if app.getDebugMode() {
            print("Debug: Retrieved \(conversations.count) conversations")
        }

        if conversations.isEmpty, !liveSearch {
            print("No conversations found.".yellow)
            return
        }

        if stdinIsTTY(), stdoutIsTTY() {
            let items = pickerItems(for: conversations)

            guard let selected = InteractivePicker.select(
                title: liveSearch ? "Search conversations" : "Select conversation",
                items: items,
                previewProvider: conversationPreviewProvider(client: client),
                remoteItemsProvider: liveSearch ? { query in
                    let conversations = try await client.listConversations(pageSize: pageSize, searchQuery: query)
                    return pickerItems(for: conversations)
                } : nil
            ) else {
                return
            }

            try await loadAndPrintConversation(selected, app: app, debug: debug, outputFormat: outputFormat)
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
        try await loadAndPrintConversation(selected, app: app, debug: debug, outputFormat: outputFormat)
    }

    private static func pickerItems(for conversations: [Conversation]) -> [PickerItem<Conversation>] {
        conversations.map { conversation in
            let dateMetadata = conversationDateMetadata(conversation)
            let preview = conversationPreviewText(conversation.preview)
            return PickerItem(
                id: conversation.conversationId,
                title: conversation.title,
                subtitle: conversationListSubtitle(conversation, dateMetadata: dateMetadata),
                metadataLabel: dateMetadata?.label,
                metadata: dateMetadata?.value,
                preview: preview,
                value: conversation,
                searchText: [
                    conversation.title,
                    conversation.conversationId,
                    conversation.systemPromptName,
                    dateMetadata?.value,
                    preview
                ].compactMap { $0 }.joined(separator: " ")
            )
        }
    }

    private static func loadAndPrintConversation(_ selected: Conversation, app: GrokCLIApp, debug: Bool, outputFormat: OutputFormat) async throws {
        if debug {
            print("Debug: Selected conversation ID: \(selected.conversationId)")
            print("Debug: Selected conversation title: \(selected.title)")
            print("Debug: Loading conversation responses...")
        }

        print("\nLoading conversation \"\(selected.title)\"...".green)
        let responses = try await app.loadConversation(conversationId: selected.conversationId, title: selected.title)

        if app.getDebugMode() {
            print("Debug: Loaded \(responses.count) responses")
        }
        if let resumedMode = app.getLastLoadedConversationMode() {
            print("Model: \(resumedMode.displayName) (\(resumedMode.id))".cyan)
        }

        print("\n\(selected.title)\n".green)
        if responses.isEmpty {
            print("This conversation has no messages yet.".yellow)
        } else {
            let formatter = OutputFormatter(format: outputFormat)
            for response in responses {
                let isHuman = response.sender == "human"
                let sender = isHuman ? "User".magenta : "Grok".cyan
                formatter.printConversationReplayMessage(
                    sender: sender,
                    message: response.message,
                    isAssistant: !isHuman
                )
            }
        }
    }

    private static func conversationDateMetadata(_ conversation: Conversation) -> (label: String, value: String)? {
        let modified = conversation.modifyTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !modified.isEmpty {
            return ("modified", modified)
        }

        let created = conversation.createTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !created.isEmpty {
            return ("created", created)
        }

        return nil
    }

    private static func conversationListSubtitle(
        _ conversation: Conversation,
        dateMetadata: (label: String, value: String)?
    ) -> String? {
        var parts: [String] = []
        if conversation.temporary {
            parts.append("private")
        } else if !conversation.systemPromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(conversation.systemPromptName)
        }
        if let dateMetadata {
            parts.append("\(dateMetadata.label) \(dateMetadata.value)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private static func conversationPreviewProvider(client: GrokClient) -> (Conversation) async -> String? {
        { conversation in
            do {
                let responseNodes = try await client.getResponseNodes(conversationId: conversation.conversationId)
                if let lastResponseId = responseNodes.reversed().first?.responseId {
                    let responses = try await client.loadResponses(
                        conversationId: conversation.conversationId,
                        specificResponseIds: [lastResponseId]
                    )
                    return conversationPreviewText(from: responses)
                }
                let responses = try await client.loadResponses(conversationId: conversation.conversationId)
                return conversationPreviewText(from: responses)
            } catch {
                return nil
            }
        }
    }

    private static func conversationPreviewText(from responses: [Response]) -> String? {
        for response in responses.reversed() {
            if let preview = conversationPreviewText(response.message) {
                return preview
            }
        }
        return nil
    }

    private static func conversationPreviewText(_ message: String) -> String? {
        let lines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)

        let preview = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else {
            return nil
        }

        let maxLength = 240
        if preview.count <= maxLength {
            return preview
        }

        let end = preview.index(preview.startIndex, offsetBy: maxLength)
        return String(preview[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
