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

    static func printAvailableModels(currentMode: GrokMode? = nil, modes: [GrokMode] = GrokMode.knownModes) {
        if let currentMode {
            print("Current model: \(currentMode.displayName) (\(currentMode.id))".cyan)
        }
        print("Available web modes:".cyan)
        for (index, mode) in modes.enumerated() {
            let marker = mode.id == currentMode?.id ? "✓ " : "  "
            print(modelListLine(mode: mode, index: index, marker: marker))
        }
        print("You can also pass a raw web modeId with --model.".blue)
    }

    static func printAvailableModelsJSON(currentMode: GrokMode, modes: [GrokMode] = GrokMode.knownModes) throws {
        try printJSONResult(
            command: "models",
            category: "model_list",
            data: AnyCodable(selectedModelJSON(currentMode: currentMode, modes: modes))
        )
    }

    static func selectableResolvedMode(_ rawValue: String, modes: [GrokMode]) -> GrokMode? {
        selectableMode(GrokMode.resolve(rawValue, modes: modes))
    }

    static func selectableMode(_ mode: GrokMode) -> GrokMode? {
        guard mode.isAvailable else {
            print("Model unavailable: \(mode.displayName) (\(mode.id)) - \(mode.unavailableDescription ?? "not available for this account")".yellow)
            return nil
        }
        return mode
    }

    private static func modelListLine(mode: GrokMode, index: Int?, marker: String) -> String {
        let number = index.map { "\($0 + 1). " } ?? ""
        let detail = mode.summary.isEmpty ? "" : " - \(mode.summary)"
        let unavailable = mode.unavailableDescription.map { " [unavailable: \($0)]" } ?? ""
        let line = "\(marker)\(number)\(mode.displayName) (\(mode.id))\(detail)\(unavailable)"
        return mode.isAvailable ? line.yellow : line.lightBlack
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

    static func promptForModelSelection(currentMode: GrokMode, modes: [GrokMode] = GrokMode.knownModes) -> GrokMode? {
        let items = modes.map { mode in
            PickerItem(
                id: mode.id,
                title: mode.displayName,
                subtitle: mode.id,
                preview: mode.summary.isEmpty ? mode.unavailableDescription : mode.summary,
                value: mode,
                isEnabled: mode.isAvailable,
                searchText: "\(mode.displayName) \(mode.id) \(mode.summary)"
            )
        }
        return InteractivePicker.select(
            title: "Select model",
            items: items,
            currentId: currentMode.id
        )
    }

    private enum ModelSelectionPromptResult {
        case selected(GrokMode)
        case cancelled
        case fallback
    }

    private static func promptForModelSelectionWithArrows(currentMode: GrokMode, modes: [GrokMode]) -> ModelSelectionPromptResult {
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
        var selectedIndex = initialModelSelectionIndex(currentMode: currentMode, modes: modes)

        defer {
            tcsetattr(modelSelectionStdinFileDescriptor, TCSANOW, &originalTermios)
            showCursor()
            fflush(stdout)
        }

        hideCursor()
        renderModelSelection(
            currentMode: currentMode,
            modes: modes,
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
                guard modes.indices.contains(selectedIndex), modes[selectedIndex].isAvailable else {
                    return .cancelled
                }
                return .selected(modes[selectedIndex])
            case UInt8(ascii: "j"):
                selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: 1, modes: modes)
            case UInt8(ascii: "k"):
                selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: -1, modes: modes)
            case UInt8(ascii: "q"):
                finishModelSelection(renderedLines: renderedLines)
                return .cancelled
            case 27:
                switch readModelSelectionEscapeSequence() {
                case .up:
                    selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: -1, modes: modes)
                case .down:
                    selectedIndex = nextModelSelectionIndex(from: selectedIndex, delta: 1, modes: modes)
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
                modes: modes,
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

    private static func initialModelSelectionIndex(currentMode: GrokMode, modes: [GrokMode]) -> Int {
        if let currentIndex = modes.firstIndex(where: { $0.id == currentMode.id }),
           modes[currentIndex].isAvailable {
            return currentIndex
        }
        return modes.firstIndex(where: \.isAvailable) ?? 0
    }

    private static func nextModelSelectionIndex(from currentIndex: Int, delta: Int, modes: [GrokMode]) -> Int {
        guard !modes.isEmpty else {
            return currentIndex
        }

        var candidate = currentIndex
        for _ in modes.indices {
            candidate = (candidate + delta + modes.count) % modes.count
            if modes[candidate].isAvailable {
                return candidate
            }
        }
        return currentIndex
    }

    private static func renderModelSelection(
        currentMode: GrokMode,
        modes: [GrokMode],
        selectedIndex: Int,
        renderedLines: inout Int
    ) {
        clearModelSelection(renderedLines: renderedLines)

        let lines = modelSelectionLines(currentMode: currentMode, modes: modes, selectedIndex: selectedIndex)
        for line in lines {
            print(line)
        }
        renderedLines = lines.count
        if renderedLines > 0 {
            print("\u{001B}[\(renderedLines)A", terminator: "")
        }
        fflush(stdout)
    }

    private static func modelSelectionLines(currentMode: GrokMode, modes: [GrokMode], selectedIndex: Int) -> [String] {
        var lines = [
            "Current model: \(currentMode.displayName) (\(currentMode.id))".cyan,
            "Available web modes:".cyan
        ]

        for (index, mode) in modes.enumerated() {
            let selector = index == selectedIndex ? "> " : "  "
            let currentMarker = mode.id == currentMode.id ? "✓ " : "  "
            lines.append(modelListLine(mode: mode, index: nil, marker: "\(selector)\(currentMarker)"))
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
