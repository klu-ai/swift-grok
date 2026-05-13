import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    enum InteractiveModelCommand {
        case select
        case set(String)
    }

    static func printAvailableModels(currentMode: GrokMode? = nil) {
        if let currentMode {
            print("Current model: \(currentMode.displayName) (\(currentMode.id))".cyan)
        }
        print("Available web modes:".cyan)
        for (index, mode) in GrokMode.knownModes.enumerated() {
            let marker = mode.id == currentMode?.id ? "✓ " : "  "
            let detail = mode.summary.isEmpty ? "" : " - \(mode.summary)"
            print("\(marker)\(index + 1). \(mode.displayName)".yellow + " (\(mode.id))\(detail)")
        }
        print("You can also pass a raw web modeId with --model.".blue)
    }

    static func printAvailableModelsJSON(currentMode: GrokMode) throws {
        try printJSONResult(
            command: "models",
            category: "model_list",
            data: AnyCodable(selectedModelJSON(currentMode: currentMode))
        )
    }

    static func interactiveModelCommand(from input: String) -> InteractiveModelCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first?.lowercased() else {
            return nil
        }

        let normalizedCommand = command.hasPrefix("/") ? String(command.dropFirst()) : command
        guard ["model", "models", "mode", "modes"].contains(normalizedCommand) else {
            return nil
        }

        guard parts.count > 1 else {
            return .select
        }

        let requestedMode = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return requestedMode.isEmpty ? .select : .set(requestedMode)
    }

    static func promptForModelSelection(currentMode: GrokMode) -> GrokMode? {
        printAvailableModels(currentMode: currentMode)
        print("Select model number/name, or press Enter to keep current: ".cyan, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return nil
        }

        if let selection = Int(input), selection >= 1, selection <= GrokMode.knownModes.count {
            return GrokMode.knownModes[selection - 1]
        }

        return GrokMode.resolve(input)
    }

}
