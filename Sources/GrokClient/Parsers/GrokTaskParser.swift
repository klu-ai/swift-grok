import Foundation

internal enum GrokTaskParser {
    internal static func makeTask(
        from dictionary: [String: Any],
        defaultIsEnabled: Bool? = nil
    ) -> GrokTask {
        makeTask(from: JSONLookup(dictionary), defaultIsEnabled: defaultIsEnabled)
    }

    internal static func makeTask(
        from dictionary: [String: AnyCodable],
        defaultIsEnabled: Bool? = nil
    ) -> GrokTask {
        makeTask(from: JSONLookup(dictionary), defaultIsEnabled: defaultIsEnabled)
    }

    internal static func makeTasksResponse(
        from json: Any,
        defaultIsEnabled: Bool? = nil
    ) -> GrokTasksResponse {
        let activeTasks = allDictionaries(from: json, keys: activeTaskKeys)
            .map { makeTask(from: $0, defaultIsEnabled: true) }
        let inactiveTasks = allDictionaries(from: json, keys: inactiveTaskKeys)
            .map { makeTask(from: $0, defaultIsEnabled: false) }

        let tasks: [GrokTask]
        if activeTasks.isEmpty && inactiveTasks.isEmpty {
            tasks = dictionaries(from: json, preferredKeys: generalTaskKeys)
                .map { makeTask(from: $0, defaultIsEnabled: defaultIsEnabled) }
        } else {
            tasks = activeTasks + inactiveTasks
        }

        return GrokTasksResponse(
            tasks: tasks,
            activeTasks: activeTasks,
            inactiveTasks: inactiveTasks,
            rawJSON: AnyCodable(json)
        )
    }

    internal static func makeTaskResult(from dictionary: [String: Any]) -> GrokTaskResult {
        makeTaskResult(from: JSONLookup(dictionary))
    }

    internal static func makeTaskResult(from dictionary: [String: AnyCodable]) -> GrokTaskResult {
        makeTaskResult(from: JSONLookup(dictionary))
    }

    internal static func makeTaskResultsResponse(from json: Any) -> GrokTaskResultsResponse {
        let resultDictionaries = dictionaries(from: json, preferredKeys: taskResultKeys)
        let results: [GrokTaskResult]
        if !resultDictionaries.isEmpty {
            results = resultDictionaries.map { makeTaskResult(from: $0) }
        } else if let dictionary = firstTaskResultDictionary(in: json) {
            results = [makeTaskResult(from: dictionary)]
        } else {
            results = []
        }

        return GrokTaskResultsResponse(results: results, rawJSON: AnyCodable(json))
    }

    private static let activeTaskKeys = [
        "activeTasks",
        "active_tasks",
        "enabledTasks",
        "enabled_tasks",
        "active",
        "enabled"
    ]

    private static let inactiveTaskKeys = [
        "inactiveTasks",
        "inactive_tasks",
        "archivedTasks",
        "archived_tasks",
        "disabledTasks",
        "disabled_tasks",
        "inactive",
        "archived",
        "disabled"
    ]

    private static let generalTaskKeys = [
        "tasks",
        "taskList",
        "task_list",
        "data",
        "result",
        "items",
        "values"
    ]

    private static let taskWrapperKeys = [
        "task",
        "taskData",
        "task_data"
    ]

    private static let taskResultKeys = [
        "results",
        "taskResults",
        "task_results",
        "data",
        "result",
        "items",
        "values"
    ]

    private static let taskResultWrapperKeys = taskResultKeys + [
        "taskResult",
        "task_result",
        "latestResult",
        "latest_result",
        "lastResult",
        "last_result",
        "response",
        "modelResponse",
        "model_response"
    ]

    private static let taskEnabledKeys = [
        "isEnabled",
        "is_enabled",
        "isActive",
        "is_active",
        "enabled",
        "active"
    ]

    private static func makeTask(
        from lookup: JSONLookup,
        defaultIsEnabled: Bool? = nil
    ) -> GrokTask {
        let taskDictionary = firstDictionary(from: lookup, preferredKeys: taskWrapperKeys)
        var rawJSON = taskDictionary ?? rawDictionary(from: lookup)
        if let schedule = firstScheduleDictionary(from: lookup) {
            copyTaskScheduleFields(from: schedule, into: &rawJSON)
            if !containsAnyValue(rawJSON, keys: taskEnabledKeys),
               boolValue(schedule, keys: ["isEnabled", "is_enabled", "enabled"]) == true {
                rawJSON["isEnabled"] = AnyCodable(true)
            }
        }
        if !containsAnyValue(rawJSON, keys: taskEnabledKeys),
           let defaultIsEnabled {
            rawJSON["isEnabled"] = AnyCodable(defaultIsEnabled)
        }

        let rawLookup = JSONLookup(rawJSON)
        return GrokTask(
            taskId: rawLookup.string("taskId", "task_id"),
            id: rawLookup.string("id"),
            name: rawLookup.string("name", "title", "displayName", "display_name"),
            prompt: rawLookup.string([
                "prompt",
                "taskPrompt",
                "task_prompt",
                "description",
                "summary",
                "query",
                "instructions"
            ]),
            isEnabled: boolValue(rawJSON, keys: taskEnabledKeys),
            status: rawLookup.string("status", "state"),
            rawJSON: rawJSON
        )
    }

