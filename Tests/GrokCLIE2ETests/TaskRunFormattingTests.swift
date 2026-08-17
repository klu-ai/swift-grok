import XCTest
import GrokClient
@testable import GrokCLI

final class TaskRunFormattingTests: XCTestCase {
    func testTaskRunTimestampLabelFormatsRecentDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-14T12:00:00Z"))

        XCTAssertEqual(
            GrokCLI.taskRunTimestampLabel("2026-05-14T08:30:00Z", now: now, calendar: calendar),
            "Today (2026-05-14 08:30)"
        )
        XCTAssertEqual(
            GrokCLI.taskRunTimestampLabel("2026-05-13T08:30:00Z", now: now, calendar: calendar),
            "Yesterday (2026-05-13 08:30)"
        )
        XCTAssertEqual(
            GrokCLI.taskRunTimestampLabel("2026-05-07T08:30:00Z", now: now, calendar: calendar),
            "Last week (2026-05-07 08:30)"
        )
        XCTAssertEqual(
            GrokCLI.taskRunTimestampLabel("2026-05-01T08:30:00Z", now: now, calendar: calendar),
            "May 1 (2026-05-01 08:30)"
        )
    }

    func testTaskRunTimestampLabelFallsBackToRawValue() {
        XCTAssertEqual(GrokCLI.taskRunTimestampLabel("not-a-date"), "not-a-date")
        XCTAssertNil(GrokCLI.taskRunTimestampLabel(nil))
    }

    func testTaskStatusShowsPausedWhenScheduleIsDisabled() {
        let pausedTask = GrokTask(
            taskId: "task-paused",
            name: "Paused task",
            isEnabled: true,
            status: "enabled",
            rawJSON: [
                "taskId": AnyCodable("task-paused"),
                "isEnabled": AnyCodable(true),
                "status": AnyCodable("enabled"),
                "scheduleIsEnabled": AnyCodable(false)
            ]
        )
        let archivedTask = GrokTask(
            taskId: "task-archived",
            name: "Archived task",
            isEnabled: false,
            status: "archived",
            rawJSON: [
                "taskId": AnyCodable("task-archived"),
                "isEnabled": AnyCodable(false),
                "status": AnyCodable("archived"),
                "scheduleIsEnabled": AnyCodable(false)
            ]
        )

        XCTAssertEqual(GrokCLI.taskStatus(pausedTask), "paused")
        XCTAssertEqual(GrokCLI.taskStatus(archivedTask), "archived")
    }
}
