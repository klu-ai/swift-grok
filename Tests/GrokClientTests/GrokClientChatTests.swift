import XCTest
@testable import GrokClient

final class GrokClientChatTests: XCTestCase {
    func testSendMessageSuccess() async throws {
        let streamingData = """
        {"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}
        {"result":{"response":{"responseId":"resp777","token":"World"}}}
        {"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let response = try await client.sendMessage(message: "Hi Grok")

        XCTAssertEqual(response.message, "Hello World")
        XCTAssertEqual(response.conversationId, "convo123")
        XCTAssertEqual(response.responseId, "resp777")
    }

    func testContinueConversationSuccess() async throws {
        let streamingData = """
        {"result":{"responseId":"resp888","modelResponse":{"message":"Continued","responseId":"resp888"}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let stream = try await client.continueConversation(
            conversationId: "convo123",
            parentResponseId: "resp777",
            message: "Continue from there"
        )

        var finalResponse: ConversationResponse?
        for try await response in stream {
            if response.isFinal {
                finalResponse = response
            }
        }

        XCTAssertEqual(finalResponse?.message, "Continued")
        XCTAssertEqual(finalResponse?.responseId, "resp888")
        XCTAssertNil(finalResponse?.webSearchResults)
        XCTAssertNil(finalResponse?.xposts)
    }

    func testContinueConversationEncodesSpecialConversationIdInPath() async throws {
        let path = try endpointPath(
            ["conversations", "conv space/slash?and&unicode東京", "responses"],
            queryItems: []
        )

        XCTAssertEqual(
            path,
            "/conversations/conv%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC/responses"
        )
    }

    func testSendMessageOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = requestBodyForSendMessage(useOptions: false)
        let optionsBody = requestBodyForSendMessage(useOptions: true)

        XCTAssertTrue(Self.jsonDictionariesEqual(oldBody, optionsBody))
    }

    func testStreamMessageOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = requestBodyForSendMessage(useOptions: false)
        let optionsBody = requestBodyForSendMessage(useOptions: true)

        XCTAssertTrue(Self.jsonDictionariesEqual(oldBody, optionsBody))
    }

    func testContinueConversationOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = requestBodyForContinueConversation(useOptions: false)
        let optionsBody = requestBodyForContinueConversation(useOptions: true)

        XCTAssertTrue(Self.jsonDictionariesEqual(oldBody, optionsBody))
    }

    private func requestBodyForSendMessage(useOptions: Bool) -> [String: Any] {
        let client = try! GrokClient(cookies: ["x-anonuserid": "123"])
        if useOptions {
            return client.preparePayload(message: "body check", options: messageOptions)
        }

        return client.preparePayload(
                message: "body check",
                enableReasoning: messageOptions.enableReasoning,
                enableDeepSearch: messageOptions.enableDeepSearch,
                disableSearch: messageOptions.disableSearch,
                customInstructions: messageOptions.customInstructions,
                temporary: messageOptions.temporary,
                personalityType: messageOptions.personalityType,
                modeId: messageOptions.modeId,
                fileAttachments: messageOptions.fileAttachments,
                workspaceIds: messageOptions.workspaceIds,
                disabledConnectorIds: messageOptions.disabledConnectorIds
        )
    }

    private func requestBodyForContinueConversation(useOptions: Bool) -> [String: Any] {
        var payload = requestBodyForSendMessage(useOptions: useOptions)
        if useOptions {
            payload["parentResponseId"] = "parent-body"
        } else {
            payload["parentResponseId"] = "parent-body"
        }
        return payload
    }

    private var messageOptions: GrokMessageOptions {
        GrokMessageOptions(
            enableReasoning: false,
            enableDeepSearch: true,
            disableSearch: true,
            customInstructions: "legacy ignored",
            temporary: true,
            personalityType: .romance,
            modeId: "grok-special",
            fileAttachments: ["file 1", "file/slash?and&unicode東京"],
            workspaceIds: ["workspace 1", "workspace/slash?and&unicode東京"],
            disabledConnectorIds: ["connector 1", "connector/slash?and&unicode東京"]
        )
    }

    private static func jsonDictionariesEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(NSDictionary(dictionary: rhs))
    }
}
