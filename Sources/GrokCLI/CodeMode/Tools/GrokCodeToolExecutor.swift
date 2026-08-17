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
        switch decision {
        case .allow:
            break
        case .deny(let reason):
            return .failure(requestID: request.id, message: reason)
        case .ask(let reason):
            if shouldPromptForApproval() {
                let approved = promptForApproval(tool: tool, request: request, reason: reason)
                if !approved {
                    return .failure(requestID: request.id, message: "Action rejected by user: \(reason)")
                }
            } else {
                return .failure(requestID: request.id, message: "\(reason) Run with --permission-mode accept-edits or --permission-mode bypass to execute non-interactively.")
            }
        }

        return await tool.run(request: request, context: context)
    }

    private func shouldPromptForApproval() -> Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }

    private func promptForApproval(tool: AnyGrokCodeTool, request: GrokCodeToolRequest, reason: String) -> Bool {
        print("\n[Permission] Grok Code requested \(tool.requiredPermission.rawValue) tool '\(request.name)' (\(reason))")
        print("Allow this action? [y/N]: ", terminator: "")
        fflush(stdout)
        guard let line = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return line == "y" || line == "yes"
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
