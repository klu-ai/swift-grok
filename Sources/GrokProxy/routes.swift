import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        "GrokProxy: OpenAI-compatible proxy for Grok"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }
    
    // Register the Grok routes
    try GrokConfiguration.register(app)
}
