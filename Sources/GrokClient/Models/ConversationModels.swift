import Foundation

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

public struct GrokConversationV2Response: Codable {
    public let conversationId: String?
    public let rawJSON: AnyCodable
}
