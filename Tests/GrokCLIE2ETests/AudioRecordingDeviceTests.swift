import XCTest
@testable import GrokCLI

final class AudioRecordingDeviceTests: XCTestCase {
    func testAVFoundationAudioInputArgumentUsesAudioOnlySpecifier() {
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: "MacBook Pro Microphone"), ":MacBook Pro Microphone")
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: "1"), ":1")
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: ":1"), ":1")
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: "   "), ":default")
    }
}
