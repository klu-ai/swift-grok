import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GrokClient

final class GrokClientModelTests: XCTestCase {
    func testGrokErrorEquatable() {
        let error1: GrokError = .invalidCredentials
        let error2: GrokError = .invalidCredentials
        let error3: GrokError = .unauthorized
        let error4: GrokError = .apiError("Something went wrong")
        let error5: GrokError = .apiError("Something went wrong")

        XCTAssertTrue(error1 == error2, "Expected .invalidCredentials to be equal.")
        XCTAssertFalse(error2 == error3, "Expected .invalidCredentials and .unauthorized to differ.")
        XCTAssertTrue(error4 == error5, "Matching .apiError messages should be equal.")
    }

    func testMessageResponseDecoding() throws {
        let json = """
        {
          "message": "Hello world",
          "timestamp": 1742045040
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MessageResponse.self, from: json)
        XCTAssertEqual(decoded.message, "Hello world")
        XCTAssertNotNil(decoded.timestamp)
    }

    func testWebSearchResultDecoding() throws {
        let json = """
        {
            "url": "https://example.com",
            "title": "Example Site",
            "preview": "Preview text...",
            "siteName": "Example",
            "description": "A sample description",
            "citationId": "abc123"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WebSearchResult.self, from: json)
        XCTAssertEqual(decoded.url, "https://example.com")
        XCTAssertEqual(decoded.title, "Example Site")
        XCTAssertEqual(decoded.citationId, "abc123")
    }

    func testXPostDecoding() throws {
        let json = """
        {
            "username": "testUser",
            "name": "Test Name",
            "text": "Hello, this is a post.",
            "postId": "xyz789",
            "createTime": "2025-03-15T09:00:00Z",
            "profileImageUrl": "https://example.com/profile.jpg",
            "citationId": "def456"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(XPost.self, from: json)
        XCTAssertEqual(decoded.username, "testUser")
        XCTAssertEqual(decoded.postId, "xyz789")
        XCTAssertEqual(decoded.citationId, "def456")
    }

    func testConversationResponseDecoding() throws {
        let json = """
        {
          "message": "Hello from Grok",
          "conversationId": "convo123",
          "responseId": "resp456",
          "timestamp": 1742045040,
          "webSearchResults": [
            {
              "url": "https://example.com",
              "title": "Example Site",
              "preview": "Preview text..."
            }
          ],
          "xposts": [
            {
              "username": "testUser",
              "name": "Test Name",
              "text": "Post content here",
              "postId": "xyz789"
            }
          ],
          "isSoftStop": false,
          "isFinal": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ConversationResponse.self, from: json)
        XCTAssertEqual(decoded.conversationId, "convo123")
        XCTAssertEqual(decoded.responseId, "resp456")
        XCTAssertEqual(decoded.webSearchResults?.count, 1)
        XCTAssertEqual(decoded.xposts?.count, 1)
    }

    func testConversationDecoding() throws {
        let json = """
        {
          "conversationId": "abc123",
          "title": "Test Conversation",
          "starred": true,
          "createTime": "2025-03-14T09:00:00Z",
          "modifyTime": "2025-03-15T09:00:00Z",
          "systemPromptName": "grok3_personality_romance_me",
          "temporary": false,
          "mediaTypes": ["text","image"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Conversation.self, from: json)
        XCTAssertEqual(decoded.conversationId, "abc123")
        XCTAssertEqual(decoded.title, "Test Conversation")
        XCTAssertTrue(decoded.starred)
        XCTAssertEqual(decoded.mediaTypes.count, 2)
    }

    func testResponseNodeDecoding() throws {
        let json = """
        {
          "responseId": "resp123",
          "sender": "user",
          "parentResponseId": "parent999"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ResponseNode.self, from: json)
        XCTAssertEqual(decoded.responseId, "resp123")
        XCTAssertEqual(decoded.sender, "user")
        XCTAssertEqual(decoded.parentResponseId, "parent999")
    }

    func testResponseDecoding() throws {
        let json = """
        {
          "responseId": "resp123",
          "message": "Hello again",
          "sender": "user",
          "createTime": "2025-03-15T08:00:00Z",
          "parentResponseId": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Response.self, from: json)
        XCTAssertEqual(decoded.responseId, "resp123")
        XCTAssertEqual(decoded.sender, "user")
        XCTAssertNil(decoded.parentResponseId)
    }

    func testConversationsResponseDecoding() throws {
        let json = """
        {
          "conversations": [
            {
              "conversationId": "abc123",
              "title": "Test 1",
              "starred": false,
              "createTime": "",
              "modifyTime": "",
              "systemPromptName": "",
              "temporary": false,
              "mediaTypes": []
            }
          ],
          "nextPageToken": "nextPage",
          "textSearchMatches": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ConversationsResponse.self, from: json)
        XCTAssertEqual(decoded.conversations.count, 1)
        XCTAssertEqual(decoded.nextPageToken, "nextPage")
    }

