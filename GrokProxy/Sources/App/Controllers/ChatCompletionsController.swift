import Vapor
@preconcurrency import GrokClient

// We're removing the Sendable conformance since GrokClient isn't Sendable
struct ChatCompletionsController: RouteCollection {
    private let grokClient: GrokClient
    
    init(grokClient: GrokClient) {
        self.grokClient = grokClient
    }
    
    func boot(routes: RoutesBuilder) throws {
        let v1 = routes.grouped("v1")
        
        // OpenAI compatibility endpoint for chat completions
        // Using a capturing closure here to avoid Sendable warning
        v1.post("chat", "completions") { [grokClient] req in
            try await self.chatCompletions(req: req, grokClient: grokClient)
        }
    }
    
    // Using a separate function that takes grokClient as a parameter to avoid 
    // capturing self in an @Sendable context
    @Sendable
    private func chatCompletions(req: Request, grokClient: GrokClient) async throws -> ChatCompletionResponse {
        // 1. Decode the incoming request
        let chatRequest = try req.content.decode(ChatCompletionRequest.self)
        
        // 2. Validate the request
        guard !chatRequest.messages.isEmpty else {
            throw Abort(.badRequest, reason: "Messages array must not be empty")
        }
        
        for message in chatRequest.messages {
            guard ChatCompletionRequest.Message.isValidRole(message.role) else {
                throw Abort(.badRequest, reason: "Invalid role: \(message.role)")
            }
        }
        
        // 3. Format the message for Grok
        let systemMessage = extractSystemMessage(from: chatRequest.messages)
        let userMessages = chatRequest.messages.filter { $0.role != "system" }
        let lastUserMessage = userMessages.last(where: { $0.role == "user" })?.content ?? ""
        
        if lastUserMessage.isEmpty {
            throw Abort(.badRequest, reason: "At least one user message is required")
        }
        
        // 4. Send request to Grok
        do {
            // Use parameters from the request
            let temperature = chatRequest.temperature
            let enableReasoning = temperature.map { $0 < 0.5 } ?? false
            
            let response = try await grokClient.sendMessage(
                message: lastUserMessage,
                enableReasoning: enableReasoning,
                customInstructions: systemMessage ?? "",
                temporary: true // Don't save in Grok's history
            )
            
            // 5. Format the response to match OpenAI's format
            return ChatCompletionResponse.create(
                model: chatRequest.model,
                message: response.message
            )
        } catch {
            throw Abort(.internalServerError, reason: "Failed to communicate with Grok: \(error.localizedDescription)")
        }
    }
    
    /// Extract system message from the list of messages
    /// - Parameter messages: Array of OpenAI messages
    /// - Returns: The content of the system message, if any
    private func extractSystemMessage(from messages: [ChatCompletionRequest.Message]) -> String? {
        return messages.first(where: { $0.role == "system" })?.content
    }
} 