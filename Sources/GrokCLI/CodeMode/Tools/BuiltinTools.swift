import Foundation
import GrokClient

enum GrokCodeBuiltinTools {
    static func registerAll(into registry: inout GrokCodeToolRegistry) {
        registry.register(ReadFileTool())
        registry.register(GrepTool())
        registry.register(ListDirTool())
        registry.register(RunTerminalCommandTool())
        registry.register(SearchReplaceTool())
        registry.register(ApplyPatchTool())

        registry.register(alias: "bash", target: "run_terminal_cmd")
        registry.register(alias: "shell", target: "run_terminal_cmd")
        registry.register(alias: "grep_search", target: "grep")
        registry.register(alias: "list_files", target: "list_dir")
    }
}

private struct ReadFileTool: GrokCodeTool {
    struct Input: Decodable {
        var filePath: String
        var offset: Int?
        var limit: Int?
        var pageRange: String?
        var pdfFormat: String?

        private enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case offset
            case limit
            case pageRange = "page_range"
            case pdfFormat = "pdf_format"
        }
    }

    let name = "read_file"
    let description = "Read UTF-8 text file contents with line numbers."

    var schema: GrokCodeToolSchema {
        GrokCodeToolSchema(
            name: name,
            description: description,
            parameters: GrokCodeToolSchemaBuilder.object(
                properties: [
                    "file_path": GrokCodeToolSchemaBuilder.string("Path of the file to read, relative to the workspace or absolute inside it."),
                    "offset": GrokCodeToolSchemaBuilder.number("Line number to start reading from. Defaults to 1."),
                    "limit": GrokCodeToolSchemaBuilder.number("Maximum number of lines to return."),
                    "page_range": GrokCodeToolSchemaBuilder.string("PDF page range. Unsupported in this local v0.1 tool."),
                    "pdf_format": GrokCodeToolSchemaBuilder.string("PDF output format. Unsupported in this local v0.1 tool.")
                ],
                required: ["file_path"]
            )
        )
    }

    func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
        guard !input.filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokCodeToolError.invalidInput("read_file requires file_path.")
        }
    }

    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
        let url = try GrokCodePath.resolveWorkspacePath(input.filePath, in: context.workingDirectory)
        if url.pathExtension.lowercased() == "pdf" || input.pageRange != nil || input.pdfFormat != nil {
            throw GrokCodeToolError.executionFailed("read_file PDF input is unsupported in this local v0.1 tool.")
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GrokCodeToolError.executionFailed("read_file supports UTF-8 text files only.")
        }

        let fingerprint = try GrokCodeFileFingerprint.capture(url: url, data: data)
        await context.readState.record(GrokCodeFileReadState(
            filePath: GrokCodePath.displayPath(url, relativeTo: context.workingDirectory),
            absolutePath: url.path,
            size: fingerprint.size,
            modifiedAt: fingerprint.modifiedAt,
            contentHash: fingerprint.contentHash
        ))

        let lines = text.isEmpty
            ? [""]
            : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let startLine = max(input.offset ?? 1, 1)
        let maxLines = min(max(input.limit ?? 200, 1), 2_000)
        let startIndex = min(startLine - 1, lines.count)
        let endIndex = min(startIndex + maxLines, lines.count)
        let width = max(String(endIndex).count, 1)

        var output: [String] = []
        let displayPath = GrokCodePath.displayPath(url, relativeTo: context.workingDirectory)
        output.append("\(displayPath) (lines \(startIndex + 1)-\(endIndex) of \(lines.count))")
        if startIndex < endIndex {
            for index in startIndex..<endIndex {
                let number = String(format: "%\(width)d", index + 1)
                output.append("\(number) | \(lines[index])")
            }
        }
        if endIndex < lines.count {
            output.append("[file truncated: use offset \(endIndex + 1) to continue]")
        }

        return .success(requestID: "", text: output.joined(separator: "\n"))
    }
}

private struct GrepTool: GrokCodeTool {
    struct Input: Decodable {
        var pattern: String?
        var query: String?
        var glob: String?
        var path: String?
        var limit: Int?
    }

    let name = "grep"
    let description = "Search workspace files with a regex pattern."

