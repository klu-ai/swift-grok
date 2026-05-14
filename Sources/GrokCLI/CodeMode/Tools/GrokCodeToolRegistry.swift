// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// struct GrokCodeToolRegistry {
//     private var toolsByName: [String: AnyGrokCodeTool] = [:]
//     private var aliases: [String: String] = [:]
// 
//     init(tools: [AnyGrokCodeTool] = [], aliases: [String: String] = [:]) {
//         for tool in tools {
//             register(tool)
//         }
//         for (alias, target) in aliases {
//             register(alias: alias, target: target)
//         }
//     }
// 
//     var tools: [AnyGrokCodeTool] {
//         toolsByName.values.sorted { $0.name < $1.name }
//     }
// 
//     mutating func register(_ tool: AnyGrokCodeTool) {
//         toolsByName[tool.name] = tool
//     }
// 
//     mutating func register<T: GrokCodeTool>(_ tool: T) {
//         register(AnyGrokCodeTool(tool))
//     }
// 
//     mutating func register(alias: String, target: String) {
//         aliases[alias] = target
//     }
// 
//     func tool(named name: String) -> AnyGrokCodeTool? {
//         if let tool = toolsByName[name] {
//             return tool
//         }
//         if let target = aliases[name] {
//             return toolsByName[target]
//         }
//         return nil
//     }
// 
//     func contains(_ name: String) -> Bool {
//         tool(named: name) != nil
//     }
// 
//     func filtered(for mode: GrokCodePermissionMode) -> [AnyGrokCodeTool] {
//         let controller = GrokCodePermissionController(mode: mode)
//         return tools.filter { tool in
//             !controller.decision(for: tool.requiredPermission).isDenied
//         }
//     }
// 
//     static func builtin() -> GrokCodeToolRegistry {
//         var registry = GrokCodeToolRegistry()
//         GrokCodeBuiltinTools.registerAll(into: &registry)
//         return registry
//     }
// }
// 
// private extension GrokCodePermissionDecision {
//     var isDenied: Bool {
//         if case .deny = self {
//             return true
//         }
//         return false
//     }
// }
