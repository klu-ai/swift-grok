import XCTest
@testable import GrokClient

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GrokClientStreamingTests: XCTestCase {
    override func tearDown() {
        ChunkedStreamingURLProtocol.reset()
        super.tearDown()
    }

    func testSendMessage_success() async throws {
        let streamingData = """
        {"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}
        {"result":{"response":{"responseId":"resp777","token":"World"}}}
        {"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let response = try await client.sendMessage(message: "Hi Grok")

        XCTAssertEqual(response.message, "Hello World")
        XCTAssertEqual(response.conversationId, "convo123")
        XCTAssertEqual(response.responseId, "resp777")
    }

    func testStreamParserYieldsFirstTokenBeforeLineSourceCompletes() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid": "123"])
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}"#)
            Task {
                try await Task.sleep(nanoseconds: 500_000_000)
                continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"World"}}}"#)
                continuation.yield(#"{"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}"#)
                continuation.finish()
            }
        }

        let stream = client.streamResponses(from: lines)
        var iterator = stream.makeAsyncIterator()
        let start = Date()

        let first = try await iterator.next()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(first?.message, "Hello ")
        XCTAssertFalse(first?.isFinal ?? true)
        XCTAssertLessThan(elapsed, 0.2, "Expected first streamed token before later chunks completed.")

        var finalResponse: ConversationResponse?
        while let response = try await iterator.next() {
            if response.isFinal {
                finalResponse = response
                break
            }
        }
        XCTAssertEqual(finalResponse?.message, "Hello World")
    }

    func testStreamParserFinishesAfterFinalBeforeLineSourceCompletes() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid": "123"])
        var lineContinuation: AsyncThrowingStream<String, Error>.Continuation?
        let lines = AsyncThrowingStream<String, Error> { continuation in
            lineContinuation = continuation
        }
        let continuation = try XCTUnwrap(lineContinuation)
        let stream = client.streamResponses(from: lines)

        let consumeTask = Task {
            var responses: [ConversationResponse] = []
            for try await response in stream {
                responses.append(response)
            }
            return responses
        }

        continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}"#)
        continuation.yield(#"{"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}"#)

        let completedBeforeSourceEOF = await completesWithinTimeout(consumeTask, nanoseconds: 500_000_000)

        continuation.finish()
        let responses = try await consumeTask.value

        XCTAssertTrue(completedBeforeSourceEOF, "Stream parser should finish as soon as final modelResponse arrives.")
        XCTAssertEqual(responses.map(\.message), ["Hello ", "Hello World"])
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamParserTreatsPlainEmptyTokenAsTerminalBeforeDelayedModelResponse() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid": "123"])
        var lineContinuation: AsyncThrowingStream<String, Error>.Continuation?
        let lines = AsyncThrowingStream<String, Error> { continuation in
            lineContinuation = continuation
        }
        let continuation = try XCTUnwrap(lineContinuation)
        let stream = client.streamResponses(from: lines)

        let consumeTask = Task {
            var responses: [ConversationResponse] = []
            for try await response in stream {
                responses.append(response)
            }
            return responses
        }

        continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}"#)
        continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"World"}}}"#)
        continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"","isThinking":false,"isSoftStop":false}}}"#)

        let completedBeforeDelayedMetadata = await completesWithinTimeout(consumeTask, nanoseconds: 500_000_000)

        continuation.yield(#"{"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}"#)
        continuation.finish()
        let responses = try await consumeTask.value

        XCTAssertTrue(completedBeforeDelayedMetadata, "Stream parser should finish on the terminal empty token before delayed final metadata arrives.")
        XCTAssertEqual(responses.map(\.message), ["Hello ", "World", "Hello World"])
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamParserDoesNotTreatToolEmptyTokenAsTerminal() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid": "123"])
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}"#)
            continuation.yield(#"{"result":{"responseId":"resp777","token":"","isThinking":false,"isSoftStop":false,"messageTag":"raw_function_result","messageStepId":0,"toolUsageCardId":"tool-1"}}"#)
            continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"World"}}}"#)
            continuation.yield(#"{"result":{"response":{"modelResponse":{"message":"Hello World","responseId":"resp777"}}}}"#)
            continuation.finish()
        }

        let responses = try await collect(client.streamResponses(from: lines))

        XCTAssertEqual(responses.count, 4)
        XCTAssertEqual(responses[1].message, "")
        XCTAssertEqual(responses[1].responseId, "resp777")
        XCTAssertFalse(responses[1].isFinal)
        XCTAssertEqual(responses.map(\.message), ["Hello ", "", "World", "Hello World"])
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamMessageYieldsFallbackFinalWhenNoModelResponseArrives() async throws {
        let streamingData = """
        {"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"Hello "}}}
        {"result":{"response":{"responseId":"resp777","token":"World"}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let responses = try await collect(try await client.streamMessage(message: "Hi Grok"))

        XCTAssertEqual(responses.map(\.message), ["Hello ", "World", "Hello World"])
        XCTAssertEqual(responses.last?.conversationId, "convo123")
        XCTAssertEqual(responses.last?.responseId, "resp777")
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamParserKeepsThinkingTokensOutOfFallbackFinal() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid": "123"])
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"{"result":{"conversation":{"conversationId":"convo123"},"response":{"responseId":"resp777","token":"long silk"}}}"#)
            continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"Responding as a beautiful Asian woman","isThinking":true}}}"#)
            continuation.yield(#"{"result":{"response":{"responseId":"resp777","token":"y black hair"}}}"#)
            continuation.finish()
        }

        let responses = try await collect(client.streamResponses(from: lines))

        XCTAssertEqual(responses.count, 4)
        XCTAssertEqual(responses[0].message, "long silk")
        XCTAssertFalse(responses[0].isThinking)
        XCTAssertEqual(responses[1].message, "Responding as a beautiful Asian woman")
        XCTAssertTrue(responses[1].isThinking)
        XCTAssertEqual(responses[2].message, "y black hair")
        XCTAssertFalse(responses[2].isThinking)
        XCTAssertEqual(responses[3].message, "long silky black hair")
        XCTAssertTrue(responses[3].isFinal)
    }

    func testContinueConversation_success() async throws {
        let streamingData = """
        {"result":{"responseId":"resp888","modelResponse":{"message":"Continued","responseId":"resp888"}}}
        """.data(using: .utf8)!

        let mockSession = makeMockSession(data: streamingData, statusCode: 200, useStreaming: true)
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: mockSession)

        let responses = try await collect(try await client.continueConversation(
            conversationId: "convo123",
            parentResponseId: "resp777",
            message: "Continue from there"
        ))

        let finalResponse = responses.last { $0.isFinal }
        XCTAssertEqual(finalResponse?.message, "Continued")
        XCTAssertEqual(finalResponse?.responseId, "resp888")
        XCTAssertNil(finalResponse?.webSearchResults)
        XCTAssertNil(finalResponse?.xposts)
    }

    func testStreamMessageHandlesArbitraryChunkSplits() async throws {
        let body = """
        data: {"result":{"conversation":{"conversationId":"convo-split"},"response":{"responseId":"resp-split","token":"Hel"}}}
        data: {"result":{"response":{"responseId":"resp-split","token":"lo"}}}
        data: {"result":{"response":{"modelResponse":{"message":"Hello","responseId":"resp-split"}}}}
        """
        let session = chunkedStreamingSession(
            data: Data(body.utf8),
            statusCode: 200,
            chunkSizes: [1, 7, 2, 19, 3, 5, 11, 1, 23]
        )
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: session)

        let responses = try await collect(try await client.streamMessage(message: "Hi Grok"))

        XCTAssertEqual(responses.map(\.message), ["Hel", "lo", "Hello"])
        XCTAssertEqual(responses.last?.conversationId, "convo-split")
        XCTAssertEqual(responses.last?.responseId, "resp-split")
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamingLinesHandlesCRLFLineEndings() async throws {
        let session = chunkedStreamingSession(
            data: Data("first\r\nsecond\r\n".utf8),
            statusCode: 200,
            chunkSizes: [3, 4, 1, 5, 2]
        )
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: session)

        let lines = try await collect(try client.streamingLinesForTest())

        XCTAssertEqual(lines, ["first", "second"])
    }

    func testStreamingLinesFlushesFinalPartialLine() async throws {
        let session = chunkedStreamingSession(
            data: Data("first\npartial-without-newline".utf8),
            statusCode: 200,
            chunkSizes: [6, 4, 3, 19]
        )
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: session)

        let lines = try await collect(try client.streamingLinesForTest())

        XCTAssertEqual(lines, ["first", "partial-without-newline"])
    }

    func testStreamingLinesThrowsAPIErrorWithNon2xxStreamingBody() async throws {
        let session = chunkedStreamingSession(
            data: Data(#"{"error":{"message":"rate limited"}}"#.utf8),
            statusCode: 429,
            chunkSizes: [2, 1, 8, 4, 99]
        )
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: session)

        do {
            _ = try await collect(try client.streamingLinesForTest())
            XCTFail("Expected non-2xx streaming response to throw.")
        } catch GrokError.apiError(let message) {
            XCTAssertTrue(message.contains("HTTP Error: 429"))
            XCTAssertTrue(message.contains("rate limited"))
        } catch {
            XCTFail("Expected GrokError.apiError, got \(error).")
        }
    }

    func testStreamingLinesThrowsDecodingErrorForInvalidUTF8() async throws {
        let session = chunkedStreamingSession(
            data: Data([0x48, 0x69, 0xff, 0x0a]),
            statusCode: 200,
            chunkSizes: [1, 2, 1]
        )
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: session)

        do {
            _ = try await collect(try client.streamingLinesForTest())
            XCTFail("Expected invalid UTF-8 to throw.")
        } catch GrokError.decodingError {
            // Expected.
        } catch {
            XCTFail("Expected GrokError.decodingError, got \(error).")
        }
    }

    func testStreamParserTreatsDoneAsExplicitTerminalSignal() async throws {
        let client = try GrokClient(cookies: ["x-anonuserid": "123"])
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"data: {"result":{"conversation":{"conversationId":"convo-done"},"response":{"responseId":"resp-done","token":"Hello"}}}"#)
            continuation.yield("data: [DONE]")
            continuation.yield(#"data: {"result":{"response":{"responseId":"resp-done","token":" ignored"}}}"#)
            continuation.finish()
        }

        let responses = try await collect(client.streamResponses(from: lines))

        XCTAssertEqual(responses.map(\.message), ["Hello", "Hello"])
        XCTAssertEqual(responses.last?.conversationId, "convo-done")
        XCTAssertEqual(responses.last?.responseId, "resp-done")
        XCTAssertEqual(responses.last?.isFinal, true)
    }

    func testStreamingLinesCancelsUnderlyingTaskOnTermination() async throws {
        let didStop = expectation(description: "URLProtocol stopLoading called")
        let session = chunkedStreamingSession(
            data: Data("first\nsecond\nthird\n".utf8),
            statusCode: 200,
            chunkSizes: [6, 7, 6],
            chunkDelay: 0.2,
            onStopLoading: {
                didStop.fulfill()
            }
        )
        let client = try GrokClient(cookies: ["x-anonuserid": "123"], session: session)
        let stream = try client.streamingLinesForTest()

        let consumer = Task {
            for try await line in stream {
                XCTAssertEqual(line, "first")
                break
            }
        }
        try await consumer.value

        await fulfillment(of: [didStop], timeout: 1.0)
    }

    private func chunkedStreamingSession(
        data: Data,
        statusCode: Int,
        chunkSizes: [Int],
        chunkDelay: TimeInterval = 0,
        onStopLoading: (() -> Void)? = nil
    ) -> URLSession {
        let url = URL(string: "https://mocked.url")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        ChunkedStreamingURLProtocol.data = data
        ChunkedStreamingURLProtocol.response = response
        ChunkedStreamingURLProtocol.chunkSizes = chunkSizes
        ChunkedStreamingURLProtocol.chunkDelay = chunkDelay
        ChunkedStreamingURLProtocol.onStopLoading = onStopLoading

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedStreamingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect<Element>(
        _ stream: AsyncThrowingStream<Element, Error>
    ) async throws -> [Element] {
        var elements: [Element] = []
        for try await element in stream {
            elements.append(element)
        }
        return elements
    }

    private func completesWithinTimeout<Success>(
        _ task: Task<Success, Error>,
        nanoseconds: UInt64
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    _ = try await task.value
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

private extension GrokClient {
    func streamingLinesForTest() throws -> AsyncThrowingStream<String, Error> {
        let request = URLRequest(url: URL(string: "https://example.test/stream")!)
        return streamingLines(for: request)
    }
}

private final class ChunkedStreamingURLProtocol: URLProtocol {
    static var data = Data()
    static var response: URLResponse?
    static var chunkSizes: [Int] = []
    static var chunkDelay: TimeInterval = 0
    static var onStopLoading: (() -> Void)?

    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let response = Self.response else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunks = Self.chunks(from: Self.data, sizes: Self.chunkSizes)
        let delay = Self.chunkDelay

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            for chunk in chunks {
                guard !self.stopped else { return }
                self.client?.urlProtocol(self, didLoad: chunk)
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
            guard !self.stopped else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopped = true
        Self.onStopLoading?()
    }

    static func reset() {
        data = Data()
        response = nil
        chunkSizes = []
        chunkDelay = 0
        onStopLoading = nil
    }

    private static func chunks(from data: Data, sizes: [Int]) -> [Data] {
        guard !data.isEmpty else { return [] }
        guard !sizes.isEmpty else { return [data] }

        var chunks: [Data] = []
        var index = data.startIndex
        var sizeIndex = 0

        while index < data.endIndex {
            let requestedSize = max(1, sizes[sizeIndex % sizes.count])
            let end = data.index(index, offsetBy: requestedSize, limitedBy: data.endIndex) ?? data.endIndex
            chunks.append(Data(data[index..<end]))
            index = end
            sizeIndex += 1
        }

        return chunks
    }
}