    var schema: GrokCodeToolSchema {
        GrokCodeToolSchema(
            name: name,
            description: description,
            parameters: GrokCodeToolSchemaBuilder.object(
                properties: [
                    "pattern": GrokCodeToolSchemaBuilder.string("Regular expression pattern to search for."),
                    "glob": GrokCodeToolSchemaBuilder.string("Optional glob limiting searched files, for example *.swift."),
                    "path": GrokCodeToolSchemaBuilder.string("Directory or file path to search. Defaults to the workspace."),
                    "limit": GrokCodeToolSchemaBuilder.number("Maximum number of matching lines to return.")
                ],
                required: ["pattern"]
            )
        )
    }

    func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
        guard !(input.searchPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            throw GrokCodeToolError.invalidInput("grep requires pattern.")
        }
    }

    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
        let pattern = input.searchPattern
        let root = try GrokCodePath.resolveWorkspacePath(input.path ?? ".", in: context.workingDirectory)
        let limit = min(max(input.limit ?? 100, 1), 1_000)

        if try GrokCodeProcess.commandExists("rg", workingDirectory: context.workingDirectory) {
            let lines = try runRipgrep(
                pattern: pattern,
                glob: input.glob,
                path: root,
                limit: limit,
                context: context
            )
            return .success(requestID: "", text: lines.isEmpty ? "[no matches]" : lines.joined(separator: "\n"))
        }

        let lines = try runSwiftScanner(
            pattern: pattern,
            glob: input.glob,
            root: root,
            limit: limit,
            context: context
        )
        return .success(requestID: "", text: lines.isEmpty ? "[no matches]" : lines.joined(separator: "\n"))
    }

    private func runRipgrep(
        pattern: String,
        glob: String?,
        path: URL,
        limit: Int,
        context: GrokCodeToolUseContext
    ) throws -> [String] {
        var arguments = ["rg", "--line-number", "--no-heading", "--color", "never"]
        if let glob, !glob.isEmpty {
            arguments += ["--glob", glob]
        }
        arguments += ["--", pattern, GrokCodePath.displayPath(path, relativeTo: context.workingDirectory)]

        let result = try GrokCodeProcess.run(
            executable: "/usr/bin/env",
            arguments: arguments,
            workingDirectory: context.workingDirectory,
            timeoutSeconds: 30
        )
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw GrokCodeToolError.executionFailed(result.summary.isEmpty ? "rg exited \(result.exitCode)" : result.summary)
        }
        var lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let truncated = lines.count > limit
        lines = Array(lines.prefix(limit))
        if truncated {
            lines.append("[grep truncated to \(limit) matches]")
        }
        return lines
    }

    private func runSwiftScanner(
        pattern: String,
        glob: String?,
        root: URL,
        limit: Int,
        context: GrokCodeToolUseContext
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        var matches: [String] = []
        for file in try GrokCodePath.candidateFiles(root: root, includeHidden: false) {
            if let glob, !glob.isEmpty, !GrokCodePath.matchesGlob(file.lastPathComponent, glob: glob) {
                continue
            }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let lineText = String(line)
                let range = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
                if regex.firstMatch(in: lineText, options: [], range: range) != nil {
                    let path = GrokCodePath.displayPath(file, relativeTo: context.workingDirectory)
                    matches.append("\(path):\(index + 1):\(lineText)")
                    if matches.count >= limit {
                        matches.append("[grep truncated to \(limit) matches]")
                        return matches
                    }
                }
            }
        }
        return matches
    }
}

private extension GrepTool.Input {
    var searchPattern: String {
        pattern ?? query ?? ""
    }
}

private struct ListDirTool: GrokCodeTool {
    struct Input: Decodable {
        var dirPath: String?
        var path: String?
        var offset: Int?
        var limit: Int?
        var depth: Int?
        var includeHidden: Bool?

        private enum CodingKeys: String, CodingKey {
            case dirPath = "dir_path"
            case path
            case offset
            case limit
            case depth
            case includeHidden = "include_hidden"
        }
    }

    let name = "list_dir"
    let description = "List directory contents in stable sorted order."

