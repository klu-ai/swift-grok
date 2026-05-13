import ArgumentParser
import Foundation
import GrokClient
import Rainbow

struct MessageCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "message",
        abstract: "Send a single message to Grok and get a response"
    )
    @OptionGroup var options: GrokCommandOptions

    @Argument(parsing: .remaining, help: "The message to send")
    var messageWords: [String]

    func run() async throws {
        let app = GrokCLIApp.shared
        app.setDebugMode(options.debug)
        let selectedMode = GrokMode.resolve(options.model)
        app.setCurrentMode(selectedMode)
        let formatter = OutputFormatter(format: try options.resolvedOutputFormat())
        let searchWarnings = GrokCLI.searchConfigurationWarnings(
            deepSearchRequested: options.deepSearch,
            noSearchRequested: options.noSearch
        )
        let customWarnings = GrokCLI.customInstructionsWarnings(
            noCustomInstructionsRequested: options.noCustomInstructions
        )

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
        if !formatter.format.isJSON {
            GrokCLI.printSearchConfigurationWarnings(searchWarnings)
            GrokCLI.printSearchConfigurationWarnings(customWarnings)
        }
        print("Calling Grok API...".cyan)
        print("Sending: \(message)".cyan)

        do {
            // Try to initialize the client
            _ = try app.initializeClient()

            let stream = try await app.msg(
                message: message,
                enableReasoning: options.reasoning,
                enableDeepSearch: false,
                disableSearch: false,
                customInstructions: "",
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


extension GrokCLI {
    static func handleMessageCommand(args: [String], exitOnError: Bool = false) async throws {
        let jsonRequested = isJSONRequested(args)
        let quietRequested = args.contains("--quiet")

        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printMessageUsage()
            return
        }

        // Parse options (very simple for now)
        var message: [String] = []
        var promptFile: String?
        var explicitStdin = false
        var enableReasoning = false
        var enableDeepSearch = false
        var outputFormat = OutputFormat.defaultFormat
        var enableDebug = false
        var enableNoSearch = false
        var enableNoCustomInstructions = false
        var enablePrivate = false
        var enableStream = false  // Default to non-streaming for message command
        var enableQuiet = false
        var selectedMode = GrokMode.defaultMode

        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil
            let modelOption = applyModelOption(arg, nextValue: nextValue)

            if modelOption.missingValue {
                reportMessageUsageError("\(arg) requires a model value", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
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
                reportMessageUsageError("\(arg) requires a format value", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                if exitOnError {
                    exit(with: 2)
                }
                return
            } else if let invalidValue = outputFormatOption.invalidValue {
                reportMessageUsageError("Invalid output format '\(invalidValue)'. Use md, raw, or json.", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
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
            } else if arg == "--quiet" {
                enableQuiet = true
            } else if arg == "--stdin" {
                explicitStdin = true
            } else if arg == "--prompt-file" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportMessageUsageError("--prompt-file requires a path", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                promptFile = nextValue
                index += 1
            } else if arg.hasPrefix("--prompt-file=") {
                let value = String(arg.dropFirst("--prompt-file=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportMessageUsageError("--prompt-file requires a path", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                promptFile = value
            } else {
                message.append(arg)
            }
            index += 1
        }

        let jsonMode = outputFormat.isJSON
        let promptSourceCount = (message.isEmpty ? 0 : 1) + (promptFile == nil ? 0 : 1) + (explicitStdin ? 1 : 0)
        guard promptSourceCount <= 1 else {
            reportMessageUsageError("Inline message arguments cannot be combined with --prompt-file or --stdin", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: enableQuiet)
            if exitOnError {
                exit(with: 2)
            }
            return
        }

        let messageText: String
        let messageCameFromStdin: Bool
        do {
            if let promptFile {
                do {
                    messageText = try readPromptFile(promptFile)
                    messageCameFromStdin = false
                } catch {
                    throw GrokError.apiError("Could not read --prompt-file \(promptFile): \(error.localizedDescription)")
                }
            } else if explicitStdin || (message.isEmpty && !stdinIsTTY()) {
                messageText = try readStandardInput()
                messageCameFromStdin = true
            } else {
                messageText = message.joined(separator: " ")
                messageCameFromStdin = false
            }
        } catch {
            reportMessageUsageError(error.localizedDescription, jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: enableQuiet)
            if exitOnError {
                exit(with: 2)
            }
            return
        }

        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = messageCameFromStdin
                ? "Please provide a message to send on stdin"
                : "Please provide a message to send"
            reportMessageUsageError(message, jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: enableQuiet)
            if exitOnError {
                exit(with: 2)
            }
            return
        }

        let searchWarnings = searchConfigurationWarnings(
            deepSearchRequested: enableDeepSearch,
            noSearchRequested: enableNoSearch
        )
        let customWarnings = customInstructionsWarnings(
            noCustomInstructionsRequested: enableNoCustomInstructions
        )
        let warnings = searchWarnings + customWarnings

        // Execute the command
        if !jsonMode {
            printSearchConfigurationWarnings(warnings, toStderr: enableQuiet)
            if !enableQuiet {
                print("Calling Grok API...".cyan)
            }
        }

        if enableDebug && !jsonMode {
            let debugLines = [
                "Debug: Message = \"\(messageText)\"",
                "Debug: Reasoning = \(enableReasoning)",
                "Debug: DeepSearch requested = \(enableDeepSearch) (ignored)",
                "Debug: Search disable requested = \(enableNoSearch) (ignored)",
                "Debug: Output Format = \(outputFormat.description)",
                "Debug: Streaming = \(enableStream)",
                "Debug: Model = \(selectedMode.displayName) (\(selectedMode.id))",
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

        let app = GrokCLIApp.shared
        app.setQuietMode(enableQuiet && !jsonMode)
        app.setDebugMode(enableDebug && !jsonMode && !enableQuiet)
        app.setCurrentMode(selectedMode)

        // For single message commands, always reset the conversation
        app.resetConversation()

        let formatter = OutputFormatter(format: outputFormat)

        if !jsonMode && !enableQuiet {
            print("Sending: \(messageText)".cyan)
            formatter.printThinkingStatus()
        }

        do {
            // Initialize client
            _ = try app.initializeClient()

            // Send message
            let stream = try await app.msg(
                message: messageText,
                enableReasoning: enableReasoning,
                enableDeepSearch: false,
                disableSearch: false,
                customInstructions: "",
                temporary: enablePrivate,
                mode: selectedMode,
                workspaceIds: app.getCurrentWorkspaceIds(),
                streamOutput: enableStream
            )

            if jsonMode {
                let request = messageRequestJSON(
                    reasoning: enableReasoning,
                    deepSearch: false,
                    noSearch: false,
                    privateMode: enablePrivate,
                    stream: enableStream,
                    workspaceIds: app.getCurrentWorkspaceIds(),
                    fileAttachmentIds: []
                )
                if enableStream {
                    let streamSucceeded = try await printMessageJSONStream(
                        stream,
                        message: messageText,
                        mode: selectedMode,
                        request: request,
                        debug: enableDebug,
                        warnings: warnings
                    )
                    if !streamSucceeded, exitOnError {
                        exit(with: 1)
                    }
                } else {
                    guard let response = try await finalResponse(from: stream) else {
                        throw GrokError.streamingError
                    }
                    try printJSONResult(
                        command: "message",
                        category: "assistant_response",
                        data: AnyCodable(assistantResponseJSON(response: response, mode: selectedMode, request: request)),
                        debug: enableDebug,
                        warnings: warnings
                    )
                }
            } else if enableQuiet {
                if enableStream {
                    try await printQuietStreamingResponse(stream)
                } else {
                    guard let response = try await finalResponse(from: stream) else {
                        throw GrokError.streamingError
                    }
                    printQuietResponse(response.message)
                }
            } else if enableStream {
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
            if jsonMode {
                if enableStream {
                    try? printJSONErrorEvent(sequence: 1, error: error, exitCode: 1, debug: enableDebug)
                    try? printJSONEvent(sequence: 2, event: "done", data: AnyCodable([
                        "ok": AnyCodable(false),
                        "phase": AnyCodable("aborted")
                    ]))
                } else {
                    printJSONError(command: "message", error: error, exitCode: 1, debug: enableDebug)
                }
            } else {
                await app.handleError(error, debug: enableDebug)
            }
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    static func reportMessageUsageError(_ message: String, jsonRequested: Bool, exitOnError: Bool, toStderr: Bool = false) {
        if jsonRequested {
            printJSONError(
                command: "message",
                message: message,
                code: "usage_error",
                exitCode: 2
            )
        } else if toStderr {
            CLIOutput.stderr("Error: \(message)")
        } else {
            print("Error: \(message)".red)
        }
    }

    static func printQuietResponse(_ message: String) {
        CLIOutput.stdout(message, terminator: message.hasSuffix("\n") ? "" : "\n")
    }

    static func printQuietStreamingResponse(_ stream: AsyncThrowingStream<ConversationResponse, Error>) async throws {
        let answerParser = GrokStreamMarkupParser()
        var printedAnswerDelta = false
        var printedAnyText = false
        var finalResponse: ConversationResponse?

        func printEvents(_ events: [StreamDisplayEvent]) {
            for event in events {
                guard case .text(let text) = event, !text.isEmpty else {
                    continue
                }
                printedAnswerDelta = true
                printedAnyText = true
                CLIOutput.stdout(text, terminator: "")
            }
        }

        for try await response in stream {
            if response.isSoftStop && response.message.isEmpty {
                continue
            }

            if response.isFinal {
                finalResponse = response
            } else if !response.isThinking {
                printEvents(answerParser.consume(response.message))
            }
        }

        printEvents(answerParser.finish())

        if !printedAnswerDelta, let finalResponse {
            printQuietResponse(finalResponse.message)
            return
        }

        if printedAnyText {
            CLIOutput.stdout("", terminator: "\n")
        }
    }

    static func finalResponse(from stream: AsyncThrowingStream<ConversationResponse, Error>) async throws -> ConversationResponse? {
        for try await response in stream {
            if response.isFinal {
                return response
            }
        }
        return nil
    }

    static func printMessageJSONStream(
        _ stream: AsyncThrowingStream<ConversationResponse, Error>,
        message: String,
        mode: GrokMode,
        request: [String: AnyCodable],
        debug: Bool = false,
        warnings: [String] = []
    ) async throws -> Bool {
        var sequence = 1
        var requestData: [String: AnyCodable] = [
            "message": AnyCodable(message),
            "model": AnyCodable(modeJSON(mode)),
            "request": AnyCodable(request)
        ]
        if !warnings.isEmpty {
            requestData["warnings"] = AnyCodable(warnings)
        }
        try printJSONEvent(sequence: sequence, event: "request", data: AnyCodable(requestData))
        sequence += 1
        try printJSONEvent(sequence: sequence, event: "progress", data: AnyCodable([
            "phase": AnyCodable("stream_started"),
            "message": AnyCodable("Streaming response started")
        ]))
        sequence += 1

        let answerParser = GrokStreamMarkupParser()
        let thinkingParser = GrokStreamMarkupParser(hidesHiddenPreamble: false)
        var thinkingActive = false
        var emittedFinal = false

        func emitDisplayEvents(_ events: [StreamDisplayEvent], textEvent: String) throws {
            for event in events {
                switch event {
                case .text(let text):
                    guard !text.isEmpty else { continue }
                    try printJSONEvent(sequence: sequence, event: textEvent, data: AnyCodable(["text": AnyCodable(text)]))
                    sequence += 1
                case .trace(let line):
                    try printJSONEvent(sequence: sequence, event: "trace", data: AnyCodable(["kind": AnyCodable("tool"), "text": AnyCodable(line)]))
                    sequence += 1
                }
            }
        }

        do {
            for try await response in stream {
                if response.isSoftStop && response.message.isEmpty {
                    continue
                }

                if response.isFinal {
                    if thinkingActive {
                        try printJSONEvent(sequence: sequence, event: "thinking_end", data: AnyCodable([
                            "phase": AnyCodable("thinking")
                        ]))
                        sequence += 1
                        thinkingActive = false
                    }
                    try emitDisplayEvents(answerParser.finish(), textEvent: "assistant_delta")
                    let data = assistantResponseJSON(response: response, mode: mode, request: request)
                    try printJSONEvent(sequence: sequence, event: "assistant_final", data: AnyCodable(data))
                    sequence += 1
                    try printJSONEvent(sequence: sequence, event: "done", data: AnyCodable([
                        "ok": AnyCodable(true),
                        "phase": AnyCodable("complete")
                    ]))
                    sequence += 1
                    emittedFinal = true
                } else if response.isThinking {
                    if !thinkingActive {
                        try printJSONEvent(sequence: sequence, event: "thinking_start", data: AnyCodable([
                            "phase": AnyCodable("thinking")
                        ]))
                        sequence += 1
                        thinkingActive = true
                    }
                    let events = thinkingParser.consume(response.message)
                    for event in events {
                        switch event {
                        case .text(let text):
                            let lines = text
                                .split(separator: "\n", omittingEmptySubsequences: false)
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            for line in lines {
                                try printJSONEvent(sequence: sequence, event: "thinking_delta", data: AnyCodable(["text": AnyCodable(line)]))
                                sequence += 1
                                try printJSONEvent(sequence: sequence, event: "trace", data: AnyCodable(["kind": AnyCodable("thinking"), "text": AnyCodable(line)]))
                                sequence += 1
                            }
                        case .trace(let line):
                            try printJSONEvent(sequence: sequence, event: "progress", data: AnyCodable(["kind": AnyCodable("tool"), "text": AnyCodable(line)]))
                            sequence += 1
                            try printJSONEvent(sequence: sequence, event: "trace", data: AnyCodable(["kind": AnyCodable("tool"), "text": AnyCodable(line)]))
                            sequence += 1
                        }
                    }
                } else {
                    if thinkingActive {
                        try printJSONEvent(sequence: sequence, event: "thinking_end", data: AnyCodable([
                            "phase": AnyCodable("thinking")
                        ]))
                        sequence += 1
                        thinkingActive = false
                    }
                    try emitDisplayEvents(answerParser.consume(response.message), textEvent: "assistant_delta")
                }
            }

            try emitDisplayEvents(answerParser.finish(), textEvent: "assistant_delta")
            if !emittedFinal {
                try printJSONEvent(sequence: sequence, event: "done", data: AnyCodable([
                    "ok": AnyCodable(true),
                    "phase": AnyCodable("complete")
                ]))
            }
            return true
        } catch {
            if thinkingActive {
                try printJSONEvent(sequence: sequence, event: "thinking_end", data: AnyCodable([
                    "phase": AnyCodable("thinking")
                ]))
                sequence += 1
            }
            try printJSONErrorEvent(sequence: sequence, error: error, exitCode: 1, debug: debug)
            sequence += 1
            try printJSONEvent(sequence: sequence, event: "done", data: AnyCodable([
                "ok": AnyCodable(false),
                "phase": AnyCodable("aborted")
            ]))
            return false
        }
    }

}
