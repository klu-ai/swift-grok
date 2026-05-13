import Foundation
import GrokClient
import Rainbow

class OutputFormatter {
    var format: OutputFormat

    private var useMarkdown: Bool {
        format == .markdown
    }

    private var markdownBuffer = ""
    private var markdownInCodeBlock = false
    private var pendingTableLines: [String] = []
    private var transientStatusActive = false

    init(format: OutputFormat = .defaultFormat) {
        self.format = format
    }

    convenience init(useMarkdown: Bool) {
        self.init(format: useMarkdown ? .markdown : .raw)
    }

    func flushBuffer(resetMarkdownState: Bool = false) {
        guard useMarkdown else { return }

        flushCompleteMarkdownLines()
        if !markdownBuffer.isEmpty {
            printMarkdownLine(markdownBuffer)
            markdownBuffer = ""
        }
        flushPendingTable()
        if resetMarkdownState {
            markdownInCodeBlock = false
        }
        fflush(stdout)
    }

    func printThinkingStatus() {
        clearTransientStatus()
        print("Thinking".blue, terminator: "")
        transientStatusActive = true
        fflush(stdout)
    }

    func printStreamingResponse(_ stream: AsyncThrowingStream<ConversationResponse, Error>) async throws {
        let answerParser = GrokStreamMarkupParser()
        let thinkingParser = GrokStreamMarkupParser(hidesHiddenPreamble: false)
        var printedText = false
        var printedTrace = false
        var finalResponse: ConversationResponse?
        var sawNonFinalEvent = false
        var pendingAnswerEvents: [StreamDisplayEvent] = []

        func renderTraceLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            clearTransientStatus()
            if printedText {
                return
            }
            printedTrace = true
            let quotedLine = "> \(trimmed)"
            if trimmed.hasPrefix("Thinking:") {
                print(quotedLine.blue)
            } else {
                print(quotedLine.cyan)
            }
            fflush(stdout)
        }