    var schema: GrokCodeToolSchema {
        GrokCodeToolSchema(
            name: name,
            description: description,
            parameters: GrokCodeToolSchemaBuilder.object(
                properties: [
                    "dir_path": GrokCodeToolSchemaBuilder.string("Directory path to list. Defaults to the workspace."),
                    "offset": GrokCodeToolSchemaBuilder.number("Entry number to start listing from, 1 or greater."),
                    "limit": GrokCodeToolSchemaBuilder.number("Maximum number of entries to return."),
                    "depth": GrokCodeToolSchemaBuilder.number("Maximum directory depth to traverse, 1 or greater."),
                    "include_hidden": GrokCodeToolSchemaBuilder.boolean("Whether to include hidden files.")
                ]
            )
        )
    }

    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
        let root = try GrokCodePath.resolveWorkspacePath(input.dirPath ?? input.path ?? ".", in: context.workingDirectory)
        let offset = max(input.offset ?? 1, 1)
        let limit = min(max(input.limit ?? 200, 1), 2_000)
        let depth = min(max(input.depth ?? 1, 1), 12)
        let includeHidden = input.includeHidden ?? false

        var entries = try GrokCodePath.listEntries(root: root, maxDepth: depth, includeHidden: includeHidden, relativeTo: context.workingDirectory)
        entries.sort()

        let start = min(offset - 1, entries.count)
        let end = min(start + limit, entries.count)
        var output = Array(entries[start..<end])
        if end < entries.count {
            output.append("[list truncated: use offset \(end + 1) to continue]")
        }
        return .success(requestID: "", text: output.isEmpty ? "[empty directory]" : output.joined(separator: "\n"))
    }
}

private struct RunTerminalCommandTool: GrokCodeTool {
    struct Input: Decodable {
        var command: String
        var timeoutMS: Double?
        var explanation: String?
        var isBackground: Bool?

        private enum CodingKeys: String, CodingKey {
            case command
            case timeoutMS = "timeout_ms"
            case explanation
            case isBackground = "is_background"
        }
    }

    let name = "run_terminal_cmd"
    let description = "Run a terminal command in the workspace."
    let isConcurrencySafeByDefault = false
    let requiredPermission: GrokCodeToolPermission = .shell

    var schema: GrokCodeToolSchema {
        GrokCodeToolSchema(
            name: name,
            description: description,
            parameters: GrokCodeToolSchemaBuilder.object(
                properties: [
                    "command": GrokCodeToolSchemaBuilder.string("The bash command to run."),
                    "timeout_ms": GrokCodeToolSchemaBuilder.number("Optional timeout in milliseconds. Defaults to 120000."),
                    "explanation": GrokCodeToolSchemaBuilder.string("One sentence explanation for why the command is needed."),
                    "is_background": GrokCodeToolSchemaBuilder.boolean("Set true for long-running commands. Unsupported in this local v0.1 tool.")
                ],
                required: ["command", "explanation"]
            )
        )
    }

    func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
        guard !input.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokCodeToolError.invalidInput("run_terminal_cmd requires command.")
        }
    }

    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
        if input.isBackground == true {
            throw GrokCodeToolError.executionFailed("run_terminal_cmd is_background=true is unsupported in this local v0.1 tool.")
        }

        let timeoutMS = min(max(input.timeoutMS ?? (context.shellTimeoutSeconds * 1_000), 1_000), 36_000_000)
        let result = try GrokCodeProcess.run(
            executable: "/bin/sh",
            arguments: ["-lc", input.command],
            workingDirectory: context.workingDirectory,
            timeoutSeconds: timeoutMS / 1_000
        )
        return GrokCodeToolResult(
            requestID: "",
            ok: result.exitCode == 0,
            content: [.text(result.summary.isEmpty ? "[no output]" : result.summary)],
            error: result.exitCode == 0 ? nil : "Command exited \(result.exitCode)"
        )
    }
}

private struct SearchReplaceTool: GrokCodeTool {
    struct Input: Decodable {
        var filePath: String
        var oldString: String
        var newString: String
        var replaceAll: Bool?

