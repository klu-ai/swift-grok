import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleCodeCommand(args: [String], exitOnError: Bool = false) async throws {
        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printCodeUsage()
            return
        }

        do {
            let invocation = try parseCodeInvocation(args)
            try await runCodeInvocation(invocation)
        } catch let error as GrokCodeUsageError {
            reportCodeUsageError(
                error.message,
                jsonRequested: isCodeJSONRequested(args),
                exitOnError: exitOnError
            )
            if exitOnError {
                exit(with: 2)
            }
        } catch {
            if isCodeJSONRequested(args) {
                printJSONError(command: "code", error: error, exitCode: 1)
            } else {
                print("Error: \(error.localizedDescription)".red)
            }
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    static func parseCodeInvocation(_ args: [String]) throws -> GrokCodeInvocation {
        var options = GrokCodeOptions()
        var taskWords: [String] = []

        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil

            let modelOption = applyModelOption(arg, nextValue: nextValue)
            if modelOption.missingValue {
                throw GrokCodeUsageError("\(arg) requires a model value")
            } else if let mode = modelOption.mode {
                options.requestedModel = mode
                index += modelOption.consumedNext ? 2 : 1
                continue
            }

            if let parsed = try parseCodeOutputFormat(arg, nextValue: nextValue) {
                options.outputFormat = parsed.format
                index += parsed.consumedNext ? 2 : 1
                continue
            }

            if arg == "--private" {
                options.privateMode = true
            } else if arg == "--prompt-file" {
                options.promptFile = try requireValue(nextValue, option: arg)
                index += 1
            } else if arg.hasPrefix("--prompt-file=") {
                options.promptFile = try requireInlineValue(arg, prefix: "--prompt-file=", option: "--prompt-file")
            } else if arg == "--permission-mode" {
                let value = try requireValue(nextValue, option: arg)
                guard let mode = GrokCodePermissionMode.resolve(value) else {
                    throw GrokCodeUsageError("--permission-mode requires one of: \(GrokCodePermissionMode.codeUsageValues)")
                }
                options.permissionMode = mode
                index += 1
            } else if arg.hasPrefix("--permission-mode=") {
                let value = try requireInlineValue(arg, prefix: "--permission-mode=", option: "--permission-mode")
                guard let mode = GrokCodePermissionMode.resolve(value) else {
                    throw GrokCodeUsageError("--permission-mode requires one of: \(GrokCodePermissionMode.codeUsageValues)")
                }
                options.permissionMode = mode
            } else if arg == "--max-turns" {
                options.maxTurns = try parsePositiveInteger(try requireValue(nextValue, option: arg), option: arg)
                index += 1
            } else if arg.hasPrefix("--max-turns=") {
                options.maxTurns = try parsePositiveInteger(
                    try requireInlineValue(arg, prefix: "--max-turns=", option: "--max-turns"),
                    option: "--max-turns"
                )
            } else if arg == "--tools" {
                options.allowedTools = try parseCSV(try requireValue(nextValue, option: arg), option: arg)
                index += 1
            } else if arg.hasPrefix("--tools=") {
                options.allowedTools = try parseCSV(
                    try requireInlineValue(arg, prefix: "--tools=", option: "--tools"),
                    option: "--tools"
                )
            } else if arg == "--disallowed-tools" {
                options.disallowedTools = try parseCSV(try requireValue(nextValue, option: arg), option: arg)
                index += 1
            } else if arg.hasPrefix("--disallowed-tools=") {
                options.disallowedTools = try parseCSV(
                    try requireInlineValue(arg, prefix: "--disallowed-tools=", option: "--disallowed-tools"),
                    option: "--disallowed-tools"
                )
            } else if arg == "--rules" {
                options.rules.append(try parseRulesValue(try requireValue(nextValue, option: arg)))
                index += 1
            } else if arg.hasPrefix("--rules=") {
                options.rules.append(try parseRulesValue(
                    try requireInlineValue(arg, prefix: "--rules=", option: "--rules")
                ))
            } else if arg == "--cwd" {
                options.cwd = try resolveCodeCWD(try requireValue(nextValue, option: arg))
                index += 1
            } else if arg.hasPrefix("--cwd=") {
                options.cwd = try resolveCodeCWD(
                    try requireInlineValue(arg, prefix: "--cwd=", option: "--cwd")
                )
            } else if arg.hasPrefix("-") {
                throw GrokCodeUsageError("Unknown code option: \(arg)")
            } else {
                taskWords.append(arg)
            }

            index += 1
        }

        let inlineTask = taskWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let fileTask = try options.promptFile.map { try readPromptFile($0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if fileTask != nil, !inlineTask.isEmpty {
            throw GrokCodeUsageError("Use either --prompt-file or inline task args, not both")
        }

        return .run(options: options, task: (fileTask ?? inlineTask).nilIfBlank)
    }

    private static func runCodeInvocation(_ invocation: GrokCodeInvocation) async throws {
        switch invocation {
        case .run(var options, let task):
            let app = GrokCLIApp.shared
            let credential: XAIOAuthCredential
            do {
                credential = try await app.validXAIOAuthCredential()
            } catch GrokError.invalidCredentials {
                throw GrokCodeUsageError("Grok Code requires saved xAI OAuth credentials. Run `grok auth oauth` and retry.")
            }
            options.resolvedModel = try await resolveCodeModel(options: options, app: app)

            let toolRegistry = GrokCodeSession.makeToolRegistry(options: options)
            let agent = GrokCodeOAuthResponsesAgent(
                credential: credential,
                client: try XAIOAuthClient(),
                executor: GrokCodeToolExecutor(registry: toolRegistry),
                context: GrokCodeToolUseContext(
                    workingDirectory: options.cwd,
                    permissionMode: options.permissionMode
                )
            )
            let session = GrokCodeSession(
                options: options,
                agent: agent,
                toolRegistry: toolRegistry
            )
            let state = try await session.run(task: task)
            try printCodeState(state, task: task)
        }
    }

    private static func resolveCodeModel(options: GrokCodeOptions, app: GrokCLIApp) async throws -> GrokMode {
        if let requested = options.requestedModel {
            return await app.resolveXAIOAuthModel(requested)
        }

        let modelIDs = await app.loadXAIOAuthModelIDsIfAvailable()
        guard let resolved = GrokCodeModelResolver.resolveDefault(from: modelIDs) else {
            throw GrokCodeUsageError("Grok Code could not find a grok-build model from xAI OAuth /v1/models. Pass --model explicitly or run `grok auth oauth`.")
        }
        return resolved
    }

    private static func printCodeState(_ state: GrokCodeSessionState, task: String?) throws {
        switch state.options.outputFormat {
        case .json:
            var data = state.json
            if let task {
                data["task"] = AnyCodable(task)
            }
            try printJSONResult(command: "code", category: "code_session", data: AnyCodable(data))
        case .streamingJSON:
            for event in state.events {
                try printJSONEvent(
                    sequence: event.sequence,
                    event: event.kind.rawValue,
                    data: AnyCodable([
                        "message": AnyCodable(event.message),
                        "metadata": AnyCodable(event.metadata)
                    ])
                )
            }
            if let finalAnswer = state.finalAnswer {
                try printJSONEvent(
                    sequence: state.events.count + 1,
                    event: "final_answer",
                    data: AnyCodable(["text": AnyCodable(finalAnswer)])
                )
            }
        case .markdown, .raw:
            print("Grok Code".green.bold)
            print("model \(state.model.id) | permission \(state.options.permissionMode.codeRawValue) | format \(state.options.outputFormat.statusName)")
            print("cwd \(state.cwd.path)")
            if let task {
                print("task: \(String(task.prefix(240)))")
            }
            let warnings = state.events
                .filter { $0.kind == .warning }
                .map(\.message)
            for warning in Array(Set(warnings)).sorted() {
                print(warning.yellow)
            }
            if let failureMessage = state.failureMessage {
                print(failureMessage.red)
            }
            if let answer = state.finalAnswer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("")
                OutputFormatter(format: state.options.outputFormat.outputFormatterFormat).printQuietResponseBody(answer)
            }
            if let transcriptPath = state.transcriptPath {
                print("transcript: \(transcriptPath)")
            }
        }
    }

    static func reportCodeUsageError(_ message: String, jsonRequested: Bool, exitOnError _: Bool) {
        if jsonRequested {
            printJSONError(
                command: "code",
                message: message,
                code: "usage_error",
                exitCode: 2
            )
        } else {
            print("Error: \(message)".red)
        }
    }

    private static func parseCodeOutputFormat(
        _ arg: String,
        nextValue: String?
    ) throws -> (format: GrokCodeOutputFormat, consumedNext: Bool)? {
        switch arg {
        case "--json":
            return (.json, false)
        case "--raw":
            return (.raw, false)
        case "--markdown", "-m":
            return (.markdown, false)
        case "--format":
            guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrokCodeUsageError("--format requires a format value")
            }
            guard let format = GrokCodeOutputFormat.resolve(nextValue) else {
                throw GrokCodeUsageError("Invalid output format '\(nextValue)'. Use md, raw, json, or streaming-json.")
            }
            return (format, true)
        default:
            guard arg.hasPrefix("--format=") else {
                return nil
            }
            let value = String(arg.dropFirst("--format=".count))
            guard !value.isEmpty else {
                throw GrokCodeUsageError("--format requires a format value")
            }
            guard let format = GrokCodeOutputFormat.resolve(value) else {
                throw GrokCodeUsageError("Invalid output format '\(value)'. Use md, raw, json, or streaming-json.")
            }
            return (format, false)
        }
    }

    private static func isCodeJSONRequested(_ args: [String]) -> Bool {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                return true
            }
            if arg.hasPrefix("--format="),
               let format = GrokCodeOutputFormat.resolve(String(arg.dropFirst("--format=".count))),
               format.isJSONLike {
                return true
            }
            if arg == "--format",
               index + 1 < args.count,
               let format = GrokCodeOutputFormat.resolve(args[index + 1]),
               format.isJSONLike {
                return true
            }
            index += 1
        }
        return false
    }

    private static func requireValue(_ value: String?, option: String) throws -> String {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.hasPrefix("--") else {
            throw GrokCodeUsageError("\(option) requires a value")
        }
        return value
    }

    private static func requireInlineValue(_ arg: String, prefix: String, option: String) throws -> String {
        let value = String(arg.dropFirst(prefix.count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokCodeUsageError("\(option) requires a value")
        }
        return value
    }

    private static func parsePositiveInteger(_ value: String, option: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw GrokCodeUsageError("\(option) requires a positive integer")
        }
        return parsed
    }

    private static func parseCSV(_ value: String, option: String) throws -> [String] {
        let values = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw GrokCodeUsageError("\(option) requires at least one comma-separated tool name")
        }
        return values
    }

    private static func parseRulesValue(_ value: String) throws -> String {
        if value.hasPrefix("@") {
            let path = String(value.dropFirst())
            guard !path.isEmpty else {
                throw GrokCodeUsageError("--rules @file requires a path after @")
            }
            return try readPromptFile(path).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func resolveCodeCWD(_ value: String) throws -> URL {
        let expanded = NSString(string: value).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GrokCodeUsageError("--cwd must point to an existing directory")
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
