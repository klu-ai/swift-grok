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

struct InputLineBuffer {
    private enum Segment: Equatable {
        case text(String)
        case pasted(display: String, content: String)

        var displayText: String {
            switch self {
            case .text(let text):
                text
            case .pasted(let display, _):
                display
            }
        }

        var actualText: String {
            switch self {
            case .text(let text):
                text
            case .pasted(_, let content):
                content
            }
        }
    }

    private var segments: [Segment]

    init(_ text: String = "") {
        segments = text.isEmpty ? [] : [.text(text)]
    }

    var display: String {
        segments.map(\.displayText).joined()
    }

    var renderedDisplay: String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                return text
            case .pasted(let display, _):
                return display.lightBlue
            }
        }.joined()
    }

    var actual: String {
        segments.map(\.actualText).joined()
    }

    var displayCount: Int {
        segments.reduce(0) { $0 + $1.displayText.count }
    }

    mutating func clear() {
        segments.removeAll()
    }

    mutating func replace(with text: String) {
        segments = text.isEmpty ? [] : [.text(text)]
    }

    mutating func replaceWithCommittedText(_ text: String) {
        if Self.shouldCollapsePastedContent(text) {
            segments = [.pasted(display: Self.pastePlaceholder(characterCount: text.count), content: text)]
        } else {
            replace(with: text)
        }
    }

    mutating func insertCharacter(_ character: Character, at cursorIndex: Int) -> Int {
        insertSegment(.text(String(character)), at: cursorIndex)
    }

    mutating func insertPastedContent(_ content: String, at cursorIndex: Int) -> Int {
        guard !content.isEmpty else { return clampedCursor(cursorIndex) }
        if Self.shouldCollapsePastedContent(content) {
            return insertSegment(
                .pasted(display: Self.pastePlaceholder(characterCount: content.count), content: content),
                at: cursorIndex
            )
        }
        return insertText(content, at: cursorIndex)
    }

    mutating func backspace(at cursorIndex: Int) -> Int {
        let clamped = clampedCursor(cursorIndex)
        guard clamped > 0 else { return 0 }
        return removeDisplayCharacter(at: clamped - 1, fallbackCursor: clamped - 1)
    }

    mutating func deleteForward(at cursorIndex: Int) -> Int {
        let clamped = clampedCursor(cursorIndex)
        guard clamped < displayCount else { return clamped }
        return removeDisplayCharacter(at: clamped, fallbackCursor: clamped)
    }

    private mutating func insertText(_ text: String, at cursorIndex: Int) -> Int {
        var cursor = clampedCursor(cursorIndex)
        for character in text {
            cursor = insertCharacter(character, at: cursor)
        }
        return cursor
    }

    private mutating func insertSegment(_ segment: Segment, at cursorIndex: Int) -> Int {
        let insertion = insertionPoint(at: cursorIndex)
        segments.insert(segment, at: insertion.segmentIndex)
        normalizeSegments()
        return insertion.cursorIndex + segment.displayText.count
    }

    private mutating func insertionPoint(at cursorIndex: Int) -> (segmentIndex: Int, cursorIndex: Int) {
        let clamped = clampedCursor(cursorIndex)
        var offset = 0

        for index in segments.indices {
            let displayText = segments[index].displayText
            let length = displayText.count
            let start = offset
            let end = offset + length

            if clamped <= start {
                return (index, clamped)
            }

            if clamped < end {
                switch segments[index] {
                case .text(let text):
                    let splitIndex = text.index(text.startIndex, offsetBy: clamped - start)
                    let before = String(text[..<splitIndex])
                    let after = String(text[splitIndex...])
                    var replacement: [Segment] = []
                    if !before.isEmpty {
                        replacement.append(.text(before))
                    }
                    if !after.isEmpty {
                        replacement.append(.text(after))
                    }
                    segments.replaceSubrange(index ... index, with: replacement)
                    return (index + (before.isEmpty ? 0 : 1), clamped)
                case .pasted:
                    segments.remove(at: index)
                    return (index, start)
                }
            }

            if clamped == end {
                return (segments.index(after: index), clamped)
            }

            offset = end
        }

        return (segments.count, clamped)
    }

    private mutating func removeDisplayCharacter(at displayIndex: Int, fallbackCursor: Int) -> Int {
        var offset = 0

        for index in segments.indices {
            let displayText = segments[index].displayText
            let length = displayText.count
            let start = offset
            let end = offset + length

            if displayIndex >= start && displayIndex < end {
                switch segments[index] {
                case .text(let text):
                    let removalIndex = text.index(text.startIndex, offsetBy: displayIndex - start)
                    var updated = text
                    updated.remove(at: removalIndex)
                    if updated.isEmpty {
                        segments.remove(at: index)
                    } else {
                        segments[index] = .text(updated)
                    }
                    normalizeSegments()
                    return fallbackCursor
                case .pasted:
                    segments.remove(at: index)
                    normalizeSegments()
                    return start
                }
            }

            offset = end
        }

        return clampedCursor(fallbackCursor)
    }

    private func clampedCursor(_ cursorIndex: Int) -> Int {
        max(0, min(cursorIndex, displayCount))
    }

    private mutating func normalizeSegments() {
        var normalized: [Segment] = []
        for segment in segments {
            switch segment {
            case .text(let text) where text.isEmpty:
                continue
            case .text(let text):
                if case .text(let previousText) = normalized.last {
                    normalized.removeLast()
                    normalized.append(.text(previousText + text))
                } else {
                    normalized.append(segment)
                }
            case .pasted:
                normalized.append(segment)
            }
        }
        segments = normalized
    }

    static func shouldCollapsePastedContent(_ content: String) -> Bool {
        content.count >= 128 || content.contains("\n") || content.contains("\r")
    }

    static func pastePlaceholder(characterCount: Int) -> String {
        "[Pasted content \(characterCount) \(characterCount == 1 ? "char" : "chars")]"
    }
}

