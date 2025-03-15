//
//  GrokClientTests.swift
//  Comprehensive test suite for GrokClient
//
//  Created by Test Engineer on 3/15/25
//

import XCTest
import ObjectiveC
@testable import GrokClient 

final class GrokClientTests: XCTestCase {
    
    // MARK: - Testable Extensions
    
    /// Extension to allow session injection for testing
    extension GrokClient {
        /// Sets the URLSession for testing purposes
        /// This is only intended to be used in tests
        func setSessionForTesting(_ newSession: URLSession) {
            // Using Objective-C runtime to set the private property
            let sessionIvar = class_getInstanceVariable(GrokClient.self, "_session")
            if let sessionIvar = sessionIvar {
                // Use withUnsafeMutablePointer to avoid direct ivar access warnings
                withUnsafeMutablePointer(to: &self) { selfPtr in
                    let sessionPtr = UnsafeMutableRawPointer(selfPtr)
                        .advanced(by: ivar_getOffset(sessionIvar))
                        .assumingMemoryBound(to: URLSession.self)
                    sessionPtr.pointee = newSession
                }
            }
        }
    }
    
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
          "timestamp": "2025-03-15T13:24:00Z"
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
          "timestamp": "2025-03-15T13:24:00Z",
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
          ]
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
            enableDeepSearch: false,
            disableSearch: false,
            customInstructions: "Custom instructions",
            temporary: true,
            personalityType: .romance
        )
        
        XCTAssertEqual(payload["message"] as? String, "test")
        XCTAssertTrue(payload["isReasoning"] as? Bool ?? false)
        XCTAssertEqual(payload["customPersonality"] as? String, "Custom instructions")
        XCTAssertEqual(payload["systemPromptName"] as? String, "grok3_personality_romance_me")
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
          "nextPageToken": "nextPage"
        }
        """.data(using: .utf8)!
        
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let cookies = ["test": "cookieVal", "x-anonuserid": "test123"]
        let client = try GrokClient(cookies: cookies)
        client.setSessionForTesting(mockSession)
        
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
        let client = try GrokClient(cookies: ["x-anonuserid":"123"])
        client.setSessionForTesting(mockSession)
        
        let response = try await client.sendMessage(message: "Hi Grok")
        XCTAssertEqual(response.message, "Hello World")
        XCTAssertEqual(response.conversationId, "convo123")
        XCTAssertEqual(response.responseId, "resp777")
    }
    
    func testContinueConversation_success() async throws {
        let streamingData = """
        {"result":{"responseId":"resp888","modelResponse":{"message":"Continued","responseId":"resp888"}}}
        """.data(using: .utf8)!
        
        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid":"123"])
        client.setSessionForTesting(mockSession)
        
        let (message, responseId, webResults, xposts) = try await client.continueConversation(
            conversationId: "convo123",
            parentResponseId: "resp777",
            message: "Continue from there"
        )
        
        XCTAssertEqual(message, "Continued")
        XCTAssertEqual(responseId, "resp888")
        XCTAssertNil(webResults)
        XCTAssertNil(xposts)
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
        let client = try GrokClient(cookies: ["x-anonuserid":"123"])
        client.setSessionForTesting(mockSession)
        
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
        let client = try GrokClient(cookies: ["x-anonuserid":"123"])
        client.setSessionForTesting(mockSession)
        
        let responses = try await client.loadResponses(conversationId: "convoXYZ")
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.responseId, "resp001")
        XCTAssertEqual(responses.first?.message, "Loaded")
    }
    
    // MARK: - Helpers
    
    private func makeMockSession(data: Data, statusCode: Int, useStreaming: Bool = false) -> URLSession {
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
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        guard let response = StreamingURLProtocol.mockResponse else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        
        if let data = StreamingURLProtocol.mockData {
            // Split the data on newline boundaries to simulate line-by-line streaming
            let lines = data.split(separator: UInt8(ascii: "\n"))
            for line in lines {
                let chunkData = Data(line)
                client?.urlProtocol(self, didLoad: chunkData)
                // Small delay to simulate streaming
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}