import Foundation
import Rainbow
#if os(Linux)
import Glibc
private let stdinFileDescriptor = STDIN_FILENO
private let stdoutFileDescriptor = STDOUT_FILENO
#else
import Darwin
private let stdinFileDescriptor = STDIN_FILENO
private let stdoutFileDescriptor = STDOUT_FILENO
#endif

#if os(Linux)
func processExit(_ code: Int32) -> Never {
    Glibc.exit(code)
}
#else
func processExit(_ code: Int32) -> Never {
    Darwin.exit(code)
}
#endif

class InputReader {
    internal var history: [String] = []
    internal var historyIndex = 0
    private let commandSpecs: [GrokCLI.CommandSpec]
    private let showsPromptWhenNotTTY: Bool
    private var previousRenderedLines = 0
    private var selectedSuggestionIndex: Int?
    private let maxSuggestions = 32

    init(
        commandSpecs: [GrokCLI.CommandSpec] = GrokCLI.interactiveCommandSpecs,
        showsPromptWhenNotTTY: Bool = true
    ) {
        self.commandSpecs = commandSpecs
        self.showsPromptWhenNotTTY = showsPromptWhenNotTTY
    }

    func readLine(prompt: String = "") -> String? {
        guard isatty(stdinFileDescriptor) == 1, isatty(stdoutFileDescriptor) == 1 else {
            if !prompt.isEmpty && showsPromptWhenNotTTY {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine()
        }

        var originalTermios = termios()
        guard tcgetattr(stdinFileDescriptor, &originalTermios) == 0 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine()
        }

        var rawTermios = originalTermios
        rawTermios.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &rawTermios.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }

