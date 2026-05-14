import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// StreamingURLProtocol simulates a streaming response by sending data in chunks.
class StreamingURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var chunkDelay: TimeInterval = 0.01
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = StreamingURLProtocol.mockResponse else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        guard let data = StreamingURLProtocol.mockData else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let lines = data.split(separator: UInt8(ascii: "\n"))
            for line in lines {
                guard !self.stopped else { return }
                var chunkData = Data(line)
                chunkData.append(UInt8(ascii: "\n"))
                self.client?.urlProtocol(self, didLoad: chunkData)
                Thread.sleep(forTimeInterval: StreamingURLProtocol.chunkDelay)
            }
            guard !self.stopped else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopped = true
    }
}
