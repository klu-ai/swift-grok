import Foundation
import GrokClient

extension GrokCLI {
    static func copyToClipboard(_ text: String) throws {
        if let clipboardFile = ProcessInfo.processInfo.environment["GROK_CLIPBOARD_FILE"], !clipboardFile.isEmpty {
            try text.write(toFile: clipboardFile, atomically: true, encoding: .utf8)
            return
        }

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")

        let input = Pipe()
        process.standardInput = input

        try process.run()
        input.fileHandleForWriting.write(Data(text.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GrokError.apiError("Could not copy to clipboard")
        }
        #else
        throw GrokError.apiError("Clipboard copy is only supported on macOS")
        #endif
    }
}
