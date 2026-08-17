import Foundation

extension GrokClient {
    public func createWorkspace(
        name: String = "workspace",
        icon: String = "l:book-open:lime",
        customPersonality: String = "New PROJECT WORKSPACE",
        preferredModel: String = "auto"
    ) async throws -> GrokWorkspaceMutationResponse {
        try await createWorkspace(
            options: GrokWorkspaceCreateOptions(
                name: name,
                icon: icon,
                customPersonality: customPersonality,
                preferredModel: preferredModel
            )
        )
    }

    public func createWorkspace(
        options: GrokWorkspaceCreateOptions
    ) async throws -> GrokWorkspaceMutationResponse {
        let payload: [String: Any] = [
            "name": options.name,
            "icon": options.icon,
            "customPersonality": options.customPersonality,
            "preferredModel": options.preferredModel
        ]

        let request = try makeRequest(
            path: try endpointPath(["workspaces"], queryItems: []),
            payload: payload,
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let workspace = firstWorkspaceMutationDictionary(from: json)
            .map { makeResourceWorkspace(from: $0) }

        return GrokWorkspaceMutationResponse(workspace: workspace, rawJSON: AnyCodable(json))
    }

    public func listWorkspacesResponse(
        pageSize: Int = 50,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> GrokWorkspacesResponse {
        try await listWorkspacesResponse(
            options: GrokWorkspaceListOptions(pageSize: pageSize, orderBy: orderBy)
        )
    }

    public func listWorkspacesResponse(
        options: GrokWorkspaceListOptions
    ) async throws -> GrokWorkspacesResponse {
        let queryItems = [
            URLQueryItem(name: "pageSize", value: String(options.pageSize)),
            URLQueryItem(name: "orderBy", value: options.orderBy)
        ]
        let request = try makeRequest(
            path: try endpointPath(["workspaces"], queryItems: queryItems),
            method: "GET",
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let workspaces = JSONLookup(json)
            .dictionaries(["workspaces", "data", "result", "items"])
            .map { makeResourceWorkspace(from: $0) }

        return GrokWorkspacesResponse(workspaces: workspaces, rawJSON: AnyCodable(json))
    }

    public func listWorkspaces(
        pageSize: Int = 50,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> [GrokWorkspace] {
        try await listWorkspaces(
            options: GrokWorkspaceListOptions(pageSize: pageSize, orderBy: orderBy)
        )
    }

    public func listWorkspaces(
        options: GrokWorkspaceListOptions
    ) async throws -> [GrokWorkspace] {
        try await listWorkspacesResponse(options: options).workspaces
    }

    public func deleteWorkspace(workspaceId: String) async throws -> GrokWorkspaceMutationResponse {
        let request = try makeRequest(
            path: try endpointPath(["workspaces", workspaceId], queryItems: []),
            method: "DELETE",
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let workspace = firstWorkspaceMutationDictionary(from: json)
            .map { makeResourceWorkspace(from: $0) }

        return GrokWorkspaceMutationResponse(workspace: workspace, rawJSON: AnyCodable(json))
    }

    public func addConversationToWorkspace(
        workspaceId: String,
        conversationId: String
    ) async throws -> GrokWorkspaceMutationResponse {
        let payload: [String: Any] = [
            "conversationId": conversationId
        ]

        let request = try makeRequest(
            path: try endpointPath(["workspaces", workspaceId, "conversations"], queryItems: []),
            payload: payload,
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let workspace = firstWorkspaceMutationDictionary(from: json)
            .map { makeResourceWorkspace(from: $0) }

        return GrokWorkspaceMutationResponse(workspace: workspace, rawJSON: AnyCodable(json))
    }

    private func firstWorkspaceMutationDictionary(from json: Any) -> [String: AnyCodable]? {
        JSONLookup(json).firstDictionary(["workspace", "data", "result"]) ??
            JSONLookup(json).rawAnyCodable.value as? [String: AnyCodable]
    }
}
