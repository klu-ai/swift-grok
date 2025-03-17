import Foundation

/// Helper extension to initialize GrokClient with cookies extracted by cookie_extractor.py
public extension GrokClient {
    /// Creates a GrokClient instance using cookies loaded from a JSON file
    /// - Parameter jsonPath: Path to the JSON file containing cookies
    /// - Parameter isDebug: Whether to enable debug output (default: false)
    /// - Returns: Initialized GrokClient or nil if loading fails
    static func fromJSONFile(at jsonPath: String, isDebug: Bool = false) throws -> GrokClient {
        let fileURL = URL(fileURLWithPath: jsonPath)
        let data = try Data(contentsOf: fileURL)
        let cookies = try JSONDecoder().decode([String: String].self, from: data)
        return try GrokClient(cookies: cookies, isDebug: isDebug)
    }
    
    /// Creates a GrokClient instance using the generated GrokCookies class
    /// - Parameter isDebug: Whether to enable debug output (default: false)
    /// - Returns: Initialized GrokClient
    static func withAutoCookies(isDebug: Bool = false) throws -> GrokClient {
        // For this to work, you must add the generated GrokCookies.swift file to your project
        // We'll check for it at runtime to avoid compile-time issues
        #if canImport(ObjectiveC)
        if let cookiesClass = NSClassFromString("GrokCookies") as? NSObject.Type,
           let cookiesValue = cookiesClass.perform(NSSelectorFromString("cookies"))?.takeUnretainedValue() as? [String: String] {
            return try GrokClient(cookies: cookiesValue, isDebug: isDebug)
        } else {
            // Fallback to check for a GrokCookies.swift file in standard locations
            for path in ["./GrokCookies.swift", "./Sources/GrokCookies.swift"] {
                if FileManager.default.fileExists(atPath: path) {
                    print("Found GrokCookies.swift but it's not compiled into the app.")
                    print("Please add GrokCookies.swift to your project or use another method.")
                    break
                }
            }
            throw GrokError.invalidCredentials
        }
        #else
            // Auto cookies are not supported on platforms without ObjectiveC (e.g. Linux)
            throw GrokError.invalidCredentials
        #endif
    }
    
    /// Loads cookies from a Swift dictionary literal string
    /// - Parameter swiftDictString: Swift dictionary literal as string
    /// - Parameter isDebug: Whether to enable debug output (default: false)
    /// - Returns: Initialized GrokClient or nil if parsing fails
    static func fromSwiftDictString(_ swiftDictString: String, isDebug: Bool = false) throws -> GrokClient {
        // Very simple parser for Swift dictionary literals, for demo purposes
        // In production, you would want a more robust solution
        let cookieRegex = try NSRegularExpression(pattern: #""([^"]+)":\s*"([^"]+)""#)
        let cookies = cookieRegex.matches(in: swiftDictString, range: NSRange(swiftDictString.startIndex..., in: swiftDictString)).reduce(into: [String: String]()) { result, match in
            guard let keyRange = Range(match.range(at: 1), in: swiftDictString),
                  let valueRange = Range(match.range(at: 2), in: swiftDictString) else { return }
            let key = String(swiftDictString[keyRange])
            let value = String(swiftDictString[valueRange])
            result[key] = value
        }
        
        guard !cookies.isEmpty else {
            throw GrokError.invalidCredentials
        }
        
        return try GrokClient(cookies: cookies, isDebug: isDebug)
    }
} 