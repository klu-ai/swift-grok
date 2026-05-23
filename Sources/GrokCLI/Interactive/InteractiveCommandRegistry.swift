import Foundation

extension GrokCLI {
    enum InteractiveCommandCategory: String, CaseIterable {
        case session = "Session"
        case model = "Model"
        case files = "Files"
        case workspace = "Workspace"
        case library = "Library"
        case auth = "Auth"
        case audio = "Audio"
        case utility = "Utility"
    }

    struct InteractiveCommandSpec {
        let command: String
        let aliases: [String]
        let usage: String
        let description: String
        let category: InteractiveCommandCategory
        let acceptsBare: Bool
        let requiresArgument: Bool
        let showsInHelp: Bool
        let showsInSlashCompletion: Bool
        let showsInEmptySlashMenu: Bool

        init(
            command: String,
            aliases: [String] = [],
            usage: String? = nil,
            description: String,
            category: InteractiveCommandCategory,
            acceptsBare: Bool = true,
            requiresArgument: Bool = false,
            showsInHelp: Bool = true,
            showsInSlashCompletion: Bool = true,
            showsInEmptySlashMenu: Bool = true
        ) {
            self.command = command
            self.aliases = aliases
            self.usage = usage ?? command
            self.description = description
            self.category = category
            self.acceptsBare = acceptsBare
            self.requiresArgument = requiresArgument
            self.showsInHelp = showsInHelp
            self.showsInSlashCompletion = showsInSlashCompletion
            self.showsInEmptySlashMenu = showsInEmptySlashMenu
        }
    }

