import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleFilesCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")
        let jsonRequested = isJSONRequested(args)

        let parsed: ParsedFilesCommand
        do {
            parsed = try parseFilesCommand(args: args)
        } catch {
            if jsonRequested {
                printJSONError(
                    command: "files",
                    message: error.localizedDescription,
                    code: "usage_error",
                    exitCode: 2,
                    rawMessage: error.localizedDescription,
                    debug: debug
                )
            } else {
                await app.handleError(error, debug: debug)
            }
            if exitOnError {
                GrokCLI.exit(with: 2)
            }
            return
        }

        app.setDebugMode(parsed.debug && !parsed.json)
        if case .help(let usage) = parsed.action {
            print(usage)
            return
        }

        do {
            switch parsed.action {
            case .upload(let options):
                let mimeType = options.mimeType ?? inferredMimeType(for: options.path)
                let response = if app.usesXAIOAuthMode() {
                    try await app.uploadFileWithXAIOAuth(at: options.path, mimeType: mimeType)
                } else {
                    try await app.initializeClient().uploadFile(
                        at: options.path,
                        mimeType: mimeType
                    )
                }
                if parsed.json {
                    try printJSONResult(
                        command: "files",
                        subcommand: "upload",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "file",
                            action: "upload",
                            id: response.uploadedFileId,
                            item: AnyCodable(uploadJSON(response)),
                            raw: response.rawJSON
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Uploaded file".green.bold)
                printLabeledParts([
                    ("ID", response.uploadedFileId),
                    ("File", response.fileName ?? URL(fileURLWithPath: options.path).lastPathComponent)
                ])

            case .list(let options):
                let response = if app.usesXAIOAuthMode() {
                    try await app.listFilesWithXAIOAuth(pageSize: options.pageSize)
                } else {
                    try await app.initializeClient().listAssetsResponse(pageSize: options.pageSize)
                }
                if parsed.json {
                    try printJSONResult(
                        command: "files",
                        subcommand: "list",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "file",
                            items: response.assets.map { AnyCodable(assetJSON($0)) },
                            raw: response.rawJSON,
                            extra: ["pageSize": AnyCodable(options.pageSize)]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                printAssetRows(response.assets)

            case .delete(let fileId):
                let response = if app.usesXAIOAuthMode() {
                    try await app.deleteFileWithXAIOAuth(fileID: fileId)
                } else {
                    try await app.initializeClient().deleteAsset(assetId: fileId)
                }
                if parsed.json {
                    try printJSONResult(
                        command: "files",
                        subcommand: "delete",
                        category: "resource_mutation",
                        data: AnyCodable(resourceMutationJSON(
                            resource: "file",
                            action: "delete",
                            id: fileId,
                            item: response.asset.map { AnyCodable(assetJSON($0)) },
                            raw: response.rawJSON
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                print("Deleted file \(fileId)".green)

            case .help(_):
                return
            }
        } catch {
            if parsed.json {
                printJSONError(command: "files", error: error, exitCode: 1, debug: parsed.debug)
            } else {
                await app.handleError(error, debug: debug)
            }
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
        case delete(String)
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
        let json = try CLIOptionParsing.removeJSONOutputOptions(from: &remaining)
        let debug = CLIOptionParsing.removeFlag("--debug", from: &remaining)

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

        case "delete", "remove":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedFilesCommand(action: .help("Usage: \(filesDeleteUsage)"), json: json, debug: debug)
            }
            guard remaining.count == 2 else {
                throw GrokError.apiError("Usage: \(filesDeleteUsage)")
            }
            return ParsedFilesCommand(action: .delete(remaining[1]), json: json, debug: debug)

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

            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--mime", let inlineValue):
                (mimeType, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--mime")
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

            switch CLIOptionParsing.nameAndValue(arg) {
            case ("--page-size", let inlineValue):
                let value: String
                (value, index) = try CLIOptionParsing.readValue(inlineValue, args: args, index: index, option: "--page-size")
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
        printLabeledParts([
            ("ID", asset.resolvedId),
            ("File", asset.fileName ?? asset.name),
            ("MIME", asset.mimeType)
        ])
    }

    static var filesUsage: String {
        """
        Files:
          grok files upload <path> [--mime <mime>] [--json|--format json]
          grok files list [--json|--format json] [--page-size N]
          grok files delete <fileId> [--json|--format json]
        """
    }

    static var filesUploadUsage: String {
        "grok files upload <path> [--mime <mime>] [--json|--format json]"
    }

    static var filesListUsage: String {
        "grok files list [--json|--format json] [--page-size N]"
    }

    static var filesDeleteUsage: String {
        "grok files delete <fileId> [--json|--format json]"
    }
}
