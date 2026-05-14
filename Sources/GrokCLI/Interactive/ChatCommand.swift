import ArgumentParser
import Foundation
import GrokClient
import Rainbow

struct ChatCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive chat session with Grok"
    )
//    static let hiddenMode = """
//    You are a highly capable, thoughtful, and precise assistant. Your goal is to deeply understand the user's intent, ask clarifying questions when needed, think step-by-step through complex problems, provide clear and accurate answers, and proactively anticipate helpful follow-up information. Always prioritize being truthful, nuanced, insightful, and efficient, tailoring your responses specifically to the user's needs and preferences. If conversational dialogue, be more human. when possible, use brevity.
//    """

    @OptionGroup var options: GrokCommandOptions

    @Argument(parsing: .remaining, help: "Optional initial message to send to Grok")
    var initialMessage: [String] = []

    // Print the current settings status line
    static func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode()) {
        GrokCLI.printSettingsStatus(
            currentReasoning: currentReasoning,
            currentDeepSearch: currentDeepSearch,
            currentNoCustomInstructions: currentNoCustomInstructions,
            currentNoSearch: currentNoSearch,
            currentPrivate: currentPrivate,
            currentStream: currentStream,
            currentFormat: currentFormat,
            currentMode: currentMode
        )
    }

    // Print the current settings status line
    func printSettingsStatus(currentReasoning: Bool, currentDeepSearch: Bool, currentNoCustomInstructions: Bool, currentNoSearch: Bool, currentPrivate: Bool, currentStream: Bool, currentFormat: OutputFormat = .defaultFormat, currentMode: GrokMode = GrokCLIApp.shared.getCurrentMode()) {
        Self.printSettingsStatus(
            currentReasoning: currentReasoning,
            currentDeepSearch: currentDeepSearch,
            currentNoCustomInstructions: currentNoCustomInstructions,
            currentNoSearch: currentNoSearch,
            currentPrivate: currentPrivate,
            currentStream: currentStream,
            currentFormat: currentFormat,
            currentMode: currentMode
        )
    }
}
