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
        var selectedMode = GrokMode.resolve(options.model)
        if app.usesXAIOAuthMode() {
            selectedMode = await app.resolveXAIOAuthModel(selectedMode)
        }
        app.setCurrentMode(selectedMode)
        let formatter = OutputFormatter(format: try options.resolvedOutputFormat())
        let reasoningWarnings = GrokCLI.reasoningConfigurationWarnings(
            reasoningRequested: options.reasoning
        )
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
            print("Debug: Reasoning: always enabled")
            print("Debug: Streaming: \(options.stream)")
            print("Debug: Model: \(selectedMode.displayName) (\(selectedMode.id))")
        }

        // Initialization message
        if !formatter.format.isJSON {
            GrokCLI.printSearchConfigurationWarnings(reasoningWarnings)
            GrokCLI.printSearchConfigurationWarnings(searchWarnings)
            GrokCLI.printSearchConfigurationWarnings(customWarnings)
        }
        print("Calling Grok API...".cyan)
        print("Sending: \(message)".cyan)

        do {
            try await app.ensureAuthenticationReady()

            let stream = try await app.msg(
                message: message,
                enableReasoning: true,
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
            formatter.clearTransientStatusBeforeError()
            await app.handleError(error, debug: options.debug)
        }
    }
}


extension GrokCLI {
    static func handleMessageCommand(
        args: [String],
        exitOnError: Bool = false,
        jsonCommandName: String = "message"
    ) async throws {
        let jsonRequested = isJSONRequested(args)
        let quietRequested = args.contains("--quiet")

        func reportUsageError(_ message: String, toStderr: Bool) {
            reportMessageUsageError(
                message,
                jsonRequested: jsonRequested,
                exitOnError: exitOnError,
                command: jsonCommandName,
                toStderr: toStderr
            )
        }

        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printMessageUsage()
            return
        }