struct InputTypeaheadSuggestion: Equatable {
    let display: String
    let insertText: String
    let description: String

    init(display: String, insertText: String? = nil, description: String = "") {
        self.display = display
        self.insertText = insertText ?? display
        self.description = description
    }
}

class InputReader {
    internal var history: [String] = []
    internal var historyIndex = 0
    private let commandSpecs: [GrokCLI.CommandSpec]
    private let showsPromptWhenNotTTY: Bool
    private let hudProvider: (() -> [String])?
    private let typeaheadSuggestionsProvider: ((String) -> [InputTypeaheadSuggestion])?
    private let typeaheadVersionProvider: (() -> Int)?
    private let typeaheadQueryDidChange: ((String) -> Void)?
    private var previousRenderedLines = 0
    private var previousCursorRow = 0
    private var selectedSuggestionIndex: Int?
    private let maxSuggestions = 32
    private let visibleSuggestionRows = 3
    private let bracketedPasteStartSequence = "200~"
    private let bracketedPasteEndBytes = Array("\u{001B}[201~".utf8)

    init(
        commandSpecs: [GrokCLI.CommandSpec] = GrokCLI.interactiveCommandSpecs,
        showsPromptWhenNotTTY: Bool = true,
        hudProvider: (() -> [String])? = nil,
        typeaheadSuggestionsProvider: ((String) -> [InputTypeaheadSuggestion])? = nil,
        typeaheadVersionProvider: (() -> Int)? = nil,
        typeaheadQueryDidChange: ((String) -> Void)? = nil
    ) {
        self.commandSpecs = commandSpecs
        self.showsPromptWhenNotTTY = showsPromptWhenNotTTY
        self.hudProvider = hudProvider
        self.typeaheadSuggestionsProvider = typeaheadSuggestionsProvider
        self.typeaheadVersionProvider = typeaheadVersionProvider
        self.typeaheadQueryDidChange = typeaheadQueryDidChange
    }

    func readLine(prompt: String = "") -> String? {
        readLine(prompt: prompt, prefill: "")
    }

    func readLine(prompt: String = "", prefill: String) -> String? {
        guard isatty(stdinFileDescriptor) == 1, isatty(stdoutFileDescriptor) == 1 else {
            if !prompt.isEmpty && showsPromptWhenNotTTY {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine(defaultValue: prefill)
        }

        var originalTermios = termios()
        guard tcgetattr(stdinFileDescriptor, &originalTermios) == 0 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine(defaultValue: prefill)
        }

        var rawTermios = originalTermios
        rawTermios.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &rawTermios.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 0
            controlCharacters[Int(VTIME)] = 1
        }

        guard tcsetattr(stdinFileDescriptor, TCSANOW, &rawTermios) == 0 else {
            if !prompt.isEmpty {
                print(prompt.green, terminator: "")
                fflush(stdout)
            }
            return readFallbackLine(defaultValue: prefill)
        }

