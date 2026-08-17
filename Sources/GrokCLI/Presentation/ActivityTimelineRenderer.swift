import Foundation

enum ToolActivityKind: String, Equatable {
    case thinking
    case search
    case tool
}

struct ToolActivityEvent: Equatable {
    var kind: ToolActivityKind
    var detail: String

    var displayText: String {
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return kind.rawValue }
        return detail
    }
}

enum ActivityTimelineRenderer {
    static func line(_ event: ToolActivityEvent) -> String {
        let label = "[\(event.kind.rawValue)]"
        switch event.kind {
        case .thinking:
            return TerminalStyle.text(label, .muted) + " " + event.displayText
        case .search:
            return TerminalStyle.text(label, .accent) + " " + event.displayText
        case .tool:
            return TerminalStyle.text(label, .status) + " " + event.displayText
        }
    }

    static func event(fromTraceLine line: String) -> ToolActivityEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Thinking:") {
            return ToolActivityEvent(
                kind: .thinking,
                detail: String(trimmed.dropFirst("Thinking:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if trimmed.lowercased().hasPrefix("thinking") {
            return ToolActivityEvent(kind: .thinking, detail: trimmed)
        }
        if trimmed.hasPrefix("Search X:") {
            return ToolActivityEvent(
                kind: .search,
                detail: String(trimmed.dropFirst("Search X:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if trimmed.hasPrefix("Search:") {
            return ToolActivityEvent(
                kind: .search,
                detail: String(trimmed.dropFirst("Search:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return ToolActivityEvent(kind: .tool, detail: trimmed)
    }
}
