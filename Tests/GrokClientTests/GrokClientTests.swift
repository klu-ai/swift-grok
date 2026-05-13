//
//  GrokClientTests.swift
//  Comprehensive test suite for GrokClient
//
//  Created by Test Engineer on 3/15/25
//

import XCTest
@testable import GrokClient

final class GrokClientTests: XCTestCase {
    // MARK: - Model Tests

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

    // MARK: - GrokClient Tests

    func testPreparePayload() {
        let cookies = ["x-anonuserid": "123", "sso": "abc"]
        let client = try? GrokClient(cookies: cookies)
        XCTAssertNotNil(client)

        let payload = client!.preparePayload(
            message: "test",
            enableReasoning: true,
            enableDeepSearch: true,
            disableSearch: true,
            customInstructions: "Custom instructions",
            temporary: true,
            personalityType: .romance,
            modeId: GrokMode.expert.id
        )

        XCTAssertEqual(payload["message"] as? String, "test")
        XCTAssertEqual(payload["modeId"] as? String, "expert")
        XCTAssertNil(payload["customPersonality"])
        XCTAssertNil(payload["systemPromptName"])
        XCTAssertNil(payload["disableSearch"])
    }

    func testGrokModeAliases() {
        XCTAssertEqual(GrokMode.resolve(nil).id, "fast")
        XCTAssertEqual(GrokMode.resolve("expert").id, "expert")
        XCTAssertEqual(GrokMode.resolve("grok-4.3-beta").id, "grok-420-computer-use-sa")
        XCTAssertEqual(GrokMode.resolve("new-web-mode").id, "new-web-mode")
    }

    func testInitGrokClient_withValidCookies() {
        let cookies = [
            "x-anonuserid": "testUserId",
            "x-challenge": "testChallenge",
            "x-signature": "testSignature",
            "sso": "testSso"
        ]

        XCTAssertNoThrow(try GrokClient(cookies: cookies))
    }

