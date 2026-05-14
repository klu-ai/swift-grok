// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// enum GrokCodePermissionMode: String, Codable, Equatable, CaseIterable, Sendable {
//     case `default`
//     case readOnly
//     case acceptEdits
//     case bypass
//     case plan
// }
// 
// enum GrokCodeToolPermission: String, Codable, Equatable, Sendable {
//     case read
//     case write
//     case shell
// }
// 
// enum GrokCodePermissionDecision: Codable, Equatable, Sendable {
//     case allow(reason: String? = nil)
//     case deny(reason: String)
//     case ask(reason: String)
// 
//     var isAllowed: Bool {
//         if case .allow = self {
//             return true
//         }
//         return false
//     }
// 
//     var requiresUserDecision: Bool {
//         if case .ask = self {
//             return true
//         }
//         return false
//     }
// 
//     var reason: String? {
//         switch self {
//         case .allow(let reason):
//             return reason
//         case .deny(let reason),
//              .ask(let reason):
//             return reason
//         }
//     }
// }
// 
// struct GrokCodePermissionController: Sendable {
//     var mode: GrokCodePermissionMode
// 
//     init(mode: GrokCodePermissionMode = .default) {
//         self.mode = mode
//     }
// 
//     func decision(for permission: GrokCodeToolPermission) -> GrokCodePermissionDecision {
//         switch mode {
//         case .bypass:
//             return .allow(reason: "Bypass mode allows all local tools.")
//         case .readOnly:
//             return permission == .read
//                 ? .allow(reason: "Read-only mode allows read tools.")
//                 : .deny(reason: "Permission mode readOnly denies \(permission.rawValue) tools.")
//         case .plan:
//             return permission == .read
//                 ? .allow(reason: "Plan mode allows read tools.")
//                 : .deny(reason: "Permission mode plan denies filesystem writes and shell execution.")
//         case .acceptEdits:
//             switch permission {
//             case .read, .write:
//                 return .allow(reason: "acceptEdits mode allows read and write tools.")
//             case .shell:
//                 return .ask(reason: "Shell execution requires approval in acceptEdits mode.")
//             }
//         case .default:
//             switch permission {
//             case .read:
//                 return .allow(reason: "Default mode allows read tools.")
//             case .write, .shell:
//                 return .ask(reason: "\(permission.rawValue.capitalized) tool requires approval.")
//             }
//         }
//     }
// 
//     func decision(for request: GrokCodeToolRequest, tool: AnyGrokCodeTool?) -> GrokCodePermissionDecision {
//         guard let tool else {
//             return .deny(reason: "Unknown tool '\(request.name)'.")
//         }
//         return decision(for: tool.requiredPermission)
//     }
// }