        guard tcsetattr(stdinFileDescriptor, TCSANOW, &rawTermios) == 0 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine()
        }

        defer {
            tcsetattr(stdinFileDescriptor, TCSANOW, &originalTermios)
            clearRenderedBlock()
        }

        var buffer = ""
        var cursorIndex = 0
        selectedSuggestionIndex = nil
        historyIndex = history.count
        render(prompt: prompt, buffer: buffer, cursorIndex: cursorIndex)

        while true {
            guard let byte = readByte() else {
                return nil
            }

            switch byte {
            case 3:
                print("^C")
                processExit(130)
            case 4:
                if buffer.isEmpty {
                    print("")
                    return nil
                }
            case 21:
                buffer = ""
                cursorIndex = 0
                selectedSuggestionIndex = nil
            case 9:
                applyCompletion(buffer: &buffer, cursorIndex: &cursorIndex)
            case 10, 13:
                if let shouldSubmit = acceptSelectedSuggestion(buffer: &buffer, cursorIndex: &cursorIndex) {
                    if shouldSubmit {
                        commitLine(prompt: prompt, buffer: buffer)
                        addToHistory(buffer)
                        return buffer
                    }
                    render(prompt: prompt, buffer: buffer, cursorIndex: cursorIndex)
                    continue
                }
                commitLine(prompt: prompt, buffer: buffer)
                addToHistory(buffer)
                return buffer
            case 27:
                handleEscapeSequence(buffer: &buffer, cursorIndex: &cursorIndex)
            case 127, 8:
                if cursorIndex > 0 {
                    let index = buffer.index(buffer.startIndex, offsetBy: cursorIndex - 1)
                    buffer.remove(at: index)
                    cursorIndex -= 1
                    selectedSuggestionIndex = nil
                }
            default:
                if byte >= 32 {
                    let scalar = UnicodeScalar(Int(byte))!
                    let index = buffer.index(buffer.startIndex, offsetBy: cursorIndex)
                    buffer.insert(Character(scalar), at: index)
                    cursorIndex += 1
                    selectedSuggestionIndex = nil
                }
            }

            render(prompt: prompt, buffer: buffer, cursorIndex: cursorIndex)
        }
    }

    private func readFallbackLine() -> String? {
        guard let input = Swift.readLine() else {
            return nil
        }
        addToHistory(input)
        return input
    }

    private func addToHistory(_ input: String) {
        guard !input.isEmpty else { return }
        history.append(input)
        historyIndex = history.count
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let count = read(stdinFileDescriptor, &byte, 1)
        return count == 1 ? byte : nil
    }

    private func handleEscapeSequence(buffer: inout String, cursorIndex: inout Int) {
        guard let first = readByte(), first == UInt8(ascii: "["),
              let second = readByte() else {
            return
        }

        switch second {
        case UInt8(ascii: "A"):
            if moveSuggestionSelection(delta: -1, buffer: buffer) {
                return
            }
            if let previous = getPreviousCommand() {
                buffer = previous
                cursorIndex = buffer.count
            }
        case UInt8(ascii: "B"):
            if moveSuggestionSelection(delta: 1, buffer: buffer) {
                return
            }
            if let next = getNextCommand() {
                buffer = next
            } else {
                historyIndex = history.count
                buffer = ""
            }
            cursorIndex = buffer.count
        case UInt8(ascii: "C"):
            cursorIndex = min(cursorIndex + 1, buffer.count)
        case UInt8(ascii: "D"):
            cursorIndex = max(cursorIndex - 1, 0)
        default:
            break
        }
    }

    private func applyCompletion(buffer: inout String, cursorIndex: inout Int) {
        let suggestions = suggestions(for: buffer)
        guard !suggestions.isEmpty else { return }

        if let selectedSuggestion = selectedSuggestion(in: suggestions) {
            apply(suggestion: selectedSuggestion, to: &buffer, cursorIndex: &cursorIndex)
            return
        }

        if suggestions.count == 1 {
            apply(suggestion: suggestions[0], to: &buffer, cursorIndex: &cursorIndex)
            return
        }

        let sharedPrefix = longestCommonPrefix(suggestions.map(\.insertText))
        if sharedPrefix.count > buffer.count {
            buffer = sharedPrefix
            cursorIndex = buffer.count
        }
    }

    private func moveSuggestionSelection(delta: Int, buffer: String) -> Bool {
        let suggestions = suggestions(for: buffer)
        guard !suggestions.isEmpty else {
            selectedSuggestionIndex = nil
            return false
        }

        let currentIndex = selectedSuggestionIndex ?? (delta > 0 ? -1 : suggestions.count)
        let nextIndex = (currentIndex + delta + suggestions.count) % suggestions.count
        selectedSuggestionIndex = nextIndex
        return true
    }

    private func acceptSelectedSuggestion(buffer: inout String, cursorIndex: inout Int) -> Bool? {
        let suggestions = suggestions(for: buffer)
        guard let selectedSuggestion = selectedSuggestion(in: suggestions) else {
            return nil
        }
        let shouldSubmit = !selectedSuggestion.requiresArgument
        apply(
            suggestion: selectedSuggestion,
            to: &buffer,
            cursorIndex: &cursorIndex,
            appendingTrailingSpace: !shouldSubmit
        )
        selectedSuggestionIndex = nil
        return shouldSubmit
    }

    private func selectedSuggestion(in suggestions: [Suggestion]) -> Suggestion? {
        guard let selectedSuggestionIndex,
              suggestions.indices.contains(selectedSuggestionIndex) else {
            return nil
        }
        return suggestions[selectedSuggestionIndex]
    }

    private func apply(
        suggestion: Suggestion,
        to buffer: inout String,
        cursorIndex: inout Int,
        appendingTrailingSpace: Bool = true
    ) {
        buffer = suggestion.insertText
        if appendingTrailingSpace, !buffer.hasSuffix(" ") {
            buffer += " "
        }
        cursorIndex = buffer.count
        selectedSuggestionIndex = nil
    }

    private struct Suggestion {
        let display: String
        let insertText: String
        let description: String
        let requiresArgument: Bool
    }

    private func suggestions(for buffer: String) -> [Suggestion] {
        guard buffer.hasPrefix("/") else { return [] }

        let normalizedInput = buffer.lowercased()
        var seen = Set<String>()
        var results: [Suggestion] = []

        for spec in commandSpecs {
            let canonical = spec.command

            if normalizedInput == "/", canonical.contains(" ") {
                continue
            }

            let allNames = [canonical] + spec.aliases
            let matches = allNames.contains { name in
                let normalizedName = name.lowercased()
                return normalizedName.hasPrefix(normalizedInput) ||
                    normalizedInput.hasPrefix(normalizedName + " ")
            }

            guard matches, seen.insert(canonical).inserted else {
                continue
            }

            results.append(Suggestion(
                display: canonical,
                insertText: insertionText(for: canonical),
                description: spec.description,
                requiresArgument: canonical.contains("<")
            ))
        }

        return results
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private func insertionText(for command: String) -> String {
        command
            .split(separator: " ")
            .prefix { !$0.hasPrefix("<") }
            .joined(separator: " ")
    }

    private func render(prompt: String, buffer: String, cursorIndex: Int) {
        clearRenderedBlock()

        let suggestions = suggestions(for: buffer)
        if let selectedSuggestionIndex, !suggestions.indices.contains(selectedSuggestionIndex) {
            self.selectedSuggestionIndex = nil
        }
        let promptText = prompt.green
        print("\(promptText)\(buffer)", terminator: "")

        if !suggestions.isEmpty {
            print("")
            let commandWidth = min(28, max(12, suggestions.map(\.display.count).max() ?? 12))
            for (index, suggestion) in suggestions.enumerated() {
                let paddedCommand = suggestion.display.padding(toLength: commandWidth, withPad: " ", startingAt: 0)
                let marker = index == selectedSuggestionIndex ? "> " : "  "
                let command = index == selectedSuggestionIndex ? paddedCommand.yellow.bold : paddedCommand.yellow
                let description = index == selectedSuggestionIndex ? suggestion.description.bold : suggestion.description
                print("\(marker)\(command) \(description)")
            }
        }

        previousRenderedLines = 1 + suggestions.count
        let linesUp = suggestions.isEmpty ? 0 : suggestions.count + 1
        if linesUp > 0 {
            print("\u{001B}[\(linesUp)A", terminator: "")
        }
        print("\r", terminator: "")
        let cursorColumn = visibleLength(prompt) + cursorIndex
        if cursorColumn > 0 {
            print("\u{001B}[\(cursorColumn)C", terminator: "")
        }
        fflush(stdout)
    }

    private func commitLine(prompt: String, buffer: String) {
        clearRenderedBlock()
        print("\(prompt.green)\(buffer)")
        fflush(stdout)
    }

    private func clearRenderedBlock() {
        guard previousRenderedLines > 0 else { return }
        print("\r", terminator: "")
        print("\u{001B}[J", terminator: "")
        previousRenderedLines = 0
    }

    private func visibleLength(_ string: String) -> Int {
        string.count
    }

    private func longestCommonPrefix(_ values: [String]) -> String {
        guard var prefix = values.first else { return "" }
        for value in values.dropFirst() {
            while !value.hasPrefix(prefix), !prefix.isEmpty {
                prefix.removeLast()
            }
        }
        return prefix
    }

    // Basic history functionality - to be expanded with arrow key navigation in the future
    func getPreviousCommand() -> String? {
        guard !history.isEmpty, historyIndex > 0 else {
            return nil
        }

        historyIndex -= 1
        return history[historyIndex]
    }

    func getNextCommand() -> String? {
        guard !history.isEmpty, historyIndex < history.count - 1 else {
            return nil
        }

        historyIndex += 1
        return history[historyIndex]
    }
}
