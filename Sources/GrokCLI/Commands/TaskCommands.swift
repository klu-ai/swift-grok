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

}

private extension GrokCLI {
    enum TaskAction {
        case list
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
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok tasks list [--json|--format json] [--debug]")
            }
            return ParsedTaskCommand(action: .list, json: json, debug: debug)

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

        print("Tasks:".cyan.bold)
        for task in tasks {
            printTaskSummary(task)
        }
    }

    static func printTaskSummary(_ task: GrokTask) {
        let raw = jsonDictionary(from: task)
        let id = task.taskId ?? task.id ?? stringValue(in: raw, keys: ["taskId", "id"])
        let title = task.name ?? stringValue(in: raw, keys: ["title", "name"]) ?? task.prompt
        let status = stringValue(in: raw, keys: ["status", "state"])
            ?? enabledStatus(task.isEnabled ?? boolValue(in: raw, keys: ["isEnabled"]))
        let schedule = scheduleValue(in: raw)

        printLabeledParts([
            ("ID", id),
            ("Title", title),
            ("Status", status),
            ("Schedule", schedule)
        ])
    }

    static var taskUsage: String {
        """
        Tasks:
          grok tasks list [--json|--format json]
          grok tasks create --prompt <text> [--name <name>] [--date YYYY-MM-DD] [--time HH:mm] [--timezone TZ] [--guideline <text>] [--model-mode BASE] [--json|--format json]
          grok tasks archive <taskId> [--json|--format json]
        """
    }

    static var taskCreateUsage: String {
        "Usage: grok tasks create --prompt <text> [--name <name>] [--date YYYY-MM-DD] [--time HH:mm] [--timezone TZ] [--guideline <text>] [--model-mode BASE] [--json|--format json]"
    }

    static var taskListUsage: String {
        "Usage: grok tasks list [--json|--format json] [--debug]"
    }

    static var taskArchiveUsage: String {
        "Usage: grok tasks archive <taskId> [--json|--format json] [--debug]"
    }

}
