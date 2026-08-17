import ArgumentParser
import Foundation
import GrokClient
import Rainbow

struct AuthCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage Grok authentication credentials",
        subcommands: [Generate.self, Import.self]
    )

    struct Generate: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "generate",
            abstract: "Generate new credentials by extracting cookies from your browser"
        )

        func run() async throws {
            print("Extracting credentials from browser...".cyan)
            fflush(stdout)

            do {
                let app = GrokCLIApp.shared
                let credentialsPath = try await app.generateCredentials()
                print("Successfully generated credentials!".green)
                print("Saved to: \(credentialsPath)".cyan)
            } catch {
                print("Error generating credentials: \(error.localizedDescription)".red)
                print("Please make sure you're logged in to Grok in your browser.".yellow)
                processExit(1)
            }
        }
    }

    struct Import: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Import credentials from a JSON file"
        )

        @Argument(help: "Path to the JSON credentials file")
        var path: String

        func run() throws {
            print("Importing credentials from \(path)...".cyan)

            do {
                let app = GrokCLIApp.shared
                try app.saveCredentials(from: path)
                print("Successfully imported credentials!".green)
            } catch {
                print("Error importing credentials: \(error.localizedDescription)".red)
                print("Please make sure the file exists and contains valid credentials.".yellow)
            }
        }
    }
}


extension GrokCLI {
    static var authBrowserNames: Set<String> {
        ["auto", "safari", "atlas", "chrome", "firefox", "chromium", "brave", "edge", "arc"]
    }

    static func handleAuthCommand(
        args: [String],
        exitOnGenerateFailure: Bool = false,
        exitOnUsageError: Bool = false,
        exitOnImportFailure: Bool = false
    ) async throws {
        let jsonRequested = isJSONRequested(args)
        let quietRequested = args.contains("--quiet")
        let args = removingJSONOutputArgs(normalizedAuthArgs(args))

        if args.first?.lowercased() == "help" || args.first == "-h" || args.first == "--help" {
            printAuthUsage()
            return
        }

        let subCommand = args.first?.lowercased() ?? "generate"
        let app = GrokCLIApp.shared

        switch subCommand {
        case "generate":
            if containsHelpArgument(Array(args.dropFirst())) {
                printAuthGenerateUsage()
                return
            }
            await generateAuthCredentials(
                app: app,
                args: args.isEmpty ? [] : Array(args.dropFirst()),
                exitOnFailure: exitOnGenerateFailure,
                jsonRequested: jsonRequested
            )

        case "status":
            try handleAuthStatusCommand(
                app: app,
                jsonRequested: jsonRequested,
                quietRequested: quietRequested
            )

        case "use":
            try handleAuthUseCommand(
                app: app,
                args: Array(args.dropFirst()),
                exitOnFailure: exitOnGenerateFailure,
                exitOnUsageError: exitOnUsageError,
                jsonRequested: jsonRequested,
                quietRequested: quietRequested
            )

        case "oauth":
            await handleXAIOAuthCommand(
                app: app,
                args: Array(args.dropFirst()),
                exitOnFailure: exitOnGenerateFailure,
                exitOnUsageError: exitOnUsageError,
                jsonRequested: jsonRequested,
                quietRequested: quietRequested
            )

        case "import":
            let importArgs = Array(args.dropFirst()).filter { $0 != "--quiet" }
            if containsHelpArgument(importArgs) {
                printAuthImportUsage()
                return
            }
            guard importArgs.count == 1 else {
                if jsonRequested {
                    printJSONError(command: "auth", subcommand: "import", message: "Please provide a path to the credentials file", code: "usage_error", exitCode: 2)
                } else {
                    print("Error: Please provide a path to the credentials file".red)
                }
                if exitOnUsageError {
                    exit(with: 2)
                }
                return
            }

            let path = importArgs[0]
            if !jsonRequested && !quietRequested {
                print("Importing credentials from \(path)...".cyan)
            }

            do {
                try app.saveCredentials(from: path)
                if jsonRequested {
                    try printJSONResult(
                        command: "auth",
                        subcommand: "import",
                        category: "auth_result",
                        data: AnyCodable([
                            "action": AnyCodable("import"),
                            "path": AnyCodable(path)
                        ])
                    )
                } else if !quietRequested {
                    print("Successfully imported credentials!".green)
                }
            } catch {
                if jsonRequested {
                    printJSONError(command: "auth", subcommand: "import", error: error, exitCode: 1)
                } else if quietRequested {
                    CLIOutput.stderr("Error importing credentials: \(error.localizedDescription)")
                } else {
                    print("Error importing credentials: \(error.localizedDescription)".red)
                    print("Please make sure the file exists and contains valid credentials.".yellow)
                }
                if exitOnImportFailure {
                    exit(with: 1)
                }
            }

        default:
            if subCommand.hasPrefix("-") {
                await generateAuthCredentials(
                    app: app,
                    args: args,
                    exitOnFailure: exitOnGenerateFailure,
                    jsonRequested: jsonRequested
                )
            } else {
                if jsonRequested {
                    printJSONError(command: "auth", message: "Unknown auth command: \(subCommand)", code: "usage_error", exitCode: 2)
                } else {
                    print("Unknown auth command: \(subCommand)".red)
                    print("Run 'grok auth help' for available auth commands.".yellow)
                }
                if exitOnUsageError {
                    exit(with: 2)
                }
            }
        }
    }

