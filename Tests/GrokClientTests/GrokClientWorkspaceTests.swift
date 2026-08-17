import XCTest
@testable import GrokClient

final class GrokClientWorkspaceTests: XCTestCase {
    func testCreateWorkspaceUsesRootEndpointAndBody() async throws {
        let mockData = #"{"workspace":{"workspaceId":"workspace-1","name":"Research"}}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.createWorkspace(
            name: "Research",
            icon: "l:book-open:lime",
            customPersonality: "Custom instructions",
            preferredModel: "grok-special"
        )

        XCTAssertEqual(response.workspace?.workspaceId, "workspace-1")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/workspaces")
        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Research")
        XCTAssertEqual(json["icon"] as? String, "l:book-open:lime")
        XCTAssertEqual(json["customPersonality"] as? String, "Custom instructions")
        XCTAssertEqual(json["preferredModel"] as? String, "grok-special")
    }

    func testListWorkspacesResponseUsesRootEndpointAndParsesItems() async throws {
        let mockData = #"{"items":[{"workspace_id":"workspace-1","title":"Research"}]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.listWorkspacesResponse(pageSize: 25, orderBy: "ORDER_BY_LAST_USE_TIME")

        XCTAssertEqual(response.workspaces.first?.workspaceId, "workspace-1")
        XCTAssertEqual(response.workspaces.first?.title, "Research")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/workspaces?pageSize=25&orderBy=ORDER_BY_LAST_USE_TIME"
        )
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testWorkspaceQueryAndPathEndpointsEncodeSpecialCharacters() async throws {
        let listData = #"{"workspaces":[]}"#.data(using: .utf8)!
        let deleteData = #"{"workspace":{"workspaceId":"deleted"}}"#.data(using: .utf8)!
        let addData = #"{"workspace":{"workspaceId":"updated"}}"#.data(using: .utf8)!
        let mockSession = makeMockSession(responses: [
            (data: listData, statusCode: 200),
            (data: deleteData, statusCode: 200),
            (data: addData, statusCode: 200)
        ])
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        _ = try await client.listWorkspacesResponse(
            options: GrokWorkspaceListOptions(
                pageSize: 8,
                orderBy: "ORDER / ? & 東京"
            )
        )
        _ = try await client.deleteWorkspace(workspaceId: "workspace space/slash?and&unicode東京")
        _ = try await client.addConversationToWorkspace(
            workspaceId: "workspace space/slash?and&unicode東京",
            conversationId: "conv space/slash?and&unicode東京"
        )

        XCTAssertEqual(
            MockURLProtocol.requests[0].url?.absoluteString,
            "https://example.test/rest/workspaces?pageSize=8&orderBy=ORDER%20/%20?%20%26%20%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(
            MockURLProtocol.requests[1].url?.absoluteString,
            "https://example.test/rest/workspaces/workspace%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(
            MockURLProtocol.requests[2].url?.absoluteString,
            "https://example.test/rest/workspaces/workspace%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC/conversations"
        )
        let addBody = try XCTUnwrap(MockURLProtocol.requestBodies[2])
        let addJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: addBody) as? [String: Any])
        XCTAssertEqual(addJSON["conversationId"] as? String, "conv space/slash?and&unicode東京")
    }

    func testCreateWorkspaceOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = try await createWorkspaceBody(useOptions: false)
        let optionsBody = try await createWorkspaceBody(useOptions: true)

        XCTAssertTrue(Self.jsonBodiesEqual(oldBody, optionsBody))
    }

    func testListWorkspacesOldSignatureAndOptionsQueryEquivalence() async throws {
        let oldURL = try await listWorkspacesURL(useOptions: false)
        let optionsURL = try await listWorkspacesURL(useOptions: true)

        XCTAssertEqual(oldURL, optionsURL)
    }

    private func createWorkspaceBody(useOptions: Bool) async throws -> Data {
        let mockData = #"{"workspace":{"workspaceId":"workspace-1"}}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )
        let options = GrokWorkspaceCreateOptions(
            name: "Workspace body",
            icon: "l:book-open:lime",
            customPersonality: "Custom body",
            preferredModel: "grok-special"
        )

        if useOptions {
            _ = try await client.createWorkspace(options: options)
        } else {
            _ = try await client.createWorkspace(
                name: options.name,
                icon: options.icon,
                customPersonality: options.customPersonality,
                preferredModel: options.preferredModel
            )
        }

        return try XCTUnwrap(MockURLProtocol.lastRequestBody)
    }

    private func listWorkspacesURL(useOptions: Bool) async throws -> String {
        let mockData = #"{"workspaces":[]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        if useOptions {
            _ = try await client.listWorkspacesResponse(
                options: GrokWorkspaceListOptions(pageSize: 25, orderBy: "ORDER")
            )
        } else {
            _ = try await client.listWorkspacesResponse(pageSize: 25, orderBy: "ORDER")
        }

        return try XCTUnwrap(MockURLProtocol.lastRequest?.url?.absoluteString)
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
