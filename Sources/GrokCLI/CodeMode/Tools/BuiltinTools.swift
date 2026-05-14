// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// enum GrokCodeBuiltinTools {
//     static func registerAll(into registry: inout GrokCodeToolRegistry) {
//         registry.register(ReadFileTool())
//         registry.register(ListFilesTool())
//         registry.register(SearchTool())
//         registry.register(ShellTool())
//         registry.register(GitDiffTool())
//         registry.register(ApplyPatchTool())
//         registry.register(WriteFileTool())
//         registry.register(WriteFilesTool())
//         registry.register(WritePlanTool())
// 
//         registry.register(alias: "rg", target: "search")
//         registry.register(alias: "grep", target: "search")
//         registry.register(alias: "diff", target: "git_diff")
//     }
// }
// 
// private struct ReadFileTool: GrokCodeTool {
//     struct Input: Decodable {
//         var path: String
//         var offset: Int?
//         var limit: Int?
//     }
// 
//     let name = "read_file"
//     let description = "Read a UTF-8 text file from the local workspace."
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         guard !input.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
//             throw GrokCodeToolError.invalidInput("read_file requires path.")
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let url = try GrokCodePath.resolve(input.path, in: context.workingDirectory)
//         let data = try Data(contentsOf: url)
//         guard let text = String(data: data, encoding: .utf8) else {
//             throw GrokCodeToolError.executionFailed("read_file supports UTF-8 text files only.")
//         }
// 
//         let offset = max(0, input.offset ?? 0)
//         let requestedLimit = max(0, input.limit ?? context.fileLimitBytes)
//         let limit = min(requestedLimit, context.fileLimitBytes)
//         let slice = String(text.dropFirst(offset).prefix(limit))
//         let suffix = text.count > offset + slice.count ? "\n[file truncated]" : ""
//         return .success(requestID: "", text: slice + suffix)
//     }
// }
// 
// private struct ListFilesTool: GrokCodeTool {
//     struct Input: Decodable {
//         var path: String?
//         var paths: [String]?
//         var recursive: Bool?
//         var limit: Int?
//     }
// 
//     let name = "list_files"
//     let description = "List files under a workspace directory."
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let requestedPaths = input.paths?.isEmpty == false ? input.paths ?? [] : [input.path ?? "."]
//         let recursive = input.recursive ?? false
//         let limit = min(max(input.limit ?? 200, 1), 1_000)
//         let fileManager = FileManager.default
//         var paths: [String] = []
//         var missingPaths: [String] = []
// 
//         for requestedPath in requestedPaths {
//             let root = try GrokCodePath.resolve(requestedPath, in: context.workingDirectory)
//             var isDirectory: ObjCBool = false
//             guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
//                 missingPaths.append(GrokCodePath.displayPath(root, relativeTo: context.workingDirectory))
//                 continue
//             }
// 
//             if !isDirectory.boolValue {
//                 paths.append(GrokCodePath.displayPath(root, relativeTo: context.workingDirectory))
//             } else if recursive {
//                 paths += try recursivePaths(root: root, workingDirectory: context.workingDirectory, limit: limit - paths.count)
//             } else {
//                 let urls = try fileManager.contentsOfDirectory(
//                     at: root,
//                     includingPropertiesForKeys: [.isDirectoryKey],
//                     options: [.skipsHiddenFiles]
//                 )
//                 paths += urls
//                     .prefix(limit - paths.count)
//                     .map { GrokCodePath.displayPath($0, relativeTo: context.workingDirectory) }
//             }
// 
//             if paths.count >= limit {
//                 break
//             }
//         }
// 
//         paths.sort()
//         let missingLines = missingPaths.sorted().map { "[missing] \($0)" }
//         let lines = missingLines + paths
//         let suffix = paths.count >= limit ? "\n[list truncated to \(limit) entries]" : ""
//         return .success(requestID: "", text: lines.joined(separator: "\n") + suffix)
//     }
// 
//     private func recursivePaths(root: URL, workingDirectory: URL, limit: Int) throws -> [String] {
//         guard let enumerator = FileManager.default.enumerator(
//             at: root,
//             includingPropertiesForKeys: [.isDirectoryKey],
//             options: [.skipsHiddenFiles, .skipsPackageDescendants]
//         ) else {
//             throw GrokCodeToolError.executionFailed("Could not list \(root.path).")
//         }
// 
//         var paths: [String] = []
//         for case let url as URL in enumerator {
//             paths.append(GrokCodePath.displayPath(url, relativeTo: workingDirectory))
//             if paths.count >= limit { break }
//         }
//         return paths
//     }
// }
// 
// private struct SearchTool: GrokCodeTool {
//     struct Input: Decodable {
//         var query: String
//         var paths: [String]?
//         var caseSensitive: Bool?
//         var maxResults: Int?
//     }
// 
//     let name = "search"
//     let description = "Search UTF-8 text files in the workspace."
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         guard !input.query.isEmpty else {
//             throw GrokCodeToolError.invalidInput("search requires query.")
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let roots = try (input.paths?.isEmpty == false ? input.paths ?? [] : ["."])
//             .map { try GrokCodePath.resolve($0, in: context.workingDirectory) }
//         let maxResults = min(max(input.maxResults ?? 100, 1), 500)
//         let caseSensitive = input.caseSensitive ?? false
//         let needle = caseSensitive ? input.query : input.query.lowercased()
//         var matches: [String] = []
// 
//         for file in try candidateFiles(roots: roots) {
//             guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
//             let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
//             for (index, line) in lines.enumerated() {
//                 let haystack = caseSensitive ? String(line) : line.lowercased()
//                 if haystack.contains(needle) {
//                     let path = GrokCodePath.displayPath(file, relativeTo: context.workingDirectory)
//                     matches.append("\(path):\(index + 1):\(line)")
//                     if matches.count >= maxResults {
//                         return .success(requestID: "", text: matches.joined(separator: "\n") + "\n[search truncated to \(maxResults) matches]")
//                     }
//                 }
//             }
//         }
// 
//         return .success(requestID: "", text: matches.isEmpty ? "[no matches]" : matches.joined(separator: "\n"))
//     }
// 
//     private func candidateFiles(roots: [URL]) throws -> [URL] {
//         let fileManager = FileManager.default
//         var files: [URL] = []
//         for root in roots {
//             var isDirectory: ObjCBool = false
//             guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
//             if !isDirectory.boolValue {
//                 files.append(root)
//                 continue
//             }
// 
//             guard let enumerator = fileManager.enumerator(
//                 at: root,
//                 includingPropertiesForKeys: [.isRegularFileKey],
//                 options: [.skipsHiddenFiles, .skipsPackageDescendants]
//             ) else {
//                 continue
//             }
//             for case let url as URL in enumerator {
//                 let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
//                 if values?.isRegularFile == true {
//                     files.append(url)
//                 }
//             }
//         }
//         return files
//     }
// }
// 
// private struct ShellTool: GrokCodeTool {
//     struct Input: Decodable {
//         var command: String
//         var timeoutSeconds: Double?
//     }
// 
//     let name = "shell"
//     let description = "Run a shell command in the workspace."
//     let isConcurrencySafeByDefault = false
//     let requiredPermission: GrokCodeToolPermission = .shell
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         guard !input.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
//             throw GrokCodeToolError.invalidInput("shell requires command.")
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let timeout = min(max(input.timeoutSeconds ?? context.shellTimeoutSeconds, 1), 120)
//         let result = try GrokCodeProcess.run(
//             executable: "/bin/sh",
//             arguments: ["-lc", input.command],
//             workingDirectory: context.workingDirectory,
//             timeoutSeconds: timeout
//         )
//         return GrokCodeToolResult(
//             requestID: "",
//             ok: result.exitCode == 0,
//             content: [.text(result.summary)],
//             error: result.exitCode == 0 ? nil : "Command exited \(result.exitCode)"
//         )
//     }
// }
// 
// private struct GitDiffTool: GrokCodeTool {
//     struct Input: Decodable {
//         var path: String?
//         var staged: Bool?
//     }
// 
//     let name = "git_diff"
//     let description = "Show git diff output for the workspace."
//     let isConcurrencySafeByDefault = false
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         var arguments = ["diff"]
//         if input.staged == true {
//             arguments.append("--staged")
//         }
//         if let path = input.path, !path.isEmpty {
//             arguments.append("--")
//             arguments.append(path)
//         }
// 
//         let result = try GrokCodeProcess.run(
//             executable: "/usr/bin/env",
//             arguments: ["git"] + arguments,
//             workingDirectory: context.workingDirectory,
//             timeoutSeconds: context.shellTimeoutSeconds
//         )
//         return GrokCodeToolResult(
//             requestID: "",
//             ok: result.exitCode == 0,
//             content: [.text(result.summary.isEmpty ? "[no diff]" : result.summary)],
//             error: result.exitCode == 0 ? nil : "git diff exited \(result.exitCode)"
//         )
//     }
// }
// 
// private struct ApplyPatchTool: GrokCodeTool {
//     struct Input: Decodable {
//         var patch: String
//     }
// 
//     let name = "apply_patch"
//     let description = "Apply a unified apply_patch patch to the workspace."
//     let isConcurrencySafeByDefault = false
//     let requiredPermission: GrokCodeToolPermission = .write
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         guard input.patch.contains("*** Begin Patch"), input.patch.contains("*** End Patch") else {
//             throw GrokCodeToolError.invalidInput("apply_patch requires a complete patch.")
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let result = try GrokCodeProcess.run(
//             executable: "/usr/bin/env",
//             arguments: ["apply_patch"],
//             workingDirectory: context.workingDirectory,
//             stdin: input.patch,
//             timeoutSeconds: context.shellTimeoutSeconds
//         )
//         return GrokCodeToolResult(
//             requestID: "",
//             ok: result.exitCode == 0,
//             content: [.text(result.summary)],
//             error: result.exitCode == 0 ? nil : "apply_patch exited \(result.exitCode)"
//         )
//     }
// }
// 
// private struct WriteFileTool: GrokCodeTool {
//     struct Input: Decodable {
//         var path: String
//         var content: String
//     }
// 
//     let name = "write_file"
//     let description = "Write a UTF-8 text file inside the workspace."
//     let isConcurrencySafeByDefault = false
//     let requiredPermission: GrokCodeToolPermission = .write
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         let trimmedPath = input.path.trimmingCharacters(in: .whitespacesAndNewlines)
//         guard !trimmedPath.isEmpty else {
//             throw GrokCodeToolError.invalidInput("write_file requires path.")
//         }
//         guard !trimmedPath.hasPrefix("/") else {
//             throw GrokCodeToolError.invalidInput("write_file path must be relative to the workspace.")
//         }
//         guard !trimmedPath.split(separator: "/").contains("..") else {
//             throw GrokCodeToolError.invalidInput("write_file path must not contain '..'.")
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let url = try GrokCodePath.resolve(input.path, in: context.workingDirectory)
//         guard GrokCodePath.isDescendant(url, of: context.workingDirectory) else {
//             throw GrokCodeToolError.permissionDenied("write_file path must stay inside the workspace.")
//         }
// 
//         try FileManager.default.createDirectory(
//             at: url.deletingLastPathComponent(),
//             withIntermediateDirectories: true
//         )
//         try input.content.write(to: url, atomically: true, encoding: .utf8)
// 
//         let bytes = input.content.data(using: .utf8)?.count ?? input.content.utf8.count
//         return .success(
//             requestID: "",
//             text: "Wrote \(GrokCodePath.displayPath(url, relativeTo: context.workingDirectory)) (\(bytes) bytes)"
//         )
//     }
// }
// 
// private struct WriteFilesTool: GrokCodeTool {
//     struct Input: Decodable {
//         var files: [FileInput]
//     }
// 
//     struct FileInput: Decodable {
//         var path: String
//         var content: String
//     }
// 
//     let name = "write_files"
//     let description = "Write multiple UTF-8 text files inside the workspace."
//     let isConcurrencySafeByDefault = false
//     let requiredPermission: GrokCodeToolPermission = .write
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         guard !input.files.isEmpty else {
//             throw GrokCodeToolError.invalidInput("write_files requires at least one file.")
//         }
//         guard input.files.count <= 24 else {
//             throw GrokCodeToolError.invalidInput("write_files accepts at most 24 files.")
//         }
// 
//         var seen = Set<String>()
//         for file in input.files {
//             let trimmedPath = file.path.trimmingCharacters(in: .whitespacesAndNewlines)
//             guard !trimmedPath.isEmpty else {
//                 throw GrokCodeToolError.invalidInput("write_files requires every file to have a path.")
//             }
//             guard !trimmedPath.hasPrefix("/") else {
//                 throw GrokCodeToolError.invalidInput("write_files paths must be relative to the workspace.")
//             }
//             guard !trimmedPath.split(separator: "/").contains("..") else {
//                 throw GrokCodeToolError.invalidInput("write_files paths must not contain '..'.")
//             }
//             guard seen.insert(trimmedPath).inserted else {
//                 throw GrokCodeToolError.invalidInput("write_files paths must be unique.")
//             }
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         var summaries: [String] = []
//         summaries.reserveCapacity(input.files.count)
// 
//         for file in input.files {
//             let url = try GrokCodePath.resolve(file.path, in: context.workingDirectory)
//             guard GrokCodePath.isDescendant(url, of: context.workingDirectory) else {
//                 throw GrokCodeToolError.permissionDenied("write_files paths must stay inside the workspace.")
//             }
// 
//             try FileManager.default.createDirectory(
//                 at: url.deletingLastPathComponent(),
//                 withIntermediateDirectories: true
//             )
//             try file.content.write(to: url, atomically: true, encoding: .utf8)
// 
//             let bytes = file.content.data(using: .utf8)?.count ?? file.content.utf8.count
//             summaries.append("Wrote \(GrokCodePath.displayPath(url, relativeTo: context.workingDirectory)) (\(bytes) bytes)")
//         }
// 
//         return .success(requestID: "", text: summaries.joined(separator: "\n"))
//     }
// }
// 
// private struct WritePlanTool: GrokCodeTool {
//     struct Input: Decodable {
//         var path: String
//         var content: String
//     }
// 
//     let name = "write_plan"
//     let description = "Write a Markdown plan file under plans/."
//     let isConcurrencySafeByDefault = false
//     let requiredPermission: GrokCodeToolPermission = .write
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {
//         guard input.path.hasPrefix("plans/"), input.path.hasSuffix(".md") else {
//             throw GrokCodeToolError.invalidInput("write_plan path must be a Markdown file under plans/.")
//         }
//     }
// 
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult {
//         let url = try GrokCodePath.resolve(input.path, in: context.workingDirectory)
//         try FileManager.default.createDirectory(
//             at: url.deletingLastPathComponent(),
//             withIntermediateDirectories: true
//         )
//         try input.content.write(to: url, atomically: true, encoding: .utf8)
//         return .success(requestID: "", text: "Wrote \(GrokCodePath.displayPath(url, relativeTo: context.workingDirectory))")
//     }
// }
// 
// private enum GrokCodePath {
//     static func resolve(_ path: String, in workingDirectory: URL) throws -> URL {
//         let expanded = NSString(string: path).expandingTildeInPath
//         let url = expanded.hasPrefix("/")
//             ? URL(fileURLWithPath: expanded)
//             : workingDirectory.appendingPathComponent(expanded)
//         return url.standardizedFileURL
//     }
// 
//     static func displayPath(_ url: URL, relativeTo root: URL) -> String {
//         let rootPath = root.standardizedFileURL.path
//         let path = url.standardizedFileURL.path
//         if path == rootPath {
//             return "."
//         }
//         if path.hasPrefix(rootPath + "/") {
//             return String(path.dropFirst(rootPath.count + 1))
//         }
//         return path
//     }
// 
//     static func isDescendant(_ url: URL, of root: URL) -> Bool {
//         let rootPath = root.standardizedFileURL.path
//         let path = url.standardizedFileURL.path
//         return path == rootPath || path.hasPrefix(rootPath + "/")
//     }
// }
// 
// private struct GrokCodeProcessResult {
//     var exitCode: Int32
//     var stdout: String
//     var stderr: String
// 
//     var summary: String {
//         [stdout, stderr].filter { !$0.isEmpty }.joined(separator: stderr.isEmpty ? "" : "\n")
//     }
// }
// 
// private enum GrokCodeProcess {
//     static func run(
//         executable: String,
//         arguments: [String],
//         workingDirectory: URL,
//         stdin: String? = nil,
//         timeoutSeconds: TimeInterval
//     ) throws -> GrokCodeProcessResult {
//         let process = Process()
//         process.executableURL = URL(fileURLWithPath: executable)
//         process.arguments = arguments
//         process.currentDirectoryURL = workingDirectory
// 
//         let stdout = Pipe()
//         let stderr = Pipe()
//         process.standardOutput = stdout
//         process.standardError = stderr
// 
//         let inputPipe = Pipe()
//         if stdin != nil {
//             process.standardInput = inputPipe
//         }
// 
//         try process.run()
// 
//         if let stdinData = stdin?.data(using: .utf8) {
//             inputPipe.fileHandleForWriting.write(stdinData)
//             try? inputPipe.fileHandleForWriting.close()
//         }
// 
//         let deadline = Date().addingTimeInterval(timeoutSeconds)
//         while process.isRunning && Date() < deadline {
//             Thread.sleep(forTimeInterval: 0.05)
//         }
//         if process.isRunning {
//             process.terminate()
//             throw GrokCodeToolError.executionFailed("Command timed out after \(Int(timeoutSeconds))s.")
//         }
// 
//         let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
//         let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
//         return GrokCodeProcessResult(
//             exitCode: process.terminationStatus,
//             stdout: String(data: stdoutData, encoding: .utf8) ?? "",
//             stderr: String(data: stderrData, encoding: .utf8) ?? ""
//         )
//     }
// }
