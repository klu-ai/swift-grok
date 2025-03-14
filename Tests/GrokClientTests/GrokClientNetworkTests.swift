import XCTest
@testable import GrokClient
@testable import GrokCLI

final class GrokClientNetworkTests: XCTestCase {
    var client: GrokClient!
    let testCookies = [
        "x-anonuserid": "test_user",
        "x-challenge": "test_challenge",
        "x-signature": "test_signature",
        "sso": "test_sso",
        "sso-rw": "test_sso_rw"
    ]
    
    override func setUp() {
        super.setUp()
        client = try? GrokClient(cookies: testCookies)
    }
    
    // MARK: - Response Model Tests
    
    func testMessageResponseDecoding() throws {
        let json = """
        {
            "result": {
                "response": {
                    "modelResponse": {
                        "message": "Test response"
                    }
                }
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(StreamingResponse.self, from: json)
        XCTAssertEqual(response.result?.response?.modelResponse?.message, "Test response")
    }
    
    func testConversationDecoding() throws {
        let json = """
        {
            "id": "test_id",
            "title": "Test Conversation"
        }
        """.data(using: .utf8)!
        
        let conversation = try JSONDecoder().decode(Conversation.self, from: json)
        XCTAssertEqual(conversation.id, "test_id")
        XCTAssertEqual(conversation.title, "Test Conversation")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidCredentialsError() {
        let emptyCookies: [String: String] = [:]
        
        XCTAssertThrowsError(try GrokClient(cookies: emptyCookies)) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    func testUnauthorizedError() {
        let error = GrokError.unauthorized
        XCTAssertEqual(error, GrokError.unauthorized)
    }
    
    func testNotFoundError() {
        let error = GrokError.notFound
        XCTAssertEqual(error, GrokError.notFound)
    }
    
    func testNetworkError() {
        let urlError = URLError(.notConnectedToInternet)
        let error = GrokError.networkError(urlError)
        
        if case .networkError = error {
            // Test passed
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected networkError")
        }
    }
    
    // MARK: - Payload Tests
    
    func testPayloadPreparation() {
        let message = "Test message"
        let payload = client.preparePayload(
            message: message,
            enableReasoning: true,
            enableDeepSearch: false,
            customInstructions: "Custom instructions"
        )
        
        XCTAssertEqual(payload["message"] as? String, message)
        XCTAssertEqual(payload["enableReasoning"] as? Bool, true)
        XCTAssertEqual(payload["enableDeepSearch"] as? Bool, false)
        XCTAssertEqual(payload["customInstructions"] as? String, "Custom instructions")
    }
    
    func testPayloadWithDeepSearch() {
        let payload = client.preparePayload(
            message: "Test",
            enableReasoning: false,
            enableDeepSearch: true,
            customInstructions: ""
        )
        
        XCTAssertEqual(payload["enableReasoning"] as? Bool, false)
        XCTAssertEqual(payload["enableDeepSearch"] as? Bool, true)
        XCTAssertEqual(payload["customInstructions"] as? String, "")
    }
    
    // MARK: - Cookie Helper Tests
    
    func testCookieHelperInitialization() throws {
        let cookies = try GrokClient.withAutoCookies()
        XCTAssertNotNil(cookies)
    }
    
    func testJSONFileLoading() throws {
        // Create a temporary JSON file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_cookies.json")
        let testCookies = [
            "x-anonuserid": "test_user",
            "x-challenge": "test_challenge",
            "x-signature": "test_signature"
        ]
        let jsonData = try JSONEncoder().encode(testCookies)
        try jsonData.write(to: tempURL)
        
        // Test loading from JSON file
        let client = try GrokClient.fromJSONFile(at: tempURL.path)
        XCTAssertNotNil(client)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Headers Tests
    
    func testDefaultHeaders() {
        let headers = client.headers
        
        XCTAssertEqual(headers["accept"], "*/*")
        XCTAssertEqual(headers["accept-language"], "en-GB,en;q=0.9")
        XCTAssertEqual(headers["content-type"], "application/json")
        XCTAssertEqual(headers["origin"], "https://grok.com")
        XCTAssertEqual(headers["referer"], "https://grok.com/")
    }
} 