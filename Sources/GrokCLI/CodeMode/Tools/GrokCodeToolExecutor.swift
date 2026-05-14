// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// struct GrokCodeToolExecutor {
//     var registry: GrokCodeToolRegistry
//     var parser: GrokCodeToolParser
//     var permissionController: GrokCodePermissionController
// 
//     init(
//         registry: GrokCodeToolRegistry = .builtin(),
//         parser: GrokCodeToolParser = GrokCodeToolParser(),
//         permissionController: GrokCodePermissionController = GrokCodePermissionController()
//     ) {
//         self.registry = registry
//         self.parser = parser
//         self.permissionController = permissionController
//     }
// 
//     func execute(request: GrokCodeToolRequest, context: GrokCodeToolUseContext) async -> GrokCodeToolResult {
//         guard let tool = registry.tool(named: request.name) else {
//             return .failure(requestID: request.id, message: "Unknown tool '\(request.name)'.")
//         }
// 
//         let globalDecision = GrokCodePermissionController(mode: context.permissionMode).decision(for: request, tool: tool)
//         guard globalDecision.isAllowed else {
//             return .failure(requestID: request.id, message: globalDecision.reason ?? "Permission denied")
//         }
// 
//         return await tool.run(request: request, context: context)
//     }
// 
//     func execute(parseResult: GrokCodeToolParseResult, context: GrokCodeToolUseContext) async -> GrokCodeToolResult {
//         switch parseResult {
//         case .request(let request):
//             return await execute(request: request, context: context)
//         case .failure(let result):
//             return result
//         }
//     }
// 
//     func execute(toolCallsIn text: String, context: GrokCodeToolUseContext) async -> [GrokCodeToolResult] {
//         let parseResults = parser.parse(text)
//         var results: [GrokCodeToolResult] = []
//         results.reserveCapacity(parseResults.count)
// 
//         for parseResult in parseResults {
//             results.append(await execute(parseResult: parseResult, context: context))
//         }
// 
//         return results
//     }
// }
