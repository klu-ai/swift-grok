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
    app.routes.defaultMaxBodySize = configuredMaxBodySize()
    
    // Register routes
    try routes(app)
    
    // Register Grok configuration
    try GrokConfiguration.register(app)
}

private func configuredMaxBodySize() -> ByteCount {
    guard let value = Environment.get("GROK_PROXY_MAX_BODY_SIZE"),
          let byteCount = parseByteCount(value) else {
        return ByteCount(value: 50 * 1024 * 1024)
    }

    return byteCount
}

private func parseByteCount(_ rawValue: String) -> ByteCount? {
    let value = rawValue
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " ", with: "")

    let suffixes: [(String, Int)] = [
        ("kb", 1024),
        ("mb", 1024 * 1024),
        ("gb", 1024 * 1024 * 1024),
        ("b", 1)
    ]

    for (suffix, multiplier) in suffixes where value.hasSuffix(suffix) {
        let numberPart = value.dropLast(suffix.count)
        guard let amount = Int(numberPart), amount >= 0 else {
            return nil
        }

        return ByteCount(value: amount * multiplier)
    }

    guard let bytes = Int(value), bytes >= 0 else {
        return nil
    }

    return ByteCount(value: bytes)
}
