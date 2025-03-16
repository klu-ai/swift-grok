import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Register app configuration (must be before other middleware)
    try AppConfiguration.register(app)
    
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
    
    // Configure content size limits
    app.routes.defaultMaxBodySize = "10mb" // Or higher as needed
    // Or if using NIO directly:
    //app.http.server.configuration.maxBodySize = 10 * 1024 * 1024 // 10MB
    
    // Register routes
    try routes(app)
    
    // Register Grok configuration
    try GrokConfiguration.register(app)
}