    static func handleAuthStatusCommand(
        app: GrokCLIApp,
        jsonRequested: Bool,
        quietRequested: Bool
    ) throws {
        let status = app.authSelectionStatus()
        if jsonRequested {
            try printJSONResult(
                command: "auth",
                subcommand: "status",
                category: "auth_status",
                data: AnyCodable(authSelectionJSON(action: "status", status: status))
            )
            return
        }

        guard !quietRequested else {
            return
        }

        printAuthSelectionStatus(status)
    }

    static func handleAuthUseCommand(
        app: GrokCLIApp,
        args: [String],
        exitOnFailure: Bool,
        exitOnUsageError: Bool,
        jsonRequested: Bool,
        quietRequested: Bool
    ) throws {
        let useArgs = args.filter { $0 != "--quiet" }
        if containsHelpArgument(useArgs) {
            printAuthUseUsage()
            return
        }

        guard useArgs.count == 1 else {
            let message = "Usage: grok auth use <web|oauth>"
            if jsonRequested {
                printJSONError(command: "auth", subcommand: "use", message: message, code: "usage_error", exitCode: 2)
            } else {
                print("Error: \(message)".red)
            }
            if exitOnUsageError {
                exit(with: 2)
            }
            return
        }

        guard let mode = GrokAuthMode.parse(useArgs[0]) else {
            let message = "Unknown auth mode: \(useArgs[0]). Use web or oauth."
            if jsonRequested {
                printJSONError(command: "auth", subcommand: "use", message: message, code: "usage_error", exitCode: 2)
            } else {
                print("Error: \(message)".red)
            }
            if exitOnUsageError {
                exit(with: 2)
            }
            return
        }

        do {
            let status = try app.selectAuthMode(mode)
            if jsonRequested {
                try printJSONResult(
                    command: "auth",
                    subcommand: "use",
                    category: "auth_result",
                    data: AnyCodable(authSelectionJSON(action: "use", status: status))
                )
            } else if !quietRequested {
                print("Default auth mode set to: \(mode.displayName)".green)
                if let environmentMode = status.environmentMode {
                    print("Current process is still using \(environmentMode.displayName) from \(GrokAuthMode.environmentKey).".yellow)
                }
            }
        } catch {
            if jsonRequested {
                printJSONError(command: "auth", subcommand: "use", error: error, exitCode: 1)
            } else if quietRequested {
                CLIOutput.stderr("Error selecting auth mode: \(error.localizedDescription)")
            } else {
                print("Error selecting auth mode: \(error.localizedDescription)".red)
            }
            if exitOnFailure {
                processExit(1)
            }
        }
    }

