import Foundation

enum StreamDisplayEvent {
    case text(String)
    case trace(String)
    case activity(ToolActivityEvent)
}

final class GrokStreamMarkupParser {
    private let hiddenPreamble = "Thinking about your request"
    private let internalTagPrefixes = [
        "<xai:",
        "</xai:",
        "<grok:",
        "</grok:"
    ]
    private let hidesHiddenPreamble: Bool
    private var buffer = ""
    private var emittedTraceLines = Set<String>()

    init(hidesHiddenPreamble: Bool = true) {
        self.hidesHiddenPreamble = hidesHiddenPreamble
    }

    func consume(_ chunk: String) -> [StreamDisplayEvent] {
        buffer += chunk
        return drain(final: false)
    }

    func finish() -> [StreamDisplayEvent] {
        drain(final: true)
    }

    var hasPendingContent: Bool {
        !buffer.isEmpty
    }

    static func visibleText(from markup: String, hidesHiddenPreamble: Bool = true) -> String {
        let parser = GrokStreamMarkupParser(hidesHiddenPreamble: hidesHiddenPreamble)
        let events = parser.consume(markup) + parser.finish()
        let text = events.compactMap { event -> String? in
            guard case .text(let text) = event else { return nil }
            return text
        }.joined()
        return stripResidualInlineCitationFragments(from: text)
    }