        // Parse options (very simple for now)
        var message: [String] = []
        var promptFile: String?
        var explicitStdin = false
        var audioPath: String?
        var audioFormat: String?
        var uploadPaths: [String] = []
        var attachmentIds: [String] = []
        var refinementLevel = GrokClient.defaultSpeechRefinementLevel
        var reasoningRequested = false
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
                reportUsageError("\(arg) requires a model value", toStderr: quietRequested)
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
                reportUsageError("\(arg) requires a format value", toStderr: quietRequested)
                if exitOnError {
                    exit(with: 2)
                }
                return
            } else if let invalidValue = outputFormatOption.invalidValue {
                reportUsageError("Invalid output format '\(invalidValue)'. Use md, raw, or json.", toStderr: quietRequested)
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
                explicitStdin = true
            } else if arg == "--audio" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportUsageError("--audio requires a path or -", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                audioPath = nextValue
                index += 1
            } else if arg.hasPrefix("--audio=") {
                let value = String(arg.dropFirst("--audio=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportUsageError("--audio requires a path or -", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                audioPath = value
            } else if arg == "--audio-format" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportUsageError("--audio-format requires a value", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                audioFormat = nextValue
                index += 1
            } else if arg.hasPrefix("--audio-format=") {
                let value = String(arg.dropFirst("--audio-format=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportUsageError("--audio-format requires a value", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                audioFormat = value
            } else if arg == "--file" || arg == "--upload" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportUsageError("\(arg) requires a path", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                uploadPaths.append(nextValue)
                index += 1
            } else if arg.hasPrefix("--file=") {
                let value = String(arg.dropFirst("--file=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportUsageError("--file requires a path", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                uploadPaths.append(value)
            } else if arg.hasPrefix("--upload=") {
                let value = String(arg.dropFirst("--upload=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportUsageError("--upload requires a path", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                uploadPaths.append(value)
            } else if arg == "--attach" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportUsageError("--attach requires a file ID", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                attachmentIds.append(nextValue)
                index += 1
            } else if arg.hasPrefix("--attach=") {
                let value = String(arg.dropFirst("--attach=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportUsageError("--attach requires a file ID", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                attachmentIds.append(value)
            } else if arg == "--refinement-level" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportUsageError("--refinement-level requires a value", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                refinementLevel = nextValue
                index += 1
            } else if arg.hasPrefix("--refinement-level=") {
                let value = String(arg.dropFirst("--refinement-level=".count))
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    reportUsageError("--refinement-level requires a value", toStderr: quietRequested)
                    if exitOnError {
                        exit(with: 2)
                    }
                    return
                }
                refinementLevel = value
            } else if arg == "--prompt-file" {
                guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
                    reportUsageError("--prompt-file requires a path", toStderr: quietRequested)
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
                    reportUsageError("--prompt-file requires a path", toStderr: quietRequested)
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
        let promptSourceCount = (message.isEmpty ? 0 : 1) + (promptFile == nil ? 0 : 1) + (explicitStdin ? 1 : 0) + (audioPath == nil ? 0 : 1)
        guard promptSourceCount <= 1 else {
            reportUsageError("Inline message arguments, --audio, --prompt-file, and --stdin are mutually exclusive", toStderr: enableQuiet)
            if exitOnError {
                exit(with: 2)
            }
            return
        }

        let app = GrokCLIApp.shared
        app.setQuietMode(enableQuiet && !jsonMode)
        app.setDebugMode(enableDebug && !jsonMode && !enableQuiet)
        if app.usesXAIOAuthMode() {
            selectedMode = await app.resolveXAIOAuthModel(selectedMode)
        }
        app.setCurrentMode(selectedMode)

        let messageText: String
        let messageCameFromStdin: Bool
        var resolvedAudioInput: ResolvedAudioInput?
        do {
            if let audioPath {
                if !jsonMode && !enableQuiet {
                    print("Transcribing audio...".cyan)
                }
                let audioOptions = AudioInputRequestOptions(
                    path: audioPath,
                    audioFormat: audioFormat,
                    refinementLevel: refinementLevel
                )
                let resolved = try await resolveAudioInput(audioOptions, app: app)
                resolvedAudioInput = resolved
                messageText = resolved.transcript
                messageCameFromStdin = audioPath == "-"
            } else if let promptFile {
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
            reportUsageError(error.localizedDescription, toStderr: enableQuiet)
            if exitOnError {
                exit(with: 2)
            }
            return
        }

        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = messageCameFromStdin
                ? "Please provide a message to send on stdin"
                : "Please provide a message to send"
            reportUsageError(message, toStderr: enableQuiet)
            if exitOnError {
                exit(with: 2)
            }
            return
        }

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
        let warnings = reasoningWarnings + searchWarnings + customWarnings

        // Execute the command
        if !jsonMode {
            printSearchConfigurationWarnings(warnings, toStderr: enableQuiet)
        }

        if enableDebug && !jsonMode {
            let debugLines = [
                "Debug: Message = \"\(messageText)\"",
                "Debug: Reasoning = always enabled",
                "Debug: DeepSearch requested = \(enableDeepSearch) (ignored)",
                "Debug: Search disable requested = \(enableNoSearch) (ignored)",
                "Debug: Output Format = \(outputFormat.description)",
                "Debug: Streaming = \(enableStream)",
                "Debug: Model = \(selectedMode.displayName) (\(selectedMode.id))",
                "Debug: Upload Files = \(uploadPaths.count)",
                "Debug: Existing Attachments = \(attachmentIds.count)",
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

        // For single message commands, always reset the conversation
        app.resetConversation()

        let formatter = OutputFormatter(format: outputFormat)

        do {
            try await app.ensureAuthenticationReady()

            var fileAttachmentIds = attachmentIds
            if !uploadPaths.isEmpty, !jsonMode, !enableQuiet {
                print(uploadPaths.count == 1 ? "Uploading file...".cyan : "Uploading \(uploadPaths.count) files...".cyan)
            }
            for path in uploadPaths {
                let mimeType = inferredMessageAttachmentMimeType(for: path)
                let response = if app.usesXAIOAuthMode() {
                    try await app.uploadFileWithXAIOAuth(at: path, mimeType: mimeType)
                } else {
                    try await app.initializeClient().uploadFile(
                        at: path,
                        mimeType: mimeType
                    )
                }
                guard let fileId = response.uploadedFileId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !fileId.isEmpty else {
                    throw GrokError.apiError("Uploaded file response did not include an attachment ID")
                }
                appendUniqueAttachmentId(fileId, to: &fileAttachmentIds)
                if !jsonMode, !enableQuiet {
                    let fileName = response.fileName ?? URL(fileURLWithPath: path).lastPathComponent
                    print("Attached: \(fileName)".green)
                }
            }

            if !jsonMode && !enableQuiet {
                print("Calling Grok API...".cyan)
                print("Sending: \(messageText)".cyan)
                formatter.printThinkingStatus()
            }

            // Send message
            let stream = try await app.msg(
                message: messageText,
                enableReasoning: true,
                enableDeepSearch: false,
                disableSearch: false,
                customInstructions: "",
                temporary: enablePrivate,
                mode: selectedMode,
                fileAttachments: fileAttachmentIds,
                workspaceIds: app.getCurrentWorkspaceIds(),
                streamOutput: enableStream
            )

            if jsonMode {
                let request = messageRequestJSON(
                    reasoning: true,
                    deepSearch: false,
                    noSearch: false,
                    privateMode: enablePrivate,
                    stream: enableStream,
                    workspaceIds: app.getCurrentWorkspaceIds(),
                    fileAttachmentIds: fileAttachmentIds
                )
                if enableStream {
                    let streamSucceeded = try await printMessageJSONStream(
                        stream,
                        message: messageText,
                        mode: selectedMode,
                        request: request,
                        input: resolvedAudioInput?.json,
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
                        command: jsonCommandName,
                        category: "assistant_response",
                        data: AnyCodable(assistantResponseJSON(response: response, mode: selectedMode, request: request, input: resolvedAudioInput?.json)),
                        debug: enableDebug,
                        warnings: warnings
                    )
                }
            } else if enableQuiet {
                if enableStream {
                    try await printQuietStreamingResponse(stream, format: outputFormat)
                } else {
                    guard let response = try await finalResponse(from: stream) else {
                        throw GrokError.streamingError
                    }
                    printQuietResponse(response.message, format: outputFormat)
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
                    printJSONError(command: jsonCommandName, error: error, exitCode: 1, debug: enableDebug)
                }
            } else {
                formatter.clearTransientStatusBeforeError()
                await app.handleError(error, debug: enableDebug)
            }
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    static func reportMessageUsageError(
        _ message: String,
        jsonRequested: Bool,
        exitOnError: Bool,
        command: String = "message",
        toStderr: Bool = false
    ) {
        if jsonRequested {
            printJSONError(
                command: command,
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

    static func printQuietResponse(_ message: String, format: OutputFormat = .raw) {
        guard format == .markdown else {
            let visibleMessage = GrokStreamMarkupParser.visibleText(from: message)
            CLIOutput.stdout(visibleMessage, terminator: visibleMessage.hasSuffix("\n") ? "" : "\n")
            return
        }

        OutputFormatter(format: .markdown).printQuietResponseBody(message)
    }

    static func printQuietStreamingResponse(_ stream: AsyncThrowingStream<ConversationResponse, Error>, format: OutputFormat = .raw) async throws {
        if format == .markdown {
            try await printQuietMarkdownStreamingResponse(stream)
            return
        }

        try await printRawQuietStreamingResponse(stream)
    }

    private static func printQuietMarkdownStreamingResponse(_ stream: AsyncThrowingStream<ConversationResponse, Error>) async throws {
        var finalResponse: ConversationResponse?
        var collectedMessage = ""

        for try await response in stream {
            if response.isSoftStop && response.message.isEmpty {
                continue
            }

            if response.isFinal {
                finalResponse = response
                break
            } else if !response.isThinking {
                collectedMessage += response.message
            }
        }

        printQuietResponse(finalResponse?.message ?? collectedMessage, format: .markdown)
    }

    private static func printRawQuietStreamingResponse(_ stream: AsyncThrowingStream<ConversationResponse, Error>) async throws {
        let answerParser = GrokStreamMarkupParser()
        var printedAnswerDelta = false
        var printedAnyText = false
        var finalResponse: ConversationResponse?

        func printEvents(_ events: [StreamDisplayEvent]) {
            let text = events.compactMap { event -> String? in
                guard case .text(let text) = event else { return nil }
                return text
            }.joined()
            guard !text.isEmpty else {
                return
            }
            let visibleText = GrokStreamMarkupParser.visibleText(from: text, hidesHiddenPreamble: false)
            guard !visibleText.isEmpty else {
                return
            }
            printedAnswerDelta = true
            printedAnyText = true
            CLIOutput.stdout(visibleText, terminator: "")
        }

        for try await response in stream {
            if response.isSoftStop && response.message.isEmpty {
                continue
            }

            if response.isFinal {
                finalResponse = response
                break
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

    static func appendUniqueAttachmentId(_ fileId: String, to attachmentIds: inout [String]) {
        guard !attachmentIds.contains(fileId) else {
            return
        }
        attachmentIds.append(fileId)
    }

    static func inferredMessageAttachmentMimeType(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "txt":
            return "text/plain"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "pdf":
            return "application/pdf"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "md":
            return "text/markdown"
        default:
            return "application/octet-stream"
        }
    }

    static func printMessageJSONStream(
        _ stream: AsyncThrowingStream<ConversationResponse, Error>,
        message: String,
        mode: GrokMode,
        request: [String: AnyCodable],
        input: [String: AnyCodable]? = nil,
        debug: Bool = false,
        warnings: [String] = []
    ) async throws -> Bool {
        var sequence = 1
        var requestData: [String: AnyCodable] = [
            "message": AnyCodable(message),
            "model": AnyCodable(modeJSON(mode)),
            "request": AnyCodable(request)
        ]
        if let input {
            requestData["input"] = AnyCodable(input)
            try printJSONEvent(sequence: sequence, event: "transcription", data: AnyCodable(input))
            sequence += 1
        }
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
        let thinkingParser = GrokStreamMarkupParser()
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
                case .activity(let activity):
                    try printJSONEvent(sequence: sequence, event: "activity", data: AnyCodable([
                        "kind": AnyCodable(activity.kind.rawValue),
                        "text": AnyCodable(activity.displayText)
                    ]))
                    sequence += 1
                    try printJSONEvent(sequence: sequence, event: "trace", data: AnyCodable([
                        "kind": AnyCodable(activity.kind.rawValue),
                        "text": AnyCodable(activity.displayText)
                    ]))
                    sequence += 1
                }
            }
        }

        func emitThinkingStartIfNeeded() throws {
            if !thinkingActive {
                try printJSONEvent(sequence: sequence, event: "thinking_start", data: AnyCodable([
                    "phase": AnyCodable("thinking")
                ]))
                sequence += 1
                thinkingActive = true
            }
        }

        func emitThinkingEndIfNeeded() throws {
            if thinkingActive {
                try printJSONEvent(sequence: sequence, event: "thinking_end", data: AnyCodable([
                    "phase": AnyCodable("thinking")
                ]))
                sequence += 1
                thinkingActive = false
            }
        }

        func emitThinkingEvents(_ events: [StreamDisplayEvent]) throws {
            for event in events {
                switch event {
                case .text(let text):
                    let lines = text
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    for line in lines {
                        try emitThinkingStartIfNeeded()
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
                case .activity(let activity):
                    try printJSONEvent(sequence: sequence, event: "activity", data: AnyCodable([
                        "kind": AnyCodable(activity.kind.rawValue),
                        "text": AnyCodable(activity.displayText)
                    ]))
                    sequence += 1
                    try printJSONEvent(sequence: sequence, event: "trace", data: AnyCodable([
                        "kind": AnyCodable(activity.kind.rawValue),
                        "text": AnyCodable(activity.displayText)
                    ]))
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
                    try emitThinkingEvents(thinkingParser.finish())
                    try emitThinkingEndIfNeeded()
                    try emitDisplayEvents(answerParser.finish(), textEvent: "assistant_delta")
                    let data = assistantResponseJSON(response: response, mode: mode, request: request, input: input)
                    try printJSONEvent(sequence: sequence, event: "assistant_final", data: AnyCodable(data))
                    sequence += 1
                    try printJSONEvent(sequence: sequence, event: "done", data: AnyCodable([
                        "ok": AnyCodable(true),
                        "phase": AnyCodable("complete")
                    ]))
                    sequence += 1
                    emittedFinal = true
                    break
                } else if response.isThinking {
                    try emitThinkingEvents(thinkingParser.consume(response.message))
                } else {
                    try emitThinkingEvents(thinkingParser.finish())
                    try emitThinkingEndIfNeeded()
                    try emitDisplayEvents(answerParser.consume(response.message), textEvent: "assistant_delta")
                }
            }

            try emitThinkingEvents(thinkingParser.finish())
            try emitThinkingEndIfNeeded()
            try emitDisplayEvents(answerParser.finish(), textEvent: "assistant_delta")
            if !emittedFinal {
                try printJSONEvent(sequence: sequence, event: "done", data: AnyCodable([
                    "ok": AnyCodable(true),
                    "phase": AnyCodable("complete")
                ]))
            }
            return true
        } catch {
            try emitThinkingEndIfNeeded()
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
