import Foundation
import Vapor

// MARK: - Request Models

struct ChatCompletionRequest: Content {
    let model: String
    let messages: [Message]
    let temperature: Double?
    let max_tokens: Int?
    let top_p: Double?
    let frequency_penalty: Double?
    let presence_penalty: Double?
    let stream: Bool?
    
    struct Message: Content {
        let role: String
        let content: String
        
        static func isValidRole(_ role: String) -> Bool {
            return ["system", "user", "assistant"].contains(role)
        }
    }
}

// MARK: - Response Models

struct ChatCompletionResponse: Content {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage
    
    struct Choice: Content {
        let index: Int
        let message: ChatCompletionRequest.Message
        let finish_reason: String
    }
    
    struct Usage: Content {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
    
    static func create(
        id: String = UUID().uuidString,
        model: String,
        message: String,
        finishReason: String = "stop"
    ) -> ChatCompletionResponse {
        let timestamp = Int(Date().timeIntervalSince1970)
        return ChatCompletionResponse(
            id: id,
            object: "chat.completion",
            created: timestamp,
            model: model,
            choices: [
                Choice(
                    index: 0,
                    message: ChatCompletionRequest.Message(role: "assistant", content: message),
                    finish_reason: finishReason
                )
            ],
            usage: Usage(
                prompt_tokens: 0,
                completion_tokens: 0,
                total_tokens: 0
            )
        )
    }
} 