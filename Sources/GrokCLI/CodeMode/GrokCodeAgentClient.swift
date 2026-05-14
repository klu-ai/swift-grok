// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// struct GrokCodeAgentInvocation {
//     var role: GrokCodeAgentRole
//     var prompt: String
//     var mode: GrokMode
//     var inputEnvelopeIDs: [UUID]
//     var context: String
//     var temporary: Bool
//     var fileAttachments: [String]
//     var workspaceIds: [String]
//     var disabledConnectorIds: [String]
// 
//     init(
//         role: GrokCodeAgentRole,
//         prompt: String,
//         mode: GrokMode,
//         inputEnvelopeIDs: [UUID] = [],
//         context: String = "",
//         temporary: Bool = true,
//         fileAttachments: [String] = [],
//         workspaceIds: [String] = [],
//         disabledConnectorIds: [String] = []
//     ) {
//         self.role = role
//         self.prompt = prompt
//         self.mode = mode
//         self.inputEnvelopeIDs = inputEnvelopeIDs
//         self.context = context
//         self.temporary = temporary
//         self.fileAttachments = fileAttachments
//         self.workspaceIds = workspaceIds
//         self.disabledConnectorIds = disabledConnectorIds
//     }
// }
// 
// enum GrokCodeAgentEvent {
//     case started(GrokCodeAgentStartedEvent)
//     case delta(GrokCodeAgentDeltaEvent)
//     case completed(GrokCodeAgentCompletedEvent)
// }
// 
// struct GrokCodeAgentStartedEvent: Equatable {
//     var role: GrokCodeAgentRole
//     var modeId: String
//     var inputEnvelopeIDs: [UUID]
// }
// 
// struct GrokCodeAgentDeltaEvent: Equatable {
//     var role: GrokCodeAgentRole
//     var text: String
//     var isThinking: Bool
// }
// 
// struct GrokCodeAgentCompletedEvent: Equatable {
//     var role: GrokCodeAgentRole
//     var text: String
//     var conversationId: String
//     var responseId: String
// }
// 
// protocol GrokCodeAgentClient {
//     func run(_ invocation: GrokCodeAgentInvocation) async throws -> AsyncThrowingStream<GrokCodeAgentEvent, Error>
// }
// 
// struct GrokCodeFallbackAgentClient: GrokCodeAgentClient {
//     private let client: GrokClient
//     private let activatesRoleSettings: Bool
// 
//     init(client: GrokClient, activatesRoleSettings: Bool = true) {
//         self.client = client
//         self.activatesRoleSettings = activatesRoleSettings
//     }
// 
//     func run(_ invocation: GrokCodeAgentInvocation) async throws -> AsyncThrowingStream<GrokCodeAgentEvent, Error> {
//         if activatesRoleSettings {
//             try await activateSettings(for: invocation.role)
//         }
// 
//         let message = Self.message(for: invocation)
//         let responseStream = try await client.streamMessage(
//             message: message,
//             enableReasoning: true,
//             enableDeepSearch: false,
//             disableSearch: false,
//             customInstructions: "",
//             temporary: invocation.temporary,
//             personalityType: .none,
//             modeId: invocation.mode.id,
//             fileAttachments: invocation.fileAttachments,
//             workspaceIds: invocation.workspaceIds,
//             disabledConnectorIds: invocation.disabledConnectorIds
//         )
// 
//         return AsyncThrowingStream<GrokCodeAgentEvent, Error> { continuation in
//             continuation.yield(.started(GrokCodeAgentStartedEvent(
//                 role: invocation.role,
//                 modeId: invocation.mode.id,
//                 inputEnvelopeIDs: invocation.inputEnvelopeIDs
//             )))
// 
//             Task {
//                 var accumulated = ""
//                 var latestConversationId = ""
//                 var latestResponseId = ""
// 
//                 do {
//                     for try await response in responseStream {
//                         latestConversationId = response.conversationId
//                         latestResponseId = response.responseId
// 
//                         if !response.message.isEmpty {
//                             if !response.isThinking {
//                                 accumulated += response.message
//                             }
//                             continuation.yield(.delta(GrokCodeAgentDeltaEvent(
//                                 role: invocation.role,
//                                 text: response.message,
//                                 isThinking: response.isThinking
//                             )))
//                         }
// 
//                         if response.isFinal {
//                             continuation.yield(.completed(GrokCodeAgentCompletedEvent(
//                                 role: invocation.role,
//                                 text: response.message.isEmpty ? accumulated : response.message,
//                                 conversationId: latestConversationId,
//                                 responseId: latestResponseId
//                             )))
//                             continuation.finish()
//                             return
//                         }
//                     }
// 
//                     continuation.yield(.completed(GrokCodeAgentCompletedEvent(
//                         role: invocation.role,
//                         text: accumulated.trimmingCharacters(in: .whitespacesAndNewlines),
//                         conversationId: latestConversationId,
//                         responseId: latestResponseId
//                     )))
//                     continuation.finish()
//                 } catch {
//                     continuation.finish(throwing: error)
//                 }
//             }
//         }
//     }
// 
//     private func activateSettings(for _: GrokCodeAgentRole) async throws {
//         let snapshot = try await client.getUserSettingsSnapshot()
//         let projection = snapshot.projection
//         let activeAgents = GrokAgentSettingsScope.codeModeActiveAgents(
//             existing: projection.activeAgents,
//             codeLibraryAgents: projection.libraryAgents
//         )
// 
//         try await client.updateAgentSettings(
//             agentCustomizations: activeAgents,
//             agentLibraryAgents: projection.libraryAgents
//         )
//     }
// 
//     static func message(for invocation: GrokCodeAgentInvocation) -> String {
//         var sections: [String] = []
// 
//         let trimmedContext = invocation.context.trimmingCharacters(in: .whitespacesAndNewlines)
//         if !trimmedContext.isEmpty {
//             sections += [
//                 "<grok-code-context>",
//                 trimmedContext,
//                 "</grok-code-context>"
//             ]
//         }
// 
//         sections.append("<user instructions>")
//         sections.append(invocation.prompt)
//         sections.append("</user instructions>")
// 
//         return sections.joined(separator: "\n")
//     }
// }
