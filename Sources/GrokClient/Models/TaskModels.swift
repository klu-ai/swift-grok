import Foundation

public struct GrokTaskSchedule: Codable {
    public let taskCadence: String
    public let isEnabled: Bool
    public let timezone: String
    public let timeOfDay: String
    public let dayOfYear: String

    public init(
        taskCadence: String = "TASK_CADENCE_ONCE",
        isEnabled: Bool = true,
        timezone: String,
        timeOfDay: String,
        dayOfYear: String
    ) {
        self.taskCadence = taskCadence
        self.isEnabled = isEnabled
        self.timezone = timezone
        self.timeOfDay = timeOfDay
        self.dayOfYear = dayOfYear
    }
}

public struct GrokTask: Codable {
    public let taskId: String?
    public let id: String?
    public let name: String?
    public let prompt: String?
    public let isEnabled: Bool?
    public let status: String?
    public let rawJSON: [String: AnyCodable]

    public var resolvedId: String? {
        taskId ?? id
    }

    public init(
        taskId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        prompt: String? = nil,
        isEnabled: Bool? = nil,
        status: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.taskId = taskId
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.status = status
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.taskId = rawJSON["taskId"]?.value as? String ?? rawJSON["task_id"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.name = Self.stringValue(rawJSON, keys: ["name", "title", "displayName", "display_name"])
        self.prompt = Self.stringValue(rawJSON, keys: [
            "prompt",
            "taskPrompt",
            "task_prompt",
            "description",
            "summary",
            "query",
            "instructions"
        ])
        self.isEnabled = Self.boolValue(rawJSON, keys: ["isEnabled", "is_enabled", "isActive", "is_active", "enabled", "active"])
        self.status = rawJSON["status"]?.value as? String ?? rawJSON["state"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }

    private static func stringValue(_ dictionary: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key]?.value as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func boolValue(_ dictionary: [String: AnyCodable], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key]?.value as? Bool {
                return value
            }
            if let value = dictionary[key]?.value as? Int {
                return value != 0
            }
            if let value = dictionary[key]?.value as? String {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1", "enabled", "active":
                    return true
                case "false", "no", "0", "disabled", "inactive", "archived":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }
}

public struct GrokSkill: Codable {
    public let skillId: String?
    public let id: String?
    public let name: String?
    public let title: String?
    public let rawJSON: [String: AnyCodable]

    public init(
        skillId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        title: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.skillId = skillId
        self.id = id
        self.name = name
        self.title = title
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.skillId = rawJSON["skillId"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.name = rawJSON["name"]?.value as? String
        self.title = rawJSON["title"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }
}

public struct GrokTasksResponse: Codable {
    public let tasks: [GrokTask]
    public let activeTasks: [GrokTask]
    public let inactiveTasks: [GrokTask]
    public let rawJSON: AnyCodable

    public init(
        tasks: [GrokTask],
        activeTasks: [GrokTask] = [],
        inactiveTasks: [GrokTask] = [],
        rawJSON: AnyCodable
    ) {
        self.tasks = tasks
        self.activeTasks = activeTasks
        self.inactiveTasks = inactiveTasks
        self.rawJSON = rawJSON
    }
}

public struct GrokTaskMutationResponse: Codable {
    public let task: GrokTask?
    public let rawJSON: AnyCodable
}

public struct GrokTaskResult: Codable {
    public let resultId: String?
    public let id: String?
    public let taskId: String?
    public let conversationId: String?
    public let responseId: String?
    public let message: String?
    public let status: String?
    public let rawJSON: [String: AnyCodable]

    public var resolvedId: String? {
        resultId ?? id
    }

    public init(
        resultId: String? = nil,
        id: String? = nil,
        taskId: String? = nil,
        conversationId: String? = nil,
        responseId: String? = nil,
        message: String? = nil,
        status: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.resultId = resultId
        self.id = id
        self.taskId = taskId
        self.conversationId = conversationId
        self.responseId = responseId
        self.message = message
        self.status = status
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.resultId = Self.stringValue(rawJSON, keys: ["taskResultId", "task_result_id", "resultId", "result_id"])
        self.id = Self.stringValue(rawJSON, keys: ["id"])
        self.taskId = Self.stringValue(rawJSON, keys: ["taskId", "task_id"])
        self.conversationId = Self.stringValue(rawJSON, keys: ["conversationId", "conversation_id"])
        self.responseId = Self.stringValue(rawJSON, keys: ["responseId", "response_id"])
        self.message = Self.stringValue(rawJSON, keys: ["summary", "message", "content", "output", "text", "result"])
        self.status = Self.stringValue(rawJSON, keys: ["status", "state"])
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }

    private static func stringValue(_ dictionary: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key]?.value as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public struct GrokTaskResultsResponse: Codable {
    public let results: [GrokTaskResult]
    public let rawJSON: AnyCodable

    public init(results: [GrokTaskResult], rawJSON: AnyCodable) {
        self.results = results
        self.rawJSON = rawJSON
    }
}

public struct GrokSkillsResponse: Codable {
    public let skills: [GrokSkill]
    public let rawJSON: AnyCodable
}

public struct GrokAgentCustomization: Codable {
    public let agentId: Int
    public let name: String
    public let instructions: String

    public init(agentId: Int, name: String, instructions: String) {
        self.agentId = agentId
        self.name = agentId == 0 ? "Grok" : name
        self.instructions = instructions
    }

    public static func defaultName(for agentId: Int) -> String {
        switch agentId {
        case 0:
            return "Grok"
        case 1:
            return "Grok II"
        case 2:
            return "Grok III"
        case 3:
            return "Grok IV"
        default:
            return "Agent \(agentId)"
        }
    }
}

public struct GrokAgentCustomizationsResponse: Codable {
    public let agentCustomizations: [GrokAgentCustomization]
    public let rawJSON: AnyCodable
}
