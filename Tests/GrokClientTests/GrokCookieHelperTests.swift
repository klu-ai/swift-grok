import XCTest
@testable import GrokClient

final class GrokCookieHelperTests: XCTestCase {
    
    func testFromSwiftDictString() throws {
        // Valid Swift dictionary string
        let validSwiftDict = """
        [
            "x-anonuserid": "test-user-id",
            "x-challenge": "test-challenge",
            "x-signature": "test-signature",
            "sso": "test-sso",
            "sso-rw": "test-sso-rw"
        ]
        """
        
        let client = try GrokClient.fromSwiftDictString(validSwiftDict)
        XCTAssertNotNil(client, "Should create a client from valid Swift dictionary string")
        
        // Empty dictionary
        let emptyDict = "[:]"
        XCTAssertThrowsError(try GrokClient.fromSwiftDictString(emptyDict)) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
        
        // Invalid format
        let invalidFormat = "not a dictionary"
        XCTAssertThrowsError(try GrokClient.fromSwiftDictString(invalidFormat)) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    func testJSONFileHandling() throws {
        // Create a temporary JSON file
        let tempDir = FileManager.default.temporaryDirectory
        let jsonURL = tempDir.appendingPathComponent("test_cookies.json")
        
        let cookiesDict = [
            "x-anonuserid": "test-user-id",
            "x-challenge": "test-challenge",
            "x-signature": "test-signature",
            "sso": "test-sso",
            "sso-rw": "test-sso-rw"
        ]
        
        let jsonData = try JSONEncoder().encode(cookiesDict)
        try jsonData.write(to: jsonURL)
        
        // Test loading from the file
        let client = try GrokClient.fromJSONFile(at: jsonURL.path)
        XCTAssertNotNil(client, "Should create a client from JSON file")
        
        // Test with non-existent file
        let nonExistentPath = tempDir.appendingPathComponent("nonexistent.json").path
        XCTAssertThrowsError(try GrokClient.fromJSONFile(at: nonExistentPath)) { _ in
            // Just verify that an error is thrown without testing the specific error type
        }
        
        // Clean up
        try FileManager.default.removeItem(at: jsonURL)
    }
} 