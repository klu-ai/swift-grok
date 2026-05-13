import ArgumentParser
import Foundation
import GrokClient
import Rainbow

enum OutputFormat: Equatable {
    case markdown
    case raw
    case json

    static let defaultFormat: OutputFormat = .markdown

    var statusName: String {
        switch self {
        case .markdown:
            return "MD"
        case .raw:
            return "Raw"
        case .json:
            return "JSON"
        }
    }

    var description: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .raw:
            return "Raw"
        case .json:
            return "JSON"
        }
    }

    static func resolve(_ rawValue: String) -> OutputFormat? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "md", "markdown":
            return .markdown
        case "raw", "plain", "text":
            return .raw
        case "json":
            return .json
        default:
            return nil
        }
    }

    var isJSON: Bool {
        self == .json
    }
}

// Shared options for Grok commands
struct GrokCommandOptions: ParsableArguments {
    @Flag(name: .long, help: .hidden)
    var reasoning: Bool = false

    @Flag(name: .long, help: .hidden)
    var deepSearch: Bool = false

    @Flag(name: .long, help: .hidden)
    var noSearch: Bool = false

    @Flag(name: .shortAndLong, help: "Use markdown formatting in output (default)")
    var markdown: Bool = false

    @Flag(name: .long, help: "Show raw Markdown text in output")
    var raw: Bool = false

    @Flag(name: .long, help: "Emit scriptable JSON output")
    var json: Bool = false

    @Option(name: .long, help: "Output format: md, raw, or json")
    var format: String?

    @Flag(name: .long, help: "Show debug information")
    var debug: Bool = false

    @Flag(name: .long, help: .hidden)
    var noCustomInstructions: Bool = false

    @Flag(name: .customLong("private"), help: "Enable private mode (conversations will not be saved)")
    var privateMode: Bool = false

    @Flag(name: .long, help: "Enable streaming responses")
    var stream: Bool = true

    @Option(name: [.customLong("model"), .customLong("mode")], help: "Web mode to use: auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId")
    var model: String?

    func resolvedOutputFormat() throws -> OutputFormat {
        if let format {
            guard let resolved = OutputFormat.resolve(format) else {
                throw GrokError.apiError("Invalid --format value: \(format). Use md, raw, or json.")
            }
            return resolved
        }

        if json {
            return .json
        }

        if raw {
            return .raw
        }

        return .markdown
    }
}

extension GrokCLI {
    static let reasoningAlwaysOnWarning = "--reasoning is deprecated and ignored since the Grok 4 release on 2025-07-09; reasoning is always enabled for all models."
    static let interactiveReasoningAlwaysOnWarning = "/reason is deprecated and ignored since the Grok 4 release on 2025-07-09; reasoning is always enabled for all models."

    static func reasoningConfigurationWarnings(reasoningRequested: Bool) -> [String] {
        reasoningRequested ? [reasoningAlwaysOnWarning] : []
    }

    static func searchConfigurationWarnings(deepSearchRequested: Bool, noSearchRequested: Bool) -> [String] {
        var warnings: [String] = []
        if deepSearchRequested {
            warnings.append("--deep-search is deprecated and ignored; deep research is no longer a Grok 4 feature.")
        }
        if noSearchRequested {
            warnings.append("--no-search is deprecated and ignored; Grok 4 search is automatic and no longer configurable.")
        }
        return warnings
    }

    static func printSearchConfigurationWarnings(_ warnings: [String]) {
        for warning in warnings {
            print("Warning: \(warning)".yellow)
        }
    }

    static func customInstructionsWarnings(noCustomInstructionsRequested: Bool) -> [String] {
        guard noCustomInstructionsRequested else {
            return []
        }
        return ["--no-custom-instructions is deprecated and ignored; instructions are managed in Grok agent settings."]
    }
}
