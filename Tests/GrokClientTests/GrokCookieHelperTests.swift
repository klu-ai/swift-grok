import XCTest
@testable import GrokClient
@testable import GrokCLI

final class GrokCookieHelperTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - JSON File Tests
    
    func testJSONFileLoading() throws {
        // Create test JSON file
        let testCookies = [
            "x-anonuserid": "test_user",
            "x-challenge": "test_challenge",
            "x-signature": "test_signature",
            "sso": "test_sso",
            "sso-rw": "test_sso_rw"
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: testCookies)
        let jsonFile = tempDirectory.appendingPathComponent("test_cookies.json")
        try jsonData.write(to: jsonFile)
        
        // Test loading from JSON file
        let client = try GrokClient.fromJSONFile(at: jsonFile.path)
        XCTAssertNotNil(client)
    }
    
    func testInvalidJSONFile() {
        // Create invalid JSON file
        let invalidContent = "invalid json content"
        let jsonFile = tempDirectory.appendingPathComponent("invalid.json")
        try? invalidContent.write(to: jsonFile, atomically: true, encoding: .utf8)
        
        // Test that invalid JSON throws error
        XCTAssertThrowsError(try GrokClient.fromJSONFile(at: jsonFile.path)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    // MARK: - Cookie File Tests
    
    func testCookieFileParsing() throws {
        // Create test cookie file
        let cookieContent = """
        let cookies = [
            "x-anonuserid": "test_user",
            "x-challenge": "test_challenge",
            "x-signature": "test_signature",
            "sso": "test_sso",
            "sso-rw": "test_sso_rw"
        ]
        """
        let cookieFile = tempDirectory.appendingPathComponent("GrokCookies.swift")
        try cookieContent.write(to: cookieFile, atomically: true, encoding: .utf8)
        
        // Test parsing the cookie file
        let app = GrokCLIApp.shared
        let cookies = try app.getCookiesFromFile()
        
        XCTAssertEqual(cookies["x-anonuserid"], "test_user")
        XCTAssertEqual(cookies["x-challenge"], "test_challenge")
        XCTAssertEqual(cookies["x-signature"], "test_signature")
        XCTAssertEqual(cookies["sso"], "test_sso")
        XCTAssertEqual(cookies["sso-rw"], "test_sso_rw")
    }
    
    func testCookieFileWithComments() throws {
        let cookieContent = """
        // Test cookies
        let cookies = [
            "x-anonuserid": "test_user", // User ID
            "x-challenge": "test_challenge", // Challenge value
            "x-signature": "test_signature", // Signature
            "sso": "test_sso", // SSO token
            "sso-rw": "test_sso_rw" // SSO read-write token
        ]
        """
        let cookieFile = tempDirectory.appendingPathComponent("GrokCookies.swift")
        try cookieContent.write(to: cookieFile, atomically: true, encoding: .utf8)
        
        let app = GrokCLIApp.shared
        let cookies = try app.getCookiesFromFile()
        
        XCTAssertEqual(cookies["x-anonuserid"], "test_user")
        XCTAssertEqual(cookies["x-challenge"], "test_challenge")
        XCTAssertEqual(cookies["x-signature"], "test_signature")
        XCTAssertEqual(cookies["sso"], "test_sso")
        XCTAssertEqual(cookies["sso-rw"], "test_sso_rw")
    }
    
    func testMissingCookieFile() {
        let app = GrokCLIApp.shared
        XCTAssertThrowsError(try app.getCookiesFromFile()) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    // MARK: - Cookie Validation Tests
    
    func testRequiredCookies() {
        let validCookies = [
            "x-anonuserid": "test_user",
            "x-challenge": "test_challenge",
            "x-signature": "test_signature",
            "sso": "test_sso",
            "sso-rw": "test_sso_rw"
        ]
        
        let invalidCookies = [
            "x-anonuserid": "test_user"
        ]
        
        XCTAssertNoThrow(try GrokClient(cookies: validCookies))
        XCTAssertThrowsError(try GrokClient(cookies: invalidCookies)) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    func testCookieValueValidation() {
        let cookiesWithEmptyValue = [
            "x-anonuserid": "",
            "x-challenge": "test_challenge",
            "x-signature": "test_signature",
            "sso": "test_sso",
            "sso-rw": "test_sso_rw"
        ]
        
        XCTAssertThrowsError(try GrokClient(cookies: cookiesWithEmptyValue)) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    // MARK: - Auto Cookie Tests
    
    func testAutoCookieLoading() {
        // Create a mock GrokCookies.swift file
        let cookieContent = """
        import Foundation
        
        class GrokCookies {
            static let cookies = [
                "x-anonuserid": "test_user",
                "x-challenge": "test_challenge",
                "x-signature": "test_signature",
                "sso": "test_sso",
                "sso-rw": "test_sso_rw"
            ]
        }
        """
        let cookieFile = tempDirectory.appendingPathComponent("GrokCookies.swift")
        try? cookieContent.write(to: cookieFile, atomically: true, encoding: .utf8)
        
        // Test auto cookie loading
        XCTAssertThrowsError(try GrokClient.withAutoCookies()) { error in
            // This should fail since the class isn't compiled into the test bundle
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
} 