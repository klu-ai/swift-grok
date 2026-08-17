import Foundation
import GrokClient

enum GrokCodeEventKind: String, Codable, Equatable {
    case sessionStarted = "session_started"
    case modelResolved = "model_resolved"
    case promptAssembled = "prompt_assembled"
    case transcriptWritten = "transcript_written"
    case agentStarted = "agent_started"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case agentCompleted = "agent_completed"
    case warning
    case failure
}

struct GrokCodeEvent: Codable, Identifiable {
    var id: UUID
    var sequence: Int
    var timestamp: Date
    var kind: GrokCodeEventKind
    var message: String
    var metadata: [String: AnyCodable]

    init(
        id: UUID = UUID(),
        sequence: Int,
        timestamp: Date = Date(),
        kind: GrokCodeEventKind,
        message: String,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
        self.metadata = metadata
    }

    static func envelope(_ envelope: GrokCodeMessageEnvelope, sequence: Int) -> GrokCodeEvent {
        GrokCodeEvent(
            sequence: sequence,
            kind: .transcriptWritten,
            message: "\(envelope.role.rawValue) \(envelope.kind.rawValue)",
            metadata: [
                "envelopeId": AnyCodable(envelope.id.uuidString),
                "role": AnyCodable(envelope.role.rawValue),
                "kind": AnyCodable(envelope.kind.rawValue)
            ]
        )
    }
}
