import XCTest
@testable import GrokClient

final class GrokClientFilesAudioTests: XCTestCase {
    func testSpeechToTextRequestUsesRootVoiceEndpoint() async throws {
        let responseData = #"{"text":"hello audio"}"#.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let response = try await client.speechToText(
            audioBase64: "YWJj",
            audioFormat: "webm",
            refinementLevel: "REFINEMENT_LEVEL_POLISH"
        )

        XCTAssertEqual(response.text, "hello audio")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/voice/speech-to-text")

        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["audioBase64"] as? String, "YWJj")
        XCTAssertEqual(json["audioFormat"] as? String, "webm")
        XCTAssertEqual(json["refinementLevel"] as? String, "REFINEMENT_LEVEL_POLISH")
        XCTAssertNil(json["message"])
        XCTAssertNil(json["modeId"])
        XCTAssertNil(json["fileName"])
    }

    func testSpeechToTextInfersSupportedFileExtensions() {
        XCTAssertEqual(GrokClient.inferAudioFormat(fromFileName: "voice.webm"), "webm")
        XCTAssertEqual(GrokClient.inferAudioFormat(fromFileName: "VOICE.WAV"), "wav")
        XCTAssertEqual(GrokClient.inferAudioFormat(fromFileName: "meeting.m4a"), "m4a")
        XCTAssertNil(GrokClient.inferAudioFormat(fromFileName: "voice.txt"))
    }

    func testSpeechToTextParsesResponseVariants() async throws {
        let variants: [(String, String)] = [
            (#"{"transcript":"top transcript"}"#, "top transcript"),
            (#"{"data":{"text":"nested data text"}}"#, "nested data text"),
            (#"{"result":{"text":"nested result text"}}"#, "nested result text"),
            (#"{"choices":[{"message":"array message"}]}"#, "array message")
        ]

        for (body, expectedText) in variants {
            let session = makeMockSession(data: Data(body.utf8), statusCode: 200)
            let client = try GrokClient(
                cookies: ["sso": "test-cookie"],
                baseURL: "https://example.test/rest",
                session: session
            )

            let response = try await client.speechToText(
                audioBase64: "YWJj",
                audioFormat: "webm"
            )

            XCTAssertEqual(response.text, expectedText)
        }
    }

    func testSpeechToTextThrowsWhenTranscriptMissing() async throws {
        let session = makeMockSession(data: Data(#"{"ok":true}"#.utf8), statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        do {
            _ = try await client.speechToText(audioBase64: "YWJj", audioFormat: "webm")
            XCTFail("Expected missing transcript to throw")
        } catch let error as GrokError {
            XCTAssertEqual(error, .apiError("Speech-to-text response did not include a transcript"))
        }
    }

    func testSpeechToTextThrowsForHTTPError() async throws {
        let session = makeMockSession(data: Data(#"{"error":"bad"}"#.utf8), statusCode: 500)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        do {
            _ = try await client.speechToText(audioBase64: "YWJj", audioFormat: "webm")
            XCTFail("Expected HTTP error to throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("500") || error.localizedDescription.contains("500"))
        }
    }

    func testSpeechToTextFilePathConvenienceEncodesAudioAndRequiresKnownFormat() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let audioURL = tempURL.appendingPathComponent("clip.wav")
        try Data("wav bytes".utf8).write(to: audioURL)
        let session = makeMockSession(data: Data(#"{"text":"from file"}"#.utf8), statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        let response = try await client.speechToText(at: audioURL.path)
        XCTAssertEqual(response.text, "from file")

        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["audioBase64"] as? String, Data("wav bytes".utf8).base64EncodedString())
        XCTAssertEqual(json["audioFormat"] as? String, "wav")

        let unknownURL = tempURL.appendingPathComponent("clip.bin")
        try Data("audio".utf8).write(to: unknownURL)
        do {
            _ = try await client.speechToText(at: unknownURL.path)
            XCTFail("Expected unknown extension to throw")
        } catch let error as GrokError {
            XCTAssertTrue(error.localizedDescription.contains("Could not infer audio format"))
        }
    }

    func testSpeechToTextOldSignatureAndOptionsBodyEquivalence() async throws {
        let oldBody = try await speechBody(useOptions: false)
        let optionsBody = try await speechBody(useOptions: true)

        XCTAssertTrue(Self.jsonBodiesEqual(oldBody, optionsBody))
    }

    func testUploadFileUsesAppChatUploadEndpointAndBody() async throws {
        let mockData = #"{"fileMetadataId":"file-123","fileName":"report.txt"}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.uploadFile(
            fileName: "report space/slash?and&unicode東京.txt",
            fileMimeType: "text/plain",
            contentBase64: "dGVzdA=="
        )

        XCTAssertEqual(response.uploadedFileId, "file-123")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/rest/app-chat/upload-file")
        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["fileName"] as? String, "report space/slash?and&unicode東京.txt")
        XCTAssertEqual(json["fileMimeType"] as? String, "text/plain")
        XCTAssertEqual(json["content"] as? String, "dGVzdA==")
    }

    func testListAssetsResponseEncodesQuerySpecialCharacters() async throws {
        let mockData = #"{"assets":[{"fileMetadataId":"file-1","fileName":"one.txt"}]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.listAssetsResponse(
            options: GrokAssetListOptions(
                pageSize: 11,
                orderBy: "ORDER BY / ? & 東京"
            )
        )

        XCTAssertEqual(response.assets.first?.resolvedId, "file-1")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/assets?pageSize=11&orderBy=ORDER%20BY%20/%20?%20%26%20%E6%9D%B1%E4%BA%AC"
        )
    }

    func testDeleteAssetEncodesAssetIdSpecialCharacters() async throws {
        let mockData = #"{"asset":{"fileMetadataId":"file-deleted"}}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        let response = try await client.deleteAsset(assetId: "asset space/slash?and&unicode東京")

        XCTAssertEqual(response.asset?.resolvedId, "file-deleted")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.test/rest/assets/asset%20space%2Fslash%3Fand%26unicode%E6%9D%B1%E4%BA%AC"
        )
    }

    func testListAssetsOldSignatureAndOptionsQueryEquivalence() async throws {
        let oldURL = try await listAssetsURL(useOptions: false)
        let optionsURL = try await listAssetsURL(useOptions: true)

        XCTAssertEqual(oldURL, optionsURL)
    }

    private func speechBody(useOptions: Bool) async throws -> Data {
        let responseData = #"{"text":"hello audio"}"#.data(using: .utf8)!
        let session = makeMockSession(data: responseData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["sso": "test-cookie"],
            baseURL: "https://example.test/rest",
            session: session
        )

        if useOptions {
            _ = try await client.speechToText(
                audioBase64: "YWJj",
                options: GrokSpeechToTextOptions(
                    audioFormat: "webm",
                    refinementLevel: "REFINEMENT_LEVEL_POLISH"
                )
            )
        } else {
            _ = try await client.speechToText(
                audioBase64: "YWJj",
                audioFormat: "webm",
                refinementLevel: "REFINEMENT_LEVEL_POLISH"
            )
        }

        return try XCTUnwrap(MockURLProtocol.lastRequestBody)
    }

    private func listAssetsURL(useOptions: Bool) async throws -> String {
        let mockData = #"{"assets":[]}"#.data(using: .utf8)!
        let mockSession = makeMockSession(data: mockData, statusCode: 200)
        let client = try GrokClient(
            cookies: ["x-anonuserid": "123"],
            baseURL: "https://example.test/rest",
            session: mockSession
        )

        if useOptions {
            _ = try await client.listAssetsResponse(options: GrokAssetListOptions(pageSize: 11, orderBy: "ORDER"))
        } else {
            _ = try await client.listAssetsResponse(pageSize: 11, orderBy: "ORDER")
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
