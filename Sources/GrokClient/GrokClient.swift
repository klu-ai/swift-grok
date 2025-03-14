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

public struct Conversation: Codable {
    public let id: String
    public let title: String
    
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - Streaming Response Models
fileprivate struct StreamingResponse: Codable {
    let result: StreamingResult?
}

fileprivate struct StreamingResult: Codable {
    let response: ResponseContent?
}

fileprivate struct ResponseContent: Codable {
    let token: String?
    let modelResponse: ModelResponse?
}

fileprivate struct ModelResponse: Codable {
    let message: String
}

// MARK: - GrokClient Class
public class GrokClient {
    private let baseURL: String
    private let cookies: [String: String]
    private var session: URLSession
    
    // Default headers that match the Python implementation
    private let headers: [String: String] = [
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
    private func preparePayload(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, customInstructions: String = "") -> [String: Any] {
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
    /// - Returns: The complete response from Grok
    /// - Throws: Network, decoding, or API errors
    public func sendMessage(message: String, enableReasoning: Bool = false, enableDeepSearch: Bool = false, customInstructions: String = "") async throws -> String {
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
        
        for try await line in bytes.lines {
            // Parse the JSON from each line
            if let data = line.data(using: .utf8),
               let streamingResponse = try? JSONDecoder().decode(StreamingResponse.self, from: data) {
                
                // Check for complete response
                if let modelResponse = streamingResponse.result?.response?.modelResponse {
                    return modelResponse.message
                }
                
                // Accumulate token
                if let token = streamingResponse.result?.response?.token {
                    fullResponse += token
                }
            }
            // Continue to next line if this one can't be parsed
        }
        
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let response = try await sendMessage(message: message)
        return MessageResponse(message: response, timestamp: Date())
    }
} 