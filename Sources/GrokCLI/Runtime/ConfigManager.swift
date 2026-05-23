import Foundation

class ConfigManager {
    private let fileManager = FileManager.default

    // Get the config directory path
    private var configDirectory: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["GROK_CONFIG_DIR"],
           !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: configuredPath).expandingTildeInPath)
        }

        let homeDirectory = ProcessInfo.processInfo.environment["HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? fileManager.homeDirectoryForCurrentUser

        #if os(macOS)
        return homeDirectory.appendingPathComponent(".config/grok-cli")
        #else
        return homeDirectory.appendingPathComponent(".grok-cli")
        #endif
    }

    // Path for saved credentials
    private var credentialsPath: URL {
        return configDirectory.appendingPathComponent("credentials.json")
    }

    private var oauthCredentialsPath: URL {
        return configDirectory.appendingPathComponent("xai-oauth.json")
    }

    private var authModePath: URL {
        return configDirectory.appendingPathComponent("auth-mode.json")
    }

    // Create config directory if it doesn't exist
    private func ensureConfigDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: configDirectory.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
    }

    // Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
//    func codeModeSettingsDirectory() throws -> URL {
//        try ensureConfigDirectoryExists()
//        let directory = configDirectory.appendingPathComponent("code-mode", isDirectory: true)
//        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
//        return directory
//    }
//
//    func codeModeSettingsBackupsDirectory() throws -> URL {
//        let directory = try codeModeSettingsDirectory().appendingPathComponent("settings-backups", isDirectory: true)
//        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
//        return directory
//    }
//
//    func codeModeSessionsDirectory() throws -> URL {
//        let directory = try codeModeSettingsDirectory().appendingPathComponent("sessions", isDirectory: true)
//        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
//        return directory
//    }
//
//    func activeCodeModeSettingsScopePath() throws -> URL {
//        try codeModeSettingsDirectory().appendingPathComponent("active-settings-scope.json")
//    }

    // Get path to saved credentials if they exist
    func getSavedCredentialsPath() -> String? {
        return fileManager.fileExists(atPath: credentialsPath.path) ? credentialsPath.path : nil
    }

    func getSavedOAuthCredentialsPath() -> String? {
        return fileManager.fileExists(atPath: oauthCredentialsPath.path) ? oauthCredentialsPath.path : nil
    }

    // Save path to credentials
    func saveCredentialsPath(_ path: String) throws {
        try ensureConfigDirectoryExists()

        // Read the credentials file
        let sourceURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        let data = try Data(contentsOf: sourceURL)
        _ = try validatedCredentialCookies(from: data, context: "Credentials file")

        // Save to the credentials path
        try data.write(to: credentialsPath)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath.path)
        try savePreferredAuthMode(.web)
    }

    @discardableResult
    func saveOAuthCredential(_ credential: XAIOAuthCredential) throws -> String {
        try ensureConfigDirectoryExists()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credential)

        try data.write(to: oauthCredentialsPath, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oauthCredentialsPath.path)
        try savePreferredAuthMode(.xaiOAuth)
        return oauthCredentialsPath.path
    }

    func loadOAuthCredential() throws -> XAIOAuthCredential? {
        guard fileManager.fileExists(atPath: oauthCredentialsPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: oauthCredentialsPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(XAIOAuthCredential.self, from: data)
    }

    func savePreferredAuthMode(_ mode: GrokAuthMode) throws {
        try ensureConfigDirectoryExists()

        let data = try JSONEncoder().encode(["mode": mode.rawValue])
        try data.write(to: authModePath, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authModePath.path)
    }

    func loadPreferredAuthMode() throws -> GrokAuthMode? {
        guard fileManager.fileExists(atPath: authModePath.path) else {
            return nil
        }

        let data = try Data(contentsOf: authModePath)
        let payload = try JSONDecoder().decode([String: String].self, from: data)
        return GrokAuthMode.parse(payload["mode"])
    }

    private func validatedCredentialCookies(from data: Data, context: String) throws -> [String: String] {
        let cookies: [String: String]
        do {
            cookies = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(context) must be a JSON object whose keys and values are strings"
            ])
        }

        let trimmedCookies = cookies.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmedCookies.isEmpty else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(context) did not contain any cookies"
            ])
        }

        let emptyKeys = trimmedCookies
            .filter { $0.value.isEmpty }
            .map(\.key)
            .sorted()
        guard emptyKeys.isEmpty else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(context) contains empty cookie values for: \(emptyKeys.joined(separator: ", "))"
            ])
        }

        let authCookieNames: Set<String> = ["sso", "sso-rw", "x-userid", "x-anonuserid"]
        guard trimmedCookies.keys.contains(where: { authCookieNames.contains($0.lowercased()) }) else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(context) must include at least one Grok auth cookie: sso, sso-rw, x-userid, or x-anonuserid"
            ])
        }

        return cookies
    }

    private func findCookieExtractor() -> String? {
        if let explicitPath = ProcessInfo.processInfo.environment["GROK_COOKIE_EXTRACTOR"],
           fileManager.fileExists(atPath: explicitPath) {
            return explicitPath
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        let candidates = [
            currentDir.appendingPathComponent("Scripts/cookie_extractor.py"),
            currentDir.appendingPathComponent("cookie_extractor.py"),
            executableDir.appendingPathComponent("cookie_extractor.py"),
            executableDir.appendingPathComponent("../Scripts/cookie_extractor.py").standardizedFileURL
        ]

        return candidates.first { fileManager.fileExists(atPath: $0.path) }?.path
    }

    private func validateSavedCredentials() throws {
        let data = try Data(contentsOf: credentialsPath)
        _ = try validatedCredentialCookies(from: data, context: "Cookie extractor output")
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath.path)
    }

    // Run the cookie extractor and return the path to generated credentials
    func runCookieExtractor(extraArgs: [String] = [], suppressOutput: Bool = false) async throws -> String {
        try ensureConfigDirectoryExists()

        guard let extractorPath = findCookieExtractor() else {
            throw NSError(domain: "GrokCLI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find cookie_extractor.py. Run from the swift-grok checkout or reinstall the CLI."
            ])
        }

        // Run the cookie extractor
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", extractorPath] + extraArgs + ["--format", "json", "--required", "--output", credentialsPath.path]
        if suppressOutput {
            let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardOutput = nullOutput
            process.standardError = nullOutput
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GrokCLI", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Cookie extraction failed with exit code \(process.terminationStatus)"
            ])
        }

        try validateSavedCredentials()
        try savePreferredAuthMode(.web)

        return credentialsPath.path
    }

}
