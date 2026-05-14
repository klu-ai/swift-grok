// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// import Rainbow
// 
// enum GrokCodeEventKind: String, Codable, Equatable {
//     case message
//     case toolRequest = "tool_request"
//     case toolResult = "tool_result"
//     case progress
//     case warning
//     case error
//     case done
// }
// 
// struct GrokCodeEvent: Codable, Equatable, Identifiable {
//     var id: UUID
//     var sequence: Int
//     var kind: GrokCodeEventKind
//     var timestamp: Date
//     var role: GrokCodeRole
//     var agentRole: GrokCodeAgentRole?
//     var envelopeID: UUID?
//     var parentID: UUID?
//     var message: String
//     var metadata: [String: AnyCodable]
// 
//     init(
//         id: UUID = UUID(),
//         sequence: Int = 0,
//         kind: GrokCodeEventKind,
//         timestamp: Date = Date(),
//         role: GrokCodeRole = .harness,
//         agentRole: GrokCodeAgentRole? = nil,
//         envelopeID: UUID? = nil,
//         parentID: UUID? = nil,
//         message: String,
//         metadata: [String: AnyCodable] = [:]
//     ) {
//         self.id = id
//         self.sequence = sequence
//         self.kind = kind
//         self.timestamp = timestamp
//         self.role = role
//         self.agentRole = agentRole
//         self.envelopeID = envelopeID
//         self.parentID = parentID
//         self.message = message
//         self.metadata = metadata
//     }
// 
//     static func envelope(_ envelope: GrokCodeMessageEnvelope, sequence: Int) -> GrokCodeEvent {
//         let eventKind: GrokCodeEventKind
//         switch envelope.kind {
//         case .message:
//             eventKind = .message
//         case .toolRequest:
//             eventKind = .toolRequest
//         case .toolResult:
//             eventKind = .toolResult
//         case .event:
//             eventKind = .progress
//         }
// 
//         return GrokCodeEvent(
//             sequence: sequence,
//             kind: eventKind,
//             timestamp: envelope.timestamp,
//             role: envelope.role,
//             agentRole: envelope.agentRole,
//             envelopeID: envelope.id,
//             parentID: envelope.parentID,
//             message: envelope.content,
//             metadata: envelope.metadata
//         )
//     }
// 
//     static func == (lhs: GrokCodeEvent, rhs: GrokCodeEvent) -> Bool {
//         lhs.id == rhs.id &&
//             lhs.sequence == rhs.sequence &&
//             lhs.kind == rhs.kind &&
//             lhs.timestamp == rhs.timestamp &&
//             lhs.role == rhs.role &&
//             lhs.agentRole == rhs.agentRole &&
//             lhs.envelopeID == rhs.envelopeID &&
//             lhs.parentID == rhs.parentID &&
//             lhs.message == rhs.message
//     }
// }
// 
// final class GrokCodeRenderer {
//     var format: OutputFormat
// 
//     init(format: OutputFormat = .defaultFormat) {
//         self.format = format
//     }
// 
//     func printEvent(_ event: GrokCodeEvent, sequence: Int? = nil) throws {
//         print(render(event, sequence: sequence))
//     }
// 
//     func printEnvelope(_ envelope: GrokCodeMessageEnvelope, sequence: Int) throws {
//         print(renderEnvelope(envelope, sequence: sequence))
//     }
// 
//     func render(_ event: GrokCodeEvent, sequence: Int? = nil) -> String {
//         switch format {
//         case .json:
//             return renderEventJSON(event, sequence: sequence)
//         case .markdown, .raw:
//             return renderHuman(event)
//         }
//     }
// 
//     func renderEnvelope(_ envelope: GrokCodeMessageEnvelope, sequence: Int) -> String {
//         switch format {
//         case .json:
//             return renderEnvelopeJSON(envelope, sequence: sequence)
//         case .markdown, .raw:
//             return renderEnvelopeHuman(envelope)
//         }
//     }
// 
//     private func renderHuman(_ event: GrokCodeEvent) -> String {
//         let label = "[\(event.kind.rawValue)]".blue
//         guard !event.message.isEmpty else {
//             return label
//         }
//         return "\(label) \(event.message)"
//     }
// 
//     private func renderEnvelopeHuman(_ envelope: GrokCodeMessageEnvelope) -> String {
//         let label: String
//         if let agentRole = envelope.agentRole {
//             label = "[\(agentRole.rawValue)]".cyan
//         } else if envelope.kind == .toolRequest || envelope.kind == .toolResult {
//             label = "[tool]".yellow
//         } else {
//             label = "[\(envelope.role.rawValue)]".blue
//         }
//         guard !envelope.content.isEmpty else {
//             return label
//         }
//         return "\(label) \(envelope.content)"
//     }
// 
//     private func renderEventJSON(_ event: GrokCodeEvent, sequence: Int?) -> String {
//         var data: [String: AnyCodable] = [
//             "schema": AnyCodable("grok.cli.code.event.v1"),
//             "id": AnyCodable(event.id.uuidString),
//             "event": AnyCodable(event.kind.rawValue),
//             "timestamp": AnyCodable(ISO8601DateFormatter().string(from: event.timestamp)),
//             "message": AnyCodable(event.message),
//             "metadata": AnyCodable(event.metadata)
//         ]
//         if let sequence {
//             data["sequence"] = AnyCodable(sequence)
//         } else {
//             data["sequence"] = AnyCodable(event.sequence)
//         }
//         if let agentRole = event.agentRole {
//             data["agentRole"] = AnyCodable(agentRole.rawValue)
//         }
//         if let envelopeID = event.envelopeID {
//             data["envelopeId"] = AnyCodable(envelopeID.uuidString)
//         }
//         if let parentID = event.parentID {
//             data["parentId"] = AnyCodable(parentID.uuidString)
//         }
//         return encodeJSON(data)
//     }
// 
//     private func renderEnvelopeJSON(_ envelope: GrokCodeMessageEnvelope, sequence: Int) -> String {
//         var data: [String: AnyCodable] = [
//             "schema": AnyCodable("grok.cli.code.event.v1"),
//             "sequence": AnyCodable(sequence),
//             "event": AnyCodable(envelope.kind.rawValue),
//             "timestamp": AnyCodable(ISO8601DateFormatter().string(from: envelope.timestamp)),
//             "role": AnyCodable(envelope.role.rawValue),
//             "envelopeId": AnyCodable(envelope.id.uuidString),
//             "message": AnyCodable(envelope.content)
//         ]
//         if let agentRole = envelope.agentRole {
//             data["agentRole"] = AnyCodable(agentRole.rawValue)
//         }
//         if let parentID = envelope.parentID {
//             data["parentId"] = AnyCodable(parentID.uuidString)
//         }
//         if !envelope.metadata.isEmpty {
//             data["metadata"] = AnyCodable(envelope.metadata)
//         }
//         return encodeJSON(data)
//     }
// 
//     private func encodeJSON(_ data: [String: AnyCodable]) -> String {
//         let encoder = JSONEncoder()
//         encoder.dateEncodingStrategy = .iso8601
//         encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
// 
//         guard
//             let jsonData = try? encoder.encode(AnyCodable(data)),
//             let json = String(data: jsonData, encoding: .utf8)
//         else {
//             return #"{"event":"error","message":"Could not encode Grok Code event"}"#
//         }
//         return json
//     }
// }
