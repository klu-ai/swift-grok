import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleTasksCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")
        let jsonRequested = isJSONRequested(args)

        let parsed: ParsedTaskCommand
        do {
            parsed = try parseTaskCommand(args: args)
        } catch {
            if jsonRequested {
                printJSONError(command: "tasks", error: error, exitCode: 2, debug: debug)
            } else {
                await app.handleError(error, debug: debug)
            }
            if exitOnError {
                GrokCLI.exit(with: 2)
            }
            return
        }

        app.setDebugMode(parsed.debug && !parsed.json)
        if case .help(let usage) = parsed.action {
            print(usage)
            return
        }

        do {
            let client = try app.initializeClient()
            switch parsed.action {
            case .list:
                let response = try await client.listTasksResponse()
                let tasks = displayOrderedTasks(response.tasks)
                if parsed.json {
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "list",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "task",
                            items: tasks.map { AnyCodable(taskJSON($0)) },
                            raw: response.rawJSON
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                printTaskRows(tasks)

            case .inactive:
                let response = try await client.listInactiveTasksResponse()
                let tasks = response.tasks
                if parsed.json {
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "inactive",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "task",
                            items: tasks.map { AnyCodable(taskJSON($0)) }
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                printTaskRows(tasks)

            case .select:
                let response = try await client.listTasksResponse()
                try await runTaskSelectionFlow(tasks: displayOrderedTasks(response.tasks), client: client, app: app)

            case .show(let taskId):
                let response = try await client.listTasksResponse()
                let task = try task(matching: taskId, in: response.tasks)
                let latestResult = try await latestResult(for: task, client: client)
                if parsed.json {
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "show",
                        category: "resource_detail",
                        data: AnyCodable([
                            "resource": AnyCodable("task"),
                            "item": AnyCodable(taskDetailJSON(task, latestResult: latestResult))
                        ] as [String: AnyCodable]),
                        debug: parsed.debug
                    )
                    return
                }
                printTaskDetail(task, latestResult: latestResult)

            case .results(let options):
                let resolved = try await resolveTaskReference(options.taskId, client: client)
                let taskId = resolved.taskId
                let results = try await client.taskResults(taskId: taskId, limit: options.limit)
                let result = results.first
                if parsed.json {
                    var data: [String: AnyCodable] = [
                        "resource": AnyCodable("task_result"),
                        "taskId": AnyCodable(taskId),
                        "limit": AnyCodable(options.limit)
                    ]
                    if let task = resolved.task {
                        data["task"] = AnyCodable(taskJSON(task))
                    }
                    if let result {
                        data["latestResult"] = AnyCodable(taskResultJSON(result))
                    }
                    if options.limit > 1 {
                        data["results"] = AnyCodable(results.map { AnyCodable(taskResultJSON($0)) })
                    }
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "results",
                        category: "resource_detail",
                        data: AnyCodable(data),
                        debug: parsed.debug
                    )
                    return
                }
                if options.limit <= 1 {
                    printTaskResult(GrokTask(taskId: taskId), result: result)
                } else {
                    printTaskRuns(results, taskId: taskId)
                }

            case .chat(let options):
                let resolved = try await resolveTaskReference(options.taskId, client: client)
                let runs = try await taskRunContexts(
                    task: resolved.task,
                    taskId: resolved.taskId,
                    client: client,
                    limit: options.limit
                )
                let run = try selectRun(from: runs, selector: options.runSelector)
                let prepared = try await prepareTaskRunChat(run, client: client, app: app)

                if parsed.json {
                    var data: [String: AnyCodable] = [
                        "taskId": AnyCodable(resolved.taskId),
                        "run": AnyCodable(taskRunJSON(prepared.run)),
                        "conversationId": AnyCodable(prepared.conversationId),
                        "parentResponseId": AnyCodable(prepared.parentResponseId)
                    ]
                    if let resultResponseId = prepared.resultResponseId {
                        data["resultResponseId"] = AnyCodable(resultResponseId)
                    }
                    if let message = options.message {
                        let response = try await sendTaskRunMessage(message, app: app, mode: options.mode)
                        data["response"] = AnyCodable(assistantResponseJSON(
                            response: response,
                            mode: options.mode,
                            request: messageRequestJSON(
                                reasoning: true,
                                deepSearch: false,
                                noSearch: false,
                                privateMode: false,
                                stream: false,
                                workspaceIds: app.getCurrentWorkspaceIds(),
                                fileAttachmentIds: []
                            )
                        ))
                    }
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "chat",
                        category: "assistant_response",
                        data: AnyCodable(data),
                        debug: parsed.debug
                    )
                    return
                }

                printTaskRunLoaded(prepared, includePreview: false)
                if let message = options.message {
                    let response = try await sendTaskRunMessage(message, app: app, mode: options.mode)
                    OutputFormatter(format: .markdown).printResponse(
                        response.message,
                        conversationId: app.getCurrentConversationId(),
                        responseId: app.getLastResponseId(),
                        debug: parsed.debug,
                        webSearchResults: response.webSearchResults,
                        xposts: response.xposts
                    )
                }

            case .create(let options):
                let schedule = GrokTaskSchedule(
                    taskCadence: "TASK_CADENCE_ONCE",
                    isEnabled: true,
                    timezone: options.timezone,
                    timeOfDay: options.time,
                    dayOfYear: options.date
                )
                let result = try await client.createTask(
                    name: options.name ?? "",
                    prompt: options.prompt,
                    metadataJsonString: "{}",
                    schedule: schedule,
                    notificationMethod: "DEFAULT",
                    modelMode: options.modelMode,
                    notificationDeciderEnable: true,
                    notificationDeciderGuideline: options.guideline ?? "only notify if it's economically valuable"
                )
                let task = result.task ?? GrokTask(rawJSON: ["response": result.rawJSON])
                if parsed.json {
                    let id = task.taskId ?? task.id
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "create",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "task",
                            action: "create",
                            id: id,
                            item: AnyCodable(taskJSON(task)),
                            raw: result.rawJSON
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Created task".green.bold)
                printTaskSummary(task)

            case .archive(let taskId):
                let result = try await client.archiveTask(taskId: taskId, isEnabled: false)
                if parsed.json {
                    try printJSONResult(
                        command: "tasks",
                        subcommand: "archive",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "task",
                            action: "archive",
                            id: taskId,
                            item: result.task.map { AnyCodable(taskJSON($0)) },
                            raw: result.rawJSON
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Archived task \(taskId)".green)

            case .help(_):
                return
            }
        } catch {
            if parsed.json {
                printJSONError(command: "tasks", error: error, exitCode: 1, debug: parsed.debug)
            } else {
                await app.handleError(error, debug: debug)
            }
            if exitOnError {
                GrokCLI.exit(with: 1)
            }
        }
    }

    static func handleInteractiveTasksCommand(args: [String], debug: Bool) async throws {
        guard args.isEmpty else {
            try await handleTasksCommand(args: args)
            return
        }

        let app = GrokCLIApp.shared
        let client = try app.initializeClient()
        let response = try await client.listTasksResponse()
        try await runTaskSelectionFlow(tasks: displayOrderedTasks(response.tasks), client: client, app: app)
        _ = debug
    }

    static func selectTask(from tasks: [GrokTask]) -> GrokTask? {
        let tasks = displayOrderedTasks(tasks)
        guard !tasks.isEmpty else {
            print("No tasks found.".yellow)
            return nil
        }

        let items = tasks.map { task in
            let raw = jsonDictionary(from: task)
            let id = taskIdentifier(task) ?? "unknown"
            return PickerItem(
                id: id,
                title: taskTitle(task) ?? id,
                subtitle: [taskStatus(task), scheduleValue(in: raw)]
                    .compactMap { $0 }
                    .joined(separator: " | "),
                preview: latestTaskResultSummary(in: raw),
                value: task,
                searchText: [
                    id,
                    taskTitle(task),
                    task.prompt,
                    latestTaskResultSummary(in: raw)
                ].compactMap { $0 }.joined(separator: " ")
            )
        }

        return InteractivePicker.select(
            title: "Tasks:",
            items: items,
            allowsEmptySelection: false
        )
    }

    static func taskRunTimestampLabel(
        _ value: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        guard let date = parseTaskRunDate(value) else {
            return value
        }

        let exactFormatter = DateFormatter()
        exactFormatter.calendar = calendar
        exactFormatter.locale = Locale(identifier: "en_US_POSIX")
        exactFormatter.timeZone = calendar.timeZone
        exactFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let exact = exactFormatter.string(from: date)

        let dateStart = calendar.startOfDay(for: date)
        let nowStart = calendar.startOfDay(for: now)
        let dayDifference = calendar.dateComponents([.day], from: dateStart, to: nowStart).day

        let friendly: String
        if dayDifference == 0 {
            friendly = "Today"
        } else if dayDifference == 1 {
            friendly = "Yesterday"
        } else if let days = dayDifference,
                  days > 1,
                  days <= 7 {
            friendly = "Last week"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d"
            friendly = formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d, yyyy"
            friendly = formatter.string(from: date)
        }

        return "\(friendly) (\(exact))"
    }

    private static func parseTaskRunDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

}

