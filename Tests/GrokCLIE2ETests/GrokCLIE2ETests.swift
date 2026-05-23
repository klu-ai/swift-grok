import Foundation
import GrokClient
import XCTest
@testable import GrokCLI

#if canImport(Network)
import Network

#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class GrokCLIE2ETests: XCTestCase {
    func testTopLevelStaticCommandsAndReservedEdges() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let help = try environment.run(["help"])
        XCTAssertEqual(help.status, 0)
        XCTAssertContains(help.cleanOutput, "Usage: grok [command] [options]")
        XCTAssertContains(help.cleanOutput, "message <text>")

        let versionRequestCount = server.requests().count
        let version = try environment.run(["--version"])
        XCTAssertEqual(version.status, 0)
        XCTAssertContains(version.cleanOutput, "SwiftGrok CLI")
        XCTAssertEqual(server.requests().count, versionRequestCount)

        let models = try environment.run(["models"])
        XCTAssertEqual(models.status, 0)
        XCTAssertContains(models.cleanOutput, "Available web modes:")
        XCTAssertContains(models.cleanOutput, "Grok 4.3 (beta)")

        let modeRequestCount = server.requests(matchingPath: "/rest/modes", method: "POST").count
        let modelsHelp = try environment.run(["models", "--help"])
        XCTAssertEqual(modelsHelp.status, 0)
        XCTAssertContains(modelsHelp.cleanOutput, "Usage: grok models")
        XCTAssertContains(modelsHelp.cleanOutput, "Available web modes:")
        XCTAssertEqual(server.requests(matchingPath: "/rest/modes", method: "POST").count, modeRequestCount)

        let modes = try environment.run(["modes"])
        XCTAssertEqual(modes.status, 0)
        XCTAssertContains(modes.cleanOutput, "Available web modes:")

        let auth = try environment.run(["auth", "help"])
        XCTAssertEqual(auth.status, 0)
        XCTAssertContains(auth.cleanOutput, "Auth commands:")
        XCTAssertContains(auth.cleanOutput, "oauth")

        let authFlagHelp = try environment.run(["auth", "--help"])
        XCTAssertEqual(authFlagHelp.status, 0)
        XCTAssertContains(authFlagHelp.cleanOutput, "Auth commands:")
        XCTAssertFalse(authFlagHelp.cleanOutput.contains("Error:"))

        let chatHelp = try environment.run(["chat", "--help"])
        XCTAssertEqual(chatHelp.status, 0)
        XCTAssertContains(chatHelp.cleanOutput, "Usage: grok chat")
        XCTAssertFalse(chatHelp.cleanOutput.contains("Calling Grok API"))

        let messageHelp = try environment.run(["message", "help"])
        XCTAssertEqual(messageHelp.status, 0)
        XCTAssertContains(messageHelp.cleanOutput, "Usage: grok message")
        XCTAssertFalse(messageHelp.cleanOutput.contains("Calling Grok API"))

        let listHelp = try environment.run(["list", "--help"])
        XCTAssertEqual(listHelp.status, 0)
        XCTAssertContains(listHelp.cleanOutput, "Usage: grok list")
        XCTAssertFalse(listHelp.cleanOutput.contains("Fetching your saved conversations"))

        let missingMessage = try environment.run(["message"])
        XCTAssertEqual(missingMessage.status, 2)
        XCTAssertContains(missingMessage.cleanOutput, "Error: Please provide a message to send")

        let testCommand = try environment.run(["test", "hello"])
        XCTAssertEqual(testCommand.status, 0)
        XCTAssertContains(testCommand.cleanOutput, "Test command executed successfully!")
        XCTAssertContains(testCommand.cleanOutput, #"Message provided: "hello""#)

        let testCommandHelp = try environment.run(["test", "--help"])
        XCTAssertEqual(testCommandHelp.status, 0)
        XCTAssertContains(testCommandHelp.cleanOutput, "Usage: grok test")
        XCTAssertFalse(testCommandHelp.cleanOutput.contains("Message provided"))

        let chatCommand = try environment.run(["chat", "hello"], input: "/quit\n")
        XCTAssertEqual(chatCommand.status, 0)
        XCTAssertContains(chatCommand.cleanOutput, "Sending message: hello")
        XCTAssertFalse(chatCommand.cleanOutput.contains("Sending message: chat hello"))

        let topLevelHelpFlag = try environment.run(["--help"])
        XCTAssertEqual(topLevelHelpFlag.status, 0)
        XCTAssertContains(topLevelHelpFlag.cleanOutput, "Usage: grok [command] [options]")
    }

    func testInitialChatMessageContinuesWithoutPromptBanner() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["chat", "hello"], input: "follow up\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Sending message: hello")
        XCTAssertFalse(run.cleanOutput.contains("Enter your message:"))
        XCTAssertFalse(run.cleanOutput.contains("Connected to Grok!"))
        XCTAssertFalse(run.cleanOutput.contains("Chat mode |"))
        XCTAssertFalse(run.cleanOutput.contains("Conversation ID:"))

        let requests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertTrue(requests.contains { $0.path == "/rest/app-chat/conversations/new" && $0.jsonString("message") == "hello" })
        XCTAssertTrue(requests.contains { $0.path.hasSuffix("/responses") && $0.jsonString("message") == "follow up" })
    }

    func testInteractiveStartupUsesCurrentSubscriptionDisplayName() throws {
        let server = try MockGrokServer(subscriptionResponse: [
            "subscriptions": [[
                "subscriptionTier": "TIER_SUPERGROK_HEAVY",
                "status": "active"
            ]]
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Connected to SuperGrok Heavy!")
        XCTAssertEqual(server.requests(matchingPath: "/rest/subscriptions", method: "GET").count, 1)
    }

    func testMessageCommandCoversOptionsStreamingAndModelAliases() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let nonStreaming = try environment.run([
            "message",
            "--debug",
            "--reasoning",
            "--deep-search",
            "--no-search",
            "--markdown",
            "--private",
            "--no-custom-instructions",
            "--model",
            "expert",
            "hello",
            "there"
        ])

        XCTAssertEqual(nonStreaming.status, 0)
        XCTAssertContains(nonStreaming.cleanOutput, "Debug: Message = \"hello there\"")
        XCTAssertContains(nonStreaming.cleanOutput, "Debug: Model = Expert (expert)")
        XCTAssertContains(nonStreaming.cleanOutput, "Mock final response")

        let messageRequests = server.requests(matchingPath: "/rest/app-chat/conversations/new")
        XCTAssertFalse(messageRequests.isEmpty)
        XCTAssertEqual(messageRequests.last?.jsonString("message"), "hello there")
        XCTAssertEqual(messageRequests.last?.jsonString("modeId"), "expert")
        XCTAssertEqual(messageRequests.last?.jsonBool("disableSearch"), false)
        XCTAssertEqual(messageRequests.last?.jsonBool("linkQuery"), false)
        XCTAssertEqual(messageRequests.last?.jsonBool("temporary"), true)
        XCTAssertNil(messageRequests.last?.json["customPersonality"])
        XCTAssertContains(nonStreaming.cleanOutput, "--reasoning is deprecated and ignored")
        XCTAssertContains(nonStreaming.cleanOutput, "--deep-search is deprecated and ignored")
        XCTAssertContains(nonStreaming.cleanOutput, "--no-search is deprecated and ignored")
        XCTAssertContains(nonStreaming.cleanOutput, "--no-custom-instructions is deprecated and ignored")

        let streaming = try environment.run([
            "message",
            "--stream",
            "--mode=grok-4.3-beta",
            "stream",
            "please"
        ])

        XCTAssertEqual(streaming.status, 0)
        XCTAssertContains(streaming.cleanOutput, "Mock streamed ")
        XCTAssertContains(streaming.cleanOutput, "answer")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new").last?.jsonString("modeId"), "grok-420-computer-use-sa")

        let rawMode = try environment.run(["message", "--model=custom-mode-id", "raw", "mode"])
        XCTAssertEqual(rawMode.status, 0)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new").last?.jsonString("modeId"), "custom-mode-id")

        let requestCountBeforeMissingModel = server.requests(matchingPath: "/rest/app-chat/conversations/new").count
        let missingModelValue = try environment.run(["message", "--model", "--json", "hello"])
        XCTAssertEqual(missingModelValue.status, 2)
        XCTAssertContains(missingModelValue.cleanOutput, "--model requires a model value")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new").count, requestCountBeforeMissingModel)
    }

    func testMessageRawQuietReadsMultilinePromptFromStdin() throws {
        let answer = "stdin answer"
        let prompt = "first line\nsecond line\n\nthird line\n"
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--raw", "--quiet"], input: prompt)

        XCTAssertEqual(run.status, 0)
        let request = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last)
        XCTAssertEqual(request.jsonString("message"), prompt)
        assertAnswerOnlyStdout(run.stdout, equals: answer)
    }

    func testMessageRawQuietPromptFileReadsExactContents() throws {
        let answer = "file answer"
        let prompt = "file line one\nfile line two\n\nfile line four\n"
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)
        let promptFile = environment.scratchURL.appendingPathComponent("prompt.txt")
        try prompt.write(to: promptFile, atomically: true, encoding: .utf8)

        let run = try environment.run(["message", "--raw", "--quiet", "--prompt-file", promptFile.path])

        XCTAssertEqual(run.status, 0)
        let request = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last)
        XCTAssertEqual(request.jsonString("message"), prompt)
        assertAnswerOnlyStdout(run.stdout, equals: answer)
    }

    func testMessageUploadsFileAndAttachesExistingFileId() throws {
        let answer = "document answer"
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)
        let pdfURL = environment.scratchURL.appendingPathComponent("paper.pdf")
        let pdfData = Data("%PDF-1.4 test document".utf8)
        try pdfData.write(to: pdfURL)

        let run = try environment.run([
            "message",
            "--file",
            pdfURL.path,
            "--attach",
            "existing-file-id",
            "--raw",
            "--quiet",
            "What is novel here?"
        ])

        XCTAssertEqual(run.status, 0)
        let uploadRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/upload-file", method: "POST").last)
        XCTAssertEqual(uploadRequest.jsonString("fileName"), "paper.pdf")
        XCTAssertEqual(uploadRequest.jsonString("fileMimeType"), "application/pdf")
        XCTAssertEqual(uploadRequest.jsonString("content"), pdfData.base64EncodedString())

        let chatRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last)
        XCTAssertEqual(chatRequest.jsonString("message"), "What is novel here?")
        let fileAttachments = try XCTUnwrap(chatRequest.json["fileAttachments"] as? [Any])
        XCTAssertEqual(fileAttachments.compactMap { $0 as? String }, ["existing-file-id", "uploaded-file-1"])
        assertAnswerOnlyStdout(run.stdout, equals: answer)
    }

    func testMessageAudioTranscribesThenSendsTranscript() throws {
        let answer = "audio answer"
        let transcript = "mock audio transcript"
        let server = try MockGrokServer(finalMessage: answer, transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("note.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let run = try environment.run(["message", "--audio", audioURL.path, "--raw", "--quiet"])

        XCTAssertEqual(run.status, 0)
        let transcription = try XCTUnwrap(server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST").last)
        XCTAssertEqual(transcription.jsonString("audioFormat"), "webm")
        XCTAssertEqual(transcription.jsonString("audioBase64"), Data("audio bytes".utf8).base64EncodedString())
        let chatRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last)
        XCTAssertEqual(chatRequest.jsonString("message"), transcript)
        assertAnswerOnlyStdout(run.stdout, equals: answer)
    }

    func testTranscribeCommandPrintsTranscriptOnly() throws {
        let transcript = "standalone transcript"
        let server = try MockGrokServer(transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("clip.wav")
        try Data("wav bytes".utf8).write(to: audioURL)

        let run = try environment.run(["transcribe", "--raw", "--quiet", audioURL.path])

        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.stdout, transcript + "\n")
        XCTAssertTrue(run.stderr.isEmpty)
        XCTAssertEqual(server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST").count, 1)
        XCTAssertTrue(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").isEmpty)
    }

    func testMessageAudioJSONIncludesInputMetadata() throws {
        let transcript = "json audio transcript"
        let server = try MockGrokServer(finalMessage: "json answer", transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("json-note.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let run = try environment.run(["message", "--audio", audioURL.path, "--json"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)

        let data = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "message",
            category: "assistant_response"
        )
        XCTAssertEqual(data["message"] as? String, "json answer")

        let input = try XCTUnwrap(data["input"] as? [String: Any])
        XCTAssertEqual(input["kind"] as? String, "audio")
        XCTAssertEqual(input["transcript"] as? String, transcript)
        let audio = try XCTUnwrap(input["audio"] as? [String: Any])
        XCTAssertEqual(audio["path"] as? String, audioURL.path)
        XCTAssertEqual(audio["format"] as? String, "webm")
    }

    func testMessageAudioStreamingJSONEmitsTranscriptionBeforeRequest() throws {
        let transcript = "stream audio transcript"
        let server = try MockGrokServer(finalMessage: "stream answer", transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("stream-note.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let run = try environment.run(["message", "--audio", audioURL.path, "--stream", "--json"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)

        let events = try jsonLines(from: run)
        XCTAssertGreaterThanOrEqual(events.count, 4)
        for (index, event) in events.enumerated() {
            XCTAssertEqual(event["schema"] as? String, "grok.cli.event.v1")
            XCTAssertEqual(event["sequence"] as? Int, index + 1)
        }

        XCTAssertEqual(events[0]["event"] as? String, "transcription")
        let transcriptionData = try XCTUnwrap(events[0]["data"] as? [String: Any])
        XCTAssertEqual(transcriptionData["kind"] as? String, "audio")
        XCTAssertEqual(transcriptionData["transcript"] as? String, transcript)

        XCTAssertEqual(events[1]["event"] as? String, "request")
        let requestData = try XCTUnwrap(events[1]["data"] as? [String: Any])
        XCTAssertEqual(requestData["message"] as? String, transcript)
        XCTAssertNotNil(requestData["input"] as? [String: Any])

        let finalEvent = try XCTUnwrap(events.last { $0["event"] as? String == "assistant_final" })
        let finalData = try XCTUnwrap(finalEvent["data"] as? [String: Any])
        XCTAssertNotNil(finalData["input"] as? [String: Any])
    }

    func testChatAudioUsesTranscriptAsInitialMessage() throws {
        let answer = "chat audio answer"
        let transcript = "chat audio transcript"
        let server = try MockGrokServer(streamTokens: [answer], finalMessage: answer, transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("chat-note.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let run = try environment.run(["chat", "--audio", audioURL.path, "--raw", "--quiet"], input: "/quit\n")

        XCTAssertEqual(run.status, 0)
        let transcription = try XCTUnwrap(server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST").last)
        XCTAssertEqual(transcription.jsonString("audioFormat"), "webm")
        let chatRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last)
        XCTAssertEqual(chatRequest.jsonString("message"), transcript)
        assertNoQuietUI(in: run.stdout)
        XCTAssertContains(run.stdout, answer)
    }

    func testTranscribeCommandJSONIncludesAudioMetadata() throws {
        let transcript = "standalone json transcript"
        let server = try MockGrokServer(transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("clip.m4a")
        try Data("m4a bytes".utf8).write(to: audioURL)

        let run = try environment.run(["transcribe", "--json", audioURL.path])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        let data = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "transcribe",
            category: "transcription"
        )
        XCTAssertEqual(data["kind"] as? String, "audio")
        XCTAssertEqual(data["transcript"] as? String, transcript)
        let audio = try XCTUnwrap(data["audio"] as? [String: Any])
        XCTAssertEqual(audio["path"] as? String, audioURL.path)
        XCTAssertEqual(audio["format"] as? String, "m4a")
        XCTAssertTrue(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").isEmpty)
    }

    func testTranscribeCommandRejectsMarkdownOutputFormat() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("clip.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let markdownFlag = try environment.run(["transcribe", "--markdown", audioURL.path])
        XCTAssertNotEqual(markdownFlag.status, 0)
        XCTAssertContains(markdownFlag.cleanOutput, "Use raw or json")

        let markdownFormat = try environment.run(["transcribe", "--format", "md", audioURL.path])
        XCTAssertNotEqual(markdownFormat.status, 0)
        XCTAssertContains(markdownFormat.cleanOutput, "Use raw or json")
        XCTAssertTrue(server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST").isEmpty)
    }

    func testTranscribeCommandUsageErrorsReturnStatusTwo() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let unknownAudioURL = environment.scratchURL.appendingPathComponent("clip.audio")
        try Data("audio bytes".utf8).write(to: unknownAudioURL)

        let missingPath = try environment.run(["transcribe"])
        assertUsageError(missingPath, mentions: ["transcribe", "path"])

        let unknownFormat = try environment.run(["transcribe", unknownAudioURL.path])
        assertUsageError(unknownFormat, mentions: ["audio format"])
        XCTAssertFalse(unknownFormat.cleanOutput.contains("Transcribing audio"))

        let missingAudioURL = environment.scratchURL.appendingPathComponent("missing.wav")
        let missingFile = try environment.run(["transcribe", missingAudioURL.path])
        assertUsageError(missingFile, mentions: ["Could not read audio file"])
        XCTAssertFalse(missingFile.cleanOutput.contains("Transcribing audio"))

        let unknownFormatJSON = try environment.run(["transcribe", "--json", unknownAudioURL.path])
        XCTAssertEqual(unknownFormatJSON.status, 2)
        let envelope = try jsonObject(from: unknownFormatJSON)
        XCTAssertEqual(envelope["ok"] as? Bool, false)
        XCTAssertEqual((envelope["error"] as? [String: Any])?["code"] as? String, "api_error")
        XCTAssertEqual((envelope["error"] as? [String: Any])?["exitCode"] as? Int, 2)

        XCTAssertTrue(server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST").isEmpty)
    }

    func testInteractiveAudioCommandsTranscribeAndSend() throws {
        let answer = "interactive audio answer"
        let transcript = "interactive audio transcript"
        let server = try MockGrokServer(streamTokens: [answer], finalMessage: answer, transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("interactive-note.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let run = try environment.run(
            ["chat", "--raw", "--quiet"],
            input: "/audio \(audioURL.path)\n/audio file \(audioURL.path)\n/audio send \(audioURL.path)\n/audio-send \(audioURL.path)\n/transcribe \(audioURL.path)\n/quit\n"
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST").count, 5)
        let chatMessages = server.requests(method: "POST")
            .filter { $0.path.contains("/rest/app-chat/conversations") }
            .compactMap { $0.jsonString("message") }
        XCTAssertEqual(chatMessages.filter { $0 == transcript }.count, 4)
        XCTAssertContains(run.stdout, answer)
        XCTAssertContains(run.stdout, transcript)
    }

    func testInteractiveAudioSendPrintsTranscriptBeforeActivity() throws {
        let transcript = "send this transcript"
        let server = try MockGrokServer(
            streamLines: [
                #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Thinking about your request","isThinking":true}}}"#,
                #"{"result":{"response":{"responseId":"resp-e2e","token":"audio answer"}}}"#,
                #"{"result":{"response":{"modelResponse":{"message":"audio answer","responseId":"resp-e2e"}}}}"#
            ],
            finalMessage: "audio answer",
            transcriptionText: transcript
        )
        let environment = try TestEnvironment(server: server)
        let audioURL = environment.scratchURL.appendingPathComponent("send-note.webm")
        try Data("audio bytes".utf8).write(to: audioURL)

        let run = try environment.run(
            ["chat", "--raw"],
            input: "/audio send \(audioURL.path)\n/quit\n"
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "[transcript] \(transcript)")
        XCTAssertFalse(run.cleanOutput.contains("[thinking] Thinking about your request"))
        XCTAssertContains(run.cleanOutput, "Grok\naudio answer")

        let transcriptRange = try XCTUnwrap(run.cleanOutput.range(of: "[transcript] \(transcript)"))
        let answerRange = try XCTUnwrap(run.cleanOutput.range(of: "Grok\naudio answer"))
        XCTAssertLessThan(transcriptRange.lowerBound, answerRange.lowerBound)
    }

    func testInteractiveAudioRecordsWhenNoPathIsProvided() throws {
        let answer = "recorded audio answer"
        let transcript = "recorded audio transcript"
        let server = try MockGrokServer(streamTokens: [answer], finalMessage: answer, transcriptionText: transcript)
        let environment = try TestEnvironment(server: server)
        let fixtureURL = environment.scratchURL.appendingPathComponent("recording-fixture.webm")
        try Data("recorded bytes".utf8).write(to: fixtureURL)

        let run = try environment.run(
            ["chat", "--raw", "--quiet"],
            input: "/audio\n/audio send\n/quit\n",
            extraEnvironment: ["GROK_CLI_AUDIO_RECORD_FIXTURE": fixtureURL.path]
        )

        XCTAssertEqual(run.status, 0)
        let transcriptionRequests = server.requests(matchingPath: "/rest/voice/speech-to-text", method: "POST")
        XCTAssertEqual(transcriptionRequests.count, 2)
        for request in transcriptionRequests {
            XCTAssertEqual(request.jsonString("audioFormat"), "webm")
            XCTAssertEqual(request.jsonString("audioBase64"), Data("recorded bytes".utf8).base64EncodedString())
        }
        let chatMessages = server.requests(method: "POST")
            .filter { $0.path.contains("/rest/app-chat/conversations") }
            .compactMap { $0.jsonString("message") }
        XCTAssertEqual(chatMessages.filter { $0 == transcript }.count, 2)
        XCTAssertContains(run.stdout, answer)
    }

    func testMessagePromptInputUsageErrors() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let missingPromptFileValue = try environment.run(["message", "--raw", "--quiet", "--prompt-file"])
        assertUsageError(missingPromptFileValue, mentions: ["prompt-file"])

        let missingPath = environment.scratchURL.appendingPathComponent("missing-prompt.txt")
        let missingFile = try environment.run(["message", "--raw", "--quiet", "--prompt-file", missingPath.path])
        assertUsageError(missingFile, mentions: ["prompt-file", missingPath.lastPathComponent])

        let promptFile = environment.scratchURL.appendingPathComponent("inline-conflict-prompt.txt")
        try "from file".write(to: promptFile, atomically: true, encoding: .utf8)
        let promptFileWithInlineArgs = try environment.run([
            "message",
            "--raw",
            "--quiet",
            "--prompt-file",
            promptFile.path,
            "inline"
        ])
        assertUsageError(promptFileWithInlineArgs, mentions: ["prompt-file", "inline"])

        let audioURL = environment.scratchURL.appendingPathComponent("conflict.webm")
        try Data("audio bytes".utf8).write(to: audioURL)
        let audioWithInlineArgs = try environment.run([
            "message",
            "--raw",
            "--quiet",
            "--audio",
            audioURL.path,
            "inline"
        ])
        assertUsageError(audioWithInlineArgs, mentions: ["audio", "inline", "exclusive"])

        let emptyPipedStdin = try environment.run(["message", "--raw", "--quiet"], input: "")
        assertUsageError(emptyPipedStdin, mentions: ["stdin"])

        XCTAssertTrue(server.requests(method: "POST").isEmpty)
    }

    func testMessageRawQuietInlineMessageEmitsCleanAnswerOnlyStdout() throws {
        let answer = "quiet inline answer"
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--raw", "--quiet", "hello"])

        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last?.jsonString("message"), "hello")
        assertAnswerOnlyStdout(run.stdout, equals: answer)

        let leadingOptions = try environment.run(["--quiet", "--raw", "message", "hello"])

        XCTAssertEqual(leadingOptions.status, 0)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last?.jsonString("message"), "hello")
        assertAnswerOnlyStdout(leadingOptions.stdout, equals: answer)
    }

    func testChatRawQuietPipedInputCreatesThenContinuesConversation() throws {
        let answer = "quiet chat answer"
        let server = try MockGrokServer(streamTokens: [answer], finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["chat", "--raw", "--quiet"], input: "first\nsecond\n/quit\n")

        XCTAssertEqual(run.status, 0)
        let createRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").first)
        XCTAssertEqual(createRequest.jsonString("message"), "first")

        let continueRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").first)
        XCTAssertEqual(continueRequest.jsonString("message"), "second")

        assertNoQuietUI(in: run.stdout)
        XCTAssertEqual(occurrences(of: answer, in: run.stdout), 2)
    }

    func testInteractiveListSelectionResumesConversationForFollowUp() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat"],
            input: "/resume\n1\ncontinue loaded thread\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue loaded thread")
        XCTAssertEqual(followUp.jsonString("parentResponseId"), "resp-e2e")
    }

    func testInteractiveResumeSwitchesToLoadedConversationMode() throws {
        let server = try MockGrokServer(loadedAssistantMetadata: ["modeId": "expert"])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--model", "fast"],
            input: "/resume\n1\ncontinue with resumed model\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Model: Expert (expert)")
        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue with resumed model")
        XCTAssertEqual(followUp.jsonString("modeId"), "expert")
    }

    func testInteractiveSearchSelectionResumesConversationForFollowUp() throws {
        let server = try MockGrokServer(loadedAssistantMetadata: ["modeId": "expert"])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--model", "fast"],
            input: "/search important thread\n1\ncontinue search result\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Mock Conversation")

        let listRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations", method: "GET").last)
        XCTAssertContains(listRequest.target, "pageSize=60")
        XCTAssertContains(listRequest.target, "searchQuery=important%20thread")

        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue search result")
        XCTAssertEqual(followUp.jsonString("parentResponseId"), "resp-e2e")
        XCTAssertEqual(followUp.jsonString("modeId"), "expert")
    }

    func testInteractiveSearchWithoutQueryShowsUsageWithoutListingConversations() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat"],
            input: "/search\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Usage: /search <query>")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations", method: "GET").count, 0)
    }

    func testInteractiveResumeMapsLoadedConversationModelDisplayName() throws {
        let server = try MockGrokServer(loadedAssistantMetadata: [
            "model": ["displayName": "Grok 4.3 (beta)"]
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--model", "fast"],
            input: "/resume\n1\ncontinue with display model\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Model: Grok 4.3 (beta) (grok-420-computer-use-sa)")
        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue with display model")
        XCTAssertEqual(followUp.jsonString("modeId"), "grok-420-computer-use-sa")
    }

    func testInteractiveResumeMapsLiveScalarModelMetadata() throws {
        let server = try MockGrokServer(loadedAssistantMetadata: [
            "model": "grok-420-computer-use-sa",
            "metadata": [
                "request_metadata": [
                    "mode": "grok-4-3",
                    "model": "grok-420-computer-use-sa"
                ],
                "llm_info": [
                    "modelHash": "redacted"
                ]
            ]
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--model", "fast"],
            input: "/resume\n1\ncontinue with live metadata\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Model: Grok 4.3 (beta) (grok-420-computer-use-sa)")
        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue with live metadata")
        XCTAssertEqual(followUp.jsonString("modeId"), "grok-420-computer-use-sa")
    }

    func testInteractiveResumeWithoutModelMetadataKeepsCurrentMode() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--model", "expert"],
            input: "/resume\n1\ncontinue without metadata\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(run.cleanOutput.contains("Model: "))
        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue without metadata")
        XCTAssertEqual(followUp.jsonString("modeId"), "expert")
    }

    func testInteractiveGoalAfterResumeContinuesFromLeafAssistantResponse() throws {
        let server = try MockGrokServer(loadedResponses: [
            [
                "responseId": "resp-leaf",
                "message": "Latest assistant response",
                "sender": "assistant",
                "createTime": "2026-05-13T00:00:03Z",
                "parentResponseId": "resp-user-2",
                "model": "grok-420-computer-use-sa"
            ],
            [
                "responseId": "resp-user-2",
                "message": "Second user response",
                "sender": "human",
                "createTime": "2026-05-13T00:00:02Z",
                "parentResponseId": "resp-old"
            ],
            [
                "responseId": "resp-old",
                "message": "Older assistant response",
                "sender": "assistant",
                "createTime": "2026-05-13T00:00:01Z",
                "parentResponseId": "resp-user-1"
            ],
            [
                "responseId": "resp-user-1",
                "message": "First user response",
                "sender": "human",
                "createTime": "2026-05-13T00:00:00Z"
            ]
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--model", "fast"],
            input: "/resume\n1\n/goal --max-turns 1 find more influencers\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Goal started")
        let goalRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(goalRequest.jsonString("parentResponseId"), "resp-leaf")
        XCTAssertContains(goalRequest.jsonString("message") ?? "", "<grok_goal_request>")
        XCTAssertEqual(goalRequest.jsonString("modeId"), "grok-420-computer-use-sa")
    }

    func testInteractiveListSelectionFormatsLoadedAssistantMarkdown() throws {
        let server = try MockGrokServer(
            loadedAssistantMessage: "# Loaded Heading\n**assistant bold**\n<grok:render type=\"chart\">hidden</grok:render>"
        )
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat"],
            input: "/resume\n1\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Loaded Heading")
        XCTAssertContains(run.cleanOutput, "assistant bold")
        XCTAssertFalse(run.cleanOutput.contains("# Loaded Heading"))
        XCTAssertFalse(run.cleanOutput.contains("**assistant bold**"))
        XCTAssertFalse(run.cleanOutput.contains("<grok:render"))
    }

    func testInteractiveListSelectionPreservesLoadedAssistantRawMarkdown() throws {
        let loadedAssistantMessage = "# Loaded Heading\n**assistant bold**\n<grok:render type=\"chart\">hidden</grok:render>"
        let server = try MockGrokServer(loadedAssistantMessage: loadedAssistantMessage)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat", "--raw"],
            input: "/resume\n1\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "# Loaded Heading")
        XCTAssertContains(run.cleanOutput, "**assistant bold**")
        XCTAssertContains(run.cleanOutput, "<grok:render")
    }

    func testInteractiveShareCopiesCurrentConversationLink() throws {
        let shareLink = "https://grok.com/share/share-e2e"
        let server = try MockGrokServer(shareLinkURL: shareLink)
        let environment = try TestEnvironment(server: server)
        let clipboardURL = environment.scratchURL.appendingPathComponent("clipboard.txt")

        let run = try environment.run(
            ["chat"],
            input: "hello\n/share\n/quit\n",
            extraEnvironment: ["GROK_CLIPBOARD_FILE": clipboardURL.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Copied share link \(shareLink)")
        XCTAssertEqual(try String(contentsOf: clipboardURL, encoding: .utf8), shareLink)

        let shareRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/share_links", method: "GET").last)
        XCTAssertContains(shareRequest.target, "pageSize=100")
        XCTAssertContains(shareRequest.target, "conversationId=conv-e2e")
    }

    func testInteractiveShareCreatesLinkWhenLookupIsEmpty() throws {
        let shareLink = "https://grok.com/share/share-created-e2e"
        let server = try MockGrokServer(shareLinkURL: shareLink, shareLinkExists: false)
        let environment = try TestEnvironment(server: server)
        let clipboardURL = environment.scratchURL.appendingPathComponent("clipboard-created.txt")

        let run = try environment.run(
            ["chat"],
            input: "hello\n/share\n/quit\n",
            extraEnvironment: ["GROK_CLIPBOARD_FILE": clipboardURL.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Copied share link \(shareLink)")
        XCTAssertEqual(try String(contentsOf: clipboardURL, encoding: .utf8), shareLink)

        let lookupRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/share_links", method: "GET").last)
        XCTAssertContains(lookupRequest.target, "conversationId=conv-e2e")
        XCTAssertContains(lookupRequest.target, "responseId=resp-e2e")

        let createRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/share", method: "POST").last)
        XCTAssertEqual(createRequest.jsonString("responseId"), "resp-e2e")
        XCTAssertEqual(createRequest.jsonBool("allowIndexing"), true)
    }

    func testInteractiveDeleteSoftDeletesCurrentConversation() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat"],
            input: "hello\n/delete --yes\n/quit\n"
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Deleted conversation conv-e2e.")
        XCTAssertEqual(
            server.requests(matchingPath: "/rest/app-chat/conversations/soft/conv-e2e", method: "DELETE").count,
            1
        )
    }

    func testInteractiveDeletePrintsResumedConversationTitle() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            ["chat"],
            input: "/resume\n1\n/delete --yes\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Deleted conversation Mock Conversation.")
        XCTAssertFalse(run.cleanOutput.contains("Deleted conversation conv-e2e."))
        XCTAssertEqual(
            server.requests(matchingPath: "/rest/app-chat/conversations/soft/conv-e2e", method: "DELETE").count,
            1
        )
    }

    func testInteractiveDeleteConfirmationRequiresD() {
        XCTAssertContains(GrokCLI.deleteConfirmationPrompt, "type d to confirm delete")
        XCTAssertTrue(GrokCLI.isDeleteConfirmation("d"))
        XCTAssertTrue(GrokCLI.isDeleteConfirmation(" D\n"))
        XCTAssertFalse(GrokCLI.isDeleteConfirmation("delete"))
        XCTAssertFalse(GrokCLI.isDeleteConfirmation(nil))
    }

    func testMessageJSONModeEmitsSingleResultEnvelopeWithoutHumanBanners() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)

        let envelope = try jsonObject(from: run)
        let data = try assertResultEnvelope(
            envelope,
            command: "message",
            category: "assistant_response"
        )
        XCTAssertEqual(data["message"] as? String, "Mock final response")
        XCTAssertEqual(data["conversationId"] as? String, "conv-e2e")
        XCTAssertEqual(data["responseId"] as? String, "resp-e2e")
        XCTAssertNotNil(data["model"] as? [String: Any])
        XCTAssertNotNil(data["sources"] as? [String: Any])

        let request = try XCTUnwrap(data["request"] as? [String: Any])
        XCTAssertEqual(request["stream"] as? Bool, false)
        XCTAssertEqual(request["reasoning"] as? Bool, true)
        XCTAssertEqual(request["deepSearch"] as? Bool, false)

        let chatAlias = try environment.run(["chat", "--format=json", "hello"])
        XCTAssertEqual(chatAlias.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: chatAlias),
            command: "chat",
            category: "assistant_response"
        )

        let bareAlias = try environment.run(["--json", "hello"])
        XCTAssertEqual(bareAlias.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: bareAlias),
            command: "message",
            category: "assistant_response"
        )
    }

    func testMessageStreamingJSONModeEmitsNDJSONEvents() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)

        let events = try jsonLines(from: run)
        XCTAssertGreaterThanOrEqual(events.count, 2)
        for (index, event) in events.enumerated() {
            XCTAssertEqual(event["schema"] as? String, "grok.cli.event.v1")
            XCTAssertEqual(event["sequence"] as? Int, index + 1)
        }

        let eventNames = events.compactMap { $0["event"] as? String }
        XCTAssertTrue(eventNames.contains("request"))
        XCTAssertTrue(eventNames.contains("progress"))
        XCTAssertTrue(eventNames.contains("assistant_final"))
        XCTAssertEqual(events.last?["event"] as? String, "done")

        let requestEvent = try XCTUnwrap(events.first { $0["event"] as? String == "request" })
        let requestData = try XCTUnwrap(requestEvent["data"] as? [String: Any])
        XCTAssertEqual(requestData["message"] as? String, "hello")
        let request = try XCTUnwrap(requestData["request"] as? [String: Any])
        XCTAssertEqual(request["stream"] as? Bool, true)

        let finalEvent = try XCTUnwrap(events.last { $0["event"] as? String == "assistant_final" })
        let finalData = try XCTUnwrap(finalEvent["data"] as? [String: Any])
        XCTAssertEqual(finalData["message"] as? String, "Mock final response")
        XCTAssertEqual(finalData["conversationId"] as? String, "conv-e2e")
        XCTAssertEqual(finalData["responseId"] as? String, "resp-e2e")
    }

    func testStreamingJSONErrorsRemainNDJSONAndExitNonZero() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"error":{"code":8,"message":"Too many requests","details":[]}}"#
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--json", "hello"])

        XCTAssertEqual(run.status, 1)
        assertNoHumanJSONBanners(in: run.stdout)

        let events = try jsonLines(from: run)
        XCTAssertFalse(events.isEmpty)
        for (index, event) in events.enumerated() {
            XCTAssertEqual(event["schema"] as? String, "grok.cli.event.v1")
            XCTAssertEqual(event["sequence"] as? Int, index + 1)
        }

        let errorEvent = try XCTUnwrap(events.first { $0["event"] as? String == "error" })
        let errorData = try XCTUnwrap(errorEvent["data"] as? [String: Any])
        XCTAssertNotNil(errorData["code"] as? String)
        XCTAssertEqual(errorData["exitCode"] as? Int, 1)

        let done = try XCTUnwrap(events.last)
        XCTAssertEqual(done["event"] as? String, "done")
        let doneData = try XCTUnwrap(done["data"] as? [String: Any])
        XCTAssertEqual(doneData["ok"] as? Bool, false)
    }

    func testStreamingJSONSuppressesGenericThinkingPlaceholder() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Thinking about your request","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"answer"}}}"#,
            #"{"result":{"response":{"modelResponse":{"message":"answer","responseId":"resp-e2e"}}}}"#
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        let eventNames = try jsonLines(from: run).compactMap { $0["event"] as? String }
        XCTAssertFalse(eventNames.contains("thinking_start"))
        XCTAssertFalse(eventNames.contains("thinking_delta"))
        XCTAssertFalse(eventNames.contains("thinking_end"))
        XCTAssertTrue(eventNames.contains("assistant_final"))
        XCTAssertEqual(eventNames.last, "done")
    }

    func testStreamingJSONThinkingLifecycleEventsForTrueThinking() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Example calculation","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"answer"}}}"#,
            #"{"result":{"response":{"modelResponse":{"message":"answer","responseId":"resp-e2e"}}}}"#
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        let events = try jsonLines(from: run)
        let eventNames = events.compactMap { $0["event"] as? String }
        XCTAssertTrue(eventNames.contains("thinking_start"))
        XCTAssertTrue(eventNames.contains("thinking_delta"))
        XCTAssertTrue(eventNames.contains("thinking_end"))
        XCTAssertTrue(eventNames.contains("assistant_final"))
        XCTAssertEqual(eventNames.last, "done")
        let thinkingDelta = try XCTUnwrap(events.first { $0["event"] as? String == "thinking_delta" })
        let data = try XCTUnwrap(thinkingDelta["data"] as? [String: Any])
        XCTAssertEqual(data["text"] as? String, "Example calculation")
    }

    func testStreamingJSONSuppressesSplitResidualCitationFragments() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Lead _id=\"ccee26\" card_type=\"citation_card\" type=\"render_inline_citation\"><arg"}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"ument name=\"citation_id\">5</argument></grok:render> tail"}}}"#,
            #"{"result":{"response":{"modelResponse":{"message":"Lead  tail","responseId":"resp-e2e"}}}}"#
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        let events = try jsonLines(from: run)
        let deltas = events
            .filter { $0["event"] as? String == "assistant_delta" }
            .compactMap { ($0["data"] as? [String: Any])?["text"] as? String }
            .joined()
        XCTAssertEqual(deltas, "Lead  tail")
        XCTAssertFalse(run.stdout.contains("ccee26"))
        XCTAssertFalse(run.stdout.contains("citation_card"))
        XCTAssertFalse(run.stdout.contains("render_inline_citation"))
        XCTAssertFalse(run.stdout.contains("citation_id"))
    }

    func testMessageJSONStripsInternalRenderMarkupFromFinalMessage() throws {
        let answer = """
        Clean answer <grok:render type="render_inline_citation"><argument name="citation_id">5</argument></grok:render> keeps text.
        Residual _id="ccee26" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">5</argument></grok:render> stays hidden.
        """
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        let data = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "message",
            category: "assistant_response"
        )
        let message = try XCTUnwrap(data["message"] as? String)
        XCTAssertContains(message, "Clean answer")
        XCTAssertContains(message, "keeps text.")
        XCTAssertContains(message, "stays hidden.")
        XCTAssertFalse(message.contains("<grok:render"))
        XCTAssertFalse(message.contains("render_inline_citation"))
        XCTAssertFalse(message.contains("citation_card"))
        XCTAssertFalse(message.contains("<argument"))
        XCTAssertEqual(data["rawMessage"] as? String, answer)
    }

    func testJSONModeEnvelopesForModelsAndConversationLists() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let models = try environment.run(["models", "--json"])
        XCTAssertEqual(models.status, 0)
        assertNoHumanJSONBanners(in: models.stdout)
        XCTAssertFalse(models.stdout.contains("Available web modes:"))
        let modelData = try assertResultEnvelope(
            try jsonObject(from: models),
            command: "models",
            category: "model_list"
        )
        XCTAssertNotNil(modelData["currentModel"] as? [String: Any])
        XCTAssertFalse((modelData["models"] as? [[String: Any]])?.isEmpty ?? true)
        XCTAssertEqual((modelData["xaiOAuthModels"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((modelData["modelSources"] as? [String: Any])?["xaiOAuthModels"] as? Int, 0)

        let modesFormat = try environment.run(["modes", "--format=json"])
        XCTAssertEqual(modesFormat.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: modesFormat),
            command: "modes",
            category: "model_list"
        )

        let leadingJSONModels = try environment.run(["--json", "models"])
        XCTAssertEqual(leadingJSONModels.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: leadingJSONModels),
            command: "models",
            category: "model_list"
        )

        let leadingFormatModels = try environment.run(["--format", "json", "models"])
        XCTAssertEqual(leadingFormatModels.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: leadingFormatModels),
            command: "models",
            category: "model_list"
        )

        let leadingFormatTasks = try environment.run(["--format=json", "tasks", "list"])
        XCTAssertEqual(leadingFormatTasks.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: leadingFormatTasks),
            command: "tasks",
            subcommand: "list",
            category: "resource_list"
        )

        let leadingJSONMessage = try environment.run(["--json", "message", "hello"])
        XCTAssertEqual(leadingJSONMessage.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: leadingJSONMessage),
            command: "message",
            category: "assistant_response"
        )

        let list = try environment.run(["list", "--format", "json"])
        XCTAssertEqual(list.status, 0)
        assertNoHumanJSONBanners(in: list.stdout)
        XCTAssertFalse(list.stdout.contains("Fetching your saved conversations"))
        XCTAssertFalse(list.stdout.contains("Select a conversation"))
        let listData = try assertResultEnvelope(
            try jsonObject(from: list),
            command: "list",
            category: "conversation_list"
        )
        let conversations = try XCTUnwrap(listData["conversations"] as? [[String: Any]])
        XCTAssertEqual(conversations.first?["conversationId"] as? String, "conv-e2e")
        XCTAssertEqual(conversations.first?["title"] as? String, "Mock Conversation")

        let history = try environment.run(["list", "--conversation", "conv-e2e", "--json"])
        XCTAssertEqual(history.status, 0)
        assertNoHumanJSONBanners(in: history.stdout)
        XCTAssertFalse(history.stdout.contains("Available conversations:"))
        XCTAssertFalse(history.stdout.contains("Select a conversation"))
        let historyData = try assertResultEnvelope(
            try jsonObject(from: history),
            command: "list",
            subcommand: "conversation",
            category: "conversation_history"
        )
        XCTAssertEqual(historyData["conversationId"] as? String, "conv-e2e")
        let responses = try XCTUnwrap(historyData["responses"] as? [[String: Any]])
        XCTAssertTrue(responses.contains { $0["sender"] as? String == "human" && $0["message"] as? String == "Loaded user response" })
        XCTAssertTrue(responses.contains { $0["sender"] as? String == "assistant" && $0["message"] as? String == "Loaded assistant response" })

        let deleteWithoutYes = try environment.run(["list", "delete", "conv-e2e", "--json"])
        XCTAssertEqual(deleteWithoutYes.status, 2)
        let deleteError = try jsonObject(from: deleteWithoutYes)
        XCTAssertEqual(deleteError["ok"] as? Bool, false)
        XCTAssertEqual((deleteError["error"] as? [String: Any])?["code"] as? String, "usage_error")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/soft/conv-e2e", method: "DELETE").count, 0)

        let delete = try environment.run(["list", "delete", "conv-e2e", "--yes", "--json"])
        XCTAssertEqual(delete.status, 0)
        assertNoHumanJSONBanners(in: delete.stdout)
        let deleteData = try assertResultEnvelope(
            try jsonObject(from: delete),
            command: "list",
            subcommand: "delete",
            category: "conversation_delete"
        )
        XCTAssertEqual(deleteData["conversationId"] as? String, "conv-e2e")
        XCTAssertEqual(deleteData["deleted"] as? Bool, true)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/soft/conv-e2e", method: "DELETE").count, 1)

        let help = try environment.run(["help", "--json"])
        XCTAssertEqual(help.status, 0)
        let helpData = try assertResultEnvelope(
            try jsonObject(from: help),
            command: "help",
            category: "help"
        )
        XCTAssertTrue((helpData["commands"] as? [String])?.contains("message") ?? false)
        XCTAssertTrue((helpData["commands"] as? [String])?.contains("modes") ?? false)
        XCTAssertTrue((helpData["commands"] as? [String])?.contains("workspace") ?? false)
        XCTAssertTrue((helpData["commands"] as? [String])?.contains("test") ?? false)
        XCTAssertTrue((helpData["interactiveCommands"] as? [String])?.contains("/workspace") ?? false)
    }

    func testModelsCommandIncludesOAuthModelsWhenSavedCredentialExists() throws {
        let server = try MockGrokServer(xaiAPIModels: ["grok-4.3", "grok-code-fast"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let extraEnvironment = [
            "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
            "GROK_AUTH_MODE": "web"
        ]
        let models = try environment.run(["models"], extraEnvironment: extraEnvironment)
        XCTAssertEqual(models.status, 0)
        XCTAssertContains(models.cleanOutput, "Available web modes:")
        XCTAssertContains(models.cleanOutput, "Available xAI API models (OAuth):")
        XCTAssertContains(models.cleanOutput, "grok-4.3")
        XCTAssertContains(models.cleanOutput, "grok-code-fast")

        let modelRequests = server.requests(matchingPath: "/v1/models", method: "GET")
        XCTAssertEqual(modelRequests.count, 1)
        XCTAssertEqual(modelRequests.first?.header("Authorization"), "Bearer oauth-token")

        let json = try environment.run(["models", "--json"], extraEnvironment: extraEnvironment)
        XCTAssertEqual(json.status, 0)
        assertNoHumanJSONBanners(in: json.stdout)
        let modelData = try assertResultEnvelope(
            try jsonObject(from: json),
            command: "models",
            category: "model_list"
        )
        let xaiOAuthModels = try XCTUnwrap(modelData["xaiOAuthModels"] as? [[String: Any]])
        XCTAssertEqual(xaiOAuthModels.compactMap { $0["id"] as? String }, ["grok-4.3", "grok-code-fast"])
        let modelSources = try XCTUnwrap(modelData["modelSources"] as? [String: Any])
        XCTAssertEqual(modelSources["xaiOAuthModels"] as? Int, 2)

        let jsonModelRequests = server.requests(matchingPath: "/v1/models", method: "GET")
        XCTAssertEqual(jsonModelRequests.count, 2)
        XCTAssertEqual(jsonModelRequests.last?.header("authorization"), "Bearer oauth-token")
    }

    func testInteractiveModelListIncludesOAuthModelsWhenSavedCredentialExists() throws {
        let server = try MockGrokServer(xaiAPIModels: ["grok-4.3", "grok-build-0.1"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "interactive-oauth-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            [],
            input: "/model list\nquit\n",
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "web"
            ]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Available web modes:")
        XCTAssertContains(run.cleanOutput, "Available xAI API models (OAuth):")
        XCTAssertContains(run.cleanOutput, "grok-4.3")
        XCTAssertContains(run.cleanOutput, "grok-build-0.1")
        XCTAssertEqual(
            server.requests(matchingPath: "/v1/models", method: "GET").first?.header("authorization"),
            "Bearer interactive-oauth-token"
        )
    }

    func testInteractiveOAuthSlashCommandDelegatesToAuthOAuth() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/oauth status\nquit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "No saved xAI OAuth credentials.")
        XCTAssertContains(run.cleanOutput, "Goodbye!")
    }

    func testModelsCommandUsesOAuthModelsAsSelectableWhenOAuthModeEnabled() throws {
        let server = try MockGrokServer(xaiAPIModels: ["grok-4.3", "grok-4.3-fast-non-reasoning"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-models-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let extraEnvironment = [
            "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
            "GROK_AUTH_MODE": "oauth"
        ]
        let models = try environment.run(["models"], extraEnvironment: extraEnvironment)

        XCTAssertEqual(models.status, 0)
        XCTAssertFalse(models.cleanOutput.contains("Available web modes:"))
        XCTAssertContains(models.cleanOutput, "Available xAI API models (OAuth):")
        XCTAssertContains(models.cleanOutput, "grok-4.3-fast-non-reasoning")
        XCTAssertContains(models.cleanOutput, "raw xAI API model ID")

        let json = try environment.run(["models", "--json"], extraEnvironment: extraEnvironment)
        XCTAssertEqual(json.status, 0)
        let modelData = try assertResultEnvelope(
            try jsonObject(from: json),
            command: "models",
            category: "model_list"
        )
        XCTAssertEqual((modelData["models"] as? [[String: Any]])?.count, 0)
        let xaiOAuthModels = try XCTUnwrap(modelData["xaiOAuthModels"] as? [[String: Any]])
        XCTAssertEqual(xaiOAuthModels.compactMap { $0["id"] as? String }, ["grok-4.3", "grok-4.3-fast-non-reasoning"])
        XCTAssertTrue(xaiOAuthModels.allSatisfy { $0["disabled"] as? Bool == false })
        XCTAssertTrue(xaiOAuthModels.contains { $0["id"] as? String == "grok-4.3-fast-non-reasoning" && $0["selected"] as? Bool == true })
    }

    func testSavedOAuthCredentialsTakePriorityOverSavedWebAuthMode() throws {
        let server = try MockGrokServer(xaiAPIModels: ["grok-4.3", "grok-code-fast"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-priority-token",
            apiBaseURL: xaiAPIBaseURL
        )
        try writeSavedAuthMode("web", in: environment)

        let run = try environment.run(
            ["models"],
            extraEnvironment: ["GROK_XAI_API_BASE_URL": xaiAPIBaseURL]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(run.cleanOutput.contains("Available web modes:"))
        XCTAssertContains(run.cleanOutput, "Available xAI API models (OAuth):")
        XCTAssertEqual(server.requests(matchingPath: "/v1/models", method: "GET").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/modes", method: "POST").count, 0)
    }

    func testInteractiveModelPickerPrioritizesSavedOAuthCredentialsOverWebAuthMode() throws {
        let server = try MockGrokServer(xaiAPIModels: ["grok-4.3", "grok-code-fast"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-picker-priority-token",
            apiBaseURL: xaiAPIBaseURL
        )
        try writeSavedAuthMode("web", in: environment)

        let run = try environment.run(
            [],
            input: "/model\n\nquit\n",
            extraEnvironment: ["GROK_XAI_API_BASE_URL": xaiAPIBaseURL]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Select model")
        XCTAssertContains(run.cleanOutput, "grok-4.3")
        XCTAssertContains(run.cleanOutput, "grok-code-fast")
        XCTAssertFalse(run.cleanOutput.contains("Auto  auto"))
        XCTAssertFalse(run.cleanOutput.contains("Fast  fast"))
        XCTAssertFalse(run.cleanOutput.contains("Grok 4.3 (beta)"))
        XCTAssertEqual(server.requests(matchingPath: "/rest/modes", method: "POST").count, 0)
    }

    func testOAuthAuthModeRoutesMessageToXAIResponsesAPI() throws {
        let server = try MockGrokServer(
            finalMessage: "oauth answer",
            xaiAPIModels: ["grok-4.3", "grok-4.3-fast-non-reasoning"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-message-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["message", "--json", "--model", "fast", "hello oauth"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        let responseData = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "message",
            category: "assistant_response"
        )
        XCTAssertEqual((responseData["model"] as? [String: Any])?["id"] as? String, "grok-4.3-fast-non-reasoning")

        let responseRequests = server.requests(matchingPath: "/v1/responses", method: "POST")
        XCTAssertEqual(responseRequests.count, 1)
        let request = try XCTUnwrap(responseRequests.first)
        XCTAssertEqual(request.header("authorization"), "Bearer oauth-message-token")
        XCTAssertEqual(request.jsonString("model"), "grok-4.3-fast-non-reasoning")
        let input = try XCTUnwrap(request.json["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["role"] as? String, "user")
        XCTAssertEqual(input.first?["content"] as? String, "hello oauth")
        XCTAssertEqual(request.jsonBool("store"), true)
        XCTAssertNil(request.jsonString("previous_response_id"))
        XCTAssertTrue(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").isEmpty)
    }

    func testOAuthStreamingResponsesAPIEmitsThinkingDeltas() throws {
        let server = try MockGrokServer(
            xaiResponseStreamLines: [
                "event: response.created",
                #"data: {"type":"response.created","response":{"id":"resp-xai-stream"}}"#,
                "event: response.reasoning_summary_text.delta",
                #"data: {"type":"response.reasoning_summary_text.delta","delta":"checking the OAuth stream"}"#,
                "id: stream-event-1",
                #"data: {"type":"response.output_text.delta","delta":"streamed "}"#,
                #"data: {"type":"response.output_text.delta","delta":"oauth answer"}"#,
                ": keep-alive",
                #"data: {"type":"response.completed","response":{"id":"resp-xai-stream","output_text":"streamed oauth answer"}}"#,
                "data: [DONE]"
            ],
            xaiAPIModels: ["grok-4.3"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-stream-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["message", "--stream", "--model", "grok-4.3", "hello oauth stream"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "[thinking] checking the OAuth stream")
        XCTAssertContains(run.cleanOutput, "streamed oauth answer")

        let request = try XCTUnwrap(server.requests(matchingPath: "/v1/responses", method: "POST").last)
        XCTAssertEqual(request.header("authorization"), "Bearer oauth-stream-token")
        XCTAssertEqual(request.jsonString("model"), "grok-4.3")
        XCTAssertEqual(request.jsonBool("stream"), true)
        XCTAssertEqual(request.jsonBool("store"), true)
        XCTAssertTrue(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").isEmpty)
    }

    func testOAuthStreamingJSONIncludesThinkingEvents() throws {
        let server = try MockGrokServer(
            xaiResponseStreamLines: [
                #"data: {"type":"response.created","response":{"id":"resp-xai-json-stream"}}"#,
                #"data: {"type":"response.reasoning_summary_text.delta","delta":"oauth json thought"}"#,
                #"data: {"type":"response.output_text.delta","delta":"json oauth answer"}"#,
                #"data: {"type":"response.completed","response":{"id":"resp-xai-json-stream","output_text":"json oauth answer"}}"#
            ],
            xaiAPIModels: ["grok-4.3"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-stream-json-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["message", "--stream", "--json", "--model", "grok-4.3", "hello oauth json stream"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        XCTAssertContains(run.stdout, #""event":"thinking_delta""#)
        XCTAssertContains(run.stdout, "oauth json thought")
        XCTAssertContains(run.stdout, #""event":"assistant_delta""#)
        XCTAssertContains(run.stdout, "json oauth answer")
        XCTAssertEqual(server.requests(matchingPath: "/v1/responses", method: "POST").last?.jsonBool("stream"), true)
    }

    func testOAuthImageModelRoutesMessageToXAIMediaEndpointNotResponses() throws {
        let server = try MockGrokServer(
            xaiAPIModels: ["grok-4.3", "grok-imagine-image-quality"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-image-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["message", "--json", "--model", "grok-imagine-image-quality", "make a blue square"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        let responseData = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "message",
            category: "assistant_response"
        )
        XCTAssertContains(responseData["message"] as? String ?? "", "https://imgen.x.ai/mock-image.jpeg")

        let imageRequests = server.requests(matchingPath: "/v1/images/generations", method: "POST")
        XCTAssertEqual(imageRequests.count, 1)
        let request = try XCTUnwrap(imageRequests.first)
        XCTAssertEqual(request.header("authorization"), "Bearer oauth-image-token")
        XCTAssertEqual(request.jsonString("model"), "grok-imagine-image-quality")
        XCTAssertEqual(request.jsonString("prompt"), "make a blue square")
        XCTAssertTrue(server.requests(matchingPath: "/v1/responses", method: "POST").isEmpty)
    }

    func testOAuthStreamingImageModelRoutesToImagesEndpointNotResponses() throws {
        let server = try MockGrokServer(
            xaiAPIModels: ["grok-4.3", "grok-imagine-image-quality"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-stream-image-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["message", "--stream", "--json", "--model", "grok-imagine-image-quality", "make a green square"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        XCTAssertContains(run.stdout, #""event":"assistant_final""#)
        XCTAssertContains(run.stdout, "https://imgen.x.ai/mock-image.jpeg")
        XCTAssertEqual(server.requests(matchingPath: "/v1/images/generations", method: "POST").count, 1)
        XCTAssertTrue(server.requests(matchingPath: "/v1/responses", method: "POST").isEmpty)
    }

    func testOAuthVideoModelRoutesMessageToXAIVideoEndpointAndPolls() throws {
        let server = try MockGrokServer(
            xaiAPIModels: ["grok-4.3", "grok-imagine-video"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-video-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["message", "--json", "--model", "grok-imagine-video", "make a red ball bounce once"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        let responseData = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "message",
            category: "assistant_response"
        )
        XCTAssertContains(responseData["message"] as? String ?? "", "https://vidgen.x.ai/mock-video.mp4")

        let videoRequests = server.requests(matchingPath: "/v1/videos/generations", method: "POST")
        XCTAssertEqual(videoRequests.count, 1)
        let request = try XCTUnwrap(videoRequests.first)
        XCTAssertEqual(request.header("authorization"), "Bearer oauth-video-token")
        XCTAssertEqual(request.jsonString("model"), "grok-imagine-video")
        XCTAssertEqual(request.jsonString("prompt"), "make a red ball bounce once")
        XCTAssertEqual(server.requests(matchingPath: "/v1/videos/vid-xai-e2e", method: "GET").count, 1)
        XCTAssertTrue(server.requests(matchingPath: "/v1/responses", method: "POST").isEmpty)
    }

    func testInteractiveOAuthVideoProgressStillPrintsFinalVideoURL() throws {
        let server = try MockGrokServer(
            xaiVideoPollResponses: [
                [
                    "status": "pending",
                    "progress": 88
                ],
                MockGrokServer.doneXAIVideoPollResponse
            ],
            xaiAPIModels: ["grok-4.3", "grok-imagine-video"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-interactive-video-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            [],
            input: """
            /model grok-imagine-video
            make a red ball bounce once
            quit
            """,
            timeout: 15,
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_XAI_VIDEO_POLL_INTERVAL_MS": "10",
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "[thinking] Video generation pending 88%")
        XCTAssertContains(run.cleanOutput, "Generated video:")
        XCTAssertContains(run.cleanOutput, "https://vidgen.x.ai/mock-video.mp4")
        XCTAssertEqual(server.requests(matchingPath: "/v1/videos/vid-xai-e2e", method: "GET").count, 2)
    }

    func testInteractiveOAuthMediaGenerationDoesNotBecomePreviousResponseID() throws {
        let server = try MockGrokServer(
            xaiAPIModels: ["grok-4.3", "grok-imagine-image-quality"]
        )
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-interactive-media-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            [],
            input: """
            /model grok-imagine-image-quality
            make a blue square
            /model grok-4.3
            hello after image
            quit
            """,
            timeout: 15,
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Generated image:")
        XCTAssertEqual(server.requests(matchingPath: "/v1/images/generations", method: "POST").count, 1)
        let responseRequest = try XCTUnwrap(server.requests(matchingPath: "/v1/responses", method: "POST").last)
        XCTAssertEqual(responseRequest.jsonString("model"), "grok-4.3")
        XCTAssertNil(responseRequest.jsonString("previous_response_id"))
    }

    func testOAuthAuthModeRoutesFilesAndTranscribeToXAIAPI() throws {
        let server = try MockGrokServer(transcriptionText: "oauth transcript", xaiAPIModels: ["grok-4.3"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-resource-token",
            apiBaseURL: xaiAPIBaseURL
        )
        let extraEnvironment = [
            "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
            "GROK_AUTH_MODE": "oauth"
        ]

        let list = try environment.run(["files", "list", "--format", "json"], extraEnvironment: extraEnvironment)
        XCTAssertEqual(list.status, 0)
        XCTAssertEqual(server.requests(matchingPath: "/v1/files", method: "GET").last?.header("authorization"), "Bearer oauth-resource-token")

        let uploadURL = environment.scratchURL.appendingPathComponent("oauth.txt")
        try "upload body".write(to: uploadURL, atomically: true, encoding: .utf8)
        let upload = try environment.run(["files", "upload", uploadURL.path, "--format", "json"], extraEnvironment: extraEnvironment)
        XCTAssertEqual(upload.status, 0)
        let uploadRequest = try XCTUnwrap(server.requests(matchingPath: "/v1/files", method: "POST").last)
        XCTAssertEqual(uploadRequest.header("authorization"), "Bearer oauth-resource-token")
        let uploadBody = String(data: uploadRequest.body, encoding: .utf8) ?? ""
        XCTAssertContains(uploadBody, #"name="purpose""#)
        XCTAssertContains(uploadBody, "assistants")
        XCTAssertContains(uploadBody, #"filename="oauth.txt""#)

        let delete = try environment.run(["files", "delete", "file-xai-1", "--format", "json"], extraEnvironment: extraEnvironment)
        XCTAssertEqual(delete.status, 0)
        XCTAssertEqual(server.requests(matchingPath: "/v1/files/file-xai-1", method: "DELETE").last?.header("authorization"), "Bearer oauth-resource-token")

        let audioURL = environment.scratchURL.appendingPathComponent("sample.wav")
        try Data("audio bytes".utf8).write(to: audioURL)
        let transcribe = try environment.run(["transcribe", "--format", "json", audioURL.path], extraEnvironment: extraEnvironment)
        XCTAssertEqual(transcribe.status, 0)
        let transcribeRequest = try XCTUnwrap(server.requests(matchingPath: "/v1/stt", method: "POST").last)
        XCTAssertEqual(transcribeRequest.header("authorization"), "Bearer oauth-resource-token")
        let transcribeBody = String(data: transcribeRequest.body, encoding: .utf8) ?? ""
        XCTAssertContains(transcribeBody, #"filename="sample.wav""#)
        XCTAssertContains(transcribeBody, "Content-Type: audio/wav")
    }

    func testOAuthAuthModeRejectsWebOnlyTasksWithoutWebRequest() throws {
        let server = try MockGrokServer(xaiAPIModels: ["grok-4.3"])
        let environment = try TestEnvironment(server: server)
        let xaiAPIBaseURL = "\(server.baseURL)/v1"
        try writeSavedXAIOAuthCredential(
            in: environment,
            accessToken: "oauth-web-only-token",
            apiBaseURL: xaiAPIBaseURL
        )

        let run = try environment.run(
            ["tasks", "list", "--format", "json"],
            extraEnvironment: [
                "GROK_XAI_API_BASE_URL": xaiAPIBaseURL,
                "GROK_AUTH_MODE": "oauth"
            ]
        )

        XCTAssertEqual(run.status, 1)
        XCTAssertContains(run.cleanOutput, "not available in xAI OAuth mode")
        XCTAssertTrue(server.requests(matchingPath: "/rest/tasks", method: "GET").isEmpty)
    }

    func testTasksListJSONModeEmitsResourceEnvelope() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["tasks", "list", "--format", "json"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        XCTAssertFalse(run.stdout.contains("Tasks:"))

        let data = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "tasks",
            subcommand: "list",
            category: "resource_list"
        )
        XCTAssertEqual(data["resource"] as? String, "task")
        XCTAssertNil(data["raw"])

        let items = try XCTUnwrap(data["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?["taskId"] as? String, "task-summary-daily")
        XCTAssertEqual(items.first?["name"] as? String, "Morning Research Brief")
        XCTAssertEqual(items.first?["prompt"] as? String, "Summarize overnight product and AI research updates.")
        XCTAssertEqual(items.first?["isEnabled"] as? Bool, true)
        XCTAssertFalse(run.stdout.contains("rawTaskPayload"))
        XCTAssertFalse(run.stdout.contains("internalOnly"))
        XCTAssertFalse(run.stdout.contains("cookie"))
    }

    func testTasksListHumanOutputShowsUsefulSummaries() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["tasks", "list"])

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Tasks")
        XCTAssertContains(run.cleanOutput, "Morning Research Brief  enabled  2026-05-15 08:00 America/New_York")
        XCTAssertContains(run.cleanOutput, "Weekly Support Digest  enabled  2026-05-18 09:30 UTC")
        XCTAssertFalse(run.cleanOutput.contains("task-summary-daily"))
        XCTAssertFalse(run.cleanOutput.contains("task-summary-weekly"))
        XCTAssertFalse(run.cleanOutput.contains("ID:"))
        XCTAssertFalse(run.cleanOutput.contains("Title:"))
        XCTAssertFalse(run.cleanOutput.contains("Status:"))
        XCTAssertFalse(run.cleanOutput.contains("Schedule:"))
    }

    func testTasksInactiveListUsesSanitizedMockResponse() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["tasks", "inactive"])

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Archived Roadmap Sweep")
        XCTAssertContains(run.cleanOutput, "archived")
        XCTAssertFalse(run.cleanOutput.contains("task-archived-roadmap"))
        XCTAssertEqual(server.requests(matchingPath: "/rest/tasks/inactive", method: "GET").count, 1)
    }

    func testTasksInteractiveSelectionShowsLatestResult() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/tasks\n1\n1\n2\n5\n/quit\n", timeout: 15)

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Tasks")
        XCTAssertContains(run.cleanOutput, "Morning Research Brief")
        XCTAssertContains(run.cleanOutput, "Task actions")
        XCTAssertContains(run.cleanOutput, "Show latest result")
        XCTAssertContains(run.cleanOutput, "Task run")
        XCTAssertContains(run.cleanOutput, "done")
        XCTAssertContains(run.cleanOutput, "Three notable product research updates landed overnight.")
        XCTAssertFalse(run.cleanOutput.contains("task-summary-daily"))
        XCTAssertFalse(run.cleanOutput.contains("conv-task-summary-daily"))
        XCTAssertFalse(run.cleanOutput.contains("Task Details:"))
        XCTAssertFalse(run.cleanOutput.contains("Latest result for"))
        XCTAssertEqual(server.requests(matchingPath: "/rest/tasks", method: "GET").count, 1)
        XCTAssertTrue(server.requests(method: "GET").contains {
            $0.path == "/rest/tasks/results/task-summary-daily" && $0.target.contains("limit=1")
        })
    }

    func testTasksInteractiveShowRunsListsAndViewsPreviousRun() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/tasks\n1\n2\n2\n2\n\n5\n/quit\n", timeout: 15)

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Task runs:")
        XCTAssertContains(run.cleanOutput, "latest")
        XCTAssertContains(run.cleanOutput, "previous")
        XCTAssertContains(run.cleanOutput, "Previous run captured one older product research update.")
        XCTAssertTrue(server.requests(method: "GET").contains {
            $0.path == "/rest/tasks/results/task-summary-daily" && $0.target.contains("limit=10")
        })
    }

    func testTasksDetailJSONDoesNotLeakRawPayload() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["tasks", "detail", "task-summary-daily", "--format", "json"])

        XCTAssertEqual(run.status, 0)
        assertNoHumanJSONBanners(in: run.stdout)
        XCTAssertFalse(run.stdout.contains("rawTaskPayload"))
        XCTAssertFalse(run.stdout.contains("internalOnly"))
        XCTAssertFalse(run.stdout.contains("cookie"))
        XCTAssertContains(run.stdout, "task-summary-daily")
        XCTAssertContains(run.stdout, "Three notable product research updates landed overnight.")
        XCTAssertTrue(server.requests(method: "GET").contains {
            $0.path == "/rest/tasks/results/task-summary-daily" && $0.target.contains("limit=1")
        })
    }

    func testTasksResultsHumanOutputShowsLatestResult() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["tasks", "results", "task-summary-daily"])

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Latest run  done  2026-05-15 12:00")
        XCTAssertContains(run.cleanOutput, "Three notable product research updates landed overnight.")
        XCTAssertFalse(run.cleanOutput.contains("task-summary-daily"))
        XCTAssertFalse(run.cleanOutput.contains("conv-task-summary-daily"))
        XCTAssertFalse(run.cleanOutput.contains("Latest result for"))
        XCTAssertTrue(server.requests(method: "GET").contains {
            $0.path == "/rest/tasks/results/task-summary-daily" && $0.target.contains("limit=1")
        })
    }

    func testJSONModeErrorsAuthAndUtilityCommands() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let badFormat = try environment.run(["message", "--json", "--format", "nope", "hello"])
        XCTAssertEqual(badFormat.status, 2)
        let badFormatEnvelope = try jsonObject(from: badFormat)
        XCTAssertEqual(badFormatEnvelope["ok"] as? Bool, false)
        XCTAssertEqual(badFormatEnvelope["category"] as? String, "error")
        let badFormatError = try XCTUnwrap(badFormatEnvelope["error"] as? [String: Any])
        XCTAssertEqual(badFormatError["code"] as? String, "usage_error")
        XCTAssertContains(badFormatError["message"] as? String ?? "", "md, raw, or json")

        let chatJSON = try environment.run(["chat", "--json"])
        XCTAssertEqual(chatJSON.status, 2)
        let chatEnvelope = try jsonObject(from: chatJSON)
        XCTAssertEqual(chatEnvelope["ok"] as? Bool, false)
        XCTAssertEqual(chatEnvelope["command"] as? String, "chat")
        XCTAssertEqual((chatEnvelope["error"] as? [String: Any])?["code"] as? String, "usage_error")

        let filesUploadMissingJSON = try environment.run(["files", "upload", "--json"])
        XCTAssertEqual(filesUploadMissingJSON.status, 2)
        let filesUploadEnvelope = try jsonObject(from: filesUploadMissingJSON)
        XCTAssertEqual(filesUploadEnvelope["ok"] as? Bool, false)
        XCTAssertEqual(filesUploadEnvelope["command"] as? String, "files")
        XCTAssertEqual((filesUploadEnvelope["error"] as? [String: Any])?["code"] as? String, "usage_error")

        let skillsUnknownJSON = try environment.run(["skills", "bogus", "--json"])
        XCTAssertEqual(skillsUnknownJSON.status, 2)
        let skillsUnknownEnvelope = try jsonObject(from: skillsUnknownJSON)
        XCTAssertEqual(skillsUnknownEnvelope["ok"] as? Bool, false)
        XCTAssertEqual(skillsUnknownEnvelope["command"] as? String, "skills")
        XCTAssertEqual((skillsUnknownEnvelope["error"] as? [String: Any])?["code"] as? String, "usage_error")

        let agentsShowMissingJSON = try environment.run(["agents", "show", "--json"])
        XCTAssertEqual(agentsShowMissingJSON.status, 2)
        let agentsShowEnvelope = try jsonObject(from: agentsShowMissingJSON)
        XCTAssertEqual(agentsShowEnvelope["ok"] as? Bool, false)
        let agentsShowError = try XCTUnwrap(agentsShowEnvelope["error"] as? [String: Any])
        XCTAssertEqual(agentsShowEnvelope["command"] as? String, "agents")
        XCTAssertEqual(agentsShowError["code"] as? String, "usage_error")
        XCTAssertContains(agentsShowError["message"] as? String ?? "", "Usage: grok agents show")
        XCTAssertFalse((agentsShowError["message"] as? String ?? "").contains("Usage: Usage:"))

        let modelsFormat = try environment.run(["models", "--format", "json"])
        XCTAssertEqual(modelsFormat.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: modelsFormat),
            command: "models",
            category: "model_list"
        )

        let testCommand = try environment.run(["test", "--json", "hello", "parser"])
        XCTAssertEqual(testCommand.status, 0)
        let testData = try assertResultEnvelope(
            try jsonObject(from: testCommand),
            command: "test",
            category: "test_result"
        )
        XCTAssertEqual(testData["provided"] as? Bool, true)
        XCTAssertEqual(testData["message"] as? String, "hello parser")

        let importFile = environment.scratchURL.appendingPathComponent("json-imported-credentials.json")
        try #"{"x-anonuserid":"json-imported","sso":"cookie"}"#.write(to: importFile, atomically: true, encoding: .utf8)
        let imported = try environment.run(["auth", "import", importFile.path, "--json"])
        XCTAssertEqual(imported.status, 0)
        let importData = try assertResultEnvelope(
            try jsonObject(from: imported),
            command: "auth",
            subcommand: "import",
            category: "auth_result"
        )
        XCTAssertEqual(importData["action"] as? String, "import")
        XCTAssertEqual(importData["path"] as? String, importFile.path)

        let invalidImportFile = environment.scratchURL.appendingPathComponent("invalid-credentials.json")
        try #"{"not":"credentials"}"#.write(to: invalidImportFile, atomically: true, encoding: .utf8)
        let invalidImport = try environment.run(["auth", "import", invalidImportFile.path, "--json"])
        XCTAssertEqual(invalidImport.status, 1)
        let invalidEnvelope = try jsonObject(from: invalidImport)
        XCTAssertEqual(invalidEnvelope["ok"] as? Bool, false)
        XCTAssertEqual(invalidEnvelope["command"] as? String, "auth")
        let invalidError = try XCTUnwrap(invalidEnvelope["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? String, "api_error")
        XCTAssertContains(invalidError["message"] as? String ?? "", "auth cookie")

        let extractor = environment.scratchURL.appendingPathComponent("fake_json_cookie_extractor.py")
        let extractorScript = """
        import json
        import sys
        print("extractor stdout noise")
        print("extractor stderr noise", file=sys.stderr)
        args = sys.argv[1:]
        output = args[args.index("--output") + 1]
        with open(output, "w") as handle:
            json.dump({"x-anonuserid": "json-generated", "sso": "cookie"}, handle)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)

        let generated = try environment.run(
            ["auth", "chrome", "--json", "--quiet"],
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )
        XCTAssertEqual(generated.status, 0)
        XCTAssertFalse(generated.stdout.contains("extractor stdout noise"))
        XCTAssertFalse(generated.stdout.contains("extractor stderr noise"))
        let generateData = try assertResultEnvelope(
            try jsonObject(from: generated),
            command: "auth",
            subcommand: "generate",
            category: "auth_result"
        )
        XCTAssertEqual(generateData["action"] as? String, "generate")
        XCTAssertEqual(generateData["browser"] as? String, "chrome")
        XCTAssertNotNil(generateData["credentialsPath"] as? String)
    }

    func testChatAndMessageUsageErrorsReturnStatusTwo() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let messageMissingFormat = try environment.run(["message", "--format"])
        XCTAssertEqual(messageMissingFormat.status, 2)
        XCTAssertContains(messageMissingFormat.cleanOutput, "requires a format value")
        XCTAssertFalse(messageMissingFormat.cleanOutput.contains("Calling Grok API"))

        let messageInvalidFormat = try environment.run(["message", "--format=bogus", "hello"])
        XCTAssertEqual(messageInvalidFormat.status, 2)
        XCTAssertContains(messageInvalidFormat.cleanOutput, "Invalid output format")
        XCTAssertFalse(messageInvalidFormat.cleanOutput.contains("Calling Grok API"))

        let messageMissingModel = try environment.run(["message", "--model"])
        XCTAssertEqual(messageMissingModel.status, 2)
        XCTAssertContains(messageMissingModel.cleanOutput, "requires a model value")
        XCTAssertFalse(messageMissingModel.cleanOutput.contains("Calling Grok API"))

        let chatInvalidFormat = try environment.run(["chat", "--format", "xml"])
        XCTAssertEqual(chatInvalidFormat.status, 2)
        XCTAssertContains(chatInvalidFormat.cleanOutput, "Invalid output format")
        XCTAssertFalse(chatInvalidFormat.cleanOutput.contains("Calling Grok API"))

        let chatMissingModel = try environment.run(["chat", "--model"])
        XCTAssertEqual(chatMissingModel.status, 2)
        XCTAssertContains(chatMissingModel.cleanOutput, "requires a model value")
        XCTAssertFalse(chatMissingModel.cleanOutput.contains("Calling Grok API"))

        let chatStdin = try environment.run(["chat", "--stdin"])
        XCTAssertEqual(chatStdin.status, 2)
        XCTAssertContains(chatStdin.cleanOutput, "--stdin is only supported by grok message")
        XCTAssertFalse(chatStdin.cleanOutput.contains("Calling Grok API"))

        let chatPromptFile = try environment.run(["chat", "--prompt-file", "prompt.txt"])
        XCTAssertEqual(chatPromptFile.status, 2)
        XCTAssertContains(chatPromptFile.cleanOutput, "--prompt-file is only supported by grok message")
        XCTAssertFalse(chatPromptFile.cleanOutput.contains("Calling Grok API"))
    }

    func testStreamingThinkingChunksRenderAboveAnswer() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Thinking about your request","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"Example calculation","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"<xai:tool_usage_card><xai:tool_usage_card_id>tool-1</xai:tool_usage_card_id><xai:tool_name>web_search</xai:tool_name><xai:tool_args><![CDATA[{\"query\":\"current Moon","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"long silk"}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":" distance Seattle\",\"num_results\":\"5\"}]]></xai:tool_args></xai:tool_usage_card>","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"y black hair\nWhy\n\n"}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"Estimating lunar distance and Saturn V fuel needs","isThinking":true,"isSoftStop":false,"messageTag":"header","messageStepId":1}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"does it matter\n"}}}"#,
            #"{"result":{"response":{"modelResponse":{"message":"long silky black hair\nWhy\n\ndoes it matter","responseId":"resp-e2e"}}}}"#
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "hello"])

        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(run.cleanOutput.contains("[thinking] Thinking about your request"))
        XCTAssertContains(run.cleanOutput, "[thinking] Example calculation")
        XCTAssertContains(run.cleanOutput, "[search] current Moon distance Seattle")
        XCTAssertContains(run.cleanOutput, "long silky black hair")
        XCTAssertContains(run.cleanOutput, "does it matter")
        XCTAssertFalse(run.cleanOutput.contains("<xai:tool_usage_card"))
        XCTAssertFalse(run.cleanOutput.contains("silkSearch"))
        XCTAssertFalse(run.cleanOutput.contains("requestlong"))
        XCTAssertFalse(run.cleanOutput.contains("Estimating lunar distance and Saturn V fuel needs"))

        let thoughtRange = try XCTUnwrap(run.cleanOutput.range(of: "[thinking] Example calculation"))
        let answerRange = try XCTUnwrap(run.cleanOutput.range(of: "\nGrok\n"))
        XCTAssertLessThan(thoughtRange.lowerBound, answerRange.lowerBound)
        let toolRange = try XCTUnwrap(run.cleanOutput.range(of: "[search] current Moon distance Seattle"))
        XCTAssertLessThan(toolRange.lowerBound, answerRange.lowerBound)
    }

    func testAuthImportAndGenerateCommands() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let importFile = environment.scratchURL.appendingPathComponent("imported-credentials.json")
        try #"{"x-anonuserid":"imported","sso":"cookie"}"#.write(to: importFile, atomically: true, encoding: .utf8)

        let imported = try environment.run(["auth", "import", importFile.path])
        XCTAssertEqual(imported.status, 0)
        XCTAssertContains(imported.cleanOutput, "Successfully imported credentials!")

        let quietImportLeading = try environment.run(["auth", "import", "--quiet", importFile.path])
        XCTAssertEqual(quietImportLeading.status, 0)
        XCTAssertEqual(quietImportLeading.cleanOutput, "")

        let quietImportTrailing = try environment.run(["auth", "import", importFile.path, "--quiet"])
        XCTAssertEqual(quietImportTrailing.status, 0)
        XCTAssertEqual(quietImportTrailing.cleanOutput, "")

        let savedCredentials = try String(contentsOf: environment.credentialsURL, encoding: .utf8)
        XCTAssertContains(savedCredentials, "imported")

        let missingImportPath = try environment.run(["auth", "import"])
        XCTAssertEqual(missingImportPath.status, 2)
        XCTAssertContains(missingImportPath.cleanOutput, "Error: Please provide a path to the credentials file")

        let importHelp = try environment.run(["auth", "import", "--help"])
        XCTAssertEqual(importHelp.status, 0)
        XCTAssertContains(importHelp.cleanOutput, "Usage: grok auth import <file>")
        XCTAssertFalse(importHelp.cleanOutput.contains("Error:"))

        let generateHelp = try environment.run(["auth", "generate", "--help"])
        XCTAssertEqual(generateHelp.status, 0)
        XCTAssertContains(generateHelp.cleanOutput, "Usage: grok auth generate")
        XCTAssertFalse(generateHelp.cleanOutput.contains("Extracting credentials"))

        let oauthHelp = try environment.run(["auth", "oauth", "--help"])
        XCTAssertEqual(oauthHelp.status, 0)
        XCTAssertContains(oauthHelp.cleanOutput, "Usage: grok auth oauth")

        let oauthStatus = try environment.run(["auth", "oauth", "status"])
        XCTAssertEqual(oauthStatus.status, 0)
        XCTAssertContains(oauthStatus.cleanOutput, "No saved xAI OAuth credentials.")

        let oauthStatusJSON = try environment.run(["auth", "oauth", "status", "--json"])
        XCTAssertEqual(oauthStatusJSON.status, 0)
        let oauthStatusData = try assertResultEnvelope(
            try jsonObject(from: oauthStatusJSON),
            command: "auth",
            subcommand: "oauth",
            category: "auth_status"
        )
        XCTAssertEqual(oauthStatusData["authenticated"] as? Bool, false)

        let oauthUnknown = try environment.run(["auth", "oauth", "unknown"])
        XCTAssertEqual(oauthUnknown.status, 2)
        XCTAssertContains(oauthUnknown.cleanOutput, "Unknown xAI OAuth command: unknown")

        let extractorLog = environment.scratchURL.appendingPathComponent("extractor-args.txt")
        let extractor = environment.scratchURL.appendingPathComponent("fake_cookie_extractor.py")
        let extractorScript = """
        import json
        import sys
        args = sys.argv[1:]
        with open("\(extractorLog.path)", "w") as log:
            log.write("\\n".join(args))
        output = args[args.index("--output") + 1]
        with open(output, "w") as handle:
            json.dump({"x-anonuserid": "generated", "sso": "cookie"}, handle)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)

        let defaultGenerated = try environment.run(
            ["auth"],
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )
        XCTAssertEqual(defaultGenerated.status, 0)
        XCTAssertContains(defaultGenerated.cleanOutput, "Successfully generated credentials!")
        XCTAssertContains(try String(contentsOf: environment.credentialsURL, encoding: .utf8), "generated")

        let generated = try environment.run(
            ["auth", "generate", "--browser", "chrome", "--quiet"],
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )
        XCTAssertEqual(generated.status, 0)
        XCTAssertEqual(generated.cleanOutput, "")
        XCTAssertContains(try String(contentsOf: environment.credentialsURL, encoding: .utf8), "generated")

        var extractorArgs = try String(contentsOf: extractorLog, encoding: .utf8)
        XCTAssertContains(extractorArgs, "--browser")
        XCTAssertContains(extractorArgs, "chrome")
        XCTAssertContains(extractorArgs, "--format")
        XCTAssertContains(extractorArgs, "--required")
        XCTAssertContains(extractorArgs, "--output")

        let safariShortcut = try environment.run(
            ["auth", "safari", "--quiet"],
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )
        XCTAssertEqual(safariShortcut.status, 0)
        XCTAssertEqual(safariShortcut.cleanOutput, "")

        extractorArgs = try String(contentsOf: extractorLog, encoding: .utf8)
        XCTAssertContains(extractorArgs, "--browser")
        XCTAssertContains(extractorArgs, "safari")

        let unknown = try environment.run(["auth", "wat"])
        XCTAssertEqual(unknown.status, 2)
        XCTAssertContains(unknown.cleanOutput, "Unknown auth command: wat")
    }

    func testInteractiveAuthGenerateRefreshesCredentialsInPlace() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let extractorLog = environment.scratchURL.appendingPathComponent("interactive-extractor-args.txt")
        let extractor = environment.scratchURL.appendingPathComponent("fake_interactive_cookie_extractor.py")
        let extractorScript = """
        import json
        import sys
        args = sys.argv[1:]
        with open("\(extractorLog.path)", "w") as log:
            log.write("\\n".join(args))
        output = args[args.index("--output") + 1]
        with open(output, "w") as handle:
            json.dump({"x-anonuserid": "interactive-generated", "sso": "cookie"}, handle)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)

        let run = try environment.run(
            [],
            input: "auth\nquit\n",
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Successfully generated credentials!")
        XCTAssertContains(run.cleanOutput, "Goodbye!")
        XCTAssertContains(try String(contentsOf: environment.credentialsURL, encoding: .utf8), "interactive-generated")

        let extractorArgs = try String(contentsOf: extractorLog, encoding: .utf8)
        XCTAssertContains(extractorArgs, "--format")
        XCTAssertContains(extractorArgs, "--required")
        XCTAssertContains(extractorArgs, "--output")
    }

    func testInteractiveAuthBrowserShortcutRefreshesCredentialsInPlace() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let extractorLog = environment.scratchURL.appendingPathComponent("interactive-browser-extractor-args.txt")
        let extractor = environment.scratchURL.appendingPathComponent("fake_interactive_browser_cookie_extractor.py")
        let extractorScript = """
        import json
        import sys
        args = sys.argv[1:]
        with open("\(extractorLog.path)", "w") as log:
            log.write("\\n".join(args))
        output = args[args.index("--output") + 1]
        with open(output, "w") as handle:
            json.dump({"x-anonuserid": "interactive-safari", "sso": "cookie"}, handle)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)

        let run = try environment.run(
            [],
            input: "auth safari --quiet\nquit\n",
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(run.cleanOutput.contains("Successfully generated credentials!"))
        XCTAssertContains(run.cleanOutput, "Goodbye!")
        XCTAssertContains(try String(contentsOf: environment.credentialsURL, encoding: .utf8), "interactive-safari")

        let extractorArgs = try String(contentsOf: extractorLog, encoding: .utf8)
        XCTAssertContains(extractorArgs, "--browser")
        XCTAssertContains(extractorArgs, "safari")
    }

    func testInteractiveAuthErrorAutomaticallyRefreshesFromBrowser() throws {
        let server = try MockGrokServer(unauthorizedNewConversationCount: 1)
        let environment = try TestEnvironment(server: server)
        let extractor = environment.scratchURL.appendingPathComponent("fake_refresh_cookie_extractor.py")
        let extractorScript = """
        import json
        import sys
        args = sys.argv[1:]
        output = args[args.index("--output") + 1]
        with open(output, "w") as handle:
            json.dump({"x-anonuserid": "refreshed", "sso": "cookie"}, handle)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)

        let run = try environment.run(
            [],
            input: "first message with expired cookies\nsecond message after refresh\nquit\n",
            timeout: 15,
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Authentication failed. Your saved Grok browser cookies may have expired.")
        XCTAssertContains(run.cleanOutput, "Trying to refresh credentials from your browser...")
        XCTAssertContains(run.cleanOutput, "Successfully refreshed credentials from browser.")
        XCTAssertContains(run.cleanOutput, "Mock streamed answer")
        XCTAssertContains(try String(contentsOf: environment.credentialsURL, encoding: .utf8), "refreshed")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").count, 2)
    }

    func testInteractiveAntiBotErrorRefreshesBrowserEnvelope() throws {
        let server = try MockGrokServer(antiBotNewConversationCount: 1)
        let environment = try TestEnvironment(server: server)
        let extractor = environment.scratchURL.appendingPathComponent("fake_antibot_cookie_extractor.py")
        let extractorScript = """
        import json
        import sys
        args = sys.argv[1:]
        output = args[args.index("--output") + 1]
        with open(output, "w") as handle:
            json.dump({
                "x-anonuserid": "refreshed-anon",
                "cf_clearance": "refreshed-cf",
                "__cf_bm": "refreshed-bm",
                "grok_device_id": "refreshed-device"
            }, handle)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)

        let run = try environment.run(
            [],
            input: "first message trips anti bot\nsecond message after envelope refresh\nquit\n",
            timeout: 15,
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Grok rejected the CLI browser request for Fast (fast)")
        XCTAssertContains(run.cleanOutput, "not model access")
        XCTAssertFalse(run.cleanOutput.contains("Switch models"))
        XCTAssertContains(run.cleanOutput, "Grok rejected this CLI request as automated")
        XCTAssertContains(run.cleanOutput, "Trying to refresh credentials from your browser...")
        XCTAssertContains(run.cleanOutput, "Successfully refreshed credentials from browser.")
        let credentials = try String(contentsOf: environment.credentialsURL, encoding: .utf8)
        XCTAssertContains(credentials, "refreshed-cf")
        XCTAssertContains(credentials, "refreshed-bm")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").count, 2)
    }

    func testInteractiveModelAccessErrorDoesNotRefreshCredentials() throws {
        let server = try MockGrokServer(accessDeniedNewConversationCount: 1, heavyRequiresUpgrade: false)
        let environment = try TestEnvironment(server: server)
        let extractor = environment.scratchURL.appendingPathComponent("unexpected_refresh_cookie_extractor.py")
        let extractorMarker = environment.scratchURL.appendingPathComponent("extractor_was_called")
        let extractorScript = """
        import pathlib
        import sys
        pathlib.Path("\(extractorMarker.path)").write_text("\\n".join(sys.argv[1:]))
        raise SystemExit(1)
        """
        try extractorScript.write(to: extractor, atomically: true, encoding: .utf8)
        let originalCredentials = try String(contentsOf: environment.credentialsURL, encoding: .utf8)

        let run = try environment.run(
            [],
            input: "/model heavy\nhello\nquit\n",
            timeout: 15,
            extraEnvironment: ["GROK_COOKIE_EXTRACTOR": extractor.path]
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Model set to: Heavy (heavy)")
        XCTAssertContains(run.cleanOutput, "Grok denied access to Heavy (heavy)")
        XCTAssertContains(run.cleanOutput, "Switch models")
        XCTAssertFalse(run.cleanOutput.contains("ThinkingError"))
        XCTAssertFalse(run.cleanOutput.contains("Authentication failed. Your saved Grok browser cookies may have expired."))
        XCTAssertFalse(run.cleanOutput.contains("Trying to refresh credentials from your browser..."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractorMarker.path))
        XCTAssertEqual(try String(contentsOf: environment.credentialsURL, encoding: .utf8), originalCredentials)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last?.jsonString("modeId"), "heavy")
    }

    func testInteractiveUnavailableModelCannotBeSelected() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            [],
            input: "/model heavy\nhello\nquit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Model unavailable: Heavy (heavy) - Requires TIER_SUPERGROK_HEAVY")
        XCTAssertFalse(run.cleanOutput.contains("Model set to: Heavy (heavy)"))
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last?.jsonString("modeId"), "fast")
    }

    func testListTasksSkillsAgentsWorkspacesAndFilesCommands() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let instructionFile = environment.scratchURL.appendingPathComponent("agent-instructions.txt")
        try "file instructions".write(to: instructionFile, atomically: true, encoding: .utf8)
        let uploadFile = environment.scratchURL.appendingPathComponent("upload.md")
        try "# Upload me\n".write(to: uploadFile, atomically: true, encoding: .utf8)

        let list = try environment.run(["list"], input: "1\n")
        XCTAssertEqual(list.status, 0)
        XCTAssertContains(list.cleanOutput, "Available conversations:")
        XCTAssertContains(list.cleanOutput, "Mock Conversation")
        XCTAssertContains(list.cleanOutput, "Loaded assistant response")

        let tasksList = try environment.run(["tasks"])
        XCTAssertEqual(tasksList.status, 0)
        XCTAssertContains(tasksList.cleanOutput, "Tasks")

        let tasksHelp = try environment.run(["tasks", "help"])
        XCTAssertEqual(tasksHelp.status, 0)
        XCTAssertContains(tasksHelp.cleanOutput, "Tasks:")
        XCTAssertFalse(tasksHelp.cleanOutput.contains("Error:"))

        let tasksFlagHelp = try environment.run(["tasks", "--help"])
        XCTAssertEqual(tasksFlagHelp.status, 0)
        XCTAssertContains(tasksFlagHelp.cleanOutput, "Tasks:")
        XCTAssertFalse(tasksFlagHelp.cleanOutput.contains("Error:"))

        let taskCreateHelp = try environment.run(["tasks", "create", "--help"])
        XCTAssertEqual(taskCreateHelp.status, 0)
        XCTAssertContains(taskCreateHelp.cleanOutput, "Usage: grok tasks create")
        XCTAssertFalse(taskCreateHelp.cleanOutput.contains("Error:"))

        let tasksJSON = try environment.run(["tasks", "list", "--format=json"])
        XCTAssertEqual(tasksJSON.status, 0)
        XCTAssertContains(tasksJSON.cleanOutput, "\"taskId\"")

        let taskCreate = try environment.run([
            "tasks", "create",
            "--prompt", "check command coverage",
            "--name=Coverage",
            "--date", "2026-05-14",
            "--time=09:30",
            "--timezone", "UTC",
            "--guideline", "notify",
            "--model-mode", "BASE"
        ])
        XCTAssertEqual(taskCreate.status, 0)
        XCTAssertContains(taskCreate.cleanOutput, "Created task")
        XCTAssertEqual(server.requests(matchingPath: "/rest/tasks", method: "POST").last?.jsonString("prompt"), "check command coverage")

        let taskArchive = try environment.run(["tasks", "archive", "task-1", "--format", "json"])
        XCTAssertEqual(taskArchive.status, 0)
        XCTAssertContains(taskArchive.cleanOutput, "\"taskId\"")
        XCTAssertEqual(server.requests(matchingPath: "/rest/tasks/archive", method: "PUT").last?.jsonString("taskId"), "task-1")

        let skillsList = try environment.run(["skills"])
        XCTAssertEqual(skillsList.status, 0)
        XCTAssertContains(skillsList.cleanOutput, "Grok Skills")
        XCTAssertContains(skillsList.cleanOutput, "Mock Skill | Mock skill description")
        XCTAssertFalse(skillsList.cleanOutput.contains("Name: Mock Skill"))
        XCTAssertContains(skillsList.cleanOutput, "User Skills")
        XCTAssertContains(skillsList.cleanOutput, "User Skill | Mock skill description")

        let skillsHelp = try environment.run(["skills", "--help"])
        XCTAssertEqual(skillsHelp.status, 0)
        XCTAssertContains(skillsHelp.cleanOutput, "Skills:")
        XCTAssertFalse(skillsHelp.cleanOutput.contains("Error:"))

        let skillsMine = try environment.run(["skills", "mine", "--format=json"])
        XCTAssertEqual(skillsMine.status, 0)
        XCTAssertContains(skillsMine.cleanOutput, "user-skill-1")

        let skillsUser = try environment.run(["skills", "user"])
        XCTAssertEqual(skillsUser.status, 0)
        XCTAssertContains(skillsUser.cleanOutput, "User Skills")

        let agentsList = try environment.run(["agents"])
        XCTAssertEqual(agentsList.status, 0)
        XCTAssertContains(agentsList.cleanOutput, "Agents:")
        XCTAssertContains(agentsList.cleanOutput, "ID: 1 | Name: Grok II | Instructions:")
        XCTAssertFalse(agentsList.cleanOutput.contains("ID: 1 | Name: Grok II | Instructions: empty"))

        let agentsListJSON = try environment.run(["agents", "list", "--json"])
        XCTAssertEqual(agentsListJSON.status, 0)
        XCTAssertFalse(agentsListJSON.stdout.contains("Skeptical agent instructions"))
        let agentsData = try assertResultEnvelope(
            try jsonObject(from: agentsListJSON),
            command: "agents",
            subcommand: "list",
            category: "resource_list"
        )
        let agentItems = try XCTUnwrap(agentsData["items"] as? [[String: Any]])
        XCTAssertEqual(agentItems.first(where: { $0["agentId"] as? Int == 1 })?["instructionsRedacted"] as? Bool, true)
        XCTAssertNil(agentItems.first(where: { $0["agentId"] as? Int == 1 })?["instructions"])

        let agentsListWithInstructions = try environment.run(["agents", "list", "--include-instructions", "--json"])
        XCTAssertEqual(agentsListWithInstructions.status, 0)
        XCTAssertContains(agentsListWithInstructions.stdout, "Skeptical agent instructions")

        let agentsHelp = try environment.run(["agents", "help"])
        XCTAssertEqual(agentsHelp.status, 0)
        XCTAssertContains(agentsHelp.cleanOutput, "Agents:")
        XCTAssertContains(agentsHelp.cleanOutput, "grok agents show <agentId>")
        XCTAssertContains(agentsHelp.cleanOutput, "grok agents edit <agentId>")
        XCTAssertContains(agentsHelp.cleanOutput, "grok agents set <agentId> --instructions <text>")
        XCTAssertFalse(agentsHelp.cleanOutput.contains("Error:"))

        let agentsShow = try environment.run(["agents", "show", "1"])
        XCTAssertEqual(agentsShow.status, 0)
        XCTAssertContains(agentsShow.cleanOutput, "Agent 1: Grok II")
        XCTAssertContains(agentsShow.cleanOutput, "Skeptical agent instructions")

        let agentsSetHelp = try environment.run(["agents", "set", "--help"])
        XCTAssertEqual(agentsSetHelp.status, 0)
        XCTAssertContains(agentsSetHelp.cleanOutput, "grok agents set <agentId>")
        XCTAssertFalse(agentsSetHelp.cleanOutput.contains("Error:"))

        let agentsSet = try environment.run(["agents", "set", "1", "--instructions", "be precise", "--name", "Careful", "--replace"])
        XCTAssertEqual(agentsSet.status, 0)
        XCTAssertContains(agentsSet.cleanOutput, "Updated agent 1")
        XCTAssertContains(agentsSet.cleanOutput, "Name: Careful")

        let agentsSetFile = try environment.run(["agents", "set", "2", "--file", instructionFile.path, "--replace", "--include-instructions", "--format", "json"])
        XCTAssertEqual(agentsSetFile.status, 0)
        XCTAssertContains(agentsSetFile.cleanOutput, "file instructions")

        let editorScript = environment.scratchURL.appendingPathComponent("edit-agent.sh")
        try """
        #!/usr/bin/env bash
        printf 'edited from editor\\nsecond line\\n' > "$1"
        """.write(to: editorScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: editorScript.path)

        let agentsEdit = try environment.run(["agents", "edit", "1"], extraEnvironment: ["EDITOR": editorScript.path])
        XCTAssertEqual(agentsEdit.status, 0)
        XCTAssertContains(agentsEdit.cleanOutput, "Updated agent 1")

        let editRequest = try XCTUnwrap(server.requests(matchingPath: "/rest/user-settings", method: "POST").last)
        let editSettings = try XCTUnwrap(editRequest.json["agentCustomizations"] as? [String: Any])
        let editValues = try XCTUnwrap(editSettings["values"] as? [[String: Any]])
        XCTAssertEqual(editValues.count, 4)
        XCTAssertEqual(editValues.first(where: { $0["agentId"] as? Int == 1 })?["instructions"] as? String, "edited from editor\nsecond line\n")
        XCTAssertEqual(editValues.first(where: { $0["agentId"] as? Int == 2 })?["instructions"] as? String, "Optimistic agent instructions")

        let agentsClear = try environment.run(["agents", "clear", "2", "--replace"])
        XCTAssertEqual(agentsClear.status, 0)
        XCTAssertContains(agentsClear.cleanOutput, "Cleared agent 2 instructions")

        let invalidAgent = try environment.run(["agents", "clear", "9"])
        XCTAssertEqual(invalidAgent.status, 2)
        XCTAssertContains(invalidAgent.cleanOutput, "Invalid agent ID")

        let workspacesList = try environment.run(["workspaces"])
        XCTAssertEqual(workspacesList.status, 0)
        XCTAssertContains(workspacesList.cleanOutput, "Workspaces:")

        let workspacesHelp = try environment.run(["workspaces", "help"])
        XCTAssertEqual(workspacesHelp.status, 0)
        XCTAssertContains(workspacesHelp.cleanOutput, "Workspaces:")
        XCTAssertFalse(workspacesHelp.cleanOutput.contains("Error:"))

        let workspaceCreateHelp = try environment.run(["workspaces", "create", "--help"])
        XCTAssertEqual(workspaceCreateHelp.status, 0)
        XCTAssertContains(workspaceCreateHelp.cleanOutput, "Usage: grok workspaces create")
        XCTAssertFalse(workspaceCreateHelp.cleanOutput.contains("Error:"))

        let workspaceAlias = try environment.run(["workspace", "list", "--format=json"])
        XCTAssertEqual(workspaceAlias.status, 0)
        XCTAssertContains(workspaceAlias.cleanOutput, "workspace-1")

        let workspaceCreate = try environment.run([
            "workspaces", "create",
            "--name", "Project One",
            "--icon=star",
            "--personality", "Focused",
            "--model", "expert"
        ])
        XCTAssertEqual(workspaceCreate.status, 0)
        XCTAssertContains(workspaceCreate.cleanOutput, "Created workspace")
        XCTAssertEqual(server.requests(matchingPath: "/rest/workspaces", method: "POST").last?.jsonString("name"), "Project One")

        let addConversation = try environment.run(["workspaces", "add-conversation", "workspace-1", "conv-e2e", "--format", "json"])
        XCTAssertEqual(addConversation.status, 0)
        XCTAssertContains(addConversation.cleanOutput, "workspace-1")

        let deleteWorkspace = try environment.run(["workspaces", "delete", "workspace-1"])
        XCTAssertEqual(deleteWorkspace.status, 0)
        XCTAssertContains(deleteWorkspace.cleanOutput, "Deleted workspace workspace-1")

        let removeWorkspace = try environment.run(["workspaces", "remove", "workspace-1"])
        XCTAssertEqual(removeWorkspace.status, 0)
        XCTAssertContains(removeWorkspace.cleanOutput, "Deleted workspace workspace-1")

        let conversation = try environment.run(["workspaces", "conversation", "conv-e2e"])
        XCTAssertEqual(conversation.status, 0)
        XCTAssertContains(conversation.cleanOutput, "Conversation: conv-e2e")
        XCTAssertContains(conversation.cleanOutput, "TaskResult: yes")

        let filesList = try environment.run(["files", "list", "--page-size", "2"])
        XCTAssertEqual(filesList.status, 0)
        XCTAssertContains(filesList.cleanOutput, "Files:")
        XCTAssertContains(filesList.cleanOutput, "mock.txt")
        XCTAssertTrue(server.requests(matchingPath: "/rest/assets").last?.target.contains("pageSize=2") ?? false)

        let filesDefaultList = try environment.run(["files"])
        XCTAssertEqual(filesDefaultList.status, 0)
        XCTAssertContains(filesDefaultList.cleanOutput, "Files:")

        let filesHelp = try environment.run(["files", "--help"])
        XCTAssertEqual(filesHelp.status, 0)
        XCTAssertContains(filesHelp.cleanOutput, "Files:")
        XCTAssertFalse(filesHelp.cleanOutput.contains("Error:"))

        let filesUploadHelp = try environment.run(["files", "upload", "--help"])
        XCTAssertEqual(filesUploadHelp.status, 0)
        XCTAssertContains(filesUploadHelp.cleanOutput, "Usage: grok files upload")
        XCTAssertFalse(filesUploadHelp.cleanOutput.contains("Error:"))

        let filesUpload = try environment.run(["files", "upload", uploadFile.path, "--mime", "text/markdown", "--format=json"])
        XCTAssertEqual(filesUpload.status, 0)
        XCTAssertContains(filesUpload.cleanOutput, "uploaded-file-1")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/upload-file", method: "POST").last?.jsonString("fileMimeType"), "text/markdown")

        let filesDelete = try environment.run(["files", "delete", "file-1", "--json"])
        XCTAssertEqual(filesDelete.status, 0)
        let filesDeleteData = try assertResultEnvelope(
            try jsonObject(from: filesDelete),
            command: "files",
            subcommand: "delete",
            category: "resource_mutation"
        )
        XCTAssertEqual(filesDeleteData["id"] as? String, "file-1")
        XCTAssertEqual(server.requests(matchingPath: "/rest/assets/file-1", method: "DELETE").count, 1)

        let filesMissingPath = try environment.run(["files", "upload"])
        XCTAssertEqual(filesMissingPath.status, 2)
        XCTAssertContains(filesMissingPath.cleanOutput, "Missing file path.")
    }

    func testSkillsListSeparatesBuiltInAndUserSkills() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["skills", "list"])

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Grok Skills")
        XCTAssertContains(run.cleanOutput, "Mock Skill | Mock skill description")
        XCTAssertContains(run.cleanOutput, "User Skills")
        XCTAssertContains(run.cleanOutput, "User Skill | Mock skill description")
        XCTAssertFalse(run.cleanOutput.contains("Name:"))
        XCTAssertFalse(run.cleanOutput.contains("Description:"))
        XCTAssertEqual(server.requests(matchingPath: "/rest/skills", method: "POST").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/user-skills", method: "GET").count, 1)
    }

    func testSkillsListOmitsUserSkillsSectionWhenEmpty() throws {
        let server = try MockGrokServer(userSkills: [])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["skills"])

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Grok Skills")
        XCTAssertContains(run.cleanOutput, "Mock Skill | Mock skill description")
        XCTAssertFalse(run.cleanOutput.contains("User Skills"))
    }

    func testSkillsListJSONIncludesSeparateUserSkillsField() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["skills", "--json"])

        XCTAssertEqual(run.status, 0)
        let data = try assertResultEnvelope(
            try jsonObject(from: run),
            command: "skills",
            subcommand: "list",
            category: "resource_list"
        )
        let items = try XCTUnwrap(data["items"] as? [[String: Any]])
        let userSkills = try XCTUnwrap(data["userSkills"] as? [[String: Any]])
        XCTAssertEqual(items.first?["name"] as? String, "Mock Skill")
        XCTAssertEqual(userSkills.first?["name"] as? String, "User Skill")
    }

    func testSubcommandHelpMatrixUsesRegularOutput() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let cases: [([String], String)] = [
            (["agents", "list", "--help"], "Usage: grok agents list"),
            (["agents", "show", "--help"], "Usage: grok agents show"),
            (["agents", "edit", "--help"], "Usage: grok agents edit"),
            (["agents", "clear", "--help"], "Usage: grok agents clear"),
            (["tasks", "list", "--help"], "Usage: grok tasks list"),
            (["tasks", "inactive", "--help"], "Usage: grok tasks inactive"),
            (["tasks", "show", "--help"], "Usage: grok tasks show"),
            (["tasks", "detail", "--help"], "Usage: grok tasks show"),
            (["tasks", "results", "--help"], "Usage: grok tasks results"),
            (["tasks", "archive", "--help"], "Usage: grok tasks archive"),
            (["skills", "list", "--help"], "Usage: grok skills list"),
            (["skills", "mine", "--help"], "Usage: grok skills mine"),
            (["skills", "user", "--help"], "Usage: grok skills user"),
            (["workspaces", "list", "--help"], "Usage: grok workspaces list"),
            (["workspaces", "add-conversation", "--help"], "Usage: grok workspaces add-conversation"),
            (["workspaces", "delete", "--help"], "Usage: grok workspaces delete"),
            (["workspaces", "remove", "--help"], "Usage: grok workspaces delete"),
            (["workspaces", "conversation", "--help"], "Usage: grok workspaces conversation"),
            (["files", "list", "--help"], "Usage: grok files list"),
            (["files", "upload", "--help"], "Usage: grok files upload"),
            (["files", "delete", "--help"], "Usage: grok files delete")
        ]

        for (arguments, expectedOutput) in cases {
            let run = try environment.run(arguments)
            XCTAssertEqual(run.status, 0, arguments.joined(separator: " "))
            XCTAssertContains(run.cleanOutput, expectedOutput)
            XCTAssertFalse(run.cleanOutput.contains("Error:"), arguments.joined(separator: " "))
        }

        XCTAssertTrue(server.requests().isEmpty)
    }

    func testInteractiveSlashCommandsEndToEnd() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let uploadFile = environment.scratchURL.appendingPathComponent("attached.txt")
        try "attachment".write(to: uploadFile, atomically: true, encoding: .utf8)

        let script = """

        /help
        /new
        /reasoning
        /private
        /stream
        /model list
        /model expert
        /mode raw-interactive-mode
        /resume
        1
        /tasks list
        /skills user
        /agents list
        /workspaces list
        /workspace
        0
        /files list
        /attach
        1
        /attach clear
        /attach upload \(uploadFile.path)
        /attach manual-file-id
        hello from interactive
        help
        quit
        """

        let run = try environment.run([], input: script, timeout: 15)
        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Connected to Grok!")
        XCTAssertContains(run.cleanOutput, "Basic Commands:")
        XCTAssertContains(run.cleanOutput, "Started a new conversation thread.")
        XCTAssertContains(run.cleanOutput, "/reason is deprecated and ignored")
        XCTAssertFalse(run.cleanOutput.contains("Search: Auto"))
        XCTAssertContains(run.cleanOutput, "/search <query>")
        XCTAssertFalse(run.cleanOutput.contains("/deepsearch"))
        XCTAssertFalse(run.cleanOutput.contains("/realtime"))
        XCTAssertFalse(run.cleanOutput.contains("/personality"))
        XCTAssertFalse(run.cleanOutput.contains("Custom Instructions"))
        XCTAssertFalse(run.cleanOutput.contains("/custom-instructions"))
        XCTAssertFalse(run.cleanOutput.contains("/edit-instructions"))
        XCTAssertFalse(run.cleanOutput.contains("/reset-instructions"))
        XCTAssertContains(run.cleanOutput, "Private mode: ENABLED")
        XCTAssertContains(run.cleanOutput, "Streaming: DISABLED")
        XCTAssertContains(run.cleanOutput, "Available web modes:")
        XCTAssertContains(run.cleanOutput, "Model set to: Expert (expert)")
        XCTAssertContains(run.cleanOutput, "Model set to: raw-interactive-mode (raw-interactive-mode)")
        XCTAssertContains(run.cleanOutput, "Mock Conversation")
        XCTAssertContains(run.cleanOutput, "User Skills")
        XCTAssertContains(run.cleanOutput, "Agents:")
        XCTAssertContains(run.cleanOutput, "Workspaces:")
        XCTAssertContains(run.cleanOutput, "Workspace cleared.")
        XCTAssertContains(run.cleanOutput, "Files:")
        XCTAssertContains(run.cleanOutput, "Attached: mock.txt")
        XCTAssertContains(run.cleanOutput, "Cleared attached files.")
        XCTAssertContains(run.cleanOutput, "Uploaded and attached: attached.txt")
        XCTAssertContains(run.cleanOutput, "Attached file ID: manual-file-id")
        XCTAssertFalse(run.cleanOutput.contains("Special mode activated."))
        XCTAssertContains(run.cleanOutput, "Goodbye!")

        let chatRequests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertTrue(chatRequests.contains { $0.jsonString("message")?.contains("hello from interactive") == true })
        XCTAssertTrue(chatRequests.contains { $0.jsonString("modeId") == "raw-interactive-mode" })
        XCTAssertTrue(chatRequests.contains {
            ($0.json["fileAttachments"] as? [Any])?.contains { ($0 as? String) == "manual-file-id" } == true
        })
    }

    func testInteractivePrivateOnStartsNewPrivateThreadAfterExistingConversation() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            [],
            input: "saved thread message\n/private on\nprivate thread message\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Started a new private conversation thread.")
        XCTAssertContains(run.cleanOutput, "Private mode: ENABLED")

        let chatRequests = server.requests(method: "POST")
            .filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertEqual(chatRequests.count, 2)
        XCTAssertEqual(chatRequests[0].path, "/rest/app-chat/conversations/new")
        XCTAssertEqual(chatRequests[0].jsonString("message"), "saved thread message")
        XCTAssertEqual(chatRequests[0].jsonBool("temporary"), false)
        XCTAssertEqual(chatRequests[1].path, "/rest/app-chat/conversations/new")
        XCTAssertEqual(chatRequests[1].jsonString("message"), "private thread message")
        XCTAssertEqual(chatRequests[1].jsonBool("temporary"), true)
        XCTAssertFalse(chatRequests.contains { $0.path.hasSuffix("/responses") })
    }

    func testInteractiveGoalCompletionMarkerStopsLoop() throws {
        let server = try MockGrokServer(
            streamTokens: [],
            finalMessage: "Audit complete\n<grok_goal status=\"complete\">"
        )
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/goal write release note\nquit\n", timeout: 10)

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Goal started")
        XCTAssertContains(run.cleanOutput, "Goal complete")
        let chatRequests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertEqual(chatRequests.count, 1)
        XCTAssertContains(chatRequests[0].jsonString("message") ?? "", "<grok_goal_request>")
        XCTAssertContains(chatRequests[0].jsonString("message") ?? "", "write release note")
        XCTAssertContains(chatRequests[0].jsonString("message") ?? "", #"<grok_goal status="complete">"#)
    }

    func testInteractiveGoalContinuesUntilMaxTurns() throws {
        let server = try MockGrokServer(streamTokens: [], finalMessage: "Still working")
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/goal --max-turns 2 ship docs\nquit\n", timeout: 10)

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Goal stopped after 2 turns.")
        let chatRequests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertEqual(chatRequests.count, 2)
        XCTAssertEqual(chatRequests[0].path, "/rest/app-chat/conversations/new")
        XCTAssertTrue(chatRequests[1].path.hasSuffix("/responses"))
        XCTAssertContains(chatRequests[1].jsonString("message") ?? "", "<grok_goal_continuation>")
        XCTAssertContains(chatRequests[1].jsonString("message") ?? "", "Goal loop turn 2 of 2")
    }

    func testInteractiveGoalPauseResumeAndClear() throws {
        let server = try MockGrokServer(
            streamTokens: [],
            finalMessage: "Blocked\n<grok_goal status=\"pause\">"
        )
        let environment = try TestEnvironment(server: server)

        let script = """
        /goal blocked task
        /goal pause
        /goal resume
        /goal clear
        /goal
        quit
        """

        let run = try environment.run([], input: script, timeout: 10)

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Goal paused")
        XCTAssertContains(run.cleanOutput, "Goal resumed")
        XCTAssertContains(run.cleanOutput, "Goal cleared")
        XCTAssertContains(run.cleanOutput, "No active goal.")
        let chatRequests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertEqual(chatRequests.count, 2)
        XCTAssertContains(chatRequests[1].jsonString("message") ?? "", "<grok_goal_continuation>")
    }

    func testInteractiveGoalNewClearsGoal() throws {
        let server = try MockGrokServer(streamTokens: [], finalMessage: "Still working")
        let environment = try TestEnvironment(server: server)

        let script = """
        /goal --max-turns 1 lingering task
        /new
        /goal
        quit
        """

        let run = try environment.run([], input: script, timeout: 10)

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Goal stopped after 1 turns.")
        XCTAssertContains(run.cleanOutput, "Started a new conversation thread.")
        XCTAssertContains(run.cleanOutput, "No active goal.")
        let chatRequests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertEqual(chatRequests.count, 1)
    }

    func testInteractiveCommandRouterHandlesBareAliasesQuotingAndBoundaries() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let uploadFile = environment.scratchURL.appendingPathComponent("file with spaces.txt")
        try "attachment with spaces".write(to: uploadFile, atomically: true, encoding: .utf8)

        let script = """

          /HELP
        new
        reasoning on
        private off
        stream on
        models list
        mode expert
        /TASKS list
        /tasks create --prompt "quoted prompt value" --name "Quoted Task"
        tasks create --prompt "bare quoted prompt" --name "Bare Task"
        /workspaces
        /workspace
        0
        /workspaces create --name "Research Notes" --personality "Deep Focus" --model expert
        /files
        /files upload "\(uploadFile.path)"
        /attach upload "\(uploadFile.path)"
        /taskslater should be chat
        model this should remain chat
        /auth help
        /QUIT
        """

        let run = try environment.run([], input: script, timeout: 15)
        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Basic Commands:")
        XCTAssertContains(run.cleanOutput, "Started a new conversation thread.")
        XCTAssertContains(run.cleanOutput, "/reason is deprecated and ignored")
        XCTAssertFalse(run.cleanOutput.contains("Search: Auto"))
        XCTAssertContains(run.cleanOutput, "/search <query>")
        XCTAssertFalse(run.cleanOutput.contains("/deepsearch"))
        XCTAssertFalse(run.cleanOutput.contains("/realtime"))
        XCTAssertFalse(run.cleanOutput.contains("/personality"))
        XCTAssertFalse(run.cleanOutput.contains("Custom Instructions"))
        XCTAssertFalse(run.cleanOutput.contains("/custom-instructions"))
        XCTAssertFalse(run.cleanOutput.contains("/edit-instructions"))
        XCTAssertFalse(run.cleanOutput.contains("/reset-instructions"))
        XCTAssertContains(run.cleanOutput, "Private mode: DISABLED")
        XCTAssertContains(run.cleanOutput, "Streaming: ENABLED")
        XCTAssertContains(run.cleanOutput, "Available web modes:")
        XCTAssertContains(run.cleanOutput, "Model set to: Expert (expert)")
        XCTAssertContains(run.cleanOutput, "Tasks")
        XCTAssertContains(run.cleanOutput, "Created task")
        XCTAssertContains(run.cleanOutput, "Workspaces:")
        XCTAssertContains(run.cleanOutput, "Workspace cleared.")
        XCTAssertContains(run.cleanOutput, "Created workspace")
        XCTAssertContains(run.cleanOutput, "Files:")
        XCTAssertContains(run.cleanOutput, "Uploaded file")
        XCTAssertContains(run.cleanOutput, "Uploaded and attached: file with spaces.txt")
        XCTAssertContains(run.cleanOutput, "Unknown command /taskslater")
        XCTAssertContains(run.cleanOutput, "Run /help for commands")
        XCTAssertContains(run.cleanOutput, "Auth commands:")
        XCTAssertContains(run.cleanOutput, "Goodbye!")

        let taskCreateRequests = server.requests(matchingPath: "/rest/tasks", method: "POST")
        XCTAssertTrue(taskCreateRequests.contains { $0.jsonString("prompt") == "quoted prompt value" })
        XCTAssertTrue(taskCreateRequests.contains { $0.jsonString("prompt") == "bare quoted prompt" })

        let workspaceCreateRequests = server.requests(matchingPath: "/rest/workspaces", method: "POST")
        XCTAssertTrue(workspaceCreateRequests.contains { $0.jsonString("name") == "Research Notes" })

        let uploadRequests = server.requests(matchingPath: "/rest/app-chat/upload-file", method: "POST")
        XCTAssertEqual(uploadRequests.last?.jsonString("fileName"), "file with spaces.txt")

        let chatMessages = server.requests(method: "POST")
            .filter { $0.path.contains("/rest/app-chat/conversations") }
            .compactMap { $0.jsonString("message") }
        XCTAssertTrue(chatMessages.contains("model this should remain chat"))
        XCTAssertFalse(chatMessages.contains("models list"))
        XCTAssertFalse(chatMessages.contains("/taskslater should be chat"))
    }

    func testInteractiveGroupHelpUsesRegularOutput() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(
            [],
            input: "/agents help\n/tasks help\n/skills help\n/workspaces help\n/files help\n/wat\n/quit\n"
        )
        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Agents:")
        XCTAssertFalse(run.cleanOutput.contains("sync-custom"))
        XCTAssertContains(run.cleanOutput, "Tasks:")
        XCTAssertContains(run.cleanOutput, "Skills:")
        XCTAssertContains(run.cleanOutput, "Workspaces:")
        XCTAssertContains(run.cleanOutput, "Files:")
        XCTAssertContains(run.cleanOutput, "Unknown command /wat")
        XCTAssertFalse(run.cleanOutput.contains("Error:"))
    }

    func testInteractiveSkillCreateStartsGrok43ConversationAndTracksIt() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)
        let prompt = "skill to take over the world and earn $1M in ARR in the next 30 days with or without world domination"

        let run = try environment.run(
            [],
            input: "hello before skill\n/skill create \(prompt)\nwhat did you create?\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Mock streamed answer")
        XCTAssertContains(run.cleanOutput, "Goodbye!")

        let createRequests = server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST")
        XCTAssertEqual(createRequests.count, 2)
        XCTAssertEqual(createRequests.first?.jsonString("message"), "hello before skill")
        let skillRequest = try XCTUnwrap(createRequests.last)
        XCTAssertEqual(skillRequest.jsonString("message"), "skill-creator skill \(prompt)")
        XCTAssertEqual(skillRequest.jsonString("modeId"), "grok-420-computer-use-sa")

        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "what did you create?")
        XCTAssertEqual(followUp.jsonString("modeId"), "grok-420-computer-use-sa")
    }

    func testInteractiveHelpDoesNotIncludeDedicatedAgentCommandSection() {
        let formatter = OutputFormatter(useMarkdown: false)

        let output = strippingANSI(captureStdout {
            formatter.printHelp()
        })

        XCTAssertContains(output, "Slash Commands:")
        XCTAssertContains(output, "/agents")
        XCTAssertFalse(output.contains("Agent Commands:"))
        XCTAssertFalse(output.contains("grok agents set 0 --instructions <text>"))
    }

    func testHUDRendererShowsProjectFirstStatusAndWarnings() {
        var state = CLIHUDState(
            modelName: "Expert",
            workspaceName: "Research Notes",
            privateMode: false,
            stream: true,
            outputFormat: .markdown,
            attachedFileCount: 2,
            rateLimitWarning: nil
        )

        let status = strippingANSI(CLIHUDRenderer.lines(state: state, width: 120).joined(separator: "\n"))
        XCTAssertContains(status, "Research Notes > Expert | MD | 2 files")
        XCTAssertFalse(status.contains("model:"))
        XCTAssertFalse(status.contains("workspace:"))
        XCTAssertFalse(status.contains("/ commands"))

        state.privateMode = true
        state.stream = false
        state.rateLimitWarning = "2 left | reset 14m"
        let warning = strippingANSI(CLIHUDRenderer.lines(state: state, width: 120).joined(separator: "\n"))
        XCTAssertContains(warning, "Research Notes > Private | Expert | MD | Stream off | 2 files")
        XCTAssertContains(warning, "Limit > 2 left | reset 14m")

        let narrow = strippingANSI(CLIHUDRenderer.lines(state: state, width: 32).joined(separator: "\n"))
        XCTAssertTrue(narrow.split(separator: "\n").allSatisfy { $0.count <= 32 })

        state = CLIHUDState(
            modelName: "Grok 4.3 (beta)",
            workspaceName: nil,
            privateMode: false,
            stream: true,
            outputFormat: .markdown,
            attachedFileCount: 0,
            rateLimitWarning: nil
        )
        let defaultStatus = strippingANSI(CLIHUDRenderer.lines(state: state, width: 120).joined(separator: "\n"))
        XCTAssertContains(defaultStatus, "Grok > 4.3 (beta) | MD")
    }

    func testCommandRegistryIncludesHelpCommandsAndTypoHints() {
        let commands = GrokCLI.InteractiveCommandRegistry.visibleCommands.map(\.command).joined(separator: "\n")
        XCTAssertContains(commands, "/resume")
        XCTAssertContains(commands, "/search")
        XCTAssertFalse(commands.contains("/list"))
        XCTAssertContains(commands, "/model")
        XCTAssertContains(commands, "/workspace")
        XCTAssertFalse(commands.contains("/workspaces"))
        XCTAssertContains(commands, "/audio")
        XCTAssertContains(commands, "/share")
        XCTAssertContains(commands, "/limits")
        XCTAssertContains(commands, "/delete")
        XCTAssertContains(commands, "/goal")
        XCTAssertContains(commands, "/oauth")
        XCTAssertContains(commands, "/skill create")
        XCTAssertFalse(commands.contains("/reset-conversation"))
        XCTAssertFalse(commands.contains("/special"))

        let suggestion = GrokCLI.InteractiveCommandRegistry.nearestCommand(to: "wrkspace")
        XCTAssertEqual(suggestion?.command, "/workspace")
        let pluralSuggestion = GrokCLI.InteractiveCommandRegistry.nearestCommand(to: "workspaces")
        XCTAssertEqual(pluralSuggestion?.command, "/workspace")
        let listSuggestion = GrokCLI.InteractiveCommandRegistry.nearestCommand(to: "list")
        XCTAssertEqual(listSuggestion?.command, "/resume")
    }

    func testSlashCompletionShowsSingularWorkspaceCommandOnly() {
        let specs = GrokCLI.interactiveCommandSpecs
        let commands = specs.map(\.command)

        XCTAssertTrue(commands.contains("/workspace"))
        XCTAssertFalse(commands.contains("/workspaces"))
        XCTAssertTrue(commands.contains("/resume"))
        XCTAssertTrue(commands.contains("/search"))
        XCTAssertFalse(commands.contains("/list"))
        XCTAssertTrue(commands.contains("/limits"))
        XCTAssertTrue(commands.contains("/goal"))
        XCTAssertTrue(commands.contains("/oauth"))
        XCTAssertTrue(commands.contains("/skill create"))
        XCTAssertFalse(commands.contains("/special"))
        XCTAssertFalse(commands.contains("/reset-conversation"))
    }

    func testSpecialCompletionIsDisabled() {
        let reader = InputReader()

        XCTAssertFalse(reader.completionSuggestionDisplays(for: "/").contains("/special"))
        XCTAssertFalse(reader.completionSuggestionDisplays(for: "/spe").contains("/special"))
    }

    func testInputLineBufferCollapsesLargePasteAndExpandsOnSubmit() {
        let pastedText = String(repeating: "a", count: 160)
        var buffer = InputLineBuffer("summarize ")

        let cursor = buffer.insertPastedContent(pastedText, at: buffer.displayCount)

        XCTAssertEqual(buffer.display, "summarize [Pasted content 160 chars]")
        XCTAssertEqual(TerminalLayout.stripANSI(buffer.renderedDisplay), buffer.display)
        XCTAssertEqual(buffer.actual, "summarize \(pastedText)")
        XCTAssertEqual(cursor, buffer.displayCount)
    }

    func testInputLineBufferCollapsesMultilinePasteAndDeletesAtomically() {
        let pastedText = "line one\nline two\nline three"
        var buffer = InputLineBuffer("review ")
        let cursorAfterPaste = buffer.insertPastedContent(pastedText, at: buffer.displayCount)

        XCTAssertEqual(buffer.display, "review [Pasted content 28 chars]")
        XCTAssertEqual(buffer.actual, "review \(pastedText)")

        let cursorAfterDelete = buffer.backspace(at: cursorAfterPaste)

        XCTAssertEqual(cursorAfterDelete, "review ".count)
        XCTAssertEqual(buffer.display, "review ")
        XCTAssertEqual(buffer.actual, "review ")
    }

    func testInputLineBufferKeepsSmallSingleLinePasteInline() {
        var buffer = InputLineBuffer("say ")

        _ = buffer.insertPastedContent("hello", at: buffer.displayCount)

        XCTAssertEqual(buffer.display, "say hello")
        XCTAssertEqual(buffer.actual, "say hello")
    }

    func testInputReaderWrappedPromptMetricsAccountForLongInput() {
        XCTAssertEqual(InputReader.wrappedLineCount(visibleLength: 10, width: 80), 1)
        XCTAssertEqual(InputReader.wrappedLineCount(visibleLength: 81, width: 80), 2)

        let middle = InputReader.wrappedCursorPosition(visibleOffset: 95, visibleLength: 160, width: 80)
        XCTAssertEqual(middle.row, 1)
        XCTAssertEqual(middle.column, 15)

        let exactEnd = InputReader.wrappedCursorPosition(visibleOffset: 160, visibleLength: 160, width: 80)
        XCTAssertEqual(exactEnd.row, 1)
        XCTAssertEqual(exactEnd.column, 79)
    }

    func testInteractivePickerDoesNotHardTruncateTitlesAtTwentyTwoCharacters() {
        let title = "Lost Gospel: Jesus Babe Magnet"
        let item = PickerItem(id: "conv-1", title: title, subtitle: "recent", preview: nil, value: title)

        let lines = strippingANSI(InteractivePicker.lines(
            title: "Select conversation",
            query: "",
            items: [item],
            selectedIndex: 0,
            width: 80
        ).joined(separator: "\n"))

        XCTAssertContains(lines, title)
        XCTAssertFalse(lines.contains("Lost Gospel: Jesus Bab "))
    }

    func testInteractivePickerLabelsDateMetadataSeparatelyFromPreview() {
        let item = PickerItem(
            id: "conv-1",
            title: "Mock Conversation",
            subtitle: "modified 2026-05-13T00:00:00Z",
            metadataLabel: "modified",
            metadata: "2026-05-13T00:00:00Z",
            preview: "Actual last message\nSecond preview line",
            value: "conv-1"
        )

        let lines = strippingANSI(InteractivePicker.lines(
            title: "Select conversation",
            query: "",
            items: [item],
            selectedIndex: 0,
            width: 100
        ).joined(separator: "\n"))

        XCTAssertContains(lines, "\nmodified\n2026-05-13T00:00:00Z\n")
        XCTAssertContains(lines, "\npreview\nActual last message\nSecond preview line\n")
        XCTAssertFalse(lines.contains("\npreview\n2026-05-13T00:00:00Z"))
    }

    func testInteractivePickerCountsWrappedAndMultilinePreviewRowsForClearing() {
        let rows = InteractivePicker.terminalRowCount(
            for: [
                "Select conversation",
                "preview",
                "first preview line\nsecond preview line",
                String(repeating: "x", count: 25)
            ],
            width: 10
        )

        XCTAssertEqual(rows, 10)
    }

    func testInteractivePickerPrefetchesSelectedVisibleAndDirectionalLookaheadFirst() {
        let items = (0..<20).map { index in
            PickerItem(id: "conv-\(index)", title: "Conversation \(index)", value: index)
        }

        let down = InteractivePicker.previewPrefetchItems(
            items: items,
            selectedIndex: 8,
            previousSelectedIndex: 7,
            visibleLimit: 8,
            directionalLookahead: 3,
            oppositeLookahead: 1
        ).map(\.id)

        XCTAssertEqual(down.prefix(5), ["conv-8", "conv-9", "conv-10", "conv-11", "conv-1"])
        XCTAssertTrue(down.firstIndex(of: "conv-9")! < down.firstIndex(of: "conv-7")!)

        let up = InteractivePicker.previewPrefetchItems(
            items: items,
            selectedIndex: 8,
            previousSelectedIndex: 9,
            visibleLimit: 8,
            directionalLookahead: 3,
            oppositeLookahead: 1
        ).map(\.id)

        XCTAssertTrue(up.firstIndex(of: "conv-7")! < up.firstIndex(of: "conv-9")!)
    }

    func testConversationDecodesListPreviewFields() throws {
        let data = Data("""
        {
          "conversationId": "conv-1",
          "title": "Thread",
          "modifyTime": "2026-05-13T00:00:00Z",
          "lastMessage": "Last user or assistant message"
        }
        """.utf8)

        let conversation = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(conversation.preview, "Last user or assistant message")
    }

    func testInteractivePickerScrollWindowFollowsSelectionPastInitialItems() {
        XCTAssertEqual(InteractivePicker.visibleWindowStart(itemCount: 50, selectedIndex: 0, visibleLimit: 8), 0)
        XCTAssertEqual(InteractivePicker.visibleWindowStart(itemCount: 50, selectedIndex: 7, visibleLimit: 8), 0)
        XCTAssertEqual(InteractivePicker.visibleWindowStart(itemCount: 50, selectedIndex: 8, visibleLimit: 8), 1)
        XCTAssertEqual(InteractivePicker.visibleWindowStart(itemCount: 50, selectedIndex: 49, visibleLimit: 8), 42)
    }

    func testInteractivePickerCancelDoesNotFallBackToNumberedSelection() {
        var fallbackWasCalled = false
        let selection: String? = InteractivePicker.resolveSelection(arrowSelection: .cancelled) {
            fallbackWasCalled = true
            return "fallback"
        }

        XCTAssertNil(selection)
        XCTAssertFalse(fallbackWasCalled)
    }

    func testFuzzyMatcherScoresSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "exp", text: "Expert expert"))
        XCTAssertNotNil(FuzzyMatcher.score(query: "wrk", text: "workspace Research Notes"))
        XCTAssertNil(FuzzyMatcher.score(query: "zzz", text: "workspace Research Notes"))
    }

    func testStreamParserEmitsStructuredToolActivity() {
        let parser = GrokStreamMarkupParser()
        let block = """
        <xai:tool_usage_card><xai:tool_name>web_search</xai:tool_name><xai:tool_args><![CDATA[{"query":"swift terminal UI"}]]></xai:tool_args></xai:tool_usage_card>
        """
        let events = parser.consume(block)

        XCTAssertTrue(events.contains {
            if case .activity(let activity) = $0 {
                return activity.kind == .search && activity.detail == "swift terminal UI"
            }
            return false
        })
    }

    func testStreamParserSuppressesGenericThinkingPlaceholder() {
        let parser = GrokStreamMarkupParser()

        let events = parser.consume("Thinking about your request\nExample calculation")

        XCTAssertFalse(events.contains {
            if case .text(let text) = $0 {
                return text.contains("Thinking about your request")
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .text(let text) = $0 {
                return text.contains("Example calculation")
            }
            return false
        })
    }

    func testStreamParserPreservesTrueThinkingText() {
        let parser = GrokStreamMarkupParser()

        let events = parser.consume("Example calculation")

        XCTAssertTrue(events.contains {
            if case .text(let text) = $0 {
                return text == "Example calculation"
            }
            return false
        })
    }

    func testStreamParserBuffersSplitInternalTagsAndEscapedRenderDirectives() {
        let parser = GrokStreamMarkupParser()

        let firstEvents = parser.consume("Keep <gro")
        let secondEvents = parser.consume(#"k:render type=\"render_inline_citation\"><argument name=\"citation_id\">7</argument></grok:render> done"#)
        let text = (firstEvents + secondEvents + parser.finish()).compactMap { event -> String? in
            guard case .text(let text) = event else { return nil }
            return text
        }.joined()

        XCTAssertEqual(text, "Keep  done")
        XCTAssertFalse(text.contains("<grok:render"))
        XCTAssertFalse(text.contains("render_inline_citation"))
        XCTAssertFalse(text.contains("citation_id"))
    }

    func testStreamParserSuppressesSplitResidualCitationFragments() {
        let parser = GrokStreamMarkupParser()

        let firstEvents = parser.consume(#"Lead _id="ccee26" card_type="citation_card" type="render_inline_citation"><arg"#)
        let secondEvents = parser.consume(#"ument name="citation_id">5</argument></grok:render> tail"#)
        let text = (firstEvents + secondEvents + parser.finish()).compactMap { event -> String? in
            guard case .text(let text) = event else { return nil }
            return text
        }.joined()

        XCTAssertEqual(text, "Lead  tail")
        XCTAssertFalse(text.contains("ccee26"))
        XCTAssertFalse(text.contains("citation_card"))
        XCTAssertFalse(text.contains("render_inline_citation"))
        XCTAssertFalse(text.contains("<argument"))
    }

    func testMarkdownStreamingBuffersPartialLineUntilComplete() {
        let formatter = OutputFormatter(useMarkdown: true)

        let firstOutput = captureStdout {
            formatter.printChunk("**bo", isFirst: true)
        }
        XCTAssertFalse(strippingANSI(firstOutput).contains("bo"))

        let secondOutput = captureStdout {
            formatter.printChunk("ld**\n", isFirst: false)
            formatter.printSources(webSearchResults: nil, xposts: nil)
        }
        XCTAssertTrue(strippingANSI(secondOutput).contains("bold"))
    }

    func testPrintSourcesFlushesFinalMarkdownFragment() {
        let formatter = OutputFormatter(useMarkdown: true)

        let output = captureStdout {
            formatter.printChunk("final fragment", isFirst: true)
            formatter.printSources(webSearchResults: nil, xposts: nil)
        }

        XCTAssertTrue(strippingANSI(output).contains("final fragment"))
    }

    func testMarkdownFormatterHandlesCodeBlockPipesBeforeTables() {
        let formatter = OutputFormatter()
        let markdown = """
        ```markdown
        | Not | table |
        | --- | --- |
        ```

        | Name | Count |
        | --- | ---: |
        | Apples | 12 |
        """

        let output = strippingANSI(captureStdout {
            formatter.printResponse(markdown)
        })

        XCTAssertContains(output, "| Not | table |")
        XCTAssertContains(output, "| --- | --- |")
        XCTAssertContains(output, "| Name   | Count |")
        XCTAssertContains(output, "| Apples |    12 |")
    }

    func testHumanFormatterUsesCleanAnswerAndSourceLabels() {
        let formatter = OutputFormatter(useMarkdown: false)

        let output = strippingANSI(captureStdout {
            formatter.printResponse(
                "answer",
                webSearchResults: [
                    WebSearchResult(url: "https://example.com/1", title: "One", preview: "One"),
                    WebSearchResult(url: "https://example.com/2", title: "Two", preview: "Two")
                ],
                xposts: [
                    XPost(username: "grok", name: "Grok", text: "post", postId: "post-1")
                ]
            )
        })

        XCTAssertContains(output, "\nGrok\n")
        XCTAssertContains(output, "\nSources\n")
        XCTAssertContains(output, "2 web results")
        XCTAssertContains(output, "1 X result")
        XCTAssertFalse(output.contains("Grok:"))
        XCTAssertFalse(output.contains("Sources:"))
        XCTAssertFalse(output.contains("Web search results:"))
        XCTAssertFalse(output.contains("X posts:"))
    }

    func testHumanFormatterUsesCleanStreamingAnswerLabel() {
        let formatter = OutputFormatter(useMarkdown: false)

        let output = strippingANSI(captureStdout {
            formatter.printChunk("stream answer", isFirst: true)
            formatter.printSources(webSearchResults: nil, xposts: nil)
        })

        XCTAssertContains(output, "\nGrok\nstream answer")
        XCTAssertFalse(output.contains("Grok:"))
    }

    func testStreamingFormatterReturnsAfterFinalBeforeSourceCloses() async throws {
        var streamContinuation: AsyncThrowingStream<ConversationResponse, Error>.Continuation?
        let stream = AsyncThrowingStream<ConversationResponse, Error> { continuation in
            streamContinuation = continuation
        }
        let continuation = try XCTUnwrap(streamContinuation)
        let formatter = OutputFormatter(useMarkdown: false)

        let renderTask = Task {
            try await formatter.printStreamingResponse(stream)
        }

        continuation.yield(ConversationResponse(
            message: "visible answer",
            conversationId: "conv-e2e",
            responseId: "resp-e2e"
        ))
        continuation.yield(ConversationResponse(
            message: "visible answer",
            conversationId: "conv-e2e",
            responseId: "resp-e2e",
            isFinal: true
        ))

        let completedBeforeEOF = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await renderTask.value
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        continuation.finish()
        try await renderTask.value

        XCTAssertTrue(completedBeforeEOF, "Streaming formatter should return as soon as the final response arrives.")
    }

    func testQuietStreamingReturnsAfterFinalBeforeSourceCloses() async throws {
        var streamContinuation: AsyncThrowingStream<ConversationResponse, Error>.Continuation?
        let stream = AsyncThrowingStream<ConversationResponse, Error> { continuation in
            streamContinuation = continuation
        }
        let continuation = try XCTUnwrap(streamContinuation)

        let renderTask = Task {
            try await GrokCLI.printQuietStreamingResponse(stream)
        }

        continuation.yield(ConversationResponse(
            message: "quiet answer",
            conversationId: "conv-e2e",
            responseId: "resp-e2e"
        ))
        continuation.yield(ConversationResponse(
            message: "quiet answer",
            conversationId: "conv-e2e",
            responseId: "resp-e2e",
            isFinal: true
        ))

        let completedBeforeEOF = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await renderTask.value
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        continuation.finish()
        try await renderTask.value

        XCTAssertTrue(completedBeforeEOF, "Quiet streaming should return as soon as the final response arrives.")
    }

    func testJSONStreamingReturnsAfterFinalBeforeSourceCloses() async throws {
        var streamContinuation: AsyncThrowingStream<ConversationResponse, Error>.Continuation?
        let stream = AsyncThrowingStream<ConversationResponse, Error> { continuation in
            streamContinuation = continuation
        }
        let continuation = try XCTUnwrap(streamContinuation)
        let mode = GrokMode(id: "grok-4-fast", displayName: "Grok 4 Fast")
        let request = GrokCLI.messageRequestJSON(
            reasoning: true,
            deepSearch: false,
            noSearch: false,
            privateMode: false,
            stream: true,
            workspaceIds: [],
            fileAttachmentIds: []
        )

        let renderTask = Task {
            try await GrokCLI.printMessageJSONStream(
                stream,
                message: "hello",
                mode: mode,
                request: request
            )
        }

        continuation.yield(ConversationResponse(
            message: "json answer",
            conversationId: "conv-e2e",
            responseId: "resp-e2e"
        ))
        continuation.yield(ConversationResponse(
            message: "json answer",
            conversationId: "conv-e2e",
            responseId: "resp-e2e",
            isFinal: true
        ))

        let completedBeforeEOF = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    return try await renderTask.value
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        continuation.finish()
        _ = try await renderTask.value

        XCTAssertTrue(completedBeforeEOF, "JSON streaming should return as soon as the final response arrives.")
    }

    func testMarkdownFormatterSupportsTerminalMarkdownSubset() {
        let formatter = OutputFormatter()
        let markdown = """
        # Heading
        ## Section
        ### Detail
        - item with **bold**
          - nested *italic*
        1. number with `code`
        - [x] done
        - [ ] todo
        > quote with [link](https://example.com)
        ![alt text](https://example.com/image.png)
        ~~old text~~
        ---
        | Name | Count |
        | --- | ---: |
        | Apples | 12 |
        """

        let output = strippingANSI(captureStdout {
            formatter.printResponse(markdown)
        })

        XCTAssertContains(output, "Heading")
        XCTAssertContains(output, "Section")
        XCTAssertContains(output, "Detail")
        XCTAssertContains(output, "• item with bold")
        XCTAssertContains(output, "  • nested italic")
        XCTAssertContains(output, "1. number with code")
        XCTAssertContains(output, "☑ done")
        XCTAssertContains(output, "☐ todo")
        XCTAssertContains(output, "> quote with link (https://example.com)")
        XCTAssertContains(output, "Image: alt text (https://example.com/image.png)")
        XCTAssertContains(output, "old text")
        XCTAssertContains(output, "| Name   | Count |")
        XCTAssertContains(output, "| Apples |    12 |")
        XCTAssertFalse(output.contains("# Heading"))
        XCTAssertFalse(output.contains("**bold**"))
    }

    func testRawFormatterPreservesMarkdownSource() {
        let formatter = OutputFormatter(format: .raw)

        let output = strippingANSI(captureStdout {
            formatter.printResponse("# Heading\n**bold** and `code`\n- [example](https://example.com)")
        })

        XCTAssertContains(output, "# Heading")
        XCTAssertContains(output, "**bold**")
        XCTAssertContains(output, "`code`")
        XCTAssertContains(output, "- [example](https://example.com)")
    }

    func testMessageRawQuietStripsGrokRenderMarkupAndPreservesMarkdownSource() throws {
        let answer = """
        # Source Heading
        Keep **bold** and [source](https://example.com) syntax.
        Hide <grok:render type="render_inline_citation"><argument name="citation_id">5</argument></grok:render> citations.
        Hide escaped <grok:render type=\\\"render_inline_citation\\\"><argument name=\\\"citation_id\\\">5</argument></grok:render> fragments.
        Hide residual _id="ccee26" card_type="citation_card" type="render_inline_citation"><argument name="citation_id">5</argument></grok:render> fragments.
        Hide escaped residual _id=\\\"ccee26\\\" card_type=\\\"citation_card\\\" type=\\\"render_inline_citation\\\"><argument name=\\\"citation_id\\\">5</argument></grok:render> fragments.
        """
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--raw", "--quiet", "hello"])

        XCTAssertEqual(run.status, 0)
        assertNoQuietUI(in: run.stdout)
        XCTAssertContains(run.stdout, "# Source Heading")
        XCTAssertContains(run.stdout, "**bold**")
        XCTAssertContains(run.stdout, "[source](https://example.com)")
        XCTAssertFalse(run.stdout.contains("<grok:render"))
        XCTAssertFalse(run.stdout.contains("render_inline_citation"))
        XCTAssertFalse(run.stdout.contains("citation_card"))
        XCTAssertFalse(run.stdout.contains("ccee26"))
        XCTAssertFalse(run.stdout.contains("<argument"))
        XCTAssertFalse(run.stdout.contains(#"\"citation_id\""#))
    }

    func testMessageStreamingRawQuietStripsSplitResidualCitationMarkup() throws {
        let server = try MockGrokServer(
            streamLines: [
                ##"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"# Source Heading\nKeep **bold** text.\nResidual _id=\"ccee26\" card_type=\"citation_card\" type=\"render_inline_citation\">"}}}"##,
                ##"{"result":{"response":{"responseId":"resp-e2e","token":"<argument name=\"citation_id\">5</argument></grok:render> after.\n"}}}"##,
                ##"{"result":{"response":{"modelResponse":{"message":"# Source Heading\nKeep **bold** text.\nResidual _id=\"ccee26\" card_type=\"citation_card\" type=\"render_inline_citation\"><argument name=\"citation_id\">5</argument></grok:render> after.\n","responseId":"resp-e2e"}}}}"##
            ]
        )
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--raw", "--quiet", "hello"])

        XCTAssertEqual(run.status, 0)
        assertNoQuietUI(in: run.stdout)
        XCTAssertContains(run.stdout, "# Source Heading")
        XCTAssertContains(run.stdout, "**bold**")
        XCTAssertContains(run.stdout, "Residual")
        XCTAssertContains(run.stdout, "after.")
        XCTAssertFalse(run.stdout.contains("render_inline_citation"))
        XCTAssertFalse(run.stdout.contains("citation_card"))
        XCTAssertFalse(run.stdout.contains("ccee26"))
        XCTAssertFalse(run.stdout.contains("<argument"))
        XCTAssertFalse(run.stdout.contains("</grok:render>"))
    }

    func testMessageQuietDefaultsToMarkdownRenderingWhileRawQuietPreservesMarkdownSource() throws {
        let answer = """
        # Quiet Heading
        Keep **bold** syntax.
        Hide <grok:render type="render_inline_citation"><argument name="citation_id">5</argument></grok:render> citations.
        """
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let markdown = try environment.run(["message", "--quiet", "hello"])
        XCTAssertEqual(markdown.status, 0)
        XCTAssertContains(markdown.cleanOutput, "Quiet Heading")
        XCTAssertContains(markdown.cleanOutput, "Keep bold syntax.")
        XCTAssertFalse(markdown.cleanOutput.contains("# Quiet Heading"))
        XCTAssertFalse(markdown.cleanOutput.contains("**bold**"))
        XCTAssertFalse(markdown.cleanOutput.contains("Grok"))
        XCTAssertFalse(markdown.cleanOutput.contains("Calling Grok API"))
        XCTAssertFalse(markdown.cleanOutput.contains("Sending:"))
        XCTAssertFalse(markdown.cleanOutput.contains("<grok:render"))
        XCTAssertFalse(markdown.cleanOutput.contains("render_inline_citation"))

        let raw = try environment.run(["message", "--raw", "--quiet", "hello"])
        XCTAssertEqual(raw.status, 0)
        assertNoQuietUI(in: raw.stdout)
        XCTAssertContains(raw.stdout, "# Quiet Heading")
        XCTAssertContains(raw.stdout, "**bold**")
        XCTAssertFalse(raw.stdout.contains("<grok:render"))
        XCTAssertFalse(raw.stdout.contains("render_inline_citation"))
    }

    func testMessageMarkdownFinalOutputStripsGrokRenderMarkup() throws {
        let answer = """
        # Cited Heading
        Final answer <grok:render type="render_inline_citation"><argument name="citation_id">5</argument></grok:render> still reads cleanly.
        Escaped fragment <grok:render type=\\\"render_inline_citation\\\"><argument name=\\\"citation_id\\\">5</argument></grok:render> is hidden too.
        """
        let server = try MockGrokServer(finalMessage: answer)
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "hello"])

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Cited Heading")
        XCTAssertContains(run.cleanOutput, "Final answer")
        XCTAssertContains(run.cleanOutput, "still reads cleanly.")
        XCTAssertContains(run.cleanOutput, "Escaped fragment")
        XCTAssertContains(run.cleanOutput, "is hidden too.")
        XCTAssertFalse(run.cleanOutput.contains("# Cited Heading"))
        XCTAssertFalse(run.cleanOutput.contains("<grok:render"))
        XCTAssertFalse(run.cleanOutput.contains("render_inline_citation"))
        XCTAssertFalse(run.cleanOutput.contains("<argument"))
        XCTAssertFalse(run.cleanOutput.contains(#"\"citation_id\""#))
    }

    func testMessageCommandDefaultsToMarkdownAndSupportsRawOutput() throws {
        let server = try MockGrokServer(finalMessage: "# CLI Heading\n**bold**")
        let environment = try TestEnvironment(server: server)

        let markdown = try environment.run(["message", "hello"])
        XCTAssertEqual(markdown.status, 0)
        XCTAssertContains(markdown.cleanOutput, "CLI Heading")
        XCTAssertContains(markdown.cleanOutput, "bold")
        XCTAssertFalse(markdown.cleanOutput.contains("# CLI Heading"))
        XCTAssertFalse(markdown.cleanOutput.contains("**bold**"))

        let raw = try environment.run(["message", "--raw", "hello"])
        XCTAssertEqual(raw.status, 0)
        XCTAssertContains(raw.cleanOutput, "# CLI Heading")
        XCTAssertContains(raw.cleanOutput, "**bold**")

        let formatRaw = try environment.run(["message", "--format", "raw", "hello"])
        XCTAssertEqual(formatRaw.status, 0)
        XCTAssertContains(formatRaw.cleanOutput, "# CLI Heading")
        XCTAssertContains(formatRaw.cleanOutput, "**bold**")
    }

    func testMessageCommandShowsFriendlyRateLimitError() throws {
        let server = try MockGrokServer(rateLimitedNewConversationCount: 2)
        let environment = try TestEnvironment(server: server)

        let normal = try environment.run(["message", "hello"])
        XCTAssertEqual(normal.status, 1)
        XCTAssertContains(normal.cleanOutput, "Message limit reached.")
        XCTAssertContains(normal.cleanOutput, "Wait a few minutes")
        XCTAssertFalse(normal.cleanOutput.contains(#"{"error""#))

        let debug = try environment.run(["message", "--debug", "hello"])
        XCTAssertEqual(debug.status, 1)
        XCTAssertContains(debug.cleanOutput, "Message limit reached.")
        XCTAssertContains(debug.cleanOutput, "Debug: Raw error: HTTP Error: 429")
    }

    func testInteractiveFormatCommandsToggleMarkdownAndRaw() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/format raw\n/format md\n/raw on\n/markdown on\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Output format: Raw")
        XCTAssertContains(run.cleanOutput, "Output format: Markdown")
        XCTAssertContains(run.cleanOutput, "Grok > Fast | Raw")
        XCTAssertContains(run.cleanOutput, "Grok > Fast | MD")
        XCTAssertFalse(run.cleanOutput.contains("Chat mode |"))
        XCTAssertFalse(run.cleanOutput.contains("Saved |"))
        XCTAssertFalse(run.cleanOutput.contains("Stream |"))
        XCTAssertFalse(run.cleanOutput.contains("Raw Output"))
        XCTAssertFalse(run.cleanOutput.contains("MD Formatted"))
    }

    func testInteractiveLowRateLimitAppearsAfterFormatStatusSegment() throws {
        let server = try MockGrokServer(rateLimitResponse: [
            "remainingResponses": 9,
            "resetAfterSeconds": 300
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/format raw\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Grok > Fast | MD")
        XCTAssertContains(run.cleanOutput, "Grok > Fast | Raw")
        XCTAssertContains(run.cleanOutput, "Limit > 9 left | reset 5m")

        let request = try XCTUnwrap(server.requests(matchingPath: "/rest/rate-limits", method: "POST").last)
        XCTAssertEqual(request.jsonString("modelName"), "fast")
    }

    func testInteractiveLimitsCommandPrintsCurrentLimitsWithoutWarningThreshold() throws {
        let server = try MockGrokServer(rateLimitResponse: [
            "remainingResponses": 42,
            "resetAfterSeconds": 900
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/limits\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Rate limits for Fast (fast)")
        XCTAssertContains(run.cleanOutput, "Remaining responses: 42 responses")
        XCTAssertContains(run.cleanOutput, "Resets in 15m")
        XCTAssertFalse(run.cleanOutput.contains("Available API data:"))
        XCTAssertFalse(run.cleanOutput.contains("Limit > 42 left"))

        let request = try XCTUnwrap(server.requests(matchingPath: "/rest/rate-limits", method: "POST").last)
        XCTAssertEqual(request.jsonString("modelName"), "fast")
    }

    func testInteractiveLimitsInfersResetFromRecentMessagesWhenOnlyWindowIsProvided() throws {
        let recentTimestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1_800))
        let server = try MockGrokServer(
            rateLimitResponse: [
                "remainingResponses": 4,
                "windowSeconds": 3_600
            ],
            conversations: [[
                "conversationId": "conv-e2e",
                "title": "Recent Conversation",
                "starred": false,
                "createTime": recentTimestamp,
                "modifyTime": recentTimestamp,
                "systemPromptName": "",
                "temporary": false,
                "mediaTypes": []
            ]],
            loadedResponses: [
                ["responseId": "resp-user", "message": "Recent user response", "sender": "human", "createTime": recentTimestamp],
                ["responseId": "resp-e2e", "message": "Recent assistant response", "sender": "assistant", "createTime": recentTimestamp, "parentResponseId": "resp-user"]
            ]
        )
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "/limits\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Remaining responses: 4 responses")
        XCTAssertContains(run.cleanOutput, "Resets in about 30m")
        XCTAssertContains(run.cleanOutput, "Window: rolling 1h")
        XCTAssertFalse(run.cleanOutput.contains("Reset: unavailable"))
        XCTAssertFalse(run.cleanOutput.contains("Available API data:"))
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations", method: "GET").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/load-responses", method: "POST").count, 1)
    }

    func testInteractiveMultiTurnLowRateLimitWarningShowsResetDuration() throws {
        let server = try MockGrokServer(rateLimitResponse: [
            "remainingResponses": 8,
            "resetAfterSeconds": 300
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run([], input: "first\nsecond\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Warning: 8 responses remaining; resets in 5m.")
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").count, 1)
    }

    private func captureStdout(_ body: () -> Void) -> String {
        fflush(stdout)

        let originalStdout = dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(originalStdout, 0)

        var fileDescriptors = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(pipe(&fileDescriptors), 0)

        dup2(fileDescriptors[1], STDOUT_FILENO)
        close(fileDescriptors[1])

        body()
        fflush(stdout)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fileDescriptors[0], &buffer, buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        close(fileDescriptors[0])

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func strippingANSI(_ text: String) -> String {
        let escape = "\u{001B}"
        return text.replacingOccurrences(
            of: "\(escape)\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }

    private func jsonObject(
        from run: RunResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let stdout = strippingANSI(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(stdout.isEmpty, "Expected JSON on stdout", file: file, line: line)
        XCTAssertTrue(stdout.hasPrefix("{"), "Expected a single JSON object on stdout", file: file, line: line)
        XCTAssertTrue(stdout.hasSuffix("}"), "Expected a single JSON object on stdout", file: file, line: line)

        let value = try JSONSerialization.jsonObject(with: Data(stdout.utf8))
        return try XCTUnwrap(value as? [String: Any], "Expected stdout JSON to be an object", file: file, line: line)
    }

    private func jsonLines(
        from run: RunResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [[String: Any]] {
        let stdout = strippingANSI(run.stdout)
        let lines = stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertFalse(lines.isEmpty, "Expected NDJSON on stdout", file: file, line: line)

        return try lines.map { lineText in
            let value = try JSONSerialization.jsonObject(with: Data(lineText.utf8))
            return try XCTUnwrap(value as? [String: Any], "Expected each stdout line to be a JSON object", file: file, line: line)
        }
    }

    @discardableResult
    private func assertResultEnvelope(
        _ envelope: [String: Any],
        command: String,
        subcommand: String? = nil,
        category: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        XCTAssertEqual(envelope["schema"] as? String, "grok.cli.result.v1", file: file, line: line)
        XCTAssertEqual(envelope["ok"] as? Bool, true, file: file, line: line)
        XCTAssertEqual(envelope["command"] as? String, command, file: file, line: line)
        XCTAssertEqual(envelope["subcommand"] as? String, subcommand, file: file, line: line)
        XCTAssertEqual(envelope["category"] as? String, category, file: file, line: line)

        let meta = try XCTUnwrap(envelope["meta"] as? [String: Any], file: file, line: line)
        XCTAssertEqual(meta["format"] as? String, "json", file: file, line: line)
        XCTAssertEqual(meta["version"] as? String, "1", file: file, line: line)

        return try XCTUnwrap(envelope["data"] as? [String: Any], file: file, line: line)
    }

    private func assertNoHumanJSONBanners(
        in stdout: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(stdout.contains("\u{001B}"), "JSON stdout should not include ANSI escapes", file: file, line: line)
        for banner in ["Calling Grok API", "Connected to ", "Sending:", "Thinking", "Grok:", "Available conversations:", "Select a conversation"] {
            XCTAssertFalse(stdout.contains(banner), "JSON stdout should not include human banner '\(banner)'", file: file, line: line)
        }
    }

    private func assertAnswerOnlyStdout(
        _ stdout: String,
        equals answer: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertNoQuietUI(in: stdout, file: file, line: line)
        let expected = answer.hasSuffix("\n") ? answer : "\(answer)\n"
        XCTAssertEqual(stdout, expected, file: file, line: line)
    }

    private func assertUsageError(
        _ run: RunResult,
        mentions fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(run.status, 2, file: file, line: line)
        XCTAssertContains(run.cleanOutput, "Error:", file: file, line: line)
        XCTAssertFalse(run.cleanOutput.contains("Calling Grok API"), file: file, line: line)

        let lowercaseOutput = run.cleanOutput.lowercased()
        for fragment in fragments {
            XCTAssertContains(lowercaseOutput, fragment.lowercased(), file: file, line: line)
        }
    }

    private func assertNoQuietUI(
        in stdout: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for banner in [
            "Calling Grok API",
            "Sending",
            "Thinking",
            "Grok:",
            "Sources:",
            "Authentication successful",
            "Connected to ",
            "Chat mode",
            "Enter your message:",
            "Available conversations:",
            "Select a conversation",
            "Goodbye!",
            "> "
        ] {
            XCTAssertFalse(stdout.contains(banner), "Quiet stdout should not include UI text '\(banner)'", file: file, line: line)
        }
        assertNoControlUISequences(in: stdout, file: file, line: line)
    }

    private func assertNoControlUISequences(
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(text.contains("\u{001B}"), "Quiet stdout should not include ANSI escapes", file: file, line: line)
        XCTAssertFalse(text.contains("\r"), "Quiet stdout should not include carriage-return UI control sequences", file: file, line: line)
        for scalar in text.unicodeScalars {
            guard scalar.value < 0x20, scalar != "\n", scalar != "\t" else {
                continue
            }
            XCTFail("Quiet stdout should not include control character U+\(String(format: "%04X", scalar.value))", file: file, line: line)
            return
        }
    }

    private func writeSavedXAIOAuthCredential(
        in environment: TestEnvironment,
        accessToken: String,
        apiBaseURL: String
    ) throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let payload = """
        {
          "accessToken": "\(accessToken)",
          "tokenType": "Bearer",
          "expiresAt": "\(formatter.string(from: now.addingTimeInterval(3_600)))",
          "obtainedAt": "\(formatter.string(from: now))",
          "issuer": "https://auth.x.ai",
          "tokenEndpoint": "\(apiBaseURL)/oauth/token",
          "apiBaseURL": "\(apiBaseURL)"
        }
        """
        let oauthCredentialsURL = environment.credentialsURL
            .deletingLastPathComponent()
            .appendingPathComponent("xai-oauth.json")
        try payload.write(to: oauthCredentialsURL, atomically: true, encoding: .utf8)
    }

    private func writeSavedAuthMode(_ mode: String, in environment: TestEnvironment) throws {
        let authModeURL = environment.credentialsURL
            .deletingLastPathComponent()
            .appendingPathComponent("auth-mode.json")
        try #"{"mode":"\#(mode)"}"#.write(to: authModeURL, atomically: true, encoding: .utf8)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else {
            return 0
        }

        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}

private final class TestEnvironment {
    let server: MockGrokServer
    let homeURL: URL
    let scratchURL: URL
    let credentialsURL: URL
    private let repositoryRoot: URL
    private let executableURL: URL

    init(server: MockGrokServer) throws {
        self.server = server
        self.repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        self.scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-grok-e2e-\(UUID().uuidString)")
        self.homeURL = scratchURL.appendingPathComponent("home")
        let configURL = homeURL
            .appendingPathComponent(".config")
            .appendingPathComponent("grok-cli")
        self.credentialsURL = configURL.appendingPathComponent("credentials.json")
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        try #"{"x-anonuserid":"test-user","sso":"test-cookie"}"#.write(to: credentialsURL, atomically: true, encoding: .utf8)

        self.executableURL = try Self.findExecutable(repositoryRoot: repositoryRoot)
    }

    deinit {
        try? FileManager.default.removeItem(at: scratchURL)
    }

    func run(
        _ arguments: [String],
        input: String = "",
        timeout: TimeInterval = 10,
        extraEnvironment: [String: String] = [:]
    ) throws -> RunResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = homeURL.path
        environment["CFFIXED_USER_HOME"] = homeURL.path
        environment["GROK_CONFIG_DIR"] = credentialsURL.deletingLastPathComponent().path
        environment["GROK_BASE_URL"] = server.baseURL
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()
        if !input.isEmpty {
            stdin.fileHandleForWriting.write(Data(input.utf8))
        }
        stdin.fileHandleForWriting.closeFile()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            throw NSError(domain: "GrokCLIE2ETests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Timed out running grok \(arguments.joined(separator: " "))"
            ])
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(status: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
    }

    private static func findExecutable(repositoryRoot: URL) throws -> URL {
        let bundleDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates = [
            executableDirectory?.appendingPathComponent("grok"),
            bundleDirectory.appendingPathComponent("grok"),
            repositoryRoot.appendingPathComponent(".build/debug/grok"),
            repositoryRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/grok")
        ].compactMap { $0 }

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }

        throw NSError(domain: "GrokCLIE2ETests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Could not find built grok executable in \(candidates.map(\.path))"
        ])
    }
}

private struct RunResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var output: String {
        stdout + stderr
    }

    var cleanOutput: String {
        strippingANSI(output)
    }

    private func strippingANSI(_ text: String) -> String {
        let escape = "\u{001B}"
        return text.replacingOccurrences(
            of: "\(escape)\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }
}

private struct RecordedRequest {
    let method: String
    let target: String
    let path: String
    let headers: [String: String]
    let body: Data
    let json: [String: Any]

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func jsonString(_ key: String) -> String? {
        json[key] as? String
    }

    func jsonBool(_ key: String) -> Bool? {
        json[key] as? Bool
    }

    func queryInt(_ key: String) -> Int? {
        guard let components = URLComponents(string: "http://localhost\(target)") else {
            return nil
        }
        return components.queryItems?
            .first(where: { $0.name == key })?
            .value
            .flatMap(Int.init)
    }
}

private final class MockGrokServer {
    private(set) var baseURL = ""
    private let listener: NWListener
    private let queue = DispatchQueue(label: "MockGrokServer")
    private let lock = NSLock()
    private var recordedRequests: [RecordedRequest] = []
    private var unauthorizedNewConversationCount: Int
    private var accessDeniedNewConversationCount: Int
    private var antiBotNewConversationCount: Int
    private var rateLimitedNewConversationCount: Int
    private let rateLimitResponse: [String: Any]
    private let conversations: [[String: Any]]
    private let streamTokens: [String]
    private let streamLines: [String]?
    private let finalMessage: String
    private let loadedAssistantMessage: String
    private let loadedAssistantMetadata: [String: Any]?
    private let loadedResponses: [[String: Any]]?
    private let transcriptionText: String
    private let shareLinkURL: String
    private let shareLinkExists: Bool
    private let subscriptionResponse: [String: Any]
    private let heavyRequiresUpgrade: Bool
    private let builtInSkills: [[String: Any]]
    private let userSkills: [[String: Any]]
    private let xaiAPIModels: [String]
    private let xaiResponseStreamLines: [String]?
    private var xaiVideoPollResponses: [[String: Any]]

    static let doneXAIVideoPollResponse: [String: Any] = [
        "status": "done",
        "video": [
            "url": "https://vidgen.x.ai/mock-video.mp4",
            "duration": 6,
            "respect_moderation": true
        ],
        "model": "grok-imagine-video",
        "progress": 100
    ]

    init(
        unauthorizedNewConversationCount: Int = 0,
        accessDeniedNewConversationCount: Int = 0,
        antiBotNewConversationCount: Int = 0,
        rateLimitedNewConversationCount: Int = 0,
        rateLimitResponse: [String: Any] = ["remainingResponses": 25, "resetAfterSeconds": 3_600],
        conversations: [[String: Any]] = [[
            "conversationId": "conv-e2e",
            "title": "Mock Conversation",
            "starred": false,
            "createTime": "2026-05-13T00:00:00Z",
            "modifyTime": "2026-05-13T00:00:00Z",
            "systemPromptName": "",
            "temporary": false,
            "mediaTypes": []
        ]],
        streamTokens: [String] = ["Mock streamed ", "answer"],
        streamLines: [String]? = nil,
        finalMessage: String = "Mock final response",
        loadedAssistantMessage: String = "Loaded assistant response",
        loadedAssistantMetadata: [String: Any]? = nil,
        loadedResponses: [[String: Any]]? = nil,
        transcriptionText: String = "mock audio transcript",
        shareLinkURL: String = "https://grok.com/share/mock-share-link",
        shareLinkExists: Bool = true,
        subscriptionResponse: [String: Any] = ["subscriptions": []],
        heavyRequiresUpgrade: Bool = true,
        builtInSkills: [[String: Any]] = [[
            "skillId": "skill-1",
            "name": "Mock Skill",
            "description": "Mock skill description",
            "status": "enabled"
        ]],
        userSkills: [[String: Any]] = [[
            "skillId": "user-skill-1",
            "name": "User Skill",
            "description": "Mock skill description",
            "status": "enabled"
        ]],
        xaiResponseStreamLines: [String]? = nil,
        xaiVideoPollResponses: [[String: Any]] = [MockGrokServer.doneXAIVideoPollResponse],
        xaiAPIModels: [String] = []
    ) throws {
        self.unauthorizedNewConversationCount = unauthorizedNewConversationCount
        self.accessDeniedNewConversationCount = accessDeniedNewConversationCount
        self.antiBotNewConversationCount = antiBotNewConversationCount
        self.rateLimitedNewConversationCount = rateLimitedNewConversationCount
        self.rateLimitResponse = rateLimitResponse
        self.conversations = conversations
        self.streamTokens = streamTokens
        self.streamLines = streamLines
        self.finalMessage = finalMessage
        self.loadedAssistantMessage = loadedAssistantMessage
        self.loadedAssistantMetadata = loadedAssistantMetadata
        self.loadedResponses = loadedResponses
        self.transcriptionText = transcriptionText
        self.shareLinkURL = shareLinkURL
        self.shareLinkExists = shareLinkExists
        self.subscriptionResponse = subscriptionResponse
        self.heavyRequiresUpgrade = heavyRequiresUpgrade
        self.builtInSkills = builtInSkills
        self.userSkills = userSkills
        self.xaiAPIModels = xaiAPIModels
        self.xaiResponseStreamLines = xaiResponseStreamLines
        self.xaiVideoPollResponses = xaiVideoPollResponses
        self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)

        let ready = DispatchSemaphore(value: 0)
        var startupError: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                startupError = error
                ready.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection: connection, buffer: Data())
        }

        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else {
            throw NSError(domain: "MockGrokServer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Timed out starting mock server"
            ])
        }
        if let startupError {
            throw startupError
        }
        guard let port = listener.port else {
            throw NSError(domain: "MockGrokServer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Mock server did not publish a port"
            ])
        }
        self.baseURL = "http://127.0.0.1:\(port.rawValue)"
    }

    deinit {
        listener.cancel()
    }

    func requests(matchingPath path: String? = nil, method: String? = nil) -> [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.filter { request in
            (path == nil || request.path == path) &&
            (method == nil || request.method == method)
        }
    }

    private func receive(connection: NWConnection, buffer: Data) {
        connection.start(queue: queue)
        receiveMore(connection: connection, buffer: buffer)
    }

    private func receiveMore(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = HTTPRequest(data: nextBuffer) {
                self.record(request)
                self.respond(to: request, on: connection)
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }

            self.receiveMore(connection: connection, buffer: nextBuffer)
        }
    }

    private func record(_ request: HTTPRequest) {
        lock.lock()
        recordedRequests.append(RecordedRequest(
            method: request.method,
            target: request.target,
            path: request.path,
            headers: request.headers,
            body: request.body,
            json: request.jsonBody
        ))
        lock.unlock()
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let response = responseBody(for: request)
        let header = """
        HTTP/1.1 \(response.status) OK\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(response.body.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func responseBody(for request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("POST", "/rest/modes"):
            return jsonResponse(["modes": modeJSON()])
        case ("GET", "/v1/models"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse([
                "data": xaiAPIModels.map { ["id": $0, "object": "model"] }
            ])
        case ("POST", "/v1/responses"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            if request.jsonBool("stream") == true {
                return xaiStreamingResponse(responseId: "resp-xai-e2e")
            }
            return jsonResponse([
                "id": "resp-xai-e2e",
                "object": "response",
                "model": request.jsonString("model") ?? "grok-4.3",
                "output_text": finalMessage
            ])
        case ("POST", "/v1/images/generations"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse([
                "data": [[
                    "url": "https://imgen.x.ai/mock-image.jpeg",
                    "mime_type": "image/jpeg",
                    "revised_prompt": request.jsonString("prompt") ?? ""
                ]],
                "usage": [
                    "cost_in_usd_ticks": 200000000
                ]
            ])
        case ("POST", "/v1/videos/generations"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse([
                "request_id": "vid-xai-e2e"
            ])
        case ("GET", "/v1/videos/vid-xai-e2e"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse(nextXAIVideoPollResponse())
        case ("POST", "/v1/stt"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse(["text": transcriptionText])
        case ("GET", "/v1/files"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse([
                "data": [
                    ["id": "file-xai-1", "filename": "oauth.txt", "mime_type": "text/plain"]
                ]
            ])
        case ("POST", "/v1/files"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse([
                "id": "file-xai-1",
                "filename": "oauth.txt",
                "mime_type": "text/plain"
            ])
        case ("DELETE", let path) where path.hasPrefix("/v1/files/"):
            guard request.header("Authorization")?.hasPrefix("Bearer ") == true else {
                return jsonResponse(["error": "missing bearer token"], status: 401)
            }
            return jsonResponse([
                "id": request.pathComponent(after: "files") ?? "file-xai-1",
                "deleted": true
            ])
        case ("POST", "/rest/voice/speech-to-text"):
            return jsonResponse([
                "text": transcriptionText,
                "transcript": transcriptionText
            ])
        case ("POST", "/rest/rate-limits"):
            var response = rateLimitResponse
            response["modelName"] = response["modelName"] ?? request.jsonString("modelName") ?? "fast"
            return jsonResponse(response)
        case ("GET", "/rest/subscriptions"):
            return jsonResponse(subscriptionResponse)
        case ("POST", "/rest/app-chat/conversations/new"):
            if unauthorizedNewConversationCount > 0 {
                unauthorizedNewConversationCount -= 1
                return jsonResponse(["error": "unauthorized"], status: 401)
            }
            if accessDeniedNewConversationCount > 0 {
                accessDeniedNewConversationCount -= 1
                return jsonResponse([
                    "error": [
                        "code": "model_access_denied",
                        "message": "Your account does not have access to Grok Heavy."
                    ]
                ], status: 403)
            }
            if antiBotNewConversationCount > 0 {
                antiBotNewConversationCount -= 1
                return jsonResponse([
                    "error": [
                        "message": "Request rejected by anti-bot rules"
                    ]
                ], status: 403)
            }
            if rateLimitedNewConversationCount > 0 {
                rateLimitedNewConversationCount -= 1
                return jsonResponse([
                    "error": [
                        "code": 8,
                        "message": "Too many requests",
                        "details": []
                    ]
                ], status: 429)
            }
            return streamResponse(conversationId: "conv-e2e", responseId: "resp-e2e")
        case ("POST", let path) where path.hasPrefix("/rest/app-chat/conversations/") && path.hasSuffix("/responses"):
            return streamResponse(conversationId: request.pathComponent(after: "conversations") ?? "conv-e2e", responseId: "resp-continued")
        case ("GET", "/rest/app-chat/conversations"):
            return jsonResponse([
                "conversations": conversations,
                "nextPageToken": "",
                "textSearchMatches": []
            ])
        case ("GET", "/rest/app-chat/share_links"):
            if shareLinkExists {
                return jsonResponse([
                    "shareLinks": [[
                        "shareUrl": shareLinkURL,
                        "conversationId": "conv-e2e"
                    ]]
                ])
            }
            return jsonResponse(["shareLinks": []])
        case ("POST", let path) where path.hasPrefix("/rest/app-chat/conversations/") && path.hasSuffix("/share"):
            return jsonResponse(["shareLinkId": shareLinkIdentifier()])
        case ("DELETE", let path) where path.hasPrefix("/rest/app-chat/conversations/soft/"):
            return jsonResponse(["ok": true])
        case ("GET", let path) where path.hasSuffix("/response-node"):
            return jsonResponse([
                "responseNodes": [
                    ["responseId": "resp-user", "sender": "human"],
                    ["responseId": "resp-e2e", "sender": "assistant", "parentResponseId": "resp-user"]
                ]
            ])
        case ("POST", let path) where path.hasSuffix("/load-responses"):
            if let loadedResponses {
                return jsonResponse(["responses": loadedResponses])
            }
            var assistantResponse: [String: Any] = [
                "responseId": "resp-e2e",
                "message": loadedAssistantMessage,
                "sender": "assistant",
                "createTime": "2026-05-13T00:00:01Z",
                "parentResponseId": "resp-user"
            ]
            if let loadedAssistantMetadata {
                for (key, value) in loadedAssistantMetadata {
                    assistantResponse[key] = value
                }
            }
            return jsonResponse([
                "responses": [
                    ["responseId": "resp-user", "message": "Loaded user response", "sender": "human", "createTime": "2026-05-13T00:00:00Z"],
                    assistantResponse
                ]
            ])
        case ("GET", let path) where path.hasPrefix("/rest/app-chat/conversations_v2/"):
            return jsonResponse([
                "conversation": [
                    "conversationId": request.pathComponent(after: "conversations_v2") ?? "conv-e2e",
                    "title": "Mock Conversation V2",
                    "workspaces": ["workspace-1"],
                    "taskResult": ["status": "done"]
                ]
            ])
        case ("GET", "/rest/tasks"):
            return jsonResponse(["tasks": activeTaskJSON()])
        case ("GET", "/rest/tasks/inactive"):
            return jsonResponse(["tasks": inactiveTaskJSON()])
        case ("GET", let path) where path.hasPrefix("/rest/tasks/results/"):
            let taskId = request.pathComponent(after: "results") ?? "task-summary-daily"
            let limit = request.queryInt("limit") ?? 1
            let results = [
                taskResultJSON(taskId: taskId),
                taskResultJSON(
                    taskId: taskId,
                    resultId: "previous-result-\(taskId)",
                    conversationId: "previous-conv-\(taskId)",
                    responseId: "previous-resp-\(taskId)",
                    message: "Previous run captured one older product research update.",
                    createTime: "2026-05-08T12:00:00Z"
                )
            ]
            return jsonResponse(["results": Array(results.prefix(max(limit, 0)))])
        case ("POST", "/rest/tasks"):
            return jsonResponse(["task": taskJSON(prompt: request.jsonString("prompt") ?? "created prompt")])
        case ("PUT", "/rest/tasks/archive"):
            return jsonResponse(["task": taskJSON(isEnabled: false)])
        case ("POST", "/rest/skills"):
            return jsonResponse(["skills": builtInSkills])
        case ("GET", "/rest/user-skills"):
            return jsonResponse(["userSkills": userSkills])
        case ("GET", "/rest/user-settings"):
            return jsonResponse(["agentCustomizations": ["values": agentValues()]])
        case ("POST", "/rest/user-settings"):
            let values = ((request.jsonBody["agentCustomizations"] as? [String: Any])?["values"] as? [[String: Any]]) ?? agentValues()
            return jsonResponse(["agentCustomizations": ["values": values]])
        case ("GET", "/rest/workspaces"):
            return jsonResponse(["workspaces": [workspaceJSON()]])
        case ("POST", "/rest/workspaces"):
            return jsonResponse(["workspace": workspaceJSON(name: request.jsonString("name") ?? "Created Workspace")])
        case ("DELETE", let path) where path.hasPrefix("/rest/workspaces/"):
            return jsonResponse(["workspace": workspaceJSON()])
        case ("POST", let path) where path.hasPrefix("/rest/workspaces/") && path.hasSuffix("/conversations"):
            return jsonResponse(["workspace": workspaceJSON()])
        case ("GET", "/rest/assets"):
            return jsonResponse(["assets": [assetJSON()]])
        case ("DELETE", let path) where path.hasPrefix("/rest/assets/"):
            return jsonResponse(["asset": assetJSON()])
        case ("POST", "/rest/app-chat/upload-file"):
            return jsonResponse([
                "fileMetadataId": "uploaded-file-1",
                "fileName": request.jsonString("fileName") ?? "upload.txt"
            ])
        default:
            return jsonResponse(["error": "Unhandled \(request.method) \(request.target)"], status: 404)
        }
    }

    private func streamResponse(conversationId: String, responseId: String) -> HTTPResponse {
        if let streamLines {
            return HTTPResponse(body: Data(streamLines.joined(separator: "\n").appending("\n").utf8), contentType: "text/event-stream")
        }

        var lines = streamTokens.enumerated().map { index, token in
            var result: [String: Any] = [
                "response": [
                    "responseId": responseId,
                    "token": token
                ]
            ]
            if index == 0 {
                result["conversation"] = ["conversationId": conversationId]
            }
            return jsonLine(["result": result])
        }
        lines.append(jsonLine([
            "result": [
                "response": [
                    "modelResponse": [
                        "message": finalMessage,
                        "responseId": responseId
                    ]
                ]
            ]
        ]))
        return HTTPResponse(body: Data(lines.joined(separator: "\n").appending("\n").utf8), contentType: "text/event-stream")
    }

    private func xaiStreamingResponse(responseId: String) -> HTTPResponse {
        let lines = xaiResponseStreamLines ?? [
            "data: \(jsonLine(["type": "response.created", "response": ["id": responseId]]))",
            "data: \(jsonLine(["type": "response.output_text.delta", "delta": finalMessage]))",
            "data: \(jsonLine(["type": "response.completed", "response": ["id": responseId, "output_text": finalMessage]]))",
            "data: [DONE]"
        ]
        return HTTPResponse(body: Data(lines.joined(separator: "\n").appending("\n").utf8), contentType: "text/event-stream")
    }

    private func nextXAIVideoPollResponse() -> [String: Any] {
        guard !xaiVideoPollResponses.isEmpty else {
            return Self.doneXAIVideoPollResponse
        }
        if xaiVideoPollResponses.count == 1 {
            return xaiVideoPollResponses[0]
        }
        return xaiVideoPollResponses.removeFirst()
    }

    private func jsonLine(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonResponse(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data, contentType: "application/json")
    }

    private func shareLinkIdentifier() -> String {
        if let url = URL(string: shareLinkURL), !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }
        return shareLinkURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .last
            .map(String.init) ?? "mock-share-link"
    }

    private func activeTaskJSON() -> [[String: Any]] {
        [
            taskJSON(
                taskId: "task-summary-daily",
                name: "Morning Research Brief",
                prompt: "Summarize overnight product and AI research updates.",
                isEnabled: true,
                dayOfYear: "2026-05-15",
                timeOfDay: "08:00",
                timezone: "America/New_York"
            ),
            taskJSON(
                taskId: "task-summary-weekly",
                name: "Weekly Support Digest",
                prompt: "Create a weekly digest of support escalations.",
                isEnabled: true,
                dayOfYear: "2026-05-18",
                timeOfDay: "09:30",
                timezone: "UTC"
            )
        ]
    }

    private func inactiveTaskJSON() -> [[String: Any]] {
        [
            taskJSON(
                taskId: "task-archived-roadmap",
                name: "Archived Roadmap Sweep",
                prompt: "Find stale roadmap notes for review.",
                isEnabled: false,
                dayOfYear: "2026-04-30",
                timeOfDay: "16:00",
                timezone: "UTC"
            )
        ]
    }

    private func taskJSON(
        taskId: String = "task-summary-daily",
        name: String = "Morning Research Brief",
        prompt: String = "Summarize overnight product and AI research updates.",
        isEnabled: Bool = true,
        dayOfYear: String = "2026-05-15",
        timeOfDay: String = "08:00",
        timezone: String = "America/New_York",
        includeLatestResult: Bool = true
    ) -> [String: Any] {
        var task: [String: Any] = [
            "taskId": taskId,
            "name": name,
            "prompt": prompt,
            "isEnabled": isEnabled,
            "status": isEnabled ? "enabled" : "archived",
            "schedule": [
                "dayOfYear": dayOfYear,
                "timeOfDay": timeOfDay,
                "timezone": timezone
            ]
        ]
        if includeLatestResult {
            task["latestResult"] = taskResultJSON(taskId: taskId)
            task["rawTaskPayload"] = "internalOnly redacted mock field with cookie marker"
        }
        return task
    }

    private func taskResultJSON(
        taskId: String,
        resultId: String? = nil,
        conversationId: String? = nil,
        responseId: String? = nil,
        message: String = "Three notable product research updates landed overnight.",
        createTime: String = "2026-05-15T12:00:00Z"
    ) -> [String: Any] {
        [
            "taskResultId": resultId ?? "result-\(taskId)",
            "taskId": taskId,
            "conversationId": conversationId ?? "conv-\(taskId)",
            "responseId": responseId ?? "resp-\(taskId)",
            "status": "done",
            "summary": message,
            "message": message,
            "createTime": createTime
        ]
    }

    private func modeJSON() -> [[String: Any]] {
        [
            [
                "id": "auto",
                "displayName": "Auto",
                "summary": "Chooses Fast or Expert",
                "availability": ["available": [:]]
            ],
            [
                "id": "fast",
                "displayName": "Fast",
                "summary": "Quick responses",
                "availability": ["available": [:]]
            ],
            [
                "id": "expert",
                "displayName": "Expert",
                "summary": "Thinks hard",
                "availability": ["available": [:]]
            ],
            [
                "id": "grok-420-computer-use-sa",
                "displayName": "Grok 4.3 (beta)",
                "summary": "Uses Skills and Connectors",
                "availability": ["available": [:]]
            ],
            [
                "id": "heavy",
                "displayName": "Heavy",
                "summary": "Team of Experts",
                "availability": heavyRequiresUpgrade ? [
                    "requiresUpgrade": [
                        "message": "",
                        "minimumSubscriptionTier": "TIER_SUPERGROK_HEAVY"
                    ]
                ] : ["available": [:]]
            ]
        ]
    }

    private func skillJSON(id: String = "skill-1", name: String = "Mock Skill") -> [String: Any] {
        [
            "skillId": id,
            "name": name,
            "description": "Mock skill description",
            "status": "enabled"
        ]
    }

    private func agentValues() -> [[String: Any]] {
        [
            [
                "agentId": false,
                "name": "Grok",
                "instructions": "Default agent instructions",
                "agent": ["name": "Grok", "instructions": "Default agent instructions"]
            ],
            [
                "agentId": true,
                "name": "Grok II",
                "agent": ["name": "Grok II", "instructions": "Skeptical agent instructions"]
            ],
            [
                "agentId": 2,
                "agent": ["name": "Grok III", "instructions": "Optimistic agent instructions"]
            ],
            [
                "agentId": 3,
                "name": "Grok IV",
                "instructions": "Scientific agent instructions",
                "agent": ["name": "Grok IV", "instructions": "Scientific agent instructions"]
            ]
        ]
    }

    private func workspaceJSON(name: String = "Mock Workspace") -> [String: Any] {
        [
            "workspaceId": "workspace-1",
            "name": name,
            "icon": "star",
            "preferredModel": "expert"
        ]
    }

    private func assetJSON() -> [String: Any] {
        [
            "fileMetadataId": "file-1",
            "fileName": "mock.txt",
            "mimeType": "text/plain"
        ]
    }
}

private struct HTTPRequest {
    let method: String
    let target: String
    let path: String
    let headers: [String: String]
    let body: Data
    let jsonBody: [String: Any]

    init?(data: Data) {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            return nil
        }

        let headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
            guard let separator = line.firstIndex(of: ":") else {
                return nil
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, value)
        })

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        self.method = requestParts[0]
        self.target = requestParts[1]
        self.path = requestParts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestParts[1]
        self.headers = headers
        self.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        self.jsonBody = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func jsonString(_ key: String) -> String? {
        jsonBody[key] as? String
    }

    func jsonBool(_ key: String) -> Bool? {
        jsonBody[key] as? Bool
    }

    func pathComponent(after component: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: component), index + 1 < parts.count else {
            return nil
        }
        return parts[index + 1]
    }

    func queryInt(_ key: String) -> Int? {
        guard let components = URLComponents(string: "http://localhost\(target)") else {
            return nil
        }
        return components.queryItems?
            .first(where: { $0.name == key })?
            .value
            .flatMap(Int.init)
    }
}

private struct HTTPResponse {
    var status: Int = 200
    let body: Data
    let contentType: String
}

private func XCTAssertContains(
    _ text: String,
    _ expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(
        text.contains(expected),
        "Expected output to contain \(expected), got:\n\(text)",
        file: file,
        line: line
    )
}
#else
final class GrokCLIE2ETests: XCTestCase {
    func testGrokCLIE2ERequiresNetworkFramework() throws {
        throw XCTSkip("Grok CLI E2E tests require Apple's Network framework.")
    }
}
#endif
