import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Error Handling
public enum GrokError: Error, Equatable, LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case notFound
    case accessDenied(String)
    case apiError(String)
    case streamingError

    public static func == (lhs: GrokError, rhs: GrokError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidCredentials, .invalidCredentials),
             (.unauthorized, .unauthorized),
             (.notFound, .notFound),
             (.streamingError, .streamingError):
            return true
        case (.apiError(let lhsMessage), .apiError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.accessDenied(let lhsMessage), .accessDenied(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.networkError, .networkError),
             (.decodingError, .decodingError):
            // Note: Cannot compare the associated Error values directly
            // Just checking if they are the same type of error
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid or missing Grok credentials"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Could not decode Grok response: \(error.localizedDescription)"
        case .unauthorized:
            return "Grok rejected the saved cookies. Re-run `grok auth generate` after logging in."
        case .notFound:
            return "Grok API endpoint was not found"
        case .accessDenied(let message):
            return message
        case .apiError(let message):
            return message
        case .streamingError:
            return "Could not read Grok streaming response"
        }
    }
}

public struct GrokMode: Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let summary: String
    public let isAvailable: Bool
    public let unavailableReason: String?
    public let minimumSubscriptionTier: String?

    public init(
        id: String,
        displayName: String? = nil,
        summary: String = "",
        isAvailable: Bool = true,
        unavailableReason: String? = nil,
        minimumSubscriptionTier: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.summary = summary
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
        self.minimumSubscriptionTier = minimumSubscriptionTier
    }

    public var unavailableDescription: String? {
        guard !isAvailable else {
            return nil
        }
        if let unavailableReason, !unavailableReason.isEmpty {
            return unavailableReason
        }
        if let minimumSubscriptionTier, !minimumSubscriptionTier.isEmpty {
            return "Requires \(minimumSubscriptionTier)"
        }
        return "Unavailable for this account"
    }

    public static let auto = GrokMode(
        id: "auto",
        displayName: "Auto",
        summary: "Chooses Fast or Expert"
    )

    public static let fast = GrokMode(
        id: "fast",
        displayName: "Fast",
        summary: "Quick responses"
    )

    public static let expert = GrokMode(
        id: "expert",
        displayName: "Expert",
        summary: "Thinks hard"
    )

    public static let grok43Beta = GrokMode(
        id: "grok-420-computer-use-sa",
        displayName: "Grok 4.3 (beta)",
        summary: "Uses Skills and Connectors"
    )

    public static let heavy = GrokMode(
        id: "heavy",
        displayName: "Heavy",
        summary: "Team of Experts"
    )

    public static let defaultMode = fast
    public static let knownModes = [auto, fast, expert, grok43Beta, heavy]

    public static func resolve(_ rawValue: String?) -> GrokMode {
        guard let rawValue else {
            return defaultMode
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultMode
        }

        let normalized = normalizedToken(trimmed)

        switch normalized {
        case "auto":
            return .auto
        case "fast":
            return .fast
        case "expert", "reasoning", "think":
            return .expert
        case "heavy":
            return .heavy
        case "grok-4.3", "grok-4-3", "grok-43", "4.3", "43", "beta", "grok-4.3-beta", "grok-4-3-beta", "grok-43-beta", "grok-420", "grok-420-computer-use-sa":
            return .grok43Beta
        default:
            return GrokMode(id: trimmed, displayName: trimmed, summary: "Custom web mode ID")
        }
    }

    public static func resolve(_ rawValue: String?, modes: [GrokMode]) -> GrokMode {
        guard let rawValue else {
            return modes.first { $0.id == defaultMode.id } ?? defaultMode
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return modes.first { $0.id == defaultMode.id } ?? defaultMode
        }

        let normalized = normalizedToken(trimmed)
        if let exactMode = modes.first(where: { mode in
            normalizedToken(mode.id) == normalized ||
                normalizedToken(mode.displayName) == normalized
        }) {
            return exactMode
        }

        let resolved = resolve(trimmed)
        if let catalogMode = modes.first(where: { $0.id == resolved.id }) {
            return catalogMode
        }
        return resolved
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Response Models
public struct MessageResponse: Codable {
    public let message: String
    public let timestamp: Date?

    public init(message: String, timestamp: Date? = nil) {
        self.message = message
        self.timestamp = timestamp
    }
}

public struct GrokSpeechToTextResponse: Codable {
    public let text: String
    public let rawJSON: AnyCodable

    public init(text: String, rawJSON: AnyCodable) {
        self.text = text
        self.rawJSON = rawJSON
    }
}

public struct GrokRateLimit: Codable {
    public let modelName: String?
    public let remainingResponses: Int?
    public let resetAt: Date?
    public let resetAfterSeconds: Int?
    public let windowSeconds: Int?
    public let fetchedAt: Date
    public let rawJSON: AnyCodable

    public init(
        modelName: String? = nil,
        remainingResponses: Int? = nil,
        resetAt: Date? = nil,
        resetAfterSeconds: Int? = nil,
        windowSeconds: Int? = nil,
        fetchedAt: Date = Date(),
        rawJSON: AnyCodable
    ) {
        self.modelName = modelName
        self.remainingResponses = remainingResponses
        self.resetAt = resetAt
        self.resetAfterSeconds = resetAfterSeconds
        self.windowSeconds = windowSeconds
        self.fetchedAt = fetchedAt
        self.rawJSON = rawJSON
    }

    public var isLow: Bool {
        guard let remainingResponses else {
            return false
        }
        return remainingResponses < 10
    }

    public func secondsUntilReset(from now: Date = Date()) -> Int? {
        if let resetAt {
            return max(0, Int(ceil(resetAt.timeIntervalSince(now))))
        }

        if let resetAfterSeconds {
            let elapsed = now.timeIntervalSince(fetchedAt)
            return max(0, Int(ceil(TimeInterval(resetAfterSeconds) - elapsed)))
        }

        return nil
    }
}

public struct GrokSubscription {
    public let tier: String?
    public let name: String?
    public let status: String?
    public let isActive: Bool
    public let rawJSON: [String: AnyCodable]

    public init(
        tier: String? = nil,
        name: String? = nil,
        status: String? = nil,
        isActive: Bool = true,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.tier = tier
        self.name = name
        self.status = status
        self.isActive = isActive
        self.rawJSON = rawJSON
    }

    public var displayName: String {
        Self.displayName(tier: tier, name: name, rawJSON: rawJSON)
    }

    public static func displayName(
        tier: String?,
        name: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) -> String {
        let rawValues = [
            "subscriptionTier",
            "subscription_tier",
            "tier",
            "tierName",
            "tier_name",
            "plan",
            "planName",
            "plan_name",
            "productName",
            "product_name",
            "displayName",
            "display_name",
            "name",
            "title",
            "sku"
        ].compactMap { rawJSON[$0]?.value as? String }

        let tokens = ([tier, name].compactMap { $0 } + rawValues)
            .map(normalizedPlanToken)
            .filter { !$0.isEmpty }

        if tokens.contains(where: { $0.contains("heavy") }) {
            return "SuperGrok Heavy"
        }
        if tokens.contains(where: { $0.contains("supergrok") || ($0.contains("super") && $0.contains("grok")) }) {
            return "SuperGrok"
        }
        return "Grok"
    }

    private static func normalizedPlanToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }
}

public struct GrokSubscriptionsResponse {
    public let subscriptions: [GrokSubscription]
    public let currentSubscription: GrokSubscription?
    public let rawJSON: AnyCodable

    public init(
        subscriptions: [GrokSubscription],
        currentSubscription: GrokSubscription?,
        rawJSON: AnyCodable
    ) {
        self.subscriptions = subscriptions
        self.currentSubscription = currentSubscription
        self.rawJSON = rawJSON
    }

    public var displayName: String {
        currentSubscription?.displayName ?? "Grok"
    }
}

// Add WebSearchResult struct
public struct WebSearchResult: Codable {
    public let url: String
    public let title: String
    public let preview: String
    public let siteName: String?
    public let description: String?
    public let citationId: String?

    public init(url: String, title: String, preview: String, siteName: String? = nil, description: String? = nil, citationId: String? = nil) {
        self.url = url
        self.title = title
        self.preview = preview
        self.siteName = siteName
        self.description = description
        self.citationId = citationId
    }
}

// Add XPost struct
public struct XPost: Codable {
    public let username: String
    public let name: String
    public let text: String
    public let createTime: String?
    public let profileImageUrl: String?
    public let postId: String
    public let citationId: String?

    public init(username: String, name: String, text: String, postId: String, createTime: String? = nil, profileImageUrl: String? = nil, citationId: String? = nil) {
        self.username = username
        self.name = name
        self.text = text
        self.postId = postId
        self.createTime = createTime
        self.profileImageUrl = profileImageUrl
        self.citationId = citationId
    }
}

public struct ConversationResponse: Codable {
    public let message: String
    public let conversationId: String
    public let responseId: String
    public let timestamp: Date?
    public let webSearchResults: [WebSearchResult]?
    public let xposts: [XPost]?
    public let isThinking: Bool
    public let isSoftStop: Bool
    public let isFinal: Bool

    private enum CodingKeys: String, CodingKey {
        case message
        case conversationId
        case responseId
        case timestamp
        case webSearchResults
        case xposts
        case isThinking
        case isSoftStop
        case isFinal
    }

    public init(message: String, conversationId: String, responseId: String, timestamp: Date? = nil, webSearchResults: [WebSearchResult]? = nil, xposts: [XPost]? = nil, isThinking: Bool = false, isSoftStop: Bool = false, isFinal: Bool = false) {
        self.message = message
        self.conversationId = conversationId
        self.responseId = responseId
        self.timestamp = timestamp
        self.webSearchResults = webSearchResults
        self.xposts = xposts
        self.isThinking = isThinking
        self.isSoftStop = isSoftStop
        self.isFinal = isFinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        responseId = try container.decode(String.self, forKey: .responseId)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        webSearchResults = try container.decodeIfPresent([WebSearchResult].self, forKey: .webSearchResults)
        xposts = try container.decodeIfPresent([XPost].self, forKey: .xposts)
        isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking) ?? false
        isSoftStop = try container.decodeIfPresent(Bool.self, forKey: .isSoftStop) ?? false
        isFinal = try container.decodeIfPresent(Bool.self, forKey: .isFinal) ?? false
    }
}

public struct Conversation: Codable {
    public let conversationId: String
    public let title: String
    public let starred: Bool
    public let createTime: String
    public let modifyTime: String
    public let systemPromptName: String
    public let temporary: Bool
    public let mediaTypes: [String]
    public let preview: String

    public init(conversationId: String, title: String, starred: Bool = false, createTime: String = "", modifyTime: String = "", systemPromptName: String = "", temporary: Bool = false, mediaTypes: [String] = [], preview: String = "") {
        self.conversationId = conversationId
        self.title = title
        self.starred = starred
        self.createTime = createTime
        self.modifyTime = modifyTime
        self.systemPromptName = systemPromptName
        self.temporary = temporary
        self.mediaTypes = mediaTypes
        self.preview = preview
    }

    private enum CodingKeys: String, CodingKey {
        case conversationId
        case conversationID = "conversation_id"
        case id
        case title
        case name
        case starred
        case createTime
        case createTimeSnake = "create_time"
        case modifyTime
        case modifyTimeSnake = "modify_time"
        case systemPromptName
        case systemPromptNameSnake = "system_prompt_name"
        case temporary
        case mediaTypes
        case mediaTypesSnake = "media_types"
        case preview
        case snippet
        case lastMessage
        case lastMessageSnake = "last_message"
        case lastResponse
        case lastResponseSnake = "last_response"
        case description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let conversationId = try Self.decodeFirstString(
            in: container,
            keys: [.conversationId, .conversationID, .id]
        )
        guard let conversationId else {
            throw DecodingError.keyNotFound(
                CodingKeys.conversationId,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Conversation did not include an id"
                )
            )
        }

