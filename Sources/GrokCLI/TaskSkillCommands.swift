import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleTasksCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")

        let parsed: ParsedTaskCommand
        do {
            parsed = try parseTaskCommand(args: args)
        } catch {
            await app.handleError(error, debug: debug)
            if exitOnError {
                GrokCLI.exit(with: 2)
            }
            return
        }

        app.setDebugMode(parsed.debug)
        if case .help(let usage) = parsed.action {
            print(usage)
            return
        }

        do {
            let client = try app.initializeClient()
            switch parsed.action {
            case .list:
                let tasks = try await client.listTasks()
                if parsed.json {
                    try printPrettyJSON(tasks)
                    return
                }
                printTaskRows(tasks)

            case .create(let options):
                let task = try await client.createTask(
                    prompt: options.prompt,
                    name: options.name,
                    date: options.date,
                    time: options.time,
                    timezone: options.timezone,
                    guideline: options.guideline,
                    notificationMethod: "DEFAULT",
                    modelMode: options.modelMode,
                    notificationDeciderEnable: true,
                    metadataJsonString: "{}"
                )
                if parsed.json {
                    try printPrettyJSON(task)
                    return
                }
                print("Created task".green.bold)
                printTaskSummary(task)

            case .archive(let taskId):
                let result = try await client.archiveTask(taskId: taskId, isEnabled: false)
                if parsed.json {
                    try printPrettyJSON(result)
                    return
                }
                print("Archived task \(taskId)".green)

            case .help(_):
                return
            }
        } catch {
            await app.handleError(error, debug: debug)
            if exitOnError {
                GrokCLI.exit(with: 1)
            }
        }
    }

    static func handleSkillsCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")

        let parsed: ParsedSkillsCommand
        do {
            parsed = try parseSkillsCommand(args: args)
        } catch {
            await app.handleError(error, debug: debug)
            if exitOnError {
                GrokCLI.exit(with: 2)
            }
            return
        }

        app.setDebugMode(parsed.debug)
        if case .help(let usage) = parsed.action {
            print(usage)
            return
        }

        do {
            let client = try app.initializeClient()
            switch parsed.action {
            case .list:
                let skills = try await client.listSkills(locale: "en")
                if parsed.json {
                    try printPrettyJSON(skills)
                    return
                }
                printSkillRows(title: "Skills", skills: skills)

            case .user:
                let skills = try await client.listUserSkills()
                if parsed.json {
                    try printPrettyJSON(skills)
                    return
                }
                printSkillRows(title: "My Skills", skills: skills)

            case .help(_):
                return
            }
        } catch {
            await app.handleError(error, debug: debug)
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

    enum SkillsAction {
        case list
        case user
        case help(String)
    }

    struct ParsedSkillsCommand {
        let action: SkillsAction
        let json: Bool
        let debug: Bool
    }

    struct RowColumn {
        let label: String
        let keys: [String]
    }

    static func parseTaskCommand(args: [String]) throws -> ParsedTaskCommand {
        var remaining = args
        let json = removeFlag("--json", from: &remaining)
        let debug = removeFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedTaskCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskListUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok tasks list [--json] [--debug]")
            }
            return ParsedTaskCommand(action: .list, json: json, debug: debug)

        case "archive":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedTaskCommand(action: .help(taskArchiveUsage), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError("Usage: grok tasks archive <taskId> [--json] [--debug]")
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

    static func parseSkillsCommand(args: [String]) throws -> ParsedSkillsCommand {
        var remaining = args
        let json = removeFlag("--json", from: &remaining)
        let debug = removeFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedSkillsCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedSkillsCommand(action: .help(skillsListUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok skills list [--json] [--debug]")
            }
            return ParsedSkillsCommand(action: .list, json: json, debug: debug)

        case "mine", "user":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedSkillsCommand(action: .help(command == "mine" ? skillsMineUsage : skillsUserUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok skills \(command) [--json] [--debug]")
            }
            return ParsedSkillsCommand(action: .user, json: json, debug: debug)

        case "help", "-h", "--help":
            return ParsedSkillsCommand(action: .help(skillsUsage), json: json, debug: debug)

        default:
            throw GrokError.apiError("Unknown skills command: \(command)\n\(skillsUsage)")
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

            switch optionNameAndValue(arg) {
            case ("--prompt", let inlineValue):
                (prompt, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--prompt")
            case ("--name", let inlineValue):
                (name, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--name")
            case ("--date", let inlineValue):
                (date, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--date")
            case ("--time", let inlineValue):
                (time, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--time")
            case ("--timezone", let inlineValue):
                (timezone, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--timezone")
            case ("--guideline", let inlineValue):
                (guideline, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--guideline")
            case ("--model-mode", let inlineValue):
                (modelMode, index) = try readOptionValue(inlineValue, args: args, index: index, option: "--model-mode")
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

    static func removeFlag(_ flag: String, from args: inout [String]) -> Bool {
        let originalCount = args.count
        args.removeAll { $0 == flag }
        return args.count != originalCount
    }

    static func optionNameAndValue(_ arg: String) -> (String, String?) {
        guard let separator = arg.firstIndex(of: "=") else {
            return (arg, nil)
        }
        return (String(arg[..<separator]), String(arg[arg.index(after: separator)...]))
    }

    static func readOptionValue(
        _ inlineValue: String?,
        args: [String],
        index: Int,
        option: String
    ) throws -> (String, Int) {
        if let inlineValue {
            guard !inlineValue.isEmpty else {
                throw GrokError.apiError("\(option) requires a value")
            }
            return (inlineValue, index)
        }

        let nextIndex = index + 1
        guard nextIndex < args.count, !args[nextIndex].hasPrefix("--") else {
            throw GrokError.apiError("\(option) requires a value")
        }
        return (args[nextIndex], nextIndex)
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

    static func printPrettyJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
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

    static func printSkillRows(title: String, skills: [GrokSkill]) {
        guard !skills.isEmpty else {
            print("No skills found.".yellow)
            return
        }

        print("\(title):".cyan.bold)
        for skill in skills {
            printSkillSummary(skill)
        }
    }

    static func printSkillSummary(_ skill: GrokSkill) {
        let raw = jsonDictionary(from: skill)
        let id = skill.skillId ?? skill.id ?? stringValue(in: raw, keys: ["skillId", "id"])
        let name = skill.name ?? skill.title ?? stringValue(in: raw, keys: ["displayName", "name", "title"])
        let status = stringValue(in: raw, keys: ["status", "state"])
        let description = stringValue(in: raw, keys: ["description", "summary"])

        printLabeledParts([
            ("ID", id),
            ("Name", name),
            ("Status", status),
            ("Description", description)
        ])
    }

    static func printLabeledParts(_ parts: [(String, String?)]) {
        let text = parts.compactMap { label, value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return "\(label): \(value)"
        }

        print(text.isEmpty ? "(no summary available)" : text.joined(separator: " | "))
    }

    static func jsonDictionary<T: Encodable>(from value: T) -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
            if let value = dictionary[key] as? CustomStringConvertible {
                return value.description
            }
        }
        return nil
    }

    static func boolValue(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }
        return nil
    }

    static func enabledStatus(_ isEnabled: Bool?) -> String? {
        guard let isEnabled else {
            return nil
        }
        return isEnabled ? "enabled" : "archived"
    }

    static func scheduleValue(in dictionary: [String: Any]) -> String? {
        if let value = stringValue(in: dictionary, keys: ["schedule", "scheduledTime", "scheduledAt"]) {
            return value
        }

        let schedule = dictionary["schedule"] as? [String: Any] ?? dictionary
        let day = stringValue(in: schedule, keys: ["dayOfYear", "date"])
        let time = stringValue(in: schedule, keys: ["timeOfDay", "time"])
        let timezone = stringValue(in: schedule, keys: ["timezone", "timeZone"])

        let joined = [day, time, timezone].compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    static func printRows<T>(
        title: String,
        values: [T],
        emptyMessage: String,
        columns: [RowColumn]
    ) {
        guard !values.isEmpty else {
            print(emptyMessage.yellow)
            return
        }

        print("\(title):".cyan.bold)
        for value in values {
            printSummary(value: value, columns: columns)
        }
    }

    static func printSummary<T>(value: T, columns: [RowColumn]) {
        let parts = columns.compactMap { column -> String? in
            guard let content = firstMirrorValue(for: column.keys, in: value) else {
                return nil
            }
            return "\(column.label): \(content)"
        }

        if parts.isEmpty {
            print(String(describing: value))
        } else {
            print(parts.joined(separator: " | "))
        }
    }

    static func firstMirrorValue<T>(for keys: [String], in value: T) -> String? {
        let fields = flattenedMirrorFields(value)
        for key in keys {
            if let value = fields[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func flattenedMirrorFields<T>(_ value: T) -> [String: String] {
        var fields: [String: String] = [:]
        collectMirrorFields(value, into: &fields, depth: 0)
        return fields
    }

    static func collectMirrorFields(_ value: Any, into fields: inout [String: String], depth: Int) {
        guard depth < 2 else {
            return
        }

        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            guard let label = child.label else {
                continue
            }

            if let text = displayValue(child.value), fields[label] == nil {
                fields[label] = text
            } else {
                collectMirrorFields(child.value, into: &fields, depth: depth + 1)
            }
        }
    }

    static func displayValue(_ value: Any) -> String? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else {
                return nil
            }
            return displayValue(child.value)
        }

        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        default:
            return nil
        }
    }

    static var taskUsage: String {
        """
        Tasks:
          grok tasks list [--json]
          grok tasks create --prompt <text> [--name <name>] [--date YYYY-MM-DD] [--time HH:mm] [--timezone TZ] [--guideline <text>] [--model-mode BASE] [--json]
          grok tasks archive <taskId> [--json]
        """
    }

    static var taskCreateUsage: String {
        "Usage: grok tasks create --prompt <text> [--name <name>] [--date YYYY-MM-DD] [--time HH:mm] [--timezone TZ] [--guideline <text>] [--model-mode BASE] [--json]"
    }

    static var taskListUsage: String {
        "Usage: grok tasks list [--json] [--debug]"
    }

    static var taskArchiveUsage: String {
        "Usage: grok tasks archive <taskId> [--json] [--debug]"
    }

    static var skillsUsage: String {
        """
        Skills:
          grok skills list [--json]
          grok skills mine [--json]
          grok skills user [--json]
        """
    }

    static var skillsListUsage: String {
        "Usage: grok skills list [--json] [--debug]"
    }

    static var skillsMineUsage: String {
        "Usage: grok skills mine [--json] [--debug]"
    }

    static var skillsUserUsage: String {
        "Usage: grok skills user [--json] [--debug]"
    }
}
