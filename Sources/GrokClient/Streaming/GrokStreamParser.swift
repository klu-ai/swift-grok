import Foundation

internal struct GrokStreamParser {
    internal private(set) var conversationId: String
    internal private(set) var responseId: String
    internal private(set) var accumulatedMessage: String
    internal private(set) var yieldedFinal: Bool
    internal private(set) var finished: Bool

    private typealias JSONDictionary = [String: Any]

    private static let nonTerminalEmptyTokenMarkerKeys = [
        "messageTag",
        "message_tag",
        "messageStepId",
        "message_step_id",
        "toolUsageCardId",
        "tool_usage_card_id",
        "toolUsageCard",
        "toolCallId",
        "tool_call_id",
        "toolName",
        "tool_name",
        "cardId",
        "card_id"
    ]

    internal init(initialConversationId: String = "") {
        self.conversationId = initialConversationId
        self.responseId = ""
        self.accumulatedMessage = ""
        self.yieldedFinal = false
        self.finished = false
    }

    internal mutating func consume(line: String) throws -> ConversationResponse? {
        guard !finished else { return nil }

        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("data:") {
            trimmed = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed == "[DONE]" {
            finished = true
            return finish()
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            return nil
        }

        if let error = json["error"] {
            throw GrokError.apiError(Self.describeAPIError(error))
        }

        let result = Self.dictionary(json["result"]) ?? json

        if let error = result["error"] {
            throw GrokError.apiError(Self.describeAPIError(error))
        }

        let response = Self.dictionary(result["response"])
        if let error = response?["error"] {
            throw GrokError.apiError(Self.describeAPIError(error))
        }

        if let conversation = Self.dictionary(result["conversation"]),
           let id = Self.stringValue(conversation, keys: ["conversationId", "id"]) {
            conversationId = id
        }

        let userResponse = Self.dictionary(response?["userResponse"]) ?? Self.dictionary(result["userResponse"])
        let modelResponse = Self.dictionary(response?["modelResponse"]) ?? Self.dictionary(result["modelResponse"])

        if let id = Self.stringValue(response, keys: ["responseId", "id"]) ??
            Self.stringValue(result, keys: ["responseId", "id"]) ??
            Self.stringValue(userResponse, keys: ["responseId", "id"]) ??
            Self.stringValue(modelResponse, keys: ["responseId", "id"]) {
            responseId = id
        }

        let isSoftStop = Self.boolValue(response, keys: ["isSoftStop"]) ??
            Self.boolValue(result, keys: ["isSoftStop"]) ??
            false
        let isThinking = Self.boolValue(response, keys: ["isThinking"]) ??
            Self.boolValue(result, keys: ["isThinking"]) ??
            false

        if let token = Self.stringValueAllowingEmpty(response, keys: ["token"]) ??
            Self.stringValueAllowingEmpty(result, keys: ["token"]) {
            let isFinal = Self.isTerminalEmptyToken(
                token,
                response: response,
                result: result,
                isThinking: isThinking,
                isSoftStop: isSoftStop
            )

            if isFinal {
                yieldedFinal = true
                finished = true
                return ConversationResponse(
                    message: accumulatedMessage,
                    conversationId: conversationId,
                    responseId: responseId,
                    timestamp: Date(),
                    webSearchResults: nil,
                    xposts: nil,
                    isSoftStop: isSoftStop,
                    isFinal: true
                )
            }

            if !isThinking {
                accumulatedMessage += token
            }

            return ConversationResponse(
                message: token,
                conversationId: conversationId,
                responseId: responseId,
                timestamp: Date(),
                webSearchResults: nil,
                xposts: nil,
                isThinking: isThinking,
                isSoftStop: isSoftStop,
                isFinal: false
            )
        }

        if let message = Self.stringValue(modelResponse, keys: ["message", "text"]) {
            yieldedFinal = true
            finished = true
            return ConversationResponse(
                message: message,
                conversationId: conversationId,
                responseId: responseId,
                timestamp: Date(),
                webSearchResults: Self.extractWebSearchResults(from: modelResponse),
                xposts: Self.extractXPosts(from: modelResponse),
                isSoftStop: false,
                isFinal: true
            )
        }

        return nil
    }

    internal mutating func finish() -> ConversationResponse? {
        guard !yieldedFinal else {
            finished = true
            return nil
        }

        let trimmed = accumulatedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finished = true
            return nil
        }

        yieldedFinal = true
        finished = true
        return ConversationResponse(
            message: trimmed,
            conversationId: conversationId,
            responseId: responseId,
            timestamp: Date(),
            webSearchResults: nil,
            xposts: nil,
            isSoftStop: false,
            isFinal: true
        )
    }

    private static func dictionary(_ value: Any?) -> JSONDictionary? {
        value as? JSONDictionary
    }

    private static func stringValue(_ dictionary: JSONDictionary?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func stringValueAllowingEmpty(_ dictionary: JSONDictionary?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func boolValue(_ dictionary: JSONDictionary?, keys: [String]) -> Bool? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }
        return nil
    }

    private static func containsAnyValue(_ dictionary: JSONDictionary?, keys: [String]) -> Bool {
        guard let dictionary else { return false }
        return keys.contains { dictionary[$0] != nil }
    }

    private static func isTerminalEmptyToken(
        _ token: String,
        response: JSONDictionary?,
        result: JSONDictionary,
        isThinking: Bool,
        isSoftStop: Bool
    ) -> Bool {
        token.isEmpty &&
            !isThinking &&
            !isSoftStop &&
            !containsAnyValue(response, keys: nonTerminalEmptyTokenMarkerKeys) &&
            !containsAnyValue(result, keys: nonTerminalEmptyTokenMarkerKeys)
    }

    private static func extractWebSearchResults(from modelResponse: JSONDictionary?) -> [WebSearchResult]? {
        guard let rawResults = modelResponse?["webSearchResults"] as? [JSONDictionary] else {
            return nil
        }

        let results = rawResults.compactMap { result -> WebSearchResult? in
            guard let url = stringValue(result, keys: ["url"]), !url.isEmpty else {
                return nil
            }

            return WebSearchResult(
                url: url,
                title: stringValue(result, keys: ["title", "metadataTitle"]) ?? url,
                preview: stringValue(result, keys: ["preview", "description", "searchEngineText"]) ?? "",
                siteName: stringValue(result, keys: ["siteName"]),
                description: stringValue(result, keys: ["description"]),
                citationId: stringValue(result, keys: ["citationId"])
            )
        }

        return results.isEmpty ? nil : results
    }

    private static func extractXPosts(from modelResponse: JSONDictionary?) -> [XPost]? {
        guard let rawPosts = modelResponse?["xposts"] as? [JSONDictionary] else {
            return nil
        }

        let posts = rawPosts.compactMap { post -> XPost? in
            guard let username = stringValue(post, keys: ["username"]), !username.isEmpty else {
                return nil
            }

            return XPost(
                username: username,
                name: stringValue(post, keys: ["name"]) ?? username,
                text: stringValue(post, keys: ["text", "message"]) ?? "",
                postId: stringValue(post, keys: ["postId", "id"]) ?? "",
                createTime: stringValue(post, keys: ["createTime"]),
                profileImageUrl: stringValue(post, keys: ["profileImageUrl"]),
                citationId: stringValue(post, keys: ["citationId"])
            )
        }

        return posts.isEmpty ? nil : posts
    }

    private static func describeAPIError(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }

        if let dict = value as? JSONDictionary {
            if let message = stringValue(dict, keys: ["message", "error", "description"]) {
                return message
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }

        return String(describing: value)
    }
}
