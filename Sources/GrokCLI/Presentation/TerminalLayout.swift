import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum TerminalLayout {
    static func columns(default defaultColumns: Int = 80) -> Int {
        guard GrokCLI.stdoutIsTTY() else {
            return defaultColumns
        }

        var size = winsize()
        let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        guard result == 0, size.ws_col > 0 else {
            return defaultColumns
        }
        return Int(size.ws_col)
    }

    static func stripANSI(_ value: String) -> String {
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }

    static func visibleLength(_ value: String) -> Int {
        stripANSI(value).count
    }

    static func truncateEnd(_ value: String, width: Int) -> String {
        guard width > 0 else { return "" }
        let plain = stripANSI(value)
        guard plain.count > width else { return value }
        guard width > 3 else { return String(plain.prefix(width)) }
        return String(plain.prefix(width - 3)) + "..."
    }

    static func truncateMiddle(_ value: String, width: Int) -> String {
        guard width > 0 else { return "" }
        let plain = stripANSI(value)
        guard plain.count > width else { return value }
        guard width > 3 else { return String(plain.prefix(width)) }

        let head = (width - 3 + 1) / 2
        let tail = width - 3 - head
        return String(plain.prefix(head)) + "..." + String(plain.suffix(tail))
    }
}
