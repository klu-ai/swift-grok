import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GrokStreamingLineReader {
    private var buffer = Data()
    private var consumedOffset = 0
    private var searchOffset = 0

    private let maxBufferedBytes: Int
    private let compactionThreshold: Int

    init(maxBufferedBytes: Int = 1_048_576, compactionThreshold: Int = 65_536) {
        self.maxBufferedBytes = maxBufferedBytes
        self.compactionThreshold = compactionThreshold
    }

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

final class StreamingLineDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let validateResponse: (URLResponse, Data?) throws -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var isErrorResponse = false
    private var errorData = Data()
    private var lineReader = GrokStreamingLineReader()

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
        defer {
            session.finishTasksAndInvalidate()
            self.task = nil
            self.session = nil
        }

        if let error {
            continuation.finish(throwing: error)
            return
        }

        guard let response else {
            continuation.finish(throwing: GrokError.networkError(URLError(.badServerResponse)))
            return
        }

        if isErrorResponse {
            do {
                try validateResponse(response, errorData)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            return
        }

        if let lineData = lineReader.flushPartialLine() {
            do {
                try yieldLine(lineData)
            } catch {
                continuation.finish(throwing: error)
                return
            }
        }

        continuation.finish()
    }

    private func appendErrorData(_ data: Data) {
        guard errorData.count < 8192 else { return }
        errorData.append(data.prefix(8192 - errorData.count))
    }

    private func yieldLine(_ data: Data) throws {
        var lineData = data
        if lineData.last == UInt8(ascii: "\r") {
            lineData.removeLast()
        }
        guard let line = String(data: lineData, encoding: .utf8) else {
            throw GrokError.decodingError(URLError(.cannotDecodeContentData))
        }
        continuation.yield(line)
    }
}
