// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// struct GrokCodeOptions {
//     var mode: GrokMode
//     var permissionMode: GrokCodePermissionMode
//     var outputFormat: OutputFormat
//     var privateMode: Bool
//     var dryRunSettings: Bool
//     var maxTurns: Int?
//     var agentTimeoutSeconds: Double?
//     var promptFile: String?
// 
//     init(
//         mode: GrokMode = .expert,
//         permissionMode: GrokCodePermissionMode = .default,
//         outputFormat: OutputFormat = .markdown,
//         privateMode: Bool = false,
//         dryRunSettings: Bool = false,
//         maxTurns: Int? = nil,
//         agentTimeoutSeconds: Double? = 90,
//         promptFile: String? = nil
//     ) {
//         self.mode = mode
//         self.permissionMode = permissionMode
//         self.outputFormat = outputFormat
//         self.privateMode = privateMode
//         self.dryRunSettings = dryRunSettings
//         self.maxTurns = maxTurns
//         self.agentTimeoutSeconds = agentTimeoutSeconds
//         self.promptFile = promptFile
//     }
// }
// 
// enum GrokCodeInvocation {
//     case interactive(GrokCodeOptions)
//     case print(GrokCodeOptions, task: String)
//     case restoreBackup(path: String, outputFormat: OutputFormat)
// }
// 
// extension GrokCodePermissionMode {
//     static func resolve(_ rawValue: String) -> GrokCodePermissionMode? {
//         switch rawValue
//             .trimmingCharacters(in: .whitespacesAndNewlines)
//             .lowercased()
//             .replacingOccurrences(of: "_", with: "-") {
//         case "default", "ask":
//             return .default
//         case "auto", "accept-edits", "acceptedits", "workspace-write", "workspacewrite":
//             return .acceptEdits
//         case "plan":
//             return .plan
//         case "read-only", "readonly", "read":
//             return .readOnly
//         case "bypass", "bypasspermissions", "trusted":
//             return .bypass
//         default:
//             return nil
//         }
//     }
// 
//     static var codeUsageValues: String {
//         "default, read-only, accept-edits, bypass, plan"
//     }
// }
// 
// extension GrokCodeOptions {
//     var json: [String: AnyCodable] {
//         var data: [String: AnyCodable] = [
//             "model": AnyCodable(GrokCLI.modeJSON(mode)),
//             "permissionMode": AnyCodable(permissionMode.rawValue),
//             "format": AnyCodable(outputFormat.description.lowercased()),
//             "private": AnyCodable(privateMode),
//             "dryRunSettings": AnyCodable(dryRunSettings)
//         ]
//         if let maxTurns {
//             data["maxTurns"] = AnyCodable(maxTurns)
//         }
//         if let agentTimeoutSeconds {
//             data["agentTimeoutSeconds"] = AnyCodable(agentTimeoutSeconds)
//         }
//         if let promptFile {
//             data["promptFile"] = AnyCodable(promptFile)
//         }
//         return data
//     }
// }
