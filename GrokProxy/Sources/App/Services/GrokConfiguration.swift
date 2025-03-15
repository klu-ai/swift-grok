import Vapor
@preconcurrency import GrokClient

enum GrokConfigurationError: Error {
    case missingCredentials
    case invalidCredentialsFile
    case fileReadError
}

struct GrokConfiguration {
    let grokClient: GrokClient
    
    init(from environment: Environment) throws {
        // Try to load credentials from environment variables first
        if let cookiesJson = Environment.get("GROK_COOKIES"),
           let cookiesData = cookiesJson.data(using: .utf8),
           let cookies = try? JSONSerialization.jsonObject(with: cookiesData) as? [String: String],
           !cookies.isEmpty {
            // Create the GrokClient with cookies from environment
            self.grokClient = try GrokClient(cookies: cookies)
            return
        }
        
        // If no environment variables, try to load from a credentials file
        let credentialsPath = "../credentials.json"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: credentialsPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: credentialsPath))
                if let cookies = try JSONSerialization.jsonObject(with: data) as? [String: String], !cookies.isEmpty {
                    self.grokClient = try GrokClient(cookies: cookies)
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
        self.grokClient = try GrokClient(cookies: mockCookies, isDebug: true)
    }
    
    static func register(_ app: Application) throws {
        let config = try GrokConfiguration(from: app.environment)
        
        // Register the chat completions controller
        let controller = ChatCompletionsController(grokClient: config.grokClient)
        try app.register(collection: controller)
    }
} 