    enum InteractiveCommandRegistry {
        static let allCommands: [InteractiveCommandSpec] = [
            InteractiveCommandSpec(command: "/model", aliases: ["/mode", "/models", "/modes"], usage: "/model [mode|list]", description: "Switch the active model", category: .model),
            InteractiveCommandSpec(command: "/new", description: "Start a new conversation thread", category: .session),
            InteractiveCommandSpec(command: "/help", description: "Show interactive command help", category: .utility),
            InteractiveCommandSpec(command: "/exit", aliases: ["/quit"], description: "Exit the app", category: .utility),
            InteractiveCommandSpec(command: "/resume", aliases: ["/list"], description: "Resume a saved conversation", category: .session),
            InteractiveCommandSpec(command: "/search", usage: "/search <query>", description: "Search saved conversations", category: .session, requiresArgument: true),
            InteractiveCommandSpec(command: "/goal", usage: "/goal [objective|pause|resume|clear|complete]", description: "Run a durable objective until completion", category: .session),
            InteractiveCommandSpec(command: "/share", description: "Copy current conversation share link", category: .session),
            InteractiveCommandSpec(command: "/limits", description: "Show current rate limits for the active model", category: .model),
            InteractiveCommandSpec(command: "/stream", usage: "/stream [on|off]", description: "Toggle streaming responses", category: .model, showsInEmptySlashMenu: false),
            InteractiveCommandSpec(command: "/typeahead", usage: "/typeahead [on|off]", description: "Toggle web typeahead suggestions", category: .utility),
            InteractiveCommandSpec(command: "/format", aliases: ["/md", "/markdown", "/raw"], usage: "/format [md|raw]", description: "Toggle Markdown/Raw output", category: .model),
            InteractiveCommandSpec(command: "/private", usage: "/private [on|off]", description: "Toggle private mode", category: .session),
            InteractiveCommandSpec(command: "/attach", usage: "/attach [fileId|list]", description: "Browse files and attach one to following messages", category: .files),
            InteractiveCommandSpec(command: "/attach upload <path>", description: "Upload a local file and attach it", category: .files, requiresArgument: true),
            InteractiveCommandSpec(command: "/attach clear", description: "Remove all attached files", category: .files),
            InteractiveCommandSpec(command: "/audio", usage: "/audio [path]", description: "Record audio, edit the transcript, then send", category: .audio),
            InteractiveCommandSpec(command: "/audio <path>", aliases: ["/audio file <path>"], description: "Transcribe audio, edit the text, then send", category: .audio, requiresArgument: true),
            InteractiveCommandSpec(command: "/audio send <path>", aliases: ["/audio-send <path>"], description: "Transcribe audio and send immediately", category: .audio, requiresArgument: true),
            InteractiveCommandSpec(command: "/transcribe <path>", description: "Transcribe audio and print the text", category: .audio, requiresArgument: true),
            InteractiveCommandSpec(command: "/files", usage: "/files [list|upload|delete]", description: "List or upload assets", category: .files),
            InteractiveCommandSpec(command: "/workspace", aliases: ["/workspaces"], description: "Choose the project for new chats", category: .workspace),
            InteractiveCommandSpec(command: "/tasks", usage: "/tasks [list|inactive|select|show|results|create|archive]", description: "Manage tasks", category: .library),
            InteractiveCommandSpec(command: "/skills", usage: "/skills [list|mine|user]", description: "List Grok skills", category: .library),
            InteractiveCommandSpec(command: "/skill create", usage: "/skill create <prompt>", description: "Create a Grok skill from a prompt", category: .library, acceptsBare: false, requiresArgument: true),
            InteractiveCommandSpec(command: "/agents", usage: "/agents [list|show|edit|set]", description: "Manage agent settings", category: .library),
            InteractiveCommandSpec(command: "/agents show <id>", aliases: ["/agents view <id>"], description: "Show full agent instructions", category: .library, requiresArgument: true),
            InteractiveCommandSpec(command: "/agents edit <id>", description: "Edit agent instructions", category: .library, requiresArgument: true),
            InteractiveCommandSpec(command: "/auth", usage: "/auth [generate|import|oauth|help]", description: "Manage credentials", category: .auth),
            InteractiveCommandSpec(command: "/oauth", usage: "/oauth [login|status|verify]", description: "Manage xAI OAuth credentials", category: .auth),
            InteractiveCommandSpec(command: "/delete", usage: "/delete [--yes]", description: "Delete current conversation", category: .session),
            InteractiveCommandSpec(command: "/clear", aliases: ["/cls"], description: "Clear the screen", category: .utility)
//            InteractiveCommandSpec(command: "/special", description: "Start a private special-mode conversation", category: .session, showsInHelp: false, showsInEmptySlashMenu: false)
        ]

        static var visibleCommands: [InteractiveCommandSpec] {
            allCommands.filter(\.showsInHelp)
        }

        static func slashCompletionSpecs() -> [CommandSpec] {
            allCommands.filter(\.showsInSlashCompletion).map {
                CommandSpec(
                    command: $0.command,
                    aliases: $0.aliases,
                    description: $0.description,
                    showsInEmptySlashMenu: $0.showsInEmptySlashMenu
                )
            }
        }

        static func helpLines() -> [String] {
            var lines: [String] = []
            for category in InteractiveCommandCategory.allCases {
                let commands = visibleCommands.filter { $0.category == category }
                guard !commands.isEmpty else { continue }
                lines.append("\n\(category.rawValue):")
                for spec in commands {
                    lines.append("  \(spec.usage.padding(toLength: 24, withPad: " ", startingAt: 0)) \(spec.description)")
                }
            }
            return lines
        }

        static func nearestCommand(to rawValue: String) -> InteractiveCommandSpec? {
            let query = rawValue.hasPrefix("/") ? rawValue : "/\(rawValue)"
            return allCommands
                .flatMap { spec in ([spec.command] + spec.aliases).map { (spec, $0) } }
                .compactMap { spec, candidate -> (InteractiveCommandSpec, Int)? in
                    guard let score = FuzzyMatcher.score(query: query, text: candidate) else { return nil }
                    return (spec, score)
                }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0.command.count < rhs.0.command.count
                    }
                    return lhs.1 > rhs.1
                }
                .first?
                .0
        }
    }
}
