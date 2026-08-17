import Foundation

struct GrokCodeToolExecutor {
    var registry: GrokCodeToolRegistry
    var parser: GrokCodeToolParser

    init(
        registry: GrokCodeToolRegistry = .builtin(),
        parser: GrokCodeToolParser = GrokCodeToolParser()
    ) {
        self.registry = registry
        self.parser = parser
    }

    func execute(request: GrokCodeToolRequest, context: GrokCodeToolUseContext) async -> GrokCodeToolResult {
        guard let tool = registry.tool(named: request.name) else {
            return .failure(requestID: request.id, message: "Unknown tool '\(request.name)'.")
        }

        let decision = GrokCodePermissionController(mode: context.permissionMode).decision(for: request, tool: tool)
        guard decision.isAllowed else {
            return .failure(requestID: request.id, message: decision.reason ?? "Permission denied")
        }

        return await tool.run(request: request, context: context)
    }

    func execute(parseResult: GrokCodeToolParseResult, context: GrokCodeToolUseContext) async -> GrokCodeToolResult {
        switch parseResult {
        case .request(let request):
            return await execute(request: request, context: context)
        case .failure(let result):
            return result
        }
    }

    func execute(toolCallsIn text: String, context: GrokCodeToolUseContext) async -> [GrokCodeToolResult] {
        let parseResults = parser.parse(text)
        var results: [GrokCodeToolResult] = []
        results.reserveCapacity(parseResults.count)

        for parseResult in parseResults {
            results.append(await execute(parseResult: parseResult, context: context))
        }

        return results
    }
}
