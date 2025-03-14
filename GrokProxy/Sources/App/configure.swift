import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Configure middleware
    app.middleware.use(CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .OPTIONS],
        allowedHeaders: [
            .accept, .authorization, .contentType, .origin, .xRequestedWith,
            .userAgent, .accessControlAllowOrigin
        ]
    )))
    
    // Uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Configure custom JSON encoder for compatibility with OpenAI format
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    
    // Register routes
    try routes(app)
}
