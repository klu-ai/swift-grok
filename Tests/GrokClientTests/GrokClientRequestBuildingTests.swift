import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GrokClient

final class GrokClientRequestBuildingTests: XCTestCase {
    func testBaseURLNormalizationFromRestBaseBuildsAppChatRootAndWebRequests() throws {
        let client = try makeClient(baseURL: "https://example.test/rest/")

        let appChat = try client.makeRequest(path: "/conversations/new")
        let root = try client.makeRequest(path: "/modes", namespace: .root)
        let web = try client.makeRequest(path: "/api/ping", method: "GET", namespace: .web)

        XCTAssertEqual(appChat.url?.absoluteString, "https://example.test/rest/app-chat/conversations/new")
        XCTAssertEqual(root.url?.absoluteString, "https://example.test/rest/modes")
        XCTAssertEqual(web.url?.absoluteString, "https://example.test/api/ping")
    }

    func testBaseURLNormalizationFromAppChatBaseDoesNotDuplicateAppChat() throws {
        let client = try makeClient(baseURL: "https://example.test/rest/app-chat")

        let request = try client.makeRequest(path: "/conversations/new")
        let root = try client.makeRequest(path: "/rate-limits", namespace: .root)

        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/app-chat/conversations/new")
        XCTAssertEqual(root.url?.absoluteString, "https://example.test/rest/rate-limits")
    }

    func testBaseURLNormalizationFromWebBaseAddsRestSegments() throws {
        let client = try makeClient(baseURL: "https://example.test")

        let appChat = try client.makeRequest(path: "/conversations/new")
        let root = try client.makeRequest(path: "/subscriptions", method: "GET", namespace: .root)
        let web = try client.makeRequest(path: "/settings", method: "GET", namespace: .web)

        XCTAssertEqual(appChat.url?.absoluteString, "https://example.test/rest/app-chat/conversations/new")
        XCTAssertEqual(root.url?.absoluteString, "https://example.test/rest/subscriptions")
        XCTAssertEqual(web.url?.absoluteString, "https://example.test/settings")
    }

    func testPostRequestIncludesBrowserHeadersCookieRequestIDAndStatsig() throws {
        let client = try makeClient(cookies: [
            "__cf_bm": "bm-cookie",
            "cf_clearance": "cf-cookie",
            "grok_device_id": "device-cookie",
            "sso": "sso-cookie",
            "x-anonuserid": "anon-cookie"
        ])
        let request = try client.makeRequest(path: "/conversations/new", payload: ["message": "hello"])

        XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "*/*")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "origin"), "https://grok.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "referer"), "https://grok.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "sec-ch-ua-full-version"), #""151.0.7922.138""#)
        XCTAssertTrue(try XCTUnwrap(request.value(forHTTPHeaderField: "sec-ch-ua-full-version-list")).contains("151.0.7922.138"))
        let cookieHeader = try XCTUnwrap(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertTrue(cookieHeader.contains("__cf_bm=bm-cookie"))
        XCTAssertTrue(cookieHeader.contains("cf_clearance=cf-cookie"))
        XCTAssertTrue(cookieHeader.contains("grok_device_id=device-cookie"))
        XCTAssertTrue(cookieHeader.contains("sso=sso-cookie"))
        XCTAssertTrue(cookieHeader.contains("x-anonuserid=anon-cookie"))

        let requestID = try XCTUnwrap(request.value(forHTTPHeaderField: "x-xai-request-id"))
        XCTAssertNotNil(UUID(uuidString: requestID))
        XCTAssertEqual(requestID, requestID.lowercased())

        #if canImport(CryptoKit)
        let statsigID = try XCTUnwrap(request.value(forHTTPHeaderField: "x-statsig-id"))
        XCTAssertFalse(statsigID.isEmpty)
        let decodedStatsig = try decodeStatsigID(statsigID)
        XCTAssertEqual(decodedStatsig.metaBase64, "n3ZIx7mlK0v5tXOOwnOW0kx919Tg8EB66MmUtAeyFyZjNZVZ3P+DYM+SHCIrOoxZ")
        XCTAssertEqual(decodedStatsig.version, 3)
        #endif
    }

    func testGetRequestWithoutPayloadOmitsContentTypeOriginAndBody() throws {
        let client = try makeClient()
        let request = try client.makeRequest(path: "/subscriptions", method: "GET", namespace: .root)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "content-type"))
        XCTAssertNil(request.value(forHTTPHeaderField: "origin"))
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sso=test-cookie")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-xai-request-id"))
    }

    func testCurlRepresentationRedactsCookiesWhenRequested() throws {
        var request = URLRequest(url: URL(string: "https://example.test/rest/app-chat/conversations/new")!)
        request.httpMethod = "POST"
        request.setValue("sso=secret-cookie; x-anonuserid=secret-anon", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": "hello"])

        let curl = request.curlRepresentation(redactCookies: true)

        XCTAssertTrue(curl.contains("Cookie: <redacted>"))
        XCTAssertFalse(curl.contains("secret-cookie"))
        XCTAssertFalse(curl.contains("secret-anon"))
        XCTAssertTrue(curl.contains("\"https://example.test/rest/app-chat/conversations/new\""))
    }

    func testCurlRepresentationRedactsSensitiveJSONPayloads() throws {
        var request = URLRequest(url: URL(string: "https://example.test/rest/voice/speech-to-text")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "audioBase64": "YWJjZGVmZw==",
            "audioFormat": "webm",
            "nested": ["data": "secret"]
        ])

        let curl = request.curlRepresentation()

        XCTAssertFalse(curl.contains("YWJjZGVmZw=="))
        XCTAssertFalse(curl.contains("secret"))
        XCTAssertTrue(curl.contains("<redacted"))
        XCTAssertTrue(curl.contains(#""audioFormat":"webm""#) || curl.contains(#""audioFormat": "webm""#))
    }

    func testEndpointRequestUsesMockSessionFactoryAndCapturesBuiltRequest() async throws {
        let session = makeMockSession(data: #"{"modes":[]}"#.data(using: .utf8)!, statusCode: 200)
        let client = try makeClient(baseURL: "https://example.test/rest", session: session)

        _ = try await client.listModes()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/modes")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sso=test-cookie")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-xai-request-id"))

        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(json.isEmpty)
    }

    private func decodeStatsigID(_ value: String) throws -> (metaBase64: String, version: UInt8) {
        let paddingLength = (4 - value.count % 4) % 4
        guard var bytes = Data(base64Encoded: value + String(repeating: "=", count: paddingLength)).map(Array.init),
              bytes.count >= 70 else {
            throw NSError(domain: "GrokClientRequestBuildingTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid x-statsig-id encoding"
            ])
        }

        let randomByte = bytes[0]
        for index in bytes.indices.dropFirst() {
            bytes[index] ^= randomByte
        }

        return (
            metaBase64: Data(bytes[1..<49]).base64EncodedString(),
            version: bytes[69]
        )
    }

    private func makeClient(
        cookies: [String: String] = ["sso": "test-cookie"],
        baseURL: String? = nil,
        session: URLSession? = nil
    ) throws -> GrokClient {
        try GrokClient(cookies: cookies, baseURL: baseURL, session: session)
    }
}
