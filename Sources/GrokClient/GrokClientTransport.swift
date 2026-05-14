import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GrokClient Transport
extension GrokClient {
    private func statsigPath(for path: String, namespace: RestNamespace = .appChat) -> String {
        let pathWithoutQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        return "\(namespace.pathPrefix)\(pathWithoutQuery)"
    }

    private func makeStatsigID(path: String, method: String, namespace: RestNamespace = .appChat) -> String? {
        #if canImport(CryptoKit)
        let metaBase64 = "aTdepyfBsvO5OewwurJnUTpd+p89iA3b26j9Sw2BhK32z+fmV5t8Qxe91l75WsOp"
        let fingerprint = "90e5cb100a3d70a3d70a3d800a3d70a3d70a3d8100"
        guard let metaBytes = Data(base64Encoded: metaBase64) else {
            return nil
        }

        let epochOffset = 0x644f6370
        let relativeSeconds = UInt32(max(0, Int(Date().timeIntervalSince1970.rounded(.down)) - epochOffset))
        let message = "\(method)!\(statsigPath(for: path, namespace: namespace))!\(relativeSeconds)obfiowerehiring\(fingerprint)"
        let digest = SHA256.hash(data: Data(message.utf8))

        var raw = Data()
        let randomByte = UInt8.random(in: UInt8.min...UInt8.max)
        raw.append(randomByte)
        raw.append(metaBytes)
        raw.append(UInt8(relativeSeconds & 0xff))
        raw.append(UInt8((relativeSeconds >> 8) & 0xff))
        raw.append(UInt8((relativeSeconds >> 16) & 0xff))
        raw.append(UInt8((relativeSeconds >> 24) & 0xff))
        raw.append(contentsOf: digest.prefix(16))
        raw.append(3)

        for index in raw.indices.dropFirst() {
            raw[index] ^= randomByte
        }

        return raw.base64EncodedString().replacingOccurrences(of: "=", with: "")
        #else
        return nil
        #endif
    }

    func makeRequest(
        path: String,
        method: String = "POST",
        payload: [String: Any]? = nil,
        namespace: RestNamespace = .appChat
    ) throws -> URLRequest {
        let requestBaseURL: String
        switch namespace {
        case .appChat:
            requestBaseURL = baseURL
        case .root:
            requestBaseURL = rootBaseURL
        case .web:
            requestBaseURL = webBaseURL
        }

        let url = URL(string: "\(requestBaseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (key, value) in headers {
            if payload == nil && ["content-type", "origin"].contains(key.lowercased()) {
                continue
            }
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "x-xai-request-id")
        if let statsigID = makeStatsigID(path: path, method: method, namespace: namespace) {
            request.setValue(statsigID, forHTTPHeaderField: "x-statsig-id")
        }
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        if let payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        if isDebug {
            print("Debug cURL: \(request.curlRepresentation(redactCookies: true))")
        }

        return request
    }

    @discardableResult
    func sendJSON(path: String, method: String = "POST", payload: [String: Any]? = nil, namespace: RestNamespace = .appChat) async throws -> Any {
        let request = try makeRequest(path: path, method: method, payload: payload, namespace: namespace)
        return try await jsonObject(for: request)
    }

    func sendVoid(path: String, method: String = "POST", payload: [String: Any]? = nil, namespace: RestNamespace = .appChat) async throws {
        let request = try makeRequest(path: path, method: method, payload: payload, namespace: namespace)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    func decodeJSON<T: Decodable>(
        _ type: T.Type = T.self,
        path: String,
        method: String = "POST",
        payload: [String: Any]? = nil,
        namespace: RestNamespace = .appChat,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, payload: payload, namespace: namespace)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    func jsonObject(for request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard !data.isEmpty else {
            return [:] as [String: Any]
        }

        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw GrokError.decodingError(error)
        }
    }

}
