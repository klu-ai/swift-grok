import Foundation

enum StreamDisplayEvent {
    case text(String)
    case trace(String)
}

final class GrokStreamMarkupParser {
    private let hiddenPreamble = "Thinking about your request"
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

    private func drain(final: Bool) -> [StreamDisplayEvent] {
        var events: [StreamDisplayEvent] = []

        while !buffer.isEmpty {
            if hidesHiddenPreamble && buffer.hasPrefix(hiddenPreamble) {
                buffer.removeFirst(hiddenPreamble.count)
                continue
            }

            if hidesHiddenPreamble && !final && hiddenPreamble.hasPrefix(buffer) {
                break
            }

            guard let tagStart = buffer.firstIndex(of: "<") else {
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

            if buffer.hasPrefix("<xai:tool_usage_card>") {
                if consumeToolUsageCard(to: &events) {
                    continue
                }
                if final {
                    buffer.removeAll(keepingCapacity: true)
                }
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

    private func consumeToolUsageCard(to events: inout [StreamDisplayEvent]) -> Bool {
        let closeTag = "</xai:tool_usage_card>"
        guard let closeRange = buffer.range(of: closeTag) else {
            return false
        }

        let blockEnd = closeRange.upperBound
        let block = String(buffer[..<blockEnd])
        buffer.removeSubrange(..<blockEnd)

        guard let traceLine = summarizeToolUsageCard(block), !emittedTraceLines.contains(traceLine) else {
            return true
        }

        emittedTraceLines.insert(traceLine)
        events.append(.trace(traceLine))
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
        let cleaned = hidesHiddenPreamble ? text.replacingOccurrences(of: hiddenPreamble, with: "") : text
        guard !cleaned.isEmpty else { return }
        events.append(.text(cleaned))
    }

    private func summarizeToolUsageCard(_ block: String) -> String? {
        let toolName = xmlValue(named: "xai:tool_name", in: block) ?? "tool"
        let argsText = xmlValue(named: "xai:tool_args", in: block).map(stripCDATA)
        let args = argsText.flatMap(jsonDictionary)

        switch toolName {
        case "web_search":
            if let query = stringValue(args, key: "query") {
                return "Search: \(compact(query))"
            }
            return "Search"
        case "x_search":
            if let query = stringValue(args, key: "query") {
                return "Search X: \(compact(query))"
            }
            return "Search X"
        case "code_execution", "code":
            let code = stringValue(args, key: "code") ?? argsText ?? ""
            return "Thinking: \(summarizeCode(code))"
        default:
            let displayName = toolName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            if let query = stringValue(args, key: "query") {
                return "\(displayName): \(compact(query))"
            }
            return displayName
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
}
