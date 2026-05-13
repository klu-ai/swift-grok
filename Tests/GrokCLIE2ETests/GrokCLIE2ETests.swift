import Foundation
import Network
import XCTest
@testable import GrokCLI

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

        let models = try environment.run(["models"])
        XCTAssertEqual(models.status, 0)
        XCTAssertContains(models.cleanOutput, "Available web modes:")
        XCTAssertContains(models.cleanOutput, "Grok 4.3 (beta)")

        let modelsHelp = try environment.run(["models", "--help"])
        XCTAssertEqual(modelsHelp.status, 0)
        XCTAssertContains(modelsHelp.cleanOutput, "Usage: grok models")
        XCTAssertContains(modelsHelp.cleanOutput, "Available web modes:")

        let modes = try environment.run(["modes"])
        XCTAssertEqual(modes.status, 0)
        XCTAssertContains(modes.cleanOutput, "Available web modes:")

        let auth = try environment.run(["auth", "help"])
        XCTAssertEqual(auth.status, 0)
        XCTAssertContains(auth.cleanOutput, "Auth commands:")

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

        let chatCommand = try environment.run(["chat", "hello"], input: "/quit\n")
        XCTAssertEqual(chatCommand.status, 0)
        XCTAssertContains(chatCommand.cleanOutput, "Sending message: hello")
        XCTAssertFalse(chatCommand.cleanOutput.contains("Sending message: chat hello"))

        let topLevelHelpFlag = try environment.run(["--help"])
        XCTAssertEqual(topLevelHelpFlag.status, 0)
        XCTAssertContains(topLevelHelpFlag.cleanOutput, "Usage: grok [command] [options]")
    }

    func testInitialChatMessageContinuesWithoutRepeatingStartupBanner() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["chat", "hello"], input: "follow up\n/quit\n")

        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Sending message: hello")
        XCTAssertContains(run.cleanOutput, "Enter your message:")
        XCTAssertFalse(run.cleanOutput.contains("Connected to Grok!"))
        XCTAssertFalse(run.cleanOutput.contains("Chat mode |"))
        XCTAssertFalse(run.cleanOutput.contains("Conversation ID:"))

        let requests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertTrue(requests.contains { $0.path == "/rest/app-chat/conversations/new" && $0.jsonString("message") == "hello" })
        XCTAssertTrue(requests.contains { $0.path.hasSuffix("/responses") && $0.jsonString("message") == "follow up" })
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
        XCTAssertNil(messageRequests.last?.json["disableSearch"])
        XCTAssertEqual(messageRequests.last?.jsonBool("temporary"), true)
        XCTAssertNil(messageRequests.last?.json["customPersonality"])
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
            input: "/list\n1\ncontinue loaded thread\n/quit\n",
            timeout: 15
        )

        XCTAssertEqual(run.status, 0)
        let followUp = try XCTUnwrap(server.requests(matchingPath: "/rest/app-chat/conversations/conv-e2e/responses", method: "POST").last)
        XCTAssertEqual(followUp.jsonString("message"), "continue loaded thread")
        XCTAssertEqual(followUp.jsonString("parentResponseId"), "resp-e2e")
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
        XCTAssertEqual(request["reasoning"] as? Bool, false)
        XCTAssertEqual(request["deepSearch"] as? Bool, false)

        let chatAlias = try environment.run(["chat", "--format=json", "hello"])
        XCTAssertEqual(chatAlias.status, 0)
        _ = try assertResultEnvelope(
            try jsonObject(from: chatAlias),
            command: "message",
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

    func testStreamingJSONThinkingLifecycleEvents() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Thinking about your request","isThinking":true}}}"#,
            #"{"result":{"response":{"responseId":"resp-e2e","token":"answer"}}}"#,
            #"{"result":{"response":{"modelResponse":{"message":"answer","responseId":"resp-e2e"}}}}"#
        ])
        let environment = try TestEnvironment(server: server)

        let run = try environment.run(["message", "--stream", "--json", "hello"])

        XCTAssertEqual(run.status, 0)
        let eventNames = try jsonLines(from: run).compactMap { $0["event"] as? String }
        XCTAssertTrue(eventNames.contains("thinking_start"))
        XCTAssertTrue(eventNames.contains("thinking_delta"))
        XCTAssertTrue(eventNames.contains("thinking_end"))
        XCTAssertTrue(eventNames.contains("assistant_final"))
        XCTAssertEqual(eventNames.last, "done")
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

        let help = try environment.run(["help", "--json"])
        XCTAssertEqual(help.status, 0)
        let helpData = try assertResultEnvelope(
            try jsonObject(from: help),
            command: "help",
            category: "help"
        )
        XCTAssertTrue((helpData["commands"] as? [String])?.contains("message") ?? false)
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
        XCTAssertNotNil(data["raw"])

        let items = try XCTUnwrap(data["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["taskId"] as? String, "task-1")
        XCTAssertEqual(items.first?["name"] as? String, "Mock Task")
        XCTAssertEqual(items.first?["prompt"] as? String, "Mock task prompt")
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
        XCTAssertEqual(chatEnvelope["command"] as? String, "message")

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
    }

    func testStreamingThinkingChunksRenderAboveAnswer() throws {
        let server = try MockGrokServer(streamLines: [
            #"{"result":{"conversation":{"conversationId":"conv-e2e"},"response":{"responseId":"resp-e2e","token":"Thinking about your request","isThinking":true}}}"#,
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
        XCTAssertContains(run.cleanOutput, "> Thinking about your request")
        XCTAssertContains(run.cleanOutput, "> Search: current Moon distance Seattle")
        XCTAssertContains(run.cleanOutput, "long silky black hair")
        XCTAssertContains(run.cleanOutput, "does it matter")
        XCTAssertFalse(run.cleanOutput.contains("<xai:tool_usage_card"))
        XCTAssertFalse(run.cleanOutput.contains("silkSearch"))
        XCTAssertFalse(run.cleanOutput.contains("requestlong"))
        XCTAssertFalse(run.cleanOutput.contains("Estimating lunar distance and Saturn V fuel needs"))

        let thoughtRange = try XCTUnwrap(run.cleanOutput.range(of: "> Thinking about your request"))
        let answerRange = try XCTUnwrap(run.cleanOutput.range(of: "Grok:"))
        XCTAssertLessThan(thoughtRange.lowerBound, answerRange.lowerBound)
        let toolRange = try XCTUnwrap(run.cleanOutput.range(of: "> Search: current Moon distance Seattle"))
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
        XCTAssertContains(generated.cleanOutput, "Successfully generated credentials!")
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
        XCTAssertContains(safariShortcut.cleanOutput, "Successfully generated credentials!")

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
        XCTAssertContains(run.cleanOutput, "Successfully generated credentials!")
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

    func testInteractiveModelAccessErrorDoesNotRefreshCredentials() throws {
        let server = try MockGrokServer(accessDeniedNewConversationCount: 1)
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
        XCTAssertFalse(run.cleanOutput.contains("Authentication failed. Your saved Grok browser cookies may have expired."))
        XCTAssertFalse(run.cleanOutput.contains("Trying to refresh credentials from your browser..."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractorMarker.path))
        XCTAssertEqual(try String(contentsOf: environment.credentialsURL, encoding: .utf8), originalCredentials)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").count, 1)
        XCTAssertEqual(server.requests(matchingPath: "/rest/app-chat/conversations/new", method: "POST").last?.jsonString("modeId"), "heavy")
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
        XCTAssertContains(tasksList.cleanOutput, "Tasks:")

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
        XCTAssertContains(skillsList.cleanOutput, "Skills:")

        let skillsHelp = try environment.run(["skills", "--help"])
        XCTAssertEqual(skillsHelp.status, 0)
        XCTAssertContains(skillsHelp.cleanOutput, "Skills:")
        XCTAssertFalse(skillsHelp.cleanOutput.contains("Error:"))

        let skillsMine = try environment.run(["skills", "mine", "--format=json"])
        XCTAssertEqual(skillsMine.status, 0)
        XCTAssertContains(skillsMine.cleanOutput, "user-skill-1")

        let skillsUser = try environment.run(["skills", "user"])
        XCTAssertEqual(skillsUser.status, 0)
        XCTAssertContains(skillsUser.cleanOutput, "My Skills:")

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

    func testSubcommandHelpMatrixUsesRegularOutput() throws {
        let server = try MockGrokServer()
        let environment = try TestEnvironment(server: server)

        let cases: [([String], String)] = [
            (["agents", "list", "--help"], "Usage: grok agents list"),
            (["agents", "show", "--help"], "Usage: grok agents show"),
            (["agents", "edit", "--help"], "Usage: grok agents edit"),
            (["agents", "clear", "--help"], "Usage: grok agents clear"),
            (["tasks", "list", "--help"], "Usage: grok tasks list"),
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
        /list
        1
        /tasks list
        /skills user
        /agents list
        /workspaces list
        /workspace select
        0
        /files list
        /attach
        1
        /attach clear
        /attach upload \(uploadFile.path)
        /attach manual-file-id
        /reset-conversation
        /special
        hello from interactive
        help
        quit
        """

        let run = try environment.run([], input: script, timeout: 15)
        XCTAssertEqual(run.status, 0)
        XCTAssertContains(run.cleanOutput, "Connected to Grok!")
        XCTAssertContains(run.cleanOutput, "Basic Commands:")
        XCTAssertContains(run.cleanOutput, "Started a new conversation thread.")
        XCTAssertContains(run.cleanOutput, "Reasoning mode enabled")
        XCTAssertFalse(run.cleanOutput.contains("Search: Auto"))
        XCTAssertFalse(run.cleanOutput.contains("/search"))
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
        XCTAssertContains(run.cleanOutput, "My Skills:")
        XCTAssertContains(run.cleanOutput, "Agents:")
        XCTAssertContains(run.cleanOutput, "Workspaces:")
        XCTAssertContains(run.cleanOutput, "Workspace cleared.")
        XCTAssertContains(run.cleanOutput, "Files:")
        XCTAssertContains(run.cleanOutput, "Attached: mock.txt")
        XCTAssertContains(run.cleanOutput, "Cleared attached files.")
        XCTAssertContains(run.cleanOutput, "Uploaded and attached: attached.txt")
        XCTAssertContains(run.cleanOutput, "Attached file ID: manual-file-id")
        XCTAssertContains(run.cleanOutput, "Conversation reset. Starting a new conversation.")
        XCTAssertContains(run.cleanOutput, "Special mode activated.")
        XCTAssertContains(run.cleanOutput, "Goodbye!")

        let chatRequests = server.requests(method: "POST").filter { $0.path.contains("/rest/app-chat/conversations") }
        XCTAssertTrue(chatRequests.contains { $0.jsonString("message")?.contains("hello from interactive") == true })
        XCTAssertTrue(chatRequests.contains { $0.jsonString("modeId") == "raw-interactive-mode" })
        XCTAssertTrue(chatRequests.contains {
            ($0.json["fileAttachments"] as? [Any])?.contains { ($0 as? String) == "manual-file-id" } == true
        })
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
        XCTAssertContains(run.cleanOutput, "Reasoning mode enabled")
        XCTAssertFalse(run.cleanOutput.contains("Search: Auto"))
        XCTAssertFalse(run.cleanOutput.contains("/search"))
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
        XCTAssertContains(run.cleanOutput, "Tasks:")
        XCTAssertContains(run.cleanOutput, "Created task")
        XCTAssertContains(run.cleanOutput, "Workspaces:")
        XCTAssertContains(run.cleanOutput, "Workspace cleared.")
        XCTAssertContains(run.cleanOutput, "Created workspace")
        XCTAssertContains(run.cleanOutput, "Files:")
        XCTAssertContains(run.cleanOutput, "Uploaded file")
        XCTAssertContains(run.cleanOutput, "Uploaded and attached: file with spaces.txt")
        XCTAssertContains(run.cleanOutput, "Unknown command: /taskslater")
        XCTAssertContains(run.cleanOutput, "Run /help for commands.")
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
        XCTAssertContains(run.cleanOutput, "Unknown command: /wat")
        XCTAssertFalse(run.cleanOutput.contains("Error:"))
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
            formatter.printResponse("# Heading\n**bold** and `code`")
        })

        XCTAssertContains(output, "# Heading")
        XCTAssertContains(output, "**bold**")
        XCTAssertContains(output, "`code`")
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
        XCTAssertContains(run.cleanOutput, "Settings > Model: Fast | Raw")
        XCTAssertContains(run.cleanOutput, "Settings > Model: Fast | MD")
        XCTAssertFalse(run.cleanOutput.contains("Chat mode |"))
        XCTAssertFalse(run.cleanOutput.contains("Saved |"))
        XCTAssertFalse(run.cleanOutput.contains("Stream |"))
        XCTAssertFalse(run.cleanOutput.contains("Raw Output"))
        XCTAssertFalse(run.cleanOutput.contains("MD Formatted"))
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
        for banner in ["Calling Grok API", "Sending:", "Thinking", "Grok:", "Available conversations:", "Select a conversation"] {
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
            "Connected to Grok!",
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
    let body: Data
    let json: [String: Any]

    func jsonString(_ key: String) -> String? {
        json[key] as? String
    }

    func jsonBool(_ key: String) -> Bool? {
        json[key] as? Bool
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
    private var rateLimitedNewConversationCount: Int
    private let streamTokens: [String]
    private let streamLines: [String]?
    private let finalMessage: String

    init(
        unauthorizedNewConversationCount: Int = 0,
        accessDeniedNewConversationCount: Int = 0,
        rateLimitedNewConversationCount: Int = 0,
        streamTokens: [String] = ["Mock streamed ", "answer"],
        streamLines: [String]? = nil,
        finalMessage: String = "Mock final response"
    ) throws {
        self.unauthorizedNewConversationCount = unauthorizedNewConversationCount
        self.accessDeniedNewConversationCount = accessDeniedNewConversationCount
        self.rateLimitedNewConversationCount = rateLimitedNewConversationCount
        self.streamTokens = streamTokens
        self.streamLines = streamLines
        self.finalMessage = finalMessage
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
                "conversations": [[
                    "conversationId": "conv-e2e",
                    "title": "Mock Conversation",
                    "starred": false,
                    "createTime": "2026-05-13T00:00:00Z",
                    "modifyTime": "2026-05-13T00:00:00Z",
                    "systemPromptName": "",
                    "temporary": false,
                    "mediaTypes": []
                ]],
                "nextPageToken": "",
                "textSearchMatches": []
            ])
        case ("GET", let path) where path.hasSuffix("/response-node"):
            return jsonResponse([
                "responseNodes": [
                    ["responseId": "resp-user", "sender": "human"],
                    ["responseId": "resp-e2e", "sender": "assistant", "parentResponseId": "resp-user"]
                ]
            ])
        case ("POST", let path) where path.hasSuffix("/load-responses"):
            return jsonResponse([
                "responses": [
                    ["responseId": "resp-user", "message": "Loaded user response", "sender": "human", "createTime": "2026-05-13T00:00:00Z"],
                    ["responseId": "resp-e2e", "message": "Loaded assistant response", "sender": "assistant", "createTime": "2026-05-13T00:00:01Z", "parentResponseId": "resp-user"]
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
            return jsonResponse(["tasks": [taskJSON()]])
        case ("POST", "/rest/tasks"):
            return jsonResponse(["task": taskJSON(prompt: request.jsonString("prompt") ?? "created prompt")])
        case ("PUT", "/rest/tasks/archive"):
            return jsonResponse(["task": taskJSON(isEnabled: false)])
        case ("POST", "/rest/skills"):
            return jsonResponse(["skills": [skillJSON()]])
        case ("GET", "/rest/user-skills"):
            return jsonResponse(["userSkills": [skillJSON(id: "user-skill-1", name: "User Skill")]])
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

    private func jsonLine(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonResponse(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data, contentType: "application/json")
    }

    private func taskJSON(prompt: String = "Mock task prompt", isEnabled: Bool = true) -> [String: Any] {
        [
            "taskId": "task-1",
            "name": "Mock Task",
            "prompt": prompt,
            "isEnabled": isEnabled,
            "schedule": ["date": "2026-05-14", "time": "09:30", "timezone": "UTC"]
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
        self.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        self.jsonBody = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    func jsonString(_ key: String) -> String? {
        jsonBody[key] as? String
    }

    func pathComponent(after component: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: component), index + 1 < parts.count else {
            return nil
        }
        return parts[index + 1]
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