        defer {
            disableBracketedPaste()
            tcsetattr(stdinFileDescriptor, TCSANOW, &originalTermios)
            clearRenderedBlock()
        }

        enableBracketedPaste()

        var buffer = InputLineBuffer(prefill)
        var cursorIndex = buffer.displayCount
        selectedSuggestionIndex = nil
        historyIndex = history.count
        var lastTypeaheadVersion = typeaheadVersionProvider?() ?? 0
        typeaheadQueryDidChange?(buffer.display)
        lastTypeaheadVersion = typeaheadVersionProvider?() ?? lastTypeaheadVersion
        render(prompt: prompt, buffer: buffer.display, renderedBuffer: buffer.renderedDisplay, cursorIndex: cursorIndex)

        while true {
            let byte: UInt8
            switch readInputByte() {
            case .byte(let value):
                byte = value
            case .timeout:
                let version = typeaheadVersionProvider?() ?? lastTypeaheadVersion
                if version != lastTypeaheadVersion {
                    lastTypeaheadVersion = version
                    render(prompt: prompt, buffer: buffer.display, renderedBuffer: buffer.renderedDisplay, cursorIndex: cursorIndex)
                }
                continue
            }

            switch byte {
            case 3:
                print("^C")
                processExit(130)
            case 4:
                if buffer.display.isEmpty {
                    print("")
                    return nil
                }
            case 21:
                buffer.clear()
                cursorIndex = 0
                selectedSuggestionIndex = nil
            case 9:
                applyCompletion(buffer: &buffer, cursorIndex: &cursorIndex)
            case 10, 13:
                if let shouldSubmit = acceptSelectedSuggestion(buffer: &buffer, cursorIndex: &cursorIndex) {
                    if shouldSubmit {
                        commitLine(prompt: prompt, buffer: buffer.renderedDisplay)
                        addToHistory(buffer.actual)
                        return buffer.actual
                    }
                    render(prompt: prompt, buffer: buffer.display, renderedBuffer: buffer.renderedDisplay, cursorIndex: cursorIndex)
                    continue
                }
                commitLine(prompt: prompt, buffer: buffer.renderedDisplay)
                addToHistory(buffer.actual)
                return buffer.actual
            case 27:
                handleEscapeSequence(buffer: &buffer, cursorIndex: &cursorIndex)
            case 127, 8:
                cursorIndex = buffer.backspace(at: cursorIndex)
                selectedSuggestionIndex = nil
            default:
                if byte >= 32 {
                    let scalar = UnicodeScalar(Int(byte))!
                    cursorIndex = buffer.insertCharacter(Character(scalar), at: cursorIndex)
                    selectedSuggestionIndex = nil
                }
            }

            typeaheadQueryDidChange?(buffer.display)
            lastTypeaheadVersion = typeaheadVersionProvider?() ?? lastTypeaheadVersion
            render(prompt: prompt, buffer: buffer.display, renderedBuffer: buffer.renderedDisplay, cursorIndex: cursorIndex)
        }
    }

    private func readFallbackLine(defaultValue: String = "") -> String? {
        if !defaultValue.isEmpty {
            addToHistory(defaultValue)
            return defaultValue
        }
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

    private enum InputByteRead {
        case byte(UInt8)
        case timeout
    }

    private func readInputByte() -> InputByteRead {
        var byte: UInt8 = 0
        let count = read(stdinFileDescriptor, &byte, 1)
        return count == 1 ? .byte(byte) : .timeout
    }

    private func readByte() -> UInt8? {
        guard case .byte(let byte) = readInputByte() else {
            return nil
        }
        return byte
    }

    private func enableBracketedPaste() {
        print("\u{001B}[?2004h", terminator: "")
        fflush(stdout)
    }

    private func disableBracketedPaste() {
        print("\u{001B}[?2004l", terminator: "")
        fflush(stdout)
    }

    private func handleEscapeSequence(buffer: inout InputLineBuffer, cursorIndex: inout Int) {
        guard let sequence = readControlSequence() else {
            return
        }

        switch sequence {
        case "A":
            if moveSuggestionSelection(delta: -1, buffer: buffer.display) {
                return
            }
            if let previous = getPreviousCommand() {
                buffer.replaceWithCommittedText(previous)
                cursorIndex = buffer.displayCount
            }
        case "B":
            if moveSuggestionSelection(delta: 1, buffer: buffer.display) {
                return
            }
            if let next = getNextCommand() {
                buffer.replaceWithCommittedText(next)
            } else {
                historyIndex = history.count
                buffer.clear()
            }
            cursorIndex = buffer.displayCount
        case "C":
            cursorIndex = min(cursorIndex + 1, buffer.displayCount)
        case "D":
            cursorIndex = max(cursorIndex - 1, 0)
        case "3~":
            cursorIndex = buffer.deleteForward(at: cursorIndex)
            selectedSuggestionIndex = nil
        case _ where sequence == bracketedPasteStartSequence:
            let pastedContent = readBracketedPasteContent()
            cursorIndex = buffer.insertPastedContent(pastedContent, at: cursorIndex)
            selectedSuggestionIndex = nil
        default:
            break
        }
    }

    private func readControlSequence() -> String? {
        guard let first = readByte(), first == UInt8(ascii: "[") else {
            return nil
        }

        var bytes: [UInt8] = []
        while let byte = readByte() {
            bytes.append(byte)
            if byte >= 0x40, byte <= 0x7E {
                break
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func readBracketedPasteContent() -> String {
        var pastedBytes: [UInt8] = []
        var possibleEndBytes: [UInt8] = []

        while let byte = readByte() {
            possibleEndBytes.append(byte)

            if possibleEndBytes == bracketedPasteEndBytes {
                return String(decoding: pastedBytes, as: UTF8.self)
            }

            while !bracketedPasteEndBytes.starts(with: possibleEndBytes),
                  !possibleEndBytes.isEmpty {
                pastedBytes.append(possibleEndBytes.removeFirst())
            }
        }

        pastedBytes.append(contentsOf: possibleEndBytes)
        return String(decoding: pastedBytes, as: UTF8.self)
    }

    private func applyCompletion(buffer: inout InputLineBuffer, cursorIndex: inout Int) {
        let display = buffer.display
        let suggestions = suggestions(for: display)
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
        if sharedPrefix.count > display.count {
            buffer.replace(with: sharedPrefix)
            cursorIndex = buffer.displayCount
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

    private func acceptSelectedSuggestion(buffer: inout InputLineBuffer, cursorIndex: inout Int) -> Bool? {
        let suggestions = suggestions(for: buffer.display)
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
        to buffer: inout InputLineBuffer,
        cursorIndex: inout Int,
        appendingTrailingSpace: Bool = true
    ) {
        var text = suggestion.insertText
        if appendingTrailingSpace, suggestion.appendsTrailingSpace, !text.hasSuffix(" ") {
            text += " "
        }
        buffer.replace(with: text)
        cursorIndex = buffer.displayCount
        selectedSuggestionIndex = nil
    }

    private struct Suggestion {
        let display: String
        let insertText: String
        let description: String
        let requiresArgument: Bool
        let appendsTrailingSpace: Bool
    }

    func completionSuggestionDisplays(for buffer: String) -> [String] {
        suggestions(for: buffer).map(\.display)
    }

    private func suggestions(for buffer: String) -> [Suggestion] {
        guard buffer.hasPrefix("/") else {
            return remoteSuggestions(for: buffer)
        }

        let normalizedInput = buffer.lowercased()
        var seen = Set<String>()
        var results: [Suggestion] = []

        for spec in commandSpecs {
            let canonical = spec.command

            if normalizedInput == "/", !spec.showsInEmptySlashMenu {
                continue
            }

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
                requiresArgument: canonical.contains("<"),
                appendsTrailingSpace: true
            ))
        }

        return results
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private func remoteSuggestions(for buffer: String) -> [Suggestion] {
        guard let typeaheadSuggestionsProvider else {
            return []
        }

        var seen = Set<String>()
        return typeaheadSuggestionsProvider(buffer)
            .filter { suggestion in
                let text = suggestion.insertText.trimmingCharacters(in: .whitespacesAndNewlines)
                return !text.isEmpty && seen.insert(text.lowercased()).inserted
            }
            .prefix(maxSuggestions)
            .map { suggestion in
                Suggestion(
                    display: suggestion.display,
                    insertText: suggestion.insertText,
                    description: suggestion.description,
                    requiresArgument: false,
                    appendsTrailingSpace: false
                )
            }
    }

    private func insertionText(for command: String) -> String {
        command
            .split(separator: " ")
            .prefix { !$0.hasPrefix("<") }
            .joined(separator: " ")
    }

    private func render(prompt: String, buffer: String, renderedBuffer: String, cursorIndex: Int) {
        clearRenderedBlock()

        let suggestions = suggestions(for: buffer)
        if let selectedSuggestionIndex, !suggestions.indices.contains(selectedSuggestionIndex) {
            self.selectedSuggestionIndex = nil
        }
        let hudLines = hudProvider?() ?? []
        for line in hudLines {
            print(line)
        }

        let terminalWidth = TerminalLayout.columns()
        if buffer.hasPrefix("/") {
            renderSlashCommandPrompt(
                prompt: prompt,
                buffer: buffer,
                renderedBuffer: renderedBuffer,
                cursorIndex: cursorIndex,
                suggestions: suggestions,
                hudLineCount: hudLines.count,
                width: terminalWidth
            )
            return
        }

        let reservedSuggestionRows = suggestions.isEmpty ? 0 : visibleSuggestionRows + 1
        if reservedSuggestionRows > 0 {
            renderSuggestionRows(suggestions, selectedIndex: selectedSuggestionIndex, width: terminalWidth)
        }

        let ghostSuffix = ghostSuffix(for: buffer, suggestions: suggestions)
        let renderedInput = renderedBuffer + dimmed(ghostSuffix)
        let promptText = prompt.green
        print("\(promptText)\(renderedInput)", terminator: "")

        let promptLength = TerminalLayout.visibleLength(prompt)
        let inputLength = promptLength + TerminalLayout.visibleLength(buffer) + ghostSuffix.count
        let inputRows = Self.wrappedLineCount(visibleLength: inputLength, width: terminalWidth)
        let targetPosition = Self.wrappedCursorPosition(
            visibleOffset: promptLength + cursorIndex,
            visibleLength: inputLength,
            width: terminalWidth
        )
        let currentPosition = Self.wrappedCursorPosition(
            visibleOffset: inputLength,
            visibleLength: inputLength,
            width: terminalWidth
        )
        let targetBlockRow = hudLines.count + reservedSuggestionRows + targetPosition.row
        let currentBlockRow = hudLines.count + reservedSuggestionRows + currentPosition.row
        let linesUp = max(0, currentBlockRow - targetBlockRow)

        previousRenderedLines = hudLines.count + inputRows + reservedSuggestionRows
        previousCursorRow = targetBlockRow

        if linesUp > 0 {
            print("\u{001B}[\(linesUp)A", terminator: "")
        }
        print("\r", terminator: "")
        if targetPosition.column > 0 {
            print("\u{001B}[\(targetPosition.column)C", terminator: "")
        }
        fflush(stdout)
    }

    private func renderSlashCommandPrompt(
        prompt: String,
        buffer: String,
        renderedBuffer: String,
        cursorIndex: Int,
        suggestions: [Suggestion],
        hudLineCount: Int,
        width: Int
    ) {
        let promptText = prompt.green
        print("\(promptText)\(renderedBuffer)", terminator: "")

        var suggestionFooterLines = 0
        if !suggestions.isEmpty {
            print("")
            let commandWidth = min(28, max(12, suggestions.map(\.display.count).max() ?? 12))
            for (index, suggestion) in suggestions.enumerated() {
                let paddedCommand = suggestion.display.padding(toLength: commandWidth, withPad: " ", startingAt: 0)
                let marker = index == selectedSuggestionIndex ? "> " : "  "
                let command = index == selectedSuggestionIndex ? paddedCommand.yellow.bold : paddedCommand.yellow
                let description = index == selectedSuggestionIndex ? suggestion.description.bold : suggestion.description
                let line = description.isEmpty ? "\(marker)\(command)" : "\(marker)\(command) \(description)"
                print(TerminalLayout.truncateEnd(line, width: width))
            }
            print(TerminalLayout.truncateEnd("tab complete  arrows select  enter run".blue, width: width))
            suggestionFooterLines = 1
        }

        let promptLength = TerminalLayout.visibleLength(prompt)
        let inputLength = promptLength + TerminalLayout.visibleLength(buffer)
        let inputRows = Self.wrappedLineCount(visibleLength: inputLength, width: width)
        let suggestionRows = suggestions.count + suggestionFooterLines
        let targetPosition = Self.wrappedCursorPosition(
            visibleOffset: promptLength + cursorIndex,
            visibleLength: inputLength,
            width: width
        )
        let currentPosition = Self.wrappedCursorPosition(
            visibleOffset: inputLength,
            visibleLength: inputLength,
            width: width
        )
        let targetBlockRow = hudLineCount + targetPosition.row
        let currentBlockRow = suggestions.isEmpty
            ? hudLineCount + currentPosition.row
            : hudLineCount + inputRows + suggestionRows
        let linesUp = max(0, currentBlockRow - targetBlockRow)

        previousRenderedLines = hudLineCount + inputRows + suggestionRows
        previousCursorRow = targetBlockRow

        if linesUp > 0 {
            print("\u{001B}[\(linesUp)A", terminator: "")
        }
        print("\r", terminator: "")
        if targetPosition.column > 0 {
            print("\u{001B}[\(targetPosition.column)C", terminator: "")
        }
        fflush(stdout)
    }

    private func renderSuggestionRows(_ suggestions: [Suggestion], selectedIndex: Int?, width: Int) {
        let windowStart = suggestionWindowStart(suggestionCount: suggestions.count, selectedIndex: selectedIndex)
        let commandWidth = max(12, suggestions.map(\.display.count).max() ?? 12)

        for row in 0..<visibleSuggestionRows {
            let index = windowStart + row
            guard suggestions.indices.contains(index) else {
                print("")
                continue
            }

            let suggestion = suggestions[index]
            let paddedCommand = suggestion.display.padding(toLength: commandWidth, withPad: " ", startingAt: 0)
            let isSelected = index == selectedIndex
            let marker = isSelected ? "> " : "  "
            let command = isSelected ? paddedCommand.yellow.bold : paddedCommand.yellow
            let description = isSelected ? suggestion.description.bold : suggestion.description
            let line = description.isEmpty ? "\(marker)\(command)" : "\(marker)\(command) \(description)"
            print(TerminalLayout.truncateEnd(line, width: width))
        }

        if suggestions.isEmpty {
            print("")
        } else {
            print(TerminalLayout.truncateEnd("tab complete  arrows select  enter run".blue, width: width))
        }
    }

    private func suggestionWindowStart(suggestionCount: Int, selectedIndex: Int?) -> Int {
        guard suggestionCount > visibleSuggestionRows else {
            return 0
        }

        guard let selectedIndex else {
            return 0
        }

        let clampedSelection = max(0, min(selectedIndex, suggestionCount - 1))
        if clampedSelection < visibleSuggestionRows {
            return 0
        }

        return min(clampedSelection - visibleSuggestionRows + 1, suggestionCount - visibleSuggestionRows)
    }

    private func ghostSuffix(for buffer: String, suggestions: [Suggestion]) -> String {
        guard !buffer.isEmpty else {
            return ""
        }

        let suggestion = selectedSuggestion(in: suggestions) ?? suggestions.first
        guard let suggestion else {
            return ""
        }

        let insertText = suggestion.insertText
        guard insertText.count > buffer.count,
              insertText.lowercased().hasPrefix(buffer.lowercased()) else {
            return ""
        }

        let suffixStart = insertText.index(insertText.startIndex, offsetBy: buffer.count)
        return String(insertText[suffixStart...])
    }

    private func dimmed(_ value: String) -> String {
        guard !value.isEmpty else {
            return ""
        }
        return "\u{001B}[2m\(value)\u{001B}[22m"
    }

    private func commitLine(prompt: String, buffer: String) {
        clearRenderedBlock()
        print("\(prompt.green)\(buffer)")
        fflush(stdout)
    }

    private func clearRenderedBlock() {
        guard previousRenderedLines > 0 else { return }
        print("\r", terminator: "")
        if previousCursorRow > 0 {
            print("\u{001B}[\(previousCursorRow)A", terminator: "")
            print("\r", terminator: "")
        }
        print("\u{001B}[J", terminator: "")
        previousRenderedLines = 0
        previousCursorRow = 0
    }

    static func wrappedLineCount(visibleLength: Int, width: Int) -> Int {
        let position = wrappedCursorPosition(
            visibleOffset: visibleLength,
            visibleLength: visibleLength,
            width: width
        )
        return max(1, position.row + 1)
    }

    static func wrappedCursorPosition(visibleOffset: Int, visibleLength: Int, width: Int) -> (row: Int, column: Int) {
        let normalizedWidth = max(1, width)
        let offset = max(0, visibleOffset)

        if offset == visibleLength, offset > 0, offset.isMultiple(of: normalizedWidth) {
            return ((offset - 1) / normalizedWidth, normalizedWidth - 1)
        }

        return (offset / normalizedWidth, offset % normalizedWidth)
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
