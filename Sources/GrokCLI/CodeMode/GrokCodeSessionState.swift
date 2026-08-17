import Foundation
import GrokClient

struct GrokCodeSessionState: Identifiable {
    let id: UUID
    let startedAt: Date
    var cwd: URL
    var model: GrokMode
    var options: GrokCodeOptions
    var events: [GrokCodeEvent]
    var completedTurns: Int
    var transcriptPath: String?
    var promptCharacterCount: Int
    var finalAnswer: String?
    var responseID: String?
    var failureMessage: String?
    var lastEnvelopeID: UUID?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        cwd: URL,
        model: GrokMode,
        options: GrokCodeOptions,
        events: [GrokCodeEvent] = [],
        completedTurns: Int = 0,
        transcriptPath: String? = nil,
        promptCharacterCount: Int = 0,
        finalAnswer: String? = nil,
        responseID: String? = nil,
        failureMessage: String? = nil,
        lastEnvelopeID: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.cwd = cwd
        self.model = model
        self.options = options
        self.events = events
        self.completedTurns = completedTurns
        self.transcriptPath = transcriptPath
        self.promptCharacterCount = promptCharacterCount
        self.finalAnswer = finalAnswer
        self.responseID = responseID
        self.failureMessage = failureMessage
        self.lastEnvelopeID = lastEnvelopeID
    }

    mutating func appendEvent(
        kind: GrokCodeEventKind,
        _ message: String,
        metadata: [String: AnyCodable] = [:]
    ) {
        events.append(GrokCodeEvent(
            sequence: events.count + 1,
            kind: kind,
            message: message,
            metadata: metadata
        ))
    }

    @discardableResult
    mutating func appendEnvelope(
        role: GrokCodeRole,
        kind: GrokCodeMessageKind = .message,
        content: String,
        isEphemeral: Bool = false,
        metadata: [String: AnyCodable] = [:],
        includeEvent: Bool = true,
        store: GrokCodeTranscriptStore? = nil
    ) throws -> GrokCodeMessageEnvelope {
        let envelope = GrokCodeMessageEnvelope(
            parentID: lastEnvelopeID,
            role: role,
            kind: kind,
            content: content,
            isEphemeral: isEphemeral,
            metadata: metadata
        )
        if !isEphemeral {
            try store?.append(envelope)
            lastEnvelopeID = envelope.id
        }
        if includeEvent {
            events.append(GrokCodeEvent.envelope(envelope, sequence: events.count + 1))
        }
        return envelope
    }
}

extension GrokCodeSessionState {
    var json: [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "sessionId": AnyCodable(id.uuidString),
            "startedAt": AnyCodable(startedAt.timeIntervalSince1970),
            "cwd": AnyCodable(cwd.path),
            "model": AnyCodable(GrokCLI.modeJSON(model)),
            "options": AnyCodable(options.json),
            "completedTurns": AnyCodable(completedTurns),
            "promptCharacterCount": AnyCodable(promptCharacterCount),
            "events": AnyCodable(events.map { event in
                [
                    "id": AnyCodable(event.id.uuidString),
                    "sequence": AnyCodable(event.sequence),
                    "kind": AnyCodable(event.kind.rawValue),
                    "timestamp": AnyCodable(event.timestamp.timeIntervalSince1970),
                    "message": AnyCodable(event.message),
                    "metadata": AnyCodable(event.metadata)
                ]
            })
        ]
        if let transcriptPath {
            data["transcriptPath"] = AnyCodable(transcriptPath)
        }
        if let finalAnswer {
            data["finalAnswer"] = AnyCodable(finalAnswer)
        }
        if let responseID {
            data["responseId"] = AnyCodable(responseID)
        }
        if let failureMessage {
            data["failure"] = AnyCodable(failureMessage)
        }
        return data
    }
}
