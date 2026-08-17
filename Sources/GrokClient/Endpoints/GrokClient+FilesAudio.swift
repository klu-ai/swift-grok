import Foundation

extension GrokClient {
    public static let defaultSpeechRefinementLevel = "REFINEMENT_LEVEL_POLISH"

    public static func inferAudioFormat(fromFileName fileName: String) -> String? {
        let ext = URL(fileURLWithPath: fileName)
            .pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !ext.isEmpty else {
            return nil
        }

        switch ext {
        case "webm", "wav", "mp3", "m4a", "ogg", "flac", "mp4", "mpeg", "mpga":
            return ext
        default:
            return nil
        }
    }

    public func speechToText(
        audioBase64: String,
        options: GrokSpeechToTextOptions
    ) async throws -> GrokSpeechToTextResponse {
        let trimmedAudioBase64 = audioBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAudioFormat = (options.audioFormat ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRefinementLevel = options.refinementLevel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAudioBase64.isEmpty else {
            throw GrokError.apiError("Audio input is empty")
        }

        guard !trimmedAudioFormat.isEmpty else {
            throw GrokError.apiError("Audio format is required")
        }

        guard !trimmedRefinementLevel.isEmpty else {
            throw GrokError.apiError("Speech refinement level is required")
        }

        let payload: [String: Any] = [
            "audioBase64": trimmedAudioBase64,
            "audioFormat": trimmedAudioFormat,
            "refinementLevel": trimmedRefinementLevel
        ]

        let request = try makeRequest(path: "/voice/speech-to-text", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        return try makeSpeechToTextResponse(from: json)
    }

    public func speechToText(
        audioBase64: String,
        audioFormat: String,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) async throws -> GrokSpeechToTextResponse {
        try await speechToText(
            audioBase64: audioBase64,
            options: GrokSpeechToTextOptions(
                audioFormat: audioFormat,
                refinementLevel: refinementLevel
            )
        )
    }

    public func speechToText(
        audioData: Data,
        options: GrokSpeechToTextOptions
    ) async throws -> GrokSpeechToTextResponse {
        guard !audioData.isEmpty else {
            throw GrokError.apiError("Audio input is empty")
        }

        return try await speechToText(
            audioBase64: audioData.base64EncodedString(),
            options: options
        )
    }

    public func speechToText(
        audioData: Data,
        audioFormat: String,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) async throws -> GrokSpeechToTextResponse {
        try await speechToText(
            audioData: audioData,
            options: GrokSpeechToTextOptions(
                audioFormat: audioFormat,
                refinementLevel: refinementLevel
            )
        )
    }

    public func speechToText(
        at path: String,
        options: GrokSpeechToTextOptions = GrokSpeechToTextOptions()
    ) async throws -> GrokSpeechToTextResponse {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        let data = try Data(contentsOf: fileURL)
        let resolvedFormat = options.audioFormat ?? GrokClient.inferAudioFormat(fromFileName: fileURL.lastPathComponent)

        guard let resolvedFormat else {
            throw GrokError.apiError("Could not infer audio format for \(fileURL.lastPathComponent). Pass an explicit audio format.")
        }

        return try await speechToText(
            audioData: data,
            options: GrokSpeechToTextOptions(
                audioFormat: resolvedFormat,
                refinementLevel: options.refinementLevel
            )
        )
    }

    public func speechToText(
        at path: String,
        audioFormat: String? = nil,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) async throws -> GrokSpeechToTextResponse {
        try await speechToText(
            at: path,
            options: GrokSpeechToTextOptions(
                audioFormat: audioFormat,
                refinementLevel: refinementLevel
            )
        )
    }

    public func uploadFile(
        fileName: String,
        fileMimeType: String,
        contentBase64: String
    ) async throws -> GrokFileUploadResponse {
        let payload: [String: Any] = [
            "fileName": fileName,
            "fileMimeType": fileMimeType,
            "content": contentBase64
        ]

        let request = try makeRequest(path: "/upload-file", payload: payload)
        let json = try await jsonObject(for: request)
        return makeResourceFileUploadResponse(from: json)
    }

    public func uploadFile(at path: String, mimeType: String? = nil) async throws -> GrokFileUploadResponse {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        let data = try Data(contentsOf: fileURL)
        let resolvedMimeType = mimeType ?? "application/octet-stream"

        return try await uploadFile(
            fileName: fileURL.lastPathComponent,
            fileMimeType: resolvedMimeType,
            contentBase64: data.base64EncodedString()
        )
    }

    public func listAssetsResponse(
        options: GrokAssetListOptions = GrokAssetListOptions()
    ) async throws -> GrokAssetsResponse {
        let path = try endpointPath(
            ["assets"],
            queryItems: [
                URLQueryItem(name: "pageSize", value: String(options.pageSize)),
                URLQueryItem(name: "orderBy", value: options.orderBy)
            ]
        )
        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        let assets = JSONLookup(json)
            .dictionaries(["assets", "data", "result", "items"])
            .map { makeResourceAsset(from: $0) }

        return GrokAssetsResponse(assets: assets, rawJSON: AnyCodable(json))
    }

    public func listAssetsResponse(
        pageSize: Int = 9,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> GrokAssetsResponse {
        try await listAssetsResponse(options: GrokAssetListOptions(pageSize: pageSize, orderBy: orderBy))
    }

    public func listAssets(
        options: GrokAssetListOptions = GrokAssetListOptions()
    ) async throws -> [GrokAsset] {
        try await listAssetsResponse(options: options).assets
    }

    public func listAssets(
        pageSize: Int = 9,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) async throws -> [GrokAsset] {
        try await listAssets(options: GrokAssetListOptions(pageSize: pageSize, orderBy: orderBy))
    }

    public func deleteAsset(assetId: String) async throws -> GrokFileMutationResponse {
        let request = try makeRequest(
            path: try endpointPath(["assets", assetId], queryItems: []),
            method: "DELETE",
            namespace: .root
        )
        let json = try await jsonObject(for: request)
        let asset = firstAssetMutationDictionary(from: json)
            .map { makeResourceAsset(from: $0) }
        return GrokFileMutationResponse(asset: asset, rawJSON: AnyCodable(json))
    }

    private func makeSpeechToTextResponse(from json: Any) throws -> GrokSpeechToTextResponse {
        if let text = JSONLookup(json).firstString("text", "transcript", "message") {
            return GrokSpeechToTextResponse(text: text, rawJSON: AnyCodable(json))
        }

        throw GrokError.apiError("Speech-to-text response did not include a transcript")
    }

    private func firstAssetMutationDictionary(from json: Any) -> [String: AnyCodable]? {
        JSONLookup(json).firstDictionary(["asset", "file", "data", "result"]) ??
            JSONLookup(json).rawAnyCodable.value as? [String: AnyCodable]
    }
}
