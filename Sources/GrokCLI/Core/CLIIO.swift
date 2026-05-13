import Foundation
import GrokClient
import Rainbow

#if os(Linux)
import Glibc
private let cliStdinFileDescriptor = STDIN_FILENO
private let cliStdoutFileDescriptor = STDOUT_FILENO
private let cliStdoutFile = Glibc.stdout
private let cliStderrFile = Glibc.stderr
#else
import Darwin
private let cliStdinFileDescriptor = STDIN_FILENO
private let cliStdoutFileDescriptor = STDOUT_FILENO
private let cliStdoutFile = Darwin.stdout
private let cliStderrFile = Darwin.stderr
#endif

enum CLIOutput {
    static func stdout(_ text: String = "", terminator: String = "\n") {
        Swift.print(text, terminator: terminator)
        fflush(cliStdoutFile)
    }

    static func stderr(_ text: String = "", terminator: String = "\n") {
        let data = Data((text + terminator).utf8)
        FileHandle.standardError.write(data)
        fflush(cliStderrFile)
    }

    final class TransientStatusLine {
        enum NonTTYBehavior {
            case printLines
            case inert
        }

        private let isTTY: Bool
        private let nonTTYBehavior: NonTTYBehavior
        private var hasRenderedStatus = false
        private var isFinished = false

        init(isTTY: Bool = GrokCLI.stdoutIsTTY(), nonTTYBehavior: NonTTYBehavior = .inert) {
            self.isTTY = isTTY
            self.nonTTYBehavior = nonTTYBehavior
        }

        func update(text: String) {
            guard !isFinished else { return }

            let statusText = oneLine(text)
            guard isTTY else {
                if nonTTYBehavior == .printLines {
                    CLIOutput.stdout(statusText)
                }
                return
            }

            CLIOutput.stdout("\r\u{001B}[2K\(statusText)", terminator: "")
            hasRenderedStatus = true
        }

        func finish(finalText: String? = nil) {
            guard !isFinished else { return }
            isFinished = true

            guard isTTY else {
                if nonTTYBehavior == .printLines, let finalText {
                    CLIOutput.stdout(oneLine(finalText))
                }
                return
            }

            clear()
            if let finalText {
                CLIOutput.stdout(oneLine(finalText))
            }
        }

        func clear() {
            guard isTTY, hasRenderedStatus else { return }
            CLIOutput.stdout("\r\u{001B}[2K", terminator: "")
            hasRenderedStatus = false
        }

        private func oneLine(_ text: String) -> String {
            text
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
        }
    }
}

extension GrokCLI {
    static func stdinIsTTY() -> Bool {
        isatty(cliStdinFileDescriptor) == 1
    }

    static func stdoutIsTTY() -> Bool {
        isatty(cliStdoutFileDescriptor) == 1
    }

    static func readStandardInput() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw GrokError.apiError("Could not read stdin as UTF-8 text")
        }
        return text
    }

    static func readPromptFile(_ path: String) throws -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return try String(contentsOfFile: expandedPath, encoding: .utf8)
    }

    static func printSearchConfigurationWarnings(_ warnings: [String], toStderr: Bool) {
        for warning in warnings {
            if toStderr {
                CLIOutput.stderr("Warning: \(warning)")
            } else {
                print("Warning: \(warning)".yellow)
            }
        }
    }
}
