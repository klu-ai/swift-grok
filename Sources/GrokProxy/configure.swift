import Vapor
import GrokClient

// configures your application
public func configure(_ app: Application) async throws {
    // Check for credentials file early in the setup process
    try ensureCredentialsExist(app.environment)
    
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

// Helper function to ensure credentials exist before starting the application
private func ensureCredentialsExist(_ environment: Environment) throws {
    // Check for GROK_COOKIES environment variable
    if let _ = Environment.get("GROK_COOKIES") {
        // Credentials exist in environment, no need to check file
        return
    }
    
    // Check for credentials.json file
    let credentialsPath = "credentials.json"
    let fileManager = FileManager.default
    
    if !fileManager.fileExists(atPath: credentialsPath) {
        print("No credentials found. Attempting to generate credentials.json...")
        
        // Create a temporary GrokConfiguration to generate credentials
        do {
            // Create the mock cookies so initialization succeeds
            let mockCookies = [
                "x-anonuserid": "mock-user-id",
                "x-challenge": "mock-challenge",
                "x-signature": "mock-signature",
                "sso": "mock-sso",
                "sso-rw": "mock-sso-rw"
            ]
            
            // Instead of creating a GrokClient directly, we'll check if the cookie extractor script exists
            // and try to run it directly
            let scriptPaths = [
                "./Scripts/cookie_extractor.py",
                "../Scripts/cookie_extractor.py"
            ]
            
            // Find the first existing script path
            if let scriptPath = scriptPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                print("Found cookie extractor script at: \(scriptPath)")
                
                // Run the cookie extractor script
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", scriptPath, "--format", "json", "--required", "--output", credentialsPath]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        print("Successfully generated credentials.json during initialization")
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8) {
                            print("Cookie extraction failed with output: \(output)")
                        }
                        print("Warning: Could not generate credentials.json automatically")
                    }
                } catch {
                    print("Error running cookie extractor: \(error.localizedDescription)")
                }
            } else {
                print("Warning: Could not find cookie_extractor.py in expected locations")
                print("You may need to run 'swift run grok auth generate' to create credentials")
            }
            
            // The initialization above will attempt to generate credentials
            if fileManager.fileExists(atPath: credentialsPath) {
                print("Successfully generated credentials.json during initialization")
            } else {
                print("Warning: Could not generate credentials.json automatically")
                print("You may need to run 'swift run grok auth generate' to create credentials")
            }
        } catch {
            print("Error during credential generation: \(error.localizedDescription)")
            print("Warning: Proxy will start with mock credentials which will likely fail with real requests")
        }
    }
}