    private func drain(final: Bool) -> [StreamDisplayEvent] {
        var events: [StreamDisplayEvent] = []

        while !buffer.isEmpty {
            if consumeHiddenPreambleIfAvailable(final: final) {
                continue
            }

            if hidesHiddenPreamble && !final && hiddenPreamble.hasPrefix(buffer) {
                break
            }

            if buffer.hasPrefix("<grok:render") {
                if consumeRenderDirective() {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            let residualStart = residualInlineCitationStart(in: buffer)
            let residualPrecedesNextTag = residualStart.map { start in
                !buffer[..<start].contains("<")
            } ?? false

            if residualPrecedesNextTag {
                if !final,
                   let start = residualStart,
                   start == buffer.startIndex,
                   residualInlineCitationTailIsIncomplete(from: start) {
                    break
                }

                if consumeResidualInlineCitationFragment(final: final, to: &events) {
                    continue
                }
            }

            guard let tagStart = buffer.firstIndex(of: "<") else {
                if holdIncompleteResidualInlineCitationFragment(final: final, to: &events) {
                    break
                }
                appendVisibleText(buffer, to: &events)
                buffer.removeAll(keepingCapacity: true)
                break
            }

            if tagStart > buffer.startIndex {
                let text = String(buffer[..<tagStart])
                appendVisibleText(text, to: &events)
                buffer.removeSubrange(..<tagStart)
                continue
            }

            if !final && isPotentialInternalTagPrefix(buffer) {
                break
            }

            if buffer.hasPrefix("<xai:tool_usage_card>") {
                if consumeToolUsageCard(to: &events) {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            if buffer.hasPrefix("<xai:") || buffer.hasPrefix("</xai:") || buffer.hasPrefix("<grok:") || buffer.hasPrefix("</grok:") {
                if consumeInternalTag() {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            if !final && buffer.count == 1 {
                break
            }

            appendVisibleText("<", to: &events)
            buffer.removeFirst()
        }

        return events
    }

    private func consumeHiddenPreambleIfAvailable(final: Bool) -> Bool {
        guard hidesHiddenPreamble else { return false }

        if !final && buffer.count < hiddenPreamble.count && hiddenPreamble.hasPrefix(buffer) {
            return false
        }

        guard buffer.hasPrefix(hiddenPreamble) else { return false }

        let afterPreamble = buffer.index(buffer.startIndex, offsetBy: hiddenPreamble.count)
        if afterPreamble < buffer.endIndex {
            let next = buffer[afterPreamble]
            guard next == "\n" || next == "\r" || next == "<" else {
                return false
            }
        }

        buffer.removeSubrange(..<afterPreamble)
        while let first = buffer.first, first == "\n" || first == "\r" {
            buffer.removeFirst()
        }
        return true
    }

    private func consumeToolUsageCard(to events: inout [StreamDisplayEvent]) -> Bool {
        let closeTag = "</xai:tool_usage_card>"
        guard let closeRange = buffer.range(of: closeTag) else {
            return false
        }

        let blockEnd = closeRange.upperBound
        let block = String(buffer[..<blockEnd])
        buffer.removeSubrange(..<blockEnd)

        guard let activity = summarizeToolUsageCard(block) else {
            return true
        }

        let traceLine = activity.displayText
        guard !emittedTraceLines.contains(traceLine) else {
            return true
        }

        emittedTraceLines.insert(traceLine)
        events.append(.activity(activity))
        return true
    }

    private func consumeRenderDirective() -> Bool {
        let closeTag = "</grok:render>"
        guard let closeRange = buffer.range(of: closeTag) else {
            return false
        }
        buffer.removeSubrange(..<closeRange.upperBound)
        return true
    }

    private func consumeInternalTag() -> Bool {
        guard let tagEnd = buffer.firstIndex(of: ">") else {
            return false
        }
        buffer.removeSubrange(...tagEnd)
        return true
    }

    private func appendVisibleText(_ text: String, to events: inout [StreamDisplayEvent]) {
        var cleaned = hidesHiddenPreamble ? removeHiddenPreambleLines(from: text) : text
        cleaned = Self.stripResidualInlineCitationFragments(from: cleaned)
        guard !cleaned.isEmpty else { return }
        events.append(.text(cleaned))
    }

    private func isPotentialInternalTagPrefix(_ text: String) -> Bool {
        internalTagPrefixes.contains { prefix in
            prefix.hasPrefix(text)
        }
    }

    private func holdIncompleteResidualInlineCitationFragment(final: Bool, to events: inout [StreamDisplayEvent]) -> Bool {
        guard !final,
              let start = residualInlineCitationStart(in: buffer),
              residualInlineCitationTailIsIncomplete(from: start) else {
            return false
        }

        if start > buffer.startIndex {
            appendVisibleText(String(buffer[..<start]), to: &events)
            buffer.removeSubrange(..<start)
        }
        return true
    }

    private func consumeResidualInlineCitationFragment(final: Bool, to events: inout [StreamDisplayEvent]) -> Bool {
        guard let start = residualInlineCitationStart(in: buffer) else {
            return false
        }

        if start > buffer.startIndex {
            appendVisibleText(String(buffer[..<start]), to: &events)
            buffer.removeSubrange(..<start)
            return true
        }

        if let closeRange = buffer.range(of: "</grok:render>") {
            buffer.removeSubrange(..<closeRange.upperBound)
            return true
        }

        if final {
            buffer.removeAll(keepingCapacity: true)
            return true
        }

        return false
    }

    private func residualInlineCitationStart(in text: String) -> String.Index? {
        let markers = [
            #"card_type="citation_card""#,
            #"card_type=\"citation_card\""#,
            #"type="render_inline_citation""#,
            #"type=\"render_inline_citation\""#
        ]

        guard markers.contains(where: { text.contains($0) }) else {
            return nil
        }

        let candidateTokens = [
            #"card_id="#,
            #"_id="#,
            #"card_type="#,
            #"type="#,
            #"card_id=\""#,
            #"_id=\""#,
            #"card_type=\""#,
            #"type=\""#
        ]
        return candidateTokens
            .compactMap { text.range(of: $0)?.lowerBound }
            .min()
    }

    private func residualInlineCitationTailIsIncomplete(from start: String.Index) -> Bool {
        let tail = String(buffer[start...])
        return tail.contains("render_inline_citation") && !tail.contains("</grok:render>")
    }

    private func removeHiddenPreambleLines(from text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines) != hiddenPreamble
            }
            .joined(separator: "\n")
    }

    private func summarizeToolUsageCard(_ block: String) -> ToolActivityEvent? {
        let toolName = xmlValue(named: "xai:tool_name", in: block) ?? "tool"
        let argsText = xmlValue(named: "xai:tool_args", in: block).map(stripCDATA)
        let args = argsText.flatMap(jsonDictionary)

        switch toolName {
        case "web_search":
            if let query = stringValue(args, key: "query") {
                return ToolActivityEvent(kind: .search, detail: compact(query))
            }
            return ToolActivityEvent(kind: .search, detail: "searching web")
        case "x_search":
            if let query = stringValue(args, key: "query") {
                return ToolActivityEvent(kind: .search, detail: "X \(compact(query))")
            }
            return ToolActivityEvent(kind: .search, detail: "searching X")
        case "code_execution", "code":
            let code = stringValue(args, key: "code") ?? argsText ?? ""
            return ToolActivityEvent(kind: .thinking, detail: summarizeCode(code))
        default:
            let displayName = toolName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            if let query = stringValue(args, key: "query") {
                return ToolActivityEvent(kind: .tool, detail: "\(displayName) \(compact(query))")
            }
            return ToolActivityEvent(kind: .tool, detail: displayName)
        }
    }

    private func xmlValue(named tagName: String, in text: String) -> String? {
        let openTag = "<\(tagName)>"
        let closeTag = "</\(tagName)>"
        guard let openRange = text.range(of: openTag),
              let closeRange = text.range(of: closeTag, range: openRange.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[openRange.upperBound..<closeRange.lowerBound])
    }

    private func stripCDATA(_ value: String) -> String {
        var stripped = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("<![CDATA[") {
            stripped.removeFirst("<![CDATA[".count)
        }
        if stripped.hasSuffix("]]>") {
            stripped.removeLast("]]>".count)
        }
        return stripped
    }

    private func jsonDictionary(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func stringValue(_ dictionary: [String: Any]?, key: String) -> String? {
        guard let value = dictionary?[key] else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private func summarizeCode(_ code: String) -> String {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                let comment = trimmed.drop(while: { $0 == "#" || $0 == " " })
                if !comment.isEmpty {
                    return compact(String(comment))
                }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return compact(trimmed)
            }
        }

        return "working through the problem"
    }

    private func compact(_ text: String, limit: Int = 140) -> String {
        let compacted = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard compacted.count > limit else {
            return compacted
        }

        let endIndex = compacted.index(compacted.startIndex, offsetBy: limit - 1)
        return "\(compacted[...endIndex])..."
    }

    private static func stripResidualInlineCitationFragments(from text: String) -> String {
        var cleaned = text
        let renderDirectivePatterns = [
            #"<grok:render[\s\S]*?</grok:render>"#,
            #"<grok:render\b[^>]*render_inline_citation[^>]*>(?:<argument\b[^>]*>[\s\S]*?</argument>)?</grok:render>"#
        ]
        for pattern in renderDirectivePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        let citationAttributePatterns = [
            #"(?:\s*(?:card_)?_?id="[^"]*")?\s*card_type="citation_card"\s+type="render_inline_citation">(?:<argument\b[^>]*>[\s\S]*?</argument>)?"#,
            #"(?:\s*(?:card_)?_?id=\\"[^"]*\\")?\s*card_type=\\"citation_card\\"\s+type=\\"render_inline_citation\\">(?:<argument\b[^>]*>[\s\S]*?</argument>)?"#
        ]
        for pattern in citationAttributePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        let argumentCitationPatterns = [
            #"<argument\s+name="citation_id">[\s\S]*?</argument>"#,
            #"<argument\s+name=\\"citation_id\\">[\s\S]*?</argument>"#
        ]
        for pattern in argumentCitationPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        return cleaned
    }
}
