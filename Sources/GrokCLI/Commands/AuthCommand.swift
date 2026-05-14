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

    static func printAuthUsage() {
        print("Auth commands:".cyan)
        print("  auth          - Generate new credentials from browser cookies")
        print("  generate      - Generate new credentials from browser cookies")
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


}
