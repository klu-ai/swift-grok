import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Error Handling
public enum GrokError: Error, Equatable {
    case invalidCredentials
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case notFound
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
        case (.networkError, .networkError),
             (.decodingError, .decodingError):
            // Note: Cannot compare the associated Error values directly
            // Just checking if they are the same type of error
            return true
        default:
            return false
        }
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
    public let isSoftStop: Bool
    public let isFinal: Bool
    
    public init(message: String, conversationId: String, responseId: String, timestamp: Date? = nil, webSearchResults: [WebSearchResult]? = nil, xposts: [XPost]? = nil, isSoftStop: Bool = false, isFinal: Bool = false) {
        self.message = message
        self.conversationId = conversationId
        self.responseId = responseId
        self.timestamp = timestamp
        self.webSearchResults = webSearchResults
        self.xposts = xposts
        self.isSoftStop = isSoftStop
        self.isFinal = isFinal
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
    
    public init(conversationId: String, title: String, starred: Bool = false, createTime: String = "", modifyTime: String = "", systemPromptName: String = "", temporary: Bool = false, mediaTypes: [String] = []) {
        self.conversationId = conversationId
        self.title = title
        self.starred = starred
        self.createTime = createTime
        self.modifyTime = modifyTime
        self.systemPromptName = systemPromptName
        self.temporary = temporary
        self.mediaTypes = mediaTypes
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
    
    public init(responseId: String, message: String, sender: String, createTime: String, parentResponseId: String? = nil) {
        self.responseId = responseId
        self.message = message
        self.sender = sender
        self.createTime = createTime
        self.parentResponseId = parentResponseId
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
internal struct AnyCodable: Codable {
    private let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
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
    
    func encode(to encoder: Encoder) throws {
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
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
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
    private let cookies: [String: String]
    private var session: URLSession
    public var isDebug: Bool = false
    internal let headers: [String: String] = [
        "accept": "*/*",
        "accept-language": "en-GB,en;q=0.9",
        "content-type": "application/json",
        "origin": "https://grok.com",
        "priority": "u=1, i",
        "referer": "https://grok.com/",
        "sec-ch-ua": "\"Not/A)Brand\";v=\"8\", \"Chromium\";v=\"126\", \"Safari\";v=\"126\"",
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": "\"macOS\"",
        "sec-fetch-dest": "empty",
        "sec-fetch-mode": "cors",
        "sec-fetch-site": "same-origin",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    ]
    
    /// Available system prompt personalities for Grok
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
    
    /// Initializes the GrokClient with cookie credentials
    /// - Parameters:
    ///   - cookies: A dictionary of cookie name-value pairs for authentication
    ///   - isDebug: Whether to print debug information (default: false)
    /// - Throws: GrokError.invalidCredentials if credentials are empty
    public init(cookies: [String: String], isDebug: Bool = false) throws {
        guard !cookies.isEmpty else {
            throw GrokError.invalidCredentials
        }
        
        self.baseURL = "https://grok.com/rest/app-chat"
        self.cookies = cookies
        self.isDebug = isDebug
        
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
    ///   - enableReasoning: Whether to enable reasoning mode (cannot be used with deepSearch)
    ///   - enableDeepSearch: Whether to enable deep search (cannot be used with reasoning)
    ///   - disableSearch: Whether to disable web search entirely (separate from deepSearch)
    ///   - customInstructions: Optional custom instructions for the model, empty string to disable
    ///   - temporary: Whether the message and thread should not be saved (private mode)
    ///   - personalityType: Optional personality type for Grok, defaults to none
    /// - Returns: A dictionary representing the payload
    internal func preparePayload(
        message: String,
        enableReasoning: Bool = false,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none
    ) -> [String: Any] {
        if enableReasoning && enableDeepSearch {
            print("Warning: Both reasoning and deep search enabled. Deep search will be ignored.")
        }
        
        var payload: [String: Any] = [
            "temporary": temporary,
            "modelName": "grok-3",
            "message": message,
            "fileAttachments": [],
            "imageAttachments": [],
            "disableSearch": disableSearch,
            "enableImageGeneration": true,
            "returnImageBytes": false,
            "returnRawGrokInXaiRequest": false,
            "enableImageStreaming": true,
            "imageGenerationCount": 2,
            "forceConcise": false,
            "toolOverrides": [:],
            "enableSideBySide": true,
            "isPreset": false,
            "sendFinalMetadata": true,
            "customPersonality": customInstructions,
            "deepsearchPreset": enableDeepSearch ? "default" : "",
            "isReasoning": enableReasoning
        ]
        
        if !personalityType.rawValue.isEmpty {
            payload["systemPromptName"] = personalityType.rawValue
        }
        
        return payload
    }
    
    /// Sends a message to Grok and returns a streaming response
    /// - Parameters:
    ///   - message: The user's input message
    ///   - enableReasoning: Whether to enable reasoning mode (cannot be used with deepSearch)
    ///   - enableDeepSearch: Whether to enable deep search (cannot be used with reasoning)
    ///   - disableSearch: Whether to disable web search entirely (separate from deepSearch)
    ///   - customInstructions: Optional custom instructions, defaults to empty string (no instructions)
    ///   - temporary: Whether the message and thread should not be saved (private mode), defaults to false
    ///   - personalityType: Optional personality type for Grok, defaults to none
    /// - Returns: An async stream of conversation responses from Grok
    /// - Throws: Network, decoding, or API errors
    public func streamMessage(
        message: String,
        enableReasoning: Bool = false,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let url = URL(string: "\(baseURL)/conversations/new")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let payload = preparePayload(
            message: message,
            enableReasoning: enableReasoning,
            enableDeepSearch: enableDeepSearch,
            disableSearch: disableSearch,
            customInstructions: customInstructions,
            temporary: temporary,
            personalityType: personalityType
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("CURL Request (streamMessage): \(request.curlRepresentation())")
        
        #if os(Linux)
            let (data, response) = try await session.data(for: request)
        #else
            let (bytes, response) = try await session.bytes(for: request)
        #endif
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 404:
                throw GrokError.notFound
            default:
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var conversationId = ""
                    var responseId = ""
                    
                    #if os(Linux)
                        guard let fullString = String(data: data, encoding: .utf8) else {
                            throw GrokError.decodingError(URLError(.cannotDecodeContentData))
                        }
                        let lines = fullString.split(separator: "\n")
                        for line in lines {
                            if let lineData = line.data(using: .utf8),
                               let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: lineData) {
                                
                                if let conversationData = streamingResponse.result?.conversation,
                                   let id = conversationData.conversationId {
                                    conversationId = id
                                }
                                if let content = streamingResponse.result?.response,
                                   let id = content.responseId {
                                    responseId = id
                                }
                                
                                let isSoftStop = streamingResponse.result?.response?.isSoftStop ??
                                                streamingResponse.result?.isSoftStop ?? false
                                
                                if let token = streamingResponse.result?.response?.token {
                                    continuation.yield(ConversationResponse(
                                        message: token,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: nil,
                                        xposts: nil,
                                        isSoftStop: isSoftStop,
                                        isFinal: false
                                    ))
                                }
                                if isSoftStop && (streamingResponse.result?.response?.token == nil ||
                                                 streamingResponse.result?.response?.token == "") {
                                    continue
                                }
                                if let modelResponse = streamingResponse.result?.response?.modelResponse {
                                    continuation.yield(ConversationResponse(
                                        message: modelResponse.message,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: modelResponse.extractWebSearchResults(),
                                        xposts: modelResponse.extractXPosts(),
                                        isSoftStop: false,
                                        isFinal: true
                                    ))
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    #else
                        for try await line in bytes.lines {
                            if let data = line.data(using: .utf8),
                               let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: data) {
                                
                                if let conversationData = streamingResponse.result?.conversation,
                                   let id = conversationData.conversationId {
                                    conversationId = id
                                }
                                if let content = streamingResponse.result?.response,
                                   let id = content.responseId {
                                    responseId = id
                                }
                                
                                let isSoftStop = streamingResponse.result?.response?.isSoftStop ??
                                                streamingResponse.result?.isSoftStop ?? false
                                
                                if let token = streamingResponse.result?.response?.token {
                                    continuation.yield(ConversationResponse(
                                        message: token,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: nil,
                                        xposts: nil,
                                        isSoftStop: isSoftStop,
                                        isFinal: false
                                    ))
                                }
                                if isSoftStop && (streamingResponse.result?.response?.token == nil ||
                                                 streamingResponse.result?.response?.token == "") {
                                    continue
                                }
                                if let modelResponse = streamingResponse.result?.response?.modelResponse {
                                    continuation.yield(ConversationResponse(
                                        message: modelResponse.message,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: modelResponse.extractWebSearchResults(),
                                        xposts: modelResponse.extractXPosts(),
                                        isSoftStop: false,
                                        isFinal: true
                                    ))
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    #endif
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Sends a single message (non-streaming)
    public func sendMessage(
        message: String,
        enableReasoning: Bool = false,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none
    ) async throws -> ConversationResponse {
        let url = URL(string: "\(baseURL)/conversations/new")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let payload = preparePayload(
            message: message,
            enableReasoning: enableReasoning,
            enableDeepSearch: enableDeepSearch,
            disableSearch: disableSearch,
            customInstructions: customInstructions,
            temporary: temporary,
            personalityType: personalityType
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        #if os(Linux)
            let (data, response) = try await session.data(for: request)
        #else
            let (bytes, response) = try await session.bytes(for: request)
        #endif

        print("CURL Request (streamMessage): \(request.curlRepresentation())")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 404:
                throw GrokError.notFound
            default:
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        var fullResponse = ""
        var conversationId = ""
        var responseId = ""
        let webSearchResults: [WebSearchResult]? = nil
        let xposts: [XPost]? = nil
        
        #if os(Linux)
            if let fullString = String(data: data, encoding: .utf8) {
                let lines = fullString.split(separator: "\n")
                for line in lines {
                    if let lineData = line.data(using: .utf8),
                       let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: lineData) {
                        
                        if let modelResponse = streamingResponse.result?.response?.modelResponse {
                            return ConversationResponse(
                                message: modelResponse.message,
                                conversationId: conversationId,
                                responseId: responseId,
                                timestamp: Date(),
                                webSearchResults: modelResponse.extractWebSearchResults(),
                                xposts: modelResponse.extractXPosts(),
                                isSoftStop: false,
                                isFinal: true
                            )
                        }
                        if let conversationData = streamingResponse.result?.conversation,
                           let id = conversationData.conversationId {
                            conversationId = id
                        }
                        if let content = streamingResponse.result?.response,
                           let id = content.responseId {
                            responseId = id
                        }
                        
                        let isSoftStop = streamingResponse.result?.response?.isSoftStop ??
                                         streamingResponse.result?.isSoftStop ?? false
                        if isSoftStop && (streamingResponse.result?.response?.token == nil ||
                                         streamingResponse.result?.response?.token == "") {
                            continue
                        }
                        if let token = streamingResponse.result?.response?.token {
                            fullResponse += token
                        }
                    }
                }
            }
        #else
            for try await line in bytes.lines {
                if let data = line.data(using: .utf8),
                   let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: data) {
                    
                    if let modelResponse = streamingResponse.result?.response?.modelResponse {
                        return ConversationResponse(
                            message: modelResponse.message,
                            conversationId: conversationId,
                            responseId: responseId,
                            timestamp: Date(),
                            webSearchResults: modelResponse.extractWebSearchResults(),
                            xposts: modelResponse.extractXPosts(),
                            isSoftStop: false,
                            isFinal: true
                        )
                    }
                    if let conversationData = streamingResponse.result?.conversation,
                       let id = conversationData.conversationId {
                        conversationId = id
                    }
                    if let content = streamingResponse.result?.response,
                       let id = content.responseId {
                        responseId = id
                    }
                    
                    let isSoftStop = streamingResponse.result?.response?.isSoftStop ??
                                     streamingResponse.result?.isSoftStop ?? false
                    if isSoftStop && (streamingResponse.result?.response?.token == nil ||
                                     streamingResponse.result?.response?.token == "") {
                        continue
                    }
                    if let token = streamingResponse.result?.response?.token {
                        fullResponse += token
                    }
                }
            }
        #endif
        
        return ConversationResponse(
            message: fullResponse.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationId: conversationId,
            responseId: responseId,
            timestamp: Date(),
            webSearchResults: webSearchResults,
            xposts: xposts,
            isSoftStop: false,
            isFinal: true
        )
    }
    
    /// Sends a message to an existing conversation
    /// - Parameters:
    ///   - conversationId: The ID of the conversation to continue
    ///   - parentResponseId: The ID of the response this message is replying to (optional)
    ///   - message: The user's input message
    ///   - enableReasoning: Whether to enable reasoning mode
    ///   - enableDeepSearch: Whether to enable deep search
    ///   - disableSearch: Whether to disable web search entirely (separate from deepSearch)
    ///   - customInstructions: Optional custom instructions
    ///   - temporary: Whether the message and thread should not be saved (private mode), defaults to false
    ///   - personalityType: Optional personality type for Grok, defaults to none
    /// - Returns: A tuple with the complete response, response ID, web search results, and X posts
    /// - Throws: Network, decoding, or API errors
    public func continueConversation(
        conversationId: String,
        parentResponseId: String? = nil,
        message: String,
        enableReasoning: Bool = false,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: PersonalityType = .none
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        var payload = preparePayload(
            message: message,
            enableReasoning: enableReasoning,
            enableDeepSearch: enableDeepSearch,
            disableSearch: disableSearch,
            customInstructions: customInstructions,
            temporary: temporary,
            personalityType: personalityType
        )
        if let parentResponseId = parentResponseId {
            payload["parentResponseId"] = parentResponseId
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        #if os(Linux)
            request.setValue("Mozilla/5.0 (compatible; GrokClient/1.0; +https://grok.com)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            print("Response from grok: \(response)")
        #else
            let (bytes, response) = try await session.bytes(for: request)
        #endif
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 404:
                throw GrokError.notFound
            default:
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var responseId = ""
                    
                    #if os(Linux)
                        if let fullString = String(data: data, encoding: .utf8) {
                            let lines = fullString.split(separator: "\n")
                            for line in lines {
                                if let lineData = line.data(using: .utf8),
                                   let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: lineData) {
                                    
                                    if let id = streamingResponse.result?.responseId {
                                        responseId = id
                                    } else if let id = streamingResponse.result?.response?.responseId {
                                        responseId = id
                                    } else if let id = streamingResponse.result?.userResponse?.responseId {
                                        responseId = id
                                    }
                                    
                                    let isSoftStop = streamingResponse.result?.isSoftStop ??
                                                     streamingResponse.result?.response?.isSoftStop ?? false
                                    
                                    if let token = streamingResponse.result?.token, !token.isEmpty {
                                        continuation.yield(ConversationResponse(
                                            message: token,
                                            conversationId: conversationId,
                                            responseId: responseId,
                                            timestamp: Date(),
                                            webSearchResults: nil,
                                            xposts: nil,
                                            isSoftStop: isSoftStop,
                                            isFinal: false
                                        ))
                                        continue
                                    }
                                    
                                    if let token = streamingResponse.result?.response?.token, !token.isEmpty {
                                        continuation.yield(ConversationResponse(
                                            message: token,
                                            conversationId: conversationId,
                                            responseId: responseId,
                                            timestamp: Date(),
                                            webSearchResults: nil,
                                            xposts: nil,
                                            isSoftStop: isSoftStop,
                                            isFinal: false
                                        ))
                                        continue
                                    }
                                    
                                    if isSoftStop && (
                                        (streamingResponse.result?.token == nil || streamingResponse.result?.token?.isEmpty == true) &&
                                        (streamingResponse.result?.response?.token == nil || streamingResponse.result?.response?.token?.isEmpty == true)
                                    ) {
                                        continue
                                    }
                                    
                                    if let modelResponse = streamingResponse.result?.modelResponse {
                                        continuation.yield(ConversationResponse(
                                            message: modelResponse.message,
                                            conversationId: conversationId,
                                            responseId: responseId,
                                            timestamp: Date(),
                                            webSearchResults: modelResponse.extractWebSearchResults(),
                                            xposts: modelResponse.extractXPosts(),
                                            isSoftStop: false,
                                            isFinal: true
                                        ))
                                        continuation.finish()
                                        return
                                    }
                                    
                                    if let modelResponse = streamingResponse.result?.response?.modelResponse {
                                        continuation.yield(ConversationResponse(
                                            message: modelResponse.message,
                                            conversationId: conversationId,
                                            responseId: responseId,
                                            timestamp: Date(),
                                            webSearchResults: modelResponse.extractWebSearchResults(),
                                            xposts: modelResponse.extractXPosts(),
                                            isSoftStop: false,
                                            isFinal: true
                                        ))
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                        }
                    #else
                        for try await line in bytes.lines {
                            if let data = line.data(using: .utf8),
                               let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: data) {
                                
                                if let id = streamingResponse.result?.responseId {
                                    responseId = id
                                } else if let id = streamingResponse.result?.response?.responseId {
                                    responseId = id
                                } else if let id = streamingResponse.result?.userResponse?.responseId {
                                    responseId = id
                                }
                                
                                let isSoftStop = streamingResponse.result?.isSoftStop ??
                                                 streamingResponse.result?.response?.isSoftStop ?? false
                                
                                if let token = streamingResponse.result?.token, !token.isEmpty {
                                    continuation.yield(ConversationResponse(
                                        message: token,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: nil,
                                        xposts: nil,
                                        isSoftStop: isSoftStop,
                                        isFinal: false
                                    ))
                                    continue
                                }
                                
                                if let token = streamingResponse.result?.response?.token, !token.isEmpty {
                                    continuation.yield(ConversationResponse(
                                        message: token,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: nil,
                                        xposts: nil,
                                        isSoftStop: isSoftStop,
                                        isFinal: false
                                    ))
                                    continue
                                }
                                
                                if isSoftStop && (
                                    (streamingResponse.result?.token == nil || streamingResponse.result?.token?.isEmpty == true) &&
                                    (streamingResponse.result?.response?.token == nil || streamingResponse.result?.response?.token?.isEmpty == true)
                                ) {
                                    continue
                                }
                                
                                if let modelResponse = streamingResponse.result?.modelResponse {
                                    continuation.yield(ConversationResponse(
                                        message: modelResponse.message,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: modelResponse.extractWebSearchResults(),
                                        xposts: modelResponse.extractXPosts(),
                                        isSoftStop: false,
                                        isFinal: true
                                    ))
                                    continuation.finish()
                                    return
                                }
                                
                                if let modelResponse = streamingResponse.result?.response?.modelResponse {
                                    continuation.yield(ConversationResponse(
                                        message: modelResponse.message,
                                        conversationId: conversationId,
                                        responseId: responseId,
                                        timestamp: Date(),
                                        webSearchResults: modelResponse.extractWebSearchResults(),
                                        xposts: modelResponse.extractXPosts(),
                                        isSoftStop: false,
                                        isFinal: true
                                    ))
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    #endif
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Fetch a list of past conversations
    /// - Parameter pageSize: The number of conversations to fetch (default 100)
    /// - Returns: An array of Conversation objects
    /// - Throws: Network, decoding, or API errors
    public func listConversations(pageSize: Int = 100) async throws -> [Conversation] {
        let url = URL(string: "\(baseURL)/conversations?pageSize=\(pageSize)&useNewImplementation=true")!
        
        if isDebug {
            print("Debug URL: \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 404:
                throw GrokError.notFound
            default:
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
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
    
    /// Get the response nodes for a conversation
    public func getResponseNodes(conversationId: String) async throws -> [ResponseNode] {
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/response-node")!
        
        if isDebug {
            print("Debug URL: \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 404:
                throw GrokError.notFound
            default:
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
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
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/load-responses")!
        
        if isDebug {
            print("Debug URL: \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
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
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 404:
                throw GrokError.notFound
            default:
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
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
}

// MARK: - URLRequest Extension for curl representation
extension URLRequest {
    func curlRepresentation() -> String {
        var components = ["curl"]
        if let method = self.httpMethod, method != "GET" {
            components.append("-X \(method)")
        }
        if let headers = self.allHTTPHeaderFields {
            for (key, value) in headers {
                components.append("-H \"\(key): \(value)\"")
            }
        }
        if let bodyData = self.httpBody, let body = String(data: bodyData, encoding: .utf8) {
            // Escape single quotes in the body
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            components.append("--data '\(escapedBody)'")
        }
        if let url = self.url {
            components.append("\"\(url.absoluteString)\"")
        }
        return components.joined(separator: " ")
    }
}
