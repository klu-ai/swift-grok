// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// struct GrokCodeAgentOrchestrationRequest {
//     var prompt: String
//     var modelProfile: GrokCodeModelProfile
//     var inputEnvelopeIDs: [UUID]
//     var context: String
//     var temporary: Bool
//     var fileAttachments: [String]
//     var workspaceIds: [String]
//     var disabledConnectorIds: [String]
//     var agentTimeoutSeconds: Double?
// 
//     init(
//         prompt: String,
//         modelProfile: GrokCodeModelProfile = .defaultProfile,
//         inputEnvelopeIDs: [UUID] = [],
//         context: String = "",
//         temporary: Bool = true,
//         fileAttachments: [String] = [],
//         workspaceIds: [String] = [],
//         disabledConnectorIds: [String] = [],
//         agentTimeoutSeconds: Double? = nil
//     ) {
//         self.prompt = prompt
//         self.modelProfile = modelProfile
//         self.inputEnvelopeIDs = inputEnvelopeIDs
//         self.context = context
//         self.temporary = temporary
//         self.fileAttachments = fileAttachments
//         self.workspaceIds = workspaceIds
//         self.disabledConnectorIds = disabledConnectorIds
//         self.agentTimeoutSeconds = agentTimeoutSeconds
//     }
// }
// 
// enum GrokCodeOrchestratorEvent {
//     case agent(GrokCodeAgentEvent)
//     case roleCompleted(GrokCodeAgentRole, String)
//     case completed(String)
// }
// 
// struct GrokCodeAgentOrchestrator {
//     private let agentClient: GrokCodeAgentClient
// 
//     init(agentClient: GrokCodeAgentClient) {
//         self.agentClient = agentClient
//     }
// 
//     func run(_ request: GrokCodeAgentOrchestrationRequest) -> AsyncThrowingStream<GrokCodeOrchestratorEvent, Error> {
//         AsyncThrowingStream<GrokCodeOrchestratorEvent, Error> { continuation in
//             Task {
//                 do {
//                     var feedback: [GrokCodeAgentRole: String] = [:]
// 
//                     let reviewRoles = reviewRoles(for: request.context)
//                     for role in reviewRoles {
//                         let output = try await runRoleWithTimeout(role, request: request, context: request.context, continuation: continuation)
//                         feedback[role] = output
//                         continuation.yield(.roleCompleted(role, output))
//                         if containsToolCall(output) {
//                             continuation.yield(.completed(output))
//                             continuation.finish()
//                             return
//                         }
//                     }
// 
//                     let strategyContext = strategyContext(baseContext: request.context, feedback: feedback)
//                     let strategyOutput = try await runRoleWithTimeout(.strategy, request: request, context: strategyContext, continuation: continuation)
//                     continuation.yield(.roleCompleted(.strategy, strategyOutput))
//                     continuation.yield(.completed(strategyOutput))
//                     continuation.finish()
//                 } catch {
//                     continuation.finish(throwing: error)
//                 }
//             }
//         }
//     }
// 
//     private func runRole(
//         _ role: GrokCodeAgentRole,
//         request: GrokCodeAgentOrchestrationRequest,
//         context: String,
//         continuation: AsyncThrowingStream<GrokCodeOrchestratorEvent, Error>.Continuation
//     ) async throws -> String {
//         let invocation = GrokCodeAgentInvocation(
//             role: role,
//             prompt: request.prompt,
//             mode: request.modelProfile.mode,
//             inputEnvelopeIDs: request.inputEnvelopeIDs,
//             context: context,
//             temporary: request.temporary,
//             fileAttachments: request.fileAttachments,
//             workspaceIds: request.workspaceIds,
//             disabledConnectorIds: request.disabledConnectorIds
//         )
//         let stream = try await agentClient.run(invocation)
// 
//         var latestCompleted = ""
//         var accumulated = ""
//         for try await event in stream {
//             continuation.yield(.agent(event))
//             switch event {
//             case .started:
//                 break
//             case .delta(let delta):
//                 if !delta.isThinking {
//                     accumulated += delta.text
//                 }
//             case .completed(let completed):
//                 latestCompleted = completed.text
//             }
//         }
// 
//         let trimmedCompleted = latestCompleted.trimmingCharacters(in: .whitespacesAndNewlines)
//         if !trimmedCompleted.isEmpty {
//             return trimmedCompleted
//         }
//         return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
//     }
// 
//     private func runRoleWithTimeout(
//         _ role: GrokCodeAgentRole,
//         request: GrokCodeAgentOrchestrationRequest,
//         context: String,
//         continuation: AsyncThrowingStream<GrokCodeOrchestratorEvent, Error>.Continuation
//     ) async throws -> String {
//         guard let timeout = request.agentTimeoutSeconds, timeout > 0 else {
//             return try await runRole(role, request: request, context: context, continuation: continuation)
//         }
// 
//         return try await withThrowingTaskGroup(of: String.self) { group in
//             group.addTask {
//                 try await runRole(role, request: request, context: context, continuation: continuation)
//             }
//             group.addTask {
//                 let nanoseconds = UInt64(min(timeout, 3_600) * 1_000_000_000)
//                 try await Task.sleep(nanoseconds: nanoseconds)
//                 throw GrokCodeAgentTimeoutError(role: role, seconds: timeout)
//             }
// 
//             let output = try await group.next() ?? ""
//             group.cancelAll()
//             return output
//         }
//     }
// 
//     private func containsToolCall(_ output: String) -> Bool {
//         !GrokCodeToolParser().parse(output).isEmpty
//     }
// 
//     private func strategyContext(baseContext: String, feedback: [GrokCodeAgentRole: String]) -> String {
//         var sections: [String] = []
//         let trimmedBase = baseContext.trimmingCharacters(in: .whitespacesAndNewlines)
//         if !trimmedBase.isEmpty {
//             sections.append(trimmedBase)
//         }
// 
//         for role in GrokCodeAgentRole.reviewOrder {
//             guard let output = feedback[role]?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
//                 continue
//             }
//             sections.append("""
//             <\(role.slug)-feedback>
//             \(output)
//             </\(role.slug)-feedback>
//             """)
//         }
// 
//         return sections.joined(separator: "\n\n")
//     }
// 
//     private func reviewRoles(for context: String) -> [GrokCodeAgentRole] {
//         if context.contains("[tool]") {
//             return [.engineering]
//         }
//         return GrokCodeAgentRole.reviewOrder
//     }
// }
// 
// struct GrokCodeAgentTimeoutError: LocalizedError {
//     let role: GrokCodeAgentRole
//     let seconds: Double
// 
//     var errorDescription: String? {
//         "\(role.agentName) timed out after \(Int(seconds.rounded())) seconds"
//     }
// }
