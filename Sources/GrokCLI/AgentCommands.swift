import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleAgentsCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")

        let parsed: ParsedAgentCommand
        do {
            parsed = try parseAgentCommand(args: args)
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
                let response = try await client.getUserSettingsResponse()
                if parsed.json {
                    try printAgentsJSON(response.rawJSON)
                    return
                }
                if response.agentCustomizations.isEmpty {
                    print("No saved agent customizations found. Built-in IDs:".yellow)
                    printAgentRows(defaultAgentCustomizations())
                } else {
                    printAgentRows(response.agentCustomizations)
                }

            case .set(let options):
                let current = try await currentAgentCustomizations(client: client, replace: options.replace)
                let updated = try mergeAgentCustomization(options: options, into: current)
                let response = try await client.updateAgentCustomizations(updated)
                if parsed.json {
                    try printAgentsJSON(response.rawJSON)
                    return
                }
                print("Updated agent \(options.agentId)".green.bold)
                if options.agentId == 0, options.name != nil {
                    print("Agent 0 uses Grok's default name.".yellow)
                }
                if let agent = updated.first(where: { $0.agentId == options.agentId }) {
                    printAgentSummary(agent)
                }

            case .clear(let options):
                let current = try await currentAgentCustomizations(client: client, replace: options.replace)
                let updated = try mergeAgentCustomization(options: options, into: current)
                let response = try await client.updateAgentCustomizations(updated)
                if parsed.json {
                    try printAgentsJSON(response.rawJSON)
                    return
                }
                print("Cleared agent \(options.agentId) instructions".yellow)
                if let agent = updated.first(where: { $0.agentId == options.agentId }) {
                    printAgentSummary(agent)
                }

            case .syncCustom(let replace):
                let current = try await currentAgentCustomizations(client: client, replace: replace)
                let options = AgentSetOptions(
                    agentId: 0,
                    name: "Grok",
                    instructions: GrokCLI.getCustomInstructions(),
                    replace: replace
                )
                let updated = try mergeAgentCustomization(options: options, into: current)
                let response = try await client.updateAgentCustomizations(updated)
                if parsed.json {
                    try printAgentsJSON(response.rawJSON)
                    return
                }
                print("Synced local custom instructions to agent 0.".green)
                if let agent = updated.first(where: { $0.agentId == 0 }) {
                    printAgentSummary(agent)
                }

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
    enum AgentAction {
        case list
        case set(AgentSetOptions)
        case clear(AgentSetOptions)
        case syncCustom(replace: Bool)
        case help(String)
    }

    struct ParsedAgentCommand {
        let action: AgentAction
        let json: Bool
        let debug: Bool
    }

    struct AgentSetOptions {
        let agentId: Int
        let name: String?
        let instructions: String
        let replace: Bool
    }

    static func parseAgentCommand(args: [String]) throws -> ParsedAgentCommand {
        var remaining = args
        let json = removeAgentFlag("--json", from: &remaining)
        let debug = removeAgentFlag("--debug", from: &remaining)
        let replace = removeAgentFlag("--replace", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedAgentCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsListUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok agents list [--json] [--debug]")
            }
            return ParsedAgentCommand(action: .list, json: json, debug: debug)

        case "set":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsSetUsage), json: json, debug: debug)
            }
            let options = try parseAgentSetOptions(args: Array(remaining.dropFirst()), replace: replace)
            return ParsedAgentCommand(action: .set(options), json: json, debug: debug)

        case "clear":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsClearUsage), json: json, debug: debug)
            }
            guard remaining.count == 2, let agentId = Int(remaining[1]) else {
                throw GrokError.apiError("Usage: grok agents clear <agentId> [--replace] [--json] [--debug]")
            }
            try validateAgentId(agentId)
            let options = AgentSetOptions(
                agentId: agentId,
                name: nil,
                instructions: "",
                replace: replace
            )
            return ParsedAgentCommand(action: .clear(options), json: json, debug: debug)

        case "sync-custom":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsSyncCustomUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok agents sync-custom [--replace] [--json] [--debug]")
            }
            return ParsedAgentCommand(action: .syncCustom(replace: replace), json: json, debug: debug)

        case "help", "-h", "--help":
            return ParsedAgentCommand(action: .help(agentsUsage), json: json, debug: debug)

        default:
            throw GrokError.apiError("Unknown agents command: \(command)\n\(agentsUsage)")
        }
    }

    static func parseAgentSetOptions(args: [String], replace: Bool) throws -> AgentSetOptions {
        guard let first = args.first, let agentId = Int(first) else {
            throw GrokError.apiError("Usage: \(agentsSetUsage)")
        }
        try validateAgentId(agentId)

        var name: String?
        var instructions: String?
        var filePath: String?

        var index = 1
        while index < args.count {
            let arg = args[index]

            switch agentOptionNameAndValue(arg) {
            case ("--name", let inlineValue):
                (name, index) = try readAgentOptionValue(inlineValue, args: args, index: index, option: "--name")
            case ("--instructions", let inlineValue):
                (instructions, index) = try readAgentOptionValue(inlineValue, args: args, index: index, option: "--instructions")
            case ("--file", let inlineValue), ("--instructions-file", let inlineValue):
                (filePath, index) = try readAgentOptionValue(inlineValue, args: args, index: index, option: "--file")
            default:
                throw GrokError.apiError("Unknown option for agents set: \(arg)\n\(agentsSetUsage)")
            }

            index += 1
        }

        if instructions != nil, filePath != nil {
            throw GrokError.apiError("Use either --instructions or --file, not both")
        }

        let resolvedInstructions: String
        if let instructions {
            resolvedInstructions = instructions
        } else if let filePath {
            resolvedInstructions = try readAgentInstructionsFile(filePath)
        } else {
            throw GrokError.apiError("Missing required option: --instructions <text> or --file <path>\n\(agentsSetUsage)")
        }

        return AgentSetOptions(
            agentId: agentId,
            name: name,
            instructions: resolvedInstructions,
            replace: replace
        )
    }

    static func currentAgentCustomizations(
        client: GrokClient,
        replace: Bool
    ) async throws -> [GrokAgentCustomization] {
        guard !replace else {
            return defaultAgentCustomizations()
        }

        do {
            let current = try await client.getUserSettingsResponse().agentCustomizations
            if current.isEmpty {
                throw GrokError.apiError("User settings did not include agent values. Re-run with --replace to send a local four-agent profile.")
            }
            return current
        } catch {
            if let grokError = error as? GrokError {
                throw grokError
            }
            throw GrokError.apiError("Could not fetch current agent settings. Re-run with --replace to send a local four-agent profile.")
        }
    }

    static func mergeAgentCustomization(
        options: AgentSetOptions,
        into current: [GrokAgentCustomization]
    ) throws -> [GrokAgentCustomization] {
        try validateAgentId(options.agentId)

        var byId = Dictionary(uniqueKeysWithValues: defaultAgentCustomizations().map { ($0.agentId, $0) })
        for agent in current {
            if (0...3).contains(agent.agentId) {
                byId[agent.agentId] = agent
            }
        }

        let existing = byId[options.agentId]
        let name = options.agentId == 0
            ? "Grok"
            : (options.name ?? existing?.name ?? GrokAgentCustomization.defaultName(for: options.agentId))
        byId[options.agentId] = GrokAgentCustomization(
            agentId: options.agentId,
            name: name,
            instructions: options.instructions
        )

        return byId.values.sorted { $0.agentId < $1.agentId }
    }

    static func defaultAgentCustomizations() -> [GrokAgentCustomization] {
        (0...3).map { agentId in
            GrokAgentCustomization(
                agentId: agentId,
                name: GrokAgentCustomization.defaultName(for: agentId),
                instructions: ""
            )
        }
    }

    static func validateAgentId(_ agentId: Int) throws {
        guard (0...3).contains(agentId) else {
            throw GrokError.apiError("Invalid agent ID. Grok currently exposes agent IDs 0, 1, 2, and 3.")
        }
    }

    static func removeAgentFlag(_ flag: String, from args: inout [String]) -> Bool {
        let originalCount = args.count
        args.removeAll { $0 == flag }
        return args.count != originalCount
    }

    static func agentOptionNameAndValue(_ arg: String) -> (String, String?) {
        guard let separator = arg.firstIndex(of: "=") else {
            return (arg, nil)
        }
        return (String(arg[..<separator]), String(arg[arg.index(after: separator)...]))
    }

    static func readAgentOptionValue(
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

    static func readAgentInstructionsFile(_ path: String) throws -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return try String(contentsOfFile: expandedPath, encoding: .utf8)
    }

    static func printAgentRows(_ agents: [GrokAgentCustomization]) {
        guard !agents.isEmpty else {
            print("No agent customizations found.".yellow)
            return
        }

        print("Agents:".cyan.bold)
        for agent in agents.sorted(by: { $0.agentId < $1.agentId }) {
            printAgentSummary(agent)
        }
    }

    static func printAgentSummary(_ agent: GrokAgentCustomization) {
        let instructionSummary = agent.instructions.isEmpty
            ? "empty"
            : "\(agent.instructions.count) chars"
        print("ID: \(agent.agentId) | Name: \(agent.name) | Instructions: \(instructionSummary)")
    }

    static func printAgentsJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static var agentsUsage: String {
        """
        Agents:
          grok agents list [--json]
          grok agents set <agentId> --instructions <text> [--name <name>] [--replace] [--json]
          grok agents set <agentId> --file <path> [--name <name>] [--replace] [--json]
          grok agents clear <agentId> [--replace] [--json]
          grok agents sync-custom [--replace] [--json]

        Agent IDs are 0 through 3. Agent 0 maps to the old custom-instructions role.
        """
    }

    static var agentsSetUsage: String {
        "grok agents set <agentId> (--instructions <text> | --file <path>) [--name <name>] [--replace] [--json]"
    }

    static var agentsListUsage: String {
        "Usage: grok agents list [--json] [--debug]"
    }

    static var agentsClearUsage: String {
        "Usage: grok agents clear <agentId> [--replace] [--json] [--debug]"
    }

    static var agentsSyncCustomUsage: String {
        "Usage: grok agents sync-custom [--replace] [--json] [--debug]"
    }
}
