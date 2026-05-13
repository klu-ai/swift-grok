import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleFilesCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")

        let parsed: ParsedFilesCommand
        do {
            parsed = try parseFilesCommand(args: args)
        } catch {
            await app.handleError(error, debug: debug)
            if exitOnError {
                GrokCLI.exit(with: 2)
            }
            return
        }

        app.setDebugMode(parsed.debug)
        if case .help(let usage) = parsed.action {
            print(usage)
            return
        }

        do {
            let client = try app.initializeClient()
            switch parsed.action {
            case .upload(let options):
                let response = try await client.uploadFile(
                    at: options.path,
                    mimeType: options.mimeType ?? inferredMimeType(for: options.path)
                )
                if parsed.json {
                    try printFilesJSON(response.rawJSON)
                    return
                }
                print("Uploaded file".green.bold)
                printFilesParts([
                    ("ID", response.uploadedFileId),
                    ("File", response.fileName ?? URL(fileURLWithPath: options.path).lastPathComponent)
                ])

            case .list(let options):
                let response = try await client.listAssetsResponse(pageSize: options.pageSize)
                if parsed.json {
                    try printFilesJSON(response.rawJSON)
                    return
                }
                printAssetRows(response.assets)

            case .help(_):
                return
            }
        } catch {
            await app.handleError(error, debug: debug)
            if exitOnError {
                GrokCLI.exit(with: 1)
            }
        }
    }
}

private extension GrokCLI {
    enum FilesAction {
        case upload(FileUploadOptions)
        case list(FileListOptions)
        case help(String)
    }

    struct ParsedFilesCommand {
        let action: FilesAction
        let json: Bool
        let debug: Bool
    }

    struct FileUploadOptions {
        let path: String
        let mimeType: String?
    }

    struct FileListOptions {
        let pageSize: Int
    }

    static func parseFilesCommand(args: [String]) throws -> ParsedFilesCommand {
        var remaining = args
        let json = removeFilesFlag("--json", from: &remaining)
        let debug = removeFilesFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedFilesCommand(action: .list(FileListOptions(pageSize: 9)), json: json, debug: debug)
        }

        switch command {
        case "upload":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedFilesCommand(action: .help("Usage: \(filesUploadUsage)"), json: json, debug: debug)
            }
            let options = try parseFileUploadOptions(args: Array(remaining.dropFirst()))
            return ParsedFilesCommand(action: .upload(options), json: json, debug: debug)

        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedFilesCommand(action: .help("Usage: \(filesListUsage)"), json: json, debug: debug)
            }
            let options = try parseFileListOptions(args: Array(remaining.dropFirst()))
            return ParsedFilesCommand(action: .list(options), json: json, debug: debug)

        case "help", "-h", "--help":
            return ParsedFilesCommand(action: .help(filesUsage), json: json, debug: debug)

        default:
            throw GrokError.apiError("Unknown files command: \(command)\n\(filesUsage)")
        }
    }

    static func parseFileUploadOptions(args: [String]) throws -> FileUploadOptions {
        var path: String?
        var mimeType: String?

        var index = 0
        while index < args.count {
            let arg = args[index]

            switch filesOptionNameAndValue(arg) {
            case ("--mime", let inlineValue):
                (mimeType, index) = try readFilesOptionValue(inlineValue, args: args, index: index, option: "--mime")
            default:
                if arg.hasPrefix("--") {
                    throw GrokError.apiError("Unknown option for files upload: \(arg)\n\(filesUploadUsage)")
                }
                guard path == nil else {
                    throw GrokError.apiError("Usage: \(filesUploadUsage)")
                }
                path = arg
            }

            index += 1
        }

        guard let path else {
            throw GrokError.apiError("Missing file path.\n\(filesUploadUsage)")
        }

        return FileUploadOptions(path: path, mimeType: mimeType)
    }

    static func parseFileListOptions(args: [String]) throws -> FileListOptions {
        var pageSize = 9

        var index = 0
        while index < args.count {
            let arg = args[index]

            switch filesOptionNameAndValue(arg) {
            case ("--page-size", let inlineValue):
                let value: String
                (value, index) = try readFilesOptionValue(inlineValue, args: args, index: index, option: "--page-size")
                guard let parsed = Int(value), parsed > 0 else {
                    throw GrokError.apiError("--page-size must be a positive integer")
                }
                pageSize = parsed
            default:
                throw GrokError.apiError("Unknown option for files list: \(arg)\n\(filesListUsage)")
            }

            index += 1
        }

        return FileListOptions(pageSize: pageSize)
    }

    static func removeFilesFlag(_ flag: String, from args: inout [String]) -> Bool {
        let originalCount = args.count
        args.removeAll { $0 == flag }
        return args.count != originalCount
    }

    static func filesOptionNameAndValue(_ arg: String) -> (String, String?) {
        guard let separator = arg.firstIndex(of: "=") else {
            return (arg, nil)
        }
        return (String(arg[..<separator]), String(arg[arg.index(after: separator)...]))
    }

    static func readFilesOptionValue(
        _ inlineValue: String?,
        args: [String],
        index: Int,
        option: String
    ) throws -> (String, Int) {
        if let inlineValue {
            guard !inlineValue.isEmpty else {
                throw GrokError.apiError("\(option) requires a value")
            }
            return (inlineValue, index)
        }

        let nextIndex = index + 1
        guard nextIndex < args.count, !args[nextIndex].hasPrefix("--") else {
            throw GrokError.apiError("\(option) requires a value")
        }
        return (args[nextIndex], nextIndex)
    }

    static func inferredMimeType(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "txt":
            return "text/plain"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "pdf":
            return "application/pdf"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "md":
            return "text/markdown"
        default:
            return "application/octet-stream"
        }
    }

    static func printFilesJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static func printAssetRows(_ assets: [GrokAsset]) {
        guard !assets.isEmpty else {
            print("No files found.".yellow)
            return
        }

        print("Files:".cyan.bold)
        for asset in assets {
            printAssetSummary(asset)
        }
    }

    static func printAssetSummary(_ asset: GrokAsset) {
        printFilesParts([
            ("ID", asset.resolvedId),
            ("File", asset.fileName ?? asset.name),
            ("MIME", asset.mimeType)
        ])
    }

    static func printFilesParts(_ parts: [(String, String?)]) {
        let text = parts.compactMap { label, value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return "\(label): \(value)"
        }

        print(text.isEmpty ? "(no summary available)" : text.joined(separator: " | "))
    }

    static var filesUsage: String {
        """
        Files:
          grok files upload <path> [--mime <mime>] [--json]
          grok files list [--json] [--page-size N]
        """
    }

    static var filesUploadUsage: String {
        "grok files upload <path> [--mime <mime>] [--json]"
    }

    static var filesListUsage: String {
        "grok files list [--json] [--page-size N]"
    }
}
