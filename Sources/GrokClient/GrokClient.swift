import Foundation

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
    
    public init(message: String, conversationId: String, responseId: String, timestamp: Date? = nil, webSearchResults: [WebSearchResult]? = nil, xposts: [XPost]? = nil) {
        self.message = message
        self.conversationId = conversationId
        self.responseId = responseId
        self.timestamp = timestamp
        self.webSearchResults = webSearchResults
        self.xposts = xposts
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
            // Skip empty username entries
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
    ///              Required cookies: x-anonuserid, x-challenge, x-signature, sso, sso-rw
    ///   - isDebug: Whether to print debug information (default: false)
    /// - Throws: GrokError.invalidCredentials if credentials are empty
    public init(cookies: [String: String], isDebug: Bool = false) throws {
        guard !cookies.isEmpty else {
            throw GrokError.invalidCredentials
        }
        
        self.baseURL = "https://grok.com/rest/app-chat"
        self.cookies = cookies
        self.isDebug = isDebug
        
        // Configure URLSession with cookies
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
            // 03152025 customInstructions -> customPersonality
            "customPersonality": customInstructions,          
            "deepsearchPreset": enableDeepSearch ? "default" : "",
            "isReasoning": enableReasoning
        ]
        
        // Only add systemPromptName if it's not empty
        if !personalityType.rawValue.isEmpty {
            payload["systemPromptName"] = personalityType.rawValue
        }
        
        return payload
    }
    
    /// Sends a message to Grok and returns the complete response
    /// - Parameters:
    ///   - message: The user's input message
    ///   - enableReasoning: Whether to enable reasoning mode (cannot be used with deepSearch)
    ///   - enableDeepSearch: Whether to enable deep search (cannot be used with reasoning)
    ///   - disableSearch: Whether to disable web search entirely (separate from deepSearch)
    ///   - customInstructions: Optional custom instructions, defaults to empty string (no instructions)
    ///   - temporary: Whether the message and thread should not be saved (private mode), defaults to false
    ///   - personalityType: Optional personality type for Grok, defaults to none
    /// - Returns: A tuple with the complete response and conversationId from Grok
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
        
        // Prepare payload
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
        
        // Create a URLSession that can handle streams
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw GrokError.unauthorized
            case 404: throw GrokError.notFound
            default: throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var conversationId = ""
                    var responseId = ""
                    
                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: data) {
                            
                            // Capture conversation ID
                            if let conversationData = streamingResponse.result?.conversation,
                               let id = conversationData.conversationId {
                                conversationId = id
                            }
                            
                            // Capture response ID
                            if let content = streamingResponse.result?.response,
                               let id = content.responseId {
                                responseId = id
                            }
                            
                            // Yield token if present
                            if let token = streamingResponse.result?.response?.token {
                                continuation.yield(ConversationResponse(
                                    message: token,
                                    conversationId: conversationId,
                                    responseId: responseId,
                                    timestamp: Date(),
                                    webSearchResults: nil,
                                    xposts: nil
                                ))
                            }
                            
                            // Yield complete response if present
                            if let modelResponse = streamingResponse.result?.response?.modelResponse {
                                continuation.yield(ConversationResponse(
                                    message: modelResponse.message,
                                    conversationId: conversationId,
                                    responseId: responseId,
                                    timestamp: Date(),
                                    webSearchResults: modelResponse.extractWebSearchResults(),
                                    xposts: modelResponse.extractXPosts()
                                ))
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
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
        
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Prepare payload
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
        
        // Create a URLSession that can handle streams
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw GrokError.unauthorized
            case 404: throw GrokError.notFound
            default: throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        // Process the streaming response
        var fullResponse = ""
        var conversationId = ""
        var responseId = ""
        let webSearchResults: [WebSearchResult]? = nil
        let xposts: [XPost]? = nil
        
        for try await line in bytes.lines {
            // Parse the JSON from each line
            if let data = line.data(using: .utf8),
               let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: data) {
                
                // Check for complete response
                if let modelResponse = streamingResponse.result?.response?.modelResponse {
                    return ConversationResponse(
                        message: modelResponse.message,
                        conversationId: conversationId,
                        responseId: responseId,
                        timestamp: Date(),
                        webSearchResults: modelResponse.extractWebSearchResults(),
                        xposts: modelResponse.extractXPosts()
                    )
                }
                
                // Capture the conversation ID if available
                if let conversationData = streamingResponse.result?.conversation,
                   let id = conversationData.conversationId {
                    conversationId = id
                }
                
                // Capture the response ID if available
                if let content = streamingResponse.result?.response,
                   let id = content.responseId {
                    responseId = id
                }
                
                // Accumulate token
                if let token = streamingResponse.result?.response?.token {
                    fullResponse += token
                }
            }
            // Continue to next line if this one can't be parsed
        }
        
        return ConversationResponse(
            message: fullResponse.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationId: conversationId,
            responseId: responseId,
            timestamp: Date(),
            webSearchResults: webSearchResults,
            xposts: xposts
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
    ) async throws -> (message: String, responseId: String, webSearchResults: [WebSearchResult]?, xposts: [XPost]?) {
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Prepare payload with parent response ID
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
        
        // Create a URLSession that can handle streams
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw GrokError.unauthorized
            case 404: throw GrokError.notFound
            default: throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        // Process the streaming response
        var fullResponse = ""
        var responseId = ""
        var webSearchResults: [WebSearchResult]? = nil
        var xposts: [XPost]? = nil
        var foundCompleteResponse = false
        
        for try await line in bytes.lines {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            
            if let data = line.data(using: .utf8) {
                do {
                    // Parse the JSON response
                    let streamingResponse = try JSONDecoder().decode(StreamingResponse.self, from: data)
                    
                    // Handle both response formats
                    
                    // Check for complete response in /new format (nested under response.modelResponse)
                    if let nestedModelResponse = streamingResponse.result?.response?.modelResponse {
                        foundCompleteResponse = true
                        fullResponse = nestedModelResponse.message
                        
                        // Capture responseId from model response or parent
                        if let respId = nestedModelResponse.responseId ?? streamingResponse.result?.response?.responseId {
                            responseId = respId
                        }
                        
                        // Extract web search results and X posts
                        webSearchResults = nestedModelResponse.extractWebSearchResults()
                        xposts = nestedModelResponse.extractXPosts()
                    }
                    
                    // Check for complete response in /responses format (directly under result.modelResponse)
                    else if let directModelResponse = streamingResponse.result?.modelResponse {
                        foundCompleteResponse = true
                        fullResponse = directModelResponse.message
                        
                        // Capture responseId from model response or parent
                        if let respId = directModelResponse.responseId ?? streamingResponse.result?.responseId {
                            responseId = respId
                        }
                        
                        // Extract web search results and X posts
                        webSearchResults = directModelResponse.extractWebSearchResults()
                        xposts = directModelResponse.extractXPosts()
                    }
                    
                    // Accumulate token if this is a streaming token
                    else if let token = streamingResponse.result?.response?.token {
                        fullResponse += token
                        
                        // Capture responseId if available
                        if let respId = streamingResponse.result?.response?.responseId ?? streamingResponse.result?.responseId {
                            responseId = respId
                        }
                    }
                } catch {
                    // Fallback: try to parse as raw JSON and extract data
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            // Try to navigate through the JSON structure
                            if let result = json["result"] as? [String: Any] {
                                // Format 1: Check if modelResponse is directly in result
                                if let modelResponse = result["modelResponse"] as? [String: Any],
                                   let message = modelResponse["message"] as? String {
                                    foundCompleteResponse = true
                                    fullResponse = message
                                    
                                    if let respId = modelResponse["responseId"] as? String ?? result["responseId"] as? String {
                                        responseId = respId
                                    }
                                    
                                    // Try to extract web search results
                                    if let webSearchResultsJson = modelResponse["webSearchResults"] as? [[String: Any]] {
                                        var results: [WebSearchResult] = []
                                        for resultJson in webSearchResultsJson {
                                            if let url = resultJson["url"] as? String, !url.isEmpty,
                                               let title = resultJson["title"] as? String,
                                               let preview = resultJson["preview"] as? String {
                                                let siteName = resultJson["siteName"] as? String
                                                let description = resultJson["description"] as? String
                                                let citationId = resultJson["citationId"] as? String
                                                
                                                results.append(WebSearchResult(
                                                    url: url,
                                                    title: title,
                                                    preview: preview,
                                                    siteName: siteName?.isEmpty ?? true ? nil : siteName,
                                                    description: description?.isEmpty ?? true ? nil : description,
                                                    citationId: citationId?.isEmpty ?? true ? nil : citationId
                                                ))
                                            }
                                        }
                                        if !results.isEmpty {
                                            webSearchResults = results
                                        }
                                    }
                                    
                                    // Try to extract X posts
                                    if let xpostsJson = modelResponse["xposts"] as? [[String: Any]] {
                                        var posts: [XPost] = []
                                        for postJson in xpostsJson {
                                            if let username = postJson["username"] as? String, !username.isEmpty,
                                               let name = postJson["name"] as? String,
                                               let text = postJson["text"] as? String,
                                               let postId = postJson["postId"] as? String {
                                                let createTime = postJson["createTime"] as? String
                                                let profileImageUrl = postJson["profileImageUrl"] as? String
                                                let citationId = postJson["citationId"] as? String
                                                
                                                posts.append(XPost(
                                                    username: username,
                                                    name: name,
                                                    text: text,
                                                    postId: postId,
                                                    createTime: createTime?.isEmpty ?? true ? nil : createTime,
                                                    profileImageUrl: profileImageUrl?.isEmpty ?? true ? nil : profileImageUrl,
                                                    citationId: citationId?.isEmpty ?? true ? nil : citationId
                                                ))
                                            }
                                        }
                                        if !posts.isEmpty {
                                            xposts = posts
                                        }
                                    }
                                }
                                // Format 2: Check if modelResponse is in result.response
                                else if let response = result["response"] as? [String: Any],
                                        let modelResponse = response["modelResponse"] as? [String: Any],
                                        let message = modelResponse["message"] as? String {
                                    foundCompleteResponse = true
                                    fullResponse = message
                                    
                                    if let respId = modelResponse["responseId"] as? String ?? response["responseId"] as? String {
                                        responseId = respId
                                    }
                                    
                                    // Try to extract web search results
                                    if let webSearchResultsJson = modelResponse["webSearchResults"] as? [[String: Any]] {
                                        var results: [WebSearchResult] = []
                                        for resultJson in webSearchResultsJson {
                                            if let url = resultJson["url"] as? String, !url.isEmpty,
                                               let title = resultJson["title"] as? String,
                                               let preview = resultJson["preview"] as? String {
                                                let siteName = resultJson["siteName"] as? String
                                                let description = resultJson["description"] as? String
                                                let citationId = resultJson["citationId"] as? String
                                                
                                                results.append(WebSearchResult(
                                                    url: url,
                                                    title: title,
                                                    preview: preview,
                                                    siteName: siteName?.isEmpty ?? true ? nil : siteName,
                                                    description: description?.isEmpty ?? true ? nil : description,
                                                    citationId: citationId?.isEmpty ?? true ? nil : citationId
                                                ))
                                            }
                                        }
                                        if !results.isEmpty {
                                            webSearchResults = results
                                        }
                                    }
                                    
                                    // Try to extract X posts
                                    if let xpostsJson = modelResponse["xposts"] as? [[String: Any]] {
                                        var posts: [XPost] = []
                                        for postJson in xpostsJson {
                                            if let username = postJson["username"] as? String, !username.isEmpty,
                                               let name = postJson["name"] as? String,
                                               let text = postJson["text"] as? String,
                                               let postId = postJson["postId"] as? String {
                                                let createTime = postJson["createTime"] as? String
                                                let profileImageUrl = postJson["profileImageUrl"] as? String
                                                let citationId = postJson["citationId"] as? String
                                                
                                                posts.append(XPost(
                                                    username: username,
                                                    name: name,
                                                    text: text,
                                                    postId: postId,
                                                    createTime: createTime?.isEmpty ?? true ? nil : createTime,
                                                    profileImageUrl: profileImageUrl?.isEmpty ?? true ? nil : profileImageUrl,
                                                    citationId: citationId?.isEmpty ?? true ? nil : citationId
                                                ))
                                            }
                                        }
                                        if !posts.isEmpty {
                                            xposts = posts
                                        }
                                    }
                                }
                                // Format 3: Check for token in streaming response
                                else if let response = result["response"] as? [String: Any],
                                        let token = response["token"] as? String {
                                    fullResponse += token
                                    
                                    if let respId = response["responseId"] as? String {
                                        responseId = respId
                                    }
                                }
                            }
                        }
                    } catch {
                        // Continue to next line if we can't parse this format
                        continue
                    }
                }
            }
        }
        
        // If we found a complete response, return it
        if foundCompleteResponse && !fullResponse.isEmpty {
            return (message: fullResponse, responseId: responseId, webSearchResults: webSearchResults, xposts: xposts)
        }
        
        // Fallback to returning whatever we accumulated
        return (
            message: fullResponse.trimmingCharacters(in: .whitespacesAndNewlines),
            responseId: responseId,
            webSearchResults: webSearchResults,
            xposts: xposts
        )
    }
    
    /// Legacy method to start a new conversation (maintained for compatibility)
    /// - Returns: A Conversation object representing the new conversation
    /// - Throws: Network, decoding, or API errors
    // public func startNewConversation() async throws -> Conversation {
    //     // In the new API structure, conversations are created when sending a message
    //     // This is a compatibility method that returns a placeholder conversation
    //     return Conversation(conversationId: "new_conversation", title: "New Conversation", starred: false, createTime: "", modifyTime: "", systemPromptName: "", temporary: false, mediaTypes: [])
    // }
    
    /// Legacy method to send a message to a specific conversation (maintained for compatibility)
    /// - Parameters:
    ///   - conversationId: The ID of the conversation (ignored in the new implementation)
    ///   - message: The message content to send
    /// - Returns: A MessageResponse object with the API response
    /// - Throws: Network, decoding, or API errors
    // public func sendMessage(conversationId: String, message: String) async throws -> MessageResponse {
    //     // For backward compatibility, we'll just start a new conversation
    //     let response = try await sendMessage(message: message)
    //     return MessageResponse(message: response.message, timestamp: response.timestamp)
    // }
    
    /// Fetch a list of past conversations
    /// - Parameter pageSize: The number of conversations to fetch (default 100)
    /// - Returns: An array of Conversation objects
    /// - Throws: Network, decoding, or API errors
    public func listConversations(pageSize: Int = 100) async throws -> [Conversation] {
        let url = URL(string: "\(baseURL)/conversations?pageSize=\(pageSize)&useNewImplementation=true")!
        
        // Print debug information
        if isDebug {
            print("Debug URL: \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw GrokError.unauthorized
            case 404: throw GrokError.notFound
            default: throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        // Print raw response for debugging
        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Raw JSON response:")
                print(jsonString)
                
                // Also try to print as a dictionary
                if let jsonDict = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Debug: JSON as Dictionary/Array:")
                    print(jsonDict)
                }
            }
        }
        
        // Decode the response
        do {
            let decoder = JSONDecoder()
            
            // Try to decode as a ConversationsResponse first (new API format)
            do {
                let conversationsResponse = try decoder.decode(ConversationsResponse.self, from: data)
                return conversationsResponse.conversations
            } catch {
                // If that fails, try to decode as an array directly (old API format)
                return try decoder.decode([Conversation].self, from: data)
            }
        } catch {
            throw GrokError.decodingError(error)
        }
    }
    
    /// Get the response nodes for a conversation
    /// - Parameter conversationId: The ID of the conversation
    /// - Returns: An array of ResponseNode objects
    /// - Throws: Network, decoding, or API errors
    public func getResponseNodes(conversationId: String) async throws -> [ResponseNode] {
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/response-node")!
        
        // Print debug information
        if isDebug {
            print("Debug URL: \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw GrokError.unauthorized
            case 404: throw GrokError.notFound
            default: throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        // Print response data for debugging
        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Response JSON from response-node:")
                print(jsonString)
            }
        }
        
        // Decode the response
        do {
            let decoder = JSONDecoder()
            
            // First try to decode as a dictionary with common wrapper keys
            do {
                // Try "responseNodes" key
                struct ResponseNodesWrapper: Codable {
                    let responseNodes: [ResponseNode]
                }
                
                do {
                    let wrapper = try decoder.decode(ResponseNodesWrapper.self, from: data)
                    return wrapper.responseNodes
                } catch {
                    // Try "nodes" key
                    struct NodesWrapper: Codable {
                        let nodes: [ResponseNode]
                    }
                    
                    do {
                        let wrapper = try decoder.decode(NodesWrapper.self, from: data)
                        return wrapper.nodes
                    } catch {
                        // Try "responses" key
                        struct ResponsesWrapper: Codable {
                            let responses: [ResponseNode]
                        }
                        
                        do {
                            let wrapper = try decoder.decode(ResponsesWrapper.self, from: data)
                            return wrapper.responses
                        } catch {
                            // If no known wrapper key works, try manual parsing
                            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                // Find a key that contains an array of dictionaries
                                for (key, value) in json {
                                    if let nodesArray = value as? [[String: Any]] {
                                        if isDebug {
                                            print("Debug: Found array in key '\(key)' with \(nodesArray.count) items")
                                        }
                                        
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
                            
                            // As a last resort, try direct array decode
                            return try decoder.decode([ResponseNode].self, from: data)
                        }
                    }
                }
            } catch {
                if isDebug {
                    print("Debug: Failed to decode response-node: \(error)")
                }
                throw GrokError.decodingError(error)
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
        // The URL is correct - keep using "/load-responses"
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/load-responses")!
        
        // Print debug information
        if isDebug {
            print("Debug URL: \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        // Change to POST method
        request.httpMethod = "POST"
        
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Use provided response IDs or get all of them
        var responseIds: [String] = []
        
        if let specificIds = specificResponseIds, !specificIds.isEmpty {
            responseIds = specificIds
        } else {
            // First, we need to get the response IDs for this conversation
            do {
                let responseNodes = try await getResponseNodes(conversationId: conversationId)
                responseIds = responseNodes.map { $0.responseId }
                
                if isDebug {
                    print("Debug: Found \(responseIds.count) response IDs for this conversation")
                }
            } catch {
                if isDebug {
                    print("Debug: Failed to get response nodes, trying to load all responses: \(error)")
                }
                // Continue with an empty array - some API implementations allow this to fetch all responses
            }
        }
        
        // Create request body, either with responseIds or empty
        var requestBody: [String: Any] = [:]
        if !responseIds.isEmpty {
            requestBody["responseIds"] = responseIds
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw GrokError.unauthorized
            case 404: throw GrokError.notFound
            default: throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)")
            }
        }
        
        // Print response data for debugging
        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Response JSON:")
                print(jsonString)
            }
        }
        
        // Try to decode using different approaches
        do {
            let decoder = JSONDecoder()
            
            // Primary approach: decode as a wrapper with responses array
            struct ResponsesWrapper: Codable {
                let responses: [Response]
            }
            
            do {
                let wrapper = try decoder.decode(ResponsesWrapper.self, from: data)
                return wrapper.responses
            } catch {
                if isDebug {
                    print("Debug: Failed to decode as ResponsesWrapper: \(error)")
                }
                
                // Fallback 1: Try to decode directly as an array of Response
                do {
                    let responses = try decoder.decode([Response].self, from: data)
                    return responses
                } catch {
                    if isDebug {
                        print("Debug: Failed to decode as [Response]: \(error)")
                    }
                    
                    // Fallback 2: Try to parse manually using JSONSerialization
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
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
                    
                    // If we got this far, all decode attempts failed
                    throw GrokError.decodingError(error)
                }
            }
        } catch {
            throw GrokError.decodingError(error)
        }
    }
} 