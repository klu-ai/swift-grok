import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var lastRequest: URLRequest?
    static var lastRequestBody: Data?
    static var requests: [URLRequest] = []
    static var requestBodies: [Data?] = []
    static var queuedResponses: [(data: Data, response: URLResponse)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        let requestBody = request.httpBody ?? request.httpBodyStream.flatMap(Self.readBodyStream)
        MockURLProtocol.lastRequestBody = requestBody
        MockURLProtocol.requests.append(request)
        MockURLProtocol.requestBodies.append(requestBody)

        if !MockURLProtocol.queuedResponses.isEmpty {
            let queuedResponse = MockURLProtocol.queuedResponses.removeFirst()
            client?.urlProtocol(self, didReceive: queuedResponse.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: queuedResponse.data)
        } else if let response = MockURLProtocol.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = MockURLProtocol.mockData {
                client?.urlProtocol(self, didLoad: data)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}
