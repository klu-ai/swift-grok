import XCTest
@testable import GrokClient

final class GrokClientSharingTests: XCTestCase {
    func testShareLinkURLUsesGetEndpointAndDecodesWrappedURL() async throws {
        let mockData = """
        {
          "result": {
            "share_links": [
              {
                "conversationId": "conv 123",
                "share_url": " https://grok.com/share/share_abc123 "
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let shareURL = try await client.shareLinkURL(conversationId: "conv 123")

        XCTAssertEqual(shareURL, "https://grok.com/share/share_abc123")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/app-chat/share_links?pageSize=100&conversationId=conv%20123"
        )
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testShareLinkURLConstructsURLFromWrappedShareIdentifier() async throws {
        let mockData = """
        {
          "data": {
            "items": [
              {
                "share_link_id": "share_token_456"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let shareURL = try await client.shareLinkURL(conversationId: "conv-token", pageSize: 25)

        XCTAssertEqual(shareURL, "https://grok.com/share/share_token_456")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/app-chat/share_links?pageSize=25&conversationId=conv-token"
        )
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testShareLinkURLCreatesLinkWhenExistingLookupIsEmpty() async throws {
        let lookupData = #"{"shareLinks":[]}"#.data(using: .utf8)!
        let createData = #"{"shareLinkId":"created_share_123"}"#.data(using: .utf8)!
        let mockSession = makeMockSession(responses: [
            (data: lookupData, statusCode: 200),
            (data: createData, statusCode: 200)
        ])
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let shareURL = try await client.shareLinkURL(
            conversationId: "conv create",
            responseId: "resp 1"
        )

        XCTAssertEqual(shareURL, "https://grok.com/share/created_share_123")
        XCTAssertEqual(MockURLProtocol.requests.count, 2)

        let lookupRequest = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(lookupRequest.httpMethod, "GET")
        XCTAssertEqual(
            lookupRequest.url?.absoluteString,
            "https://example.test/rest/app-chat/share_links?pageSize=100&conversationId=conv%20create&responseId=resp%201"
        )

        let createRequest = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(
            createRequest.url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/conv%20create/share"
        )
        let createBody = try XCTUnwrap(MockURLProtocol.requestBodies.last.flatMap { $0 })
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["responseId"] as? String, "resp 1")
        XCTAssertEqual(createJSON["allowIndexing"] as? Bool, true)
    }

    func testShareLinkURLQueryAndCreatePathEncodeSpecialCharacters() async throws {
        let lookupData = #"{"shareLinks":[]}"#.data(using: .utf8)!
        let createData = #"{"shareLinkId":"share space/slash?and&unicode東京"}"#.data(using: .utf8)!
        let mockSession = makeMockSession(responses: [
            (data: lookupData, statusCode: 200),
            (data: createData, statusCode: 200)
        ])
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let shareURL = try await client.shareLinkURL(
            conversationId: "conv space/slash?and&unicode東京",
            responseId: "resp space/slash?and&unicode東京",
            options: GrokShareLinkOptions(pageSize: 9, allowIndexing: false)
        )

        XCTAssertEqual(
            shareURL,
            "https://grok.com/share/share%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(
            MockURLProtocol.requests[0].url?.absoluteString,
            "https://example.test/rest/app-chat/share_links?pageSize=9&conversationId=conv%20space/slash?and%26unicode%E6%9D%B1%E4%BA%AC&responseId=resp%20space/slash?and%26unicode%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(
            MockURLProtocol.requests[1].url?.absoluteString,
            "https://example.test/rest/app-chat/conversations/conv%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC/share"
        )
        let createBody = try XCTUnwrap(MockURLProtocol.requestBodies[1])
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["responseId"] as? String, "resp space/slash?and&unicode東京")
        XCTAssertEqual(createJSON["allowIndexing"] as? Bool, false)
    }

    func testShareLinkURLOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = try await createShareBody(useOptions: false)
        let optionsBody = try await createShareBody(useOptions: true)

        XCTAssertTrue(Self.jsonBodiesEqual(oldBody, optionsBody))
    }

    private func createShareBody(useOptions: Bool) async throws -> Data {
        let mockData = #"{"shareLinkId":"created_share_123"}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        if useOptions {
            _ = try await client.createShareLinkURL(
                conversationId: "conv-body",
                responseId: "resp-body",
                options: GrokShareLinkOptions(allowIndexing: true)
            )
        } else {
            _ = try await client.createShareLinkURL(conversationId: "conv-body", responseId: "resp-body")
        }

        return try XCTUnwrap(MockURLProtocol.lastRequestBody)
    }

    private static func jsonBodiesEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard
            let lhsJSON = try? JSONSerialization.jsonObject(with: lhs) as? NSDictionary,
            let rhsJSON = try? JSONSerialization.jsonObject(with: rhs) as? [AnyHashable: Any]
        else {
            return false
        }
        return lhsJSON.isEqual(NSDictionary(dictionary: rhsJSON))
    }
}
