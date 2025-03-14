import Foundation

/// This file contains example code for using the GrokClient.
/// These functions are not meant to be used directly but serve as documentation on how to use the library.

/// Example of basic client usage
/// - Returns: A function that demonstrates basic client initialization and API calls
public func grokClientBasicExample() async {
    // Replace with your actual cookies from the browser
    // Required cookies: x-anonuserid, x-challenge, x-signature, sso, sso-rw
    let cookies = [
        "x-anonuserid": "your_anon_user_id",
        "x-challenge": "your_challenge_value",
        "x-signature": "your_signature_value",
        "sso": "your_sso_cookie",
        "sso-rw": "your_sso_rw_cookie"
    ]
    
    do {
        // Initialize the client
        let client = try GrokClient(cookies: cookies)
        
        // Send a message and get the complete response
        let response = try await client.sendMessage(message: "What is artificial intelligence?")
        print("Response: \(response)")
        
    } catch GrokError.invalidCredentials {
        print("Error: Invalid or empty credentials")
    } catch GrokError.unauthorized {
        print("Error: Unauthorized - check your cookies")
    } catch GrokError.notFound {
        print("Error: Resource not found")
    } catch GrokError.networkError(let error) {
        print("Network error: \(error.localizedDescription)")
    } catch GrokError.decodingError(let error) {
        print("Decoding error: \(error.localizedDescription)")
    } catch GrokError.apiError(let message) {
        print("API error: \(message)")
    } catch {
        print("Unexpected error: \(error.localizedDescription)")
    }
}

/// Example using the reasoning mode
public func grokClientReasoningExample() async {
    let cookies = ["x-anonuserid": "your_anon_user_id", "x-challenge": "your_challenge_value"]
    
    do {
        let client = try GrokClient(cookies: cookies)
        
        // Enable reasoning mode (step-by-step thinking)
        let response = try await client.sendMessage(
            message: "Solve this math problem: If a train travels at 60 mph, how long will it take to travel 240 miles?",
            enableReasoning: true
        )
        
        print("Reasoning Response: \(response)")
    } catch {
        print("Error: \(error)")
    }
}

/// Example using the deep search mode
public func grokClientDeepSearchExample() async {
    let cookies = ["x-anonuserid": "your_anon_user_id", "x-challenge": "your_challenge_value"]
    
    do {
        let client = try GrokClient(cookies: cookies)
        
        // Enable deep search for more comprehensive results
        let response = try await client.sendMessage(
            message: "What are the latest advancements in quantum computing?",
            enableDeepSearch: true
        )
        
        print("Deep Search Response: \(response)")
    } catch {
        print("Error: \(error)")
    }
}

/// Example of extracting cookies from a browser cookie string
/// - Parameter cookieString: The raw cookie string copied from browser developer tools
/// - Returns: A dictionary of cookie name-value pairs
public func extractCookiesFromString(_ cookieString: String) -> [String: String] {
    var cookies = [String: String]()
    
    let cookiePairs = cookieString.components(separatedBy: "; ")
    for pair in cookiePairs {
        let keyValue = pair.components(separatedBy: "=")
        if keyValue.count == 2 {
            let name = keyValue[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = keyValue[1].trimmingCharacters(in: .whitespacesAndNewlines)
            cookies[name] = value
        }
    }
    
    return cookies
}

/// Example showing how to use the legacy API (for backward compatibility)
public func grokClientLegacyExample() async {
    let cookies = ["x-anonuserid": "your_anon_user_id", "x-challenge": "your_challenge_value"]
    
    do {
        let client = try GrokClient(cookies: cookies)
        
        // Using the legacy API that works with conversation IDs
        // This still works but uses the new implementation under the hood
        let conversation = try await client.startNewConversation()
        let response = try await client.sendMessage(conversationId: conversation.id, message: "Hello, Grok!")
        
        print("Legacy API Response: \(response.message)")
    } catch {
        print("Error: \(error)")
    }
}

/// Advanced usage example showing how to handle multiple messages in a conversation
public func grokClientAdvancedExample() async {
    let cookies = [
        "x-anonuserid": "your_anon_user_id",
        "x-challenge": "your_challenge_value",
        "x-signature": "your_signature_value"
    ]
    
    do {
        let client = try GrokClient(cookies: cookies)
        
        // Send multiple messages with different settings
        let messages = [
            (message: "What can you tell me about Swift programming?", reasoning: false, deepSearch: false),
            (message: "How do async/await features work?", reasoning: true, deepSearch: false),
            (message: "What are the latest developments in Swift concurrency?", reasoning: false, deepSearch: true)
        ]
        
        for (index, messageData) in messages.enumerated() {
            print("\n[\(index + 1)/\(messages.count)] Sending: \(messageData.message)")
            print("Settings: Reasoning=\(messageData.reasoning), DeepSearch=\(messageData.deepSearch)")
            
            let response = try await client.sendMessage(
                message: messageData.message,
                enableReasoning: messageData.reasoning,
                enableDeepSearch: messageData.deepSearch
            )
            
            print("\nResponse: \(response)")
            
            // Add a small delay between messages to avoid rate limiting
            if index < messages.count - 1 {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
        
    } catch {
        print("Error: \(error)")
    }
} 