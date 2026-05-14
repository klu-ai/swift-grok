import Foundation
import GrokClient

extension GrokCLI {
    struct InteractiveCommand {
        let name: String
        let hasSlash: Bool
        let remainder: String

        var isExact: Bool {
            remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func arguments() throws -> [String] {
            try GrokCLI.splitCommandArguments(remainder)
        }
    }


    static var toggleWords: Set<String> {
        ["on", "off", "enable", "enabled", "disable", "disabled", "true", "false"]
    }

    static func interactiveCommand(from input: String) -> InteractiveCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let hasSlash = trimmed.hasPrefix("/")
        let commandText = hasSlash ? String(trimmed.dropFirst()) : trimmed
        guard !commandText.isEmpty else {
            return nil
        }

        var commandEnd = commandText.startIndex
        while commandEnd < commandText.endIndex, !commandText[commandEnd].isWhitespace {
            commandEnd = commandText.index(after: commandEnd)
        }

        let name = String(commandText[..<commandEnd]).lowercased()
        let remainder = String(commandText[commandEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let command = InteractiveCommand(name: name, hasSlash: hasSlash, remainder: remainder)

        if hasSlash {
            return command
        }

        return isBareInteractiveCommand(command) ? command : nil
    }

    static func parseSkillCreatePrompt(from remainder: String) throws -> String {
        let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        var commandEnd = trimmed.startIndex
        while commandEnd < trimmed.endIndex, !trimmed[commandEnd].isWhitespace {
            commandEnd = trimmed.index(after: commandEnd)
        }

        let subcommand = String(trimmed[..<commandEnd]).lowercased()
        guard subcommand == "create" else {
            throw GrokError.apiError("Usage: /skill create <prompt>")
        }

        let prompt = String(trimmed[commandEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw GrokError.apiError("Usage: /skill create <prompt>")
        }
        return prompt
    }

    static func isBareInteractiveCommand(_ command: InteractiveCommand) -> Bool {
        let exactCommands: Set<String> = [
            "exit", "quit", "help", "new", "resume", "list",
            "clear", "cls", "limits"
//            "special"
        ]
        if exactCommands.contains(command.name) {
            return command.isExact
        }

        let modelCommands: Set<String> = ["model", "models", "mode", "modes"]
        if modelCommands.contains(command.name) {
            return command.isExact || command.remainder.split(whereSeparator: { $0.isWhitespace }).count == 1
        }

        let toggleCommands: Set<String> = [
            "reason", "reasoning",
            "private", "stream", "typeahead",
            "md", "markdown", "raw"
        ]
        if toggleCommands.contains(command.name) {
            guard !command.isExact else {
                return true
            }
            let parts = command.remainder.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 1 else {
                return false
            }
            return toggleWords.contains(parts[0].lowercased())
        }

        if command.name == "format" {
            guard !command.isExact else {
                return true
            }
            let parts = command.remainder.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 1 else {
                return false
            }
            return OutputFormat.resolve(String(parts[0])) != nil
        }

        if command.name == "goal" {
            return true
        }

        let groupSubcommands: [String: Set<String>] = [
            "auth": Set(["generate", "import", "help", "-h", "--help"]).union(authBrowserNames),
            "tasks": ["list", "select", "show", "details", "detail", "results", "result", "create", "archive", "help", "-h", "--help", "--json", "--debug"],
            "skills": ["list", "mine", "user", "help", "-h", "--help", "--json", "--debug"],
            "agents": ["list", "show", "view", "edit", "set", "clear", "help", "-h", "--help", "--replace", "--include-instructions", "--show-instructions", "--json", "--debug"],
            "workspaces": ["list", "create", "add-conversation", "delete", "remove", "conversation", "select", "help", "-h", "--help", "--json", "--debug"],
            "workspace": ["list", "create", "add-conversation", "delete", "remove", "conversation", "select", "help", "-h", "--help", "--json", "--debug"],
            "files": ["list", "upload", "delete", "remove", "help", "-h", "--help", "--json", "--debug"],
            "attach": ["list", "upload", "clear"]
        ]

        guard let allowedSubcommands = groupSubcommands[command.name] else {
            return false
        }
        guard let firstArg = command.remainder.split(whereSeparator: { $0.isWhitespace }).first else {
            return true
        }
        if command.name == "auth", firstArg.hasPrefix("-") {
            return true
        }
        return allowedSubcommands.contains(firstArg.lowercased())
    }

    static func resolveToggle(current: Bool, args: [String], usage: String) throws -> Bool {
        guard args.count <= 1 else {
            throw GrokError.apiError("Usage: \(usage) [on|off]")
        }
        guard let rawValue = args.first?.lowercased() else {
            return !current
        }

        switch rawValue {
        case "on", "enable", "enabled", "true":
            return true
        case "off", "disable", "disabled", "false":
            return false
        default:
            throw GrokError.apiError("Usage: \(usage) [on|off]")
        }
    }

    static func resolveOutputFormatCommand(command: String, current: OutputFormat, args: [String], usage: String) throws -> OutputFormat {
        let normalizedCommand = command.lowercased()

        switch normalizedCommand {
        case "format":
            guard args.count <= 1 else {
                throw GrokError.apiError("Usage: \(usage) [md|raw]")
            }
            guard let rawValue = args.first else {
                return current == .markdown ? .raw : .markdown
            }
            guard let format = OutputFormat.resolve(rawValue) else {
                throw GrokError.apiError("Usage: \(usage) [md|raw]")
            }
            guard !format.isJSON else {
                throw GrokError.apiError("JSON output is available from the CLI command line. Run a command with --json, for example: grok message --json <message>")
            }
            return format
        case "md", "markdown":
            let markdownEnabled = try resolveToggle(current: current == .markdown, args: args, usage: usage)
            return markdownEnabled ? .markdown : .raw
        case "raw":
            let rawEnabled = try resolveToggle(current: current == .raw, args: args, usage: usage)
            return rawEnabled ? .raw : .markdown
        default:
            throw GrokError.apiError("Usage: \(usage) [md|raw]")
        }
    }

}
