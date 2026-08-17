import XCTest
@testable import GrokClient

final class GrokClientFactoryTests: XCTestCase {
    func testResourceFactoriesAcceptSnakeCaseAndAssetUploadWrappers() throws {
        let skill = GrokResourceParsers.makeSkill(from: [
            "skill_id": "skill-1",
            "title": "Research"
        ])
        XCTAssertEqual(skill.skillId, "skill-1")
        XCTAssertEqual(skill.title, "Research")

        let workspace = GrokResourceParsers.makeWorkspace(from: [
            "workspace_id": "workspace-1",
            "custom_personality": "Be terse",
            "preferred_model": "fast"
        ])
        XCTAssertEqual(workspace.workspaceId, "workspace-1")
        XCTAssertEqual(workspace.customPersonality, "Be terse")
        XCTAssertEqual(workspace.preferredModel, "fast")

        let upload = GrokResourceParsers.makeFileUploadResponse(from: [
            "asset": [
                "file_metadata_id": "file-meta-1",
                "file_name": "notes.pdf",
                "mime_type": "application/pdf"
            ]
        ])

        XCTAssertEqual(upload.uploadedFileId, "file-meta-1")
        XCTAssertEqual(upload.asset?.fileName, "notes.pdf")
        XCTAssertEqual(upload.asset?.mimeType, "application/pdf")
    }

    func testModeFactoryTraversesWrappersDeduplicatesAndParsesAvailability() {
        let modes = GrokModeParser.modes(from: [
            "modes": [
                [
                    "mode_id": "fast",
                    "display_name": "Fast",
                    "availability": ["available": true]
                ],
                [
                    "id": "fast",
                    "displayName": "Duplicate Fast"
                ],
                [
                    "modelId": "heavy",
                    "label": "Heavy",
                    "availability": [
                        "requires_upgrade": [
                            "message": "Upgrade required",
                            "minimum_subscription_tier": "TIER_SUPERGROK_HEAVY"
                        ]
                    ]
                ]
            ]
        ])

        XCTAssertEqual(modes.map(\.id), ["fast", "heavy"])
        XCTAssertEqual(modes[0].displayName, "Fast")
        XCTAssertTrue(modes[0].isAvailable)
        XCTAssertEqual(modes[1].displayName, "Heavy")
        XCTAssertFalse(modes[1].isAvailable)
        XCTAssertEqual(modes[1].unavailableReason, "Upgrade required")
        XCTAssertEqual(modes[1].minimumSubscriptionTier, "TIER_SUPERGROK_HEAVY")
    }

    func testTaskFactoryTraversesWrappersAndCopiesScheduleFields() {
        let response = GrokTaskParser.makeTasksResponse(from: [
            "tasks": [
                [
                    "task": [
                        "task_id": "scheduled-1",
                        "title": "Morning brief",
                        "query": "Summarize overnight news"
                    ],
                    "schedule": [
                        "isEnabled": true,
                        "timeOfDay": "08:00",
                        "timezone": "America/New_York",
                        "dayOfYear": "2026-05-14"
                    ]
                ]
            ]
        ])

        XCTAssertEqual(response.tasks.map(\.resolvedId), ["scheduled-1"])
        XCTAssertEqual(response.tasks.first?.name, "Morning brief")
        XCTAssertEqual(response.tasks.first?.prompt, "Summarize overnight news")
        XCTAssertEqual(response.tasks.first?.isEnabled, true)
        XCTAssertEqual(response.tasks.first?.rawJSON["timeOfDay"]?.value as? String, "08:00")
        XCTAssertEqual(response.tasks.first?.rawJSON["timezone"]?.value as? String, "America/New_York")
    }

    func testTaskFactoryCollectsActiveAndInactiveWrapperBuckets() {
        let response = GrokTaskParser.makeTasksResponse(from: [
            "payload": [
                "activeTasks": [
                    [
                        "task": [
                            "task_id": "active-1",
                            "title": "Morning brief",
                            "query": "Summarize overnight news"
                        ]
                    ]
                ],
                "archived_tasks": [
                    [
                        "task": [
                            "id": "inactive-1",
                            "display_name": "Old brief",
                            "instructions": "Old prompt"
                        ]
                    ]
                ]
            ]
        ])

        XCTAssertEqual(response.tasks.map(\.resolvedId), ["active-1", "inactive-1"])
        XCTAssertEqual(response.activeTasks.first?.name, "Morning brief")
        XCTAssertEqual(response.activeTasks.first?.prompt, "Summarize overnight news")
        XCTAssertEqual(response.activeTasks.first?.isEnabled, true)
        XCTAssertEqual(response.inactiveTasks.first?.name, "Old brief")
        XCTAssertEqual(response.inactiveTasks.first?.prompt, "Old prompt")
        XCTAssertEqual(response.inactiveTasks.first?.isEnabled, false)
    }

    func testTaskResultFactoryFindsNestedModelResponseMessage() {
        let response = GrokTaskParser.makeTaskResultsResponse(from: [
            "result": [
                "latestResult": [
                    "taskResultId": "result-1",
                    "taskId": "task-1",
                    "modelResponse": [
                        "message": "Done"
                    ],
                    "state": "complete"
                ]
            ]
        ])

        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.resultId, "result-1")
        XCTAssertEqual(response.results.first?.taskId, "task-1")
        XCTAssertEqual(response.results.first?.message, "Done")
        XCTAssertEqual(response.results.first?.status, "complete")
    }

    func testSubscriptionFactoryFindsCurrentNestedPlan() {
        let response = GrokAccountParser.makeSubscriptionsResponse(from: [
            "data": [
                "subscriptions": [
                    [
                        "subscription_tier": "TIER_FREE",
                        "subscription_status": "canceled"
                    ],
                    [
                        "planName": "SuperGrok Heavy",
                        "tier": "TIER_SUPERGROK_HEAVY",
                        "status": "active"
                    ]
                ]
            ]
        ])

        XCTAssertEqual(response.subscriptions.count, 2)
        XCTAssertEqual(response.currentSubscription?.tier, "TIER_SUPERGROK_HEAVY")
        XCTAssertEqual(response.currentSubscription?.displayName, "SuperGrok Heavy")
        XCTAssertEqual(response.currentSubscription?.isActive, true)
    }

    func testRateLimitFactoryPrefersRequestedModelAndParsesWindows() {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let response = GrokRateLimitParser.makeRateLimitResponse(
            from: [
                "data": [
                    "rateLimits": [
                        [
                            "modelName": "other",
                            "remainingResponses": 99,
                            "resetAfterSeconds": 60
                        ],
                        [
                            "modelName": "fast",
                            "responsesRemaining": "8",
                            "resetIn": "1h 30m",
                            "window": "2h"
                        ]
                    ]
                ]
            ],
            requestedModelName: "fast",
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(response.modelName, "fast")
        XCTAssertEqual(response.remainingResponses, 8)
        XCTAssertEqual(response.resetAfterSeconds, 5_400)
        XCTAssertEqual(response.windowSeconds, 7_200)
    }
}
