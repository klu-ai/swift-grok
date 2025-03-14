import XCTest
@testable import GrokCLI

final class ConfigManagerTests: XCTestCase {
    var configManager: ConfigManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Initialize ConfigManager with test directory
        configManager = ConfigManager()
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Credentials Path Tests
    
    func testCredentialsPathManagement() throws {
        let testPath = tempDirectory.appendingPathComponent("test_credentials.json").path
        
        // Test saving credentials path
        try configManager.saveCredentialsPath(testPath)
        
        // Test retrieving credentials path
        let retrievedPath = configManager.getSavedCredentialsPath()
        XCTAssertEqual(retrievedPath, testPath)
    }
    
    func testMissingCredentialsPath() {
        let path = configManager.getSavedCredentialsPath()
        XCTAssertNil(path)
    }
    
    // MARK: - Cookie File Tests
    
    func testCookieFileParsing() throws {
        // Create a test cookie file
        let cookieContent = """
        let cookies = [
            "x-anonuserid": "test_user",
            "x-challenge": "test_challenge"
        ]
        """
        let cookieFile = tempDirectory.appendingPathComponent("GrokCookies.swift")
        try cookieContent.write(to: cookieFile, atomically: true, encoding: .utf8)
        
        // Test parsing the cookie file
        let app = GrokCLIApp.shared
        let cookies = try app.getCookiesFromFile()
        
        XCTAssertEqual(cookies["x-anonuserid"], "test_user")
        XCTAssertEqual(cookies["x-challenge"], "test_challenge")
    }
    
    func testInvalidCookieFile() {
        // Create an invalid cookie file
        let invalidContent = "invalid content"
        let cookieFile = tempDirectory.appendingPathComponent("GrokCookies.swift")
        try? invalidContent.write(to: cookieFile, atomically: true, encoding: .utf8)
        
        // Test that invalid file throws error
        let app = GrokCLIApp.shared
        XCTAssertThrowsError(try app.getCookiesFromFile()) { error in
            XCTAssertEqual(error as? GrokError, GrokError.invalidCredentials)
        }
    }
    
    // MARK: - File System Tests
    
    func testFileSystemOperations() throws {
        let testFile = tempDirectory.appendingPathComponent("test.json")
        let testContent = "test content"
        
        // Test file creation
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        // Test file reading
        let content = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(content, testContent)
        
        // Test file deletion
        try FileManager.default.removeItem(at: testFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
    }
} 