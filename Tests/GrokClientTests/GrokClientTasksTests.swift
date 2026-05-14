import XCTest
@testable import GrokClient

final class GrokClientTasksTests: XCTestCase {
    func testListTasksResponseDecodesActiveAndInactiveTaskBuckets() async throws {
        let mockData = """
        {
          "activeTasks": [
            {
              "taskId": "task-active-1",
              "name": "Morning brief",
              "prompt": "Summarize sanitized market headlines",
              "schedule": {
                "taskCadence": "TASK_CADENCE_DAILY",
                "timezone": "Asia/Bangkok"
              }
            }
          ],
          "inactiveTasks": [
            {
              "task_id": "task-inactive-1",
              "title": "Old reminder",
              "prompt": "Sanitized inactive prompt",
              "state": "ARCHIVED"
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.listTasksResponse()

        XCTAssertEqual(response.tasks.map(\.resolvedId), ["task-active-1", "task-inactive-1"])
        XCTAssertEqual(response.activeTasks.count, 1)
        XCTAssertEqual(response.inactiveTasks.count, 1)
        XCTAssertEqual(response.activeTasks.first?.isEnabled, true)
        XCTAssertEqual(response.inactiveTasks.first?.isEnabled, false)
        XCTAssertEqual(response.inactiveTasks.first?.name, "Old reminder")
        XCTAssertEqual(response.inactiveTasks.first?.status, "ARCHIVED")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/tasks")
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testListTasksResponseDecodesNestedActiveInactiveTaskBuckets() async throws {
        let mockData = """
        {
          "data": {
            "tasks": {
              "active": [
                {
                  "task": {
                    "id": "nested-active",
                    "name": "Nested active",
                    "enabled": true
                  }
                }
              ],
              "archived": [
                {
                  "task": {
                    "id": "nested-archived",
                    "name": "Nested archived"
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.listTasksResponse()

        XCTAssertEqual(response.tasks.map(\.resolvedId), ["nested-active", "nested-archived"])
        XCTAssertEqual(response.activeTasks.first?.isEnabled, true)
        XCTAssertEqual(response.inactiveTasks.first?.isEnabled, false)
    }

    func testListInactiveTasksResponseUsesInactiveEndpointAndDefaultsDisabled() async throws {
        let mockData = """
        {
          "tasks": [
            {
              "taskId": "task-archived-1",
              "title": "Archived reminder",
              "taskPrompt": "Sanitized archived prompt"
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.listInactiveTasksResponse()

        XCTAssertEqual(response.tasks.map(\.resolvedId), ["task-archived-1"])
        XCTAssertEqual(response.tasks.first?.name, "Archived reminder")
        XCTAssertEqual(response.tasks.first?.prompt, "Sanitized archived prompt")
        XCTAssertEqual(response.tasks.first?.isEnabled, false)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/tasks/inactive")
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testTaskResultsResponseUsesRootResultsEndpointAndLimitOne() async throws {
        let mockData = """
        {
          "results": [
            {
              "taskResultId": "result-1",
              "taskId": "task-123",
              "conversationId": "conv-123",
              "responseId": "resp-123",
              "summary": "Sanitized task result text",
              "status": "COMPLETE"
            }
          ]
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.taskResultsResponse(taskId: "task 123")

        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.resolvedId, "result-1")
        XCTAssertEqual(response.results.first?.taskId, "task-123")
        XCTAssertEqual(response.results.first?.conversationId, "conv-123")
        XCTAssertEqual(response.results.first?.responseId, "resp-123")
        XCTAssertEqual(response.results.first?.message, "Sanitized task result text")
        XCTAssertEqual(response.results.first?.status, "COMPLETE")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/tasks/results/task%20123?limit=1")
        XCTAssertNil(MockURLProtocol.lastRequestBody)
    }

    func testTaskResultsResponseEncodesTaskIdSpecialCharactersAndLimit() async throws {
        let mockData = #"{"results":[]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        _ = try await client.taskResultsResponse(taskId: "task space/slash?and&unicode東京", limit: 25)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/tasks/results/task%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC?limit=25"
        )
    }

    func testLatestTaskResultDecodesSingularWrappedResult() async throws {
        let mockData = """
        {
          "data": {
            "id": "result-single",
            "task_id": "task-single",
            "conversation_id": "conv-single",
            "output": "Sanitized single result"
          }
        }
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let result = try await client.latestTaskResult(taskId: "task-single")

        XCTAssertEqual(result?.resolvedId, "result-single")
        XCTAssertEqual(result?.taskId, "task-single")
        XCTAssertEqual(result?.conversationId, "conv-single")
        XCTAssertEqual(result?.message, "Sanitized single result")
    }

    func testCreateTaskOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = try await createTaskBody(useOptions: false)
        let optionsBody = try await createTaskBody(useOptions: true)

        XCTAssertTrue(Self.jsonBodiesEqual(oldBody, optionsBody))
    }

    private func createTaskBody(useOptions: Bool) async throws -> Data {
        let mockData = #"{"task":{"taskId":"task-created"}}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )
        let schedule = GrokTaskSchedule(
            timezone: "Asia/Bangkok",
            timeOfDay: "09:30",
            dayOfYear: "2026-05-14"
        )
        let options = GrokTaskCreateOptions(
            name: "Task body",
            metadataJsonString: #"{"source":"test"}"#,
            schedule: schedule,
            notificationMethod: "EMAIL",
            modelMode: "BASE",
            notificationDeciderEnable: false,
            notificationDeciderGuideline: "notify for test",
            modelName: "grok-special",
            toolset: ["web", "x"]
        )

        if useOptions {
            _ = try await client.createTask(prompt: "prompt body", options: options)
        } else {
            _ = try await client.createTask(
                name: options.name,
                prompt: "prompt body",
                metadataJsonString: options.metadataJsonString,
                schedule: schedule,
                notificationMethod: options.notificationMethod,
                modelMode: options.modelMode,
                notificationDeciderEnable: options.notificationDeciderEnable,
                notificationDeciderGuideline: options.notificationDeciderGuideline,
                modelName: options.modelName,
                toolset: options.toolset
            )
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
