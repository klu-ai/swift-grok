import XCTest
@testable import GrokCLI

final class AudioRecordingDeviceTests: XCTestCase {
    func testAVFoundationDefaultDeviceSpecifierRejectsNamesFFmpegParsesAsIndexes() {
        XCTAssertEqual(
            GrokCLI.avFoundationSpecifierForDefaultAudioDeviceName("MacBook Pro Microphone"),
            "MacBook Pro Microphone"
        )
        XCTAssertNil(GrokCLI.avFoundationSpecifierForDefaultAudioDeviceName("009 AirMax"))
        XCTAssertNil(GrokCLI.avFoundationSpecifierForDefaultAudioDeviceName("1MORE Headset"))
        XCTAssertNil(GrokCLI.avFoundationSpecifierForDefaultAudioDeviceName("Built-in: Microphone"))
        XCTAssertNil(GrokCLI.avFoundationSpecifierForDefaultAudioDeviceName("   "))
    }

    func testAVFoundationAudioInputArgumentUsesAudioOnlySpecifier() {
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: "MacBook Pro Microphone"), ":MacBook Pro Microphone")
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: "1"), ":1")
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: ":1"), ":1")
        XCTAssertEqual(GrokCLI.avFoundationAudioInputArgument(for: "   "), ":default")
    }
}
