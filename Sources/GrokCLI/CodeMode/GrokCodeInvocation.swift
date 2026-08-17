import Foundation
import GrokClient

enum GrokCodeOutputFormat: String, Codable, Equatable {
    case markdown = "md"
    case raw
    case json
    case streamingJSON = "streaming-json"

    static let defaultFormat: GrokCodeOutputFormat = .markdown

    static func resolve(_ rawValue: String) -> GrokCodeOutputFormat? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "md", "markdown":
            return .markdown
        case "raw", "plain", "text":
            return .raw
        case "json":
            return .json
        case "streaming-json", "streaming_json", "ndjson", "jsonl":
            return .streamingJSON
        default:
            return nil
        }
    }

    var isJSONLike: Bool {
        self == .json || self == .streamingJSON
    }

    var outputFormatterFormat: OutputFormat {
        switch self {
        case .markdown:
            return .markdown
        case .raw, .streamingJSON:
            return .raw
        case .json:
            return .json
        }
    }

    var statusName: String {
        switch self {
        case .markdown:
            return "MD"
        case .raw:
            return "Raw"
        case .json:
            return "JSON"
        case .streamingJSON:
            return "Streaming JSON"
        }
    }
}

extension GrokCodePermissionMode {
    static func resolve(_ rawValue: String) -> GrokCodePermissionMode? {
        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-") {
        case "default", "ask":
            return .default
        case "auto", "accept-edits", "acceptedits", "workspace-write", "workspacewrite":
            return .acceptEdits
        case "plan":
            return .plan
        case "read-only", "readonly", "read":
            return .readOnly
        case "bypass", "bypasspermissions", "bypass-permissions", "dontask", "dont-ask", "trusted":
            return .bypass
        default:
            return nil
        }
    }

    static var codeUsageValues: String {
        "default, read-only, accept-edits, bypass, plan"
    }

    var codeRawValue: String {
        switch self {
        case .default:
            return "default"
        case .readOnly:
            return "read-only"
        case .acceptEdits:
            return "accept-edits"
        case .bypass:
            return "bypass"
        case .plan:
            return "plan"
        }
    }
}

struct GrokCodeOptions {
    var requestedModel: GrokMode?
    var resolvedModel: GrokMode?
    var permissionMode: GrokCodePermissionMode
    var outputFormat: GrokCodeOutputFormat
    var privateMode: Bool
    var maxTurns: Int
    var promptFile: String?
    var allowedTools: [String]
    var disallowedTools: [String]
    var rules: [String]
    var cwd: URL

    init(
        requestedModel: GrokMode? = nil,
        resolvedModel: GrokMode? = nil,
        permissionMode: GrokCodePermissionMode = .default,
        outputFormat: GrokCodeOutputFormat = .defaultFormat,
        privateMode: Bool = false,
        maxTurns: Int = 8,
        promptFile: String? = nil,
        allowedTools: [String] = [],
        disallowedTools: [String] = [],
        rules: [String] = [],
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) {
        self.requestedModel = requestedModel
        self.resolvedModel = resolvedModel
        self.permissionMode = permissionMode
        self.outputFormat = outputFormat
        self.privateMode = privateMode
        self.maxTurns = maxTurns
        self.promptFile = promptFile
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.rules = rules
        self.cwd = cwd
    }
}

enum GrokCodeInvocation {
    case run(options: GrokCodeOptions, task: String?)
}

struct GrokCodeUsageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

extension GrokCodeOptions {
    var activeToolNames: [String] {
        let defaultTools = [
            "run_terminal_cmd",
            "read_file",
            "grep",
            "list_dir",
            "search_replace",
            "apply_patch"
        ]
        let selected = allowedTools.isEmpty ? defaultTools : allowedTools
        let denied = Set(disallowedTools)
        return selected.filter { !denied.contains($0) }
    }

    var json: [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "permissionMode": AnyCodable(permissionMode.codeRawValue),
            "format": AnyCodable(outputFormat.rawValue),
            "private": AnyCodable(privateMode),
            "maxTurns": AnyCodable(maxTurns),
            "cwd": AnyCodable(cwd.path),
            "tools": AnyCodable(activeToolNames)
        ]
        if let requestedModel {
            data["requestedModel"] = AnyCodable(GrokCLI.modeJSON(requestedModel))
        }
        if let resolvedModel {
            data["resolvedModel"] = AnyCodable(GrokCLI.modeJSON(resolvedModel))
        }
        if let promptFile {
            data["promptFile"] = AnyCodable(promptFile)
        }
        if !allowedTools.isEmpty {
            data["allowedTools"] = AnyCodable(allowedTools)
        }
        if !disallowedTools.isEmpty {
            data["disallowedTools"] = AnyCodable(disallowedTools)
        }
        if !rules.isEmpty {
            data["rules"] = AnyCodable(rules)
        }
        return data
    }
}

enum GrokCodeModelResolver {
    static func resolveDefault(from modelIDs: [String]) -> GrokMode? {
        if modelIDs.contains("grok-build-0.1") {
            return GrokMode(id: "grok-build-0.1", displayName: "grok-build-0.1", summary: "xAI API model")
        }

        if modelIDs.contains("grok-code-fast") {
            return GrokMode(id: "grok-code-fast", displayName: "grok-code-fast", summary: "xAI API model")
        }

        guard let buildModel = modelIDs.first(where: {
            $0.localizedCaseInsensitiveContains("grok-build") ||
                $0.localizedCaseInsensitiveContains("grok-code")
        }) else {
            return nil
        }
        return GrokMode(id: buildModel, displayName: buildModel, summary: "xAI API model")
    }
}
