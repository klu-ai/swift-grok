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
                let response = try await grokClient.sendMessage(
                    message: lastUserMessage,
                    enableReasoning: enableReasoning,
                    customInstructions: systemMessage ?? "",
                    temporary: true // Don't save in Grok's history
                )
                
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
        // For now, we'll simulate streaming by chunking the complete response
        let response = try await grokClient.sendMessage(
            message: userMessage,
            enableReasoning: enableReasoning,
            customInstructions: customInstructions,
            temporary: true
        )
        
        // Generate a response ID for the entire stream
        let responseId = UUID().uuidString
        
        // Split the message into chunks (for demonstration)
        // In a real implementation, this would come from Grok's streaming API
        let chunkSize = 10
        var chunks = [String]()
        let message = response.message
        
        // Chunk the message into pieces
        for i in stride(from: 0, to: message.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, message.count)
            let startIndex = message.index(message.startIndex, offsetBy: i)
            let endStringIndex = message.index(message.startIndex, offsetBy: endIndex)
            chunks.append(String(message[startIndex..<endStringIndex]))
        }
        
        // Set up the stream response
        let streamResponse = Vapor.Response(status: .ok)
        streamResponse.headers.contentType = HTTPMediaType(type: "text", subType: "event-stream")
        
        // Create a body stream according to Vapor docs
        streamResponse.body = .init(stream: { writer in
            // First chunk with role
            let firstChunk = ChatCompletionChunkResponse.create(
                id: responseId,
                model: model,
                chunk: chunks.first ?? "",
                includeRole: true
            )
            let firstChunkData = try! JSONEncoder().encode(firstChunk)
            let firstChunkString = "data: \(String(data: firstChunkData, encoding: .utf8)!)\n\n"
            
            // Write the first chunk immediately
            _ = writer.write(.buffer(ByteBuffer(string: firstChunkString)))
            
            // Send remaining chunks with delays
            for (index, chunk) in chunks.dropFirst().enumerated() {
                // Schedule the delayed write with explicit Int64 conversion
                _ = writer.eventLoop.scheduleTask(in: .milliseconds(Int64(100 * (index + 1)))) {
                    let chunkResponse = ChatCompletionChunkResponse.create(
                        id: responseId,
                        model: model,
                        chunk: chunk
                    )
                    let chunkData = try! JSONEncoder().encode(chunkResponse)
                    let chunkString = "data: \(String(data: chunkData, encoding: .utf8)!)\n\n"
                    
                    _ = writer.write(.buffer(ByteBuffer(string: chunkString)))
                }
            }
            
            // Schedule the final "done" chunk with explicit Int64 conversion
            let finalDelay = Int64(chunks.count * 100)
            
            _ = writer.eventLoop.scheduleTask(in: .milliseconds(finalDelay)) {
                // Send the final chunk
                let doneChunk = ChatCompletionChunkResponse.createDoneChunk(
                    id: responseId,
                    model: model
                )
                let doneData = try! JSONEncoder().encode(doneChunk)
                let doneString = "data: \(String(data: doneData, encoding: .utf8)!)\n\n"
                
                _ = writer.write(.buffer(ByteBuffer(string: doneString)))
                
                // Send [DONE] marker
                _ = writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
                
                // End the stream
                _ = writer.write(.end)
            }
            
            // The stream closure doesn't need to return anything
            // The EventLoopFuture-based streaming is handled by the writer
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