// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// struct GrokCodeSessionState: Identifiable {
//     let id: UUID
//     let startedAt: Date
//     var options: GrokCodeOptions
//     var queue: GrokCodeCommandQueue
//     var events: [GrokCodeEvent]
//     var completedTurns: Int
//     var settingsBackupPath: String?
//     var transcriptPath: String?
//     var finalAnswer: String?
//     var lastEnvelopeID: UUID?
//     var restoreErrorMessage: String?
// 
//     init(
//         id: UUID = UUID(),
//         startedAt: Date = Date(),
//         options: GrokCodeOptions,
//         queue: GrokCodeCommandQueue = GrokCodeCommandQueue(),
//         events: [GrokCodeEvent] = [],
//         completedTurns: Int = 0,
//         settingsBackupPath: String? = nil,
//         transcriptPath: String? = nil,
//         finalAnswer: String? = nil,
//         lastEnvelopeID: UUID? = nil,
//         restoreErrorMessage: String? = nil
//     ) {
//         self.id = id
//         self.startedAt = startedAt
//         self.options = options
//         self.queue = queue
//         self.events = events
//         self.completedTurns = completedTurns
//         self.settingsBackupPath = settingsBackupPath
//         self.transcriptPath = transcriptPath
//         self.finalAnswer = finalAnswer
//         self.lastEnvelopeID = lastEnvelopeID
//         self.restoreErrorMessage = restoreErrorMessage
//     }
// 
//     mutating func appendEvent(
//         kind: GrokCodeEventKind,
//         _ message: String,
//         role: GrokCodeRole = .harness,
//         agentRole: GrokCodeAgentRole? = nil,
//         envelopeID: UUID? = nil,
//         parentID: UUID? = nil,
//         metadata: [String: AnyCodable] = [:]
//     ) {
//         events.append(GrokCodeEvent(
//             sequence: events.count + 1,
//             kind: kind,
//             role: role,
//             agentRole: agentRole,
//             envelopeID: envelopeID,
//             parentID: parentID,
//             message: message,
//             metadata: metadata
//         ))
//     }
// 
//     @discardableResult
//     mutating func appendEnvelope(
//         role: GrokCodeRole,
//         agentRole: GrokCodeAgentRole? = nil,
//         kind: GrokCodeMessageKind = .message,
//         content: String,
//         isEphemeral: Bool = false,
//         metadata: [String: AnyCodable] = [:],
//         includeEvent: Bool = true,
//         store: GrokCodeTranscriptStore? = nil
//     ) throws -> GrokCodeMessageEnvelope {
//         let envelope = GrokCodeMessageEnvelope(
//             parentID: lastEnvelopeID,
//             role: role,
//             agentRole: agentRole,
//             kind: kind,
//             content: content,
//             isEphemeral: isEphemeral,
//             metadata: metadata
//         )
//         if !isEphemeral {
//             try store?.append(envelope)
//             lastEnvelopeID = envelope.id
//         }
//         if includeEvent {
//             events.append(GrokCodeEvent.envelope(envelope, sequence: events.count + 1))
//         }
//         return envelope
//     }
// }
// 
// extension GrokCodeSessionState {
//     var json: [String: AnyCodable] {
//         var data: [String: AnyCodable] = [
//             "sessionId": AnyCodable(id.uuidString),
//             "startedAt": AnyCodable(startedAt.timeIntervalSince1970),
//             "options": AnyCodable(options.json),
//             "queuedCommands": AnyCodable(queue.pending.count),
//             "completedTurns": AnyCodable(completedTurns),
//             "events": AnyCodable(events.map { event in
//                 [
//                     "sequence": AnyCodable(event.sequence),
//                     "kind": AnyCodable(event.kind.rawValue),
//                     "timestamp": AnyCodable(event.timestamp.timeIntervalSince1970),
//                     "role": AnyCodable(event.role.rawValue),
//                     "message": AnyCodable(event.message),
//                     "metadata": AnyCodable(event.metadata)
//                 ]
//             })
//         ]
//         if let settingsBackupPath {
//             data["settingsBackupPath"] = AnyCodable(settingsBackupPath)
//         }
//         if let transcriptPath {
//             data["transcriptPath"] = AnyCodable(transcriptPath)
//         }
//         if let finalAnswer {
//             data["finalAnswer"] = AnyCodable(finalAnswer)
//         }
//         if let restoreErrorMessage {
//             data["restoreError"] = AnyCodable(restoreErrorMessage)
//         }
//         return data
//     }
// }
