@testable import GrokProxy
@testable import GrokClient
import Foundation
import NIOCore
import VaporTesting
import Testing

@Suite("App Tests")
struct AppTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await test(app)
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func withAudioApp(
        transcribe: @escaping AudioTranscriptionHandler,
        _ test: (Application) async throws -> ()
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try app.register(collection: AudioTranscriptionsController(transcribe: transcribe))
            try await test(app)
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func withModelsApp(
        modes: [GrokMode],
        _ test: (Application) async throws -> ()
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            let client = try GrokClient(cookies: ["sso": "test-cookie"])
            try app.register(collection: ChatCompletionsController(
                grokClient: client,
                modeCatalog: { _ in modes }
            ))
            try await test(app)
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    @Test("Test Hello World Route")
    func helloWorld() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "hello", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "Hello, world!")
            })
        }
    }

    @Test("Models endpoints return known Grok modes")
    func modelsEndpoints() async throws {
        let modes = [
            GrokMode(id: "fast", displayName: "Fast", summary: "Quick responses"),
            GrokMode(
                id: "heavy",
                displayName: "Heavy",
                summary: "Team of Experts",
                isAvailable: false,
                minimumSubscriptionTier: "TIER_SUPERGROK_HEAVY"
            )
        ]

        try await withModelsApp(modes: modes) { app in
            try await app.testing().test(.GET, "v1/models", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(ModelsResponse.self, res) { models in
                    #expect(models.object == "list")
                    #expect(models.data.map(\.id) == ["fast", "heavy"])
                    #expect(models.data.allSatisfy { $0.object == "model" })
                    #expect(models.data.allSatisfy { $0.owned_by == "grok" })
                    #expect(models.data[0].available == true)
                    #expect(models.data[0].disabled == false)
                    #expect(models.data[1].available == false)
                    #expect(models.data[1].disabled == true)
                    #expect(models.data[1].minimum_subscription_tier == "TIER_SUPERGROK_HEAVY")
                }
            })

            try await app.testing().test(.GET, "models", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(ModelsResponse.self, res) { models in
                    #expect(models.object == "list")
                    #expect(models.data.map(\.id) == ["fast", "heavy"])
                }
            })
        }
    }

    @Test("Chat completion validation fails before calling Grok")
    func chatCompletionValidation() async throws {
        try await withApp { app in
            try await app.testing().test(.POST, "v1/chat/completions") { req async throws in
                try req.content.encode(ChatCompletionRequest(
                    model: "fast",
                    messages: [],
                    temperature: nil,
                    max_tokens: nil,
                    top_p: nil,
                    frequency_penalty: nil,
                    presence_penalty: nil,
                    stream: nil
                ))
            } afterResponse: { res async in
                #expect(res.status == .badRequest)
                expectContains(res.body.string, "Messages array must not be empty")
            }

            try await app.testing().test(.POST, "v1/chat/completions") { req async throws in
                try req.content.encode(ChatCompletionRequest(
                    model: "fast",
                    messages: [.init(role: "tool", content: "bad role")],
                    temperature: nil,
                    max_tokens: nil,
                    top_p: nil,
                    frequency_penalty: nil,
                    presence_penalty: nil,
                    stream: nil
                ))
            } afterResponse: { res async in
                #expect(res.status == .badRequest)
                expectContains(res.body.string, "Invalid role: tool")
            }

            try await app.testing().test(.POST, "v1/chat/completions") { req async throws in
                try req.content.encode(ChatCompletionRequest(
                    model: "fast",
                    messages: [.init(role: "system", content: "Be concise")],
                    temperature: nil,
                    max_tokens: nil,
                    top_p: nil,
                    frequency_penalty: nil,
                    presence_penalty: nil,
                    stream: nil
                ))
            } afterResponse: { res async in
                #expect(res.status == .badRequest)
                expectContains(res.body.string, "At least one user message is required")
            }
        }
    }

    @Test("Streaming final chunk uses explicit final response")
    func streamingFinalChunkUsesExplicitFinalResponse() throws {
        var isFirstChunk = true
        var emittedContent = false
        let responseId = "chatcmpl-test"
        let sourceBackedToken = ConversationResponse(
            message: "Here is a source-backed token.",
            conversationId: "conversation-test",
            responseId: "grok-response-test",
            webSearchResults: [
                WebSearchResult(
                    url: "https://example.com",
                    title: "Example",
                    preview: "Example preview"
                )
            ],
            isFinal: false
        )

        let sourceChunks = ChatCompletionsController.streamingChunks(
            for: sourceBackedToken,
            model: "fast",
            responseId: responseId,
            isFirstChunk: &isFirstChunk,
            emittedContent: &emittedContent
        )

        #expect(sourceChunks.count == 1)
        #expect(sourceChunks[0].choices[0].delta.role == "assistant")
        #expect(sourceChunks[0].choices[0].delta.content == "Here is a source-backed token.")
        #expect(sourceChunks[0].choices[0].finish_reason == nil)

        let finalResponse = ConversationResponse(
            message: "Here is the complete answer.",
            conversationId: "conversation-test",
            responseId: "grok-response-test",
            isFinal: true
        )

        let finalChunks = ChatCompletionsController.streamingChunks(
            for: finalResponse,
            model: "fast",
            responseId: responseId,
            isFirstChunk: &isFirstChunk,
            emittedContent: &emittedContent
        )

        #expect(finalChunks.count == 1)
        #expect(finalChunks[0].choices[0].delta.role == nil)
        #expect(finalChunks[0].choices[0].delta.content == nil)
        #expect(finalChunks[0].choices[0].finish_reason == "stop")
        #expect(ChatCompletionsController.doneServerSentEvent == "data: [DONE]\n\n")
    }

    @Test("Streaming final response emits content when no token was sent")
    func streamingFinalResponseEmitsContentWhenNoTokenWasSent() throws {
        var isFirstChunk = true
        var emittedContent = false
        let finalResponse = ConversationResponse(
            message: "Only final content.",
            conversationId: "conversation-test",
            responseId: "grok-response-test",
            isFinal: true
        )

        let finalChunks = ChatCompletionsController.streamingChunks(
            for: finalResponse,
            model: "fast",
            responseId: "chatcmpl-test",
            isFirstChunk: &isFirstChunk,
            emittedContent: &emittedContent
        )

        #expect(finalChunks.count == 2)
        #expect(finalChunks[0].choices[0].delta.role == "assistant")
        #expect(finalChunks[0].choices[0].delta.content == "Only final content.")
        #expect(finalChunks[0].choices[0].finish_reason == nil)
        #expect(finalChunks[1].choices[0].delta.content == nil)
        #expect(finalChunks[1].choices[0].finish_reason == "stop")
    }

    @Test("Streaming ignores thinking chunks without consuming assistant role")
    func streamingIgnoresThinkingChunksWithoutConsumingAssistantRole() throws {
        var isFirstChunk = true
        var emittedContent = false
        let thinkingResponse = ConversationResponse(
            message: "Thinking through the answer.",
            conversationId: "conversation-test",
            responseId: "grok-response-test",
            isThinking: true
        )

        let thinkingChunks = ChatCompletionsController.streamingChunks(
            for: thinkingResponse,
            model: "fast",
            responseId: "chatcmpl-test",
            isFirstChunk: &isFirstChunk,
            emittedContent: &emittedContent
        )

        #expect(thinkingChunks.isEmpty)
        #expect(isFirstChunk == true)
        #expect(emittedContent == false)

        let answerResponse = ConversationResponse(
            message: "Visible answer.",
            conversationId: "conversation-test",
            responseId: "grok-response-test"
        )

        let answerChunks = ChatCompletionsController.streamingChunks(
            for: answerResponse,
            model: "fast",
            responseId: "chatcmpl-test",
            isFirstChunk: &isFirstChunk,
            emittedContent: &emittedContent
        )

        #expect(answerChunks.count == 1)
        #expect(answerChunks[0].choices[0].delta.role == "assistant")
        #expect(answerChunks[0].choices[0].delta.content == "Visible answer.")
        #expect(answerChunks[0].choices[0].finish_reason == nil)
        #expect(isFirstChunk == false)
        #expect(emittedContent == true)
    }

    @Test("Streaming terminal events synthesize stop chunk before done marker")
    func streamingTerminalEventsSynthesizeStopChunkBeforeDoneMarker() throws {
        let events = try ChatCompletionsController.terminalServerSentEvents(
            emittedFinalChunk: false,
            model: "fast",
            responseId: "chatcmpl-test"
        )

        #expect(events.count == 2)
        let stopChunk = try decodeChunk(from: events[0])
        #expect(stopChunk.choices[0].delta.content == nil)
        #expect(stopChunk.choices[0].finish_reason == "stop")
        #expect(events[1] == ChatCompletionsController.doneServerSentEvent)

        let finalAlreadyEmittedEvents = try ChatCompletionsController.terminalServerSentEvents(
            emittedFinalChunk: true,
            model: "fast",
            responseId: "chatcmpl-test"
        )

        #expect(finalAlreadyEmittedEvents == [ChatCompletionsController.doneServerSentEvent])
    }

    @Test("Audio transcription validation fails before calling Grok")
    func audioTranscriptionValidation() async throws {
        try await withApp { app in
            try await app.testing().test(.POST, "v1/audio/transcriptions") { req async throws in
                try req.content.encode(AudioTranscriptionJSONRequest(
                    model: "grok-2-voice",
                    file: nil,
                    audioBase64: nil,
                    audio_base64: nil,
                    content: nil,
                    data: nil,
                    response_format: nil,
                    audioFormat: nil,
                    audio_format: nil,
                    refinementLevel: nil,
                    refinement_level: nil,
                    language: nil,
                    prompt: nil
                ))
            } afterResponse: { res async in
                #expect(res.status == .badRequest)
                expectContains(res.body.string, "JSON transcription requests require file, audioBase64, content, or data")
            }

            try await app.testing().test(.POST, "v1/audio/transcriptions") { req async throws in
                try req.content.encode(AudioTranscriptionJSONRequest(
                    model: "grok-2-voice",
                    file: nil,
                    audioBase64: "UklGRg==",
                    audio_base64: nil,
                    content: nil,
                    data: nil,
                    response_format: "srt",
                    audioFormat: nil,
                    audio_format: "wav",
                    refinementLevel: nil,
                    refinement_level: nil,
                    language: nil,
                    prompt: nil
                ))
            } afterResponse: { res async in
                #expect(res.status == .badRequest)
                expectContains(res.body.string, "Unsupported response_format: srt")
            }

            try await app.testing().test(.POST, "v1/audio/transcriptions") { req async throws in
                try req.content.encode(AudioTranscriptionJSONRequest(
                    model: "grok-2-voice",
                    file: nil,
                    audioBase64: "not raw base64",
                    audio_base64: nil,
                    content: nil,
                    data: nil,
                    response_format: nil,
                    audioFormat: nil,
                    audio_format: "webm",
                    refinementLevel: nil,
                    refinement_level: nil,
                    language: nil,
                    prompt: nil
                ))
            } afterResponse: { res async in
                #expect(res.status == .badRequest)
                expectContains(res.body.string, "raw base64")
            }
        }
    }

    @Test("Audio transcription response formats")
    func audioTranscriptionResponseFormats() async throws {
        try await withAudioApp(transcribe: { request in
            #expect(request.model == "grok-2-voice")
            #expect(request.audioBase64 == "UklGRg==")
            #expect(request.audioFormat == "wav")
            #expect(request.language == "en")
            #expect(request.prompt == "short clip")
            return "hello audio"
        }) { app in
            try await app.testing().test(.POST, "v1/audio/transcriptions") { req async throws in
                try req.content.encode(AudioTranscriptionJSONRequest(
                    model: "grok-2-voice",
                    file: nil,
                    audioBase64: "UklGRg==",
                    audio_base64: nil,
                    content: nil,
                    data: nil,
                    response_format: nil,
                    audioFormat: nil,
                    audio_format: "wav",
                    refinementLevel: nil,
                    refinement_level: nil,
                    language: "en",
                    prompt: "short clip"
                ))
            } afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(AudioTranscriptionResponse.self, res) { body in
                    #expect(body.text == "hello audio")
                }
            }

            try await app.testing().test(.POST, "v1/audio/transcriptions") { req async throws in
                try req.content.encode(AudioTranscriptionJSONRequest(
                    model: "grok-2-voice",
                    file: nil,
                    audioBase64: "UklGRg==",
                    audio_base64: nil,
                    content: nil,
                    data: nil,
                    response_format: "text",
                    audioFormat: nil,
                    audio_format: "wav",
                    refinementLevel: nil,
                    refinement_level: nil,
                    language: "en",
                    prompt: "short clip"
                ))
            } afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == .plainText)
                #expect(res.body.string == "hello audio")
            }
        }
    }

    @Test("Audio transcription multipart request converts file to base64")
    func audioTranscriptionMultipartRequest() async throws {
        let audioBytes = Data("webm bytes".utf8)
        try await withAudioApp(transcribe: { request in
            #expect(request.model == "grok-2-voice")
            #expect(request.audioBase64 == audioBytes.base64EncodedString())
            #expect(request.audioFormat == "webm")
            return "multipart transcript"
        }) { app in
            let boundary = "Boundary-\(UUID().uuidString)"
            let body = """
            --\(boundary)\r
            Content-Disposition: form-data; name="model"\r
            \r
            grok-2-voice\r
            --\(boundary)\r
            Content-Disposition: form-data; name="response_format"\r
            \r
            json\r
            --\(boundary)\r
            Content-Disposition: form-data; name="file"; filename="clip.webm"\r
            Content-Type: audio/webm\r
            \r
            webm bytes\r
            --\(boundary)--\r

            """

            try await app.testing().test(.POST, "v1/audio/transcriptions") { req async throws in
                req.headers.replaceOrAdd(name: .contentType, value: "multipart/form-data; boundary=\(boundary)")
                req.body = ByteBuffer(data: Data(body.utf8))
            } afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(AudioTranscriptionResponse.self, res) { body in
                    #expect(body.text == "multipart transcript")
                }
            }
        }
    }

    private func decodeChunk(from event: String) throws -> ChatCompletionChunkResponse {
        let prefix = "data: "
        #expect(event.hasPrefix(prefix))
        let json = String(event.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return try JSONDecoder().decode(ChatCompletionChunkResponse.self, from: Data(json.utf8))
    }
}
