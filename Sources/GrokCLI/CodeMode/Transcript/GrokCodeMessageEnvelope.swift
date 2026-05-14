// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// enum GrokCodeRole: String, Codable, Equatable {
//     case user
//     case assistant
//     case tool
//     case system
//     case harness
// }
// 
// enum GrokCodeAgentRole: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
//     case strategy
//     case architecture
//     case engineering
//     case security
// }
// 
// enum GrokCodeMessageKind: String, Codable, Equatable {
//     case message
//     case toolRequest = "tool_request"
//     case toolResult = "tool_result"
//     case event
// }
// 
// struct GrokCodeMessageEnvelope: Codable, Identifiable {
//     var id: UUID
//     var parentID: UUID?
//     var timestamp: Date
//     var role: GrokCodeRole
//     var agentRole: GrokCodeAgentRole?
//     var kind: GrokCodeMessageKind
//     var content: String
//     var isEphemeral: Bool
//     var metadata: [String: AnyCodable]
// 
//     init(
//         id: UUID = UUID(),
//         parentID: UUID? = nil,
//         timestamp: Date = Date(),
//         role: GrokCodeRole,
//         agentRole: GrokCodeAgentRole? = nil,
//         kind: GrokCodeMessageKind = .message,
//         content: String,
//         isEphemeral: Bool = false,
//         metadata: [String: AnyCodable] = [:]
//     ) {
//         self.id = id
//         self.parentID = parentID
//         self.timestamp = timestamp
//         self.role = role
//         self.agentRole = agentRole
//         self.kind = kind
//         self.content = content
//         self.isEphemeral = isEphemeral
//         self.metadata = metadata
//     }
// }
// 
// extension GrokCodeMessageEnvelope: Equatable {
//     static func == (lhs: GrokCodeMessageEnvelope, rhs: GrokCodeMessageEnvelope) -> Bool {
//         lhs.id == rhs.id &&
//             lhs.parentID == rhs.parentID &&
//             lhs.timestamp == rhs.timestamp &&
//             lhs.role == rhs.role &&
//             lhs.agentRole == rhs.agentRole &&
//             lhs.kind == rhs.kind &&
//             lhs.content == rhs.content &&
//             lhs.isEphemeral == rhs.isEphemeral
//     }
// }