        private enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case oldString = "old_string"
            case newString = "new_string"
            case replaceAll = "replace_all"
        }
    }

    let name = "search_replace"
    let description = "Make a precise edit to a previously read UTF-8 text file."
    let isConcurrencySafeByDefault = false
    let requiredPermission: GrokCodeToolPermission = .write

    var schema: GrokCodeToolSchema {
        GrokCodeToolSchema(
            name: name,
            description: description,
            parameters: GrokCodeToolSchemaBuilder.object(
                properties: [
                    "file_path": GrokCodeToolSchemaBuilder.string("Path to the file to modify."),
                    "old_string": GrokCodeToolSchemaBuilder.string("Exact text to replace."),
                    "new_string": GrokCodeToolSchemaBuilder.string("Replacement text. Must differ from old_string."),
                    "replace_all": GrokCodeToolSchemaBuilder.boolean("Replace every occurrence. Defaults to false.")
                ],
                required: ["file_path", "old_string", "new_string"]
            )
        )
    }

    func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
        guard !input.filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokCodeToolError.invalidInput("search_replace requires file_path.")
        }
        guard !input.oldString.isEmpty else {
            throw GrokCodeToolError.invalidInput("search_replace requires old_string.")
        }
        guard input.oldString != input.newString else {
            throw GrokCodeToolError.invalidInput("Old string and new string are the same")
        }
    }

    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
        let url = try GrokCodePath.resolveWorkspacePath(input.filePath, in: context.workingDirectory)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GrokCodeToolError.executionFailed("search_replace supports UTF-8 text files only.")
        }

        let fingerprint = try GrokCodeFileFingerprint.capture(url: url, data: data)
        guard let readState = await context.readState.state(for: url.path) else {
            throw GrokCodeToolError.executionFailed("You must read the file with the tool before editing it.")
        }
        guard readState.size == fingerprint.size,
              readState.modifiedAt == fingerprint.modifiedAt,
              readState.contentHash == fingerprint.contentHash else {
            throw GrokCodeToolError.executionFailed("File has been modified since it was read. Please read the file again to see the latest changes before editing.")
        }

        let matches = text.grokCodeRanges(of: input.oldString)
        guard !matches.isEmpty else {
            throw GrokCodeToolError.executionFailed("The string to replace was not found in the file, use the read_file tool to see the correct string.")
        }
        guard matches.count == 1 || input.replaceAll == true else {
            throw GrokCodeToolError.executionFailed("The string to replace was found multiple times in the file. Use replace_all to replace all occurrences, or include more context to only edit one occurrence.")
        }

        let updated: String
        if input.replaceAll == true {
            updated = text.replacingOccurrences(of: input.oldString, with: input.newString)
        } else {
            var copy = text
            copy.replaceSubrange(matches[0], with: input.newString)
            updated = copy
        }

        try updated.write(to: url, atomically: true, encoding: .utf8)
        await context.readState.remove(url.path)

        let displayPath = GrokCodePath.displayPath(url, relativeTo: context.workingDirectory)
        let count = input.replaceAll == true ? matches.count : 1
        return .success(requestID: "", text: "Replaced \(count) occurrence\(count == 1 ? "" : "s") in \(displayPath).")
    }
}

private struct ApplyPatchTool: GrokCodeTool {
    struct Input: Decodable {
        var patch: String
    }

    let name = "apply_patch"
    let description = "Apply a Codex-style patch to create, update, move, or delete files."
    let isConcurrencySafeByDefault = false
    let requiredPermission: GrokCodeToolPermission = .write

    var schema: GrokCodeToolSchema {
        GrokCodeToolSchema(
            name: name,
            description: description,
            parameters: GrokCodeToolSchemaBuilder.object(
                properties: [
                    "patch": GrokCodeToolSchemaBuilder.string("The patch text in Codex patch format.")
                ],
                required: ["patch"]
            )
        )
    }

    func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
        guard input.patch.contains("*** Begin Patch"),
              input.patch.contains("*** End Patch") else {
            throw GrokCodeToolError.invalidInput("apply_patch requires Codex patch text with begin and end markers.")
        }
    }

    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
        let operations = try GrokCodePatchParser.parse(input.patch)
        var summaries: [String] = []
        for operation in operations {
            let summary = try operation.apply(in: context.workingDirectory)
            summaries.append(summary)
        }
        return .success(requestID: "", text: summaries.joined(separator: "\n"))
    }
}

private struct GrokCodeFileFingerprint: Equatable {
    var size: UInt64
    var modifiedAt: TimeInterval
    var contentHash: String

    static func capture(url: URL, data: Data) throws -> GrokCodeFileFingerprint {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return GrokCodeFileFingerprint(
            size: UInt64(values.fileSize ?? data.count),
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            contentHash: fnv1a64(data)
        )
    }

