import Foundation

extension GrokCLI {
    struct CommandSpec {
        let command: String
        let aliases: [String]
        let description: String
    }


    static var interactiveCommandSpecs: [CommandSpec] {
        [
        CommandSpec(command: "/new", aliases: [], description: "Start a new conversation thread"),
        CommandSpec(command: "/help", aliases: [], description: "Show interactive command help"),
        CommandSpec(command: "/exit", aliases: ["/quit"], description: "Exit the app"),
        CommandSpec(command: "/list", aliases: [], description: "List and load saved conversations"),
        CommandSpec(command: "/model", aliases: ["/mode", "/models", "/modes"], description: "Switch the active model or open the model picker"),
        CommandSpec(command: "/reason", aliases: ["/reasoning"], description: "Toggle reasoning mode"),
        CommandSpec(command: "/stream", aliases: [], description: "Toggle streaming responses"),
        CommandSpec(command: "/format", aliases: ["/md", "/markdown", "/raw"], description: "Toggle Markdown/Raw output"),
        CommandSpec(command: "/private", aliases: [], description: "Toggle private mode"),
        CommandSpec(command: "/attach", aliases: [], description: "Browse files and attach one to following messages"),
        CommandSpec(command: "/attach upload <path>", aliases: [], description: "Upload a local file and attach it"),
        CommandSpec(command: "/attach clear", aliases: [], description: "Remove all attached files"),
        CommandSpec(command: "/audio <path>", aliases: [], description: "Transcribe audio, edit the text, then send"),
        CommandSpec(command: "/audio-send <path>", aliases: [], description: "Transcribe audio and send immediately"),
        CommandSpec(command: "/transcribe <path>", aliases: [], description: "Transcribe audio and print the text"),
        CommandSpec(command: "/files", aliases: [], description: "List or upload assets"),
        CommandSpec(command: "/workspaces", aliases: ["/workspace"], description: "List or manage workspaces"),
        CommandSpec(command: "/workspace select", aliases: ["/workspaces select"], description: "Choose the project for new chats"),
        CommandSpec(command: "/tasks", aliases: [], description: "Manage tasks"),
        CommandSpec(command: "/skills", aliases: [], description: "List Grok skills"),
        CommandSpec(command: "/agents", aliases: [], description: "Manage agent settings"),
        CommandSpec(command: "/agents show <id>", aliases: ["/agents view <id>"], description: "Show full agent instructions"),
        CommandSpec(command: "/agents edit <id>", aliases: [], description: "Edit agent instructions"),
        CommandSpec(command: "/auth", aliases: [], description: "Generate or import credentials"),
        CommandSpec(command: "/reset-conversation", aliases: [], description: "Clear the current conversation context"),
        CommandSpec(command: "/clear", aliases: ["/cls"], description: "Clear the screen"),
        CommandSpec(command: "/special", aliases: [], description: "Start a private special-mode conversation")
        ]
    }
}
