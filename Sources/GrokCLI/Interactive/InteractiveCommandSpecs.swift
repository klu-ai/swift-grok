import Foundation

extension GrokCLI {
    struct CommandSpec {
        let command: String
        let aliases: [String]
        let description: String
        let showsInEmptySlashMenu: Bool
    }
    static var interactiveCommandSpecs: [CommandSpec] {
        InteractiveCommandRegistry.slashCompletionSpecs()
    }
}
