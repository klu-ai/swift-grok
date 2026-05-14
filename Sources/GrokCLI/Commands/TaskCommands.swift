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
                let tasks = response.tasks
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
                guard let task = selectTask(from: response.tasks) else {
                    return
                }
                let latestResult = try await latestResult(for: task, client: client)
                printTaskDetail(task, latestResult: latestResult)

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

            case .results(let taskId):
                let result = try await client.latestTaskResult(taskId: taskId)
                if parsed.json {
                    var data: [String: AnyCodable] = [
                        "resource": AnyCodable("task_result"),
                        "taskId": AnyCodable(taskId)
                    ]
                    if let result {
                        data["latestResult"] = AnyCodable(taskResultJSON(result))
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
                printTaskResult(GrokTask(taskId: taskId), result: result)

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
        guard let selected = selectTask(from: response.tasks) else {
            return
        }
        let latestResult = try await latestResult(for: selected, client: client)
        printTaskDetail(selected, latestResult: latestResult)
        _ = debug
    }

    static func selectTask(from tasks: [GrokTask]) -> GrokTask? {
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
                subtitle: [enabledStatus(task.isEnabled ?? boolValue(in: raw, keys: ["isEnabled"])), scheduleValue(in: raw)]
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

}

private extension GrokCLI {
    enum TaskAction {
        case list
        case inactive
        case select
        case show(String)
        case results(String)
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
            guard remaining.count == 2 else {
                throw GrokError.apiError(taskResultsUsage)
            }
            return ParsedTaskCommand(action: .results(remaining[1]), json: json, debug: debug)

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

    static func taskStatus(_ task: GrokTask) -> String? {
        let raw = jsonDictionary(from: task)
        return compactStatus(
            stringValue(in: raw, keys: ["status", "state"])
                ?? enabledStatus(task.isEnabled ?? boolValue(in: raw, keys: ["isEnabled"]))
        )
    }

    static func taskSchedule(_ task: GrokTask) -> String? {
        let raw = jsonDictionary(from: task)
        return scheduleValue(in: raw)
    }

    static func task(matching taskId: String, in tasks: [GrokTask]) throws -> GrokTask {
        if let task = tasks.first(where: { taskIdentifier($0) == taskId }) {
            return task
        }
        throw GrokError.apiError("Task not found: \(taskId)")
    }

    static func latestResult(for task: GrokTask, client: GrokClient) async throws -> GrokTaskResult? {
        guard let taskId = taskIdentifier(task) else {
            return nil
        }
        return try await client.latestTaskResult(taskId: taskId)
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
          grok tasks results <taskId> [--json|--format json]
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
        "Usage: grok tasks results <taskId> [--json|--format json] [--debug]"
    }

    static var taskArchiveUsage: String {
        "Usage: grok tasks archive <taskId> [--json|--format json] [--debug]"
    }

}
