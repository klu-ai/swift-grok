import Foundation
import GrokClient
import Rainbow
#if os(Linux)
import Glibc
private let modelSelectionStdinFileDescriptor = STDIN_FILENO
#else
import Darwin
private let modelSelectionStdinFileDescriptor = STDIN_FILENO
#endif

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
        guard stdinIsTTY(), stdoutIsTTY() else {
            return promptForModelSelectionByText(currentMode: currentMode)
        }

        switch promptForModelSelectionWithArrows(currentMode: currentMode) {
        case .selected(let mode):
            return mode
        case .cancelled:
            return nil
        case .fallback:
            return promptForModelSelectionByText(currentMode: currentMode)
        }
    }

    private static func promptForModelSelectionByText(currentMode: GrokMode) -> GrokMode? {
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

    private enum ModelSelectionPromptResult {
        case selected(GrokMode)
        case cancelled
        case fallback
    }

    private static func promptForModelSelectionWithArrows(currentMode: GrokMode) -> ModelSelectionPromptResult {
        var originalTermios = termios()
        guard tcgetattr(modelSelectionStdinFileDescriptor, &originalTermios) == 0 else {
            return .fallback
        }

        var rawTermios = originalTermios
        rawTermios.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &rawTermios.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 0
            controlCharacters[Int(VTIME)] = 1
        }

        guard tcsetattr(modelSelectionStdinFileDescriptor, TCSANOW, &rawTermios) == 0 else {
            return .fallback
        }

        var renderedLines = 0
        var selectedIndex = GrokMode.knownModes.firstIndex { $0.id == currentMode.id } ?? 0

        defer {
            tcsetattr(modelSelectionStdinFileDescriptor, TCSANOW, &originalTermios)
            showCursor()
            fflush(stdout)
        }

        hideCursor()
        renderModelSelection(
            currentMode: currentMode,
            selectedIndex: selectedIndex,
            renderedLines: &renderedLines
        )

        while true {
            guard let byte = readModelSelectionByte() else {
                continue
            }

            switch byte {
            case 3:
                print("^C")
                processExit(130)
            case 4:
                finishModelSelection(renderedLines: renderedLines)
                return .cancelled
            case 10, 13:
                finishModelSelection(renderedLines: renderedLines)
                return .selected(GrokMode.knownModes[selectedIndex])
            case UInt8(ascii: "j"):
                selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: 1)
            case UInt8(ascii: "k"):
                selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: -1)
            case UInt8(ascii: "q"):
                finishModelSelection(renderedLines: renderedLines)
                return .cancelled
            case 27:
                switch readModelSelectionEscapeSequence() {
                case .up:
                    selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: -1)
                case .down:
                    selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: 1)
                case .cancelled:
                    finishModelSelection(renderedLines: renderedLines)
                    return .cancelled
                case .none:
                    break
                }
            default:
                break
            }

            renderModelSelection(
                currentMode: currentMode,
                selectedIndex: selectedIndex,
                renderedLines: &renderedLines
            )
        }
    }

    private enum ModelSelectionEscapeSequence {
        case up
        case down
        case cancelled
        case none
    }

    private static func readModelSelectionEscapeSequence() -> ModelSelectionEscapeSequence {
        guard let first = readModelSelectionByte() else {
            return .cancelled
        }
        guard first == UInt8(ascii: "[") else {
            return .none
        }
        guard let second = readModelSelectionByte() else {
            return .none
        }

        switch second {
        case UInt8(ascii: "A"):
            return .up
        case UInt8(ascii: "B"):
            return .down
        default:
            return .none
        }
    }

    private static func nextModelSelectionIndex(from currentIndex: Int, delta: Int) -> Int {
        let count = GrokMode.knownModes.count
        return (currentIndex + delta + count) % count
    }

    private static func renderModelSelection(
        currentMode: GrokMode,
        selectedIndex: Int,
        renderedLines: inout Int
    ) {
        clearModelSelection(renderedLines: renderedLines)

        let lines = modelSelectionLines(currentMode: currentMode, selectedIndex: selectedIndex)
        for line in lines {
            print(line)
        }
        renderedLines = lines.count
        if renderedLines > 0 {
            print("\u{001B}[\(renderedLines)A", terminator: "")
        }
        fflush(stdout)
    }

    private static func modelSelectionLines(currentMode: GrokMode, selectedIndex: Int) -> [String] {
        var lines = [
            "Current model: \(currentMode.displayName) (\(currentMode.id))".cyan,
            "Available web modes:".cyan
        ]

        for (index, mode) in GrokMode.knownModes.enumerated() {
            let selector = index == selectedIndex ? "> " : "  "
            let currentMarker = mode.id == currentMode.id ? "✓ " : "  "
            let detail = mode.summary.isEmpty ? "" : " - \(mode.summary)"
            let name = "\(mode.displayName)".yellow
            lines.append("\(selector)\(currentMarker)\(name) (\(mode.id))\(detail)")
        }

        lines.append("Use up/down arrows to select, Enter to confirm, q to cancel.".blue)
        return lines
    }

    private static func finishModelSelection(renderedLines: Int) {
        guard renderedLines > 0 else { return }
        print("\u{001B}[\(renderedLines)B", terminator: "")
        print("\r", terminator: "")
        fflush(stdout)
    }

    private static func clearModelSelection(renderedLines: Int) {
        guard renderedLines > 0 else { return }
        print("\r", terminator: "")
        print("\u{001B}[J", terminator: "")
    }

    private static func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
    }

    private static func showCursor() {
        print("\u{001B}[?25h", terminator: "")
    }

    private static func readModelSelectionByte() -> UInt8? {
        var byte: UInt8 = 0
        let count = read(modelSelectionStdinFileDescriptor, &byte, 1)
        return count == 1 ? byte : nil
    }

}
