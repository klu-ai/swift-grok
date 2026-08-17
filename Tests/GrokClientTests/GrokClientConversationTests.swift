import XCTest
@testable import GrokClient

final class GrokClientConversationTests: XCTestCase {
    func testListConversationsSuccess() async throws {
        let mockData = """
        {
          "conversations": [
            {
              "conversationId": "111",
              "title": "Test Conv",
              "starred": false,
              "createTime": "2025-03-15T09:00:00Z",
              "modifyTime": "2025-03-15T09:10:00Z",
              "systemPromptName": "",
              "temporary": false,
              "mediaTypes": []
            }
          ],
          "nextPageToken": "nextPage",
          "textSearchMatches": []
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(cookies: ["x-anonuserid": "test123"], session: mockSession)

        let conversations = try await client.listConversations()

        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.conversationId, "111")
    }

    func testListConversationsWithSearchQueryUsesEncodedURLAndPageSize() async throws {
        let mockData = """
        {
          "conversations": [
            {
              "conversation_id": "conv-search",
              "name": "Search Result"
            }
          ],
          "textSearchMatches": [
            { "text": "matched snippet" }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let conversations = try await client.listConversations(
            pageSize: 60,
            searchQuery: "swift concurrency & actors"
        )

        XCTAssertEqual(conversations.first?.conversationId, "conv-search")
        XCTAssertEqual(conversations.first?.title, "Search Result")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/app-chat/conversations?pageSize=60&searchQuery=swift%20concurrency%20%26%20actors"
        )
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testListConversationsEncodesSearchQuerySpecialCharacters() async throws {
        let mockData = #"{"conversations":[],"textSearchMatches":[]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        _ = try await client.listConversations(
            pageSize: 7,
            searchQuery: "space / slash ? question & amp 東京"
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/app-chat/conversations?pageSize=7&searchQuery=space%20/%20slash%20?%20question%20%26%20amp%20%E6%9D%B1%E4%BA%AC"
        )
    }

    func testSoftDeleteConversationUsesDeleteEndpointWithNoBody() async throws {
        let mockSession = makeMockSession(data: Data(), statusCode: 204)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        try await client.softDeleteConversation(conversationId: "conv 123")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/soft/conv%20123"
        )
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testConversationIdPathEndpointsEncodeSpecialCharacters() async throws {
        let nodesData = #"{"responseNodes":[]}"#.data(using: .utf8)!
        let loadData = #"{"responses":[]}"#.data(using: .utf8)!
        let session = makeMockSession(responses: [
            (data: nodesData, statusCode: 200),
            (data: loadData, statusCode: 200),
            (data: Data(), statusCode: 204)
        ])
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: session
        )
        let conversationId = "conv space/slash?and&unicode東京"

        _ = try await client.getResponseNodes(conversationId: conversationId)
        _ = try await client.loadResponses(conversationId: conversationId, specificResponseIds: ["resp 1"])
        try await client.softDeleteConversation(conversationId: conversationId)

        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        XCTAssertEqual(
            MockURLProtocol.requests[0].url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/conv%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC/response-node"
        )
        XCTAssertEqual(
            MockURLProtocol.requests[1].url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/conv%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC/load-responses"
        )
        XCTAssertEqual(
            MockURLProtocol.requests[2].url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/soft/conv%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC"
        )
    }

    func testGetResponseNodesSuccess() async throws {
        let mockData = """
        {
          "responseNodes": [
            {
              "responseId": "r1",
              "sender": "user",
              "parentResponseId": null
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let nodes = try await client.getResponseNodes(conversationId: "convoABC")

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.responseId, "r1")
    }

    func testGetResponseNodesCanIncludeThreads() async throws {
        let mockData = """
        {
          "responseNodes": [
            {
              "responseId": "result-response",
              "sender": "assistant",
              "parentResponseId": "thread-parent"
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let nodes = try await client.getResponseNodes(conversationId: "conv-thread", includeThreads: true)

        XCTAssertEqual(nodes.first?.responseId, "result-response")
        XCTAssertEqual(nodes.first?.parentResponseId, "thread-parent")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/conv-thread/response-node?includeThreads=true"
        )
    }

    func testLoadResponsesSuccess() async throws {
        let mockData = """
        {
          "responses": [
            {
              "responseId": "resp001",
              "message": "Loaded",
              "sender": "grok",
              "createTime": "2025-03-15T09:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let responses = try await client.loadResponses(conversationId: "convoXYZ", specificResponseIds: ["resp001"])

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.responseId, "resp001")
        XCTAssertEqual(responses.first?.message, "Loaded")
    }

    func testLoadResponsesDecodesLiveScalarModelMetadata() async throws {
        let mockData = """
        {
          "responses": [
            {
              "responseId": "resp001",
              "message": "Loaded",
              "sender": "ASSISTANT",
              "createTime": "2026-05-13T21:58:08.392Z",
              "parentResponseId": "resp-user",
              "model": "grok-420-computer-use-sa",
              "metadata": {
                "request_metadata": {
                  "mode": "grok-4-3",
                  "model": "grok-420-computer-use-sa"
                },
                "llm_info": {
                  "modelHash": "redacted"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let responses = try await client.loadResponses(conversationId: "convoXYZ", specificResponseIds: ["resp001"])

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.modelId, "grok-420-computer-use-sa")
        XCTAssertEqual(responses.first?.modeId, "grok-4-3")
    }
}