        func traceLines(from events: [StreamDisplayEvent]) -> [String] {
            events.flatMap { event -> [String] in
                switch event {
                case .trace(let line):
                    return [line]
                case .text(let text):
                    return text
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        }

        func renderAnswerEvent(_ event: StreamDisplayEvent) {
            switch event {
            case .trace(let line):
                renderTraceLine(line)
            case .text(let text):
                renderText(text)
            }
        }

        func renderText(_ text: String) {
            guard !text.isEmpty else { return }
            clearTransientStatus()
            if !printedText {
                let prefix = printedTrace ? "\n" : ""
                print(prefix + "Grok:".green.bold)
                printedText = true
            }
            if useMarkdown {
                printMarkdownChunk(text)
            } else {
                print(text, terminator: "")
            }
            fflush(stdout)
        }

        func releasePendingAnswerIfReady(force: Bool = false) {
            guard !pendingAnswerEvents.isEmpty else { return }
            guard force || !thinkingParser.hasPendingContent else { return }

            let events = pendingAnswerEvents
            pendingAnswerEvents.removeAll()
            events.forEach(renderAnswerEvent)
        }

        func handleAnswerEvents(_ events: [StreamDisplayEvent]) {
            guard !events.isEmpty else { return }
            if !printedText && (thinkingParser.hasPendingContent || !pendingAnswerEvents.isEmpty) {
                pendingAnswerEvents.append(contentsOf: events)
                releasePendingAnswerIfReady()
                return
            }

            for event in events {
                renderAnswerEvent(event)
            }
        }

        func handleThinking(_ text: String) {
            let lines = traceLines(from: thinkingParser.consume(text))
            guard !lines.isEmpty else { return }
            for line in lines {
                renderTraceLine(line)
            }
            releasePendingAnswerIfReady()
        }

        for try await response in stream {
            if response.isSoftStop && response.message.isEmpty {
                continue
            }

            if response.isFinal {
                finalResponse = response
                if !sawNonFinalEvent && !printedText {
                    handleAnswerEvents(answerParser.consume(response.message))
                }
            } else if response.isThinking {
                sawNonFinalEvent = true
                handleThinking(response.message)
            } else {
                sawNonFinalEvent = true
                handleAnswerEvents(answerParser.consume(response.message))
            }
        }

        handleAnswerEvents(answerParser.finish())
        for line in traceLines(from: thinkingParser.finish()) {
            renderTraceLine(line)
        }
        releasePendingAnswerIfReady(force: true)

        clearTransientStatus()
        if printedText {
            flushBuffer(resetMarkdownState: true)
            print("")
        } else if transientStatusActive {
            print("")
        }

        if let finalResponse {
            printSources(webSearchResults: finalResponse.webSearchResults, xposts: finalResponse.xposts)
        }
    }

    private func clearTransientStatus() {
        guard transientStatusActive else { return }
        print("\r\u{001B}[2K", terminator: "")
        transientStatusActive = false
    }

    func printResponse(_ response: String, conversationId: String? = nil, responseId: String? = nil, debug: Bool = false, webSearchResults: [WebSearchResult]? = nil, xposts: [XPost]? = nil) {
        clearTransientStatus()
        print("\n" + "Grok:".green.bold)

        if useMarkdown {
            markdownBuffer = ""
            markdownInCodeBlock = false
            pendingTableLines.removeAll()
            printMarkdown(response)
            markdownInCodeBlock = false
            pendingTableLines.removeAll()
        } else {
            print(response)
        }

        let webSearchCount = webSearchResults?.count ?? 0
        let xpostsCount = xposts?.count ?? 0

        if webSearchCount > 0 || xpostsCount > 0 {
            print("\n" + "Sources:".cyan)
            if webSearchCount > 0 {
                print("Web search results: \(webSearchCount)".yellow)
            }
            if xpostsCount > 0 {
                print("X posts: \(xpostsCount)".yellow)
            }
        }

        if debug, let conversationId = conversationId, let responseId = responseId {
            print("\n" + "Debug Info:".cyan)
            print("Conversation ID: \(conversationId)".cyan)
            print("Response ID: \(responseId)".cyan)
        }

        print("")
        fflush(stdout)
    }

    func printStreamingChunk(_ chunk: String, isFirst: Bool, isLast: Bool) {
        clearTransientStatus()
        if isFirst {
            print("\n" + "Grok:".green.bold, terminator: "")
        }

        if useMarkdown {
            printMarkdownChunk(chunk)
            if isLast {
                flushBuffer(resetMarkdownState: true)
            }
        } else {
            print(chunk, terminator: "")
        }

        if isLast {
            let webSearchCount = GrokCLIApp.shared.getLastWebSearchResults()?.count ?? 0
            let xpostsCount = GrokCLIApp.shared.getLastXPosts()?.count ?? 0

            if webSearchCount > 0 || xpostsCount > 0 {
                print("\n" + "Sources:".cyan)
                if webSearchCount > 0 {
                    print("Web search results: \(webSearchCount)".yellow)
                }
                if xpostsCount > 0 {
                    print("X posts: \(xpostsCount)".yellow)
                }
            }

            print("")
        }

        fflush(stdout)
    }

    func printChunk(_ chunk: String, isFirst: Bool) {
        clearTransientStatus()
        if isFirst {
            print("\n" + "Grok:".green.bold, terminator: "")
        }
        if useMarkdown {
            printMarkdownChunk(chunk)
        } else {
            print(chunk, terminator: "")
        }
        fflush(stdout)
    }

    func printSources(webSearchResults: [WebSearchResult]?, xposts: [XPost]?) {
        clearTransientStatus()
        flushBuffer(resetMarkdownState: true)

        let webSearchCount = webSearchResults?.count ?? 0
        let xpostsCount = xposts?.count ?? 0
        if webSearchCount > 0 || xpostsCount > 0 {
            print("\n" + "Sources:".cyan)
            if webSearchCount > 0 {
                print("Web search results: \(webSearchCount)".yellow)
            }
            if xpostsCount > 0 {
                print("X posts: \(xpostsCount)".yellow)
            }
        }
        print("")
    }

    func printError(_ message: String) {
        print(message.red)
    }

    func printHelp() {
        print("""

        \("Basic Commands:".cyan.bold)
        - \("new".yellow): Start a new conversation thread
        - \("help".yellow): Show this help message
        - \("exit".yellow): Exit the app

        \("Slash Commands:".cyan.bold)
        Type commands with \("/".yellow), for example \("/help".yellow).
        - \("/new".yellow): Start a new conversation thread
        - \("/help".yellow): Show this help message
        - \("/list".yellow): List and load past conversations
        - \("/tasks".yellow): List or manage tasks
        - \("/agents".yellow): List or manage agent settings
        - \("/skills".yellow): List Grok skills
        - \("/auth".yellow): Refresh browser credentials
        - \("/workspaces".yellow): List or manage workspaces
        - \("/workspace".yellow): Choose the project for new chats
        - \("/files".yellow): List files/assets
        - \("/auth help".yellow): Show auth commands
        - \("/agents help".yellow): Show agent management usage
        - \("/agents show <id>".yellow): Show full agent instructions
        - \("/agents edit <id>".yellow): Edit agent instructions in $EDITOR
        - \("/tasks help".yellow): Show task command usage
        - \("/skills help".yellow): Show skills command usage
        - \("/workspaces help".yellow): Show workspace command usage
        - \("/files help".yellow): Show file command usage
        - \("/workspace select".yellow): Choose the project for new chats
        - \("/attach".yellow): Browse files and attach one to following messages
        - \("/attach upload <path>".yellow): Upload a local file and attach it
        - \("/attach clear".yellow): Remove all attached files
        - \("/reason [on|off]".yellow): Toggle reasoning mode on/off
        - \("/reasoning [on|off]".yellow): Alias for /reason
        - \("/model <mode>".yellow): Switch web model/mode
        - \("/mode, /models, /modes".yellow): Model command aliases
        - \("models <mode>".yellow): Common commands also work without the slash
        - \("/format [md|raw]".yellow): Toggle or choose Markdown/Raw output
        - \("/md, /markdown".yellow): Enable Markdown output
        - \("/raw [on|off]".yellow): Toggle raw Markdown output
        - \("/private [on|off]".yellow): Toggle private mode on/off
        - \("/stream [on|off]".yellow): Toggle streaming responses on/off
        - \("/reset-conversation".yellow): Clear the current conversation context
        - \("/special".yellow): Start a private special-mode conversation
        - \("/clear".yellow): Clear the screen
        - \("/cls".yellow): Alias for /clear
        - \("/exit, /quit".yellow): Exit the app

        \("Modes:".cyan.bold)
        - \("Reasoning".yellow): Enables Grok reasoning model for hard problems
        - \("Model".yellow): auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId
        - \("Private Mode".yellow): When enabled, conversations will not be saved
        - \("Streaming".yellow): Displays responses as they are generated
        - \("Output Format".yellow): Markdown is default; Raw preserves source Markdown
        - \("Agents".yellow): Configure instructions in Grok agent settings

        """)
    }

    // temporarily hidden from slash commands

    // temporarily hidden from modes

    //- \("Conversation Threading".yellow): Messages maintain context within the current conversation
    //

    func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }

