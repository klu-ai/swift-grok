import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension GrokClient {
    func streamResponses<Lines: AsyncSequence>(
        from lines: Lines,
        initialConversationId: String = ""
    ) -> AsyncThrowingStream<ConversationResponse, Error> where Lines.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = GrokStreamParser(initialConversationId: initialConversationId)

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

    func streamResponses(
        for request: URLRequest,
        initialConversationId: String = "",
        modeId: String? = nil
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let lines = streamingLines(for: request, modeId: modeId)
        return streamResponses(from: lines, initialConversationId: initialConversationId)
    }

    func streamingLines(for request: URLRequest, modeId: String? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let validateResponse: (URLResponse, Data?) throws -> Void = { response, data in
                try self.validateHTTPResponse(response, data: data, modeId: modeId)
            }
            let delegate = StreamingLineDelegate(
                continuation: continuation,
                validateResponse: validateResponse
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
}
