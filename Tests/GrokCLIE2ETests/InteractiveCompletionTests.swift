import XCTest
@testable import GrokCLI

final class InteractiveCompletionTests: XCTestCase {
    func testBareSlashMenuPrioritizesModelAndHidesAdvancedCommandsUntilTyped() {
        let reader = InputReader()

        let bareSuggestions = reader.completionSuggestionDisplays(for: "/")
        XCTAssertEqual(bareSuggestions.first, "/model")
        XCTAssertTrue(bareSuggestions.contains("/limits"))
        XCTAssertTrue(bareSuggestions.contains("/oauth"))
        XCTAssertTrue(bareSuggestions.contains("/search"))
        XCTAssertFalse(bareSuggestions.contains("/stream"))
        XCTAssertFalse(bareSuggestions.contains("/special"))

        XCTAssertTrue(reader.completionSuggestionDisplays(for: "/oa").contains("/oauth"))
        XCTAssertTrue(reader.completionSuggestionDisplays(for: "/sea").contains("/search"))
        XCTAssertTrue(reader.completionSuggestionDisplays(for: "/str").contains("/stream"))
        XCTAssertFalse(reader.completionSuggestionDisplays(for: "/spe").contains("/special"))
    }

    func testRemoteTypeaheadSuggestionsAreUsedForFreeTextOnly() {
        let reader = InputReader(typeaheadSuggestionsProvider: { buffer in
            guard buffer == "test" else { return [] }
            return [
                InputTypeaheadSuggestion(display: "test driven development"),
                InputTypeaheadSuggestion(display: "testing swift")
            ]
        })

        XCTAssertEqual(reader.completionSuggestionDisplays(for: "test"), [
            "test driven development",
            "testing swift"
        ])
        XCTAssertFalse(reader.completionSuggestionDisplays(for: "/").contains("test driven development"))
    }

    func testBareSpecialCommandIsDisabled() {
        XCTAssertNil(GrokCLI.interactiveCommand(from: "special"))
        XCTAssertNil(GrokCLI.interactiveCommand(from: "special now"))
    }

    func testBareLimitsCommandIsRecognizedExactly() {
        let command = GrokCLI.interactiveCommand(from: "limits")

        XCTAssertEqual(command?.name, "limits")
        XCTAssertFalse(command?.hasSlash ?? true)
        XCTAssertNil(GrokCLI.interactiveCommand(from: "limits now"))
    }

    func testOAuthSlashCommandIsRecognizedOnlyWithSlash() {
        XCTAssertEqual(GrokCLI.interactiveCommand(from: "/oauth")?.name, "oauth")
        XCTAssertEqual(GrokCLI.interactiveCommand(from: "/oauth status")?.remainder, "status")
        XCTAssertNil(GrokCLI.interactiveCommand(from: "oauth"))
    }
}
