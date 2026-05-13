import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleAgentsCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")
        let jsonRequested = isJSONRequested(args)

        let parsed: ParsedAgentCommand
        do {
            parsed = try parseAgentCommand(args: args)
        } catch {
            if jsonRequested {
                printJSONError(command: "agents", error: error, exitCode: 2, debug: debug)
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
                let response = try await client.getUserSettingsResponse()
                if parsed.json {
                    let agents = response.agentCustomizations.isEmpty ? defaultAgentCustomizations() : response.agentCustomizations
                    try printJSONResult(
                        command: "agents",
                        subcommand: "list",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "agent",
                            items: agents.map { AnyCodable(agentJSON($0, includeInstructions: parsed.includeInstructions)) },
                            raw: parsed.includeInstructions ? response.rawJSON : nil,
                            extra: parsed.includeInstructions ? [:] : ["rawRedacted": AnyCodable(true)]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                if response.agentCustomizations.isEmpty {
                    print("No saved agent customizations found. Built-in IDs:".yellow)
                    printAgentRows(defaultAgentCustomizations())
                } else {
                    printAgentRows(response.agentCustomizations)
                }

            case .show(let agentId):
                let response = try await client.getUserSettingsResponse()
                let agents = response.agentCustomizations.isEmpty ? defaultAgentCustomizations() : response.agentCustomizations
                let agent = try agentCustomization(agentId: agentId, in: agents)
                if parsed.json {
                    try printJSONResult(
                        command: "agents",
                        subcommand: "show",
                        category: "resource_detail",
                        data: AnyCodable([
                            "resource": AnyCodable("agent"),
                            "item": AnyCodable(agentJSON(agent, includeInstructions: true)),
                            "raw": response.rawJSON
                        ] as [String: AnyCodable]),
                        debug: parsed.debug
                    )
                    return
                }
                printAgentDetail(agent)

            case .set(let options):
                let current = try await currentAgentCustomizations(client: client, replace: options.replace)
                let updated = try mergeAgentCustomization(options: options, into: current)
                let response = try await client.updateAgentCustomizations(updated)
                if parsed.json {
                    try printJSONResult(
                        command: "agents",
                        subcommand: "set",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "agent",
                            action: "set",
                            id: String(options.agentId),
                            item: updated.first(where: { $0.agentId == options.agentId }).map { AnyCodable(agentJSON($0, includeInstructions: parsed.includeInstructions)) },
                            raw: parsed.includeInstructions ? response.rawJSON : nil,
                            extra: parsed.includeInstructions ? [:] : ["rawRedacted": AnyCodable(true)]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Updated agent \(options.agentId)".green.bold)
                if options.agentId == 0, options.name != nil {
                    print("Agent 0 uses Grok's default name.".yellow)
                }
                if let agent = updated.first(where: { $0.agentId == options.agentId }) {
                    printAgentSummary(agent)
                }

            case .edit(let agentId, let replace):
                let current = try await currentAgentCustomizations(client: client, replace: replace)
                let agent = try agentCustomization(agentId: agentId, in: current)
                let editedInstructions = try editAgentInstructions(agent)
                if editedInstructions == agent.instructions {
                    if parsed.json {
                        try printJSONResult(
                            command: "agents",
                            subcommand: "edit",
                            category: "resource_mutation",
                            data: AnyCodable(resourceMutationJSON(
                                resource: "agent",
                                action: "edit",
                                id: String(agentId),
                                item: AnyCodable(agentJSON(agent, includeInstructions: parsed.includeInstructions)),
                                extra: ["changed": AnyCodable(false)]
                            )),
                            debug: parsed.debug
                        )
                        return
                    }
                    print("No changes made for agent \(agentId).".yellow)
                    return
                }

                let options = AgentSetOptions(
                    agentId: agentId,
                    name: nil,
                    instructions: editedInstructions,
                    replace: replace
                )
                let updated = try mergeAgentCustomization(options: options, into: current)
                let response = try await client.updateAgentCustomizations(updated)
                if parsed.json {
                    try printJSONResult(
                        command: "agents",
                        subcommand: "edit",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "agent",
                            action: "edit",
                            id: String(agentId),
                            item: updated.first(where: { $0.agentId == agentId }).map { AnyCodable(agentJSON($0, includeInstructions: parsed.includeInstructions)) },
                            raw: parsed.includeInstructions ? response.rawJSON : nil,
                            extra: parsed.includeInstructions ? ["changed": AnyCodable(true)] : ["changed": AnyCodable(true), "rawRedacted": AnyCodable(true)]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Updated agent \(agentId)".green.bold)
                if let agent = updated.first(where: { $0.agentId == agentId }) {
                    printAgentSummary(agent)
                }

            case .clear(let options):
                let current = try await currentAgentCustomizations(client: client, replace: options.replace)
                let updated = try mergeAgentCustomization(options: options, into: current)
                let response = try await client.updateAgentCustomizations(updated)
                if parsed.json {
                    try printJSONResult(
                        command: "agents",
                        subcommand: "clear",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "agent",
                            action: "clear",
                            id: String(options.agentId),
                            item: updated.first(where: { $0.agentId == options.agentId }).map { AnyCodable(agentJSON($0, includeInstructions: parsed.includeInstructions)) },
                            raw: parsed.includeInstructions ? response.rawJSON : nil,
                            extra: parsed.includeInstructions ? [:] : ["rawRedacted": AnyCodable(true)]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Cleared agent \(options.agentId) instructions".yellow)
                if let agent = updated.first(where: { $0.agentId == options.agentId }) {
                    printAgentSummary(agent)
                }

            case .help(_):
                return
            }
        } catch {
            if parsed.json {
                printJSONError(command: "agents", error: error, exitCode: 1, debug: parsed.debug)
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
    enum AgentAction {
        case list
        case show(Int)
        case set(AgentSetOptions)
        case edit(agentId: Int, replace: Bool)
        case clear(AgentSetOptions)
        case help(String)
    }

    struct ParsedAgentCommand {
        let action: AgentAction
        let json: Bool
        let debug: Bool
        let includeInstructions: Bool
    }

    struct AgentSetOptions {
        let agentId: Int
        let name: String?
        let instructions: String
        let replace: Bool
    }

    static func parseAgentCommand(args: [String]) throws -> ParsedAgentCommand {
        var remaining = args
        let json = try CLIOptionParsing.removeJSONOutputOptions(from: &remaining)
        let debug = CLIOptionParsing.removeFlag("--debug", from: &remaining)
        let replace = CLIOptionParsing.removeFlag("--replace", from: &remaining)
        let includeInstructions =
            CLIOptionParsing.removeFlag("--include-instructions", from: &remaining) ||
            CLIOptionParsing.removeFlag("--show-instructions", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedAgentCommand(action: .list, json: json, debug: debug, includeInstructions: includeInstructions)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsListUsage), json: json, debug: debug, includeInstructions: includeInstructions)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok agents list [--json|--format json] [--debug]")
            }
            return ParsedAgentCommand(action: .list, json: json, debug: debug, includeInstructions: includeInstructions)

        case "show", "view":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsShowUsage), json: json, debug: debug, includeInstructions: includeInstructions)
            }
            guard remaining.count == 2, let agentId = Int(remaining[1]) else {
                throw GrokError.apiError("Usage: \(agentsShowUsage)")
            }
            try validateAgentId(agentId)
            return ParsedAgentCommand(action: .show(agentId), json: json, debug: debug, includeInstructions: includeInstructions)

        case "set":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsSetUsage), json: json, debug: debug, includeInstructions: includeInstructions)
            }
            let options = try parseAgentSetOptions(args: Array(remaining.dropFirst()), replace: replace)
            return ParsedAgentCommand(action: .set(options), json: json, debug: debug, includeInstructions: includeInstructions)

        case "edit":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsEditUsage), json: json, debug: debug, includeInstructions: includeInstructions)
            }
            guard remaining.count == 2, let agentId = Int(remaining[1]) else {
                throw GrokError.apiError("Usage: \(agentsEditUsage)")
            }
            try validateAgentId(agentId)
            return ParsedAgentCommand(action: .edit(agentId: agentId, replace: replace), json: json, debug: debug, includeInstructions: includeInstructions)

        case "clear":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedAgentCommand(action: .help(agentsClearUsage), json: json, debug: debug, includeInstructions: includeInstructions)
            }
            guard remaining.count == 2, let agentId = Int(remaining[1]) else {
                throw GrokError.apiError("Usage: grok agents clear <agentId> [--replace] [--json|--format json] [--debug]")
            }
            try validateAgentId(agentId)
            let options = AgentSetOptions(
                agentId: agentId,
                name: nil,
                instructions: "",
                replace: replace
            )
            return ParsedAgentCommand(action: .clear(options), json: json, debug: debug, includeInstructions: includeInstructions)

        case "help", "-h", "--help":
            return ParsedAgentCommand(action: .help(agentsUsage), json: json, debug: debug, includeInstructions: includeInstructions)

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

            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--name", let inlineValue):
                (name, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--name")
            case ("--instructions", let inlineValue):
                (instructions, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--instructions")
            case ("--file", let inlineValue), ("--instructions-file", let inlineValue):
                (filePath, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--file")
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

    static func agentCustomization(
        agentId: Int,
        in agents: [GrokAgentCustomization]
    ) throws -> GrokAgentCustomization {
        try validateAgentId(agentId)
        guard let agent = agents.first(where: { $0.agentId == agentId }) else {
            throw GrokError.apiError("Agent \(agentId) was not found in user settings.")
        }
        return agent
    }

    static func editAgentInstructions(_ agent: GrokAgentCustomization) throws -> String {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-agent-\(agent.agentId)-instructions-\(UUID().uuidString).md")
        try agent.instructions.write(to: temporaryURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try runEditor(for: temporaryURL)
        return try String(contentsOf: temporaryURL, encoding: .utf8)
    }

    static func runEditor(for fileURL: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        let editorCommand = environment["VISUAL"] ?? environment["EDITOR"] ?? "vi"
        let parts = try splitCommandArguments(editorCommand)
        guard let executable = parts.first else {
            throw GrokError.apiError("EDITOR is empty.")
        }

        let process = Process()
        let editorArguments = Array(parts.dropFirst()) + [fileURL.path]
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: NSString(string: executable).expandingTildeInPath)
            process.arguments = editorArguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + editorArguments
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GrokError.apiError("Editor exited with status \(process.terminationStatus).")
        }
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

    static func printAgentDetail(_ agent: GrokAgentCustomization) {
        let instructionSummary = agent.instructions.isEmpty
            ? "empty"
            : "\(agent.instructions.count) chars"
        print("Agent \(agent.agentId): \(agent.name)".cyan.bold)
        print("Instructions: \(instructionSummary)".yellow)
        guard !agent.instructions.isEmpty else {
            return
        }
        print("")
        print(agent.instructions)
    }

    static var agentsUsage: String {
        """
        Agents:
          grok agents list [--include-instructions] [--json|--format json]
          grok agents show <agentId> [--json|--format json]
          grok agents edit <agentId> [--replace] [--include-instructions] [--json|--format json]
          grok agents set <agentId> --instructions <text> [--name <name>] [--replace] [--include-instructions] [--json|--format json]
          grok agents set <agentId> --file <path> [--name <name>] [--replace] [--include-instructions] [--json|--format json]
          grok agents clear <agentId> [--replace] [--include-instructions] [--json|--format json]
        Agent availability depends on the account. Basic accounts usually expose agent 0; SuperGrok accounts can expose agents 0 through 3.
        JSON list and mutation responses redact instruction text by default; pass --include-instructions to include it.
        The edit command opens $VISUAL, $EDITOR, or vi with the current instructions.
        """
    }

    static var agentsShowUsage: String {
        "Usage: grok agents show <agentId> [--json|--format json] [--debug]"
    }

    static var agentsEditUsage: String {
        "Usage: grok agents edit <agentId> [--replace] [--include-instructions] [--json|--format json] [--debug]"
    }

    static var agentsSetUsage: String {
        "grok agents set <agentId> (--instructions <text> | --file <path>) [--name <name>] [--replace] [--include-instructions] [--json|--format json]"
    }

    static var agentsListUsage: String {
        "Usage: grok agents list [--include-instructions] [--json|--format json] [--debug]"
    }

    static var agentsClearUsage: String {
        "Usage: grok agents clear <agentId> [--replace] [--include-instructions] [--json|--format json] [--debug]"
    }
}
