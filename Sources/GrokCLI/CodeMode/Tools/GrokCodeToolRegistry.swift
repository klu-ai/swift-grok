import Foundation

struct GrokCodeToolRegistry {
    private var toolsByName: [String: AnyGrokCodeTool] = [:]
    private var aliases: [String: String] = [:]

    init(tools: [AnyGrokCodeTool] = [], aliases: [String: String] = [:]) {
        for tool in tools {
            register(tool)
        }
        for (alias, target) in aliases {
            register(alias: alias, target: target)
        }
    }

    var tools: [AnyGrokCodeTool] {
        toolsByName.values.sorted { $0.name < $1.name }
    }

    var schemas: [GrokCodeToolSchema] {
        tools.map(\.schema)
    }

    mutating func register(_ tool: AnyGrokCodeTool) {
        toolsByName[tool.name] = tool
    }

    mutating func register<T: GrokCodeTool>(_ tool: T) {
        register(AnyGrokCodeTool(tool))
    }

    mutating func register(alias: String, target: String) {
        aliases[alias] = target
    }

    func canonicalName(for name: String) -> String? {
        if toolsByName[name] != nil {
            return name
        }
        if let target = aliases[name], toolsByName[target] != nil {
            return target
        }
        return nil
    }

    func tool(named name: String) -> AnyGrokCodeTool? {
        guard let canonical = canonicalName(for: name) else {
            return nil
        }
        return toolsByName[canonical]
    }

    func contains(_ name: String) -> Bool {
        tool(named: name) != nil
    }

    func filtered(
        allowedTools: Set<String>? = nil,
        disallowedTools: Set<String> = [],
        permissionMode: GrokCodePermissionMode? = nil
    ) -> GrokCodeToolRegistry {
        let allowedCanonical = allowedTools.map { names in
            Set(names.compactMap { canonicalName(for: $0) ?? $0 })
        }
        let disallowedCanonical = Set(disallowedTools.map { canonicalName(for: $0) ?? $0 })
        let controller = permissionMode.map(GrokCodePermissionController.init(mode:))

        var filtered = GrokCodeToolRegistry()
        for tool in tools {
            if let allowedCanonical, !allowedCanonical.contains(tool.name) {
                continue
            }
            if disallowedCanonical.contains(tool.name) {
                continue
            }
            if let controller, controller.decision(for: tool.requiredPermission).isDenied {
                continue
            }
            filtered.register(tool)
        }

        for (alias, target) in aliases where filtered.toolsByName[target] != nil {
            filtered.register(alias: alias, target: target)
        }
        return filtered
    }

    func filtered(for mode: GrokCodePermissionMode) -> [AnyGrokCodeTool] {
        filtered(permissionMode: mode).tools
    }

    static func builtin() -> GrokCodeToolRegistry {
        var registry = GrokCodeToolRegistry()
        GrokCodeBuiltinTools.registerAll(into: &registry)
        return registry
    }
}