    static func handleXAIOAuthCommand(
        app: GrokCLIApp,
        args: [String],
        exitOnFailure: Bool,
        exitOnUsageError: Bool,
        jsonRequested: Bool,
        quietRequested: Bool
    ) async {
        if containsHelpArgument(args) {
            printAuthOAuthUsage()
            return
        }

        let parsed: XAIOAuthCommandOptions
        do {
            parsed = try parseXAIOAuthCommandOptions(args)
        } catch {
            if jsonRequested {
                printJSONError(
                    command: "auth",
                    subcommand: "oauth",
                    message: error.localizedDescription,
                    code: "usage_error",
                    exitCode: 2
                )
            } else {
                print("Error: \(error.localizedDescription)".red)
                printAuthOAuthUsage()
            }
            if exitOnUsageError {
                exit(with: 2)
            }
            return
        }

        do {
            switch parsed.action {
            case .login:
                if !jsonRequested && !quietRequested {
                    print("Starting xAI OAuth device login...".cyan)
                }

                let login = try await app.authenticateWithXAIOAuth { device in
                    printXAIDeviceAuthorization(device, jsonRequested: jsonRequested)
                }

                let verification: XAIOAuthVerificationResult?
                if parsed.verifyModels {
                    verification = try await app.verifyXAIOAuthCredential(sendTestResponse: parsed.sendTestResponse)
                } else {
                    verification = nil
                }

                if jsonRequested {
                    var data = oauthCredentialJSON(
                        action: "login",
                        credential: verification?.credential ?? login.credential,
                        credentialPath: verification?.credentialPath ?? login.credentialPath
                    )
                    if let verification {
                        data.merge(oauthVerificationJSON(verification), uniquingKeysWith: { _, new in new })
                    }
                    try printJSONResult(
                        command: "auth",
                        subcommand: "oauth",
                        category: "auth_result",
                        data: AnyCodable(data)
                    )
                } else if !quietRequested {
                    print("xAI OAuth credentials saved.".green)
                    print("Saved to: \(login.credentialPath)".cyan)
                    if let verification {
                        print("Verified xAI API models: \(verification.models.count)".green)
                    }
                }

            case .status:
                let status = try app.savedXAIOAuthStatus()
                if jsonRequested {
                    let data = oauthStatusJSON(credential: status.credential, credentialPath: status.credentialPath)
                    try printJSONResult(
                        command: "auth",
                        subcommand: "oauth",
                        category: "auth_status",
                        data: AnyCodable(data)
                    )
                } else if let credential = status.credential, let path = status.credentialPath {
                    print("xAI OAuth credentials found.".green)
                    print("Saved to: \(path)".cyan)
                    print("Expires at: \(iso8601String(credential.expiresAt))")
                    print("Expired: \(credential.isExpired ? "yes" : "no")")
                } else {
                    print("No saved xAI OAuth credentials.".yellow)
                    print("Run: grok auth oauth")
                }

            case .verify:
                let verification = try await app.verifyXAIOAuthCredential(sendTestResponse: parsed.sendTestResponse)
                if jsonRequested {
                    var data = oauthCredentialJSON(
                        action: "verify",
                        credential: verification.credential,
                        credentialPath: verification.credentialPath
                    )
                    data.merge(oauthVerificationJSON(verification), uniquingKeysWith: { _, new in new })
                    try printJSONResult(
                        command: "auth",
                        subcommand: "oauth",
                        category: "auth_verification",
                        data: AnyCodable(data)
                    )
                } else if !quietRequested {
                    print("xAI OAuth credential verified.".green)
                    print("Models available: \(verification.models.count)".cyan)
                    if let responseID = verification.testResponseID {
                        print("Responses API test response: \(responseID)".cyan)
                    }
                }
            }
        } catch {
            if jsonRequested {
                printJSONError(command: "auth", subcommand: "oauth", error: error, exitCode: 1)
            } else if quietRequested {
                CLIOutput.stderr("Error running xAI OAuth: \(error.localizedDescription)")
            } else {
                print("Error running xAI OAuth: \(error.localizedDescription)".red)
            }
            if exitOnFailure {
                processExit(1)
            }
        }
    }

    enum XAIOAuthCommandAction {
        case login
        case status
        case verify
    }

    struct XAIOAuthCommandOptions {
        let action: XAIOAuthCommandAction
        let verifyModels: Bool
        let sendTestResponse: Bool
    }

    static func parseXAIOAuthCommandOptions(_ args: [String]) throws -> XAIOAuthCommandOptions {
        var action: XAIOAuthCommandAction = .login
        var actionWasSet = false
        var verifyModels = true
        var sendTestResponse = false

        for arg in args where arg != "--quiet" {
            switch arg {
            case "login", "device", "device-code", "--device-code":
                action = .login
                actionWasSet = true
            case "status":
                action = .status
                actionWasSet = true
                verifyModels = false
            case "verify":
                action = .verify
                actionWasSet = true
            case "--no-verify":
                verifyModels = false
            case "--verify-response", "--test-response", "--response":
                sendTestResponse = true
            default:
                if arg.hasPrefix("-") {
                    throw GrokError.apiError("Unknown xAI OAuth option: \(arg)")
                }
                if actionWasSet {
                    throw GrokError.apiError("Unexpected xAI OAuth argument: \(arg)")
                }
                throw GrokError.apiError("Unknown xAI OAuth command: \(arg)")
            }
        }

        if sendTestResponse {
            verifyModels = true
        }

        return XAIOAuthCommandOptions(
            action: action,
            verifyModels: verifyModels,
            sendTestResponse: sendTestResponse
        )
    }