    private static func makeTaskResult(from lookup: JSONLookup) -> GrokTaskResult {
        let rawJSON = rawDictionary(from: lookup)
        let rawLookup = JSONLookup(rawJSON)
        return GrokTaskResult(
            resultId: rawLookup.string("taskResultId", "task_result_id", "resultId", "result_id"),
            id: rawLookup.string("id"),
            taskId: rawLookup.string("taskId", "task_id"),
            conversationId: rawLookup.string("conversationId", "conversation_id"),
            responseId: rawLookup.string("responseId", "response_id"),
            message: taskResultMessage(from: lookup) ??
                rawLookup.string("summary", "message", "content", "output", "text", "result"),
            status: rawLookup.string("status", "state"),
            rawJSON: rawJSON
        )
    }

    private static func firstScheduleDictionary(from lookup: JSONLookup) -> [String: AnyCodable]? {
        guard let dictionary = rawDictionaryIfPresent(from: lookup) else {
            return nil
        }

        if let schedule = dictionary["schedule"]?.value,
           let scheduleDictionary = Self.dictionary(from: schedule) {
            return scheduleDictionary
        }

        if let schedules = dictionary["schedules"]?.value,
           let scheduleArray = array(from: schedules) {
            return scheduleArray.compactMap { Self.dictionary(from: $0) }.first
        }

        return nil
    }

    private static func copyTaskScheduleFields(
        from schedule: [String: AnyCodable],
        into rawJSON: inout [String: AnyCodable]
    ) {
        for key in ["scheduleId", "schedule_id"] {
            guard rawJSON["scheduleId"] == nil, let value = schedule[key] else {
                continue
            }
            rawJSON["scheduleId"] = value
            break
        }
        for key in ["dayOfYear", "date", "timeOfDay", "time", "timezone", "timeZone", "nextRun"] {
            guard rawJSON[key] == nil, let value = schedule[key] else {
                continue
            }
            rawJSON[key] = value
        }
        for key in ["isEnabled", "is_enabled", "enabled"] {
            guard let value = schedule[key] else {
                continue
            }
            rawJSON["scheduleIsEnabled"] = value
            break
        }
    }

    private static func firstTaskResultDictionary(in value: Any) -> [String: AnyCodable]? {
        if let array = array(from: value) {
            for item in array {
                if let dictionary = firstTaskResultDictionary(in: item) {
                    return dictionary
                }
            }
            return nil
        }

        guard let dictionary = dictionary(from: value) else {
            return nil
        }

        if isTaskResultDictionary(dictionary) {
            return dictionary
        }

        for key in taskResultWrapperKeys {
            if let nested = dictionary[key]?.value,
               let result = firstTaskResultDictionary(in: nested) {
                return result
            }
        }

        return nil
    }

    private static func isTaskResultDictionary(_ dictionary: [String: AnyCodable]) -> Bool {
        containsAnyValue(dictionary, keys: [
            "taskResultId",
            "task_result_id",
            "resultId",
            "result_id",
            "id",
            "taskId",
            "task_id",
            "conversationId",
            "conversation_id",
            "responseId",
            "response_id",
            "summary",
            "message",
            "content",
            "output",
            "text"
        ])
    }