        self.conversationId = conversationId
        self.title = try Self.decodeFirstString(in: container, keys: [.title, .name]) ?? conversationId
        self.starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        self.createTime = try Self.decodeFirstString(in: container, keys: [.createTime, .createTimeSnake]) ?? ""
        self.modifyTime = try Self.decodeFirstString(in: container, keys: [.modifyTime, .modifyTimeSnake]) ?? ""
        self.systemPromptName = try Self.decodeFirstString(
            in: container,
            keys: [.systemPromptName, .systemPromptNameSnake]
        ) ?? ""
        self.temporary = try container.decodeIfPresent(Bool.self, forKey: .temporary) ?? false
        if let mediaTypes = try container.decodeIfPresent([String].self, forKey: .mediaTypes) {
            self.mediaTypes = mediaTypes
        } else {
            self.mediaTypes = try container.decodeIfPresent([String].self, forKey: .mediaTypesSnake) ?? []
        }
        self.preview = try Self.decodeFirstString(
            in: container,
            keys: [.preview, .snippet, .lastMessage, .lastMessageSnake, .lastResponse, .lastResponseSnake, .description]
        ) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(title, forKey: .title)
        try container.encode(starred, forKey: .starred)
        try container.encode(createTime, forKey: .createTime)
        try container.encode(modifyTime, forKey: .modifyTime)
        try container.encode(systemPromptName, forKey: .systemPromptName)
        try container.encode(temporary, forKey: .temporary)
        try container.encode(mediaTypes, forKey: .mediaTypes)
        try container.encode(preview, forKey: .preview)
    }

    private static func decodeFirstString(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> String? {
        for key in keys {
            if let value = try container.decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

// Response Node struct for conversation threading
public struct ResponseNode: Codable {
    public let responseId: String
    public let sender: String
    public let parentResponseId: String?

    public init(responseId: String, sender: String, parentResponseId: String? = nil) {
        self.responseId = responseId
        self.sender = sender
        self.parentResponseId = parentResponseId
    }
}

// Response struct for conversation messages
public struct Response: Codable {
    public let responseId: String
    public let message: String
    public let sender: String
    public let createTime: String
    public let parentResponseId: String?
    public let modeId: String?
    public let modelId: String?
    public let modeName: String?
    public let modelName: String?

    public init(
        responseId: String,
        message: String,
        sender: String,
        createTime: String,
        parentResponseId: String? = nil,
        modeId: String? = nil,
        modelId: String? = nil,
        modeName: String? = nil,
        modelName: String? = nil
    ) {
        self.responseId = responseId
        self.message = message
        self.sender = sender
        self.createTime = createTime
        self.parentResponseId = parentResponseId
        self.modeId = modeId
        self.modelId = modelId
        self.modeName = modeName
        self.modelName = modelName
    }

    private enum CodingKeys: String, CodingKey {
        case responseId
        case message
        case sender
        case createTime
        case parentResponseId
        case modeId
        case modeID = "mode_id"
        case modelId
        case modelID = "model_id"
        case modeName
        case modeNameSnake = "mode_name"
        case modelName
        case modelNameSnake = "model_name"
        case mode
        case model
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        responseId = try container.decode(String.self, forKey: .responseId)
        message = try container.decode(String.self, forKey: .message)
        sender = try container.decode(String.self, forKey: .sender)
        createTime = try container.decode(String.self, forKey: .createTime)
        parentResponseId = try container.decodeIfPresent(String.self, forKey: .parentResponseId)

        let modeDictionary = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .mode)
        let modelDictionary = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .model)
        let metadataDictionary = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        let requestMetadataDictionary = Self.nestedDictionary(
            in: metadataDictionary ?? nil,
            keys: ["request_metadata", "requestMetadata"]
        )
        let modeValue = try? container.decodeIfPresent(String.self, forKey: .mode)
        let modelValue = try? container.decodeIfPresent(String.self, forKey: .model)

        modeId = try Self.decodeFirstString(
            in: container,
            keys: [.modeId, .modeID],
            scalarValues: [modeValue ?? nil],
            nested: [modeDictionary ?? nil, requestMetadataDictionary, metadataDictionary ?? nil],
            nestedKeys: ["modeId", "mode_id", "mode", "id", "value"]
        )
        modelId = try Self.decodeFirstString(
            in: container,
            keys: [.modelId, .modelID],
            scalarValues: [modelValue ?? nil],
            nested: [modelDictionary ?? nil, requestMetadataDictionary, metadataDictionary ?? nil],
            nestedKeys: ["modelId", "model_id", "model", "id", "value"]
        )
        modeName = try Self.decodeFirstString(
            in: container,
            keys: [.modeName, .modeNameSnake],
            nested: [modeDictionary ?? nil, requestMetadataDictionary, metadataDictionary ?? nil],
            nestedKeys: ["displayName", "display_name", "name", "title", "label", "modeName", "mode_name"]
        )
        modelName = try Self.decodeFirstString(
            in: container,
            keys: [.modelName, .modelNameSnake],
            nested: [modelDictionary ?? nil, requestMetadataDictionary, metadataDictionary ?? nil],
            nestedKeys: ["displayName", "display_name", "name", "title", "label", "modelName", "model_name"]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(responseId, forKey: .responseId)
        try container.encode(message, forKey: .message)
        try container.encode(sender, forKey: .sender)
        try container.encode(createTime, forKey: .createTime)
        try container.encodeIfPresent(parentResponseId, forKey: .parentResponseId)
        try container.encodeIfPresent(modeId, forKey: .modeId)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encodeIfPresent(modeName, forKey: .modeName)
        try container.encodeIfPresent(modelName, forKey: .modelName)
    }

    private static func decodeFirstString(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        scalarValues: [String?] = [],
        nested dictionaries: [[String: AnyCodable]?],
        nestedKeys: [String]
    ) throws -> String? {
        for key in keys {
            if let value = try container.decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }

        for value in scalarValues {
            if let value, !value.isEmpty {
                return value
            }
        }

        for dictionary in dictionaries {
            guard let dictionary else {
                continue
            }
            for key in nestedKeys {
                guard let value = dictionary[key]?.value as? String, !value.isEmpty else {
                    continue
                }
                return value
            }
        }

        return nil
    }

    private static func nestedDictionary(
        in dictionary: [String: AnyCodable]?,
        keys: [String]
    ) -> [String: AnyCodable]? {
        guard let dictionary else {
            return nil
        }
        for key in keys {
            if let nested = dictionary[key]?.value as? [String: AnyCodable] {
                return nested
            }
        }
        return nil
    }
}

// Wrapper structure for conversations API response
public struct ConversationsResponse: Codable {
    public let conversations: [Conversation]
    public let nextPageToken: String?
    public let textSearchMatches: [String]

    public init(conversations: [Conversation], nextPageToken: String? = nil, textSearchMatches: [String] = []) {
        self.conversations = conversations
        self.nextPageToken = nextPageToken
        self.textSearchMatches = textSearchMatches
    }

    private enum CodingKeys: String, CodingKey {
        case conversations
        case data
        case result
        case items
        case nextPageToken
        case nextPageTokenSnake = "next_page_token"
        case textSearchMatches
        case textSearchMatchesSnake = "text_search_matches"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try Self.decodeConversations(from: container)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
            ?? container.decodeIfPresent(String.self, forKey: .nextPageTokenSnake)
        textSearchMatches = try Self.decodeTextSearchMatches(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversations, forKey: .conversations)
        try container.encodeIfPresent(nextPageToken, forKey: .nextPageToken)
        try container.encode(textSearchMatches, forKey: .textSearchMatches)
    }

    private static func decodeConversations(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [Conversation] {
        for key in [CodingKeys.conversations, .items] {
            if let conversations = try container.decodeIfPresent([Conversation].self, forKey: key) {
                return conversations
            }
        }

        for key in [CodingKeys.data, .result] {
            if let conversations = try container.decodeIfPresent([Conversation].self, forKey: key) {
                return conversations
            }
            if let nested = try container.decodeIfPresent(ConversationsResponse.self, forKey: key) {
                return nested.conversations
            }
        }

        return []
    }

    private static func decodeTextSearchMatches(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
        for key in [CodingKeys.textSearchMatches, .textSearchMatchesSnake] {
            if let matches = try? container.decodeIfPresent([String].self, forKey: key) {
                return matches
            }
            if let values = try? container.decodeIfPresent([AnyCodable].self, forKey: key) {
                return values.compactMap { value in
                    if let string = value.value as? String {
                        return string
                    }
                    if let dictionary = value.value as? [String: AnyCodable] {
                        for matchKey in ["text", "snippet", "message", "value"] {
                            if let string = dictionary[matchKey]?.value as? String, !string.isEmpty {
                                return string
                            }
                        }
                    }
                    return nil
                }
            }
        }

        return []
    }
}

public struct GrokTypeaheadSuggestion: Codable {
    public let text: String
    public let title: String?
    public let rawJSON: [String: AnyCodable]

    public init(text: String, title: String? = nil, rawJSON: [String: AnyCodable] = [:]) {
        self.text = text
        self.title = title
        self.rawJSON = rawJSON
    }
}

public struct GrokTypeaheadResponse: Codable {
    public let suggestions: [GrokTypeaheadSuggestion]
    public let rawJSON: AnyCodable

    public init(suggestions: [GrokTypeaheadSuggestion], rawJSON: AnyCodable) {
        self.suggestions = suggestions
        self.rawJSON = rawJSON
    }
}

public struct GrokModesResponse {
    public let modes: [GrokMode]
    public let rawJSON: AnyCodable

    public init(modes: [GrokMode], rawJSON: AnyCodable) {
        self.modes = modes
        self.rawJSON = rawJSON
    }
}

// MARK: - Streaming Response Models
internal struct StreamingResponse: Codable {
    let result: StreamingResult?
}

internal struct StreamingResult: Codable {
    let response: ResponseContent?
    let modelResponse: ModelResponse?
    let conversation: ConversationData?
    let responseId: String?
    let isThinking: Bool?
    let isSoftStop: Bool?
    let token: String?
    let userResponse: UserResponse?
    let finalMetadata: FinalMetadata?
}

internal struct ConversationData: Codable {
    let conversationId: String?
}

internal struct ResponseContent: Codable {
    let token: String?
    let modelResponse: ModelResponse?
    let responseId: String?
    let isThinking: Bool?
    let isSoftStop: Bool?
    let finalMetadata: FinalMetadata?
}

// AnyCodable type to handle unknown types in JSON
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable cannot decode value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self.value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [AnyCodable]:
            try container.encode(array)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: AnyCodable]:
            try container.encode(dictionary)
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(self.value, EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable cannot encode value"
            ))
        }
    }
}

public struct GrokTaskSchedule: Codable {
    public let taskCadence: String
    public let isEnabled: Bool
    public let timezone: String
    public let timeOfDay: String
    public let dayOfYear: String

    public init(
        taskCadence: String = "TASK_CADENCE_ONCE",
        isEnabled: Bool = true,
        timezone: String,
        timeOfDay: String,
        dayOfYear: String
    ) {
        self.taskCadence = taskCadence
        self.isEnabled = isEnabled
        self.timezone = timezone
        self.timeOfDay = timeOfDay
        self.dayOfYear = dayOfYear
    }
}

public struct GrokTask: Codable {
    public let taskId: String?
    public let id: String?
    public let name: String?
    public let prompt: String?
    public let isEnabled: Bool?
    public let status: String?
    public let rawJSON: [String: AnyCodable]

    public var resolvedId: String? {
        taskId ?? id
    }

