import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleWorkspacesCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")

        let parsed: ParsedWorkspaceCommand
        do {
            parsed = try parseWorkspaceCommand(args: args)
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
                let response = try await client.listWorkspacesResponse()
                if parsed.json {
                    try printWorkspaceJSON(response.rawJSON)
                    return
                }
                printWorkspaceRows(response.workspaces)

            case .create(let options):
                let response = try await client.createWorkspace(
                    name: options.name,
                    icon: options.icon,
                    customPersonality: options.personality,
                    preferredModel: options.model
                )
                if parsed.json {
                    try printWorkspaceJSON(response.rawJSON)
                    return
                }
                print("Created workspace".green.bold)
                if let workspace = response.workspace {
                    printWorkspaceSummary(workspace)
                }

            case .addConversation(let workspaceId, let conversationId):
                let response = try await client.addConversationToWorkspace(
                    workspaceId: workspaceId,
                    conversationId: conversationId
                )
                if parsed.json {
                    try printWorkspaceJSON(response.rawJSON)
                    return
                }
                print("Added conversation \(conversationId) to workspace \(workspaceId)".green)

            case .delete(let workspaceId):
                let response = try await client.deleteWorkspace(workspaceId: workspaceId)
                if parsed.json {
                    try printWorkspaceJSON(response.rawJSON)
                    return
                }
                print("Deleted workspace \(workspaceId)".green)

            case .conversation(let conversationId):
                let response = try await client.getConversationV2(
                    conversationId: conversationId,
                    includeWorkspaces: true,
                    includeTaskResult: true
                )
                if parsed.json {
                    try printWorkspaceJSON(response.rawJSON)
                    return
                }
                printConversationV2Summary(response, fallbackId: conversationId)

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
    enum WorkspaceAction {
        case list
        case create(WorkspaceCreateOptions)
        case addConversation(workspaceId: String, conversationId: String)
        case delete(workspaceId: String)
        case conversation(conversationId: String)
        case help(String)
    }

    struct ParsedWorkspaceCommand {
        let action: WorkspaceAction
        let json: Bool
        let debug: Bool
    }

    struct WorkspaceCreateOptions {
        let name: String
        let icon: String
        let personality: String
        let model: String
    }

    static func parseWorkspaceCommand(args: [String]) throws -> ParsedWorkspaceCommand {
        var remaining = args
        let json = removeWorkspaceFlag("--json", from: &remaining)
        let debug = removeWorkspaceFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedWorkspaceCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspacesListUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok workspaces list [--json] [--debug]")
            }
            return ParsedWorkspaceCommand(action: .list, json: json, debug: debug)

        case "create":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspaceCreateUsage), json: json, debug: debug)
            }
            let options = try parseWorkspaceCreateOptions(args: Array(remaining.dropFirst()))
            return ParsedWorkspaceCommand(action: .create(options), json: json, debug: debug)

        case "add-conversation":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspacesAddConversationUsage), json: json, debug: debug)
            }
            guard remaining.count == 3 else {
                throw GrokError.apiError("Usage: grok workspaces add-conversation <workspaceId> <conversationId> [--json] [--debug]")
            }
            return ParsedWorkspaceCommand(
                action: .addConversation(workspaceId: remaining[1], conversationId: remaining[2]),
                json: json,
                debug: debug
            )

        case "delete", "remove":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspacesDeleteUsage), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError("Usage: grok workspaces delete <workspaceId> [--json] [--debug]")
            }
            return ParsedWorkspaceCommand(action: .delete(workspaceId: remaining[1]), json: json, debug: debug)

        case "conversation":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspacesConversationUsage), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError("Usage: grok workspaces conversation <conversationId> [--json] [--debug]")
            }
            return ParsedWorkspaceCommand(action: .conversation(conversationId: remaining[1]), json: json, debug: debug)

        case "help", "-h", "--help":
            return ParsedWorkspaceCommand(action: .help(workspacesUsage), json: json, debug: debug)

        default:
            throw GrokError.apiError("Unknown workspaces command: \(command)\n\(workspacesUsage)")
        }
    }

    static func parseWorkspaceCreateOptions(args: [String]) throws -> WorkspaceCreateOptions {
        var name: String?
        var icon = "l:book-open:lime"
        var personality = "New PROJECT WORKSPACE"
        var model = "auto"

        var index = 0
        while index < args.count {
            let arg = args[index]

            switch workspaceOptionNameAndValue(arg) {
            case ("--name", let inlineValue):
                (name, index) = try readWorkspaceOptionValue(inlineValue, args: args, index: index, option: "--name")
            case ("--icon", let inlineValue):
                (icon, index) = try readWorkspaceOptionValue(inlineValue, args: args, index: index, option: "--icon")
            case ("--personality", let inlineValue):
                (personality, index) = try readWorkspaceOptionValue(inlineValue, args: args, index: index, option: "--personality")
            case ("--model", let inlineValue):
                (model, index) = try readWorkspaceOptionValue(inlineValue, args: args, index: index, option: "--model")
            default:
                throw GrokError.apiError("Unknown option for workspaces create: \(arg)\n\(workspaceCreateUsage)")
            }

            index += 1
        }

        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("Missing required option: --name <name>\n\(workspaceCreateUsage)")
        }

        return WorkspaceCreateOptions(name: name, icon: icon, personality: personality, model: model)
    }

    static func removeWorkspaceFlag(_ flag: String, from args: inout [String]) -> Bool {
        let originalCount = args.count
        args.removeAll { $0 == flag }
        return args.count != originalCount
    }

    static func workspaceOptionNameAndValue(_ arg: String) -> (String, String?) {
        guard let separator = arg.firstIndex(of: "=") else {
            return (arg, nil)
        }
        return (String(arg[..<separator]), String(arg[arg.index(after: separator)...]))
    }

    static func readWorkspaceOptionValue(
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

    static func printWorkspaceJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static func printWorkspaceRows(_ workspaces: [GrokWorkspace]) {
        guard !workspaces.isEmpty else {
            print("No workspaces found.".yellow)
            return
        }

        print("Workspaces:".cyan.bold)
        for workspace in workspaces {
            printWorkspaceSummary(workspace)
        }
    }

    static func printWorkspaceSummary(_ workspace: GrokWorkspace) {
        let raw = workspaceDictionary(from: workspace)
        let id = workspace.workspaceId ?? workspace.id ?? workspaceString(in: raw, keys: ["workspaceId", "workspace_id", "id"])
        let name = workspace.name ?? workspace.title ?? workspaceString(in: raw, keys: ["name", "title"])
        let model = workspace.preferredModel ?? workspaceString(in: raw, keys: ["preferredModel", "preferred_model"])
        let icon = workspace.icon ?? workspaceString(in: raw, keys: ["icon"])

        printWorkspaceParts([
            ("ID", id),
            ("Name", name),
            ("Model", model),
            ("Icon", icon)
        ])
    }

    static func printConversationV2Summary(_ response: GrokConversationV2Response, fallbackId: String) {
        let raw = workspaceAnyDictionary(from: response.rawJSON)
        let conversation = firstWorkspaceDictionary(in: raw, keys: ["conversation", "data", "result"]) ?? raw
        let id = response.conversationId ?? workspaceString(in: conversation, keys: ["conversationId", "conversation_id", "id"]) ?? fallbackId
        let title = workspaceString(in: conversation, keys: ["title", "name"])
        let workspaceCount = workspaceArrayCount(in: conversation, keys: ["workspaces", "workspaceIds", "workspace_ids"])
        let hasTaskResult = conversation["taskResult"] != nil || conversation["task_result"] != nil

        printWorkspaceParts([
            ("Conversation", id),
            ("Title", title),
            ("Workspaces", workspaceCount.map(String.init)),
            ("TaskResult", hasTaskResult ? "yes" : nil)
        ])
    }

    static func printWorkspaceParts(_ parts: [(String, String?)]) {
        let text = parts.compactMap { label, value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return "\(label): \(value)"
        }

        print(text.isEmpty ? "(no summary available)" : text.joined(separator: " | "))
    }

    static func workspaceDictionary<T: Encodable>(from value: T) -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    static func workspaceAnyDictionary(from value: AnyCodable) -> [String: Any] {
        workspaceDictionary(from: value)
    }

    static func workspaceString(in dictionary: [String: Any], keys: [String]) -> String? {
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

    static func firstWorkspaceDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    static func workspaceArrayCount(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? [Any] {
                return value.count
            }
        }
        return nil
    }

    static var workspacesUsage: String {
        """
        Workspaces:
          grok workspaces list [--json]
          grok workspaces create --name <name> [--icon <icon>] [--personality <text>] [--model <mode>] [--json]
          grok workspaces add-conversation <workspaceId> <conversationId> [--json]
          grok workspaces delete <workspaceId> [--json]
          grok workspaces conversation <conversationId> [--json]
        """
    }

    static var workspaceCreateUsage: String {
        "Usage: grok workspaces create --name <name> [--icon <icon>] [--personality <text>] [--model <mode>] [--json]"
    }

    static var workspacesListUsage: String {
        "Usage: grok workspaces list [--json] [--debug]"
    }

    static var workspacesAddConversationUsage: String {
        "Usage: grok workspaces add-conversation <workspaceId> <conversationId> [--json] [--debug]"
    }

    static var workspacesDeleteUsage: String {
        "Usage: grok workspaces delete <workspaceId> [--json] [--debug]"
    }

    static var workspacesConversationUsage: String {
        "Usage: grok workspaces conversation <conversationId> [--json] [--debug]"
    }
}
