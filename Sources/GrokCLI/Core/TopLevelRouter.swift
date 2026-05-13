import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func exit(with code: Int32) -> Never {
        processExit(code)
    }

    static func isHelpArgument(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized == "help" || normalized == "-h" || normalized == "--help"
    }

    static func containsHelpArgument(_ args: [String]) -> Bool {
        args.contains { isHelpArgument($0) }
    }

    static func printChatUsage() {
        print("""
        Usage: grok chat [options] [initial message...]

        Starts interactive chat mode. If an initial message is supplied, Grok sends it first and then keeps the prompt open.

        Options:
          --reasoning                 Enable reasoning mode
          --markdown, -m              Use markdown formatting in output
          --raw                       Show raw Markdown text in output
          --format <md|raw>           Choose output format
          --debug                     Show debug information
          --private                   Do not save the conversation
          --stream                    Stream responses
          --quiet                     Suppress UI/status output for piped raw scripting
          --model, --mode <mode>      Use auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId

        With --json, chat sends the initial message as one JSON result and exits.
        With --raw --quiet, piped chat writes assistant answers to stdout without prompts.
        """)
    }

    static func printMessageUsage() {
        print("""
        Usage: grok message [options] [message...]

        Sends one message to Grok and exits.

        Options:
          --reasoning                 Enable reasoning mode
          --markdown, -m              Use markdown formatting in output
          --raw                       Show raw Markdown text in output
          --json                      Emit scriptable JSON output
          --format <md|raw|json>      Choose output format
          --debug                     Show debug information
          --private                   Do not save the conversation
          --stream                    Stream responses
          --quiet                     Suppress UI/status output; useful with --raw in scripts
          --stdin                     Read the message from stdin
          --prompt-file <path>        Read the message from a UTF-8 text file
          --model, --mode <mode>      Use auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId

        Message input:
          - message args, --prompt-file, and --stdin are mutually exclusive
          - if no message args or prompt file are supplied and stdin is piped, stdin is used

        JSON mode writes only JSON to stdout. Human progress and debug banners are suppressed.
        With --stream --json, output is NDJSON: one JSON event object per line.
        With --raw --quiet, stdout contains only assistant answer text.
        """)
    }

    static func printListUsage() {
        print("""
        Usage: grok list [--json|--format json] [--conversation <conversationId>] [--debug]

        Lists saved conversations and optionally loads one by number.
        With JSON output, prints conversation JSON to stdout instead of opening the selector.
        """)
    }

    static func printModelsUsage() {
        print("""
        Usage: grok models [--json|--format json]

        Shows available Grok web modes. With JSON output, stdout contains one JSON result object.
        """)
    }

    static let recognizedTopLevelCommands: Set<String> = [
        "chat", "message", "auth", "help", "list", "models", "modes", "agents", "tasks",
        "skills", "workspaces", "workspace", "files", "test"
    ]

    static func normalizedTopLevelArguments(_ arguments: [String]) -> [String] {
        var leadingOptions: [String] = []
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]

            if isTopLevelFlagOption(arg) || isInlineTopLevelValueOption(arg) {
                leadingOptions.append(arg)
                index += 1
                continue
            }

            if isTopLevelValueOption(arg), index + 1 < arguments.count {
                leadingOptions.append(arg)
                leadingOptions.append(arguments[index + 1])
                index += 2
                continue
            }

            break
        }

        guard !leadingOptions.isEmpty, index < arguments.count else {
            return arguments
        }

        let candidate = arguments[index].lowercased()
        guard recognizedTopLevelCommands.contains(candidate) || isHelpArgument(candidate) else {
            return arguments
        }

        return [arguments[index]] + leadingOptions + Array(arguments.dropFirst(index + 1))
    }

    private static func isTopLevelFlagOption(_ arg: String) -> Bool {
        [
            "--reasoning",
            "--deep-search",
            "--no-search",
            "--markdown",
            "-m",
            "--raw",
            "--json",
            "--debug",
            "--no-custom-instructions",
            "--private",
            "--stream"
        ].contains(arg)
    }

    private static func isTopLevelValueOption(_ arg: String) -> Bool {
        ["--format", "--model", "--mode"].contains(arg)
    }

    private static func isInlineTopLevelValueOption(_ arg: String) -> Bool {
        arg.hasPrefix("--format=") || arg.hasPrefix("--model=") || arg.hasPrefix("--mode=")
    }


    static func main() async throws {
        // Simple command-line argument parsing
        let arguments = normalizedTopLevelArguments(Array(CommandLine.arguments.dropFirst())) // Drop the executable name

        if arguments.isEmpty {
            // No arguments provided, start interactive chat mode
            try await handleChatCommand(args: [])
            return
        }

        let command = arguments[0].lowercased() // Convert to lowercase for case-insensitive comparison
        let remainingArgs = Array(arguments.dropFirst())

        if command == "--help" || command == "-h" {
            if isJSONRequested(arguments) {
                try printHelpJSON()
            } else {
                showHelp()
            }
            return
        }

        // Check if first argument is a recognized command
        // If not a recognized command, treat all arguments as an initial message for chat
        if !recognizedTopLevelCommands.contains(command) {
            if isJSONRequested(arguments) {
                try await handleMessageCommand(args: arguments, exitOnError: true)
                return
            }
            try await handleChatCommand(args: arguments)
            return
        }

        // Process the command
        switch command {
        case "chat":
            try await handleChatCommand(args: remainingArgs, exitOnParseError: true)
        case "message":
            try await handleMessageCommand(args: remainingArgs, exitOnError: true)
        case "auth":
            try await handleAuthCommand(
                args: remainingArgs,
                exitOnGenerateFailure: true,
                exitOnUsageError: true,
                exitOnImportFailure: true
            )
        case "list":
            try await handleListCommand(args: remainingArgs, exitOnError: true)
        case "models", "modes":
            if isJSONRequested(remainingArgs) {
                try printJSONResult(
                    command: command == "modes" ? "modes" : "models",
                    category: "model_list",
                    data: AnyCodable(selectedModelJSON(currentMode: GrokCLIApp.shared.getCurrentMode()))
                )
            } else if containsHelpArgument(remainingArgs) {
                printModelsUsage()
                printAvailableModels(currentMode: GrokCLIApp.shared.getCurrentMode())
            } else {
                printAvailableModels(currentMode: GrokCLIApp.shared.getCurrentMode())
            }
        case "agents":
            try await handleAgentsCommand(args: remainingArgs, exitOnError: true)
        case "tasks":
            try await handleTasksCommand(args: remainingArgs, exitOnError: true)
        case "skills":
            try await handleSkillsCommand(args: remainingArgs, exitOnError: true)
        case "workspaces", "workspace":
            try await handleWorkspacesCommand(args: remainingArgs, exitOnError: true)
        case "files":
            try await handleFilesCommand(args: remainingArgs, exitOnError: true)
        case "test":
            var command = TestCommand()
            command.message = remainingArgs
            try await command.run()
        case "help":
            if isJSONRequested(remainingArgs) {
                try printHelpJSON()
            } else {
                showHelp()
            }
        default:
            print("Unknown command: \(command)")
            print("Run 'grok help' for usage information.")
        }
    }

}
