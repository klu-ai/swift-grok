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
    public let id: String
    public let title: String
    
    public init(id: String, title: String) {
        self.id = id
        self.title = title
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
    
    /// Initializes the GrokClient with cookie credentials
    /// - Parameters:
    ///   - cookies: A dictionary of cookie name-value pairs for authentication
    ///              Required cookies: x-anonuserid, x-challenge, x-signature, sso, sso-rw
    /// - Throws: GrokError.invalidCredentials if credentials are empty
    public init(cookies: [String: String]) throws {
        guard !cookies.isEmpty else {
            throw GrokError.invalidCredentials
        }
        
        self.baseURL = "https://grok.com/rest/app-chat"
        self.cookies = cookies
        
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
    ///   - customInstructions: Optional custom instructions for the model, empty string to disable
    /// - Returns: A dictionary representing the payload
    internal func preparePayload(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, customInstructions: String = "") -> [String: Any] {
        if enableReasoning && enableDeepSearch {
            print("Warning: Both reasoning and deep search enabled. Deep search will be ignored.")
        }
        
        return [
            "temporary": false,
            "modelName": "grok-3",
            "message": message,
            "fileAttachments": [],
            "imageAttachments": [],
            "disableSearch": false,
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
            "customInstructions": customInstructions,
            "deepsearchPreset": enableDeepSearch ? "default" : "",
            "isReasoning": enableReasoning
        ]
    }
    
    /// Sends a message to Grok and returns the complete response
    /// - Parameters:
    ///   - message: The user's input message
    ///   - enableReasoning: Whether to enable reasoning mode (cannot be used with deepSearch)
    ///   - enableDeepSearch: Whether to enable deep search (cannot be used with reasoning)
    ///   - customInstructions: Optional custom instructions, defaults to empty string (no instructions)
    /// - Returns: A tuple with the complete response and conversationId from Grok
    /// - Throws: Network, decoding, or API errors
    public func sendMessage(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, customInstructions: String = "") async throws -> ConversationResponse {
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
            customInstructions: customInstructions
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
    ///   - parentResponseId: The ID of the response this message is replying to
    ///   - message: The user's input message
    ///   - enableReasoning: Whether to enable reasoning mode
    ///   - enableDeepSearch: Whether to enable deep search
    ///   - customInstructions: Optional custom instructions
    /// - Returns: A tuple with the complete response, response ID, web search results, and X posts
    /// - Throws: Network, decoding, or API errors
    public func continueConversation(
        conversationId: String,
        parentResponseId: String,
        message: String,
        enableReasoning: Bool = false,
        enableDeepSearch: Bool = false,
        customInstructions: String = ""
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
            customInstructions: customInstructions
        )
        payload["parentResponseId"] = parentResponseId
        
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
    public func startNewConversation() async throws -> Conversation {
        // In the new API structure, conversations are created when sending a message
        // This is a compatibility method that returns a placeholder conversation
        return Conversation(id: "new_conversation", title: "New Conversation")
    }
    
    /// Legacy method to send a message to a specific conversation (maintained for compatibility)
    /// - Parameters:
    ///   - conversationId: The ID of the conversation (ignored in the new implementation)
    ///   - message: The message content to send
    /// - Returns: A MessageResponse object with the API response
    /// - Throws: Network, decoding, or API errors
    public func sendMessage(conversationId: String, message: String) async throws -> MessageResponse {
        // For backward compatibility, we'll just start a new conversation
        let response = try await sendMessage(message: message)
        return MessageResponse(message: response.message, timestamp: response.timestamp)
    }
} 