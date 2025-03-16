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

// Streaming chunk response format
struct ChatCompletionChunkResponse: Content {
    let id: String
    let object: String
    let created: Int
    let model: String
    let system_fingerprint: String
    let choices: [Choice]
    
    struct Choice: Content {
        let index: Int
        let delta: Delta
        let logprobs: String?
        let finish_reason: String?
        
        struct Delta: Content {
            let role: String?
            let content: String?
        }
    }
    
    static func create(
        id: String = UUID().uuidString,
        model: String,
        chunk: String,
        finishReason: String? = nil,
        includeRole: Bool = false
    ) -> ChatCompletionChunkResponse {
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // For the first chunk, include the role
        let role = includeRole ? "assistant" : nil
        
        return ChatCompletionChunkResponse(
            id: id,
            object: "chat.completion.chunk",
            created: timestamp,
            model: model,
            system_fingerprint: "fp_\(String(UUID().uuidString.prefix(12)))",
            choices: [
                Choice(
                    index: 0,
                    delta: Choice.Delta(
                        role: role,
                        content: chunk
                    ),
                    logprobs: nil,
                    finish_reason: finishReason
                )
            ]
        )
    }
    
    // Create a special "done" chunk that signals the end of the stream
    static func createDoneChunk(
        id: String = UUID().uuidString,
        model: String
    ) -> ChatCompletionChunkResponse {
        let timestamp = Int(Date().timeIntervalSince1970)
        return ChatCompletionChunkResponse(
            id: id,
            object: "chat.completion.chunk",
            created: timestamp,
            model: model,
            system_fingerprint: "fp_\(String(UUID().uuidString.prefix(12)))",
            choices: [
                Choice(
                    index: 0,
                    delta: Choice.Delta(
                        role: nil,
                        content: nil
                    ),
                    logprobs: nil,
                    finish_reason: "stop"
                )
            ]
        )
    }
}

struct ChatCompletionResponse: Content {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage
    let service_tier: String
    
    struct Choice: Content {
        let index: Int
        let message: Message
        let logprobs: String?
        let finish_reason: String
        
        struct Message: Content {
            let role: String
            let content: String
            let refusal: String?
            let annotations: [String]
        }
    }
    
    struct Usage: Content {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
        let prompt_tokens_details: TokenDetails
        let completion_tokens_details: CompletionTokenDetails
        
        struct TokenDetails: Content {
            let cached_tokens: Int
            let audio_tokens: Int
        }
        
        struct CompletionTokenDetails: Content {
            let reasoning_tokens: Int
            let audio_tokens: Int
            let accepted_prediction_tokens: Int
            let rejected_prediction_tokens: Int
        }
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
                    message: Choice.Message(
                        role: "assistant", 
                        content: message,
                        refusal: nil,
                        annotations: []
                    ),
                    logprobs: nil,
                    finish_reason: finishReason
                )
            ],
            usage: Usage(
                prompt_tokens: 0,
                completion_tokens: 0,
                total_tokens: 0,
                prompt_tokens_details: Usage.TokenDetails(
                    cached_tokens: 0,
                    audio_tokens: 0
                ),
                completion_tokens_details: Usage.CompletionTokenDetails(
                    reasoning_tokens: 0,
                    audio_tokens: 0,
                    accepted_prediction_tokens: 0,
                    rejected_prediction_tokens: 0
                )
            ),
            service_tier: "default"
        )
    }
}

// MARK: - Models Response

struct ModelsResponse: Content {
    let object: String
    let data: [Model]
    
    struct Model: Content {
        let id: String
        let object: String
        let created: Int
        let owned_by: String
        
        init(id: String, owned_by: String = "grok") {
            self.id = id
            self.object = "model"
            self.created = Int(Date().timeIntervalSince1970) - 86400 // Yesterday
            self.owned_by = owned_by
        }
    }
    
    static func defaultResponse() -> ModelsResponse {
        let grokModels = [
            Model(id: "gpt-3.5-turbo"), // Standard model name used by OpenAI clients
            Model(id: "gpt-4"),         // More advanced model name used by OpenAI clients 
            Model(id: "grok-3")         // Actual Grok model name
        ]
        
        return ModelsResponse(
            object: "list",
            data: grokModels
        )
    }
} 