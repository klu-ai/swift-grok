import Vapor

struct AppConfiguration {
    /// Whether verbose logging is enabled
    let verboseLogging: Bool
    
    /// Initialize from environment variables or command line arguments
    init(from environment: Environment) {
        // Check for VERBOSE environment variable (1, true, yes, y will enable it)
        if let verboseValue = Environment.get("VERBOSE")?.lowercased() {
            self.verboseLogging = ["1", "true", "yes", "y"].contains(verboseValue)
        }
        // Check for --verbose command line argument
        else if environment.arguments.contains("--verbose") {
            self.verboseLogging = true
        }
        // Default to false
        else {
            self.verboseLogging = false
        }
    }
    
    /// Register the configuration with the application
    static func register(_ app: Application) throws {
        let config = AppConfiguration(from: app.environment)
        
        // Store configuration in application storage
        app.storage[AppConfigurationKey.self] = config
        
        // Register middleware based on configuration
        if config.verboseLogging {
            // Add the verbose logging middleware to the beginning of the middleware chain
            app.middleware.use(VerboseLoggingMiddleware(isEnabled: true), at: .beginning)
            app.logger.notice("Verbose logging enabled")
        }
    }
}

/// Storage key for app configuration
private struct AppConfigurationKey: StorageKey {
    typealias Value = AppConfiguration
}

/// Extension to make the configuration accessible from the application
extension Application {
    var appConfig: AppConfiguration {
        guard let config = storage[AppConfigurationKey.self] else {
            fatalError("App configuration not initialized. Call AppConfiguration.register(_:) in configure.swift")
        }
        return config
    }
}

/// Extension to make the configuration accessible from requests
extension Request {
    var appConfig: AppConfiguration {
        application.appConfig
    }
} 