    private static func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private enum GrokCodePatchOperation {
    case add(path: String, lines: [String])
    case delete(path: String)
    case update(path: String, moveTo: String?, hunks: [[GrokCodePatchLine]])

    func apply(in workingDirectory: URL) throws -> String {
        switch self {
        case .add(let path, let lines):
            let url = try GrokCodePath.resolveWorkspacePath(path, in: workingDirectory)
            if FileManager.default.fileExists(atPath: url.path) {
                throw GrokCodeToolError.executionFailed("apply_patch add failed because file already exists: \(path)")
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return "Added \(GrokCodePath.displayPath(url, relativeTo: workingDirectory))."

        case .delete(let path):
            let url = try GrokCodePath.resolveWorkspacePath(path, in: workingDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw GrokCodeToolError.executionFailed("apply_patch delete failed because file does not exist: \(path)")
            }
            try FileManager.default.removeItem(at: url)
            return "Deleted \(GrokCodePath.displayPath(url, relativeTo: workingDirectory))."

        case .update(let path, let moveTo, let hunks):
            let sourceURL = try GrokCodePath.resolveWorkspacePath(path, in: workingDirectory)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw GrokCodeToolError.executionFailed("apply_patch update failed because file does not exist: \(path)")
            }
            var text = try String(contentsOf: sourceURL, encoding: .utf8)
            for hunk in hunks {
                text = try Self.applying(hunk: hunk, to: text, path: path)
            }

            let destinationURL: URL
            if let moveTo {
                destinationURL = try GrokCodePath.resolveWorkspacePath(moveTo, in: workingDirectory)
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try text.write(to: destinationURL, atomically: true, encoding: .utf8)
                if sourceURL.path != destinationURL.path {
                    try FileManager.default.removeItem(at: sourceURL)
                }
            } else {
                destinationURL = sourceURL
                try text.write(to: destinationURL, atomically: true, encoding: .utf8)
            }
            return "Updated \(GrokCodePath.displayPath(destinationURL, relativeTo: workingDirectory))."
        }
    }

    private static func applying(hunk: [GrokCodePatchLine], to text: String, path: String) throws -> String {
        let oldLines = hunk.compactMap(\.oldLine)
        let newLines = hunk.compactMap(\.newLine)
        let oldText = oldLines.joined(separator: "\n")
        let newText = newLines.joined(separator: "\n")

        if oldText.isEmpty {
            return text + (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + newText
        }

        guard let range = text.range(of: oldText) else {
            throw GrokCodeToolError.executionFailed("apply_patch update hunk did not match file: \(path)")
        }

        var updated = text
        updated.replaceSubrange(range, with: newText)
        return updated
    }
}

private enum GrokCodePatchLine {
    case context(String)
    case removal(String)
    case addition(String)

    var oldLine: String? {
        switch self {
        case .context(let line), .removal(let line):
            return line
        case .addition:
            return nil
        }
    }

    var newLine: String? {
        switch self {
        case .context(let line), .addition(let line):
            return line
        case .removal:
            return nil
        }
    }
}

private enum GrokCodePatchParser {
    static func parse(_ patch: String) throws -> [GrokCodePatchOperation] {
        let lines = patch
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.first == "*** Begin Patch",
              lines.last == "*** End Patch" else {
            throw GrokCodeToolError.invalidInput("apply_patch patch must start with *** Begin Patch and end with *** End Patch.")
        }

        var index = 1
        var operations: [GrokCodePatchOperation] = []
        while index < lines.count - 1 {
            let line = lines[index]
            if line.hasPrefix("*** Add File: ") {
                let path = String(line.dropFirst("*** Add File: ".count))
                index += 1
                var added: [String] = []
                while index < lines.count - 1, !lines[index].hasPrefix("*** ") {
                    guard lines[index].hasPrefix("+") else {
                        throw GrokCodeToolError.invalidInput("apply_patch add lines must start with '+'.")
                    }
                    added.append(String(lines[index].dropFirst()))
                    index += 1
                }
                operations.append(.add(path: path, lines: added))
            } else if line.hasPrefix("*** Delete File: ") {
                let path = String(line.dropFirst("*** Delete File: ".count))
                operations.append(.delete(path: path))
                index += 1
            } else if line.hasPrefix("*** Update File: ") {
                let path = String(line.dropFirst("*** Update File: ".count))
                index += 1
                var moveTo: String?
                if index < lines.count - 1, lines[index].hasPrefix("*** Move to: ") {
                    moveTo = String(lines[index].dropFirst("*** Move to: ".count))
                    index += 1
                }

                var hunks: [[GrokCodePatchLine]] = []
                var current: [GrokCodePatchLine] = []
                while index < lines.count - 1, !lines[index].hasPrefix("*** ") {
                    let hunkLine = lines[index]
                    if hunkLine.hasPrefix("@@") {
                        if !current.isEmpty {
                            hunks.append(current)
                            current = []
                        }
                    } else if hunkLine.hasPrefix("+") {
                        current.append(.addition(String(hunkLine.dropFirst())))
                    } else if hunkLine.hasPrefix("-") {
                        current.append(.removal(String(hunkLine.dropFirst())))
                    } else if hunkLine.hasPrefix(" ") {
                        current.append(.context(String(hunkLine.dropFirst())))
                    } else if hunkLine == "*** End of File" {
                        break
                    } else {
                        throw GrokCodeToolError.invalidInput("apply_patch update lines must start with space, '+', '-', or '@@'.")
                    }
                    index += 1
                }
                if !current.isEmpty {
                    hunks.append(current)
                }
                operations.append(.update(path: path, moveTo: moveTo, hunks: hunks))
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
            } else {
                throw GrokCodeToolError.invalidInput("Unsupported apply_patch hunk: \(line)")
            }
        }

        guard !operations.isEmpty else {
            throw GrokCodeToolError.invalidInput("apply_patch contained no file operations.")
        }
        return operations
    }
}

private enum GrokCodePath {
    static func resolveWorkspacePath(_ path: String, in workingDirectory: URL) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : workingDirectory.appendingPathComponent(expanded)
        let resolved = url.standardizedFileURL
        guard isDescendant(resolved, of: workingDirectory.standardizedFileURL) else {
            throw GrokCodeToolError.permissionDenied("Path must stay inside the workspace.")
        }
        return resolved
    }

    static func displayPath(_ url: URL, relativeTo root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath {
            return "."
        }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    static func listEntries(root: URL, maxDepth: Int, includeHidden: Bool, relativeTo workingDirectory: URL) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw GrokCodeToolError.executionFailed("Path does not exist: \(displayPath(root, relativeTo: workingDirectory))")
        }
        if !isDirectory.boolValue {
            return [displayPath(root, relativeTo: workingDirectory)]
        }

        var entries: [String] = []
        try collectDirectoryEntries(
            root: root,
            current: root,
            currentDepth: 1,
            maxDepth: maxDepth,
            includeHidden: includeHidden,
            relativeTo: workingDirectory,
            entries: &entries
        )
        return entries
    }