    private func printMarkdownChunk(_ chunk: String) {
        markdownBuffer += chunk
        flushCompleteMarkdownLines()
    }

    private func flushCompleteMarkdownLines() {
        while let newlineIndex = markdownBuffer.firstIndex(of: "\n") {
            var line = String(markdownBuffer[..<newlineIndex])
            if line.last == "\r" {
                line.removeLast()
            }
            printMarkdownLine(line)
            markdownBuffer.removeSubrange(...newlineIndex)
        }
    }

    // Simple markdown formatter
    private func printMarkdown(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            printMarkdownLine(String(line))
        }
        flushPendingTable()
    }

    private func printMarkdownLine(_ lineStr: String) {
        if !markdownInCodeBlock {
            if isPotentialTableLine(lineStr) {
                pendingTableLines.append(lineStr)
                return
            }
            flushPendingTable()
        }

        renderMarkdownLine(lineStr)
    }

    private func renderMarkdownLine(_ lineStr: String) {
        if lineStr.hasPrefix("```") {
            markdownInCodeBlock.toggle()
            print(lineStr.magenta)
            return
        }

        if markdownInCodeBlock {
            print(lineStr.blue)
            return
        }

        if let heading = markdownHeading(in: lineStr) {
            switch heading.level {
            case 1:
                print(formatInlineMarkdown(heading.text).magenta.bold)
            case 2:
                print(formatInlineMarkdown(heading.text).cyan.bold)
            default:
                print(formatInlineMarkdown(heading.text).cyan)
            }
            return
        }

        if isHorizontalRule(lineStr) {
            print(String(repeating: "-", count: 48).magenta)
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^(\s*)([-*+])\s+\[([ xX])\]\s+(.*)$"#) {
            let checkbox = captures[3].lowercased() == "x" ? "☑" : "☐"
            print("\(captures[1])\(checkbox) \(formatInlineMarkdown(captures[4]))")
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^(\s*)(\d+[.)])\s+(.*)$"#) {
            print("\(captures[1])\(captures[2]) \(formatInlineMarkdown(captures[3]))")
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^(\s*)([-*+])\s+(.*)$"#) {
            print("\(captures[1])• \(formatInlineMarkdown(captures[3]))")
            return
        }

        if let captures = firstMatch(lineStr, pattern: #"^\s*>\s?(.*)$"#) {
            print(("> " + formatInlineMarkdown(captures[1])).green)
            return
        }

        print(formatInlineMarkdown(lineStr))
    }

    private func markdownHeading(in line: String) -> (level: Int, text: String)? {
        guard let captures = firstMatch(line, pattern: #"^(#{1,3})\s+(.+)$"#) else {
            return nil
        }
        return (captures[1].count, captures[2])
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard compact.count >= 3 else {
            return false
        }
        return compact.allSatisfy { $0 == "-" } ||
            compact.allSatisfy { $0 == "*" } ||
            compact.allSatisfy { $0 == "_" }
    }

    private func formatInlineMarkdown(_ input: String) -> String {
        var protected: [String] = []
        var text = input

        func protect(_ value: String) -> String {
            let token = "GROKMDTOKEN\(protected.count)PLACEHOLDER"
            protected.append(value)
            return token
        }

        text = replaceMatches(in: text, pattern: #"`([^`]+)`"#) { captures in
            protect(captures[1].cyan)
        }
        text = replaceMatches(in: text, pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#) { captures in
            let alt = captures[1].isEmpty ? "image" : captures[1]
            return protect("Image: \(alt) (\(captures[2]))".cyan)
        }
        text = replaceMatches(in: text, pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#) { captures in
            protect("\(captures[1].cyan) (\(captures[2]))")
        }
        text = replaceMatches(in: text, pattern: #"~~(.+?)~~"#) { captures in
            captures[1]
        }
        text = replaceMatches(in: text, pattern: #"\*\*\*(.+?)\*\*\*"#) { captures in
            captures[1].bold.italic
        }
        text = replaceMatches(in: text, pattern: #"\*\*(.+?)\*\*"#) { captures in
            captures[1].bold
        }
        text = replaceMatches(in: text, pattern: #"__(.+?)__"#) { captures in
            captures[1].bold
        }
        text = replaceMatches(in: text, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#) { captures in
            captures[1].italic
        }
        text = replaceMatches(in: text, pattern: #"(?<!_)_([^_\n]+)_(?!_)"#) { captures in
            captures[1].italic
        }

        for (index, value) in protected.enumerated() {
            text = text.replacingOccurrences(of: "GROKMDTOKEN\(index)PLACEHOLDER", with: value)
        }
        return text
    }

    private func isPotentialTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("|")
    }

    private func flushPendingTable() {
        guard !pendingTableLines.isEmpty else {
            return
        }

        let lines = pendingTableLines
        pendingTableLines.removeAll()

        guard lines.count >= 2,
              let header = parseTableRow(lines[0]),
              let alignments = parseTableSeparator(lines[1]) else {
            lines.forEach(renderMarkdownLine)
            return
        }

        let bodyRows = lines.dropFirst(2).compactMap(parseTableRow)
        let columnCount = max(
            header.count,
            alignments.count,
            bodyRows.map(\.count).max() ?? 0
        )
        guard columnCount > 0 else {
            lines.forEach(renderMarkdownLine)
            return
        }

        let normalizedAlignments = normalizedTableRow(alignments.map { $0 }, count: columnCount, defaultValue: .left)
        let formattedHeader = normalizedTableRow(header, count: columnCount).map(formatInlineMarkdown)
        let formattedRows = bodyRows.map { row in
            normalizedTableRow(row, count: columnCount).map(formatInlineMarkdown)
        }
        let widths = tableColumnWidths(rows: [formattedHeader] + formattedRows, columnCount: columnCount)

        print(renderTableRow(formattedHeader, widths: widths, alignments: normalizedAlignments))
        print(renderTableSeparator(widths: widths, alignments: normalizedAlignments))
        for row in formattedRows {
            print(renderTableRow(row, widths: widths, alignments: normalizedAlignments))
        }
    }

    private func firstMatch(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        return captureGroups(from: match, in: text)
    }

    private func replaceMatches(in text: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else {
            return text
        }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            let captures = captureGroups(from: match, in: text)
            result.replaceSubrange(range, with: transform(captures))
        }
        return result
    }

    private func captureGroups(from match: NSTextCheckingResult, in text: String) -> [String] {
        (0..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else {
                return ""
            }
            return String(text[range])
        }
    }
}
