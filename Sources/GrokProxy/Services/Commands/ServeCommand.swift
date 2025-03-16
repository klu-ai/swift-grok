import Vapor

public struct ServeCommand: Command {
    public struct Signature: CommandSignature {
        @Option(name: "hostname", short: "H", help: "Set the hostname the server will run on")
        public var hostname: String?
        
        @Option(name: "port", short: "p", help: "Set the port the server will run on")
        public var port: Int?
        
        @Option(name: "env", short: "e", help: "Set the environment to run on")
        public var env: String?
        
        @Flag(name: "verbose", help: "Enable verbose logging")
        public var verbose: Bool
        
        public init() {}
    }
    
    public var help: String {
        "Starts the Grok Proxy server"
    }
    
    public func run(using context: CommandContext, signature: Signature) throws {
        // Store the verbose flag in application storage
        context.application.storage[VerboseFlagKey.self] = signature.verbose
        
        // Extract configuration from signature
        let hostname = signature.hostname ?? "127.0.0.1"
        let port = signature.port ?? 8080
        // Using the env variable for potential future enhancements
        let _ = signature.env ?? (context.application.environment.name)
        
        // Configure hostname/port
        context.application.http.server.configuration.hostname = hostname
        context.application.http.server.configuration.port = port
        
        // Start the server
        try context.application.server.start(address: .hostname(hostname, port: port))
        
        // Display startup message
        context.application.logger.notice("Server starting on \(hostname):\(port)")
        context.console.print("Server starting on ", newLine: false)
        context.console.output("http://\(hostname):\(port)".consoleText(.info))
        context.console.print()
        
        // Wait for the application to terminate - proper way to wait in Vapor
        try context.application.server.onShutdown.wait()
    }
}

extension Commands {
    public static func serveCommand() -> ServeCommand {
        ServeCommand()
    }
} 