import XCTest
import GrokClient

final class GrokClientTests: XCTestCase, @unchecked Sendable {
    
    func testClientInitialization() throws {
        // This is just a test that the client initializes properly
        let cookies = ["x-anonuserid": "test_value", "x-challenge": "test_value"]
        
        XCTAssertNoThrow(try GrokClient(cookies: cookies))
    }
    
    func testInvalidCredentials() {
        // Testing that empty credentials throw an error
        let emptyCookies: [String: String] = [:]
        
        XCTAssertThrowsError(try GrokClient(cookies: emptyCookies)) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    // Note: The following tests would typically interact with the actual API
    // but are commented out as they require valid credentials and would make network calls
    
    /*
    func testSendMessage() async throws {
        let cookies = [
            "x-anonuserid": "your_anon_user_id",
            "x-challenge": "your_challenge_value",
            "x-signature": "your_signature_value"
        ]
        
        let client = try GrokClient(cookies: cookies)
        let response = try await client.sendMessage(message: "Hello, Grok!")
        
        XCTAssertFalse(response.isEmpty)
    }
    
    func testReasoningMode() async throws {
        let cookies = [
            "x-anonuserid": "your_anon_user_id",
            "x-challenge": "your_challenge_value",
            "x-signature": "your_signature_value"
        ]
        
        let client = try GrokClient(cookies: cookies)
        let response = try await client.sendMessage(
            message: "Explain how to calculate the area of a circle",
            enableReasoning: true
        )
        
        XCTAssertFalse(response.isEmpty)
        // Check if response contains reasoning markers
        XCTAssertTrue(response.contains("step") || response.contains("think") || response.contains("reason"))
    }
    */
    
    static let allTests = [
        ("testClientInitialization", testClientInitialization),
        ("testInvalidCredentials", testInvalidCredentials),
    ]
} 