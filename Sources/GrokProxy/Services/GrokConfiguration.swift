import Vapor
@preconcurrency import GrokClient
import Foundation

enum GrokConfigurationError: Error {
    case missingCredentials
    case invalidCredentialsFile
    case fileReadError
    case credentialsGenerationFailed
}

struct GrokConfiguration {
    let grokClient: GrokClient
    
    init(from environment: Environment) throws {
        // First, set up a default mock client as fallback
        let mockCookies = [
            "x-anonuserid": "mock-user-id",
            "x-challenge": "mock-challenge",
            "x-signature": "mock-signature",
            "sso": "mock-sso",
            "sso-rw": "mock-sso-rw"
        ]
        
        // Initialize with mock cookies as a fallback (this ensures self.grokClient is always initialized)
        self.grokClient = try GrokClient(cookies: mockCookies, isDebug: true)
        
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
        let credentialsPath = "credentials.json"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: credentialsPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: credentialsPath))
                if let cookies = try JSONSerialization.jsonObject(with: data) as? [String: String], !cookies.isEmpty {
                    self.grokClient = try GrokClient(cookies: cookies)
                    return
                }
            } catch {
                print("Error loading credentials.json: \(error.localizedDescription)")
                // Continue with mock cookies
            }
        } else {
            // Attempt to generate credentials if they don't exist
            do {
                if try Self.generateCredentials(to: credentialsPath) {
                    // Now try to load the newly generated credentials
                    let data = try Data(contentsOf: URL(fileURLWithPath: credentialsPath))
                    if let cookies = try JSONSerialization.jsonObject(with: data) as? [String: String], !cookies.isEmpty {
                        self.grokClient = try GrokClient(cookies: cookies)
                        return
                    }
                }
            } catch {
                // Log the error but continue with mock cookies
                print("Error generating credentials: \(error.localizedDescription)")
            }
        }
        
        // At this point, we're using the mock cookies initialized at the start
        print("Warning: Using mock cookies - API requests will likely fail.")
    }
    
    // Method to generate credentials using the cookie_extractor.py script
    // Made static to avoid 'self' usage before initialization
    private static func generateCredentials(to outputPath: String) throws -> Bool {
        print("Credentials file not found. Attempting to generate...")
        
        // Determine the path to the script relative to the current executable
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()
        
        // Try to find cookie_extractor.py in common locations
        var scriptLocations = [
            executableDir.appendingPathComponent("cookie_extractor.py").path,
            executableDir.appendingPathComponent("Scripts/cookie_extractor.py").path,
            "./Scripts/cookie_extractor.py",
            "../Scripts/cookie_extractor.py"
        ]
        
        // Find project root based on package structure
        if let projectRootURL = findProjectRoot() {
            scriptLocations.append(projectRootURL.appendingPathComponent("Scripts/cookie_extractor.py").path)
        }
        
        // Find the first existing script path
        let scriptPath: String
        if let existingScriptPath = scriptLocations.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            scriptPath = existingScriptPath
            print("Found cookie extractor script at: \(scriptPath)")
        } else {
            // Download the script if it doesn't exist
            print("Cookie extractor script not found. Downloading it...")
            
            // Create a temporary directory for the script
            let tempDir = FileManager.default.temporaryDirectory
            let downloadedScriptPath = tempDir.appendingPathComponent("cookie_extractor.py").path
            
            // URL for the cookie extractor script
            guard let url = URL(string: "https://raw.githubusercontent.com/klu-ai/swift-grok/refs/heads/main/Scripts/cookie_extractor.py") else {
                throw GrokConfigurationError.credentialsGenerationFailed
            }
            
            // Create a semaphore for synchronous download
            let semaphore = DispatchSemaphore(value: 0)
            var downloadedData: Data?
            var downloadError: Error?
            var httpResponse: HTTPURLResponse?
            
            // Execute the download task - using @unchecked Sendable to address concurrent mutation warnings
            URLSession.shared.dataTask(with: url) { [semaphore] data, response, error in
                // Using withoutActuallyEscaping to avoid capture list warnings
                withoutActuallyEscaping(data) { capturedData in
                    downloadedData = capturedData
                }
                withoutActuallyEscaping(error) { capturedError in
                    downloadError = capturedError
                }
                withoutActuallyEscaping(response) { capturedResponse in
                    httpResponse = capturedResponse as? HTTPURLResponse
                }
                semaphore.signal()
            }.resume()
            
            // Wait for download to complete
            _ = semaphore.wait(timeout: .distantFuture)
            
            // Check for download errors
            if let error = downloadError {
                print("Failed to download cookie extractor script: \(error.localizedDescription)")
                throw GrokConfigurationError.credentialsGenerationFailed
            }
            
            guard let data = downloadedData,
                  let response = httpResponse,
                  response.statusCode == 200 else {
                print("Failed to download cookie extractor script: Invalid response")
                throw GrokConfigurationError.credentialsGenerationFailed
            }
            
            // Save the script
            do {
                try data.write(to: URL(fileURLWithPath: downloadedScriptPath))
                scriptPath = downloadedScriptPath
                print("Cookie extractor script downloaded successfully to: \(scriptPath)")
            } catch {
                print("Failed to save cookie extractor script: \(error.localizedDescription)")
                throw GrokConfigurationError.credentialsGenerationFailed
            }
        }
        
        // Run the cookie extractor script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptPath, "--format", "json", "--required", "--output", outputPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("Cookie extraction failed with output: \(output)")
                }
                return false
            }
            
            print("Successfully generated credentials file at: \(outputPath)")
            return true
        } catch {
            print("Failed to run cookie extractor: \(error.localizedDescription)")
            return false
        }
    }
    
    // Helper method to find the project root directory
    // Made static to avoid 'self' usage before initialization
    private static func findProjectRoot() -> URL? {
        let fileManager = FileManager.default
        var currentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        // Try to find Package.swift going up in the directory hierarchy
        while currentURL.pathComponents.count > 1 {
            let packageSwiftURL = currentURL.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageSwiftURL.path) {
                return currentURL
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        return nil
    }
    
    static func register(_ app: Application) throws {
        let config = try GrokConfiguration(from: app.environment)
        
        // Register the chat completions controller
        let controller = ChatCompletionsController(grokClient: config.grokClient)
        try app.register(collection: controller)
    }
} 