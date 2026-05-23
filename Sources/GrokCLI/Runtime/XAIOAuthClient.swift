import Foundation
import GrokClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct XAIOAuthCredential: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let tokenType: String
    let scope: String?
    let expiresAt: Date
    let obtainedAt: Date
    let issuer: String
    let tokenEndpoint: String
    let deviceAuthorizationEndpoint: String?
    let apiBaseURL: String

    var expiresSoon: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var bearerToken: String {
        "\(tokenType) \(accessToken)"
    }
}

struct XAIDeviceAuthorization {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int
}

struct XAIOAuthVerificationResult {
    let credential: XAIOAuthCredential
    let credentialPath: String
    let models: [String]
    let testResponseID: String?
    let testResponseText: String?
}

private struct XAIOAuthDiscovery: Decodable {
    let issuer: String
    let authorizationEndpoint: String?
    let tokenEndpoint: String
    let deviceAuthorizationEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case deviceAuthorizationEndpoint = "device_authorization_endpoint"
    }
}

private struct XAIDeviceAuthorizationResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct XAITokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

private struct XAIOAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct XAIModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct XAIResponseCreateResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let text: String?
            let type: String?
        }

        let content: [ContentItem]?
        let text: String?
    }

    let id: String
    let output: [OutputItem]?
    let outputText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case output
        case outputText = "output_text"
    }

    var flattenedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let pieces = output?.flatMap { item -> [String] in
            var values: [String] = []
            if let text = item.text, !text.isEmpty {
                values.append(text)
            }
            values.append(contentsOf: item.content?.compactMap(\.text).filter { !$0.isEmpty } ?? [])
            return values
        } ?? []

        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }
}

final class XAIOAuthClient {
    private static let defaultDiscoveryURL = "https://auth.x.ai/.well-known/openid-configuration"
    private static let defaultAPIBaseURL = "https://api.x.ai/v1"
    private static let defaultClientID = "b1a00492-073a-47ea-816f-4c329264a828"
    private static let defaultScope = "openid profile email offline_access grok-cli:access api:access"
    private static let deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"