    public init(
        taskId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        prompt: String? = nil,
        isEnabled: Bool? = nil,
        status: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.taskId = taskId
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.status = status
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.taskId = rawJSON["taskId"]?.value as? String ?? rawJSON["task_id"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.name = Self.stringValue(rawJSON, keys: ["name", "title", "displayName", "display_name"])
        self.prompt = Self.stringValue(rawJSON, keys: [
            "prompt",
            "taskPrompt",
            "task_prompt",
            "description",
            "summary",
            "query",
            "instructions"
        ])
        self.isEnabled = Self.boolValue(rawJSON, keys: ["isEnabled", "is_enabled", "isActive", "is_active", "enabled", "active"])
        self.status = rawJSON["status"]?.value as? String ?? rawJSON["state"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }

    private static func stringValue(_ dictionary: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key]?.value as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func boolValue(_ dictionary: [String: AnyCodable], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key]?.value as? Bool {
                return value
            }
            if let value = dictionary[key]?.value as? Int {
                return value != 0
            }
            if let value = dictionary[key]?.value as? String {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1", "enabled", "active":
                    return true
                case "false", "no", "0", "disabled", "inactive", "archived":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }
}

public struct GrokSkill: Codable {
    public let skillId: String?
    public let id: String?
    public let name: String?
    public let title: String?
    public let rawJSON: [String: AnyCodable]

    public init(
        skillId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        title: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.skillId = skillId
        self.id = id
        self.name = name
        self.title = title
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.skillId = rawJSON["skillId"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.name = rawJSON["name"]?.value as? String
        self.title = rawJSON["title"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }
}

public struct GrokTasksResponse: Codable {
    public let tasks: [GrokTask]
    public let activeTasks: [GrokTask]
    public let inactiveTasks: [GrokTask]
    public let rawJSON: AnyCodable

    public init(
        tasks: [GrokTask],
        activeTasks: [GrokTask] = [],
        inactiveTasks: [GrokTask] = [],
        rawJSON: AnyCodable
    ) {
        self.tasks = tasks
        self.activeTasks = activeTasks
        self.inactiveTasks = inactiveTasks
        self.rawJSON = rawJSON
    }
}

public struct GrokTaskMutationResponse: Codable {
    public let task: GrokTask?
    public let rawJSON: AnyCodable
}

public struct GrokTaskResult: Codable {
    public let resultId: String?
    public let id: String?
    public let taskId: String?
    public let conversationId: String?
    public let responseId: String?
    public let message: String?
    public let status: String?
    public let rawJSON: [String: AnyCodable]

    public var resolvedId: String? {
        resultId ?? id
    }

    public init(
        resultId: String? = nil,
        id: String? = nil,
        taskId: String? = nil,
        conversationId: String? = nil,
        responseId: String? = nil,
        message: String? = nil,
        status: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.resultId = resultId
        self.id = id
        self.taskId = taskId
        self.conversationId = conversationId
        self.responseId = responseId
        self.message = message
        self.status = status
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.resultId = Self.stringValue(rawJSON, keys: ["taskResultId", "task_result_id", "resultId", "result_id"])
        self.id = Self.stringValue(rawJSON, keys: ["id"])
        self.taskId = Self.stringValue(rawJSON, keys: ["taskId", "task_id"])
        self.conversationId = Self.stringValue(rawJSON, keys: ["conversationId", "conversation_id"])
        self.responseId = Self.stringValue(rawJSON, keys: ["responseId", "response_id"])
        self.message = Self.stringValue(rawJSON, keys: ["summary", "message", "content", "output", "text", "result"])
        self.status = Self.stringValue(rawJSON, keys: ["status", "state"])
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }

    private static func stringValue(_ dictionary: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key]?.value as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public struct GrokTaskResultsResponse: Codable {
    public let results: [GrokTaskResult]
    public let rawJSON: AnyCodable

    public init(results: [GrokTaskResult], rawJSON: AnyCodable) {
        self.results = results
        self.rawJSON = rawJSON
    }
}

public struct GrokSkillsResponse: Codable {
    public let skills: [GrokSkill]
    public let rawJSON: AnyCodable
}

public struct GrokAgentCustomization: Codable {
    public let agentId: Int
    public let name: String
    public let instructions: String

    public init(agentId: Int, name: String, instructions: String) {
        self.agentId = agentId
        self.name = agentId == 0 ? "Grok" : name
        self.instructions = instructions
    }

    public static func defaultName(for agentId: Int) -> String {
        switch agentId {
        case 0:
            return "Grok"
        case 1:
            return "Grok II"
        case 2:
            return "Grok III"
        case 3:
            return "Grok IV"
        default:
            return "Agent \(agentId)"
        }
    }
}

public struct GrokAgentCustomizationsResponse: Codable {
    public let agentCustomizations: [GrokAgentCustomization]
    public let rawJSON: AnyCodable
}

public struct GrokWorkspace: Codable {
    public let workspaceId: String?
    public let id: String?
    public let name: String?
    public let title: String?
    public let icon: String?
    public let customPersonality: String?
    public let preferredModel: String?
    public let rawJSON: [String: AnyCodable]

    public init(
        workspaceId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        title: String? = nil,
        icon: String? = nil,
        customPersonality: String? = nil,
        preferredModel: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.workspaceId = workspaceId
        self.id = id
        self.name = name
        self.title = title
        self.icon = icon
        self.customPersonality = customPersonality
        self.preferredModel = preferredModel
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.workspaceId = rawJSON["workspaceId"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.name = rawJSON["name"]?.value as? String
        self.title = rawJSON["title"]?.value as? String
        self.icon = rawJSON["icon"]?.value as? String
        self.customPersonality = rawJSON["customPersonality"]?.value as? String
        self.preferredModel = rawJSON["preferredModel"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }
}

public struct GrokWorkspacesResponse: Codable {
    public let workspaces: [GrokWorkspace]
    public let rawJSON: AnyCodable
}

public struct GrokWorkspaceMutationResponse: Codable {
    public let workspace: GrokWorkspace?
    public let rawJSON: AnyCodable
}

public struct GrokAsset: Codable {
    public let assetId: String?
    public let fileMetadataId: String?
    public let fileId: String?
    public let id: String?
    public let fileName: String?
    public let name: String?
    public let mimeType: String?
    public let rawJSON: [String: AnyCodable]

    public var resolvedId: String? {
        fileMetadataId ?? fileId ?? assetId ?? id
    }

    public init(
        assetId: String? = nil,
        fileMetadataId: String? = nil,
        fileId: String? = nil,
        id: String? = nil,
        fileName: String? = nil,
        name: String? = nil,
        mimeType: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.assetId = assetId
        self.fileMetadataId = fileMetadataId
        self.fileId = fileId
        self.id = id
        self.fileName = fileName
        self.name = name
        self.mimeType = mimeType
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.assetId = rawJSON["assetId"]?.value as? String ?? rawJSON["asset_id"]?.value as? String
        self.fileMetadataId = rawJSON["fileMetadataId"]?.value as? String ?? rawJSON["file_metadata_id"]?.value as? String
        self.fileId = rawJSON["fileId"]?.value as? String ?? rawJSON["file_id"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.fileName = rawJSON["fileName"]?.value as? String ?? rawJSON["file_name"]?.value as? String
        self.name = rawJSON["name"]?.value as? String
        self.mimeType = rawJSON["mimeType"]?.value as? String
            ?? rawJSON["mime_type"]?.value as? String
            ?? rawJSON["fileMimeType"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }
}

public struct GrokFileUploadResponse: Codable {
    public let fileMetadataId: String?
    public let fileId: String?
    public let assetId: String?
    public let id: String?
    public let fileName: String?
    public let asset: GrokAsset?
    public let rawJSON: AnyCodable

    public var uploadedFileId: String? {
        fileMetadataId ?? fileId ?? assetId ?? id ?? asset?.resolvedId
    }
}

public struct GrokAssetsResponse: Codable {
    public let assets: [GrokAsset]
    public let rawJSON: AnyCodable
}

public struct GrokFileMutationResponse: Codable {
    public let asset: GrokAsset?
    public let rawJSON: AnyCodable
}

public struct GrokConversationV2Response: Codable {
    public let conversationId: String?
    public let rawJSON: AnyCodable
}

internal struct FinalMetadata: Codable {
    let followUpSuggestions: [String]?
    let feedbackLabels: [String]?
    let disclaimer: String?
    let toolsUsed: [String: AnyCodable]?
}

internal struct UserResponse: Codable {
    let responseId: String?
    let message: String?
    let sender: String?
}

// Add internal models for web search results and X posts
internal struct WebSearchResultInternal: Codable {
    let url: String
    let title: String
    let preview: String
    let searchEngineText: String
    let description: String
    let siteName: String
    let metadataTitle: String
    let creator: String
    let image: String
    let favicon: String
    let citationId: String
}

internal struct XPostInternal: Codable {
    let username: String
    let name: String
    let text: String
    let createTime: String
    let profileImageUrl: String
    let postId: String
    let citationId: String
    // Additional fields like parent, quote, viewCount are omitted for simplicity
}

internal struct ModelResponse: Codable {
    let message: String
    let responseId: String?
    let sender: String?
    let createTime: String?
    let parentResponseId: String?
    let webSearchResults: [WebSearchResultInternal]?
    let xposts: [XPostInternal]?

    // Helper functions to convert internal models to public models
    func extractWebSearchResults() -> [WebSearchResult]? {
        guard let results = webSearchResults else { return nil }

        // Filter out empty results and convert to public model
        return results.compactMap { result in
            // Skip empty URL entries
            guard !result.url.isEmpty else { return nil }

            return WebSearchResult(
                url: result.url,
                title: result.title,
                preview: result.preview,
                siteName: result.siteName.isEmpty ? nil : result.siteName,
                description: result.description.isEmpty ? nil : result.description,
                citationId: result.citationId.isEmpty ? nil : result.citationId
            )
        }
    }

    func extractXPosts() -> [XPost]? {
        guard let posts = xposts else { return nil }

        // Filter out empty posts and convert to public model
        return posts.compactMap { post in
            guard !post.username.isEmpty else { return nil }
            return XPost(
                username: post.username,
                name: post.name,
                text: post.text,
                postId: post.postId,
                createTime: post.createTime.isEmpty ? nil : post.createTime,
                profileImageUrl: post.profileImageUrl.isEmpty ? nil : post.profileImageUrl,
                citationId: post.citationId.isEmpty ? nil : post.citationId
            )
        }
    }
}

// MARK: - GrokClient Class
public class GrokClient {
    private let baseURL: String
    private let rootBaseURL: String
    private let webBaseURL: String
    private let cookies: [String: String]
    private var session: URLSession
    public var isDebug: Bool = false
	internal let headers: [String: String] = [
	    "accept": "*/*",
	    "accept-language": "en-US,en;q=0.9",
	    "content-type": "application/json",
	    "origin": "https://grok.com",
	    "priority": "u=1, i",
	    "referer": "https://grok.com/",
	    "sec-ch-ua": "\"Chromium\";v=\"148\", \"Google Chrome\";v=\"148\", \"Not/A)Brand\";v=\"99\"",
	    "sec-ch-ua-arch": "\"arm\"",
	    "sec-ch-ua-bitness": "\"64\"",
	    "sec-ch-ua-full-version": "\"148.0.7778.97\"",
	    "sec-ch-ua-full-version-list": "\"Chromium\";v=\"148.0.7778.97\", \"Google Chrome\";v=\"148.0.7778.97\", \"Not/A)Brand\";v=\"99.0.0.0\"",
	    "sec-ch-ua-mobile": "?0",
	    "sec-ch-ua-model": "\"\"",
	    "sec-ch-ua-platform": "\"macOS\"",
	    "sec-ch-ua-platform-version": "\"15.6.1\"",
	    "sec-fetch-dest": "empty",
	    "sec-fetch-mode": "cors",
	    "sec-fetch-site": "same-origin",
	    "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
	]

    enum RestNamespace {
        case appChat
        case root
        case web

        var pathPrefix: String {
            switch self {
            case .appChat:
                return "/rest/app-chat"
            case .root:
                return "/rest"
            case .web:
                return ""
            }
        }
    }

    private var cookieHeader: String {
        cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    public static let defaultModeId = GrokMode.defaultMode.id

    /// Deprecated Grok 3 server-side system prompt presets.
    ///
    /// These values are kept for source compatibility, but they are no longer
    /// sent to Grok. Configure instructions in Grok agent settings instead.
    public enum PersonalityType: String, CaseIterable {
        case romance = "grok3_personality_romance_me"
        case medicalAdvisor = "grok3_personality_medical_advisor"
        case latestNews = "grok3_personality_latest_news"
        case unhingedComedian = "grok3_personality_unhinged_comedian"
        case loyalFriend = "grok3_personality_loyal_friend"
        case homeworkHelper = "grok3_personality_homework_helper"
        case trustedTherapist = "grok3_personality_trusted_therapist"
        case none = ""

        public var displayName: String {
            switch self {
            case .romance: return "Romance Me"
            case .medicalAdvisor: return "Medical Advisor"
            case .latestNews: return "Latest News"
            case .unhingedComedian: return "Unhinged Comedian"
            case .loyalFriend: return "Loyal Friend"
            case .homeworkHelper: return "Homework Helper"
            case .trustedTherapist: return "Trusted Therapist"
            case .none: return "Default (No Personality)"
            }
        }

        public var description: String {
            switch self {
            case .romance: return "A flirty and romantic personality"
            case .medicalAdvisor: return "A helpful medical information advisor"
            case .latestNews: return "Focused on providing the latest news and current events"
            case .unhingedComedian: return "A wild and unhinged comedian"
            case .loyalFriend: return "A supportive and loyal friend"
            case .homeworkHelper: return "A patient tutor focused on helping with homework"
            case .trustedTherapist: return "A compassionate therapeutic personality"
            case .none: return "Standard Grok personality"
            }
        }
    }

    private static func normalizedBaseURLs(from configuredBaseURL: String?) -> (appChat: String, root: String, web: String) {
        let rawBaseURL = configuredBaseURL
            ?? ProcessInfo.processInfo.environment["GROK_BASE_URL"]
            ?? "https://grok.com/rest"
        let trimmed = rawBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmed.hasSuffix("/rest/app-chat") {
            let root = String(trimmed.dropLast("/app-chat".count))
            let web = String(root.dropLast("/rest".count))
            return (trimmed, root, web)
        }

        if trimmed.hasSuffix("/rest") {
            let web = String(trimmed.dropLast("/rest".count))
            return ("\(trimmed)/app-chat", trimmed, web)
        }

        let root = "\(trimmed)/rest"
        return ("\(root)/app-chat", root, trimmed)
    }

    /// Initializes the GrokClient with cookie credentials
    /// - Parameters:
    ///   - cookies: A dictionary of cookie name-value pairs for authentication
    ///   - isDebug: Whether to print debug information (default: false)
    /// - Throws: GrokError.invalidCredentials if credentials are empty
    public init(
        cookies: [String: String],
        isDebug: Bool = false,
        baseURL configuredBaseURL: String? = nil,
        session injectedSession: URLSession? = nil
    ) throws {
        guard !cookies.isEmpty else {
            throw GrokError.invalidCredentials
        }

        let resolvedBaseURLs = Self.normalizedBaseURLs(from: configuredBaseURL)
        self.baseURL = resolvedBaseURLs.appChat
        self.rootBaseURL = resolvedBaseURLs.root
        self.webBaseURL = resolvedBaseURLs.web
        self.cookies = cookies
        self.isDebug = isDebug

        if let injectedSession {
            self.session = injectedSession
            return
        }

        // #if os(Linux)
        //     // Linux: URLSession cookie support is limited, so skip setting cookies.
        //     self.session = URLSession(configuration: .default)
        // #else
        let configuration = URLSessionConfiguration.default
        var httpCookies = [HTTPCookie]()
        for (name, value) in cookies {
            if let cookie = HTTPCookie(properties: [
                .domain: "grok.com",
                .path: "/",
                .name: name,
                .value: value
            ]) {
                httpCookies.append(cookie)
            }
        }
        configuration.httpCookieStorage?.setCookies(httpCookies, for: URL(string: "https://grok.com"), mainDocumentURL: nil)
        self.session = URLSession(configuration: configuration)
        // #endif
    }

    /// Prepares the default payload with the user's message
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
	    var payload: [String: Any] = [
	        "temporary": temporary,
	        "message": message,
            "modeId": modeId,
	        "imageAttachments": [],
            "fileAttachments": fileAttachments,
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
            "disabledConnectorIds": disabledConnectorIds,
	        "deviceEnvInfo": deviceEnvInfo()
	    ]

        if !workspaceIds.isEmpty {
            payload["workspaceIds"] = workspaceIds
        }

        return payload
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

	private func statsigPath(for path: String, namespace: RestNamespace = .appChat) -> String {
	    let pathWithoutQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
	    return "\(namespace.pathPrefix)\(pathWithoutQuery)"
	}

	private func makeStatsigID(path: String, method: String, namespace: RestNamespace = .appChat) -> String? {
	    #if canImport(CryptoKit)
	    let metaBase64 = "aTdepyfBsvO5OewwurJnUTpd+p89iA3b26j9Sw2BhK32z+fmV5t8Qxe91l75WsOp"
	    let fingerprint = "90e5cb100a3d70a3d70a3d800a3d70a3d70a3d8100"
	    guard let metaBytes = Data(base64Encoded: metaBase64) else {
	        return nil
	    }

	    let epochOffset = 0x644f6370
	    let relativeSeconds = UInt32(max(0, Int(Date().timeIntervalSince1970.rounded(.down)) - epochOffset))
	    let message = "\(method)!\(statsigPath(for: path, namespace: namespace))!\(relativeSeconds)obfiowerehiring\(fingerprint)"
	    let digest = SHA256.hash(data: Data(message.utf8))

	    var raw = Data()
	    let randomByte = UInt8.random(in: UInt8.min...UInt8.max)
	    raw.append(randomByte)
	    raw.append(metaBytes)
	    raw.append(UInt8(relativeSeconds & 0xff))
	    raw.append(UInt8((relativeSeconds >> 8) & 0xff))
	    raw.append(UInt8((relativeSeconds >> 16) & 0xff))
	    raw.append(UInt8((relativeSeconds >> 24) & 0xff))
	    raw.append(contentsOf: digest.prefix(16))
	    raw.append(3)

	    for index in raw.indices.dropFirst() {
	        raw[index] ^= randomByte
	    }

	    return raw.base64EncodedString().replacingOccurrences(of: "=", with: "")
	    #else
	    return nil
	    #endif
	}

	func makeRequest(
        path: String,
        method: String = "POST",
        payload: [String: Any]? = nil,
        namespace: RestNamespace = .appChat
    ) throws -> URLRequest {
        let requestBaseURL: String
        switch namespace {
        case .appChat:
            requestBaseURL = baseURL
        case .root:
            requestBaseURL = rootBaseURL
        case .web:
            requestBaseURL = webBaseURL
        }

        let url = URL(string: "\(requestBaseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (key, value) in headers {
            if payload == nil && ["content-type", "origin"].contains(key.lowercased()) {
                continue
            }
            request.setValue(value, forHTTPHeaderField: key)
        }

	    request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "x-xai-request-id")
	    if let statsigID = makeStatsigID(path: path, method: method, namespace: namespace) {
	        request.setValue(statsigID, forHTTPHeaderField: "x-statsig-id")
	    }
	    request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        if let payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        if isDebug {
            print("Debug cURL: \(request.curlRepresentation(redactCookies: true))")
        }

        return request
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data? = nil, modeId: String? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 403:
                let bodyMessage = httpErrorBodyMessage(from: data)
                if responseBodyIndicatesAuthenticationFailure(bodyMessage) {
                    throw GrokError.unauthorized
                }
                throw GrokError.accessDenied(accessDeniedMessage(bodyMessage: bodyMessage, modeId: modeId))
            case 404:
                throw GrokError.notFound
            default:
                let body = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = body?.isEmpty == false ? ": \(body!.prefix(600))" : ""
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)\(suffix)")
            }
        }
    }

    private func httpErrorBodyMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            if let dict = json as? JSONDictionary {
                if let error = dict["error"] {
                    return trimmedMessage(describeAPIError(error))
                }
                if let message = stringValue(dict, keys: ["message", "description", "detail"]) {
                    return trimmedMessage(message)
                }
            }

            return trimmedMessage(String(describing: json))
        }

        return trimmedMessage(String(data: data, encoding: .utf8))
    }

    private func trimmedMessage(_ message: String?) -> String? {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(600))
    }

    private func responseBodyIndicatesAuthenticationFailure(_ message: String?) -> Bool {
        guard let message else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("unauthorized") ||
            normalized.contains("unauthenticated") ||
            normalized.contains("not authenticated") ||
            normalized.contains("authentication required") ||
            normalized.contains("login required") ||
            normalized.contains("log in") ||
            (normalized.contains("cookie") && (normalized.contains("invalid") || normalized.contains("expired"))) ||
            normalized.contains("csrf") ||
            normalized.contains("sso")
    }

    private func accessDeniedMessage(bodyMessage: String?, modeId: String?) -> String {
        let resolvedMode = modeId.map(GrokMode.resolve)
        let subject: String
        if let resolvedMode {
            subject = "\(resolvedMode.displayName) (\(resolvedMode.id))"
        } else {
            subject = "this request"
        }

        var message = "Grok denied access to \(subject)."
        if let bodyMessage, !isGenericForbiddenMessage(bodyMessage) {
            message += " \(bodyMessage)"
        } else {
            message += " The selected model or feature may not be available to your account."
        }
        message += " Switch models with `/model` or pass `--model fast`, `--model expert`, or `--model auto`."
        return message
    }

    private func isGenericForbiddenMessage(_ message: String) -> Bool {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "forbidden" ||
            normalized == "access denied" ||
            normalized == "{\"error\":\"forbidden\"}" ||
            normalized == "{\"error\":\"access denied\"}"
    }

    private typealias JSONDictionary = [String: Any]
    private static let rateLimitRemainingKeys = [
        "remainingResponses",
        "remainingResponseCount",
        "responsesRemaining",
        "remainingMessages",
        "messagesRemaining",
        "remainingRequests",
        "requestsRemaining",
        "remainingQueries",
        "queriesRemaining",
        "remaining"
    ]
    private static let rateLimitResetAtKeys = [
        "resetAt",
        "resetsAt",
        "resetTime",
        "resetTimestamp",
        "windowResetAt",
        "rateLimitResetAt",
        "expiresAt",
        "reset"
    ]
    private static let rateLimitResetAfterKeys = [
        "resetAfterSeconds",
        "secondsUntilReset",
        "resetInSeconds",
        "timeUntilResetSeconds",
        "resetAfter",
        "resetIn",
        "ttlSeconds"
    ]
    private static let rateLimitWindowKeys = [
        "windowSeconds",
        "windowLengthSeconds",
        "windowDurationSeconds",
        "limitWindowSeconds",
        "rateLimitWindowSeconds",
        "periodSeconds",
        "durationSeconds",
        "window",
        "windowLength",
        "windowDuration",
        "limitWindow",
        "rateLimitWindow",
        "period",
        "duration"
    ]
    private static let activeSubscriptionStatuses: Set<String> = [
        "active",
        "trialing",
        "current",
        "subscribed",
        "paid"
    ]
    private static let inactiveSubscriptionStatuses: Set<String> = [
        "canceled",
        "cancelled",
        "expired",
        "inactive",
        "pastdue",
        "past_due",
        "unpaid"
    ]
    private static let shareLinkWrapperKeys = [
        "shareLinks",
        "share_links",
        "items",
        "result",
        "data"
    ]
    private static let shareLinkURLKeys = [
        "url",
        "shareUrl",
        "share_url",
        "link",
        "shareLink",
        "share_link"
    ]
    private static let shareLinkIDKeys = [
        "publicId",
        "public_id",
        "token",
        "id",
        "shareId",
        "share_id",
        "shareLinkId",
        "share_link_id"
    ]
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
    private static let activeTaskKeys = [
        "activeTasks",
        "active_tasks",
        "enabledTasks",
        "enabled_tasks",
        "active",
        "enabled"
    ]
    private static let inactiveTaskKeys = [
        "inactiveTasks",
        "inactive_tasks",
        "archivedTasks",
        "archived_tasks",
        "disabledTasks",
        "disabled_tasks",
        "inactive",
        "archived",
        "disabled"
    ]
    private static let generalTaskKeys = [
        "tasks",
        "taskList",
        "task_list",
        "data",
        "result",
        "items",
        "values"
    ]
    private static let taskWrapperKeys = [
        "task",
        "taskData",
        "task_data"
    ]
    private static let taskResultKeys = [
        "results",
        "taskResults",
        "task_results",
        "data",
        "result",
        "items",
        "values"
    ]

    private func dictionary(_ value: Any?) -> JSONDictionary? {
        value as? JSONDictionary
    }

    private func stringValue(_ dictionary: JSONDictionary?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func stringValueAllowingEmpty(_ dictionary: JSONDictionary?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    private func boolValue(_ dictionary: JSONDictionary?, keys: [String]) -> Bool? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }
        return nil
    }

    private func containsAnyValue(_ dictionary: JSONDictionary?, keys: [String]) -> Bool {
        guard let dictionary else { return false }
        return keys.contains { dictionary[$0] != nil }
    }

    private func isTerminalEmptyToken(_ token: String, response: JSONDictionary?, result: JSONDictionary, isThinking: Bool, isSoftStop: Bool) -> Bool {
        token.isEmpty &&
            !isThinking &&
            !isSoftStop &&
            !containsAnyValue(response, keys: Self.nonTerminalEmptyTokenMarkerKeys) &&
            !containsAnyValue(result, keys: Self.nonTerminalEmptyTokenMarkerKeys)
    }

    private func firstBool(in value: Any, keys: [String]) -> Bool? {
        if let dictionary = value as? JSONDictionary {
            for key in keys {
                if let bool = boolFromSubscriptionValue(dictionary[key]) {
                    return bool
                }
            }

            for nested in dictionary.values {
                if let bool = firstBool(in: nested, keys: keys) {
                    return bool
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let bool = firstBool(in: nested, keys: keys) {
                    return bool
                }
            }
        }

        return nil
    }

    private func boolFromSubscriptionValue(_ value: Any?) -> Bool? {
        guard let value else {
            return nil
        }

        if let bool = value as? Bool {
            return bool
        }

        if let int = value as? Int {
            return int != 0
        }

        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1", "active", "current", "subscribed":
                return true
            case "false", "no", "0", "inactive", "expired", "canceled", "cancelled":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    private func describeAPIError(_ value: Any) -> String {
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

    func jsonObject(for request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard !data.isEmpty else {
            return [:] as JSONDictionary
        }

        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    private func stringValue(_ dictionary: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key]?.value as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func boolValue(_ dictionary: [String: AnyCodable], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key]?.value as? Bool {
                return value
            }
        }
        return nil
    }

    private func intValue(_ dictionary: [String: AnyCodable], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key]?.value as? Bool {
                return value ? 1 : 0
            }
            if let value = dictionary[key]?.value as? Int {
                return value
            }
            if let value = dictionary[key]?.value as? Double {
                return Int(value)
            }
            if let value = dictionary[key]?.value as? String, let int = Int(value) {
                return int
            }
        }
        return nil
    }

    private func anyCodableDictionary(_ dictionary: JSONDictionary) -> [String: AnyCodable] {
        dictionary.mapValues { AnyCodable($0) }
    }

    private func dictionaries(from value: Any, preferredKeys: [String]) -> [JSONDictionary] {
        if let array = value as? [JSONDictionary] {
            return array
        }

        guard let dictionary = value as? JSONDictionary else {
            return []
        }

        for key in preferredKeys {
            if let array = dictionary[key] as? [JSONDictionary] {
                return array
            }
            if let nested = dictionary[key] {
                let nestedDictionaries = dictionaries(from: nested, preferredKeys: preferredKeys)
                if !nestedDictionaries.isEmpty {
                    return nestedDictionaries
                }
            }
        }

        return []
    }

    private func allDictionaries(from value: Any, keys: [String]) -> [JSONDictionary] {
        if let array = value as? [Any] {
            return array.flatMap { allDictionaries(from: $0, keys: keys) }
        }

        guard let dictionary = value as? JSONDictionary else {
            return []
        }

        var results: [JSONDictionary] = []
        for (key, nested) in dictionary {
            if keys.contains(key) {
                results.append(contentsOf: directDictionaries(from: nested))
            } else {
                results.append(contentsOf: allDictionaries(from: nested, keys: keys))
            }
        }
        return results
    }

    private func directDictionaries(from value: Any) -> [JSONDictionary] {
        if let array = value as? [JSONDictionary] {
            return array
        }

        if let array = value as? [Any] {
            return array.flatMap { directDictionaries(from: $0) }
        }

        guard let dictionary = value as? JSONDictionary else {
            return []
        }

        let nested = dictionaries(from: dictionary, preferredKeys: Self.generalTaskKeys + Self.taskWrapperKeys)
        return nested.isEmpty ? [dictionary] : nested
    }

    private func firstDictionary(from value: Any, preferredKeys: [String]) -> JSONDictionary? {
        if let dictionary = value as? JSONDictionary {
            for key in preferredKeys {
                if let nested = dictionary[key] as? JSONDictionary {
                    return nested
                }
                if let nested = dictionary[key],
                   let nestedDictionary = firstDictionary(from: nested, preferredKeys: preferredKeys) {
                    return nestedDictionary
                }
            }

            return dictionary
        }

        if let array = value as? [JSONDictionary] {
            return array.first
        }

        return nil
    }

    private func makeShareLinkURL(from json: Any) throws -> String {
        if let url = firstShareLinkURL(in: json) {
            return url
        }

        throw GrokError.apiError("Share link response did not include a share URL")
    }

    private func firstShareLinkURL(in value: Any) -> String? {
        if let dictionary = value as? JSONDictionary {
            if let url = shareLinkURL(from: dictionary) {
                return url
            }

            for key in Self.shareLinkWrapperKeys {
                guard let nested = dictionary[key],
                      let url = firstShareLinkURL(in: nested) else {
                    continue
                }
                return url
            }

            for nested in dictionary.values {
                if let url = firstShareLinkURL(in: nested) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let url = firstShareLinkURL(in: nested) {
                    return url
                }
            }
        }

        return nil
    }

    private func shareLinkURL(from dictionary: JSONDictionary) -> String? {
        if let url = firstString(in: dictionary, keys: Self.shareLinkURLKeys)
            .flatMap(cleanShareLinkURL) {
            return url
        }

        if let shareID = firstString(in: dictionary, keys: Self.shareLinkIDKeys) {
            return shareLinkURL(fromIdentifier: shareID)
        }

        return nil
    }

    private func cleanShareLinkURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return trimmed
        }

        if trimmed.hasPrefix("grok.com/") {
            return "https://\(trimmed)"
        }

        if trimmed.hasPrefix("/share/") {
            return "https://grok.com\(trimmed)"
        }

        return shareLinkURL(fromIdentifier: trimmed)
    }

    private func shareLinkURL(fromIdentifier value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return trimmed
        }

        if trimmed.hasPrefix("grok.com/") {
            return "https://\(trimmed)"
        }

        if trimmed.hasPrefix("/share/") {
            return "https://grok.com\(trimmed)"
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return "https://grok.com/share/\(encoded)"
    }

    private struct ParsedModeAvailability {
        let isAvailable: Bool
        let reason: String?
        let minimumSubscriptionTier: String?
    }

    private func modeDictionaries(from value: Any) -> [JSONDictionary] {
        dictionaries(
            from: value,
            preferredKeys: [
                "modes",
                "modeItems",
                "mode_items",
                "models",
                "data",
                "result",
                "items"
            ]
        )
    }

    private func makeMode(from dictionary: JSONDictionary) -> GrokMode? {
        let rawJSON = anyCodableDictionary(dictionary)
        guard let id = stringValue(rawJSON, keys: [
            "id",
            "modeId",
            "mode_id",
            "modelId",
            "model_id",
            "slug",
            "value"
        ]) else {
            return nil
        }

        let availability = modeAvailability(from: dictionary)
        return GrokMode(
            id: id,
            displayName: stringValue(rawJSON, keys: [
                "displayName",
                "display_name",
                "name",
                "title",
                "label"
            ]),
            summary: stringValue(rawJSON, keys: [
                "summary",
                "description",
                "subtitle"
            ]) ?? "",
            isAvailable: availability.isAvailable,
            unavailableReason: availability.reason,
            minimumSubscriptionTier: availability.minimumSubscriptionTier
        )
    }

    private func modeAvailability(from dictionary: JSONDictionary) -> ParsedModeAvailability {
        if let availability = self.dictionary(dictionary["availability"]) {
            if let availableValue = availability["available"] {
                if let available = availableValue as? Bool {
                    return ParsedModeAvailability(
                        isAvailable: available,
                        reason: available ? nil : stringValue(availability, keys: ["message", "reason", "description"]),
                        minimumSubscriptionTier: stringValue(availability, keys: ["minimumSubscriptionTier", "minimum_subscription_tier"])
                    )
                }
                return ParsedModeAvailability(isAvailable: true, reason: nil, minimumSubscriptionTier: nil)
            }

            if let requiresUpgrade = self.dictionary(availability["requiresUpgrade"]) ??
                self.dictionary(availability["requires_upgrade"]) {
                return ParsedModeAvailability(
                    isAvailable: false,
                    reason: stringValue(requiresUpgrade, keys: ["message", "reason", "description"]),
                    minimumSubscriptionTier: stringValue(requiresUpgrade, keys: ["minimumSubscriptionTier", "minimum_subscription_tier"])
                )
            }

            if let unavailable = self.dictionary(availability["unavailable"]) ??
                self.dictionary(availability["disabled"]) {
                return ParsedModeAvailability(
                    isAvailable: false,
                    reason: stringValue(unavailable, keys: ["message", "reason", "description"]),
                    minimumSubscriptionTier: stringValue(unavailable, keys: ["minimumSubscriptionTier", "minimum_subscription_tier"])
                )
            }

            if boolValue(availability, keys: ["requiresUpgrade", "requires_upgrade"]) == true {
                return ParsedModeAvailability(
                    isAvailable: false,
                    reason: stringValue(availability, keys: ["message", "reason", "description"]),
                    minimumSubscriptionTier: stringValue(availability, keys: ["minimumSubscriptionTier", "minimum_subscription_tier"])
                )
            }
        }

        if let isAvailable = boolValue(dictionary, keys: ["available", "isAvailable", "is_available"]) {
            return ParsedModeAvailability(
                isAvailable: isAvailable,
                reason: isAvailable ? nil : stringValue(dictionary, keys: ["unavailableReason", "unavailable_reason", "reason", "message"]),
                minimumSubscriptionTier: stringValue(dictionary, keys: ["minimumSubscriptionTier", "minimum_subscription_tier"])
            )
        }

        if let disabled = boolValue(dictionary, keys: ["disabled", "isDisabled", "is_disabled"]), disabled {
            return ParsedModeAvailability(
                isAvailable: false,
                reason: stringValue(dictionary, keys: ["unavailableReason", "unavailable_reason", "reason", "message"]),
                minimumSubscriptionTier: stringValue(dictionary, keys: ["minimumSubscriptionTier", "minimum_subscription_tier"])
            )
        }

        return ParsedModeAvailability(isAvailable: true, reason: nil, minimumSubscriptionTier: nil)
    }

    private func makeTask(from dictionary: JSONDictionary, defaultIsEnabled: Bool? = nil) -> GrokTask {
        let taskDictionary = firstDictionary(from: dictionary, preferredKeys: Self.taskWrapperKeys) ?? dictionary
        var rawJSON = anyCodableDictionary(taskDictionary)
        if let schedule = firstScheduleDictionary(from: dictionary) {
            copyTaskScheduleFields(from: schedule, into: &rawJSON)
            if rawJSON["isEnabled"] == nil,
               rawJSON["is_enabled"] == nil,
               rawJSON["isActive"] == nil,
               rawJSON["is_active"] == nil,
               rawJSON["enabled"] == nil,
               rawJSON["active"] == nil,
               let scheduleEnabled = schedule["isEnabled"] as? Bool {
                rawJSON["isEnabled"] = AnyCodable(scheduleEnabled)
            }
        }
        if rawJSON["isEnabled"] == nil,
           rawJSON["is_enabled"] == nil,
           rawJSON["isActive"] == nil,
           rawJSON["is_active"] == nil,
           rawJSON["enabled"] == nil,
           rawJSON["active"] == nil,
           let defaultIsEnabled {
            rawJSON["isEnabled"] = AnyCodable(defaultIsEnabled)
        }
        return GrokTask(
            taskId: stringValue(rawJSON, keys: ["taskId", "task_id"]),
            id: stringValue(rawJSON, keys: ["id"]),
            name: stringValue(rawJSON, keys: ["name", "title", "displayName", "display_name"]),
            prompt: stringValue(rawJSON, keys: [
                "prompt",
                "taskPrompt",
                "task_prompt",
                "description",
                "summary",
                "query",
                "instructions"
            ]),
            isEnabled: boolValue(rawJSON, keys: ["isEnabled", "is_enabled", "isActive", "is_active", "enabled", "active"]),
            status: stringValue(rawJSON, keys: ["status", "state"]),
            rawJSON: rawJSON
        )
    }

    private func firstScheduleDictionary(from dictionary: JSONDictionary) -> JSONDictionary? {
        if let schedule = dictionary["schedule"] as? JSONDictionary {
            return schedule
        }
        if let schedules = dictionary["schedules"] as? [JSONDictionary] {
            return schedules.first
        }
        if let schedules = dictionary["schedules"] as? [Any] {
            return schedules.first { $0 is JSONDictionary } as? JSONDictionary
        }
        return nil
    }

    private func copyTaskScheduleFields(
        from schedule: JSONDictionary,
        into rawJSON: inout [String: AnyCodable]
    ) {
        for key in ["dayOfYear", "date", "timeOfDay", "time", "timezone", "timeZone", "nextRun"] {
            guard rawJSON[key] == nil, let value = schedule[key] else {
                continue
            }
            rawJSON[key] = AnyCodable(value)
        }
    }

    private func makeTasksResponse(from json: Any, defaultIsEnabled: Bool? = nil) -> GrokTasksResponse {
        let activeTasks = allDictionaries(from: json, keys: Self.activeTaskKeys)
            .map { makeTask(from: $0, defaultIsEnabled: true) }
        let inactiveTasks = allDictionaries(from: json, keys: Self.inactiveTaskKeys)
            .map { makeTask(from: $0, defaultIsEnabled: false) }

        let tasks: [GrokTask]
        if activeTasks.isEmpty && inactiveTasks.isEmpty {
            tasks = dictionaries(from: json, preferredKeys: Self.generalTaskKeys)
                .map { makeTask(from: $0, defaultIsEnabled: defaultIsEnabled) }
        } else {
            tasks = activeTasks + inactiveTasks
        }

        return GrokTasksResponse(
            tasks: tasks,
            activeTasks: activeTasks,
            inactiveTasks: inactiveTasks,
            rawJSON: AnyCodable(json)
        )
    }

    private func makeTaskResult(from dictionary: JSONDictionary) -> GrokTaskResult {
        let rawJSON = anyCodableDictionary(dictionary)
        return GrokTaskResult(
            resultId: stringValue(rawJSON, keys: ["taskResultId", "task_result_id", "resultId", "result_id"]),
            id: stringValue(rawJSON, keys: ["id"]),
            taskId: stringValue(rawJSON, keys: ["taskId", "task_id"]),
            conversationId: stringValue(rawJSON, keys: ["conversationId", "conversation_id"]),
            responseId: stringValue(rawJSON, keys: ["responseId", "response_id"]),
            message: taskResultMessage(from: dictionary) ?? stringValue(rawJSON, keys: ["summary", "message", "content", "output", "text", "result"]),
            status: stringValue(rawJSON, keys: ["status", "state"]),
            rawJSON: rawJSON
        )
    }

    private func makeTaskResultsResponse(from json: Any) -> GrokTaskResultsResponse {
        let resultDictionaries = dictionaries(from: json, preferredKeys: Self.taskResultKeys)
        let results: [GrokTaskResult]
        if !resultDictionaries.isEmpty {
            results = resultDictionaries.map { makeTaskResult(from: $0) }
        } else if let dictionary = firstTaskResultDictionary(in: json) {
            results = [makeTaskResult(from: dictionary)]
        } else {
            results = []
        }

        return GrokTaskResultsResponse(results: results, rawJSON: AnyCodable(json))
    }

    private func firstTaskResultDictionary(in value: Any) -> JSONDictionary? {
        if let array = value as? [Any] {
            for item in array {
                if let dictionary = firstTaskResultDictionary(in: item) {
                    return dictionary
                }
            }
            return nil
        }

        guard let dictionary = value as? JSONDictionary else {
            return nil
        }

        if isTaskResultDictionary(dictionary) {
            return dictionary
        }

        for key in Self.taskResultKeys + [
            "taskResult",
            "task_result",
            "latestResult",
            "latest_result",
            "lastResult",
            "last_result",
            "response",
            "modelResponse",
            "model_response"
        ] {
            if let nested = dictionary[key],
               let result = firstTaskResultDictionary(in: nested) {
                return result
            }
        }

        return nil
    }

    private func isTaskResultDictionary(_ dictionary: JSONDictionary) -> Bool {
        containsAnyValue(dictionary, keys: [
            "taskResultId",
            "task_result_id",
            "resultId",
            "result_id",
            "id",
            "taskId",
            "task_id",
            "conversationId",
            "conversation_id",
            "responseId",
            "response_id",
            "summary",
            "message",
            "content",
            "output",
            "text"
        ])
    }

    private func taskResultMessage(from dictionary: JSONDictionary) -> String? {
        if let direct = stringValue(dictionary, keys: ["summary", "message", "content", "output", "text", "result"]) {
            return direct
        }

        for key in ["result", "response", "modelResponse", "model_response", "conversation"] {
            if let nested = dictionary[key] as? JSONDictionary,
               let text = taskResultMessage(from: nested) {
                return text
            }
        }

        for key in ["messages", "responses", "contents", "parts"] {
            if let array = dictionary[key] as? [JSONDictionary] {
                for nested in array {
                    if let text = taskResultMessage(from: nested) {
                        return text
                    }
                }
            }
            if let array = dictionary[key] as? [Any] {
                for item in array {
                    if let nested = item as? JSONDictionary,
                       let text = taskResultMessage(from: nested) {
                        return text
                    }
                    if let text = item as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
        }

        return nil
    }

    private func makeSkill(from dictionary: JSONDictionary) -> GrokSkill {
        let rawJSON = anyCodableDictionary(dictionary)
        return GrokSkill(
            skillId: stringValue(rawJSON, keys: ["skillId", "skill_id"]),
            id: stringValue(rawJSON, keys: ["id"]),
            name: stringValue(rawJSON, keys: ["name"]),
            title: stringValue(rawJSON, keys: ["title"]),
            rawJSON: rawJSON
        )
    }

    private func makeAgentCustomization(from dictionary: JSONDictionary) -> GrokAgentCustomization? {
        let rawJSON = anyCodableDictionary(dictionary)
        guard let agentId = intValue(rawJSON, keys: ["agentId", "agent_id", "id"]) else {
            return nil
        }

        let nestedAgent = dictionary["agent"] as? JSONDictionary
        let nestedAgentJSON = nestedAgent.map { anyCodableDictionary($0) }
        let defaultName = GrokAgentCustomization.defaultName(for: agentId)
        return GrokAgentCustomization(
            agentId: agentId,
            name: stringValue(rawJSON, keys: ["name"]) ??
                nestedAgentJSON.flatMap { stringValue($0, keys: ["name"]) } ??
                defaultName,
            instructions: stringValue(rawJSON, keys: ["instructions", "customInstructions", "custom_instructions"]) ??
                nestedAgentJSON.flatMap { stringValue($0, keys: ["instructions", "customInstructions", "custom_instructions"]) } ??
                ""
        )
    }

    private func makeAgentCustomizationsResponse(from json: Any) -> GrokAgentCustomizationsResponse {
        let customizations = agentCustomizationDictionaries(from: json)
            .compactMap { makeAgentCustomization(from: $0) }

        return GrokAgentCustomizationsResponse(
            agentCustomizations: customizations.sorted { $0.agentId < $1.agentId },
            rawJSON: AnyCodable(json)
        )
    }

    private func makeSubscriptionsResponse(from json: Any) -> GrokSubscriptionsResponse {
        let subscriptions = subscriptionDictionaries(from: json)
            .map { makeSubscription(from: $0) }

        return GrokSubscriptionsResponse(
            subscriptions: subscriptions,
            currentSubscription: subscriptions.first(where: \.isActive),
            rawJSON: AnyCodable(json)
        )
    }

    private func makeSubscription(from dictionary: JSONDictionary) -> GrokSubscription {
        let rawJSON = anyCodableDictionary(dictionary)
        return GrokSubscription(
            tier: firstString(in: dictionary, keys: [
                "subscriptionTier",
                "subscription_tier",
                "tier",
                "tierName",
                "tier_name",
                "planTier",
                "plan_tier",
                "sku"
            ]),
            name: firstString(in: dictionary, keys: [
                "displayName",
                "display_name",
                "name",
                "title",
                "planName",
                "plan_name",
                "productName",
                "product_name"
            ]),
            status: firstString(in: dictionary, keys: [
                "status",
                "subscriptionStatus",
                "subscription_status",
                "state"
            ]),
            isActive: isActiveSubscription(dictionary),
            rawJSON: rawJSON
        )
    }

    private func subscriptionDictionaries(from value: Any) -> [JSONDictionary] {
        if let array = value as? [Any] {
            return array.flatMap { nested -> [JSONDictionary] in
                if let dictionary = nested as? JSONDictionary {
                    return [dictionary]
                }
                return subscriptionDictionaries(from: nested)
            }
        }

        guard let dictionary = value as? JSONDictionary else {
            return []
        }

        let preferredKeys = [
            "currentSubscription",
            "current_subscription",
            "activeSubscription",
            "active_subscription",
            "subscription",
            "subscriptions",
            "activeSubscriptions",
            "active_subscriptions",
            "userSubscriptions",
            "user_subscriptions",
            "accountSubscriptions",
            "account_subscriptions",
            "data",
            "result",
            "items"
        ]

        for key in preferredKeys {
            guard let nested = dictionary[key] else {
                continue
            }

            let found = subscriptionDictionaries(from: nested)
            if !found.isEmpty {
                return found
            }
        }

        if looksLikeSubscription(dictionary) {
            return [dictionary]
        }

        for nested in dictionary.values {
            let found = subscriptionDictionaries(from: nested)
            if !found.isEmpty {
                return found
            }
        }

        return []
    }

    private func looksLikeSubscription(_ dictionary: JSONDictionary) -> Bool {
        containsAnyKey(dictionary, keys: [
            "subscriptionTier",
            "subscription_tier",
            "tier",
            "tierName",
            "tier_name",
            "planName",
            "plan_name",
            "productName",
            "product_name",
            "subscriptionStatus",
            "subscription_status",
            "currentPeriodEnd",
            "current_period_end"
        ])
    }

    private func isActiveSubscription(_ dictionary: JSONDictionary) -> Bool {
        if let isActive = firstBool(in: dictionary, keys: [
            "isActive",
            "is_active",
            "active",
            "current",
            "isCurrent",
            "is_current",
            "subscribed",
            "isSubscribed",
            "is_subscribed",
            "hasActiveSubscription",
            "has_active_subscription"
        ]) {
            return isActive
        }

        if let status = firstString(in: dictionary, keys: [
            "status",
            "subscriptionStatus",
            "subscription_status",
            "state"
        ]) {
            let normalized = status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")

            if Self.activeSubscriptionStatuses.contains(normalized) {
                return true
            }
            if Self.inactiveSubscriptionStatuses.contains(normalized) {
                return false
            }
        }

        return true
    }

    private func agentCustomizationDictionaries(from value: Any) -> [JSONDictionary] {
        if let array = value as? [JSONDictionary],
           array.contains(where: { dictionary in
               dictionary["agentId"] != nil || dictionary["agent_id"] != nil || dictionary["id"] != nil
           }) {
            return array
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? JSONDictionary }
            if dictionaries.contains(where: { dictionary in
                dictionary["agentId"] != nil || dictionary["agent_id"] != nil || dictionary["id"] != nil
            }) {
                return dictionaries
            }

            for nested in array {
                let found = agentCustomizationDictionaries(from: nested)
                if !found.isEmpty {
                    return found
                }
            }
        }

        guard let dictionary = value as? JSONDictionary else {
            return []
        }

        let preferredKeys = [
            "values",
            "agentCustomizations",
            "agent_customizations",
            "userSettings",
            "user_settings",
            "settings",
            "data",
            "result",
            "items"
        ]

        for key in preferredKeys {
            guard let nested = dictionary[key] else {
                continue
            }
            let found = agentCustomizationDictionaries(from: nested)
            if !found.isEmpty {
                return found
            }
        }

        for nested in dictionary.values {
            let found = agentCustomizationDictionaries(from: nested)
            if !found.isEmpty {
                return found
            }
        }

        return []
    }

    private func makeWorkspace(from dictionary: JSONDictionary) -> GrokWorkspace {
        let rawJSON = anyCodableDictionary(dictionary)
        return GrokWorkspace(
            workspaceId: stringValue(rawJSON, keys: ["workspaceId", "workspace_id"]),
            id: stringValue(rawJSON, keys: ["id"]),
            name: stringValue(rawJSON, keys: ["name"]),
            title: stringValue(rawJSON, keys: ["title"]),
            icon: stringValue(rawJSON, keys: ["icon"]),
            customPersonality: stringValue(rawJSON, keys: ["customPersonality", "custom_personality"]),
            preferredModel: stringValue(rawJSON, keys: ["preferredModel", "preferred_model"]),
            rawJSON: rawJSON
        )
    }

    private func makeAsset(from dictionary: JSONDictionary) -> GrokAsset {
        let rawJSON = anyCodableDictionary(dictionary)
        return GrokAsset(
            assetId: stringValue(rawJSON, keys: ["assetId", "asset_id"]),
            fileMetadataId: stringValue(rawJSON, keys: ["fileMetadataId", "file_metadata_id"]),
            fileId: stringValue(rawJSON, keys: ["fileId", "file_id"]),
            id: stringValue(rawJSON, keys: ["id"]),
            fileName: stringValue(rawJSON, keys: ["fileName", "file_name"]),
            name: stringValue(rawJSON, keys: ["name"]),
            mimeType: stringValue(rawJSON, keys: ["mimeType", "mime_type", "fileMimeType"]),
            rawJSON: rawJSON
        )
    }

    private func firstString(in value: Any, keys: [String]) -> String? {
        if let dictionary = value as? JSONDictionary {
            for key in keys {
                if let string = dictionary[key] as? String, !string.isEmpty {
                    return string
                }
            }
            for nested in dictionary.values {
                if let string = firstString(in: nested, keys: keys) {
                    return string
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let string = firstString(in: nested, keys: keys) {
                    return string
                }
            }
        }

        return nil
    }

    private func makeFileUploadResponse(from json: Any) -> GrokFileUploadResponse {
        let assetDictionary = firstDictionary(from: json, preferredKeys: ["asset", "file", "data", "result"])
        let asset = assetDictionary.map { makeAsset(from: $0) }

        let fileMetadataId = firstString(in: json, keys: ["fileMetadataId", "file_metadata_id"])
        let fileId = firstString(in: json, keys: ["fileId", "file_id"])
        let assetId = firstString(in: json, keys: ["assetId", "asset_id"])
        let id = firstString(in: json, keys: ["id"])
        let fileName = firstString(in: json, keys: ["fileName", "file_name", "name"])

        return GrokFileUploadResponse(
            fileMetadataId: fileMetadataId,
            fileId: fileId,
            assetId: assetId,
            id: id,
            fileName: fileName,
            asset: asset,
            rawJSON: AnyCodable(json)
        )
    }

    private func makeSpeechToTextResponse(from json: Any) throws -> GrokSpeechToTextResponse {
        if let text = firstString(in: json, keys: ["text", "transcript", "message"]) {
            return GrokSpeechToTextResponse(text: text, rawJSON: AnyCodable(json))
        }

        throw GrokError.apiError("Speech-to-text response did not include a transcript")
    }

    private func makeRateLimitResponse(
        from json: Any,
        requestedModelName: String,
        fetchedAt: Date = Date()
    ) -> GrokRateLimit {
        let rateLimit = matchingRateLimitDictionary(from: json, requestedModelName: requestedModelName)
            ?? rateLimitDictionary(from: json, requestedModelName: requestedModelName)
            ?? [:]
        let modelName = firstString(in: rateLimit, keys: ["modelName", "model", "modelId", "modeId"])
            ?? (requestedModelName.isEmpty ? nil : requestedModelName)

        return GrokRateLimit(
            modelName: modelName,
            remainingResponses: firstInt(in: rateLimit, keys: Self.rateLimitRemainingKeys),
            resetAt: firstDate(in: rateLimit, keys: Self.rateLimitResetAtKeys, fetchedAt: fetchedAt),
            resetAfterSeconds: firstDurationSeconds(in: rateLimit, keys: Self.rateLimitResetAfterKeys),
            windowSeconds: firstDurationSeconds(in: rateLimit, keys: Self.rateLimitWindowKeys),
            fetchedAt: fetchedAt,
            rawJSON: AnyCodable(json)
        )
    }

    private func matchingRateLimitDictionary(from value: Any, requestedModelName: String) -> JSONDictionary? {
        guard !requestedModelName.isEmpty else {
            return nil
        }

        if let dictionary = value as? JSONDictionary {
            if let nested = dictionary[requestedModelName],
               let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                return found
            }

            if matchesRateLimitModel(dictionary, requestedModelName: requestedModelName) {
                return dictionary
            }

            for nested in dictionary.values {
                if let found = matchingRateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                    return found
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let found = matchingRateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                    return found
                }
            }
        }

        return nil
    }

    private func rateLimitDictionary(from value: Any, requestedModelName: String) -> JSONDictionary? {
        if let dictionary = value as? JSONDictionary {
            if !requestedModelName.isEmpty,
               let nested = dictionary[requestedModelName],
               let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                return found
            }

            if matchesRateLimitModel(dictionary, requestedModelName: requestedModelName) {
                return dictionary
            }

            for key in ["rateLimit", "rateLimits", "limits", "usage", "data", "result", "models", "items", "values"] {
                guard let nested = dictionary[key],
                      let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) else {
                    continue
                }
                return found
            }

            if containsAnyKey(dictionary, keys: Self.rateLimitRemainingKeys) {
                return dictionary
            }

            for nested in dictionary.values {
                if let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                    return found
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                    return found
                }
            }
        }

        return nil
    }

    private func matchesRateLimitModel(_ dictionary: JSONDictionary, requestedModelName: String) -> Bool {
        guard !requestedModelName.isEmpty else {
            return false
        }

        for key in ["modelName", "model", "modelId", "modeId", "name"] {
            guard let value = dictionary[key] else {
                continue
            }
            if stringMatchesRequestedModel(value, requestedModelName: requestedModelName) {
                return true
            }
        }

        return false
    }

    private func stringMatchesRequestedModel(_ value: Any, requestedModelName: String) -> Bool {
        if let string = value as? String {
            return string.caseInsensitiveCompare(requestedModelName) == .orderedSame
        }

        if let array = value as? [Any] {
            return array.contains { stringMatchesRequestedModel($0, requestedModelName: requestedModelName) }
        }

        return false
    }

    private func containsAnyKey(_ dictionary: JSONDictionary, keys: [String]) -> Bool {
        keys.contains { dictionary[$0] != nil }
    }

    private func firstInt(in value: Any, keys: [String]) -> Int? {
        if let dictionary = value as? JSONDictionary {
            for key in keys {
                if let int = intFromRateLimitValue(dictionary[key]) {
                    return int
                }
            }

            for nested in dictionary.values {
                if let int = firstInt(in: nested, keys: keys) {
                    return int
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let int = firstInt(in: nested, keys: keys) {
                    return int
                }
            }
        }

        return nil
    }

    private func firstDate(in value: Any, keys: [String], fetchedAt: Date) -> Date? {
        if let dictionary = value as? JSONDictionary {
            for key in keys {
                if let date = dateFromRateLimitValue(dictionary[key], fetchedAt: fetchedAt) {
                    return date
                }
            }

            for nested in dictionary.values {
                if let date = firstDate(in: nested, keys: keys, fetchedAt: fetchedAt) {
                    return date
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let date = firstDate(in: nested, keys: keys, fetchedAt: fetchedAt) {
                    return date
                }
            }
        }

        return nil
    }

    private func firstDurationSeconds(in value: Any, keys: [String]) -> Int? {
        if let dictionary = value as? JSONDictionary {
            for key in keys {
                if let seconds = durationSecondsFromRateLimitValue(dictionary[key]) {
                    return seconds
                }
            }

            for nested in dictionary.values {
                if let seconds = firstDurationSeconds(in: nested, keys: keys) {
                    return seconds
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let seconds = firstDurationSeconds(in: nested, keys: keys) {
                    return seconds
                }
            }
        }

        return nil
    }

    private func intFromRateLimitValue(_ value: Any?) -> Int? {
        guard let value else {
            return nil
        }

        if value is Bool {
            return nil
        }

        if let int = value as? Int {
            return int
        }

        if let double = value as? Double, double.isFinite {
            return Int(double)
        }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let int = Int(trimmed) {
                return int
            }
            if let double = Double(trimmed), double.isFinite {
                return Int(double)
            }
        }

        return nil
    }

    private func doubleFromRateLimitValue(_ value: Any?) -> Double? {
        guard let value else {
            return nil
        }

        if value is Bool {
            return nil
        }

        if let double = value as? Double, double.isFinite {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = Double(trimmed), double.isFinite {
                return double
            }
        }

        return nil
    }

    private func dateFromRateLimitValue(_ value: Any?, fetchedAt: Date) -> Date? {
        guard let value else {
            return nil
        }

        if let dictionary = value as? JSONDictionary {
            for key in ["at", "time", "timestamp", "date", "value", "resetAt", "resetTime"] {
                if let date = dateFromRateLimitValue(dictionary[key], fetchedAt: fetchedAt) {
                    return date
                }
            }
        }

        if let seconds = doubleFromRateLimitValue(value) {
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1_000)
            }
            if seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
            if seconds >= 0 {
                return fetchedAt.addingTimeInterval(seconds)
            }
        }

        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let formatterWithFractions = ISO8601DateFormatter()
        formatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractions.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return date
        }

        if let duration = durationSecondsFromString(trimmed) {
            return fetchedAt.addingTimeInterval(TimeInterval(duration))
        }

        return nil
    }

    private func durationSecondsFromRateLimitValue(_ value: Any?) -> Int? {
        if let int = intFromRateLimitValue(value) {
            return max(0, int)
        }

        if let string = value as? String {
            return durationSecondsFromString(string)
        }

        if let dictionary = value as? JSONDictionary {
            for key in ["seconds", "second", "value", "duration"] {
                if let seconds = durationSecondsFromRateLimitValue(dictionary[key]) {
                    return seconds
                }
            }
        }

        return nil
    }

    private func durationSecondsFromString(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return nil
        }

        if let seconds = Double(trimmed), seconds.isFinite {
            return max(0, Int(seconds))
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(\d+(?:\.\d+)?)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#
        ) else {
            return nil
        }

        let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard !matches.isEmpty else {
            return nil
        }

        let total = matches.reduce(0.0) { total, match in
            guard let numberRange = Range(match.range(at: 1), in: trimmed),
                  let unitRange = Range(match.range(at: 2), in: trimmed),
                  let number = Double(trimmed[numberRange]) else {
                return total
            }

            let unit = String(trimmed[unitRange])
            let multiplier: Double
            if unit.hasPrefix("d") {
                multiplier = 86_400
            } else if unit.hasPrefix("h") {
                multiplier = 3_600
            } else if unit.hasPrefix("m") {
                multiplier = 60
            } else {
                multiplier = 1
            }

            return total + number * multiplier
        }

        return max(0, Int(total.rounded(.up)))
    }

    private func makeConversationV2Response(from json: Any) -> GrokConversationV2Response {
        let conversation = firstDictionary(from: json, preferredKeys: ["conversation", "data", "result"])
        let conversationId = stringValue(conversation, keys: ["conversationId", "conversation_id", "id"])
        return GrokConversationV2Response(conversationId: conversationId, rawJSON: AnyCodable(json))
    }

    private func makeTypeaheadResponse(from json: Any, maxItems: Int) -> GrokTypeaheadResponse {
        var seen = Set<String>()
        let suggestions = typeaheadValues(from: json)
            .compactMap(makeTypeaheadSuggestion)
            .filter { suggestion in
                seen.insert(suggestion.text.lowercased()).inserted
            }
            .prefix(max(0, maxItems))
            .map { $0 }

        return GrokTypeaheadResponse(suggestions: suggestions, rawJSON: AnyCodable(json))
    }

    private func typeaheadValues(from value: Any) -> [Any] {
        if let array = value as? [Any] {
            return array
        }

        guard let dictionary = value as? JSONDictionary else {
            return []
        }

        if typeaheadText(in: dictionary) != nil {
            return [dictionary]
        }

        for key in ["suggestions", "items", "results", "data", "result", "queries", "completions"] {
            guard let nested = dictionary[key] else {
                continue
            }
            let values = typeaheadValues(from: nested)
            if !values.isEmpty {
                return values
            }
        }

        return []
    }

    private func makeTypeaheadSuggestion(from value: Any) -> GrokTypeaheadSuggestion? {
        if let string = value as? String {
            let text = normalizedTypeaheadText(string)
            return text.isEmpty ? nil : GrokTypeaheadSuggestion(text: text)
        }

        guard let dictionary = value as? JSONDictionary,
              let text = typeaheadText(in: dictionary) else {
            return nil
        }

        let title = stringValue(dictionary, keys: ["title", "label", "display", "name"])
        return GrokTypeaheadSuggestion(
            text: text,
            title: title == text ? nil : title,
            rawJSON: anyCodableDictionary(dictionary)
        )
    }

    private func typeaheadText(in dictionary: JSONDictionary) -> String? {
        for key in ["text", "query", "value", "completion", "suggestion", "title", "name", "label"] {
            guard let value = dictionary[key] as? String else {
                continue
            }
            let text = normalizedTypeaheadText(value)
            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func normalizedTypeaheadText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractWebSearchResults(from modelResponse: JSONDictionary?) -> [WebSearchResult]? {
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

    private func extractXPosts(from modelResponse: JSONDictionary?) -> [XPost]? {
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

    private func parseStreamLine(
        _ line: String,
        conversationId: inout String,
        responseId: inout String
    ) throws -> ConversationResponse? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("data:") {
            trimmed = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed == "[DONE]" {
            return nil
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            return nil
        }

        if let error = json["error"] {
            throw GrokError.apiError(describeAPIError(error))
        }

        let result = dictionary(json["result"]) ?? json

        if let error = result["error"] {
            throw GrokError.apiError(describeAPIError(error))
        }

        let response = dictionary(result["response"])
        if let error = response?["error"] {
            throw GrokError.apiError(describeAPIError(error))
        }

        if let conversation = dictionary(result["conversation"]),
           let id = stringValue(conversation, keys: ["conversationId", "id"]) {
            conversationId = id
        }

        let userResponse = dictionary(response?["userResponse"]) ?? dictionary(result["userResponse"])
        let modelResponse = dictionary(response?["modelResponse"]) ?? dictionary(result["modelResponse"])

        if let id = stringValue(response, keys: ["responseId", "id"]) ??
            stringValue(result, keys: ["responseId", "id"]) ??
            stringValue(userResponse, keys: ["responseId", "id"]) ??
            stringValue(modelResponse, keys: ["responseId", "id"]) {
            responseId = id
        }

        let isSoftStop = boolValue(response, keys: ["isSoftStop"]) ??
            boolValue(result, keys: ["isSoftStop"]) ??
            false
        let isThinking = boolValue(response, keys: ["isThinking"]) ??
            boolValue(result, keys: ["isThinking"]) ??
            false

        if let token = stringValueAllowingEmpty(response, keys: ["token"]) ?? stringValueAllowingEmpty(result, keys: ["token"]) {
            let isFinal = isTerminalEmptyToken(
                token,
                response: response,
                result: result,
                isThinking: isThinking,
                isSoftStop: isSoftStop
            )
            return ConversationResponse(
                message: token,
                conversationId: conversationId,
                responseId: responseId,
                timestamp: Date(),
                webSearchResults: nil,
                xposts: nil,
                isThinking: isThinking,
                isSoftStop: isSoftStop,
                isFinal: isFinal
            )
        }

        if let message = stringValue(modelResponse, keys: ["message", "text"]) {
            return ConversationResponse(
                message: message,
                conversationId: conversationId,
                responseId: responseId,
                timestamp: Date(),
                webSearchResults: extractWebSearchResults(from: modelResponse),
                xposts: extractXPosts(from: modelResponse),
                isSoftStop: false,
                isFinal: true
            )
        }

        return nil
    }

    private func yieldParsedResponse(
        _ response: ConversationResponse,
        continuation: AsyncThrowingStream<ConversationResponse, Error>.Continuation,
        accumulatedMessage: inout String,
        yieldedFinal: inout Bool
    ) {
        if response.isFinal {
            yieldedFinal = true
            let finalMessage = response.message.isEmpty ? accumulatedMessage : response.message
            continuation.yield(ConversationResponse(
                message: finalMessage,
                conversationId: response.conversationId,
                responseId: response.responseId,
                timestamp: response.timestamp,
                webSearchResults: response.webSearchResults,
                xposts: response.xposts,
                isSoftStop: response.isSoftStop,
                isFinal: true
            ))
        } else {
            if !response.isThinking {
                accumulatedMessage += response.message
            }
            continuation.yield(response)
        }
    }

    private func yieldFallbackFinalIfNeeded(
        continuation: AsyncThrowingStream<ConversationResponse, Error>.Continuation,
        conversationId: String,
        responseId: String,
        accumulatedMessage: String,
        yieldedFinal: Bool
    ) {
        guard !yieldedFinal else { return }

        let trimmed = accumulatedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        continuation.yield(ConversationResponse(
            message: trimmed,
            conversationId: conversationId,
            responseId: responseId,
            timestamp: Date(),
            webSearchResults: nil,
            xposts: nil,
            isSoftStop: false,
            isFinal: true
        ))
    }

    func streamResponses<Lines: AsyncSequence>(
        from lines: Lines,
        initialConversationId: String = ""
    ) -> AsyncThrowingStream<ConversationResponse, Error> where Lines.Element == String {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var conversationId = initialConversationId
                    var responseId = ""
                    var accumulatedMessage = ""
                    var yieldedFinal = false

                    for try await line in lines {
                        if let response = try parseStreamLine(line, conversationId: &conversationId, responseId: &responseId) {
                            let isFinal = response.isFinal
                            yieldParsedResponse(
                                response,
                                continuation: continuation,
                                accumulatedMessage: &accumulatedMessage,
                                yieldedFinal: &yieldedFinal
                            )
                            if isFinal {
                                continuation.finish()
                                return
                            }
                        }
                    }

                    yieldFallbackFinalIfNeeded(
                        continuation: continuation,
                        conversationId: conversationId,
                        responseId: responseId,
                        accumulatedMessage: accumulatedMessage,
                        yieldedFinal: yieldedFinal
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamResponses(for request: URLRequest, initialConversationId: String = "", modeId: String? = nil) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let lines = streamingLines(for: request, modeId: modeId)
        return streamResponses(from: lines, initialConversationId: initialConversationId)
    }

    private func streamingLines(for request: URLRequest, modeId: String? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let delegate = StreamingLineDelegate(
                continuation: continuation,
                validateResponse: { [weak self] response, data in
                    try self?.validateHTTPResponse(response, data: data, modeId: modeId)
                }
            )
            let streamingSession = URLSession(
                configuration: session.configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            delegate.start(request: request, session: streamingSession)

            continuation.onTermination = { _ in
                delegate.cancel()
            }
        }
    }

    private final class StreamingLineDelegate: NSObject, URLSessionDataDelegate {
        private let continuation: AsyncThrowingStream<String, Error>.Continuation
        private let validateResponse: (URLResponse, Data?) throws -> Void
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var response: URLResponse?
        private var isErrorResponse = false
        private var errorData = Data()
        private var lineBuffer = Data()

        init(
            continuation: AsyncThrowingStream<String, Error>.Continuation,
            validateResponse: @escaping (URLResponse, Data?) throws -> Void
        ) {
            self.continuation = continuation
            self.validateResponse = validateResponse
        }

        func start(request: URLRequest, session: URLSession) {
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            task.resume()
        }

        func cancel() {
            task?.cancel()
            session?.invalidateAndCancel()
            task = nil
            session = nil
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            self.response = response
            if let httpResponse = response as? HTTPURLResponse {
                isErrorResponse = !(200...299).contains(httpResponse.statusCode)
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            if isErrorResponse {
                appendErrorData(data)
                return
            }

            lineBuffer.append(data)
            yieldCompleteLines()
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            defer {
                session.finishTasksAndInvalidate()
                self.task = nil
                self.session = nil
            }

            if let error {
                continuation.finish(throwing: error)
                return
            }

            guard let response else {
                continuation.finish(throwing: GrokError.networkError(URLError(.badServerResponse)))
                return
            }

            if isErrorResponse {
                do {
                    try validateResponse(response, errorData)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                return
            }

            if !lineBuffer.isEmpty {
                do {
                    try yieldLine(lineBuffer)
                    lineBuffer.removeAll(keepingCapacity: false)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }

            continuation.finish()
        }

        private func appendErrorData(_ data: Data) {
            guard errorData.count < 8192 else { return }
            errorData.append(data.prefix(8192 - errorData.count))
        }

        private func yieldCompleteLines() {
            while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = Data(lineBuffer[..<newlineIndex])
                lineBuffer.removeSubrange(...newlineIndex)
                do {
                    try yieldLine(lineData)
                } catch {
                    continuation.finish(throwing: error)
                    cancel()
                    return
                }
            }
        }

        private func yieldLine(_ data: Data) throws {
            var lineData = data
            if lineData.last == UInt8(ascii: "\r") {
                lineData.removeLast()
            }
            guard let line = String(data: lineData, encoding: .utf8) else {
                throw GrokError.decodingError(URLError(.cannotDecodeContentData))
            }
            continuation.yield(line)
        }
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
        let payload = preparePayload(
            message: message,
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

        let request = try makeRequest(path: "/conversations/new", payload: payload)
        return try await streamResponses(for: request, modeId: modeId)
    }

    /// Sends a single message (non-streaming)
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
        let stream = try await streamMessage(
            message: message,
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
        var payload = preparePayload(
            message: message,
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
        if let parentResponseId = parentResponseId {
            payload["parentResponseId"] = parentResponseId
        }

        let request = try makeRequest(path: "/conversations/\(conversationId)/responses", payload: payload)
        return try await streamResponses(for: request, initialConversationId: conversationId, modeId: modeId)
    }

    /// Fetch a list of past conversations
    /// - Parameters:
    ///   - pageSize: The number of conversations to fetch (default 100)
    ///   - searchQuery: Optional query to search saved conversation threads.
    /// - Returns: An array of Conversation objects
    /// - Throws: Network, decoding, or API errors
    public func listConversations(pageSize: Int = 100, searchQuery: String? = nil) async throws -> [Conversation] {
        var components = URLComponents()
        components.path = "/conversations"
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        if let searchQuery = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !searchQuery.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "searchQuery", value: searchQuery))
        }

        guard let path = components.string else {
            throw GrokError.apiError("Could not build conversations request URL")
        }

        let request = try makeRequest(path: path, method: "GET")

        if isDebug {
            print("Debug URL: \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Raw JSON response:")
                print(jsonString)
                if let jsonDict = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Debug: JSON as Dictionary/Array:")
                    print(jsonDict)
                }
            }
        }

        let decoder = JSONDecoder()
        do {
            // new API format
            let conversationsResponse = try decoder.decode(ConversationsResponse.self, from: data)
            return conversationsResponse.conversations
        } catch {
            // old API format
            return try decoder.decode([Conversation].self, from: data)
        }
    }

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

        var components = URLComponents()
        components.path = "/_worker/typeahead"
        components.queryItems = [
            URLQueryItem(name: "lang", value: lang),
            URLQueryItem(name: "maxItems", value: String(maxItems)),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "source", value: String(source))
        ]

        guard let path = components.string else {
            throw GrokError.apiError("Could not build typeahead request URL")
        }

        let request = try makeRequest(path: path, method: "GET", namespace: .web)
        let json = try await jsonObject(for: request)
        return self.makeTypeaheadResponse(from: json, maxItems: maxItems)
    }

    public func shareLinkURL(conversationId: String, responseId: String? = nil, pageSize: Int = 100) async throws -> String {
        var components = URLComponents()
        components.path = "/share_links"
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "conversationId", value: conversationId)
        ]
        if let responseId, !responseId.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "responseId", value: responseId))
        }

        guard let path = components.string else {
            throw GrokError.apiError("Could not build share links request URL")
        }

        let request = try makeRequest(path: path, method: "GET")
        let json = try await jsonObject(for: request)
        if let shareURL = firstShareLinkURL(in: json) {
            return shareURL
        }

        guard let responseId, !responseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("No existing share link found and no response ID available to create one")
        }

        return try await createShareLinkURL(conversationId: conversationId, responseId: responseId)
    }

    public func createShareLinkURL(conversationId: String, responseId: String) async throws -> String {
        let encodedConversationId = conversationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationId
        let payload: [String: Any] = [
            "responseId": responseId,
            "allowIndexing": true
        ]
        let request = try makeRequest(
            path: "/conversations/\(encodedConversationId)/share",
            method: "POST",
            payload: payload
        )
        let json = try await jsonObject(for: request)
        return try makeShareLinkURL(from: json)
    }

    public func softDeleteConversation(conversationId: String) async throws {
        let encodedConversationId = conversationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationId
        let request = try makeRequest(path: "/conversations/soft/\(encodedConversationId)", method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    /// Get the response nodes for a conversation
    public func getResponseNodes(conversationId: String) async throws -> [ResponseNode] {
        let request = try makeRequest(path: "/conversations/\(conversationId)/response-node", method: "GET")

        if isDebug {
            print("Debug URL: \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Response JSON from response-node:")
                print(jsonString)
            }
        }

        let decoder = JSONDecoder()
        do {
            // common wrapper keys
            struct ResponseNodesWrapper: Codable {
                let responseNodes: [ResponseNode]
            }
            struct NodesWrapper: Codable {
                let nodes: [ResponseNode]
            }
            struct ResponsesWrapper: Codable {
                let responses: [ResponseNode]
            }

            do {
                let wrapper = try decoder.decode(ResponseNodesWrapper.self, from: data)
                return wrapper.responseNodes
            } catch {
                do {
                    let wrapper = try decoder.decode(NodesWrapper.self, from: data)
                    return wrapper.nodes
                } catch {
                    do {
                        let wrapper = try decoder.decode(ResponsesWrapper.self, from: data)
                        return wrapper.responses
                    } catch {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            for (_, value) in json {
                                if let nodesArray = value as? [[String: Any]] {
                                    var nodes = [ResponseNode]()
                                    for nodeDict in nodesArray {
                                        if let responseId = nodeDict["responseId"] as? String,
                                           let sender = nodeDict["sender"] as? String {
                                            let parentResponseId = nodeDict["parentResponseId"] as? String
                                            nodes.append(ResponseNode(
                                                responseId: responseId,
                                                sender: sender,
                                                parentResponseId: parentResponseId
                                            ))
                                        }
                                    }
                                    if !nodes.isEmpty {
                                        return nodes
                                    }
                                }
                            }
                        }
                        // fallback
                        return try decoder.decode([ResponseNode].self, from: data)
                    }
                }
            }
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    /// Load the detailed responses for a conversation
    /// - Parameter conversationId: The ID of the conversation
    /// - Parameter specificResponseIds: Optional array of specific response IDs to load, if nil will fetch all
    /// - Returns: An array of Response objects
    /// - Throws: Network, decoding, or API errors
    public func loadResponses(conversationId: String, specificResponseIds: [String]? = nil) async throws -> [Response] {
        var responseIds: [String] = []

        if let specificIds = specificResponseIds, !specificIds.isEmpty {
            responseIds = specificIds
        } else {
            do {
                let responseNodes = try await getResponseNodes(conversationId: conversationId)
                responseIds = responseNodes.map { $0.responseId }
                if isDebug {
                    print("Debug: Found \(responseIds.count) response IDs for this conversation")
                }
            } catch {
                if isDebug {
                    print("Debug: Failed to get response nodes: \(error)")
                }
            }
        }

        var requestBody: [String: Any] = [:]
        if !responseIds.isEmpty {
            requestBody["responseIds"] = responseIds
        }

        let request = try makeRequest(path: "/conversations/\(conversationId)/load-responses", payload: requestBody)

        if isDebug {
            print("Debug URL: \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Response JSON:")
                print(jsonString)
            }
        }

        let decoder = JSONDecoder()
        struct ResponsesWrapper: Codable {
            let responses: [Response]
        }

        do {
            let wrapper = try decoder.decode(ResponsesWrapper.self, from: data)
            return wrapper.responses
        } catch {
            do {
                return try decoder.decode([Response].self, from: data)
            } catch {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responsesArray = json["responses"] as? [[String: Any]] {
                    var responses: [Response] = []
                    for item in responsesArray {
                        if let responseId = item["responseId"] as? String,
                           let message = item["message"] as? String,
                           let sender = item["sender"] as? String,
                           let createTime = item["createTime"] as? String {
                            let parentResponseId = item["parentResponseId"] as? String
                            responses.append(Response(
                                responseId: responseId,
                                message: message,
                                sender: sender,
                                createTime: createTime,
                                parentResponseId: parentResponseId
                            ))
                        }
                    }
                    if !responses.isEmpty {
                        return responses
                    }
                }
                throw GrokError.decodingError(error)
            }
        }
    }

    public func listTasksResponse() async throws -> GrokTasksResponse {
        let request = try makeRequest(path: "/tasks", method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeTasksResponse(from: json)
    }

    public func listTasks() async throws -> [GrokTask] {
        try await listTasksResponse().tasks
    }

    public func listInactiveTasksResponse() async throws -> GrokTasksResponse {
        let request = try makeRequest(path: "/tasks/inactive", method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeTasksResponse(from: json, defaultIsEnabled: false)
    }

    public func listInactiveTasks() async throws -> [GrokTask] {
        try await listInactiveTasksResponse().tasks
    }

    public func taskResultsResponse(taskId: String, limit: Int = 1) async throws -> GrokTaskResultsResponse {
        var components = URLComponents()
        components.path = "/tasks/results/\(taskId)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let path = components.string else {
            throw GrokError.apiError("Could not build task results request URL")
        }

        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeTaskResultsResponse(from: json)
    }

    public func taskResults(taskId: String, limit: Int = 1) async throws -> [GrokTaskResult] {
        try await taskResultsResponse(taskId: taskId, limit: limit).results
    }

    public func latestTaskResult(taskId: String) async throws -> GrokTaskResult? {
        try await taskResults(taskId: taskId, limit: 1).first
    }

    public func createTask(
        name: String = "",
        prompt: String,
        metadataJsonString: String = "{}",
        schedule: GrokTaskSchedule,
        notificationMethod: String = "DEFAULT",
        modelMode: String = "BASE",
        notificationDeciderEnable: Bool = true,
        notificationDeciderGuideline: String = "only notify if it's economically valuable",
        modelName: String = "",
        toolset: [String] = [""]
    ) async throws -> GrokTaskMutationResponse {
        let payload: [String: Any] = [
            "name": name,
            "prompt": prompt,
            "metadataJsonString": metadataJsonString,
            "schedule": [
                "taskCadence": schedule.taskCadence,
                "isEnabled": schedule.isEnabled,
                "timezone": schedule.timezone,
                "timeOfDay": schedule.timeOfDay,
                "dayOfYear": schedule.dayOfYear
            ],
            "notificationMethod": notificationMethod,
            "modelMode": modelMode,
            "notificationDeciderEnable": notificationDeciderEnable,
            "notificationDeciderGuideline": notificationDeciderGuideline,
            "modelName": modelName,
            "toolset": toolset
        ]

        let request = try makeRequest(path: "/tasks", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        let task = firstDictionary(from: json, preferredKeys: ["task", "data", "result"])
            .map { makeTask(from: $0) }

        return GrokTaskMutationResponse(task: task, rawJSON: AnyCodable(json))
    }

    public func createTask(
        prompt: String,
        name: String? = nil,
        date: String,
        time: String,
        timezone: String,
        guideline: String? = nil,
        notificationMethod: String = "DEFAULT",
        modelMode: String = "BASE",
        notificationDeciderEnable: Bool = true,
        metadataJsonString: String = "{}",
        modelName: String = "",
        toolset: [String] = [""]
    ) async throws -> GrokTask {
        let schedule = GrokTaskSchedule(
            taskCadence: "TASK_CADENCE_ONCE",
            isEnabled: true,
            timezone: timezone,
            timeOfDay: time,
            dayOfYear: date
        )
        let response = try await createTask(
            name: name ?? "",
            prompt: prompt,
            metadataJsonString: metadataJsonString,
            schedule: schedule,
            notificationMethod: notificationMethod,
            modelMode: modelMode,
            notificationDeciderEnable: notificationDeciderEnable,
            notificationDeciderGuideline: guideline ?? "only notify if it's economically valuable",
            modelName: modelName,
            toolset: toolset
        )

        if let task = response.task {
            return task
        }

        return GrokTask(rawJSON: ["response": response.rawJSON])
    }

    public func archiveTask(taskId: String, isEnabled: Bool) async throws -> GrokTaskMutationResponse {
        let payload: [String: Any] = [
            "taskId": taskId,
            "isEnabled": isEnabled
        ]

        let request = try makeRequest(path: "/tasks/archive", method: "PUT", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        let task = firstDictionary(from: json, preferredKeys: ["task", "data", "result"])
            .map { makeTask(from: $0) }

        return GrokTaskMutationResponse(task: task, rawJSON: AnyCodable(json))
    }

    public func listSkillsResponse(locale: String = "en") async throws -> GrokSkillsResponse {
        let request = try makeRequest(path: "/skills", payload: ["locale": locale], namespace: .root)
        let json = try await jsonObject(for: request)
        let skills = dictionaries(from: json, preferredKeys: ["skills", "data", "result", "items"])
            .map { makeSkill(from: $0) }

        return GrokSkillsResponse(skills: skills, rawJSON: AnyCodable(json))
    }

    public func listSkills(locale: String = "en") async throws -> [GrokSkill] {
        try await listSkillsResponse(locale: locale).skills
    }

    public func listUserSkillsResponse() async throws -> GrokSkillsResponse {
        let request = try makeRequest(path: "/user-skills", method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        let skills = dictionaries(from: json, preferredKeys: ["userSkills", "skills", "data", "result", "items"])
            .map { makeSkill(from: $0) }

        return GrokSkillsResponse(skills: skills, rawJSON: AnyCodable(json))
    }

    public func listUserSkills() async throws -> [GrokSkill] {
        try await listUserSkillsResponse().skills
    }

    public func getUserSettingsResponse() async throws -> GrokAgentCustomizationsResponse {
        let request = try makeRequest(path: "/user-settings", method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeAgentCustomizationsResponse(from: json)
    }

    public func subscriptionsResponse() async throws -> GrokSubscriptionsResponse {
        let request = try makeRequest(path: "/subscriptions", method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeSubscriptionsResponse(from: json)
    }

    public func currentSubscription() async throws -> GrokSubscription? {
        try await subscriptionsResponse().currentSubscription
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

        let request = try makeRequest(path: "/user-settings", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        let response = makeAgentCustomizationsResponse(from: json)

        if response.agentCustomizations.isEmpty {
            return GrokAgentCustomizationsResponse(agentCustomizations: customizations, rawJSON: AnyCodable(json))
        }

        return response
    }

    public func rateLimits(modelName: String = GrokClient.defaultModeId) async throws -> GrokRateLimit {
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModelName = trimmedModelName.isEmpty ? GrokClient.defaultModeId : trimmedModelName
        let request = try makeRequest(
            path: "/rate-limits",
            payload: ["modelName": resolvedModelName],
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        return makeRateLimitResponse(from: json, requestedModelName: resolvedModelName)
    }

    public func rateLimits(mode: GrokMode) async throws -> GrokRateLimit {
        try await rateLimits(modelName: mode.id)
    }

    public static let defaultSpeechRefinementLevel = "REFINEMENT_LEVEL_POLISH"

    public static func inferAudioFormat(fromFileName fileName: String) -> String? {
        let ext = URL(fileURLWithPath: fileName)
            .pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !ext.isEmpty else {
            return nil
        }

        switch ext {
        case "webm", "wav", "mp3", "m4a", "ogg", "flac", "mp4", "mpeg", "mpga":
            return ext
        default:
            return nil
        }
    }

    public func speechToText(
        audioBase64: String,
        audioFormat: String,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) async throws -> GrokSpeechToTextResponse {
        let trimmedAudioBase64 = audioBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAudioFormat = audioFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRefinementLevel = refinementLevel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAudioBase64.isEmpty else {
            throw GrokError.apiError("Audio input is empty")
        }

        guard !trimmedAudioFormat.isEmpty else {
            throw GrokError.apiError("Audio format is required")
        }

        guard !trimmedRefinementLevel.isEmpty else {
            throw GrokError.apiError("Speech refinement level is required")
        }

        let payload: [String: Any] = [
            "audioBase64": trimmedAudioBase64,
            "audioFormat": trimmedAudioFormat,
            "refinementLevel": trimmedRefinementLevel
        ]

        let request = try makeRequest(path: "/voice/speech-to-text", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        return try makeSpeechToTextResponse(from: json)
    }

    public func speechToText(
        audioData: Data,
        audioFormat: String,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) async throws -> GrokSpeechToTextResponse {
        guard !audioData.isEmpty else {
            throw GrokError.apiError("Audio input is empty")
        }

        return try await speechToText(
            audioBase64: audioData.base64EncodedString(),
            audioFormat: audioFormat,
            refinementLevel: refinementLevel
        )
    }

    public func speechToText(
        at path: String,
        audioFormat: String? = nil,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) async throws -> GrokSpeechToTextResponse {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        let data = try Data(contentsOf: fileURL)
        let resolvedFormat = audioFormat ?? GrokClient.inferAudioFormat(fromFileName: fileURL.lastPathComponent)

        guard let resolvedFormat else {
            throw GrokError.apiError("Could not infer audio format for \(fileURL.lastPathComponent). Pass an explicit audio format.")
        }

        return try await speechToText(
            audioData: data,
            audioFormat: resolvedFormat,
            refinementLevel: refinementLevel
        )
    }

    public func uploadFile(
        fileName: String,
        fileMimeType: String,
        contentBase64: String
    ) async throws -> GrokFileUploadResponse {
        let payload: [String: Any] = [
            "fileName": fileName,
            "fileMimeType": fileMimeType,
            "content": contentBase64
        ]

        let request = try makeRequest(path: "/upload-file", payload: payload)
        let json = try await jsonObject(for: request)
        return makeFileUploadResponse(from: json)
    }

    public func uploadFile(at path: String, mimeType: String? = nil) async throws -> GrokFileUploadResponse {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        let data = try Data(contentsOf: fileURL)
        let resolvedMimeType = mimeType ?? "application/octet-stream"

        return try await uploadFile(
            fileName: fileURL.lastPathComponent,
            fileMimeType: resolvedMimeType,
            contentBase64: data.base64EncodedString()
        )
    }

    public func listModesResponse() async throws -> GrokModesResponse {
        let request = try makeRequest(path: "/modes", payload: [:], namespace: .root)
        let json = try await jsonObject(for: request)
        let modes = modeDictionaries(from: json)
            .compactMap { makeMode(from: $0) }
            .reduce(into: [GrokMode]()) { uniqueModes, mode in
                guard !uniqueModes.contains(where: { $0.id == mode.id }) else {
                    return
                }
                uniqueModes.append(mode)
            }

        return GrokModesResponse(modes: modes, rawJSON: AnyCodable(json))
    }

    public func listModes() async throws -> [GrokMode] {
        try await listModesResponse().modes
    }

    public func listAssetsResponse(
        pageSize: Int = 9,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> GrokAssetsResponse {
        let path = "/assets?pageSize=\(pageSize)&orderBy=\(orderBy)"
        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        let assets = dictionaries(from: json, preferredKeys: ["assets", "data", "result", "items"])
            .map { makeAsset(from: $0) }

        return GrokAssetsResponse(assets: assets, rawJSON: AnyCodable(json))
    }

    public func listAssets(
        pageSize: Int = 9,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> [GrokAsset] {
        try await listAssetsResponse(pageSize: pageSize, orderBy: orderBy).assets
    }

    public func deleteAsset(assetId: String) async throws -> GrokFileMutationResponse {
        let encodedId = assetId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assetId
        let request = try makeRequest(path: "/assets/\(encodedId)", method: "DELETE", namespace: .root)
        let json = try await jsonObject(for: request)
        let asset = firstDictionary(from: json, preferredKeys: ["asset", "file", "data", "result"])
            .map { makeAsset(from: $0) }
        return GrokFileMutationResponse(asset: asset, rawJSON: AnyCodable(json))
    }

    public func createWorkspace(
        name: String = "workspace",
        icon: String = "l:book-open:lime",
        customPersonality: String = "New PROJECT WORKSPACE",
        preferredModel: String = "auto"
    ) async throws -> GrokWorkspaceMutationResponse {
        let payload: [String: Any] = [
            "name": name,
            "icon": icon,
            "customPersonality": customPersonality,
            "preferredModel": preferredModel
        ]

        let request = try makeRequest(path: "/workspaces", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        let workspace = firstDictionary(from: json, preferredKeys: ["workspace", "data", "result"])
            .map { makeWorkspace(from: $0) }

        return GrokWorkspaceMutationResponse(workspace: workspace, rawJSON: AnyCodable(json))
    }

    public func listWorkspacesResponse(
        pageSize: Int = 50,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> GrokWorkspacesResponse {
        let path = "/workspaces?pageSize=\(pageSize)&orderBy=\(orderBy)"
        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        let workspaces = dictionaries(from: json, preferredKeys: ["workspaces", "data", "result", "items"])
            .map { makeWorkspace(from: $0) }

        return GrokWorkspacesResponse(workspaces: workspaces, rawJSON: AnyCodable(json))
    }

    public func listWorkspaces(
        pageSize: Int = 50,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> [GrokWorkspace] {
        try await listWorkspacesResponse(pageSize: pageSize, orderBy: orderBy).workspaces
    }

    public func deleteWorkspace(workspaceId: String) async throws -> GrokWorkspaceMutationResponse {
        let encodedWorkspaceId = workspaceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workspaceId
        let request = try makeRequest(
            path: "/workspaces/\(encodedWorkspaceId)",
            method: "DELETE",
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let workspace = firstDictionary(from: json, preferredKeys: ["workspace", "data", "result"])
            .map { makeWorkspace(from: $0) }

        return GrokWorkspaceMutationResponse(workspace: workspace, rawJSON: AnyCodable(json))
    }

    public func addConversationToWorkspace(
        workspaceId: String,
        conversationId: String
    ) async throws -> GrokWorkspaceMutationResponse {
        let payload: [String: Any] = [
            "conversationId": conversationId
        ]

        let encodedWorkspaceId = workspaceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workspaceId
        let request = try makeRequest(
            path: "/workspaces/\(encodedWorkspaceId)/conversations",
            payload: payload,
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let workspace = firstDictionary(from: json, preferredKeys: ["workspace", "data", "result"])
            .map { makeWorkspace(from: $0) }

        return GrokWorkspaceMutationResponse(workspace: workspace, rawJSON: AnyCodable(json))
    }

    public func getConversationV2(
        conversationId: String,
        includeWorkspaces: Bool = true,
        includeTaskResult: Bool = true
    ) async throws -> GrokConversationV2Response {
        let encodedConversationId = conversationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationId
        let path = "/conversations_v2/\(encodedConversationId)?includeWorkspaces=\(includeWorkspaces)&includeTaskResult=\(includeTaskResult)"
        let request = try makeRequest(path: path, method: "GET")
        let json = try await jsonObject(for: request)

        return makeConversationV2Response(from: json)
    }
}

// MARK: - URLRequest Extension for curl representation
extension URLRequest {
    func curlRepresentation(redactCookies: Bool = false) -> String {
        var components = ["curl"]
        if let method = self.httpMethod, method != "GET" {
            components.append("-X \(method)")
        }
        if let headers = self.allHTTPHeaderFields {
            for (key, value) in headers {
                let redactedHeaders = ["authorization", "cookie", "proxy-authorization", "set-cookie"]
                let headerValue = redactCookies && redactedHeaders.contains(key.lowercased()) ? "<redacted>" : value
                components.append("-H \"\(key): \(headerValue)\"")
            }
        }
        if let bodyData = self.httpBody, let body = redactedBodyString(from: bodyData) {
            // Escape single quotes in the body
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            components.append("--data '\(escapedBody)'")
        }
        if let url = self.url {
            components.append("\"\(url.absoluteString)\"")
        }
        return components.joined(separator: " ")
    }

    private func redactedBodyString(from bodyData: Data) -> String? {
        guard let body = String(data: bodyData, encoding: .utf8) else {
            return nil
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: bodyData, options: []),
            let redacted = redactedJSONValue(json),
            JSONSerialization.isValidJSONObject(redacted),
            let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: []),
            let redactedBody = String(data: redactedData, encoding: .utf8)
        else {
            return body
        }

        return redactedBody
    }

    private func redactedJSONValue(_ value: Any) -> Any? {
        let sensitiveKeys = Set(["audiobase64", "content", "data", "file"])

        if let dictionary = value as? [String: Any] {
            var redacted = [String: Any]()
            var changed = false

            for (key, nestedValue) in dictionary {
                if sensitiveKeys.contains(key.lowercased()) {
                    redacted[key] = redactedDescription(for: nestedValue)
                    changed = true
                } else if let nestedRedacted = redactedJSONValue(nestedValue) {
                    redacted[key] = nestedRedacted
                    changed = true
                } else {
                    redacted[key] = nestedValue
                }
            }

            return changed ? redacted : nil
        }

        if let array = value as? [Any] {
            var changed = false
            let redacted = array.map { nestedValue -> Any in
                if let nestedRedacted = redactedJSONValue(nestedValue) {
                    changed = true
                    return nestedRedacted
                }
                return nestedValue
            }

            return changed ? redacted : nil
        }

        return nil
    }

    private func redactedDescription(for value: Any) -> String {
        if let string = value as? String {
            return "<redacted \(string.count) chars>"
        }

        if let data = value as? Data {
            return "<redacted \(data.count) bytes>"
        }

        if let array = value as? [Any] {
            return "<redacted \(array.count) items>"
        }

        if let dictionary = value as? [String: Any] {
            return "<redacted \(dictionary.count) fields>"
        }

        return "<redacted>"
    }
}
