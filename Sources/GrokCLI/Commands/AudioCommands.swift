import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    struct AudioInputRequestOptions {
        let path: String
        let audioFormat: String?
        let refinementLevel: String
    }

    struct ResolvedAudioInput {
        let transcript: String
        let sourcePath: String
        let audioFormat: String
        let refinementLevel: String

        var json: [String: AnyCodable] {
            [
                "kind": AnyCodable("audio"),
                "transcript": AnyCodable(transcript),
                "audio": AnyCodable([
                    "path": AnyCodable(sourcePath),
                    "format": AnyCodable(audioFormat),
                    "refinementLevel": AnyCodable(refinementLevel)
                ])
            ]
        }
    }

    static func parseAudioInputOptions(args: [String], usage: String) throws -> AudioInputRequestOptions {
        var path: String?
        var audioFormat: String?
        var refinementLevel = GrokClient.defaultSpeechRefinementLevel

        var index = 0
        while index < args.count {
            let arg = args[index]
            let option = CLIOptionParsing.nameAndValue(arg)

            switch option.name {
            case "--audio-format":
                let value = try CLIOptionParsing.readValue(option.inlineValue, args: args, index: index, option: "--audio-format")
                audioFormat = value.0
                index = value.1
            case "--refinement-level":
                let value = try CLIOptionParsing.readValue(option.inlineValue, args: args, index: index, option: "--refinement-level")
                refinementLevel = value.0
                index = value.1
            default:
                if arg.hasPrefix("--") {
                    throw GrokError.apiError("Unknown audio option: \(arg)")
                }
                guard path == nil else {
                    throw GrokError.apiError("Usage: \(usage)")
                }
                path = arg
            }

            index += 1
        }

        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("Usage: \(usage)")
        }

        guard !refinementLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("--refinement-level requires a value")
        }

        if let audioFormat, audioFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GrokError.apiError("--audio-format requires a value")
        }

        return AudioInputRequestOptions(
            path: path,
            audioFormat: audioFormat,
            refinementLevel: refinementLevel
        )
    }

    static func resolveAudioInput(
        _ options: AudioInputRequestOptions,
        app: GrokCLIApp
    ) async throws -> ResolvedAudioInput {
        let path = options.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioData: Data
        let sourcePath: String
        let fileName: String?

        if path == "-" {
            audioData = try readStandardInputData()
            sourcePath = "-"
            fileName = nil
        } else {
            let expandedPath = NSString(string: path).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expandedPath)
            do {
                audioData = try Data(contentsOf: fileURL)
            } catch {
                throw GrokError.apiError("Could not read audio file \(path): \(error.localizedDescription)")
            }
            sourcePath = path
            fileName = fileURL.lastPathComponent
        }

        guard !audioData.isEmpty else {
            throw GrokError.apiError(path == "-" ? "Please provide audio bytes on stdin" : "Audio file is empty: \(path)")
        }

        let trimmedAudioFormat = options.audioFormat?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedFormat = trimmedAudioFormat ?? fileName.flatMap { GrokClient.inferAudioFormat(fromFileName: $0) }

        guard let resolvedFormat, !resolvedFormat.isEmpty else {
            throw GrokError.apiError("Could not infer audio format. Pass --audio-format when using stdin or an unknown extension.")
        }

        let client = try app.initializeClient()
        let response = try await client.speechToText(
            audioData: audioData,
            audioFormat: resolvedFormat,
            refinementLevel: options.refinementLevel
        )

        return ResolvedAudioInput(
            transcript: response.text,
            sourcePath: sourcePath,
            audioFormat: resolvedFormat,
            refinementLevel: options.refinementLevel
        )
    }

    static func handleTranscribeCommand(args: [String], exitOnError: Bool = false) async throws {
        let jsonRequested = isJSONRequested(args)
        let quietRequested = args.contains("--quiet")

        if args.count == 1, let first = args.first, isHelpArgument(first) {
            printTranscribeUsage()
            return
        }

        var audioArgs: [String] = []
        var outputFormat = OutputFormat.raw
        var enableDebug = false
        var enableQuiet = false

        var index = 0
        while index < args.count {
            let arg = args[index]
            let nextValue = index + 1 < args.count ? args[index + 1] : nil

            let outputFormatOption = applyOutputFormatOption(arg, nextValue: nextValue)
            if outputFormatOption.missingValue {
                reportTranscribeUsageError("\(arg) requires a format value", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                if exitOnError { exit(with: 2) }
                return
            } else if let invalidValue = outputFormatOption.invalidValue {
                reportTranscribeUsageError("Invalid output format '\(invalidValue)'. Use raw, md, or json.", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                if exitOnError { exit(with: 2) }
                return
            } else if let format = outputFormatOption.format {
                outputFormat = format
                index += outputFormatOption.consumedNext ? 2 : 1
                continue
            }

            if arg == "--debug" {
                enableDebug = true
            } else if arg == "--quiet" {
                enableQuiet = true
            } else {
                audioArgs.append(arg)
            }
            index += 1
        }

        do {
            let options = try parseAudioInputOptions(
                args: audioArgs,
                usage: "grok transcribe [--audio-format <format>] [--refinement-level <level>] <path|->"
            )
            let jsonMode = outputFormat.isJSON
            let app = GrokCLIApp.shared
            app.setQuietMode(enableQuiet && !jsonMode)
            app.setDebugMode(enableDebug && !jsonMode && !enableQuiet)

            if !jsonMode && !enableQuiet {
                print("Transcribing audio...".cyan)
            }

            let resolved = try await resolveAudioInput(options, app: app)

            if jsonMode {
                try printJSONResult(
                    command: "transcribe",
                    category: "transcription",
                    data: AnyCodable(resolved.json),
                    debug: enableDebug
                )
            } else {
                CLIOutput.stdout(resolved.transcript, terminator: resolved.transcript.hasSuffix("\n") ? "" : "\n")
            }
        } catch {
            if jsonRequested || outputFormat.isJSON {
                printJSONError(command: "transcribe", error: error, exitCode: 1, debug: enableDebug)
            } else {
                reportTranscribeUsageError(error.localizedDescription, jsonRequested: false, exitOnError: exitOnError, toStderr: enableQuiet)
            }
            if exitOnError {
                exit(with: 1)
            }
        }
    }

    static func reportTranscribeUsageError(
        _ message: String,
        jsonRequested: Bool,
        exitOnError: Bool,
        toStderr: Bool = false
    ) {
        if jsonRequested {
            printJSONError(
                command: "transcribe",
                message: message,
                code: "usage_error",
                exitCode: 2
            )
        } else if toStderr {
            CLIOutput.stderr("Error: \(message)")
        } else {
            print("Error: \(message)".red)
        }
    }
}
