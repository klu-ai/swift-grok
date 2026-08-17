import XCTest
@testable import GrokClient

final class GrokClientAccountTests: XCTestCase {
    func testTypeaheadUsesWorkerEndpointAndParsesSuggestions() async throws {
        let mockData = """
        {
          "suggestions": [
            { "text": "test driven development", "title": "TDD" },
            { "query": "testing swift" },
            "test cases"
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.typeahead(query: "test", maxItems: 3)

        XCTAssertEqual(response.suggestions.map(\.text), [
            "test driven development",
            "testing swift",
            "test cases"
        ])
        XCTAssertEqual(response.suggestions.first?.title, "TDD")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/_worker/typeahead?lang=en&maxItems=3&q=test&platform=web&source=1"
        )
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testTypeaheadEncodesQuerySpecialCharacters() async throws {
        let mockData = #"{"suggestions":[]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        _ = try await client.typeahead(
            query: "space / slash ? question & amp 東京",
            lang: "en-US",
            maxItems: 5,
            platform: "web app",
            source: 2
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/_worker/typeahead?lang=en-US&maxItems=5&q=space%20/%20slash%20?%20question%20%26%20amp%20%E6%9D%B1%E4%BA%AC&platform=web%20app&source=2"
        )
    }

    func testListModesUsesRootModesEndpointAndParsesAvailability() async throws {
        let responseData = """
        {
          "modes": [
            {
              "id": "fast",
              "displayName": "Fast",
              "summary": "Quick responses",
              "availability": { "available": {} }
            },
            {
              "modeId": "heavy",
              "name": "Heavy",
              "description": "Team of Experts",
              "availability": {
                "requiresUpgrade": {
                  "message": "",
                  "minimumSubscriptionTier": "TIER_SUPERGROK_HEAVY"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let modes = try await client.listModes()

        XCTAssertEqual(modes.count, 2)
        XCTAssertEqual(modes[0].id, "fast")
        XCTAssertTrue(modes[0].isAvailable)
        XCTAssertEqual(modes[1].id, "heavy")
        XCTAssertEqual(modes[1].displayName, "Heavy")
        XCTAssertFalse(modes[1].isAvailable)
        XCTAssertEqual(modes[1].minimumSubscriptionTier, "TIER_SUPERGROK_HEAVY")
        XCTAssertEqual(modes[1].unavailableDescription, "Requires TIER_SUPERGROK_HEAVY")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/modes")
        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(json.isEmpty)
    }

    func testRateLimitsRequestUsesRootEndpointAndModelName() async throws {
        let responseData = #"{"remainingResponses":9,"resetAfterSeconds":300}"#.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let response = try await client.rateLimits(modelName: "grok-420-computer-use-sa")

        XCTAssertEqual(response.modelName, "grok-420-computer-use-sa")
        XCTAssertEqual(response.remainingResponses, 9)
        XCTAssertEqual(response.resetAfterSeconds, 300)
        XCTAssertTrue(response.isLow)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/rate-limits")

        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["modelName"] as? String, "grok-420-computer-use-sa")
    }

    func testRateLimitsParsesNestedStringFieldsForRequestedModel() async throws {
        let responseData = """
        {
          "data": {
            "rateLimits": [
              {
                "modelName": "other",
                "remainingResponses": 99,
                "resetAfterSeconds": 60
              },
              {
                "modelName": "grok-420-computer-use-sa",
                "responsesRemaining": "8",
                "resetIn": "1h 30m"
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let response = try await client.rateLimits(mode: .grok43Beta)

        XCTAssertEqual(response.modelName, "grok-420-computer-use-sa")
        XCTAssertEqual(response.remainingResponses, 8)
        XCTAssertEqual(response.resetAfterSeconds, 5_400)
    }

    func testRateLimitsParsesWindowDurationWhenResetIsMissing() async throws {
        let responseData = """
        {
          "rateLimit": {
            "modelName": "fast",
            "remainingResponses": 4,
            "window": "1h"
          }
        }
        """.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let response = try await client.rateLimits(modelName: "fast")

        XCTAssertEqual(response.modelName, "fast")
        XCTAssertEqual(response.remainingResponses, 4)
        XCTAssertNil(response.resetAfterSeconds)
        XCTAssertNil(response.resetAt)
        XCTAssertEqual(response.windowSeconds, 3_600)
    }

    func testRateLimitsModeAndModelNameBodyEquivalence() async throws {
        let modelBody = try await rateLimitsBody(useMode: false)
        let modeBody = try await rateLimitsBody(useMode: true)

        XCTAssertTrue(Self.jsonBodiesEqual(modelBody, modeBody))
    }

    func testSubscriptionsRequestUsesRootEndpointAndParsesCurrentPlan() async throws {
        let responseData = """
        {
          "subscriptions": [
            {
              "subscriptionTier": "TIER_SUPERGROK",
              "status": "canceled"
            },
            {
              "subscriptionTier": "TIER_SUPERGROK_HEAVY",
              "planName": "SuperGrok Heavy",
              "status": "active"
            }
          ]
        }
        """.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let response = try await client.subscriptionsResponse()

        XCTAssertEqual(response.subscriptions.count, 2)
        XCTAssertEqual(response.currentSubscription?.tier, "TIER_SUPERGROK_HEAVY")
        XCTAssertEqual(response.currentSubscription?.displayName, "SuperGrok Heavy")
        XCTAssertEqual(response.displayName, "SuperGrok Heavy")

        let current = try await client.currentSubscription()
        XCTAssertEqual(current?.displayName, "SuperGrok Heavy")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/subscriptions")
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    private func rateLimitsBody(useMode: Bool) async throws -> Data {
        let responseData = #"{"remainingResponses":9,"resetAfterSeconds":300}"#.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        if useMode {
            _ = try await client.rateLimits(mode: .grok43Beta)
        } else {
            _ = try await client.rateLimits(modelName: GrokMode.grok43Beta.id)
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