    static func candidateFiles(root: URL, includeHidden: Bool) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return []
        }
        if !isDirectory.boolValue {
            return [root]
        }

        var files: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: includeHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func matchesGlob(_ name: String, glob: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: glob)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$") else {
            return true
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return regex.firstMatch(in: name, options: [], range: range) != nil
    }

    private static func collectDirectoryEntries(
        root: URL,
        current: URL,
        currentDepth: Int,
        maxDepth: Int,
        includeHidden: Bool,
        relativeTo workingDirectory: URL,
        entries: inout [String]
    ) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: current,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in urls {
            if !includeHidden, url.lastPathComponent.hasPrefix(".") {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            entries.append(displayPath(url, relativeTo: workingDirectory) + (isDirectory ? "/" : ""))
            if isDirectory, currentDepth < maxDepth {
                try collectDirectoryEntries(
                    root: root,
                    current: url,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    includeHidden: includeHidden,
                    relativeTo: workingDirectory,
                    entries: &entries
                )
            }
        }
    }
}

private struct GrokCodeProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var summary: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: stderr.isEmpty ? "" : "\n")
    }
}

private enum GrokCodeProcess {
    static func commandExists(_ command: String, workingDirectory: URL) throws -> Bool {
        let result = try run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-lc", "command -v \(command) >/dev/null 2>&1"],
            workingDirectory: workingDirectory,
            timeoutSeconds: 2
        )
        return result.exitCode == 0
    }

    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        stdin: String? = nil,
        timeoutSeconds: TimeInterval
    ) throws -> GrokCodeProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let inputPipe = Pipe()
        if stdin != nil {
            process.standardInput = inputPipe
        }

        try process.run()

        if let stdinData = stdin?.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(stdinData)
            try? inputPipe.fileHandleForWriting.close()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw GrokCodeToolError.executionFailed("Command timed out after \(Int(timeoutSeconds))s.")
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return GrokCodeProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

private extension String {
    func grokCodeRanges(of needle: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else {
            return []
        }
        var ranges: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = self.range(of: needle, range: searchStart..<endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