    private static func taskResultMessage(from lookup: JSONLookup) -> String? {
        if let direct = lookup.string("summary", "message", "content", "output", "text", "result") {
            return direct
        }

        guard let dictionary = rawDictionaryIfPresent(from: lookup) else {
            return nil
        }

        for key in ["result", "response", "modelResponse", "model_response", "conversation"] {
            if let value = dictionary[key]?.value,
               let nested = Self.dictionary(from: value),
               let text = taskResultMessage(from: JSONLookup(nested)) {
                return text
            }
        }

        for key in ["messages", "responses", "contents", "parts"] {
            guard let nested = dictionary[key]?.value else {
                continue
            }

            if let array = array(from: nested) {
                for item in array {
                    if let nestedDictionary = Self.dictionary(from: item),
                       let text = taskResultMessage(from: JSONLookup(nestedDictionary)) {
                        return text
                    }
                    if let text = item as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
        }

        return nil
    }

    private static func dictionaries(
        from value: Any,
        preferredKeys: [String]
    ) -> [[String: AnyCodable]] {
        if let array = array(from: value) {
            return array.compactMap { dictionary(from: $0) }
        }

        guard let dictionary = dictionary(from: value) else {
            return []
        }

        for key in preferredKeys {
            guard let nested = dictionary[key]?.value else {
                continue
            }

            if let array = array(from: nested) {
                let dictionaries = array.compactMap { Self.dictionary(from: $0) }
                if !dictionaries.isEmpty {
                    return dictionaries
                }
            }

            let nestedDictionaries = dictionaries(from: nested, preferredKeys: preferredKeys)
            if !nestedDictionaries.isEmpty {
                return nestedDictionaries
            }
        }

        return []
    }

    private static func allDictionaries(
        from value: Any,
        keys: [String]
    ) -> [[String: AnyCodable]] {
        if let array = array(from: value) {
            return array.flatMap { allDictionaries(from: $0, keys: keys) }
        }

        guard let dictionary = dictionary(from: value) else {
            return []
        }

        var results: [[String: AnyCodable]] = []
        for (key, nested) in dictionary {
            if keys.contains(key) {
                results.append(contentsOf: directTaskDictionaries(from: nested.value))
            } else {
                results.append(contentsOf: allDictionaries(from: nested.value, keys: keys))
            }
        }
        return results
    }

    private static func directTaskDictionaries(from value: Any) -> [[String: AnyCodable]] {
        if let array = array(from: value) {
            return array.flatMap { directTaskDictionaries(from: $0) }
        }

        guard let dictionary = dictionary(from: value) else {
            return []
        }

        let nested = dictionaries(from: dictionary, preferredKeys: generalTaskKeys + taskWrapperKeys)
        return nested.isEmpty ? [dictionary] : nested
    }

    private static func firstDictionary(
        from lookup: JSONLookup,
        preferredKeys: [String]
    ) -> [String: AnyCodable]? {
        for key in preferredKeys {
            if let dictionary = lookup.firstDictionary(key) {
                return dictionary
            }
        }

        return rawDictionaryIfPresent(from: lookup)
    }

    private static func dictionary(from value: Any) -> [String: AnyCodable]? {
        (JSONLookup(value).rawAnyCodable.value as? [String: AnyCodable])
    }

    private static func array(from value: Any) -> [Any]? {
        switch JSONLookup(value).rawAnyCodable.value {
        case let array as [AnyCodable]:
            return array.map(\.value)
        case let array as [Any]:
            return array
        default:
            return nil
        }
    }

    private static func rawDictionary(from lookup: JSONLookup) -> [String: AnyCodable] {
        rawDictionaryIfPresent(from: lookup) ?? [:]
    }

    private static func rawDictionaryIfPresent(from lookup: JSONLookup) -> [String: AnyCodable]? {
        lookup.rawAnyCodable.value as? [String: AnyCodable]
    }

    private static func containsAnyValue(
        _ dictionary: [String: AnyCodable],
        keys: [String]
    ) -> Bool {
        keys.contains { dictionary[$0] != nil }
    }

    private static func boolValue(
        _ dictionary: [String: AnyCodable],
        keys: [String]
    ) -> Bool? {
        for key in keys {
            if let value = dictionary[key]?.value as? Bool {
                return value
            }
        }
        return nil
    }
}

internal extension GrokClient {
    func makeTaskParserTask(
        from dictionary: [String: Any],
        defaultIsEnabled: Bool? = nil
    ) -> GrokTask {
        GrokTaskParser.makeTask(from: dictionary, defaultIsEnabled: defaultIsEnabled)
    }

    func makeTaskParserTask(
        from dictionary: [String: AnyCodable],
        defaultIsEnabled: Bool? = nil
    ) -> GrokTask {
        GrokTaskParser.makeTask(from: dictionary, defaultIsEnabled: defaultIsEnabled)
    }

    func makeTaskParserTasksResponse(
        from json: Any,
        defaultIsEnabled: Bool? = nil
    ) -> GrokTasksResponse {
        GrokTaskParser.makeTasksResponse(from: json, defaultIsEnabled: defaultIsEnabled)
    }

    func makeTaskParserTaskResult(from dictionary: [String: Any]) -> GrokTaskResult {
        GrokTaskParser.makeTaskResult(from: dictionary)
    }

    func makeTaskParserTaskResult(from dictionary: [String: AnyCodable]) -> GrokTaskResult {
        GrokTaskParser.makeTaskResult(from: dictionary)
    }

    func makeTaskParserTaskResultsResponse(from json: Any) -> GrokTaskResultsResponse {
        GrokTaskParser.makeTaskResultsResponse(from: json)
    }
}
