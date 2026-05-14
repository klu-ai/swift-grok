import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func handleSkillsCommand(args: [String], exitOnError: Bool = false) async throws {
        let app = GrokCLIApp.shared
        let debug = args.contains("--debug")
        let jsonRequested = isJSONRequested(args)

        let parsed: ParsedSkillsCommand
        do {
            parsed = try parseSkillsCommand(args: args)
        } catch {
            if jsonRequested {
                printJSONError(command: "skills", error: error, exitCode: 2, debug: debug)
            } else {
                await app.handleError(error, debug: debug)
            }
            if exitOnError {
                GrokCLI.exit(with: 2)
            }
            return
        }

        app.setDebugMode(parsed.debug && !parsed.json)
        if case .help(let usage) = parsed.action {
            print(usage)
            return
        }

        do {
            let client = try app.initializeClient()
            switch parsed.action {
            case .list:
                async let builtInResponse = client.listSkillsResponse(locale: "en")
                async let userResponse = client.listUserSkillsResponse()
                let responses = try await (builtInResponse, userResponse)
                let skills = responses.0.skills
                let userSkills = responses.1.skills
                if parsed.json {
                    try printJSONResult(
                        command: "skills",
                        subcommand: "list",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "skill",
                            items: skills.map { AnyCodable(skillJSON($0)) },
                            extra: [
                                "scope": AnyCodable("available"),
                                "builtInSkills": AnyCodable(skills.map { AnyCodable(skillJSON($0)) }),
                                "userSkills": AnyCodable(userSkills.map { AnyCodable(skillJSON($0)) })
                            ]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                printSkillRows(title: "Grok Skills", skills: skills)
                if !userSkills.isEmpty {
                    print("")
                    printSkillRows(title: "User Skills", skills: userSkills)
                }

            case .user:
                let response = try await client.listUserSkillsResponse()
                let skills = response.skills
                if parsed.json {
                    try printJSONResult(
                        command: "skills",
                        subcommand: "user",
                        category: "resource_list",
                        data: AnyCodable(resourceListJSON(
                            resource: "skill",
                            items: skills.map { AnyCodable(skillJSON($0)) },
                            raw: response.rawJSON,
                            extra: ["scope": AnyCodable("user")]
                        )),
                        debug: parsed.debug
                    )
                    return
                }
                printSkillRows(title: "User Skills", skills: skills)

            case .help(_):
                return
            }
        } catch {
            if parsed.json {
                printJSONError(command: "skills", error: error, exitCode: 1, debug: parsed.debug)
            } else {
                await app.handleError(error, debug: debug)
            }
            if exitOnError {
                GrokCLI.exit(with: 1)
            }
        }
    }
}

private extension GrokCLI {
    enum SkillsAction {
        case list
        case user
        case help(String)
    }

    struct ParsedSkillsCommand {
        let action: SkillsAction
        let json: Bool
        let debug: Bool
    }

    static func parseSkillsCommand(args: [String]) throws -> ParsedSkillsCommand {
        var remaining = args
        let json = try CLIOptionParsing.removeJSONOutputOptions(from: &remaining)
        let debug = CLIOptionParsing.removeFlag("--debug", from: &remaining)

        guard let command = remaining.first?.lowercased() else {
            return ParsedSkillsCommand(action: .list, json: json, debug: debug)
        }

        switch command {
        case "list":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedSkillsCommand(action: .help(skillsListUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok skills list [--json|--format json] [--debug]")
            }
            return ParsedSkillsCommand(action: .list, json: json, debug: debug)

        case "mine", "user":
            if GrokCLI.containsHelpArgument(Array(remaining.dropFirst())) {
                return ParsedSkillsCommand(action: .help(command == "mine" ? skillsMineUsage : skillsUserUsage), json: json, debug: debug)
            }
            guard remaining.count == 1 else {
                throw GrokError.apiError("Usage: grok skills \(command) [--json|--format json] [--debug]")
            }
            return ParsedSkillsCommand(action: .user, json: json, debug: debug)

        case "help", "-h", "--help":
            return ParsedSkillsCommand(action: .help(skillsUsage), json: json, debug: debug)

        default:
            throw GrokError.apiError("Unknown skills command: \(command)\n\(skillsUsage)")
        }
    }

    static func printSkillRows(title: String, skills: [GrokSkill]) {
        guard !skills.isEmpty else {
            print("No skills found.".yellow)
            return
        }

        print(title.cyan.bold)
        for skill in skills {
            printSkillSummary(skill)
        }
    }

    static func printSkillSummary(_ skill: GrokSkill) {
        let raw = jsonDictionary(from: skill)
        let name = skill.name ?? skill.title ?? stringValue(in: raw, keys: ["displayName", "name", "title"])
        let description = stringValue(in: raw, keys: ["description", "summary"])

        let parts = [name, description].compactMap { value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        print(parts.isEmpty ? "(no summary available)" : parts.joined(separator: " | "))
    }

    static var skillsUsage: String {
        """
        Skills:
          grok skills list [--json|--format json]
          grok skills mine [--json|--format json]
          grok skills user [--json|--format json]
        """
    }

    static var skillsListUsage: String {
        "Usage: grok skills list [--json|--format json] [--debug]"
    }

    static var skillsMineUsage: String {
        "Usage: grok skills mine [--json|--format json] [--debug]"
    }

    static var skillsUserUsage: String {
        "Usage: grok skills user [--json|--format json] [--debug]"
    }
}
