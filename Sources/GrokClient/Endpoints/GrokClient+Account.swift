import Foundation

// MARK: - Account, Discovery, Modes, Settings
extension GrokClient {
    public func typeahead(
        query: String,
        lang: String = "en",
        maxItems: Int = 3,
        platform: String = "web",
        source: Int = 1
    ) async throws -> GrokTypeaheadResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return GrokTypeaheadResponse(suggestions: [], rawJSON: AnyCodable([:]))
        }

        let path = try endpointPath(
            ["_worker", "typeahead"],
            queryItems: [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "maxItems", value: String(maxItems)),
                URLQueryItem(name: "q", value: trimmedQuery),
                URLQueryItem(name: "platform", value: platform),
                URLQueryItem(name: "source", value: String(source))
            ]
        )

        let json = try await sendJSON(path: path, method: "GET", namespace: .web)
        return makeTypeaheadParserResponse(from: json, maxItems: maxItems)
    }

    public func listSkillsResponse(locale: String = "en") async throws -> GrokSkillsResponse {
        let json = try await sendJSON(path: "/skills", payload: ["locale": locale], namespace: .root)
        let skills = JSONLookup(json)
            .dictionaries(["skills", "data", "result", "items"])
            .map { makeResourceSkill(from: $0) }

        return GrokSkillsResponse(skills: skills, rawJSON: AnyCodable(json))
    }

    public func listSkills(locale: String = "en") async throws -> [GrokSkill] {
        try await listSkillsResponse(locale: locale).skills
    }

    public func listUserSkillsResponse() async throws -> GrokSkillsResponse {
        let json = try await sendJSON(path: "/user-skills", method: "GET", namespace: .root)
        let skills = JSONLookup(json)
            .dictionaries(["userSkills", "skills", "data", "result", "items"])
            .map { makeResourceSkill(from: $0) }

        return GrokSkillsResponse(skills: skills, rawJSON: AnyCodable(json))
    }

    public func listUserSkills() async throws -> [GrokSkill] {
        try await listUserSkillsResponse().skills
    }

    public func getUserSettingsResponse() async throws -> GrokAgentCustomizationsResponse {
        let json = try await sendJSON(path: "/user-settings", method: "GET", namespace: .root)
        return makeAccountAgentCustomizationsResponse(from: json)
    }

    public func updateAgentCustomizations(
        _ customizations: [GrokAgentCustomization]
    ) async throws -> GrokAgentCustomizationsResponse {
        let values = customizations
            .sorted { $0.agentId < $1.agentId }
            .map { customization in
                [
                    "agentId": customization.agentId,
                    "name": customization.agentId == 0 ? "Grok" : customization.name,
                    "instructions": customization.instructions
                ] as [String: Any]
            }

        let payload: [String: Any] = [
            "agentCustomizations": [
                "values": values
            ]
        ]

        let json = try await sendJSON(path: "/user-settings", payload: payload, namespace: .root)
        let response = makeAccountAgentCustomizationsResponse(from: json)

        if response.agentCustomizations.isEmpty {
            return GrokAgentCustomizationsResponse(agentCustomizations: customizations, rawJSON: AnyCodable(json))
        }

        return response
    }

    public func subscriptionsResponse() async throws -> GrokSubscriptionsResponse {
        let json = try await sendJSON(path: "/subscriptions", method: "GET", namespace: .root)
        return makeAccountSubscriptionsResponse(from: json)
    }

    public func currentSubscription() async throws -> GrokSubscription? {
        try await subscriptionsResponse().currentSubscription
    }

    public func rateLimits(modelName: String = GrokClient.defaultModeId) async throws -> GrokRateLimit {
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModelName = trimmedModelName.isEmpty ? GrokClient.defaultModeId : trimmedModelName
        let json = try await sendJSON(
            path: "/rate-limits",
            payload: ["modelName": resolvedModelName],
            namespace: .root
        )
        return makeParsedRateLimitResponse(from: json, requestedModelName: resolvedModelName)
    }

    public func rateLimits(mode: GrokMode) async throws -> GrokRateLimit {
        try await rateLimits(modelName: mode.id)
    }

    public func listModesResponse() async throws -> GrokModesResponse {
        let json = try await sendJSON(path: "/modes", payload: [:], namespace: .root)
        return GrokModesResponse(modes: GrokModeParser.modes(from: json), rawJSON: AnyCodable(json))
    }

    public func listModes() async throws -> [GrokMode] {
        try await listModesResponse().modes
    }
}