    func testExtractWebSearchResults() {
        let modelResponse = ModelResponse(
            message: "Example",
            responseId: "111",
            sender: nil,
            createTime: nil,
            parentResponseId: nil,
            webSearchResults: [
                WebSearchResultInternal(
                    url: "https://example.com",
                    title: "Example",
                    preview: "Preview",
                    searchEngineText: "",
                    description: "Desc",
                    siteName: "Site",
                    metadataTitle: "Meta",
                    creator: "",
                    image: "",
                    favicon: "",
                    citationId: "cit1"
                ),
                WebSearchResultInternal(
                    url: "",
                    title: "Ignore me",
                    preview: "Preview",
                    searchEngineText: "",
                    description: "Desc",
                    siteName: "Site",
                    metadataTitle: "Meta",
                    creator: "",
                    image: "",
                    favicon: "",
                    citationId: ""
                )
            ],
            xposts: nil
        )

        let results = modelResponse.extractWebSearchResults()
        XCTAssertEqual(results?.count, 1, "Expected to ignore empty URL entries.")
        XCTAssertEqual(results?.first?.url, "https://example.com")
        XCTAssertEqual(results?.first?.title, "Example")
    }

    func testExtractXPosts() {
        let modelResponse = ModelResponse(
            message: "XPost Example",
            responseId: "222",
            sender: nil,
            createTime: nil,
            parentResponseId: nil,
            webSearchResults: nil,
            xposts: [
                XPostInternal(
                    username: "stephen",
                    name: "Stephen",
                    text: "Hello from X",
                    createTime: "2025-03-15T08:00:00Z",
                    profileImageUrl: "",
                    postId: "post123",
                    citationId: ""
                ),
                XPostInternal(
                    username: "",
                    name: "Jane",
                    text: "No username",
                    createTime: "",
                    profileImageUrl: "",
                    postId: "post456",
                    citationId: ""
                )
            ]
        )

        let results = modelResponse.extractXPosts()
        XCTAssertEqual(results?.count, 1, "Expected to ignore empty username entries.")
        XCTAssertEqual(results?.first?.username, "stephen")
    }

    func testGrokModeAliases() {
        XCTAssertEqual(GrokMode.resolve(nil).id, "fast")
        XCTAssertEqual(GrokMode.resolve("expert").id, "expert")
        XCTAssertEqual(GrokMode.resolve("grok-4.3-beta").id, "grok-420-computer-use-sa")
        XCTAssertEqual(GrokMode.resolve("new-web-mode").id, "new-web-mode")
    }

    func testValidationMaps401ToUnauthorized() throws {
        let client = try makeClient()
        let response = try httpResponse(statusCode: 401)

        XCTAssertThrowsError(try client.validateHTTPResponse(response)) { error in
            XCTAssertEqual(error as? GrokError, .unauthorized)
        }
    }

    func testValidationMaps403AuthenticationBodyToUnauthorized() throws {
        let client = try makeClient()
        let response = try httpResponse(statusCode: 403)
        let body = #"{"error":{"message":"cookie expired"}}"#.data(using: .utf8)!

        XCTAssertThrowsError(try client.validateHTTPResponse(response, data: body)) { error in
            XCTAssertEqual(error as? GrokError, .unauthorized)
        }
    }

    func testValidationMaps403FeatureDenialToAccessDenied() throws {
        let client = try makeClient()
        let response = try httpResponse(statusCode: 403)
        let body = #"{"message":"Requires upgraded access"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try client.validateHTTPResponse(response, data: body, modeId: "grok-4.3-beta")) { error in
            guard case .accessDenied(let message) = error as? GrokError else {
                return XCTFail("Expected accessDenied, got \(error)")
            }

            XCTAssertTrue(message.contains("Grok 4.3 (beta)"))
            XCTAssertTrue(message.contains("Requires upgraded access"))
            XCTAssertTrue(message.contains("--model fast"))
        }
    }

    func testValidationMaps403AntiBotBodyToAntiBotRejected() throws {
        let client = try makeClient()
        let response = try httpResponse(statusCode: 403)
        let body = #"{"error":{"message":"Request rejected by anti-bot rules"}}"#.data(using: .utf8)!

        XCTAssertThrowsError(try client.validateHTTPResponse(response, data: body, modeId: "fast")) { error in
            guard case .antiBotRejected(let message) = error as? GrokError else {
                return XCTFail("Expected antiBotRejected, got \(error)")
            }

            XCTAssertTrue(message.contains("Fast (fast)"))
            XCTAssertTrue(message.contains("Request rejected by anti-bot rules"))
            XCTAssertTrue(message.contains("not model access"))
            XCTAssertFalse(message.contains("Switch models"))
        }
    }

    func testValidationMaps404ToNotFound() throws {
        let client = try makeClient()
        let response = try httpResponse(statusCode: 404)

        XCTAssertThrowsError(try client.validateHTTPResponse(response)) { error in
            XCTAssertEqual(error as? GrokError, .notFound)
        }
    }

    func testValidationMapsOtherStatusToAPIErrorWithBody() throws {
        let client = try makeClient()
        let response = try httpResponse(statusCode: 500)
        let body = #"{"error":"server bad"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try client.validateHTTPResponse(response, data: body)) { error in
            guard case .apiError(let message) = error as? GrokError else {
                return XCTFail("Expected apiError, got \(error)")
            }

            XCTAssertTrue(message.contains("HTTP Error: 500"))
            XCTAssertTrue(message.contains("server bad"))
        }
    }

    private func makeClient() throws -> GrokClient {
        try GrokClient(cookies: ["sso": "test-cookie"])
    }

    private func httpResponse(statusCode: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.test/rest/app-chat/test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
    }
}
