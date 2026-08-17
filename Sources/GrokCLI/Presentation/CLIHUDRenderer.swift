import Foundation
import GrokClient
import Rainbow

struct CLIHUDState: Equatable {
    var modelName: String
    var workspaceName: String?
    var privateMode: Bool
    var stream: Bool
    var outputFormat: OutputFormat
    var attachedFileCount: Int
    var rateLimitWarning: String?
}

enum CLIHUDRenderer {
    static func state(from chatState: ChatSessionState, app: GrokCLIApp) -> CLIHUDState {
        CLIHUDState(
            modelName: chatState.mode.displayName,
            workspaceName: app.getCurrentWorkspace()?.cliDisplayName,
            privateMode: chatState.privateMode,
            stream: chatState.stream,
            outputFormat: chatState.outputFormat,
            attachedFileCount: app.getAttachedFileIds().count,
            rateLimitWarning: chatState.rateLimitStatus
        )
    }

    static func lines(state: CLIHUDState, width: Int = TerminalLayout.columns()) -> [String] {
        let label = state.workspaceName ?? "Grok"
        var segments: [String] = []

        if state.privateMode {
            segments.append("Private")
        }

        segments.append(modelStatusName(state.modelName, label: label))
        segments.append(state.outputFormat.statusName)

        if !state.stream {
            segments.append("Stream off")
        }

        if state.attachedFileCount > 0 {
            segments.append(state.attachedFileCount == 1 ? "1 file" : "\(state.attachedFileCount) files")
        }

        let plainStatus = TerminalLayout.truncateEnd("\(label) > \(segments.joined(separator: " | "))", width: width)
        var lines = [colorStatusLine(plainStatus, label: label)]

        if let warning = state.rateLimitWarning, !warning.isEmpty {
            let plainWarning = TerminalLayout.truncateEnd("Limit > \(warning)", width: width)
            lines.append(colorWarningLine(plainWarning))
        }

        return lines
    }

    static func plainLines(state: CLIHUDState, width: Int = TerminalLayout.columns()) -> [String] {
        lines(state: state, width: width).map(TerminalLayout.stripANSI)
    }

    private static func colorStatusLine(_ line: String, label: String) -> String {
        let prefix = "\(label) > "
        guard line.hasPrefix(prefix) else {
            return TerminalStyle.text(line, .status)
        }
        let rest = String(line.dropFirst(prefix.count))
        return TerminalStyle.text(label, .status)
            + " > ".cyan
            + rest.yellow
    }

    private static func colorWarningLine(_ line: String) -> String {
        let prefix = "Limit > "
        guard line.hasPrefix(prefix) else {
            return TerminalStyle.text(line, .warning)
        }
        let rest = String(line.dropFirst(prefix.count))
        return TerminalStyle.text("Limit", .warning)
            + " > ".cyan
            + rest.yellow
    }

    private static func modelStatusName(_ modelName: String, label: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if label == "Grok", trimmed.hasPrefix("Grok ") {
            return String(trimmed.dropFirst("Grok ".count))
        }
        return trimmed.isEmpty ? "Auto" : trimmed
    }
}

final class InteractiveRenderState {
    var chatState: ChatSessionState

    init(chatState: ChatSessionState) {
        self.chatState = chatState
    }
}
