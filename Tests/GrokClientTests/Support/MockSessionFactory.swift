import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func makeMockSession(
    data: Data,
    statusCode: Int,
    useStreaming: Bool = false,
    chunkDelay: TimeInterval = 0.01
) -> URLSession {
    let url = URL(string: "https://mocked.url")!
    let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!

    let protocolClass: AnyClass = useStreaming ? StreamingURLProtocol.self : MockURLProtocol.self

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [protocolClass]
    let session = URLSession(configuration: config)
    MockURLProtocol.lastRequest = nil
    MockURLProtocol.lastRequestBody = nil
    MockURLProtocol.requests = []
    MockURLProtocol.requestBodies = []
    MockURLProtocol.queuedResponses = []

    if let streamingProto = protocolClass as? StreamingURLProtocol.Type {
        streamingProto.mockData = data
        streamingProto.mockResponse = response
        streamingProto.chunkDelay = chunkDelay
    } else if let mockProto = protocolClass as? MockURLProtocol.Type {
        mockProto.mockData = data
        mockProto.mockResponse = response
    }

    return session
}

func makeMockSession(responses: [(data: Data, statusCode: Int)]) -> URLSession {
    let url = URL(string: "https://mocked.url")!
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    MockURLProtocol.lastRequest = nil
    MockURLProtocol.lastRequestBody = nil
    MockURLProtocol.requests = []
    MockURLProtocol.requestBodies = []
    MockURLProtocol.mockData = nil
    MockURLProtocol.mockResponse = nil
    MockURLProtocol.queuedResponses = responses.map { response in
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data: response.data, response: httpResponse)
    }

    return session
}
