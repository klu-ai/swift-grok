// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// protocol GrokCodeSettingsScopeManaging {
//     func enter(options: GrokCodeOptions) async throws -> String?
//     func restore(backupPath: String) async throws
// }
// 
// struct GrokCodeNoopSettingsScopeManager: GrokCodeSettingsScopeManaging {
//     func enter(options: GrokCodeOptions) async throws -> String? {
//         nil
//     }
// 
//     func restore(backupPath: String) async throws {}
// }
// 
// struct GrokCodeSession {
//     private(set) var state: GrokCodeSessionState
//     private let settingsScope: GrokCodeSettingsScopeManaging
//     private let agentClient: (any GrokCodeAgentClient)?
//     private let config: ConfigManager
//     private let toolExecutor: GrokCodeToolExecutor
//     private var lastRateLimitWarning: String?
// 
//     init(
//         options: GrokCodeOptions,
//         settingsScope: GrokCodeSettingsScopeManaging = GrokCodeNoopSettingsScopeManager(),
//         agentClient: (any GrokCodeAgentClient)? = nil,
//         config: ConfigManager = ConfigManager(),
//         toolExecutor: GrokCodeToolExecutor? = nil
//     ) {
//         self.state = GrokCodeSessionState(options: options)
//         self.settingsScope = settingsScope
//         self.agentClient = agentClient
//         self.config = config
//         self.toolExecutor = toolExecutor ?? GrokCodeToolExecutor(
//             permissionController: GrokCodePermissionController(mode: options.permissionMode)
//         )
//         self.lastRateLimitWarning = nil
//     }
// 
//     mutating func run(task: String?) async throws -> GrokCodeSessionState {
//         let transcriptStore = try makeTranscriptStore()
//         state.transcriptPath = transcriptStore.url.path
//         state.appendEvent(
//             kind: .progress,
//             "Grok Code session started",
//             metadata: [
//                 "phase": AnyCodable("session_started"),
//                 "model": AnyCodable(state.options.mode.id),
//                 "permissionMode": AnyCodable(state.options.permissionMode.rawValue),
//                 "transcriptPath": AnyCodable(transcriptStore.url.path)
//             ]
//         )
// 
//         var backupPath: String?
//         var pendingError: Error?
// 
//         do {
//             backupPath = try await settingsScope.enter(options: state.options)
//             state.settingsBackupPath = backupPath
//             state.appendEvent(
//                 kind: .progress,
//                 backupPath == nil ? "Settings scope skipped" : "Settings scope entered",
//                 metadata: backupPath.map {
//                     ["phase": AnyCodable("settings_scope_entered"), "backupPath": AnyCodable($0)]
//                 } ?? ["phase": AnyCodable("settings_scope_skipped")]
//             )
//             await appendRateLimitWarningIfNeeded(phase: "settings_scope_entered")
// 
//             if let task, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                 state.queue.enqueueUserTask(task)
//                 state.appendEvent(kind: .progress, "Queued initial task", metadata: ["phase": AnyCodable("user_task_queued")])
//             }
// 
//             while let command = state.queue.dequeue() {
//                 let maxTurns = max(1, state.options.maxTurns ?? 4)
//                 var didRequestTools = false
//                 repeat {
//                     didRequestTools = try await runTurn(prompt: command.text, transcriptStore: transcriptStore)
//                 } while didRequestTools && state.completedTurns < maxTurns
// 
//                 if didRequestTools && state.completedTurns >= maxTurns {
//                     state.appendEvent(
//                         kind: .progress,
//                         "Max turns reached; leaving queued work pending",
//                         metadata: ["phase": AnyCodable("max_turns_reached")]
//                     )
//                     break
//                 }
//             }
//         } catch {
//             pendingError = error
//         }
// 
//         if let backupPath {
//             do {
//                 try await settingsScope.restore(backupPath: backupPath)
//                 state.appendEvent(
//                     kind: .progress,
//                     "Settings scope restored",
//                     metadata: ["phase": AnyCodable("settings_scope_restored"), "backupPath": AnyCodable(backupPath)]
//                 )
//             } catch {
//                 state.restoreErrorMessage = error.localizedDescription
//                 state.appendEvent(
//                     kind: .error,
//                     "Settings restore failed",
//                     metadata: [
//                         "phase": AnyCodable("settings_restore_failed"),
//                         "backupPath": AnyCodable(backupPath),
//                         "recoveryCommand": AnyCodable("grok code restore --backup \(backupPath)")
//                     ]
//                 )
//                 throw GrokCodeSettingsRestoreError(backupPath: backupPath, cause: error)
//             }
//         }
// 
//         if let pendingError {
//             throw pendingError
//         }
// 
//         return state
//     }
// 
//     private mutating func runTurn(prompt: String, transcriptStore: GrokCodeTranscriptStore) async throws -> Bool {
//         state.completedTurns += 1
//         let userEnvelope = try state.appendEnvelope(
//             role: .user,
//             content: prompt,
//             store: transcriptStore
//         )
//         state.appendEvent(
//             kind: .progress,
//             "Started agent turn",
//             metadata: ["phase": AnyCodable("turn_started"), "turn": AnyCodable(state.completedTurns)]
//         )
// 
//         let context = try makeAgentContext(transcriptStore: transcriptStore)
//         let orchestrator = GrokCodeAgentOrchestrator(agentClient: try makeAgentClient())
//         let request = GrokCodeAgentOrchestrationRequest(
//             prompt: prompt,
//             modelProfile: GrokCodeModelProfile(mode: state.options.mode),
//             inputEnvelopeIDs: [userEnvelope.id],
//             context: context,
//             temporary: state.options.privateMode,
//             agentTimeoutSeconds: state.options.agentTimeoutSeconds
//         )
// 
//         var sawToolCall = false
//         let stream = orchestrator.run(request)
//         for try await event in stream {
//             switch event {
//             case .agent(.started(let started)):
//                 state.appendEvent(
//                     kind: .progress,
//                     "Started \(started.role.agentName)",
//                     agentRole: started.role,
//                     metadata: ["phase": AnyCodable("agent_started"), "mode": AnyCodable(started.modeId)]
//                 )
//                 await appendRateLimitWarningIfNeeded(phase: "agent_started", agentRole: started.role)
//             case .agent(.delta):
//                 continue
//             case .agent(.completed):
//                 continue
//             case .roleCompleted(let role, let output):
//                 try await recordAgentOutput(role: role, output: output, transcriptStore: transcriptStore)
//                 await appendRateLimitWarningIfNeeded(phase: "agent_completed", agentRole: role)
//                 let toolResults = try await executeToolCalls(in: output, transcriptStore: transcriptStore)
//                 sawToolCall = sawToolCall || !toolResults.isEmpty
//             case .completed(let finalText):
//                 if !containsLocalAction(finalText) {
//                     state.finalAnswer = finalText
//                 }
//             }
//         }
// 
//         state.appendEvent(
//             kind: .done,
//             "Completed agent turn",
//             metadata: ["phase": AnyCodable("turn_completed"), "turn": AnyCodable(state.completedTurns)]
//         )
//         return sawToolCall
//     }
// 
//     private mutating func appendRateLimitWarningIfNeeded(
//         phase: String,
//         agentRole: GrokCodeAgentRole? = nil
//     ) async {
//         let app = GrokCLIApp.shared
//         _ = try? app.initializeClient()
//         _ = await app.refreshRateLimitStatus(for: state.options.mode)
//         guard let warning = app.currentRateLimitWarning(for: state.options.mode),
//               warning != lastRateLimitWarning else {
//             return
//         }
// 
//         lastRateLimitWarning = warning
//         state.appendEvent(
//             kind: .warning,
//             warning,
//             agentRole: agentRole,
//             metadata: [
//                 "phase": AnyCodable(phase),
//                 "model": AnyCodable(state.options.mode.id)
//             ]
//         )
//     }
// 
//     private mutating func recordAgentOutput(
//         role: GrokCodeAgentRole,
//         output: String,
//         transcriptStore: GrokCodeTranscriptStore
//     ) async throws {
//         _ = try state.appendEnvelope(
//             role: .assistant,
//             agentRole: role,
//             content: output,
//             includeEvent: !containsLocalAction(output),
//             store: transcriptStore
//         )
//         state.appendEvent(
//             kind: .progress,
//             "Completed \(role.agentName)",
//             agentRole: role,
//             metadata: ["phase": AnyCodable("agent_completed"), "characters": AnyCodable(output.count)]
//         )
//     }
// 
//     @discardableResult
//     private mutating func executeToolCalls(
//         in text: String,
//         transcriptStore: GrokCodeTranscriptStore
//     ) async throws -> [GrokCodeToolResult] {
//         let parseResults = GrokCodeToolParser().parse(text)
//         guard !parseResults.isEmpty else {
//             return []
//         }
// 
//         let context = GrokCodeToolUseContext(permissionMode: state.options.permissionMode)
//         var results: [GrokCodeToolResult] = []
//         results.reserveCapacity(parseResults.count)
// 
//         for parseResult in parseResults {
//             let toolName: String
//             switch parseResult {
//             case .request(let request):
//                 toolName = request.name
//                 _ = try state.appendEnvelope(
//                     role: .tool,
//                     kind: .toolRequest,
//                     content: "\(request.name) \(request.id)",
//                     metadata: [
//                         "tool": AnyCodable(request.name),
//                         "requestID": AnyCodable(request.id)
//                     ],
//                     store: transcriptStore
//                 )
//             case .failure:
//                 toolName = "synthetic"
//             }
// 
//             let result = await toolExecutor.execute(parseResult: parseResult, context: context)
//             results.append(result)
//             let resultText = renderToolResult(result)
//             _ = try state.appendEnvelope(
//                 role: .tool,
//                 kind: .toolResult,
//                 content: resultText,
//                 metadata: [
//                     "requestID": AnyCodable(result.requestID),
//                     "ok": AnyCodable(result.ok),
//                     "tool": AnyCodable(toolName)
//                 ],
//                 store: transcriptStore
//             )
//             state.appendEvent(
//                 kind: result.ok ? .toolResult : .error,
//                 result.ok ? "Tool result" : (result.error ?? "Tool failed"),
//                 role: .tool,
//                 metadata: [
//                     "phase": AnyCodable("tool_result"),
//                     "requestID": AnyCodable(result.requestID),
//                     "ok": AnyCodable(result.ok),
//                     "tool": AnyCodable(toolName)
//                 ]
//             )
//         }
// 
//         return results
//     }
// 
//     private func renderToolResult(_ result: GrokCodeToolResult) -> String {
//         let blocks = result.content.map { block -> String in
//             switch block {
//             case .text(let text):
//                 return text
//             case .json(let json):
//                 guard let data = try? JSONEncoder().encode(json),
//                       let text = String(data: data, encoding: .utf8) else {
//                     return "[json]"
//                 }
//                 return text
//             }
//         }.joined(separator: "\n")
// 
//         guard !result.ok else {
//             return blocks
//         }
// 
//         return [result.error, blocks]
//             .compactMap { $0 }
//             .filter { !$0.isEmpty }
//             .joined(separator: "\n")
//     }
// 
//     private func containsLocalAction(_ text: String) -> Bool {
//         !GrokCodeToolParser().parse(text).isEmpty
//     }
// 
//     private func makeAgentContext(transcriptStore: GrokCodeTranscriptStore) throws -> String {
//         let envelopes = try transcriptStore.readAll()
//         let projected = GrokCodeContextProjector.project(envelopes)
//         let hasToolResults = projected.contains { $0.role == .tool }
//         let transcriptText = projected.map { message in
//             let roleName = message.role == .tool ? "local_action" : message.role.rawValue
//             let role = [roleName, message.agentRole?.rawValue]
//                 .compactMap { $0 }
//                 .joined(separator: ":")
//             return "[\(role)] \(message.content)"
//         }.joined(separator: "\n\n")
//         let nextActionGuidance = hasToolResults ? """
// 
//         <next-action-guidance>
//         The local harness has already returned action results. Move from inspection to the next concrete write_files, write_file, apply_patch, or shell action when enough information exists. Do not repeat an identical read_file/list_files/search action unless the earlier result failed or the path changed.
//         </next-action-guidance>
//         """ : ""
// 
//         return """
//         <local-action-protocol>
//         Do not use Grok hosted actions, hosted command execution, hosted filesystem access, browser actions, search, connectors, or any server-side runtime. You cannot access the user workspace from Grok's servers.
//         To ask the local CLI harness to act on the user's machine, print exactly one fenced JSON block or one single-line JSON object with this inert text shape:
//         {"local_action":{"id":"act_unique_id","name":"search","arguments":{"query":"needle","paths":["Sources"]}}}
// 
//         Available local action names: read_file, list_files, search, git_diff, write_file, write_files, apply_patch, write_plan, shell.
//         Use read_file/list_files/search/git_diff before editing. Use write_files when creating several new standalone files, write_file when creating one standalone file, apply_patch for modifying existing files, and write_plan only for Markdown files under plans/.
//         For tasks that require creating files, editing files, installing packages, running tests, or inspecting command output, your response must contain local_action JSON. Do not present file contents as Markdown as a substitute for a local action envelope.
//         Use write_file with {"path":"relative/path","content":"complete UTF-8 file contents"} to create fixture files.
//         Use write_files with {"files":[{"path":"relative/path","content":"complete UTF-8 file contents"}]} when the task asks for a small project with multiple files.
//         Use apply_patch with {"patch":"*** Begin Patch\\n...\\n*** End Patch"} to create or modify files.
//         If list_files returns [missing] for a target directory that the task asks you to create, the next local_action should usually be write_files, write_file, or apply_patch.
//         Do not say a file was created, updated, installed, tested, or verified until a local action result in the transcript proves it.
//         Every accepted or rejected local action request receives one result in the next turn.
//         </local-action-protocol>
// 
//         <local-context>
//         cwd: \(FileManager.default.currentDirectoryPath)
//         permissionMode: \(state.options.permissionMode.rawValue)
//         </local-context>
//         \(nextActionGuidance)
// 
//         <transcript>
//         \(transcriptText)
//         </transcript>
//         """
//     }
// 
//     private func makeAgentClient() throws -> any GrokCodeAgentClient {
//         if let agentClient {
//             return agentClient
//         }
//         return GrokCodeFallbackAgentClient(
//             client: try GrokCLIApp.shared.initializeClient(),
//             activatesRoleSettings: !state.options.dryRunSettings
//         )
//     }
// 
//     private func makeTranscriptStore() throws -> GrokCodeTranscriptStore {
//         let directory = try config.codeModeSessionsDirectory()
//         let filename = "\(state.id.uuidString.lowercased()).jsonl"
//         return GrokCodeTranscriptStore(url: directory.appendingPathComponent(filename))
//     }
// 
//     static func restoreBackup(
//         path: String,
//         settingsScope: GrokCodeSettingsScopeManaging = GrokCodeNoopSettingsScopeManager()
//     ) async throws -> GrokCodeEvent {
//         try await settingsScope.restore(backupPath: path)
//         return GrokCodeEvent(
//             sequence: 1,
//             kind: .progress,
//             message: "Restore requested",
//             metadata: ["phase": AnyCodable("restore_requested"), "backupPath": AnyCodable(path)]
//         )
//     }
// }
// 
// struct GrokCodeSettingsRestoreError: LocalizedError {
//     let backupPath: String
//     let cause: Error
// 
//     var errorDescription: String? {
//         "Grok Code settings restore failed. Backup: \(backupPath). Run: grok code restore --backup \(backupPath). Cause: \(cause.localizedDescription)"
//     }
// }
