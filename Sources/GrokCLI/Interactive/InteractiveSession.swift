import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static let deleteConfirmationPrompt = "Delete current conversation? type d to confirm delete "

    static func isDeleteConfirmation(_ input: String?) -> Bool {
        input?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "d"
    }

    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode(), rateLimitStatus: String? = nil) {
        var state = ChatSessionState(
            reasoning: currentReasoning,
            deepSearch: currentDeepSearch,
            noSearch: currentNoSearch,
            privateMode: currentPrivate,
            stream: currentStream,
            mode: currentMode,
            outputFormat: currentFormat
        )
        state.rateLimitStatus = rateLimitStatus
        printSettingsStatus(state: state)
    }

    static func printSettingsStatus(state: ChatSessionState) {
        let hudState = CLIHUDRenderer.state(from: state, app: GrokCLIApp.shared)
        for line in CLIHUDRenderer.lines(state: hudState) {
            print(line)
        }
    }

    private static func refreshRateLimitStatus(
        state: inout ChatSessionState,
        app: GrokCLIApp,
        enableQuiet: Bool,
        printWarning: Bool = false
    ) async {
        guard !enableQuiet else {
            return
        }

        state.rateLimitStatus = await app.refreshRateLimitStatus(for: state.mode)
        if printWarning, let warning = app.currentRateLimitWarning(for: state.mode) {
            print(warning.yellow)
        }
    }

    private static func printInteractiveAudioTranscript(_ transcript: String) {
        let label = TerminalStyle.text("[transcript]", .transcript)
        let displayText = transcript.trimmingCharacters(in: .newlines)
        let lines = displayText.components(separatedBy: .newlines)
        guard let first = lines.first else {
            print(label)
            return
        }

        print("\(label) \(first)")
        for line in lines.dropFirst() {
            print("             \(line)")
        }
    }

    private static func handleGoalCommand(
        args: [String],
        state: inout ChatSessionState,
        app: GrokCLIApp,
        formatter: OutputFormatter,
        enableQuiet: Bool,
        enableDebug: Bool
    ) async {
        do {
            switch try parseGoalCommand(args: args) {
            case .show:
                print(goalSummary(state.goal))
            case .create(let objective, let maxTurns):
                state.goal = GoalState(objective: objective, maxTurns: maxTurns)
                print("Goal started")
                try await runGoalLoop(
                    state: &state,
                    app: app,
                    formatter: formatter,
                    enableQuiet: enableQuiet,
                    enableDebug: enableDebug
                )
            case .pause:
                guard var goal = state.goal else {
                    print("No active goal.")
                    return
                }
                goal.status = .paused
                state.goal = goal
                print("Goal paused")
            case .resume:
                guard var goal = state.goal else {
                    print("No active goal.")
                    return
                }
                guard goal.status == .paused || goal.status == .budgetLimited else {
                    print(goalSummary(goal))
                    return
                }
                goal.status = .active
                if goal.turnsCompleted >= goal.maxTurns {
                    goal.maxTurns = goal.turnsCompleted + GoalState.defaultMaxTurns
                }
                state.goal = goal
                print("Goal resumed")
                try await runGoalLoop(
                    state: &state,
                    app: app,
                    formatter: formatter,
                    enableQuiet: enableQuiet,
                    enableDebug: enableDebug
                )
            case .clear:
                state.goal = nil
                print("Goal cleared")
            case .complete:
                guard var goal = state.goal else {
                    print("No active goal.")
                    return
                }
                goal.status = .complete
                state.goal = goal
                print("Goal complete")
            }
        } catch {
            formatter.clearTransientStatusBeforeError()
            await app.handleError(error, debug: enableDebug)
        }
    }

    private static func runGoalLoop(
        state: inout ChatSessionState,
        app: GrokCLIApp,
        formatter: OutputFormatter,
        enableQuiet: Bool,
        enableDebug: Bool
    ) async throws {
        while shouldContinueGoal(state.goal) {
            guard var goal = state.goal else {
                return
            }

            let prompt = goal.turnsCompleted == 0
                ? initialGoalPrompt(for: goal)
                : continuationGoalPrompt(for: goal)
            let pendingFileAttachments = goal.turnsCompleted == 0 ? app.getAttachedFileIds() : []
            let assistantMessage = try await sendGoalTurn(
                prompt: prompt,
                state: state,
                app: app,
                formatter: formatter,
                fileAttachments: pendingFileAttachments,
                enableQuiet: enableQuiet,
                enableDebug: enableDebug
            )
            if !pendingFileAttachments.isEmpty {
                app.clearAttachedFiles()
            }

            goal.turnsCompleted += 1
            switch goalTurnResult(from: assistantMessage) {
            case .complete:
                goal.status = .complete
                state.goal = goal
                print("Goal complete")
                return
            case .paused:
                goal.status = .paused
                state.goal = goal
                print("Goal paused")
                return
            case .continueRunning:
                if goal.turnsCompleted >= goal.maxTurns {
                    goal.status = .budgetLimited
                    state.goal = goal
                    print("Goal stopped after \(goal.maxTurns) turns.")
                    return
                }
                state.goal = goal
            case .maxTurns:
                goal.status = .budgetLimited
                state.goal = goal
                print("Goal stopped after \(goal.maxTurns) turns.")
                return
            }
        }
    }

    private static func sendGoalTurn(
        prompt: String,
        state: ChatSessionState,
        app: GrokCLIApp,
        formatter: OutputFormatter,
        fileAttachments: [String],
        enableQuiet: Bool,
        enableDebug: Bool
    ) async throws -> String {
        if !enableQuiet {
            formatter.printThinkingStatus()
        }
        let stream = try await app.msg(
            message: prompt,
            enableReasoning: true,
            enableDeepSearch: false,
            disableSearch: false,
            customInstructions: "",
            temporary: state.privateMode,
            mode: state.mode,
            fileAttachments: fileAttachments,
            workspaceIds: state.workspaceIds(app: app),
            streamOutput: state.stream
        )

        var capturedFinalResponse: ConversationResponse?
        if enableQuiet {
            if state.stream {
                capturedFinalResponse = try await printQuietGoalStreamingResponse(stream, format: state.outputFormat)
            } else {
                capturedFinalResponse = try await finalResponse(from: stream)
                if let response = capturedFinalResponse {
                    printQuietResponse(response.message, format: state.outputFormat)
                }
            }
        } else if state.stream {
            let capturedStream = AsyncThrowingStream<ConversationResponse, Error> { continuation in
                let forwardingTask = Task {
                    do {
                        for try await response in stream {
                            if response.isFinal {
                                capturedFinalResponse = response
                            }
                            continuation.yield(response)
                            if response.isFinal {
                                continuation.finish()
                                return
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    forwardingTask.cancel()
                }
            }
            try await formatter.printStreamingResponse(capturedStream)
        } else {
            capturedFinalResponse = try await finalResponse(from: stream)
            if let response = capturedFinalResponse {
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

        return capturedFinalResponse?.message ?? ""
    }

    private static func printQuietGoalStreamingResponse(
        _ stream: AsyncThrowingStream<ConversationResponse, Error>,
        format: OutputFormat
    ) async throws -> ConversationResponse? {
        var finalResponse: ConversationResponse?
        let capturedStream = AsyncThrowingStream<ConversationResponse, Error> { continuation in
            let forwardingTask = Task {
                do {
                    for try await response in stream {
                        if response.isFinal {
                            finalResponse = response
                        }
                        continuation.yield(response)
                        if response.isFinal {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                forwardingTask.cancel()
            }
        }
        try await printQuietStreamingResponse(capturedStream, format: format)
        return finalResponse
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
            try await handleMessageCommand(args: args, exitOnError: exitOnParseError, jsonCommandName: "chat")
            return
        }

        // Parse options
        var initialMessage: [String] = []
        var audioPath: String?
        var audioFormat: String?
        var refinementLevel = GrokClient.defaultSpeechRefinementLevel
        var reasoningRequested = false
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
                reasoningRequested = true
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
            } else if arg == "--stdin" {
                printParseError("--stdin is only supported by grok message")
                if exitOnParseError {
                    exit(with: 2)
                }
                return
            } else if arg == "--prompt-file" || arg.hasPrefix("--prompt-file=") {
                printParseError("--prompt-file is only supported by grok message")
                if exitOnParseError {
                    exit(with: 2)
                }
                return
            } else if arg == "--audio" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    printParseError("--audio requires a path or -")
                    if exitOnParseError {
                        exit(with: 2)
                    }
                    return
                }
                audioPath = nextValue
                index += 1
            } else if arg.hasPrefix("--audio=") {
                let value = String(arg.dropFirst("--audio=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    printParseError("--audio requires a path or -")
                    if exitOnParseError {
                        exit(with: 2)
                    }
                    return
                }
                audioPath = value
            } else if arg == "--audio-format" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    printParseError("--audio-format requires a value")
                    if exitOnParseError {
                        exit(with: 2)
                    }
                    return
                }
                audioFormat = nextValue
                index += 1
            } else if arg.hasPrefix("--audio-format=") {
                let value = String(arg.dropFirst("--audio-format=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    printParseError("--audio-format requires a value")
                    if exitOnParseError {
                        exit(with: 2)
                    }
                    return
                }
                audioFormat = value
            } else if arg == "--refinement-level" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    printParseError("--refinement-level requires a value")
                    if exitOnParseError {
                        exit(with: 2)
                    }
                    return
                }
                refinementLevel = nextValue
                index += 1
            } else if arg.hasPrefix("--refinement-level=") {
                let value = String(arg.dropFirst("--refinement-level=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    printParseError("--refinement-level requires a value")
                    if exitOnParseError {
                        exit(with: 2)
                    }
                    return
                }
                refinementLevel = value
            } else {
                initialMessage.append(arg)
            }
            index += 1
        }

        if audioPath != nil, !initialMessage.isEmpty {
            printParseError("Initial message arguments and --audio are mutually exclusive")
            if exitOnParseError {
                exit(with: 2)
            }
            return
        }

        let app = GrokCLIApp.shared
        app.setQuietMode(enableQuiet)
        app.setDebugMode(enableDebug && !enableQuiet)
        if app.usesXAIOAuthMode() {
            selectedMode = await app.resolveXAIOAuthModel(selectedMode)
        }
        app.setCurrentMode(selectedMode)

        // Reset conversation ID when starting a new chat session
        app.resetConversation()

        var formatter = OutputFormatter(format: outputFormat)
        var inputReader = InputReader(showsPromptWhenNotTTY: !enableQuiet)
        let startupStatus = !enableQuiet && !enableDebug && stdoutIsTTY()
            ? CLIOutput.TransientStatusLine()
            : nil
        var connectedServiceName = "Grok"
        let hasInitialInput = !initialMessage.isEmpty || audioPath != nil

        func loadConnectedServiceName() async throws -> String {
            do {
                return try await app.refreshSubscriptionDisplayName()
            } catch {
                if app.isAuthenticationError(error) {
                    throw error
                }
                if enableDebug && !enableQuiet {
                    print("Debug: Could not fetch subscription: \(error.localizedDescription)")
                }
                return app.currentSubscriptionDisplayName()
            }
        }

        // Initialization message
        let searchWarnings = searchConfigurationWarnings(
            deepSearchRequested: enableDeepSearch,
            noSearchRequested: enableNoSearch
        )
        let reasoningWarnings = reasoningConfigurationWarnings(
            reasoningRequested: reasoningRequested
        )
        let customWarnings = customInstructionsWarnings(
            noCustomInstructionsRequested: enableNoCustomInstructions
        )
        printSearchConfigurationWarnings(reasoningWarnings + searchWarnings + customWarnings, toStderr: enableQuiet)
        if let startupStatus {
            startupStatus.update(text: "Calling Grok API...".cyan)
        } else if !enableQuiet {
            print("Calling Grok API...".cyan)
        }

        if enableDebug {
            let debugLines = [
                "Debug: initialMessage = \(initialMessage)",
                "Debug: Reasoning = always enabled",
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
            try await app.ensureAuthenticationReady()
            if !hasInitialInput {
                connectedServiceName = try await loadConnectedServiceName()
            }
            if let startupStatus {
                startupStatus.update(text: "Authentication successful".green)
            } else if !enableQuiet {
                print("Authentication successful".green)
            }
        } catch {
            let recovered = await app.handleError(error, debug: enableDebug, statusLine: startupStatus)
            if recovered {
                do {
                    try await app.ensureAuthenticationReady()
                    if !hasInitialInput {
                        connectedServiceName = try await loadConnectedServiceName()
                    }
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
                let authHint = app.usesXAIOAuthMode()
                    ? "Interactive mode is still available. Run '/oauth' to refresh xAI OAuth credentials."
                    : "Interactive mode is still available. Run '/auth' or '/auth import <file>' to refresh credentials."
                if enableQuiet {
                    CLIOutput.stderr(authHint)
                } else {
                    print(authHint.yellow)
                }
            } else {
                return
            }
        }

        // If there's an initial message, send it immediately
        var sentInitialMessage = false
        if hasInitialInput && !canSendInitialMessage {
            if enableQuiet {
                CLIOutput.stderr("Initial message was not sent because authentication is not ready.")
                CLIOutput.stderr("After auth succeeds, send it again from the prompt.")
            } else {
                print("Initial message was not sent because authentication is not ready.".yellow)
                print("After auth succeeds, send it again from the prompt.".yellow)
            }
        } else if hasInitialInput {
            let message: String
            if let audioPath {
                do {
                    if !enableQuiet {
                        print("Transcribing audio...".cyan)
                    }
                    let resolved = try await resolveAudioInput(
                        AudioInputRequestOptions(
                            path: audioPath,
                            audioFormat: audioFormat,
                            refinementLevel: refinementLevel
                        ),
                        app: app
                    )
                    message = resolved.transcript
                } catch {
                    _ = await app.handleError(error, debug: enableDebug)
                    if !app.isAuthenticationError(error) {
                        return
                    }
                    message = ""
                }
            } else {
                message = initialMessage.joined(separator: " ")
            }
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if enableQuiet {
                    CLIOutput.stderr("Initial audio did not produce text.")
                } else {
                    print("Initial audio did not produce text.".yellow)
                }
                return
            }
            if !enableQuiet {
                startupStatus?.finish(finalText: "Authentication successful".green)
                print("Sending message: \(message)".cyan)
            }

            do {
                let stream = try await app.msg(
                    message: message,
                    enableReasoning: true,
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
                        try await printQuietStreamingResponse(stream, format: outputFormat)
                    } else {
                        guard let response = try await finalResponse(from: stream) else {
                            throw GrokError.streamingError
                        }
                        printQuietResponse(response.message, format: outputFormat)
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
                formatter.clearTransientStatusBeforeError()
                _ = await app.handleError(error, debug: enableDebug)
                if !app.isAuthenticationError(error) {
                    return
                }
            }
        }

        var state = ChatSessionState(
            reasoning: true,
            deepSearch: false,
            noSearch: false,
            privateMode: enablePrivate,
            stream: enableStream,
            mode: selectedMode,
            outputFormat: outputFormat
        )
        let renderState = InteractiveRenderState(chatState: state)

        func syncPromptHUD() {
            renderState.chatState = state
        }

        func printSessionStatus() {
            syncPromptHUD()
            guard !stdinIsTTY() || !stdoutIsTTY() else {
                return
            }
            let hudState = CLIHUDRenderer.state(from: state, app: app)
            for line in CLIHUDRenderer.lines(state: hudState) {
                print(line)
            }
        }

        var typeaheadEnabled = false
        let typeaheadController = (!enableQuiet && stdinIsTTY() && stdoutIsTTY())
            ? RemoteTypeaheadController(app: app)
            : nil
        inputReader = InputReader(
            showsPromptWhenNotTTY: !enableQuiet,
            hudProvider: {
                guard !enableQuiet, stdinIsTTY(), stdoutIsTTY() else {
                    return []
                }
                return CLIHUDRenderer.lines(
                    state: CLIHUDRenderer.state(from: renderState.chatState, app: app)
                )
            },
            typeaheadSuggestionsProvider: { buffer in
                guard typeaheadEnabled else {
                    return []
                }
                return typeaheadController?.suggestions(for: buffer) ?? []
            },
            typeaheadVersionProvider: {
                typeaheadEnabled ? (typeaheadController?.version ?? 0) : 0
            },
            typeaheadQueryDidChange: { buffer in
                guard typeaheadEnabled else {
                    return
                }
                typeaheadController?.observe(buffer: buffer)
            }
        )

        if !sentInitialMessage && !enableQuiet {
            if canSendInitialMessage {
                await refreshRateLimitStatus(state: &state, app: app, enableQuiet: enableQuiet)
                syncPromptHUD()
            }
            if canSendInitialMessage {
                if let startupStatus {
                    startupStatus.finish(finalText: "Connected to \(connectedServiceName)! Use / for commands, or type help.".green)
                } else {
                    print("Connected to \(connectedServiceName)! Use / for commands, or type help.".green)
                }
            } else {
                startupStatus?.clear()
                print("Interactive mode ready. Authenticate with '/auth' or '/auth import <file>' before sending messages.".yellow)
            }
            printSessionStatus()
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
                if interactiveCommand?.name == "skill" {
                    interactiveArgs = []
                } else {
                    interactiveArgs = try interactiveCommand?.arguments() ?? []
                }
            } catch {
                await app.handleError(error, debug: enableDebug)
                continue
            }
            var inputForSend = input

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
                state.goal = nil
                print("Started a new conversation thread.".yellow)
                printSessionStatus()
                continue

            case .some("reason"), .some("reasoning"):
                do {
                    _ = try GrokCLI.resolveToggle(current: true, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/reason" : "reason")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Warning: \(GrokCLI.interactiveReasoningAlwaysOnWarning)".yellow)
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
                printSessionStatus()
                continue

            case .some("stream"):
                do {
                    state.stream = try GrokCLI.resolveToggle(current: state.stream, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/stream" : "stream")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Streaming: \(state.stream ? "ENABLED".green : "DISABLED".red)")
                printSessionStatus()
                continue

            case .some("typeahead"):
                do {
                    typeaheadEnabled = try GrokCLI.resolveToggle(current: typeaheadEnabled, args: interactiveArgs, usage: interactiveCommand?.hasSlash == true ? "/typeahead" : "typeahead")
                    if !typeaheadEnabled {
                        typeaheadController?.reset()
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                print("Typeahead: \(typeaheadEnabled ? "ENABLED".green : "DISABLED".red)")
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
                await refreshRateLimitStatus(state: &state, app: app, enableQuiet: enableQuiet)
                printSessionStatus()
                continue

            case .some("model"), .some("models"), .some("mode"), .some("modes"):
                let modelCommand = interactiveModelCommand(from: input)
                let xaiOAuthMode = app.usesXAIOAuthMode()
                let xaiOAuthModelIDs = await app.loadXAIOAuthModelIDsIfAvailable()
                let modes = xaiOAuthMode ? [] : await app.loadModes()
                let currentDisplayMode = xaiOAuthMode ? await app.resolveXAIOAuthModel(state.mode) : state.mode
                switch modelCommand {
                case .some(.select):
                    guard let selectedMode = promptForModelSelection(
                        currentMode: currentDisplayMode,
                        modes: modes,
                        xaiOAuthModelIDs: xaiOAuthModelIDs,
                        xaiOAuthSelectable: xaiOAuthMode
                    ) else {
                        continue
                    }
                    state.mode = selectedMode
                case .some(.set(let requestedMode)):
                    if requestedMode.lowercased() == "list" {
                        printAvailableModels(
                            currentMode: currentDisplayMode,
                            modes: modes,
                            xaiOAuthModelIDs: xaiOAuthModelIDs,
                            xaiOAuthSelectable: xaiOAuthMode
                        )
                        continue
                    }
                    if xaiOAuthMode {
                        state.mode = await app.resolveXAIOAuthModel(
                            GrokMode.resolve(requestedMode, modes: xaiOAuthModes(from: xaiOAuthModelIDs))
                        )
                    } else {
                        guard let selectedMode = selectableResolvedMode(requestedMode, modes: modes) else {
                            continue
                        }
                        state.mode = selectedMode
                    }
                case .none:
                    continue
                }
                app.setCurrentMode(state.mode)
                print("Model set to: \(state.mode.displayName) (\(state.mode.id))".green)
                await refreshRateLimitStatus(state: &state, app: app, enableQuiet: enableQuiet)
                printSessionStatus()
                continue

            case .some("help"):
                formatter.printHelp()
                continue

            case .some("limits"):
                guard interactiveArgs.isEmpty else {
                    print("Usage: /limits".red)
                    continue
                }
                let summary = await app.refreshRateLimitSummary(for: state.mode)
                state.rateLimitStatus = app.currentRateLimitStatus(for: state.mode)
                print(summary.green)
                syncPromptHUD()
                continue

            case .some("goal"):
                await handleGoalCommand(
                    args: interactiveArgs,
                    state: &state,
                    app: app,
                    formatter: formatter,
                    enableQuiet: enableQuiet,
                    enableDebug: enableDebug
                )
                syncPromptHUD()
                continue

            case .some("share"):
                guard interactiveArgs.isEmpty else {
                    print("Usage: /share".red)
                    continue
                }
                do {
                    let shareLink = try await app.shareLinkForCurrentConversation()
                    do {
                        try GrokCLI.copyToClipboard(shareLink)
                        print("Copied share link \(shareLink)".green)
                    } catch {
                        print("Share link \(shareLink)".green)
                        print("Clipboard copy failed \(error.localizedDescription)".yellow)
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("resume"), .some("list"):
                guard interactiveArgs.isEmpty else {
                    print("Usage: /resume".red)
                    continue
                }
                do {
                    try await GrokCLI.listAndSelectConversation(
                        app: app,
                        debug: app.getDebugMode(),
                        selectionPrompt: "Select a conversation by number: ",
                        allowsEmptySelection: false,
                        outputFormat: state.outputFormat,
                        invalidSelectionMessage: "Invalid selection.",
                        readSelection: { prompt in
                            inputReader.readLine(prompt: prompt)
                        }
                    )
                    state.mode = app.getCurrentMode()
                    syncPromptHUD()
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                continue

            case .some("search"):
                let query = interactiveCommand?.remainder.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let liveSearch = query.isEmpty
                if liveSearch, (!stdinIsTTY() || !stdoutIsTTY() || enableQuiet) {
                    print("Usage: /search <query>".red)
                    continue
                }
                do {
                    try await GrokCLI.listAndSelectConversation(
                        app: app,
                        debug: app.getDebugMode(),
                        selectionPrompt: "Select a conversation by number: ",
                        allowsEmptySelection: false,
                        outputFormat: state.outputFormat,
                        invalidSelectionMessage: "Invalid selection.",
                        pageSize: 60,
                        searchQuery: liveSearch ? nil : query,
                        liveSearch: liveSearch,
                        readSelection: { prompt in
                            inputReader.readLine(prompt: prompt)
                        }
                    )
                    state.mode = app.getCurrentMode()
                    syncPromptHUD()
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }
                continue

            case .some("delete"):
                let skipsConfirmation = interactiveArgs == ["--yes"]
                guard interactiveArgs.isEmpty || skipsConfirmation else {
                    print("Usage: /delete [--yes]".red)
                    continue
                }
                if !skipsConfirmation {
                    guard stdinIsTTY(), stdoutIsTTY(), !enableQuiet else {
                        print("Usage: /delete --yes".red)
                        continue
                    }
                    let confirmationReader = InputReader(commandSpecs: [], showsPromptWhenNotTTY: !enableQuiet)
                    let confirmation = confirmationReader
                        .readLine(prompt: deleteConfirmationPrompt)
                    guard isDeleteConfirmation(confirmation) else {
                        print("Delete cancelled.".yellow)
                        continue
                    }
                }

                do {
                    let conversationDisplayName = try await app.deleteCurrentConversation()
                    print("Deleted conversation \(conversationDisplayName).".yellow)
                    printSessionStatus()
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

            case .some("tasks"):
                do {
                    try await GrokCLI.handleInteractiveTasksCommand(args: interactiveArgs, debug: enableDebug)
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

            case .some("skill"):
                let prompt: String
                do {
                    prompt = try GrokCLI.parseSkillCreatePrompt(from: interactiveCommand?.remainder ?? "")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }

                do {
                    state.mode = .grok43Beta
                    app.setCurrentMode(state.mode)
                    let stream = try await app.createSkillConversation(
                        prompt: prompt,
                        temporary: state.privateMode,
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
                    formatter.clearTransientStatusBeforeError()
                    await app.handleError(error, debug: enableDebug)
                }
                syncPromptHUD()
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

            case .some("oauth"):
                do {
                    try await GrokCLI.handleAuthCommand(args: ["oauth"] + interactiveArgs)
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
                        throw GrokError.apiError("Usage: /workspace")
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

            case .some("audio"):
                do {
                    let options = try parseInteractiveAudioInputOptions(
                        args: interactiveArgs,
                        usage: "/audio [send|file|record] [--audio-format <format>] [--refinement-level <level>] [path]"
                    )
                    if options.input.path == "-" {
                        throw GrokError.apiError("Audio stdin is only supported by non-interactive message/transcribe commands")
                    }
                    if !enableQuiet {
                        if options.input.path == nil {
                            print("Recording audio...".cyan)
                        } else {
                            print("Transcribing audio...".cyan)
                        }
                    }
                    let resolved = try await resolveInteractiveAudioInput(options, app: app) {
                        _ = inputReader.readLine(prompt: enableQuiet ? "" : "Press Enter to stop recording... ")
                    }
                    if !options.sendImmediately && !enableQuiet {
                        print("Edit transcript, then press Enter to send.".yellow)
                    }
                    if options.sendImmediately {
                        if !enableQuiet {
                            printInteractiveAudioTranscript(resolved.transcript)
                        }
                        inputForSend = resolved.transcript
                    } else {
                        guard let edited = inputReader.readLine(prompt: enableQuiet ? "" : "> ", prefill: resolved.transcript) else {
                            continue
                        }
                        guard !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }
                        inputForSend = edited
                    }
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }

            case .some("audio-send"):
                do {
                    let options = try parseInteractiveAudioInputOptions(
                        args: ["send"] + interactiveArgs,
                        usage: "/audio send [--audio-format <format>] [--refinement-level <level>] [path]"
                    )
                    if options.input.path == "-" {
                        throw GrokError.apiError("Audio stdin is only supported by non-interactive message/transcribe commands")
                    }
                    if !enableQuiet {
                        if options.input.path == nil {
                            print("Recording audio...".cyan)
                        } else {
                            print("Transcribing audio...".cyan)
                        }
                    }
                    let resolved = try await resolveInteractiveAudioInput(options, app: app) {
                        _ = inputReader.readLine(prompt: enableQuiet ? "" : "Press Enter to stop recording... ")
                    }
                    if !enableQuiet {
                        printInteractiveAudioTranscript(resolved.transcript)
                    }
                    inputForSend = resolved.transcript
                } catch {
                    await app.handleError(error, debug: enableDebug)
                    continue
                }

            case .some("transcribe"):
                do {
                    let options = try parseAudioInputOptions(
                        args: interactiveArgs,
                        usage: "/transcribe [--audio-format <format>] [--refinement-level <level>] <path>"
                    )
                    guard options.path != "-" else {
                        throw GrokError.apiError("Audio stdin is only supported by non-interactive message/transcribe commands")
                    }
                    if !enableQuiet {
                        print("Transcribing audio...".cyan)
                    }
                    let resolved = try await resolveAudioInput(options, app: app)
                    CLIOutput.stdout(resolved.transcript, terminator: resolved.transcript.hasSuffix("\n") ? "" : "\n")
                } catch {
                    await app.handleError(error, debug: enableDebug)
                }
                continue

//            case .some("special"):
//                // Start a new private thread
//                app.resetConversation()
//                state.goal = nil
//                print("Started a new special mode conversation thread.".red.bold)
//                print("Special mode activated.".red.bold)
//                state.privateMode = true
//                printSessionStatus()
//
//                do {
//                    let stream = try await app.msg(
//                        message: ChatCommand.hiddenMode,
//                        enableReasoning: true,
//                        enableDeepSearch: false,
//                        disableSearch: false,
//                        customInstructions: "",
//                        temporary: true,
//                        mode: state.mode,
//                        fileAttachments: app.getAttachedFileIds(),
//                        workspaceIds: state.workspaceIds(app: app),
//                        streamOutput: state.stream
//                    )
//                    formatter.printThinkingStatus()
//
//                    if state.stream {
//                        try await formatter.printStreamingResponse(stream)
//                    } else {
//                        var finalResponse: ConversationResponse?
//                        for try await response in stream {
//                            if response.isFinal {
//                                finalResponse = response
//                                break
//                            }
//                        }
//                        if let response = finalResponse {
//                            formatter.printResponse(
//                                response.message,
//                                conversationId: app.getCurrentConversationId(),
//                                responseId: app.getLastResponseId(),
//                                debug: false,
//                                webSearchResults: response.webSearchResults,
//                                xposts: response.xposts
//                            )
//                        }
//                    }
//                } catch {
//                    await app.handleError(error, debug: enableDebug)
//                    continue
//                }


            case .some("clear"), .some("cls"):
                formatter.clearScreen()
                printSessionStatus()
                continue

            case .some(let unknown) where interactiveCommand?.hasSlash == true:
                print("Unknown command /\(unknown)".red)
                if let suggestion = InteractiveCommandRegistry.nearestCommand(to: unknown) {
                    print("Did you mean \(suggestion.command)".yellow)
                }
                print("Run /help for commands".yellow)
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
                let wasMultiTurnConversation = app.getCurrentConversationId() != nil
                if !enableQuiet {
                    formatter.printThinkingStatus()
                }
                let stream = try await app.msg(
                    message: inputForSend,
                    enableReasoning: true,
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
                        try await printQuietStreamingResponse(stream, format: state.outputFormat)
                    } else {
                        guard let response = try await finalResponse(from: stream) else {
                            throw GrokError.streamingError
                        }
                        printQuietResponse(response.message, format: state.outputFormat)
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
                await refreshRateLimitStatus(
                    state: &state,
                    app: app,
                    enableQuiet: enableQuiet,
                    printWarning: wasMultiTurnConversation
                )
                syncPromptHUD()
            } catch {
                formatter.clearTransientStatusBeforeError()
                await app.handleError(error, debug: enableDebug)
            }
        }
    }
}
