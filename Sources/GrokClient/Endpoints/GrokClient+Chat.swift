import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Chat
extension GrokClient {
    /// Prepares the default payload with the user's message.
    internal func preparePayload(
        message: String,
        options: GrokMessageOptions = GrokMessageOptions()
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "temporary": options.temporary,
            "message": message,
            "modeId": options.modeId,
            "imageAttachments": [],
            "fileAttachments": options.fileAttachments,
            "enableImageGeneration": true,
            "returnImageBytes": false,
            "returnRawGrokInXaiRequest": false,
            "enableImageStreaming": true,
            "imageGenerationCount": 2,
            "forceConcise": false,
            "enableSideBySide": true,
            "sendFinalMetadata": true,
            "disableTextFollowUps": false,
            "responseMetadata": [:],
            "disableMemory": false,
            "forceSideBySide": false,
            "isAsyncChat": false,
            "disableSelfHarmShortCircuit": false,
            "collectionIds": [],
            "disabledConnectorIds": options.disabledConnectorIds,
            "deviceEnvInfo": deviceEnvInfo()
        ]

        if !options.workspaceIds.isEmpty {
            payload["workspaceIds"] = options.workspaceIds
        }

        return payload
    }

    /// Prepares the default payload with the user's message.
    /// - Parameters:
    ///   - message: The user's input message
    ///   - enableReasoning: Deprecated and ignored since the Grok 4 release on 2025-07-09; reasoning is always enabled by Grok web modes.
    ///   - enableDeepSearch: Deprecated and ignored since Grok 4; deep research is no longer a Grok web feature.
    ///   - disableSearch: Deprecated and ignored since Grok 4; search is automatic and no longer configurable.
    ///   - customInstructions: Deprecated and ignored; configure instructions in Grok agent settings instead.
    ///   - temporary: Whether the message and thread should not be saved (private mode)
    ///   - personalityType: Deprecated; retained for source compatibility and no longer sent to Grok.
    /// - Returns: A dictionary representing the payload
    internal func preparePayload(
        message: String,
        enableReasoning: Bool = true,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none,
        modeId: String = GrokClient.defaultModeId,
        fileAttachments: [String] = [],
        workspaceIds: [String] = [],
        disabledConnectorIds: [String] = []
    ) -> [String: Any] {
        preparePayload(
            message: message,
            options: GrokMessageOptions(
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                disableSearch: disableSearch,
                customInstructions: customInstructions,
                temporary: temporary,
                personalityType: personalityType,
                modeId: modeId,
                fileAttachments: fileAttachments,
                workspaceIds: workspaceIds,
                disabledConnectorIds: disabledConnectorIds
            )
        )
    }

    /// Sends a message to Grok and returns a streaming response.
    public func streamMessage(
        message: String,
        options: GrokMessageOptions = GrokMessageOptions()
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let payload = preparePayload(message: message, options: options)
        let request = try makeRequest(path: "/conversations/new", payload: payload)
        return try await streamResponses(for: request, modeId: options.modeId)
    }

    /// Sends a message to Grok and returns a streaming response
    /// - Parameters:
    ///   - message: The user's input message
    ///   - enableReasoning: Deprecated and ignored since the Grok 4 release on 2025-07-09; reasoning is always enabled by Grok web modes.
    ///   - enableDeepSearch: Deprecated and ignored since Grok 4; deep research is no longer a Grok web feature.
    ///   - disableSearch: Deprecated and ignored since Grok 4; search is automatic and no longer configurable.
    ///   - customInstructions: Deprecated and ignored; configure instructions in Grok agent settings instead.
    ///   - temporary: Whether the message and thread should not be saved (private mode), defaults to false
    ///   - personalityType: Deprecated; retained for source compatibility and no longer sent to Grok.
    /// - Returns: An async stream of conversation responses from Grok
    /// - Throws: Network, decoding, or API errors
    public func streamMessage(
        message: String,
        enableReasoning: Bool = true,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none,
        modeId: String = GrokClient.defaultModeId,
        fileAttachments: [String] = [],
        workspaceIds: [String] = [],
        disabledConnectorIds: [String] = []
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        try await streamMessage(
            message: message,
            options: GrokMessageOptions(
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                disableSearch: disableSearch,
                customInstructions: customInstructions,
                temporary: temporary,
                personalityType: personalityType,
                modeId: modeId,
                fileAttachments: fileAttachments,
                workspaceIds: workspaceIds,
                disabledConnectorIds: disabledConnectorIds
            )
        )
    }

    /// Sends a single message (non-streaming).
    public func sendMessage(
        message: String,
        options: GrokMessageOptions = GrokMessageOptions()
    ) async throws -> ConversationResponse {
        let stream = try await streamMessage(message: message, options: options)

        var accumulated = ""
        var latest: ConversationResponse?
        for try await response in stream {
            if response.isFinal {
                latest = response
                break
            }
            accumulated += response.message
            latest = response
        }

        if let latest {
            if latest.isFinal {
                return latest
            }
            return ConversationResponse(
                message: accumulated.trimmingCharacters(in: .whitespacesAndNewlines),
                conversationId: latest.conversationId,
                responseId: latest.responseId,
                timestamp: Date(),
                webSearchResults: nil,
                xposts: nil,
                isSoftStop: false,
                isFinal: true
            )
        }

        throw GrokError.streamingError
    }

    /// Sends a single message (non-streaming).
    public func sendMessage(
        message: String,
        enableReasoning: Bool = true,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none,
        modeId: String = GrokClient.defaultModeId,
        fileAttachments: [String] = [],
        workspaceIds: [String] = [],
        disabledConnectorIds: [String] = []
    ) async throws -> ConversationResponse {
        try await sendMessage(
            message: message,
            options: GrokMessageOptions(
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                disableSearch: disableSearch,
                customInstructions: customInstructions,
                temporary: temporary,
                personalityType: personalityType,
                modeId: modeId,
                fileAttachments: fileAttachments,
                workspaceIds: workspaceIds,
                disabledConnectorIds: disabledConnectorIds
            )
        )
    }

    /// Sends a message to an existing conversation.
    public func continueConversation(
        conversationId: String,
        parentResponseId: String? = nil,
        message: String,
        options: GrokMessageOptions = GrokMessageOptions()
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        var payload = preparePayload(message: message, options: options)
        if let parentResponseId = parentResponseId {
            payload["parentResponseId"] = parentResponseId
        }

        let request = try makeRequest(path: "/conversations/\(conversationId)/responses", payload: payload)
        return try await streamResponses(for: request, initialConversationId: conversationId, modeId: options.modeId)
    }

    /// Sends a message to an existing conversation
    /// - Parameters:
    ///   - conversationId: The ID of the conversation to continue
    ///   - parentResponseId: The ID of the response this message is replying to (optional)
    ///   - message: The user's input message
    ///   - enableReasoning: Deprecated and ignored since the Grok 4 release on 2025-07-09; reasoning is always enabled by Grok web modes.
    ///   - enableDeepSearch: Deprecated and ignored since Grok 4; deep research is no longer a Grok web feature.
    ///   - disableSearch: Deprecated and ignored since Grok 4; search is automatic and no longer configurable.
    ///   - customInstructions: Deprecated and ignored; configure instructions in Grok agent settings instead.
    ///   - temporary: Whether the message and thread should not be saved (private mode), defaults to false
    ///   - personalityType: Deprecated; retained for source compatibility and no longer sent to Grok.
    /// - Returns: A tuple with the complete response, response ID, web search results, and X posts
    /// - Throws: Network, decoding, or API errors
    public func continueConversation(
        conversationId: String,
        parentResponseId: String? = nil,
        message: String,
        enableReasoning: Bool = true,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none,
        modeId: String = GrokClient.defaultModeId,
        fileAttachments: [String] = [],
        workspaceIds: [String] = [],
        disabledConnectorIds: [String] = []
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        try await continueConversation(
            conversationId: conversationId,
            parentResponseId: parentResponseId,
            message: message,
            options: GrokMessageOptions(
                enableReasoning: enableReasoning,
                enableDeepSearch: enableDeepSearch,
                disableSearch: disableSearch,
                customInstructions: customInstructions,
                temporary: temporary,
                personalityType: personalityType,
                modeId: modeId,
                fileAttachments: fileAttachments,
                workspaceIds: workspaceIds,
                disabledConnectorIds: disabledConnectorIds
            )
        )
    }

    private func deviceEnvInfo() -> [String: Any] {
        [
            "darkModeEnabled": true,
            "devicePixelRatio": 2,
            "screenWidth": 1728,
            "screenHeight": 1117,
            "viewportWidth": 1728,
            "viewportHeight": 564
        ]
    }
}