    func testInitGrokClient_withEmptyCookies() {
        do {
            _ = try GrokClient(cookies: [:])
            XCTFail("Expected GrokError.invalidCredentials when passing empty cookies")
        } catch let error as GrokError {
            XCTAssertEqual(error, .invalidCredentials, "Expected .invalidCredentials but got \(error)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Below tests demonstrate the network calls with a basic mock. In practice, replace the mock responses with more rigorous tests.

    func testListConversations_success() async throws {
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
        let cookies = ["test": "cookieVal", "x-anonuserid": "test123"]
        let client = try GrokClient(cookies: cookies, session: mockSession)

        let conversations = try await client.listConversations()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.conversationId, "111")
    }

    func testSendMessage_success() async throws {
        let streamingData = """
        {"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}
        {"result":{"response":{"responseId":"resp777","token":"World"}}}
        {"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid":"123"], session: mockSession)

        let response = try await client.sendMessage(message: "Hi Grok")
        XCTAssertEqual(response.message, "Hello World")
        XCTAssertEqual(response.conversationId, "convo123")
        XCTAssertEqual(response.responseId, "resp777")
    }

    func testStreamParserYieldsFirstTokenBeforeLineSourceCompletes() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid":"123"])
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}"#)
            Task {
                try await Task.sleep(nanoseconds: 500_000_000)
                continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"World"}}}"#)
                continuation.yield(#"{"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}"#)
                continuation.finish()
            }
        }

        let stream = client.streamResponses(from: lines)
        var iterator = stream.makeAsyncIterator()
        let start = Date()

        let first = try await iterator.next()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(first?.message, "Hello ")
        XCTAssertFalse(first?.isFinal ?? true)
        XCTAssertLessThan(elapsed, 0.2, "Expected first streamed token before later chunks completed.")

        var finalResponse: ConversationResponse?
        while let response = try await iterator.next() {
            if response.isFinal {
                finalResponse = response
                break
            }
        }
        XCTAssertEqual(finalResponse?.message, "Hello World")
    }

    func testStreamMessageYieldsFallbackFinalWhenNoModelResponseArrives() async throws {
        let streamingData = """
        {"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}
        {"result":{"response":{"responseId":"resp777","token":"World"}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid":"123"], session: mockSession)

        let stream = try await client.streamMessage(message: "Hi Grok")
        var responses: [ConversationResponse] = []
        for try await response in stream {
            responses.append(response)
        }

        XCTAssertEqual(responses.map(\.message), ["Hello ", "World", "Hello World"])
        XCTAssertEqual(responses.last?.conversationId, "convo123")
        XCTAssertEqual(responses.last?.responseId, "resp777")
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamParserKeepsThinkingTokensOutOfFallbackFinal() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid":"123"])
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"long silk"}}}"#)
            continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"Responding as a beautiful Asian woman","isThinking":true}}}"#)
            continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"y black hair"}}}"#)
            continuation.finish()
        }

        let stream = client.streamResponses(from: lines)
        var responses: [ConversationResponse] = []
        for try await response in stream {
            responses.append(response)
        }

        XCTAssertEqual(responses.count, 4)
        XCTAssertEqual(responses[0].message, "long silk")
        XCTAssertFalse(responses[0].isThinking)
        XCTAssertEqual(responses[1].message, "Responding as a beautiful Asian woman")
        XCTAssertTrue(responses[1].isThinking)
        XCTAssertEqual(responses[2].message, "y black hair")
        XCTAssertFalse(responses[2].isThinking)
        XCTAssertEqual(responses[3].message, "long silky black hair")
        XCTAssertTrue(responses[3].isFinal)
    }

    func testContinueConversation_success() async throws {
        let streamingData = """
        {"result":{"responseId":"resp888","modelResponse":{"message":"Continued","responseId":"resp888"}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid":"123"], session: mockSession)

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

    func testGetResponseNodes_success() async throws {
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
        let client = try GrokClient(cookies: ["x-anonuserid":"123"], session: mockSession)

        let nodes = try await client.getResponseNodes(conversationId: "convoABC")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.responseId, "r1")
    }

    func testLoadResponses_success() async throws {
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
        let client = try GrokClient(cookies: ["x-anonuserid":"123"], session: mockSession)

        let responses = try await client.loadResponses(conversationId: "convoXYZ")
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.responseId, "resp001")
        XCTAssertEqual(responses.first?.message, "Loaded")
    }

    // MARK: - Helpers

    private func makeMockSession(data: Data, statusCode: Int, useStreaming: Bool = false, chunkDelay: TimeInterval = 0.01) -> URLSession {
        let url = URL(string: "https://mocked.url")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!

        let protocolClass: AnyClass = useStreaming ? StreamingURLProtocol.self : MockURLProtocol.self

        // Register custom protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        let session = URLSession(configuration: config)

        // Provide the static response
        if let streamingProto = protocolClass as? StreamingURLProtocol.Type {
            streamingProto.mockData = data
            streamingProto.mockResponse = response
            streamingProto.chunkDelay = chunkDelay
        } else if let mockProto = protocolClass as? MockURLProtocol.Type {
            mockProto.mockData = data
            mockProto.mockResponse = response
        }

        return session
    }
}

// MARK: - Custom URLProtocols for Mocks

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let response = MockURLProtocol.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = MockURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// StreamingURLProtocol simulates a streaming response by sending data in chunks.
class StreamingURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var chunkDelay: TimeInterval = 0.01
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = StreamingURLProtocol.mockResponse else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        guard let data = StreamingURLProtocol.mockData else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            // Split the data on newline boundaries to simulate line-by-line streaming
            let lines = data.split(separator: UInt8(ascii: "\n"))
            for line in lines {
                guard !self.stopped else { return }
                var chunkData = Data(line)
                chunkData.append(UInt8(ascii: "\n"))
                self.client?.urlProtocol(self, didLoad: chunkData)
                // Small delay to simulate streaming
                Thread.sleep(forTimeInterval: StreamingURLProtocol.chunkDelay)
            }
            guard !self.stopped else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopped = true
    }
}