private extension GrokCLI {
    enum TaskAction {
        case list
        case inactive
        case select
        case show(String)
        case results(TaskResultsOptions)
        case chat(TaskChatOptions)
        case create(TaskCreateOptions)
        case archive(String)
        case help(String)
    }

    struct ParsedTaskCommand {
        let action: TaskAction
        let json: Bool
        let debug: Bool
    }

    struct TaskCreateOptions {
        let prompt: String
        let name: String?
        let date: String
        let time: String
        let timezone: String
        let guideline: String?
        let modelMode: String
    }

    struct TaskResultsOptions {
        let taskId: String
        let limit: Int
    }

    struct TaskChatOptions {
        let taskId: String
        let runSelector: TaskRunSelector
        let limit: Int
        let message: String?
        let mode: GrokMode
    }

    enum TaskRunSelector: Equatable {
        case latest
        case previous
        case resultId(String)
        case ordinal(Int)
    }

    struct ResolvedTaskReference {
        let taskId: String
        let task: GrokTask?
    }

    struct TaskRunContext {
        let taskId: String
        let taskTitle: String?
        let result: GrokTaskResult
        let index: Int
        let total: Int
        let timestamp: String?
        let timestampLabel: String?

        var resultId: String? {
            result.resolvedId
        }

        var conversationId: String? {
            result.conversationId ?? GrokCLI.stringValue(in: GrokCLI.jsonDictionary(from: result), keys: ["conversationId", "conversation_id"])
        }

        var resultResponseId: String? {
            result.responseId ?? GrokCLI.stringValue(in: GrokCLI.jsonDictionary(from: result), keys: ["responseId", "response_id"])
        }

