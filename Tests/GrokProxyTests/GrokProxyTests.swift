@testable import GrokProxy
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
        try await withApp { app in
            let expectedIds = ModelsResponse.defaultResponse().data.map(\.id)

            try await app.testing().test(.GET, "v1/models", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(ModelsResponse.self, res) { models in
                    #expect(models.object == "list")
                    #expect(models.data.map(\.id) == expectedIds)
                    #expect(models.data.allSatisfy { $0.object == "model" })
                    #expect(models.data.allSatisfy { $0.owned_by == "grok" })
                }
            })

            try await app.testing().test(.GET, "models", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(ModelsResponse.self, res) { models in
                    #expect(models.object == "list")
                    #expect(models.data.map(\.id) == expectedIds)
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
}
