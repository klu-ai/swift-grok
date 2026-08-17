import Foundation
import Rainbow

enum TerminalRole {
    case brand
    case accent
    case muted
    case success
    case warning
    case error
    case command
    case selected
    case status
    case transcript
}

enum TerminalStyle {
    static func text(_ value: String, _ role: TerminalRole, bold: Bool = false) -> String {
        let colored: String
        switch role {
        case .brand:
            colored = value.green
        case .accent:
            colored = value.cyan
        case .muted:
            colored = value.blue
        case .success:
            colored = value.green
        case .warning:
            colored = value.yellow
        case .error:
            colored = value.red
        case .command:
            colored = value.yellow
        case .selected:
            colored = value.yellow
        case .status:
            colored = value.cyan
        case .transcript:
            colored = value
        }
        return bold ? colored.bold : colored
    }
}