        var title: String {
            let ordinal = GrokCLI.runOrdinalLabel(index: index)
            if let timestampLabel {
                return "\(ordinal)  \(timestampLabel)"
            }
            return ordinal
        }

        var summary: String {
            GrokCLI.taskResultDisplayText(result)
        }
    }

    struct PreparedTaskRunChat {
        let run: TaskRunContext
        let conversationId: String
        let parentResponseId: String
        let resultResponseId: String?
        let loadedResponses: [Response]
    }

    enum TaskDetailAction {
        case backToTasks
        case showLatest
        case showRuns
        case openLatest
        case done
    }

    enum TaskRunViewerDecision {
        case open(PreparedTaskRunChat)
        case back
    }

    enum TaskRunViewerMode {
        case latest
        case choose
    }

    enum TaskRunMenuAction {
        case open
        case back
    }

    static func parseTaskCommand(args: [String]) throws -> ParsedTaskCommand {
        var remaining = args
        let json = try CLIOptionParsing.removeJSONOutputOptions(from: &remaining)
        let debug = CLIOptionParsing.removeFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedTaskCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskListUsage), json: json, debug: debug)
            }
            let listArgs = Array(remaining.dropFirst())
            if listArgs == ["--inactive"] || listArgs == ["--archived"] {
                return ParsedTaskCommand(action: .inactive, json: json, debug: debug)
            }
            guard listArgs.isEmpty else {
                throw GrokError.apiError("Usage: grok tasks list [--json|--format json] [--debug]")
            }
            return ParsedTaskCommand(action: .list, json: json, debug: debug)

        case "inactive", "archived":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskInactiveUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError(taskInactiveUsage)
            }
            return ParsedTaskCommand(action: .inactive, json: json, debug: debug)

        case "select":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskSelectUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError(taskSelectUsage)
            }
            return ParsedTaskCommand(action: .select, json: json, debug: debug)

        case "show", "details", "detail":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskShowUsage), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError(taskShowUsage)
            }
            return ParsedTaskCommand(action: .show(remaining[1]), json: json, debug: debug)

        case "results", "result":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskResultsUsage), json: json, debug: debug)
            }
            let options = try parseTaskResultsOptions(args: Array(remaining.dropFirst()))
            return ParsedTaskCommand(action: .results(options), json: json, debug: debug)

        case "chat", "thread", "open":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskChatUsage), json: json, debug: debug)
            }
            let options = try parseTaskChatOptions(args: Array(remaining.dropFirst()))
            return ParsedTaskCommand(action: .chat(options), json: json, debug: debug)

        case "archive":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskArchiveUsage), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError("Usage: grok tasks archive <taskId> [--json|--format json] [--debug]")
            }
            return ParsedTaskCommand(action: .archive(remaining[1]), json: json, debug: debug)

        case "create":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskCreateUsage), json: json, debug: debug)
            }
            let options = try parseTaskCreateOptions(args: Array(remaining.dropFirst()))
            return ParsedTaskCommand(action: .create(options), json: json, debug: debug)

        case "help", "-h", "--help":
            return ParsedTaskCommand(action: .help(taskUsage), json: json, debug: debug)

        default:
            throw GrokError.apiError("Unknown tasks command: \(command)\n\(taskUsage)")
        }
    }

    static func parseTaskCreateOptions(args: [String]) throws -> TaskCreateOptions {
        var prompt: String?
        var name: String?
        var date: String?
        var time: String?
        var timezone: String?
        var guideline: String?
        var modelMode = "BASE"

        var index = 0
        while index < args.count {
            let arg = args[index]

            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--prompt", let inlineValue):
                (prompt, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--prompt")
            case ("--name", let inlineValue):
                (name, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--name")
            case ("--date", let inlineValue):
                (date, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--date")
            case ("--time", let inlineValue):
                (time, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--time")
            case ("--timezone", let inlineValue):
                (timezone, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--timezone")
            case ("--guideline", let inlineValue):
                (guideline, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--guideline")
            case ("--model-mode", let inlineValue):
                (modelMode, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--model-mode")
            default:
                throw GrokError.apiError("Unknown option for tasks create: \(arg)\n\(taskCreateUsage)")
            }

            index += 1
        }

        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("Missing required option: --prompt <text>\n\(taskCreateUsage)")
        }

        let resolvedTimezone = timezone ?? "Asia/Bangkok"
        return TaskCreateOptions(
            prompt: prompt,
            name: name,
            date: date ?? currentDateString(timezone: resolvedTimezone),
            time: time ?? currentTimeString(timezone: resolvedTimezone),
            timezone: resolvedTimezone,
            guideline: guideline,
            modelMode: modelMode
        )
    }

    static func parseTaskResultsOptions(args: [String]) throws -> TaskResultsOptions {
        var remaining = args
        let limit = try removeLimitOption(from: &remaining, defaultValue: 1)
        guard remaining.count == 1 else {
            throw GrokError.apiError(taskResultsUsage)
        }
        return TaskResultsOptions(taskId: remaining[0], limit: limit)
    }

    static func parseTaskChatOptions(args: [String]) throws -> TaskChatOptions {
        var taskId: String?
        var runSelector = TaskRunSelector.latest
        var limit = 10
        var message: String?
        var messageWords: [String] = []
        var selectedMode = GrokMode.defaultMode

        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil
            let modelOption = applyModelOption(arg, nextValue: nextValue)
            if modelOption.missingValue {
                throw GrokError.apiError("\(arg) requires a model value")
            }
            if let mode = modelOption.mode {
                selectedMode = mode
                index += modelOption.consumedNext ? 2 : 1
                continue
            }

            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--run", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--run")
                runSelector = parseTaskRunSelector(value)
            case ("--result-id", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--result-id")
                runSelector = .resultId(value)
            case ("--run-index", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--run-index")
                guard let ordinal = Int(value), ordinal > 0 else {
                    throw GrokError.apiError("--run-index must be a positive integer")
                }
                runSelector = .ordinal(ordinal - 1)
            case ("--limit", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--limit")
                limit = try parsePositiveLimit(value)
            case ("--message", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--message")
                message = value
            default:
                if arg.hasPrefix("--") {
                    throw GrokError.apiError("Unknown option for tasks chat: \(arg)\n\(taskChatUsage)")
                }
                if taskId == nil {
                    taskId = arg
                } else {
                    messageWords.append(arg)
                }
            }

            index += 1
        }

        if message == nil, !messageWords.isEmpty {
            message = messageWords.joined(separator: " ")
        }

        guard let taskId, !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError(taskChatUsage)
        }

        if runSelector == .previous {
            limit = max(limit, 2)
        }

        return TaskChatOptions(
            taskId: taskId,
            runSelector: runSelector,
            limit: limit,
            message: message,
            mode: selectedMode
        )
    }

    static func removeLimitOption(from args: inout [String], defaultValue: Int) throws -> Int {
        var limit = defaultValue
        var result: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--limit", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--limit")
                limit = try parsePositiveLimit(value)
                index += 1
            default:
                result.append(arg)
                index += 1
            }
        }
        args = result
        return limit
    }

    static func parsePositiveLimit(_ value: String) throws -> Int {
        guard let limit = Int(value), limit > 0 else {
            throw GrokError.apiError("--limit must be a positive integer")
        }
        return limit
    }

    static func parseTaskRunSelector(_ value: String) -> TaskRunSelector {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "", "latest", "newest":
            return .latest
        case "previous", "prev":
            return .previous
        default:
            if let ordinal = Int(trimmed), ordinal > 0 {
                return .ordinal(ordinal - 1)
            }
            return .resultId(trimmed)
        }
    }

    static func currentDateString(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "Asia/Bangkok")
        return formatter.string(from: Date())
    }

    static func currentTimeString(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "Asia/Bangkok")
        return formatter.string(from: Date())
    }

    static func printTaskRows(_ tasks: [GrokTask]) {
        let tasks = displayOrderedTasks(tasks)
        guard !tasks.isEmpty else {
            print("No tasks found.".yellow)
            return
        }

        print("Tasks".cyan.bold)
        for task in tasks {
            printTaskSummary(task)
        }
    }

    static func printTaskSummary(_ task: GrokTask) {
        let primary = [taskTitle(task), taskStatus(task), taskSchedule(task)]
            .compactMap { $0 }
            .joined(separator: "  ")
        print(primary.isEmpty ? "(no summary available)" : primary)
    }

    static func displayOrderedTasks(_ tasks: [GrokTask]) -> [GrokTask] {
        tasks.enumerated()
            .sorted { lhs, rhs in
                let lhsPaused = taskStatus(lhs.element) == "paused"
                let rhsPaused = taskStatus(rhs.element) == "paused"
                if lhsPaused != rhsPaused {
                    return !lhsPaused
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func printTaskDetail(_ task: GrokTask, latestResult: GrokTaskResult? = nil) {
        let raw = jsonDictionary(from: task)
        let heading = [taskTitle(task), taskStatus(task), taskSchedule(task)]
            .compactMap { $0 }
            .joined(separator: "  ")
        print((heading.isEmpty ? "Task" : heading).cyan.bold)

        if let prompt = taskPrompt(task) {
            print("")
            print(prompt)
        }

        if let latestResult {
            print("")
            printTaskResult(task, result: latestResult)
        } else {
            print("")
            printTaskResult(task, embeddedResult: latestTaskResult(in: raw))
        }
    }

    static func printTaskPromptDetail(_ task: GrokTask) {
        let heading = [taskTitle(task), taskStatus(task), taskSchedule(task)]
            .compactMap { $0 }
            .joined(separator: "  ")
        print((heading.isEmpty ? "Task" : heading).cyan.bold)

        if let prompt = taskPrompt(task) {
            print("")
            print(prompt)
        }
    }

    static func printTaskResult(_ task: GrokTask, result: GrokTaskResult?) {
        guard let result else {
            print("Latest run  none".yellow)
            return
        }
        printTaskResultBlock(raw: jsonDictionary(from: result), message: result.message)
    }

    static func printTaskResult(_ task: GrokTask, embeddedResult: Any?) {
        guard let embeddedResult else {
            print("Latest run  none".yellow)
            return
        }

        if let dictionary = embeddedResult as? [String: Any] {
            printTaskResultBlock(raw: dictionary, message: taskResultMessage(in: dictionary))
            return
        }

        print("Latest run".cyan.bold)
        print(taskResultDisplayText(embeddedResult))
    }

    static func printTaskRuns(_ results: [GrokTaskResult], taskId: String) {
        guard !results.isEmpty else {
            print("No task runs found for \(taskId).".yellow)
            return
        }

        print("Task runs".cyan.bold)
        for (index, result) in results.enumerated() {
            let timestamp = taskResultTimestamp(result)
            let timestampLabel = taskRunTimestampLabel(timestamp)
            let title = [runOrdinalLabel(index: index), timestampLabel, compactStatus(result.status)]
                .compactMap { $0 }
                .joined(separator: "  ")
            print(title.yellow)
            let text = (result.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                print(text)
            }
            if index != results.count - 1 {
                print("")
            }
        }
    }

    static func printTaskRunLoaded(_ prepared: PreparedTaskRunChat, includePreview: Bool = true) {
        print("Opened task run chat".green.bold)
        print(taskRunMetadata(prepared.run))
        if prepared.run.resultResponseId == nil, let resultResponseId = prepared.resultResponseId {
            print("responseId: \(resultResponseId)")
        }
        print("parentResponseId: \(prepared.parentResponseId)")
        if includePreview, let body = taskRunLoadedResponseText(prepared) {
            print("")
            OutputFormatter(format: .markdown).printQuietResponseBody(body)
            print("")
        }
        print("The next chat message will continue this task run thread.".yellow)
    }

    static func printTaskRunResult(_ prepared: PreparedTaskRunChat) {
        print("Task run".cyan.bold)
        print([prepared.run.title, prepared.run.result.status.flatMap(compactStatus)].compactMap { $0 }.joined(separator: "  "))
        guard let body = taskRunLoadedResponseText(prepared) else {
            print("")
            print("No loaded response body was available for this run.".yellow)
            return
        }
        print("")
        OutputFormatter(format: .markdown).printQuietResponseBody(body)
        print("")
    }

    static func taskRunLoadedResponseText(_ prepared: PreparedTaskRunChat) -> String? {
        let preferred = prepared.resultResponseId ?? prepared.run.resultResponseId
        let response = preferred.flatMap { responseId in
            prepared.loadedResponses.first(where: { $0.responseId == responseId })
        } ?? (preferred == nil ? prepared.loadedResponses.last : nil)
        guard let message = response?.message.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            let message = prepared.run.result.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            return message?.isEmpty == false ? message : nil
        }
        return GrokStreamMarkupParser.visibleText(from: message)
    }

    static func taskDetailJSON(_ task: GrokTask, latestResult: GrokTaskResult? = nil) -> [String: AnyCodable] {
        var data = taskJSON(task)
        let raw = jsonDictionary(from: task)
        if let title = taskTitle(task) {
            data["title"] = AnyCodable(title)
        }
        if let latestResult {
            data["latestResult"] = AnyCodable(taskResultJSON(latestResult))
        } else if let latest = latestTaskResult(in: raw) {
            data["latestResult"] = AnyCodable(latest)
        }
        return data
    }

    static func taskRunJSON(_ run: TaskRunContext) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "taskId": AnyCodable(run.taskId),
            "index": AnyCodable(run.index),
            "ordinal": AnyCodable(runOrdinalLabel(index: run.index)),
            "result": AnyCodable(taskResultJSON(run.result))
        ]
        if let taskTitle = run.taskTitle {
            data["taskTitle"] = AnyCodable(taskTitle)
        }
        if let timestamp = run.timestamp {
            data["timestamp"] = AnyCodable(timestamp)
        }
        if let timestampLabel = run.timestampLabel {
            data["timestampLabel"] = AnyCodable(timestampLabel)
        }
        if let conversationId = run.conversationId {
            data["conversationId"] = AnyCodable(conversationId)
        }
        if let responseId = run.resultResponseId {
            data["responseId"] = AnyCodable(responseId)
        }
        return data
    }

    static func taskIdentifier(_ task: GrokTask) -> String? {
        let raw = jsonDictionary(from: task)
        return task.taskId ?? task.id ?? stringValue(in: raw, keys: ["taskId", "task_id", "id"])
    }

    static func taskTitle(_ task: GrokTask) -> String? {
        let raw = jsonDictionary(from: task)
        return task.name
            ?? stringValue(in: raw, keys: ["title", "name", "displayName"])
            ?? task.prompt
            ?? stringValue(in: raw, keys: ["prompt", "taskPrompt", "description", "summary"])
    }

    static func taskPrompt(_ task: GrokTask) -> String? {
        let raw = jsonDictionary(from: task)
        let prompt = task.prompt
            ?? stringValue(in: raw, keys: ["prompt", "taskPrompt", "task_prompt", "description", "summary", "query", "instructions"])
        guard let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
            return nil
        }
        return prompt
    }

    static func taskSchedule(_ task: GrokTask) -> String? {
        let raw = jsonDictionary(from: task)
        return scheduleValue(in: raw)
    }

    static func taskResultTimestamp(_ result: GrokTaskResult) -> String? {
        let raw = jsonDictionary(from: result)
        return stringValue(in: raw, keys: [
            "createTime",
            "createdAt",
            "created_at",
            "completedAt",
            "completed_at",
            "lastRunAt",
            "last_run_at",
            "runAt",
            "run_at",
            "timestamp"
        ])
    }

    static func runOrdinalLabel(index: Int) -> String {
        switch index {
        case 0:
            return "latest"
        case 1:
            return "previous"
        default:
            return "\(index + 1) runs back"
        }
    }

    static func taskRunMetadata(_ run: TaskRunContext) -> String {
        [
            "run: \(run.title)",
            run.resultId.map { "resultId: \($0)" },
            run.conversationId.map { "conversationId: \($0)" },
            run.resultResponseId.map { "responseId: \($0)" },
            run.result.status.flatMap(compactStatus).map { "status: \($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    static func task(matching taskId: String, in tasks: [GrokTask]) throws -> GrokTask {
        let normalized = taskId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let task = tasks.first(where: {
            taskIdentifier($0) == taskId ||
                taskTitle($0)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }) {
            return task
        }
        throw GrokError.apiError("Task not found: \(taskId)")
    }

    static func resolveTaskReference(_ reference: String, client: GrokClient) async throws -> ResolvedTaskReference {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = try await client.listTasksResponse()
        if let task = try? task(matching: trimmed, in: response.tasks),
           let taskId = taskIdentifier(task) {
            return ResolvedTaskReference(taskId: taskId, task: task)
        }
        return ResolvedTaskReference(taskId: trimmed, task: nil)
    }

    static func latestResult(for task: GrokTask, client: GrokClient) async throws -> GrokTaskResult? {
        guard let taskId = taskIdentifier(task) else {
            return nil
        }
        return try await client.latestTaskResult(taskId: taskId)
    }

    static func taskRunContexts(
        task: GrokTask?,
        taskId: String,
        client: GrokClient,
        limit: Int
    ) async throws -> [TaskRunContext] {
        let results = try await client.taskResults(taskId: taskId, limit: limit)
        guard !results.isEmpty else {
            throw GrokError.apiError("No task runs found for \(taskTitle(task ?? GrokTask(taskId: taskId)) ?? taskId)")
        }

        return results.enumerated().map { index, result in
            let timestamp = taskResultTimestamp(result)
            return TaskRunContext(
                taskId: taskId,
                taskTitle: task.flatMap { taskTitle($0) },
                result: result,
                index: index,
                total: results.count,
                timestamp: timestamp,
                timestampLabel: taskRunTimestampLabel(timestamp)
            )
        }
    }

    static func selectRun(from runs: [TaskRunContext], selector: TaskRunSelector) throws -> TaskRunContext {
        guard !runs.isEmpty else {
            throw GrokError.apiError("No task runs found")
        }

        switch selector {
        case .latest:
            return runs[0]
        case .previous:
            guard runs.indices.contains(1) else {
                throw GrokError.apiError("No previous task run found")
            }
            return runs[1]
        case .ordinal(let index):
            guard runs.indices.contains(index) else {
                throw GrokError.apiError("Task run index \(index + 1) is outside the \(runs.count) loaded runs")
            }
            return runs[index]
        case .resultId(let id):
            let needle = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if let run = runs.first(where: {
                $0.resultId == needle ||
                    $0.resultResponseId == needle ||
                    stringValue(in: jsonDictionary(from: $0.result), keys: ["responseId", "response_id", "id"]) == needle
            }) {
                return run
            }
            throw GrokError.apiError("Task run not found: \(id)")
        }
    }

    static func loadTaskRunChatContext(
        _ run: TaskRunContext,
        client: GrokClient
    ) async throws -> PreparedTaskRunChat {
        guard let conversationId = run.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !conversationId.isEmpty else {
            throw GrokError.apiError("Task run is missing conversationId")
        }

        _ = try await client.getConversationV2(
            conversationId: conversationId,
            includeWorkspaces: true,
            includeTaskResult: true
        )

        let nodes = (try? await client.getResponseNodes(conversationId: conversationId, includeThreads: true)) ?? []
        let inferredPair = inferredRunResponsePair(nodes: nodes)
        let resultResponseId = run.resultResponseId ?? inferredPair.resultResponseId
        let parentResponseId = resultResponseId
            ?? selectedRunParentResponseId(run)
            ?? inferredPair.parentResponseId
        let responseIds = uniqueResponseIds([resultResponseId, inferredPair.secondaryResponseId, parentResponseId])
        let loadedResponses = responseIds.isEmpty
            ? []
            : try await client.loadResponses(conversationId: conversationId, specificResponseIds: responseIds)

        let resolvedParent = parentResponseId
            ?? loadedResponses.first(where: { $0.responseId == resultResponseId })?.parentResponseId
            ?? resultResponseId

        guard let resolvedParent, !resolvedParent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("Task run is missing responseId")
        }

        return PreparedTaskRunChat(
            run: run,
            conversationId: conversationId,
            parentResponseId: resolvedParent,
            resultResponseId: resultResponseId,
            loadedResponses: loadedResponses
        )
    }

    static func prepareTaskRunChat(
        _ run: TaskRunContext,
        client: GrokClient,
        app: GrokCLIApp
    ) async throws -> PreparedTaskRunChat {
        let prepared = try await loadTaskRunChatContext(run, client: client)
        seedTaskRunChat(prepared, app: app)
        return prepared
    }

    static func seedTaskRunChat(_ prepared: PreparedTaskRunChat, app: GrokCLIApp) {
        app.seedConversation(
            conversationId: prepared.conversationId,
            title: prepared.run.taskTitle ?? prepared.run.taskId,
            parentResponseId: prepared.parentResponseId
        )
    }

    static func selectedRunParentResponseId(
        _ run: TaskRunContext
    ) -> String? {
        let raw = jsonDictionary(from: run.result)
        return stringValue(in: raw, keys: [
            "parentResponseId",
            "parent_response_id",
            "threadParentResponseId",
            "thread_parent_response_id"
        ])
    }

    static func inferredRunResponsePair(nodes: [ResponseNode]) -> (parentResponseId: String?, resultResponseId: String?, secondaryResponseId: String?) {
        guard !nodes.isEmpty else {
            return (nil, nil, nil)
        }

        let result = nodes.first { node in
            let sender = node.sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return sender == "assistant" || sender == "grok" || sender == "model"
        }?.responseId ?? nodes.last?.responseId
        let secondary = nodes.first { $0.responseId != result }?.responseId
        return (result, result, secondary)
    }

    static func uniqueResponseIds(_ ids: [String?]) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for id in ids {
            guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            guard seen.insert(trimmed).inserted else {
                continue
            }
            values.append(trimmed)
        }
        return values
    }

    static func sendTaskRunMessage(
        _ message: String,
        app: GrokCLIApp,
        mode: GrokMode
    ) async throws -> ConversationResponse {
        let stream = try await app.msg(
            message: message,
            mode: mode,
            workspaceIds: app.getCurrentWorkspaceIds(),
            streamOutput: false
        )
        guard let response = try await finalResponse(from: stream) else {
            throw GrokError.streamingError
        }
        return response
    }

    static func runTaskSelectionFlow(
        tasks: [GrokTask],
        client: GrokClient,
        app: GrokCLIApp
    ) async throws {
        var currentTasks = tasks
        while true {
            guard let task = selectTask(from: currentTasks) else {
                return
            }
            let shouldReturnToTasks = try await runTaskDetailFlow(task: task, client: client, app: app)
            guard shouldReturnToTasks else {
                return
            }
            currentTasks = try await client.listTasksResponse().tasks
        }
    }

    static func runTaskDetailFlow(
        task: GrokTask,
        client: GrokClient,
        app: GrokCLIApp
    ) async throws -> Bool {
        printTaskPromptDetail(task)
        let taskId = try requireTaskId(task)

        while true {
            guard let action = selectTaskDetailAction() else {
                return false
            }

            switch action {
            case .backToTasks:
                return true
            case .showLatest:
                let runs = try await taskRunContexts(task: task, taskId: taskId, client: client, limit: 1)
                if let decision = try await runTaskRunViewer(runs: runs, mode: .latest, client: client, app: app) {
                    switch decision {
                    case .open(let prepared):
                        seedTaskRunChat(prepared, app: app)
                        printTaskRunLoaded(prepared, includePreview: false)
                        return false
                    case .back:
                        continue
                    }
                }
            case .showRuns:
                let runs = try await taskRunContexts(task: task, taskId: taskId, client: client, limit: 10)
                if let decision = try await runTaskRunViewer(runs: runs, mode: .choose, client: client, app: app) {
                    switch decision {
                    case .open(let prepared):
                        seedTaskRunChat(prepared, app: app)
                        printTaskRunLoaded(prepared, includePreview: false)
                        return false
                    case .back:
                        continue
                    }
                }
            case .openLatest:
                let runs = try await taskRunContexts(task: task, taskId: taskId, client: client, limit: 1)
                let run = try selectRun(from: runs, selector: .latest)
                let prepared = try await prepareTaskRunChat(run, client: client, app: app)
                printTaskRunLoaded(prepared, includePreview: false)
                return false
            case .done:
                return false
            }
        }
    }

    static func selectTaskDetailAction() -> TaskDetailAction? {
        let items = [
            PickerItem(id: "latest", title: "Show latest result", value: TaskDetailAction.showLatest),
            PickerItem(id: "runs", title: "Show runs", subtitle: "Page through previous and next runs", value: TaskDetailAction.showRuns),
            PickerItem(id: "chat", title: "Open result chat", subtitle: "Use latest run", value: TaskDetailAction.openLatest),
            PickerItem(id: "back", title: "Back to tasks", value: TaskDetailAction.backToTasks),
            PickerItem(id: "done", title: "Done", value: TaskDetailAction.done)
        ]
        return InteractivePicker.select(
            title: "Task actions:",
            items: items,
            allowsEmptySelection: false
        )
    }

    static func runTaskRunViewer(
        runs: [TaskRunContext],
        mode: TaskRunViewerMode = .latest,
        client: GrokClient,
        app _: GrokCLIApp
    ) async throws -> TaskRunViewerDecision? {
        guard !runs.isEmpty else {
            print("No task runs found.".yellow)
            return .back
        }

        return try await runTaskRunMenuViewer(runs: runs, mode: mode, client: client)
    }

    static func runTaskRunMenuViewer(
        runs: [TaskRunContext],
        mode: TaskRunViewerMode,
        client: GrokClient
    ) async throws -> TaskRunViewerDecision? {
        switch mode {
        case .latest:
            let prepared = try await loadTaskRunChatContext(runs[0], client: client)
            printTaskRunResult(prepared)
            return selectTaskRunAction(backTitle: "Back").map { action in
                switch action {
                case .open:
                    return .open(prepared)
                case .back:
                    return .back
                }
            }
        case .choose:
            while true {
                guard let selected = selectRunByPicker(runs) else {
                    return .back
                }
                let prepared = try await loadTaskRunChatContext(selected, client: client)
                printTaskRunResult(prepared)
                switch selectTaskRunAction(backTitle: "Back to runs") {
                case .open:
                    return .open(prepared)
                case .back:
                    continue
                case nil:
                    return .back
                }
            }
        }
    }

    static func selectTaskRunAction(backTitle: String) -> TaskRunMenuAction? {
        let items = [
            PickerItem(id: "open", title: "Open chat", value: TaskRunMenuAction.open),
            PickerItem(id: "back", title: backTitle, value: TaskRunMenuAction.back)
        ]
        return InteractivePicker.select(title: "Task run actions:", items: items, allowsEmptySelection: false)
    }

    static func selectRunByPicker(_ runs: [TaskRunContext]) -> TaskRunContext? {
        let items = runs.map { run in
            PickerItem(
                id: run.resultId ?? run.resultResponseId ?? String(run.index),
                title: run.title,
                subtitle: run.result.status.flatMap(compactStatus),
                metadataLabel: "run",
                metadata: taskRunMetadata(run),
                previewLabel: "result",
                preview: run.result.message,
                value: run,
                searchText: [run.title, run.resultId, run.resultResponseId, run.summary].compactMap { $0 }.joined(separator: " ")
            )
        }
        return InteractivePicker.select(title: "Task runs:", items: items, allowsEmptySelection: false)
    }

    static func requireTaskId(_ task: GrokTask) throws -> String {
        guard let taskId = taskIdentifier(task) else {
            throw GrokError.apiError("Task is missing taskId")
        }
        return taskId
    }

    static func latestTaskResult(in raw: [String: Any]) -> Any? {
        for key in ["latestResult", "latest_result", "lastResult", "last_result", "taskResult", "task_result", "result"] {
            if let value = raw[key] {
                return value
            }
        }
        for key in ["results", "taskResults", "task_results", "runs"] {
            if let values = raw[key] as? [Any], let latest = values.last {
                return latest
            }
        }
        return nil
    }

    static func latestTaskResultSummary(in raw: [String: Any]) -> String? {
        latestTaskResult(in: raw).map(taskResultDisplayText)
    }

    static func printTaskResultBlock(raw: [String: Any], message: String?) {
        let summary = [
            "Latest run",
            compactStatus(stringValue(in: raw, keys: ["status", "state"])),
            compactTimestamp(stringValue(in: raw, keys: ["createTime", "createdAt", "created_at", "completedAt", "completed_at", "lastRunAt", "last_run_at"]))
        ].compactMap { $0 }.joined(separator: "  ")
        print(summary.isEmpty ? "Latest run".cyan.bold : summary.cyan.bold)

        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            print(message)
        }
    }

    static func taskResultMessage(in dictionary: [String: Any]) -> String? {
        stringValue(in: dictionary, keys: ["summary", "message", "text", "content", "output", "result"])
    }

    static func taskResultDisplayText(_ result: Any) -> String {
        if let text = result as? String {
            return text
        }
        if let dictionary = result as? [String: Any] {
            if let text = taskResultMessage(in: dictionary) {
                return text
            }
            let summary = [
                compactStatus(stringValue(in: dictionary, keys: ["status", "state"])),
                compactTimestamp(stringValue(in: dictionary, keys: ["createTime", "createdAt", "created_at", "completedAt", "completed_at", "lastRunAt", "last_run_at"]))
            ].compactMap { $0 }.joined(separator: "  ")
            if !summary.isEmpty {
                return summary
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: result)
    }

    static func taskResultDisplayText(_ result: GrokTaskResult) -> String {
        if let message = result.message, !message.isEmpty {
            return message
        }

        let raw = jsonDictionary(from: result)
        return taskResultDisplayText(raw)
    }

    static func compactStatus(_ value: String?) -> String? {
        guard var status = value?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty else {
            return nil
        }
        for prefix in ["TASK_RESULT_", "TASK_", "RESULT_"] {
            if status.uppercased().hasPrefix(prefix) {
                status.removeFirst(prefix.count)
                break
            }
        }
        return status.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    static func compactTimestamp(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let tIndex = value.firstIndex(of: "T") {
            let date = String(value[..<tIndex])
            let timeStart = value.index(after: tIndex)
            let timeRemainder = value[timeStart...]
            let hourMinute = timeRemainder.prefix(5)
            if hourMinute.count == 5 {
                return "\(date) \(hourMinute)"
            }
        }

        return value
    }

    static var taskUsage: String {
        """
        Tasks:
          grok tasks list [--json|--format json]
          grok tasks inactive [--json|--format json]
          grok tasks select
          grok tasks show <taskId> [--json|--format json]
          grok tasks results <taskId> [--limit N] [--json|--format json]
          grok tasks chat <taskId|taskName> [--run latest|previous|N|RESULT_ID] [--limit N] [--message <text>] [--json|--format json]
          grok tasks create --prompt <text> [--name <name>] [--date YYYY-MM-DD] [--time HH:mm] [--timezone TZ] [--guideline <text>] [--model-mode BASE] [--json|--format json]
          grok tasks archive <taskId> [--json|--format json]
        """
    }

    static var taskCreateUsage: String {
        "Usage: grok tasks create --prompt <text> [--name <name>] [--date YYYY-MM-DD] [--time HH:mm] [--timezone TZ] [--guideline <text>] [--model-mode BASE] [--json|--format json]"
    }

    static var taskListUsage: String {
        "Usage: grok tasks list [--inactive|--archived] [--json|--format json] [--debug]"
    }

    static var taskInactiveUsage: String {
        "Usage: grok tasks inactive [--json|--format json] [--debug]"
    }

    static var taskSelectUsage: String {
        "Usage: grok tasks select"
    }

    static var taskShowUsage: String {
        "Usage: grok tasks show <taskId> [--json|--format json] [--debug]"
    }

    static var taskResultsUsage: String {
        "Usage: grok tasks results <taskId> [--limit N] [--json|--format json] [--debug]"
    }

    static var taskChatUsage: String {
        "Usage: grok tasks chat <taskId|taskName> [--run latest|previous|N|RESULT_ID] [--limit N] [--message <text>] [--model MODEL] [--json|--format json] [--debug]"
    }

    static var taskArchiveUsage: String {
        "Usage: grok tasks archive <taskId> [--json|--format json] [--debug]"
    }

}
