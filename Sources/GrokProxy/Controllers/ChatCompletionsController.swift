import Vapor
import Logging
@preconcurrency import GrokClient

// We're removing the Sendable conformance since GrokClient isn't Sendable
struct ChatCompletionsController: RouteCollection {
    private static let logger = Logger(label: "ChatCompletionsController")
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
        
        // OpenAI compatibility endpoint for models
        v1.get("models") { req in
            return ModelsResponse.defaultResponse()
        }
        
        // Alternative endpoint without the v1 prefix
        routes.get("models") { req in
            return ModelsResponse.defaultResponse()
        }
    }
    
    // Using a separate function that takes grokClient as a parameter to avoid 
    // capturing self in an @Sendable context
    @Sendable
    private func chatCompletions(req: Request, grokClient: GrokClient) async throws -> Vapor.Response {
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
        
        // Check if streaming is requested
        let isStreaming = chatRequest.stream ?? false
        
        // 4. Send request to Grok
        do {
            // Use parameters from the request
            let temperature = chatRequest.temperature
            let enableReasoning = temperature.map { $0 < 0.5 } ?? false
            
            // If streaming is requested, handle it differently
            if isStreaming {

                Self.logger.info("Streaming request received")
                
                return try await handleStreamingResponse(
                    req: req,
                    grokClient: grokClient,
                    model: chatRequest.model,
                    userMessage: lastUserMessage,
                    enableReasoning: enableReasoning,
                    customInstructions: systemMessage ?? ""
                )
            } else {
                // Non-streaming response
                Self.logger.info("Non-streaming request received")
                let response = try await grokClient.sendMessage(
                    message: lastUserMessage,
                    enableReasoning: enableReasoning,
                    customInstructions: systemMessage ?? "",
                    temporary: true // Don't save in Grok's history
                )
                
                Self.logger.info("result from grok: \(response.message)")
                
                
                // 5. Format the response to match OpenAI's format
                let responseData = ChatCompletionResponse.create(
                    model: chatRequest.model,
                    message: response.message
                )
                
                // Create a proper response with the correct body initialization
                let jsonData = try JSONEncoder().encode(responseData)
                let httpResponse = Vapor.Response(status: .ok)
                httpResponse.headers.contentType = .json
                httpResponse.body = .init(data: jsonData)
                return httpResponse
            }
        } catch {
            throw Abort(.internalServerError, reason: "Failed to communicate with Grok: \(error.localizedDescription)")
        }
    }
    
    /// Handle streaming response by setting up a StreamingResponse
    private func handleStreamingResponse(
        req: Request,
        grokClient: GrokClient,
        model: String,
        userMessage: String,
        enableReasoning: Bool,
        customInstructions: String
    ) async throws -> Vapor.Response {
        let stream = try await grokClient.streamMessage(
            message: userMessage,
            enableReasoning: enableReasoning,
            customInstructions: customInstructions,
            temporary: true
        )
        
        let responseId = UUID().uuidString
        let streamResponse = Vapor.Response(status: .ok)
        streamResponse.headers.contentType = HTTPMediaType(type: "text", subType: "event-stream")
        
        streamResponse.body = .init(stream: { writer in
            Task {
                do {
                    var isFirstChunk = true
                    for try await response in stream {
                        let chunkResponse: ChatCompletionChunkResponse
                        if response.webSearchResults != nil || response.xposts != nil {
                            // Final response
                            chunkResponse = ChatCompletionChunkResponse.create(
                                id: responseId,
                                model: model,
                                chunk: response.message,
                                finishReason: "stop"
                            )
                        } else {
                            // Streaming token
                            chunkResponse = ChatCompletionChunkResponse.create(
                                id: responseId,
                                model: model,
                                chunk: response.message,
                                includeRole: isFirstChunk
                            )
                            isFirstChunk = false
                        }
                        
                        let chunkData = try JSONEncoder().encode(chunkResponse)
                        let chunkString = "data: \(String(data: chunkData, encoding: .utf8)!)\n\n"
                        _ = writer.write(.buffer(ByteBuffer(string: chunkString)))
                    }
                    
                    // Send [DONE] marker
                    _ = writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
                    _ = writer.write(.end)
                } catch {
                    let errorString = "data: {\"error\": \"\(error.localizedDescription)\"}\n\n"
                    _ = writer.write(.buffer(ByteBuffer(string: errorString)))
                    _ = writer.write(.end)
                }
            }
        })
        
        return streamResponse
    }
    
    /// Extract system message from the list of messages
    /// - Parameter messages: Array of OpenAI messages
    /// - Returns: The content of the system message, if any
    private func extractSystemMessage(from messages: [ChatCompletionRequest.Message]) -> String? {
        return messages.first(where: { $0.role == "system" })?.content
    }
} 
