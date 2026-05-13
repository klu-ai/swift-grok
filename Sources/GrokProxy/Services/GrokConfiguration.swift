import Vapor
@preconcurrency import GrokClient

enum GrokConfigurationError: Error {
    case missingCredentials
    case invalidCredentialsFile
    case fileReadError
}

struct GrokConfiguration {
    let grokClient: GrokClient
    let audioTranscriber: GrokAudioTranscriber
    
    init(from environment: Environment) throws {
        // Try to load credentials from environment variables first
        if let cookiesJson = Environment.get("GROK_COOKIES"),
           let cookiesData = cookiesJson.data(using: .utf8),
           let cookies = try? JSONSerialization.jsonObject(with: cookiesData) as? [String: String],
           !cookies.isEmpty {
            // Create the GrokClient with cookies from environment
            let client = try GrokClient(cookies: cookies)
            self.grokClient = client
            self.audioTranscriber = GrokAudioTranscriber(grokClient: client)
            return
        }
        
        // If no environment variables, try to load from a credentials file
        let credentialsPath = "credentials.json"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: credentialsPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: credentialsPath))
                if let cookies = try JSONSerialization.jsonObject(with: data) as? [String: String], !cookies.isEmpty {
                    let client = try GrokClient(cookies: cookies)
                    self.grokClient = client
                    self.audioTranscriber = GrokAudioTranscriber(grokClient: client)
                    return
                } else {
                    throw GrokConfigurationError.invalidCredentialsFile
                }
            } catch {
                throw GrokConfigurationError.fileReadError
            }

        }
        
        // Fallback to mock cookies (this will likely not work with the actual Grok API)
        let mockCookies = [
            "x-anonuserid": "mock-user-id",
            "x-challenge": "mock-challenge",
            "x-signature": "mock-signature",
            "sso": "mock-sso",
            "sso-rw": "mock-sso-rw"
        ]
        
        // This will likely fail in a real environment, but allows for compilation
        let client = try GrokClient(cookies: mockCookies, isDebug: true)
        self.grokClient = client
        self.audioTranscriber = GrokAudioTranscriber(grokClient: client)
    }
    
    static func register(_ app: Application) throws {
        let config = try GrokConfiguration(from: app.environment)
        
        // Register the chat completions controller
        try app.register(collection: ChatCompletionsController(grokClient: config.grokClient))
        try app.register(collection: AudioTranscriptionsController { [audioTranscriber = config.audioTranscriber] request in
            try await audioTranscriber.transcribe(request)
        })
    }
}

final class GrokAudioTranscriber: @unchecked Sendable {
    private let grokClient: GrokClient

    init(grokClient: GrokClient) {
        self.grokClient = grokClient
    }

    func transcribe(_ request: AudioTranscriptionRequest) async throws -> String {
        guard let audioFormat = request.audioFormat?.trimmingCharacters(in: .whitespacesAndNewlines),
              !audioFormat.isEmpty else {
            throw Abort(.badRequest, reason: "audio_format is required when the audio format cannot be inferred")
        }

        do {
            let response = try await grokClient.speechToText(
                audioBase64: request.audioBase64,
                audioFormat: audioFormat,
                refinementLevel: request.refinementLevel ?? GrokClient.defaultSpeechRefinementLevel
            )
            return response.text
        } catch let abort as AbortError {
            throw abort
        } catch {
            throw Abort(.badGateway, reason: error.localizedDescription)
        }
    }
}