    static func normalizedAuthArgs(_ args: [String]) -> [String] {
        guard let first = args.first else {
            return args
        }

        let browser = first.lowercased()
        guard authBrowserNames.contains(browser) else {
            return args
        }

        return ["generate", "--browser", browser] + Array(args.dropFirst())
    }

    static func removingJSONOutputArgs(_ args: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                index += 1
                continue
            }
            if arg.hasPrefix("--format="), String(arg.dropFirst("--format=".count)).lowercased() == "json" {
                index += 1
                continue
            }
            if arg == "--format", index + 1 < args.count, args[index + 1].lowercased() == "json" {
                index += 2
                continue
            }
            result.append(arg)
            index += 1
        }
        return result
    }

    static func generateAuthCredentials(app: GrokCLIApp, args: [String], exitOnFailure: Bool, jsonRequested: Bool = false) async {
        let quietRequested = args.contains("--quiet")
        let extractorArgs = jsonRequested && !args.contains("--quiet") ? args + ["--quiet"] : args
        if !jsonRequested && !quietRequested {
            print("Extracting credentials from browser...".cyan)
            fflush(stdout)
        }
        do {
            let credentialsPath = try await app.generateCredentials(args: extractorArgs, suppressOutput: jsonRequested || quietRequested)
            if jsonRequested {
                var data: [String: AnyCodable] = [
                    "action": AnyCodable("generate"),
                    "credentialsPath": AnyCodable(credentialsPath)
                ]
                if let browser = authBrowserValue(in: extractorArgs) {
                    data["browser"] = AnyCodable(browser)
                }
                try printJSONResult(
                    command: "auth",
                    subcommand: "generate",
                    category: "auth_result",
                    data: AnyCodable(data)
                )
            } else if !quietRequested {
                print("Successfully generated credentials!".green)
                print("Saved to: \(credentialsPath)".cyan)
            }
        } catch {
            if jsonRequested {
                printJSONError(command: "auth", subcommand: "generate", error: error, exitCode: 1)
            } else if quietRequested {
                CLIOutput.stderr("Error generating credentials: \(error.localizedDescription)")
            } else {
                print("Error generating credentials: \(error.localizedDescription)".red)
                print("Please make sure you're logged in to Grok in your browser.".yellow)
            }
            if exitOnFailure {
                processExit(1)
            }
        }
    }

    static func authBrowserValue(in args: [String]) -> String? {
        for (index, arg) in args.enumerated() {
            if arg == "--browser", index + 1 < args.count {
                return args[index + 1]
            }
            if arg.hasPrefix("--browser=") {
                return String(arg.dropFirst("--browser=".count))
            }
        }
        return nil
    }

    static func printXAIDeviceAuthorization(_ device: XAIDeviceAuthorization, jsonRequested: Bool) {
        let target = device.verificationURIComplete ?? device.verificationURI
        if jsonRequested {
            CLIOutput.stderr("Open: \(target)")
            CLIOutput.stderr("Code: \(device.userCode)")
            return
        }

        print("Open: \(target)".cyan)
        print("Code: \(device.userCode)".green)
        print("Waiting for xAI authorization...".yellow)
    }

    static func oauthCredentialJSON(
        action: String,
        credential: XAIOAuthCredential,
        credentialPath: String
    ) -> [String: AnyCodable] {
        [
            "action": AnyCodable(action),
            "authFlow": AnyCodable("device_code"),
            "apiBaseURL": AnyCodable(credential.apiBaseURL),
            "credentialPath": AnyCodable(credentialPath),
            "expiresAt": AnyCodable(iso8601String(credential.expiresAt)),
            "expired": AnyCodable(credential.isExpired),
            "hasRefreshToken": AnyCodable(credential.refreshToken != nil),
            "issuer": AnyCodable(credential.issuer),
            "scope": AnyCodable(credential.scope ?? ""),
            "tokenType": AnyCodable(credential.tokenType)
        ]
    }

    static func oauthStatusJSON(credential: XAIOAuthCredential?, credentialPath: String?) -> [String: AnyCodable] {
        guard let credential, let credentialPath else {
            return [
                "authenticated": AnyCodable(false),
                "credentialPath": AnyCodable(credentialPath ?? "")
            ]
        }

        var data = oauthCredentialJSON(action: "status", credential: credential, credentialPath: credentialPath)
        data["authenticated"] = AnyCodable(true)
        return data
    }

    static func authSelectionJSON(action: String, status: GrokAuthSelectionStatus) -> [String: AnyCodable] {
        [
            "action": AnyCodable(action),
            "selectedMode": AnyCodable(status.selectedMode.rawValue),
            "selectedModeDisplayName": AnyCodable(status.selectedMode.displayName),
            "preferredMode": AnyCodable(status.preferredMode?.rawValue ?? ""),
            "environmentMode": AnyCodable(status.environmentMode?.rawValue ?? ""),
            "environmentKey": AnyCodable(GrokAuthMode.environmentKey),
            "webAuthenticated": AnyCodable(status.webCredentialsPath != nil),
            "webCredentialsPath": AnyCodable(status.webCredentialsPath ?? ""),
            "oauthAuthenticated": AnyCodable(status.oauthCredentialsPath != nil),
            "oauthCredentialsPath": AnyCodable(status.oauthCredentialsPath ?? "")
        ]
    }

    static func oauthVerificationJSON(_ verification: XAIOAuthVerificationResult) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "modelCount": AnyCodable(verification.models.count),
            "models": AnyCodable(verification.models)
        ]
        if let responseID = verification.testResponseID {
            data["testResponseID"] = AnyCodable(responseID)
        }
        if let responseText = verification.testResponseText {
            data["testResponseText"] = AnyCodable(responseText)
        }
        return data
    }

    static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func printAuthUsage() {
        print("Auth commands:".cyan)
        print("  auth          - Generate new credentials from browser cookies")
        print("  status        - Show saved auth credentials and selected default")
        print("  use <mode>    - Select default auth mode: web or oauth")
        print("  generate      - Generate new credentials from browser cookies")
        print("  oauth         - Sign in with xAI OAuth device code")
        print("  safari        - Generate credentials from Safari")
        print("  chrome        - Generate credentials from Chrome")
        print("  <browser>     - Browser shortcut: auto, safari, atlas, chrome, firefox, chromium, brave, edge, arc")
        print("  import <file> - Import credentials from a JSON file")
        print("  Add --json, --format json, or --format=json for JSON output")
    }

    static func printAuthGenerateUsage() {
        print("""
        Usage: grok auth generate [--browser <name>] [--quiet] [--json|--format json]

        Generates credentials from browser cookies.
        Browser shortcuts: auto, safari, atlas, chrome, firefox, chromium, brave, edge, arc
        """)
    }

    static func printAuthImportUsage() {
        print("""
        Usage: grok auth import <file> [--json|--format json]

        Imports credentials from a JSON file.
        """)
    }

    static func printAuthUseUsage() {
        print("""
        Usage: grok auth use <web|oauth> [--json|--format json]

        Selects the default auth mode without deleting saved credentials for the other mode.
        """)
    }

    static func printAuthOAuthUsage() {
        print("""
        Usage: grok auth oauth [login|status|verify] [options] [--json|--format json]

        Signs in to xAI OAuth with the device-code flow and stores the bearer credential separately from browser cookies.

        Options:
          --no-verify       Save credentials without calling the xAI models API
          --verify-response Verify the Responses API with a tiny test request
          --quiet           Suppress nonessential output
        """)
    }

    static func printAuthSelectionStatus(_ status: GrokAuthSelectionStatus) {
        if let environmentMode = status.environmentMode {
            print("Selected auth mode: \(status.selectedMode.displayName) (\(GrokAuthMode.environmentKey))".cyan)
            if let preferredMode = status.preferredMode {
                print("Default auth mode: \(preferredMode.displayName)".cyan)
            }
            print("Environment override: \(environmentMode.rawValue)")
        } else {
            print("Selected auth mode: \(status.selectedMode.displayName)".cyan)
            if let preferredMode = status.preferredMode {
                print("Default auth mode: \(preferredMode.displayName)")
            }
        }

        let webStatus = status.webCredentialsPath == nil ? "missing" : "active"
        let oauthStatus = status.oauthCredentialsPath == nil ? "missing" : "active"
        print("Grok web credentials: \(webStatus)")
        if let path = status.webCredentialsPath {
            print("  Saved to: \(path)")
        }
        print("xAI OAuth credentials: \(oauthStatus)")
        if let path = status.oauthCredentialsPath {
            print("  Saved to: \(path)")
        }
    }


}
