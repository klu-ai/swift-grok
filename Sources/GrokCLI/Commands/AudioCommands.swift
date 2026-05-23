import Foundation
import GrokClient
import Rainbow
#if os(macOS)
import CoreAudio
#endif

extension GrokCLI {
    private static let audioRecordingFixtureEnvironmentKey = "GROK_CLI_AUDIO_RECORD_FIXTURE"
    private static let audioRecordingDeviceEnvironmentKey = "GROK_CLI_AUDIO_DEVICE"

    struct AudioInputRequestOptions {
        let path: String
        let audioFormat: String?
        let refinementLevel: String
    }

    struct ParsedAudioInputOptions {
        let path: String?
        let audioFormat: String?
        let refinementLevel: String
    }

    struct InteractiveAudioInputOptions {
        let sendImmediately: Bool
        let input: ParsedAudioInputOptions
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
        let parsed = try parseOptionalAudioInputOptions(args: args, usage: usage)

        guard let path = parsed.path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("Usage: \(usage)")
        }

        return AudioInputRequestOptions(
            path: path,
            audioFormat: parsed.audioFormat,
            refinementLevel: parsed.refinementLevel
        )
    }

    static func parseOptionalAudioInputOptions(args: [String], usage: String) throws -> ParsedAudioInputOptions {
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

        guard !refinementLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("--refinement-level requires a value")
        }

        if let audioFormat, audioFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GrokError.apiError("--audio-format requires a value")
        }

        return ParsedAudioInputOptions(
            path: path,
            audioFormat: audioFormat,
            refinementLevel: refinementLevel
        )
    }

    static func parseInteractiveAudioInputOptions(args: [String], usage: String) throws -> InteractiveAudioInputOptions {
        var audioArgs = args
        var sendImmediately = false

        if let first = audioArgs.first?.lowercased() {
            switch first {
            case "send":
                sendImmediately = true
                audioArgs.removeFirst()
            case "file":
                audioArgs.removeFirst()
            case "record":
                audioArgs.removeFirst()
                if audioArgs.contains(where: { !$0.hasPrefix("--") }) {
                    throw GrokError.apiError("Usage: \(usage)")
                }
            default:
                break
            }
        }

        let parsed = try parseOptionalAudioInputOptions(args: audioArgs, usage: usage)
        return InteractiveAudioInputOptions(sendImmediately: sendImmediately, input: parsed)
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

        let response: GrokSpeechToTextResponse
        if app.usesXAIOAuthMode() {
            let uploadName = fileName ?? "audio.\(resolvedFormat)"
            response = try await app.transcribeWithXAIOAuth(
                audioData: audioData,
                fileName: uploadName,
                mimeType: audioMimeType(for: resolvedFormat)
            )
        } else {
            let client = try app.initializeClient()
            response = try await client.speechToText(
                audioData: audioData,
                audioFormat: resolvedFormat,
                refinementLevel: options.refinementLevel
            )
        }

        return ResolvedAudioInput(
            transcript: response.text,
            sourcePath: sourcePath,
            audioFormat: resolvedFormat,
            refinementLevel: options.refinementLevel
        )
    }

    static func audioMimeType(for format: String) -> String {
        switch format.lowercased() {
        case "mp3", "mpeg", "mpga":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        case "ogg", "oga":
            return "audio/ogg"
        case "flac":
            return "audio/flac"
        default:
            return "audio/\(format.lowercased())"
        }
    }

    static func resolveInteractiveAudioInput(
        _ options: InteractiveAudioInputOptions,
        app: GrokCLIApp,
        waitForRecordingStop: () -> Void
    ) async throws -> ResolvedAudioInput {
        if let path = options.input.path {
            let request = AudioInputRequestOptions(
                path: path,
                audioFormat: options.input.audioFormat,
                refinementLevel: options.input.refinementLevel
            )
            return try await resolveAudioInput(request, app: app)
        }

        let requestedFormat = options.input.audioFormat?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let requestedFormat, requestedFormat != "webm" {
            throw GrokError.apiError("Recording creates webm audio; omit --audio-format or use --audio-format webm.")
        }

        let recordingURL = try recordAudioToTemporaryWebM(waitForStop: waitForRecordingStop)
        return try await resolveAudioInput(
            AudioInputRequestOptions(
                path: recordingURL.path,
                audioFormat: "webm",
                refinementLevel: options.input.refinementLevel
            ),
            app: app
        )
    }

    static func recordAudioToTemporaryWebM(waitForStop: () -> Void) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-audio-\(UUID().uuidString)")
            .appendingPathExtension("webm")

        if let fixturePath = ProcessInfo.processInfo.environment[audioRecordingFixtureEnvironmentKey],
           !fixturePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fixtureURL = URL(fileURLWithPath: NSString(string: fixturePath).expandingTildeInPath)
            do {
                try FileManager.default.copyItem(at: fixtureURL, to: outputURL)
                return outputURL
            } catch {
                throw GrokError.apiError("Could not use recording fixture \(fixturePath): \(error.localizedDescription)")
            }
        }

        #if os(macOS)
        guard let ffmpegPath = findExecutableInPATH(named: "ffmpeg") else {
            throw GrokError.apiError("Recording from /audio requires ffmpeg on macOS. Install it with `brew install ffmpeg`, then run /audio again.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        let audioDevice = preferredAVFoundationAudioDeviceSpecifier()
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-nostdin",
            "-f", "avfoundation",
            "-i", avFoundationAudioInputArgument(for: audioDevice),
            "-vn",
            "-ac", "1",
            "-ar", "48000",
            "-c:a", "libopus",
            "-b:a", "64k",
            "-f", "webm",
            "-y",
            outputURL.path
        ]

        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GrokError.apiError("Could not start audio recording: \(error.localizedDescription)")
        }

        waitForStop()

        if process.isRunning {
            process.interrupt()
        }
        process.waitUntilExit()

        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 0 {
            return outputURL
        }

        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderrText?.isEmpty == false ? ": \(stderrText!)" : "."
        throw GrokError.apiError("Audio recording failed\(detail)")
        #else
        throw GrokError.apiError("Recording from /audio is currently supported on macOS with ffmpeg installed.")
        #endif
    }

    static func findExecutableInPATH(named executableName: String) -> String? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executableName).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func preferredAVFoundationAudioDeviceSpecifier() -> String {
        if let override = ProcessInfo.processInfo.environment[audioRecordingDeviceEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }

        #if os(macOS)
        if let deviceName = defaultAudioInputDeviceName(),
           let specifier = avFoundationSpecifierForDefaultAudioDeviceName(deviceName) {
            return specifier
        }
        #endif

        return "default"
    }

    static func avFoundationSpecifierForDefaultAudioDeviceName(_ deviceName: String) -> String? {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !trimmed.contains(":") else {
            return nil
        }
        guard let firstScalar = trimmed.unicodeScalars.first,
              !CharacterSet.decimalDigits.contains(firstScalar) else {
            return nil
        }
        return trimmed
    }

    static func avFoundationAudioInputArgument(for deviceSpecifier: String) -> String {
        let trimmed = deviceSpecifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(":") {
            return trimmed
        }
        return ":\(trimmed.isEmpty ? "default" : trimmed)"
    }

    #if os(macOS)
    static func defaultAudioInputDeviceName() -> String? {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        )
        guard deviceStatus == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &unmanagedName
        )
        guard nameStatus == noErr,
              let deviceName = unmanagedName?.takeUnretainedValue() as String? else {
            return nil
        }

        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    #endif

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
                reportTranscribeUsageError("Invalid output format '\(invalidValue)'. Use raw or json.", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                if exitOnError { exit(with: 2) }
                return
            } else if let format = outputFormatOption.format {
                guard format != .markdown else {
                    reportTranscribeUsageError("Invalid output format 'markdown'. Use raw or json.", jsonRequested: jsonRequested, exitOnError: exitOnError, toStderr: quietRequested)
                    if exitOnError { exit(with: 2) }
                    return
                }
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
            try validateTranscribeAudioFormatBeforeProgress(options)
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
            let exitCode = transcribeExitCode(for: error)
            if jsonRequested || outputFormat.isJSON {
                printJSONError(command: "transcribe", error: error, exitCode: exitCode, debug: enableDebug)
            } else {
                reportTranscribeUsageError(error.localizedDescription, jsonRequested: false, exitOnError: exitOnError, toStderr: enableQuiet)
            }
            if exitOnError {
                exit(with: exitCode)
            }
        }
    }

    private static func transcribeExitCode(for error: Error) -> Int32 {
        let message = error.localizedDescription
        let usagePrefixes = [
            "Usage:",
            "--audio-format requires",
            "--refinement-level requires",
            "Unknown audio option:",
            "Could not infer audio format.",
            "Please provide audio bytes on stdin",
            "Audio file is empty:",
            "Could not read audio file "
        ]

        return usagePrefixes.contains { message.hasPrefix($0) } ? 2 : 1
    }

    private static func validateTranscribeAudioFormatBeforeProgress(_ options: AudioInputRequestOptions) throws {
        if let audioFormat = options.audioFormat?.trimmingCharacters(in: .whitespacesAndNewlines),
           !audioFormat.isEmpty {
            return
        }

        guard options.path != "-" else {
            throw GrokError.apiError("Could not infer audio format. Pass --audio-format when using stdin or an unknown extension.")
        }

        let expandedPath = NSString(string: options.path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        let fileName = fileURL.lastPathComponent
        guard GrokClient.inferAudioFormat(fromFileName: fileName) != nil else {
            throw GrokError.apiError("Could not infer audio format. Pass --audio-format when using stdin or an unknown extension.")
        }

        let fileAttributes: [FileAttributeKey: Any]
        do {
            fileAttributes = try FileManager.default.attributesOfItem(atPath: expandedPath)
        } catch {
            throw GrokError.apiError("Could not read audio file \(options.path): \(error.localizedDescription)")
        }

        if let size = fileAttributes[.size] as? NSNumber, size.intValue == 0 {
            throw GrokError.apiError("Audio file is empty: \(options.path)")
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