    private let session: URLSession
    private let discoveryURL: URL
    private let apiBaseURL: URL
    private let clientID: String
    private let scope: String
    private let allowsLocalEndpoints: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment, session: URLSession = .shared) throws {
        self.session = session
        self.clientID = environment["GROK_XAI_OAUTH_CLIENT_ID"]?.trimmedNonEmpty ?? Self.defaultClientID
        self.scope = environment["GROK_XAI_OAUTH_SCOPE"]?.trimmedNonEmpty ?? Self.defaultScope
        self.allowsLocalEndpoints = environment["GROK_XAI_OAUTH_ALLOW_LOCAL"] == "1" ||
            environment["GROK_XAI_OAUTH_DISCOVERY_URL"] != nil ||
            environment["GROK_XAI_API_BASE_URL"] != nil

        let discovery = environment["GROK_XAI_OAUTH_DISCOVERY_URL"]?.trimmedNonEmpty ?? Self.defaultDiscoveryURL
        self.discoveryURL = try Self.validatedEndpointURL(
            discovery,
            name: "xAI OAuth discovery URL",
            allowLocal: allowsLocalEndpoints
        )

        let apiBase = environment["GROK_XAI_API_BASE_URL"]?.trimmedNonEmpty ?? Self.defaultAPIBaseURL
        self.apiBaseURL = try Self.validatedEndpointURL(
            apiBase,
            name: "xAI API base URL",
            allowLocal: allowsLocalEndpoints
        )
    }

    func authenticateWithDeviceCode(onDeviceCode: (XAIDeviceAuthorization) -> Void) async throws -> XAIOAuthCredential {
        let discovery = try await fetchDiscovery()
        guard let deviceEndpoint = discovery.deviceAuthorizationEndpoint?.trimmedNonEmpty else {
            throw GrokError.apiError("xAI OAuth discovery did not include a device authorization endpoint")
        }

        let deviceURL = try Self.validatedEndpointURL(
            deviceEndpoint,
            name: "xAI OAuth device endpoint",
            allowLocal: allowsLocalEndpoints
        )
        let deviceAuthorization = try await requestDeviceAuthorization(deviceURL: deviceURL)
        onDeviceCode(deviceAuthorization)

        let tokenResponse = try await pollForToken(
            tokenURL: try tokenURL(from: discovery),
            deviceCode: deviceAuthorization.deviceCode,
            interval: deviceAuthorization.interval,
            expiresIn: deviceAuthorization.expiresIn
        )

        return try credential(from: tokenResponse, discovery: discovery)
    }

    func refresh(_ credential: XAIOAuthCredential) async throws -> XAIOAuthCredential {
        guard let refreshToken = credential.refreshToken?.trimmedNonEmpty else {
            throw GrokError.apiError("Saved xAI OAuth credential has expired and does not include a refresh token")
        }

        let tokenURL = try Self.validatedEndpointURL(
            credential.tokenEndpoint,
            name: "xAI OAuth token endpoint",
            allowLocal: allowsLocalEndpoints
        )
        let response = try await performTokenRequest(
            tokenURL: tokenURL,
            fields: [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", clientID)
            ]
        )

        return XAIOAuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? credential.refreshToken,
            idToken: response.idToken ?? credential.idToken,
            tokenType: response.tokenType ?? credential.tokenType,
            scope: response.scope ?? credential.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 21_600)),
            obtainedAt: Date(),
            issuer: credential.issuer,
            tokenEndpoint: credential.tokenEndpoint,
            deviceAuthorizationEndpoint: credential.deviceAuthorizationEndpoint,
            apiBaseURL: credential.apiBaseURL
        )
    }

    func listModels(using credential: XAIOAuthCredential) async throws -> [String] {
        let url = apiBaseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            return try JSONDecoder().decode(XAIModelsResponse.self, from: data).data.map(\.id)
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    func createTinyResponse(using credential: XAIOAuthCredential) async throws -> (id: String, text: String?) {
        try await createResponse(
            using: credential,
            modelID: "grok-4.3",
            message: "Reply with exactly: oauth-ok",
            previousResponseID: nil,
            store: false,
            fileAttachmentIDs: [],
            maxOutputTokens: 16
        )
    }

    func createResponse(
        using credential: XAIOAuthCredential,
        modelID: String,
        message: String,
        previousResponseID: String?,
        store: Bool,
        fileAttachmentIDs: [String],
        maxOutputTokens: Int? = nil
    ) async throws -> (id: String, text: String?) {
        let data = try await performJSONRequest(
            path: "responses",
            method: "POST",
            credential: credential,
            body: responseRequestBody(
                modelID: modelID,
                message: message,
                previousResponseID: previousResponseID,
                store: store,
                fileAttachmentIDs: fileAttachmentIDs,
                maxOutputTokens: maxOutputTokens,
                stream: false
            )
        )

        do {
            let decoded = try JSONDecoder().decode(XAIResponseCreateResponse.self, from: data)
            return (decoded.id, decoded.flattenedText)
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    func streamResponse(
        using credential: XAIOAuthCredential,
        modelID: String,
        message: String,
        previousResponseID: String?,
        store: Bool,
        fileAttachmentIDs: [String]
    ) throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let request = try jsonRequest(
            path: "responses",
            method: "POST",
            credential: credential,
            body: responseRequestBody(
                modelID: modelID,
                message: message,
                previousResponseID: previousResponseID,
                store: store,
                fileAttachmentIDs: fileAttachmentIDs,
                maxOutputTokens: nil,
                stream: true
            )
        )
        let lines = streamingLines(for: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = XAIOAuthResponsesStreamParser()
                    for try await line in lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        if let response = try parser.consume(line: line) {
                            continuation.yield(response)
                            if response.isFinal {
                                continuation.finish()
                                return
                            }
                        }
                    }

                    if let finalResponse = parser.finish() {
                        continuation.yield(finalResponse)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func transcribeAudio(
        using credential: XAIOAuthCredential,
        audioData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> GrokSpeechToTextResponse {
        let data = try await performMultipartRequest(
            path: "stt",
            credential: credential,
            fields: [],
            fileFieldName: "file",
            fileName: fileName,
            fileMimeType: mimeType,
            fileData: audioData
        )
        let json = try Self.jsonObject(from: data)
        guard let text = json["text"] as? String, !text.isEmpty else {
            throw GrokError.apiError("xAI speech-to-text response did not include a transcript")
        }
        return GrokSpeechToTextResponse(text: text, rawJSON: AnyCodable(json))
    }

    func uploadFile(
        using credential: XAIOAuthCredential,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> GrokFileUploadResponse {
        let data = try await performMultipartRequest(
            path: "files",
            credential: credential,
            fields: [("purpose", "assistants")],
            fileFieldName: "file",
            fileName: fileName,
            fileMimeType: mimeType,
            fileData: fileData
        )
        let json = try Self.jsonObject(from: data)
        let asset = Self.asset(from: json)
        return GrokFileUploadResponse(
            fileId: json["id"] as? String,
            id: json["id"] as? String,
            fileName: json["filename"] as? String ?? json["fileName"] as? String,
            asset: asset,
            rawJSON: AnyCodable(json)
        )
    }

    func listFiles(using credential: XAIOAuthCredential, pageSize: Int) async throws -> GrokAssetsResponse {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(pageSize))]
        guard let url = components?.url else {
            throw GrokError.apiError("Invalid xAI files URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let json = try Self.jsonObject(from: data)
        let dataArray = json["data"] as? [[String: Any]] ?? []
        return GrokAssetsResponse(
            assets: dataArray.map(Self.asset),
            rawJSON: AnyCodable(json)
        )
    }

    func deleteFile(using credential: XAIOAuthCredential, fileID: String) async throws -> GrokFileMutationResponse {
        let data = try await performJSONRequest(
            path: "files/\(Self.percentEncodedPathComponent(fileID))",
            method: "DELETE",
            credential: credential,
            body: nil
        )
        let json = try Self.jsonObject(from: data)
        return GrokFileMutationResponse(
            asset: GrokAsset(
                fileId: json["id"] as? String,
                id: json["id"] as? String,
                rawJSON: json.mapValues(AnyCodable.init)
            ),
            rawJSON: AnyCodable(json)
        )
    }

    private func responseRequestBody(
        modelID: String,
        message: String,
        previousResponseID: String?,
        store: Bool,
        fileAttachmentIDs: [String],
        maxOutputTokens: Int?,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelID,
            "input": responseInput(message: message, fileAttachmentIDs: fileAttachmentIDs),
            "store": store
        ]
        if let previousResponseID, !previousResponseID.isEmpty {
            body["previous_response_id"] = previousResponseID
        }
        if let maxOutputTokens {
            body["max_output_tokens"] = maxOutputTokens
        }
        if stream {
            body["stream"] = true
        }
        return body
    }

    private func responseInput(message: String, fileAttachmentIDs: [String]) -> Any {
        let trimmedIDs = fileAttachmentIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let content: Any
        if trimmedIDs.isEmpty {
            content = message
        } else {
            var items: [[String: Any]] = [
                ["type": "input_text", "text": message]
            ]
            items.append(contentsOf: trimmedIDs.map { fileID in
                ["type": "input_file", "file_id": fileID]
            })
            content = items
        }

        return [
            [
                "role": "user",
                "content": content
            ]
        ]
    }

    private func performJSONRequest(
        path: String,
        method: String,
        credential: XAIOAuthCredential,
        body: [String: Any]?
    ) async throws -> Data {
        let request = try jsonRequest(
            path: path,
            method: method,
            credential: credential,
            body: body
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func jsonRequest(
        path: String,
        method: String,
        credential: XAIOAuthCredential,
        body: [String: Any]?
    ) throws -> URLRequest {
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credential.bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func streamingLines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let delegate = XAIOAuthStreamingLineDelegate(
                continuation: continuation,
                validateResponse: { response, data in
                    try self.validate(response: response, data: data ?? Data())
                }
            )
            let streamingSession = URLSession(
                configuration: session.configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            delegate.start(request: request, session: streamingSession)

            continuation.onTermination = { _ in
                delegate.cancel()
            }
        }
    }

    private func performMultipartRequest(
        path: String,
        credential: XAIOAuthCredential,
        fields: [(String, String)],
        fileFieldName: String,
        fileName: String,
        fileMimeType: String,
        fileData: Data
    ) async throws -> Data {
        let boundary = "grok-xai-\(UUID().uuidString)"
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credential.bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: fields,
            fileFieldName: fileFieldName,
            fileName: fileName,
            fileMimeType: fileMimeType,
            fileData: fileData
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private static func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileFieldName: String,
        fileName: String,
        fileMimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(fileMimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected JSON object"))
            )
        }
        return json
    }

    private static func asset(from json: [String: Any]) -> GrokAsset {
        GrokAsset(
            fileId: json["id"] as? String ?? json["file_id"] as? String,
            id: json["id"] as? String,
            fileName: json["filename"] as? String ?? json["fileName"] as? String,
            name: json["filename"] as? String ?? json["name"] as? String,
            mimeType: json["mime_type"] as? String ?? json["mimeType"] as? String,
            rawJSON: json.mapValues(AnyCodable.init)
        )
    }

    private static func percentEncodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func fetchDiscovery() async throws -> XAIOAuthDiscovery {
        var request = URLRequest(url: discoveryURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            let discovery = try JSONDecoder().decode(XAIOAuthDiscovery.self, from: data)
            _ = try tokenURL(from: discovery)
            return discovery
        } catch let error as GrokError {
            throw error
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    private func requestDeviceAuthorization(deviceURL: URL) async throws -> XAIDeviceAuthorization {
        var request = URLRequest(url: deviceURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody([
            ("client_id", clientID),
            ("scope", scope)
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(XAIDeviceAuthorizationResponse.self, from: data)
            return XAIDeviceAuthorization(
                deviceCode: decoded.deviceCode,
                userCode: decoded.userCode,
                verificationURI: decoded.verificationURI,
                verificationURIComplete: decoded.verificationURIComplete,
                expiresIn: decoded.expiresIn,
                interval: max(1, decoded.interval ?? 5)
            )
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    private func pollForToken(
        tokenURL: URL,
        deviceCode: String,
        interval initialInterval: Int,
        expiresIn: Int
    ) async throws -> XAITokenResponse {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var interval = max(1, initialInterval)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)

            do {
                return try await performTokenRequest(
                    tokenURL: tokenURL,
                    fields: [
                        ("grant_type", Self.deviceGrantType),
                        ("device_code", deviceCode),
                        ("client_id", clientID)
                    ]
                )
            } catch let error as XAIOAuthPollingError {
                switch error.kind {
                case "authorization_pending":
                    continue
                case "slow_down":
                    interval += 5
                    continue
                case "expired_token":
                    throw GrokError.apiError("xAI OAuth device code expired; run `grok auth oauth` again")
                case "access_denied", "authorization_denied":
                    throw GrokError.apiError("xAI OAuth authorization was denied")
                default:
                    throw GrokError.apiError(error.message)
                }
            }
        }

        throw GrokError.apiError("xAI OAuth device code expired; run `grok auth oauth` again")
    }

    private func performTokenRequest(tokenURL: URL, fields: [(String, String)]) async throws -> XAITokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(fields)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if let oauthError = try? JSONDecoder().decode(XAIOAuthErrorResponse.self, from: data) {
                throw XAIOAuthPollingError(
                    kind: oauthError.error,
                    message: oauthError.errorDescription ?? oauthError.error
                )
            }
            try validate(response: response, data: data)
        }

        do {
            return try JSONDecoder().decode(XAITokenResponse.self, from: data)
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    private func credential(from response: XAITokenResponse, discovery: XAIOAuthDiscovery) throws -> XAIOAuthCredential {
        let tokenURL = try tokenURL(from: discovery)
        return XAIOAuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            idToken: response.idToken,
            tokenType: response.tokenType ?? "Bearer",
            scope: response.scope ?? scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 21_600)),
            obtainedAt: Date(),
            issuer: discovery.issuer,
            tokenEndpoint: tokenURL.absoluteString,
            deviceAuthorizationEndpoint: discovery.deviceAuthorizationEndpoint,
            apiBaseURL: apiBaseURL.absoluteString
        )
    }

    private func tokenURL(from discovery: XAIOAuthDiscovery) throws -> URL {
        guard let tokenEndpoint = discovery.tokenEndpoint.trimmedNonEmpty else {
            throw GrokError.apiError("xAI OAuth discovery did not include a token endpoint")
        }
        return try Self.validatedEndpointURL(
            tokenEndpoint,
            name: "xAI OAuth token endpoint",
            allowLocal: allowsLocalEndpoints
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(NSError(
                domain: "GrokCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "xAI OAuth request did not return an HTTP response"]
            ))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let suffix = body.isEmpty ? "" : ": \(body)"
            throw GrokError.apiError("xAI API returned HTTP \(httpResponse.statusCode)\(suffix)")
        }
    }

    private static func validatedEndpointURL(_ value: String, name: String, allowLocal: Bool) throws -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            throw GrokError.apiError("\(name) is not a valid URL")
        }

        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        let validScheme = scheme == "https" || (allowLocal && isLocal && scheme == "http")
        let validHost = host == "x.ai" || host.hasSuffix(".x.ai") || (allowLocal && isLocal)

        guard validScheme, validHost else {
            throw GrokError.apiError("\(name) must use HTTPS on x.ai endpoints")
        }

        return url
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        fields
            .map { "\(formEncode($0.0))=\(formEncode($0.1))" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }
}

private struct XAIOAuthPollingError: LocalizedError {
    let kind: String
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct XAIOAuthStreamingLineReader {
    private var buffer = Data()
    private var consumedOffset = 0
    private var searchOffset = 0
    private let maxBufferedBytes = 1_048_576
    private let compactionThreshold = 65_536

    mutating func append(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var lines: [Data] = []
        while searchOffset < buffer.count,
              let newlineIndex = buffer[searchOffset...].firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Data(buffer[consumedOffset..<newlineIndex]))
            consumedOffset = buffer.index(after: newlineIndex)
            searchOffset = consumedOffset
        }

        compactIfNeeded()
        try validatePendingByteCount()
        return lines
    }

    mutating func flushPartialLine() -> Data? {
        guard consumedOffset < buffer.count else {
            reset()
            return nil
        }

        let line = Data(buffer[consumedOffset...])
        reset()
        return line
    }

    private mutating func compactIfNeeded() {
        guard consumedOffset > 0 else { return }
        guard consumedOffset >= compactionThreshold || consumedOffset > buffer.count / 2 else { return }

        buffer = Data(buffer[consumedOffset...])
        searchOffset -= consumedOffset
        consumedOffset = 0
    }

    private func validatePendingByteCount() throws {
        guard buffer.count - consumedOffset <= maxBufferedBytes else {
            throw GrokError.streamingError
        }
    }

    private mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
        consumedOffset = 0
        searchOffset = 0
    }
}

private final class XAIOAuthStreamingLineDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let validateResponse: (URLResponse, Data?) throws -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var isErrorResponse = false
    private var errorData = Data()
    private var lineReader = XAIOAuthStreamingLineReader()

    init(
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        validateResponse: @escaping (URLResponse, Data?) throws -> Void
    ) {
        self.continuation = continuation
        self.validateResponse = validateResponse
    }

    func start(request: URLRequest, session: URLSession) {
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        if let httpResponse = response as? HTTPURLResponse {
            isErrorResponse = !(200...299).contains(httpResponse.statusCode)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isErrorResponse {
            appendErrorData(data)
            return
        }

        do {
            for lineData in try lineReader.append(data) {
                try yieldLine(lineData)
            }
        } catch {
            continuation.finish(throwing: error)
            cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer { cancel() }

        if let error {
            continuation.finish(throwing: error)
            return
        }

        do {
            if let response {
                try validateResponse(response, isErrorResponse ? errorData : nil)
            }
            if !isErrorResponse, let partial = lineReader.flushPartialLine() {
                try yieldLine(partial)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func appendErrorData(_ data: Data) {
        guard errorData.count < 65_536 else { return }
        let remaining = 65_536 - errorData.count
        errorData.append(data.prefix(remaining))
    }

    private func yieldLine(_ data: Data) throws {
        var lineData = data
        if lineData.last == UInt8(ascii: "\r") {
            lineData.removeLast()
        }
        guard let line = String(data: lineData, encoding: .utf8) else {
            throw GrokError.decodingError(
                DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Streaming line was not valid UTF-8"
                ))
            )
        }
        continuation.yield(line)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
