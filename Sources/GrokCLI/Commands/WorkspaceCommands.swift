import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleWorkspacesCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")
        let jsonRequested = isJSONRequested(args)

        let parsed: ParsedWorkspaceCommand
        do {
            parsed = try parseWorkspaceCommand(args: args)
        } catch {
            if jsonRequested {
                printJSONError(command: "workspaces", error: error, exitCode: 2, debug: debug)
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
                let response = try await client.listWorkspacesResponse()
                if parsed.json {
                    try printJSONResult(
                        command: "workspaces",
                        subcommand: "list",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "workspace",
                            items: response.workspaces.map { AnyCodable(workspaceJSON($0)) },
                            raw: response.rawJSON
                        )),
                        debug: parsed.debug
                    )
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
                    try printJSONResult(
                        command: "workspaces",
                        subcommand: "create",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "workspace",
                            action: "create",
                            id: response.workspace?.workspaceId ?? response.workspace?.id,
                            item: response.workspace.map { AnyCodable(workspaceJSON($0)) },
                            raw: response.rawJSON
                        )),
                        debug: parsed.debug
                    )
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
                    try printJSONResult(
                        command: "workspaces",
                        subcommand: "add-conversation",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "workspace",
                            action: "addConversation",
                            id: workspaceId,
                            item: response.workspace.map { AnyCodable(workspaceJSON($0)) },
                            raw: response.rawJSON,
                            extra: ["conversationId": AnyCodable(conversationId)]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Added conversation \(conversationId) to workspace \(workspaceId)".green)

            case .delete(let workspaceId):
                let response = try await client.deleteWorkspace(workspaceId: workspaceId)
                if parsed.json {
                    try printJSONResult(
                        command: "workspaces",
                        subcommand: "delete",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "workspace",
                            action: "delete",
                            id: workspaceId,
                            item: response.workspace.map { AnyCodable(workspaceJSON($0)) },
                            raw: response.rawJSON
                        )),
                        debug: parsed.debug
                    )
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
                    try printJSONResult(
                        command: "workspaces",
                        subcommand: "conversation",
                        category: "conversation_detail",
                        data: AnyCodable([
                            "conversationId": AnyCodable(response.conversationId ?? conversationId),
                            "raw": response.rawJSON
                        ]),
                        debug: parsed.debug
                    )
                    return
                }
                printConversationV2Summary(response, fallbackId: conversationId)

            case .help(_):
                return
            }
        } catch {
            if parsed.json {
                printJSONError(command: "workspaces", error: error, exitCode: 1, debug: parsed.debug)
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
        let json = try CLIOptionParsing.removeJSONOutputOptions(from: &remaining)
        let debug = CLIOptionParsing.removeFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedWorkspaceCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspacesListUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok workspaces list [--json|--format json] [--debug]")
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
                throw GrokError.apiError("Usage: grok workspaces add-conversation <workspaceId> <conversationId> [--json|--format json] [--debug]")
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
                throw GrokError.apiError("Usage: grok workspaces delete <workspaceId> [--json|--format json] [--debug]")
            }
            return ParsedWorkspaceCommand(action: .delete(workspaceId: remaining[1]), json: json, debug: debug)

        case "conversation":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedWorkspaceCommand(action: .help(workspacesConversationUsage), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError("Usage: grok workspaces conversation <conversationId> [--json|--format json] [--debug]")
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

            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--name", let inlineValue):
                (name, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--name")
            case ("--icon", let inlineValue):
                (icon, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--icon")
            case ("--personality", let inlineValue):
                (personality, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--personality")
            case ("--model", let inlineValue):
                (model, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--model")
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
        let raw = jsonDictionary(from: workspace)
        let id = workspace.workspaceId ?? workspace.id ?? stringValue(in: raw, keys: ["workspaceId", "workspace_id", "id"])
        let name = workspace.name ?? workspace.title ?? stringValue(in: raw, keys: ["name", "title"])
        let model = workspace.preferredModel ?? stringValue(in: raw, keys: ["preferredModel", "preferred_model"])
        let icon = workspace.icon ?? stringValue(in: raw, keys: ["icon"])

        printLabeledParts([
            ("ID", id),
            ("Name", name),
            ("Model", model),
            ("Icon", icon)
        ])
    }

    static func printConversationV2Summary(_ response: GrokConversationV2Response, fallbackId: String) {
        let raw = anyDictionary(from: response.rawJSON)
        let conversation = firstDictionary(in: raw, keys: ["conversation", "data", "result"]) ?? raw
        let id = response.conversationId ?? stringValue(in: conversation, keys: ["conversationId", "conversation_id", "id"]) ?? fallbackId
        let title = stringValue(in: conversation, keys: ["title", "name"])
        let workspaceCount = arrayCount(in: conversation, keys: ["workspaces", "workspaceIds", "workspace_ids"])
        let hasTaskResult = conversation["taskResult"] != nil || conversation["task_result"] != nil

        printLabeledParts([
            ("Conversation", id),
            ("Title", title),
            ("Workspaces", workspaceCount.map(String.init)),
            ("TaskResult", hasTaskResult ? "yes" : nil)
        ])
    }

    static var workspacesUsage: String {
        """
        Workspaces:
          grok workspaces list [--json|--format json]
          grok workspaces create --name <name> [--icon <icon>] [--personality <text>] [--model <mode>] [--json|--format json]
          grok workspaces add-conversation <workspaceId> <conversationId> [--json|--format json]
          grok workspaces delete <workspaceId> [--json|--format json]
          grok workspaces conversation <conversationId> [--json|--format json]
        """
    }

    static var workspaceCreateUsage: String {
        "Usage: grok workspaces create --name <name> [--icon <icon>] [--personality <text>] [--model <mode>] [--json|--format json]"
    }

    static var workspacesListUsage: String {
        "Usage: grok workspaces list [--json|--format json] [--debug]"
    }

    static var workspacesAddConversationUsage: String {
        "Usage: grok workspaces add-conversation <workspaceId> <conversationId> [--json|--format json] [--debug]"
    }

    static var workspacesDeleteUsage: String {
        "Usage: grok workspaces delete <workspaceId> [--json|--format json] [--debug]"
    }

    static var workspacesConversationUsage: String {
        "Usage: grok workspaces conversation <conversationId> [--json|--format json] [--debug]"
    }
}
