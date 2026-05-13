import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode()) {
        var segments = ["Model: \(currentMode.displayName)".yellow]
        if currentReasoning {
            segments.append("Reasoning".green)
        }
        if currentPrivate {
            segments.append("Private".red)
        }
        if !currentStream {
            segments.append("No Stream".red)
        }
        segments.append(currentFormat.statusName.yellow)

        print("Settings > ".cyan + segments.joined(separator: " | "))
    }

    static func printSettingsStatus(state: ChatSessionState) {
        printSettingsStatus(
            currentReasoning: state.reasoning,
            currentDeepSearch: state.deepSearch,
            currentNoCustomInstructions: false,
            currentNoSearch: state.noSearch,
            currentPrivate: state.privateMode,
            currentStream: state.stream,
            currentFormat: state.outputFormat,
            currentMode: state.mode
        )
    }

    static func handleChatCommand(args: [String], exitOnParseError: Bool = false) async throws {
        let quietRequested = args.contains("--quiet")
        func printParseError(_ message: String) {
            if quietRequested {
                CLIOutput.stderr("Error: \(message)")
            } else {
                print("Error: \(message)".red)
            }
        }

        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printChatUsage()
            return
        }

        if isJSONRequested(args) {
            try await handleMessageCommand(args: args, exitOnError: exitOnParseError)
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
        var enableQuiet = false
        var selectedMode = GrokMode.defaultMode

        // Parse all arguments
        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil
            let modelOption = applyModelOption(arg, nextValue: nextValue)

            if modelOption.missingValue {
                printParseError("\(arg) requires a model value")
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
                printParseError("\(arg) requires a format value")
                if exitOnParseError {
                    exit(with: 2)
                }
                return
            } else if let invalidValue = outputFormatOption.invalidValue {
                printParseError("Invalid output format '\(invalidValue)'. Use md, raw, or json.")
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
            } else if arg == "--quiet" {
                enableQuiet = true
            } else {
                initialMessage.append(arg)
            }
            index += 1
        }

        let app = GrokCLIApp.shared
        app.setQuietMode(enableQuiet)
        app.setDebugMode(enableDebug && !enableQuiet)
        app.setCurrentMode(selectedMode)

        // Reset conversation ID when starting a new chat session
        app.resetConversation()

        var formatter = OutputFormatter(format: outputFormat)
        let inputReader = InputReader(showsPromptWhenNotTTY: !enableQuiet)
        let startupStatus = !enableQuiet && !enableDebug && stdoutIsTTY()
            ? CLIOutput.TransientStatusLine()
            : nil
        let connectedMessage = "Connected to Grok! Use / for commands, or type help."

        // Initialization message
        let searchWarnings = searchConfigurationWarnings(
            deepSearchRequested: enableDeepSearch,
            noSearchRequested: enableNoSearch
        )
        let customWarnings = customInstructionsWarnings(
            noCustomInstructionsRequested: enableNoCustomInstructions
        )
        printSearchConfigurationWarnings(searchWarnings + customWarnings, toStderr: enableQuiet)
        if let startupStatus {
            startupStatus.update(text: "Calling Grok API...".cyan)
        } else if !enableQuiet {
            print("Calling Grok API...".cyan)
        }

        if enableDebug {
            let debugLines = [
                "Debug: initialMessage = \(initialMessage)",
                "Debug: Streaming = \(enableStream)",
                "Debug: Output Format = \(outputFormat.description)",
                "Debug: Model = \(selectedMode.displayName) (\(selectedMode.id))",
                "Debug: DeepSearch requested = \(enableDeepSearch) (ignored)",
                "Debug: Search disable requested = \(enableNoSearch) (ignored)",
                "Debug: Custom instructions disable requested = \(enableNoCustomInstructions) (ignored)"
            ]
            for line in debugLines {
                if enableQuiet {
                    CLIOutput.stderr(line)
                } else {
                    print(line)
                }
            }
        }

        // Try to initialize the client to check authentication before starting.
        // If credentials are missing or expired, stay in interactive mode so
        // `/auth` and `/auth import` can repair the session in place.
        var canSendInitialMessage = true
        do {
            _ = try app.initializeClient()
            if let startupStatus {
                startupStatus.update(text: "Authentication successful".green)
            } else if !enableQuiet {
                print("Authentication successful".green)
            }
        } catch {
            let recovered = await app.handleError(error, debug: enableDebug, statusLine: startupStatus)
            if recovered {
                do {
                    _ = try app.initializeClient()
                    if let startupStatus {
                        startupStatus.update(text: "Authentication successful".green)
                    } else if !enableQuiet {
                        print("Authentication successful".green)
                    }
                } catch {
                    canSendInitialMessage = false
                    _ = await app.handleError(error, debug: enableDebug, statusLine: startupStatus)
                }
            } else if app.isAuthenticationError(error) {
                canSendInitialMessage = false
                if enableQuiet {
                    CLIOutput.stderr("Interactive mode is still available. Run '/auth' or '/auth import <file>' to refresh credentials.")
                } else {
                    print("Interactive mode is still available. Run '/auth' or '/auth import <file>' to refresh credentials.".yellow)
                }
            } else {
                return
            }
        }

        // If there's an initial message, send it immediately
        var sentInitialMessage = false
        if !initialMessage.isEmpty && !canSendInitialMessage {
            if enableQuiet {
                CLIOutput.stderr("Initial message was not sent because authentication is not ready.")
                CLIOutput.stderr("After auth succeeds, send it again from the prompt.")
            } else {
                print("Initial message was not sent because authentication is not ready.".yellow)
                print("After auth succeeds, send it again from the prompt.".yellow)
            }
        } else if !initialMessage.isEmpty {
            let message = initialMessage.joined(separator: " ")
            if !enableQuiet {
                startupStatus?.finish(finalText: "Authentication successful".green)
                print("Sending message: \(message)".cyan)
            }

            do {
                let stream = try await app.msg(
                    message: message,
                    enableReasoning: enableReasoning,
                    enableDeepSearch: false,
                    disableSearch: false,
                    customInstructions: "",
                    temporary: enablePrivate,
                    mode: selectedMode,
                    workspaceIds: app.getCurrentWorkspaceIds(),
                    streamOutput: enableStream
                )

                if !enableQuiet {
                    formatter.printThinkingStatus()
                }

                if enableQuiet {
                    if enableStream {
                        try await printQuietStreamingResponse(stream)
                    } else {
                        guard let response = try await finalResponse(from: stream) else {
                            throw GrokError.streamingError
                        }
                        printQuietResponse(response.message)
                    }
                } else if enableStream {
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
                sentInitialMessage = true
            } catch {
                _ = await app.handleError(error, debug: enableDebug)
                if !app.isAuthenticationError(error) {
                    return
                }
            }
        }

        var state = ChatSessionState(
            reasoning: enableReasoning,
            deepSearch: false,
            noSearch: false,
            privateMode: enablePrivate,
            stream: enableStream,
            mode: selectedMode,
            outputFormat: outputFormat
        )
        if !sentInitialMessage && !enableQuiet {
            if canSendInitialMessage {
                if let startupStatus {
                    startupStatus.finish(finalText: connectedMessage.green)
                } else {
                    print(connectedMessage.green)
                }
            } else {
                startupStatus?.clear()
                print("Interactive mode ready. Authenticate with '/auth' or '/auth import <file>' before sending messages.".yellow)
            }
            printSettingsStatus(state: state)
            if let workspace = app.getCurrentWorkspace() {
                print("Workspace: \(workspace.cliDisplayName)".cyan)
            }
            if !app.getAttachedFileIds().isEmpty {
                print("Attached files: \(app.getAttachedFileIds().count)".cyan)
            }
            if let conversationId = app.getCurrentConversationId() {
                print("Conversation ID: \(conversationId)".cyan)
            }
        }
        if !enableQuiet {
            print("\nEnter your message:".cyan)
        }

        // Main chat loop
        var isRunning = true

        while isRunning {
            // Get user input
            guard let input = inputReader.readLine(prompt: enableQuiet ? "" : "> ") else { break }
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
                if !enableQuiet {
                    print("Goodbye!".cyan)
                }
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
                printSettingsStatus(state: state)
                continue

            case .some("reason"), .some("reasoning"):
                do {
                    state.reasoning = try GrokCLI.resolveToggle(current: state.reasoning, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/reason" : "reason")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print(state.reasoning ? "Reasoning mode enabled".yellow : "Reasoning mode disabled".blue)
                continue

            case .some("private"):
                do {
                    let previousPrivate = state.privateMode
                    state.privateMode = try GrokCLI.resolveToggle(current: state.privateMode, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/private" : "private")
                    if state.privateMode, !previousPrivate, app.getCurrentConversationId() != nil {
                        app.resetConversation()
                        print("Started a new private conversation thread.".yellow)
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Private mode: \(state.privateMode ? "ENABLED".green : "DISABLED".red)")
                printSettingsStatus(state: state)
                continue

            case .some("stream"):
                do {
                    state.stream = try GrokCLI.resolveToggle(current: state.stream, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/stream" : "stream")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Streaming: \(state.stream ? "ENABLED".green : "DISABLED".red)")
                printSettingsStatus(state: state)
                continue

            case .some("format"), .some("md"), .some("markdown"), .some("raw"):
                do {
                    let usagePrefix = interactiveCommand?.hasSlash == true ? "/\(interactiveCommand?.name ?? "format")" : (interactiveCommand?.name ?? "format")
                    state.outputFormat = try GrokCLI.resolveOutputFormatCommand(
                        command: interactiveCommand?.name ?? "format",
                        current: state.outputFormat,
                        args: interactiveArgs,
                        usage: usagePrefix
                    )
                    formatter = OutputFormatter(format: state.outputFormat)
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Output format: \(state.outputFormat.description)".green)
                printSettingsStatus(state: state)
                continue

            case .some("model"), .some("models"), .some("mode"), .some("modes"):
                let modelCommand = interactiveModelCommand(from: input)
                switch modelCommand {
                case .some(.select):
                    guard let selectedMode = promptForModelSelection(currentMode: state.mode) else {
                        continue
                    }
                    state.mode = selectedMode
                case .some(.set(let requestedMode)):
                    if requestedMode.lowercased() == "list" {
                        printAvailableModels(currentMode: state.mode)
                        continue
                    }
                    state.mode = GrokMode.resolve(requestedMode)
                case .none:
                    continue
                }
                app.setCurrentMode(state.mode)
                print("Model set to: \(state.mode.displayName) (\(state.mode.id))".green)
                printSettingsStatus(state: state)
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
                    try await GrokCLI.listAndSelectConversation(
                        app: app,
                        debug: app.getDebugMode(),
                        selectionPrompt: "Select a conversation by number: ",
                        allowsEmptySelection: false,
                        invalidSelectionMessage: "Invalid selection.",
                        readSelection: { prompt in
                            inputReader.readLine(prompt: prompt)
                        }
                    )
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                continue

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
                printSettingsStatus(state: state)
                continue

            case .some("special"):
                // Start a new private thread
                app.resetConversation()
                print("Started a new special mode conversation thread.".red.bold)
                print("Special mode activated.".red.bold)
                state.privateMode = true
                printSettingsStatus(state: state)

                do {
                    let stream = try await app.msg(
                        message: ChatCommand.hiddenMode,
                        enableReasoning: false,
                        enableDeepSearch: false,
                        disableSearch: false,
                        customInstructions: "",
                        temporary: true,
                        mode: state.mode,
                        fileAttachments: app.getAttachedFileIds(),
                        workspaceIds: state.workspaceIds(app: app),
                        streamOutput: state.stream
                    )
                    formatter.printThinkingStatus()

                    if state.stream {
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
                printSettingsStatus(state: state)
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
                if !enableQuiet {
                    formatter.printThinkingStatus()
                }
                let stream = try await app.msg(
                    message: input,
                    enableReasoning: state.reasoning,
                    enableDeepSearch: false,
                    disableSearch: false,
                    customInstructions: "",
                    temporary: state.privateMode,
                    mode: state.mode,
                    fileAttachments: pendingFileAttachments,
                    workspaceIds: state.workspaceIds(app: app),
                    streamOutput: state.stream
                )

                if enableQuiet {
                    if state.stream {
                        try await printQuietStreamingResponse(stream)
                    } else {
                        guard let response = try await finalResponse(from: stream) else {
                            throw GrokError.streamingError
                        }
                        printQuietResponse(response.message)
                    }
                } else if state.stream {
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
}
