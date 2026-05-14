// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// import Rainbow
// 
// extension GrokCLI {
//     static func handleCodeCommand(args: [String], exitOnError: Bool = false) async throws {
//         if args.count == 1, let first = args.first, isHelpArgument(first) {
//             printCodeUsage()
//             return
//         }
// 
//         do {
//             let invocation = try parseCodeInvocation(args)
//             try await runCodeInvocation(invocation)
//         } catch let error as GrokCodeUsageError {
//             reportCodeUsageError(
//                 error.message,
//                 jsonRequested: isJSONRequested(args),
//                 exitOnError: exitOnError
//             )
//             if exitOnError {
//                 exit(with: 2)
//             }
//         } catch {
//             if isJSONRequested(args) {
//                 printJSONError(command: "code", error: error, exitCode: 1)
//             } else {
//                 print("Error: \(error.localizedDescription)".red)
//             }
//             if exitOnError {
//                 exit(with: 1)
//             }
//         }
//     }
// 
//     static func parseCodeInvocation(_ args: [String]) throws -> GrokCodeInvocation {
//         var options = GrokCodeOptions()
//         var taskWords: [String] = []
// 
//         if args.first?.lowercased() == "restore" {
//             var backupPath: String?
//             var outputFormat = OutputFormat.defaultFormat
//             var index = 1
//             while index < args.count {
//                 let arg = args[index]
//                 let nextValue = index + 1 < args.count ? args[index + 1] : nil
// 
//                 let outputFormatOption = applyOutputFormatOption(arg, nextValue: nextValue)
//                 if outputFormatOption.missingValue {
//                     throw GrokCodeUsageError("\(arg) requires a format value")
//                 } else if let invalidValue = outputFormatOption.invalidValue {
//                     throw GrokCodeUsageError("Invalid output format '\(invalidValue)'. Use md, raw, or json.")
//                 } else if let format = outputFormatOption.format {
//                     outputFormat = format
//                     index += outputFormatOption.consumedNext ? 2 : 1
//                     continue
//                 }
// 
//                 if arg == "--backup" {
//                     guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
//                         throw GrokCodeUsageError("restore --backup requires a path")
//                     }
//                     backupPath = nextValue
//                     index += 2
//                 } else if arg.hasPrefix("--backup=") {
//                     let value = String(arg.dropFirst("--backup=".count))
//                     guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
//                         throw GrokCodeUsageError("restore --backup requires a path")
//                     }
//                     backupPath = value
//                     index += 1
//                 } else if arg == "--json" {
//                     outputFormat = .json
//                     index += 1
//                 } else {
//                     throw GrokCodeUsageError("Unknown code restore option: \(arg)")
//                 }
//             }
// 
//             guard let backupPath else {
//                 throw GrokCodeUsageError("restore --backup requires a path")
//             }
//             return .restoreBackup(path: backupPath, outputFormat: outputFormat)
//         }
// 
//         var index = 0
//         while index < args.count {
//             let arg = args[index]
//             let nextValue = index + 1 < args.count ? args[index + 1] : nil
// 
//             let modelOption = applyModelOption(arg, nextValue: nextValue)
//             if modelOption.missingValue {
//                 throw GrokCodeUsageError("\(arg) requires a model value")
//             } else if let mode = modelOption.mode {
//                 options.mode = mode
//                 index += modelOption.consumedNext ? 2 : 1
//                 continue
//             }
// 
//             let outputFormatOption = applyOutputFormatOption(arg, nextValue: nextValue)
//             if outputFormatOption.missingValue {
//                 throw GrokCodeUsageError("\(arg) requires a format value")
//             } else if let invalidValue = outputFormatOption.invalidValue {
//                 throw GrokCodeUsageError("Invalid output format '\(invalidValue)'. Use md, raw, or json.")
//             } else if let format = outputFormatOption.format {
//                 options.outputFormat = format
//                 index += outputFormatOption.consumedNext ? 2 : 1
//                 continue
//             }
// 
//             if arg == "--json" {
//                 options.outputFormat = .json
//             } else if arg == "--private" {
//                 options.privateMode = true
//             } else if arg == "--dry-run-settings" {
//                 options.dryRunSettings = true
//             } else if arg == "--prompt-file" {
//                 guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nextValue.hasPrefix("--") else {
//                     throw GrokCodeUsageError("--prompt-file requires a path")
//                 }
//                 options.promptFile = nextValue
//                 index += 1
//             } else if arg.hasPrefix("--prompt-file=") {
//                 let value = String(arg.dropFirst("--prompt-file=".count))
//                 guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
//                     throw GrokCodeUsageError("--prompt-file requires a path")
//                 }
//                 options.promptFile = value
//             } else if arg == "--permission-mode" {
//                 guard let nextValue, let mode = GrokCodePermissionMode.resolve(nextValue) else {
//                     throw GrokCodeUsageError("--permission-mode requires one of: \(GrokCodePermissionMode.codeUsageValues)")
//                 }
//                 options.permissionMode = mode
//                 index += 1
//             } else if arg.hasPrefix("--permission-mode=") {
//                 let value = String(arg.dropFirst("--permission-mode=".count))
//                 guard let mode = GrokCodePermissionMode.resolve(value) else {
//                     throw GrokCodeUsageError("--permission-mode requires one of: \(GrokCodePermissionMode.codeUsageValues)")
//                 }
//                 options.permissionMode = mode
//             } else if arg == "--max-turns" {
//                 guard let nextValue, let turns = Int(nextValue), turns > 0 else {
//                     throw GrokCodeUsageError("--max-turns requires a positive integer")
//                 }
//                 options.maxTurns = turns
//                 index += 1
//             } else if arg.hasPrefix("--max-turns=") {
//                 let value = String(arg.dropFirst("--max-turns=".count))
//                 guard let turns = Int(value), turns > 0 else {
//                     throw GrokCodeUsageError("--max-turns requires a positive integer")
//                 }
//                 options.maxTurns = turns
//             } else if arg == "--agent-timeout-seconds" {
//                 guard let nextValue, let seconds = Double(nextValue), seconds > 0 else {
//                     throw GrokCodeUsageError("--agent-timeout-seconds requires a positive number")
//                 }
//                 options.agentTimeoutSeconds = seconds
//                 index += 1
//             } else if arg.hasPrefix("--agent-timeout-seconds=") {
//                 let value = String(arg.dropFirst("--agent-timeout-seconds=".count))
//                 guard let seconds = Double(value), seconds > 0 else {
//                     throw GrokCodeUsageError("--agent-timeout-seconds requires a positive number")
//                 }
//                 options.agentTimeoutSeconds = seconds
//             } else if arg.hasPrefix("-") {
//                 throw GrokCodeUsageError("Unknown code option: \(arg)")
//             } else {
//                 taskWords.append(arg)
//             }
// 
//             index += 1
//         }
// 
//         let inlineTask = taskWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
//         let fileTask = try options.promptFile.map { try readPromptFile($0) }?
//             .trimmingCharacters(in: .whitespacesAndNewlines)
//         if fileTask != nil, !inlineTask.isEmpty {
//             throw GrokCodeUsageError("Use either --prompt-file or inline task args, not both")
//         }
// 
//         let task = fileTask ?? inlineTask
//         if task.isEmpty {
//             return .interactive(options)
//         }
//         return .print(options, task: task)
//     }
// 
//     private static func runCodeInvocation(_ invocation: GrokCodeInvocation) async throws {
//         switch invocation {
//         case .interactive(let options):
//             var session = GrokCodeSession(options: options, settingsScope: GrokCodeAgentSettingsScopeManager())
//             let state = try await session.run(task: nil)
//             try printCodeState(state, task: nil)
//         case .print(let options, let task):
//             var session = GrokCodeSession(options: options, settingsScope: GrokCodeAgentSettingsScopeManager())
//             let state = try await session.run(task: task)
//             try printCodeState(state, task: task)
//         case .restoreBackup(let path, let outputFormat):
//             let event = try await GrokCodeSession.restoreBackup(path: path, settingsScope: GrokCodeAgentSettingsScopeManager())
//             if outputFormat.isJSON {
//                 try printJSONResult(
//                     command: "code",
//                     category: "settings_restore",
//                     data: AnyCodable([
//                         "backupPath": AnyCodable(path),
//                         "event": AnyCodable(event.kind.rawValue),
//                         "message": AnyCodable(event.message)
//                     ])
//                 )
//             } else {
//                 print("Grok Code settings restore requested.")
//                 print("Backup: \(path)")
//             }
//         }
//     }
// 
//     private static func printCodeState(_ state: GrokCodeSessionState, task: String?) throws {
//         if state.options.outputFormat.isJSON {
//             var data = state.json
//             if let task {
//                 data["task"] = AnyCodable(task)
//             }
//             try printJSONResult(command: "code", category: "code_session", data: AnyCodable(data))
//             return
//         }
// 
//         print("Grok Code".green.bold)
//         print("model \(state.options.mode.id) | permission \(state.options.permissionMode.rawValue) | format \(state.options.outputFormat.statusName)")
//         if state.options.privateMode {
//             print("private mode enabled")
//         }
//         if state.options.dryRunSettings {
//             print("dry-run settings enabled")
//         }
//         if let task {
//             print("task: \(String(task.prefix(240)))")
//         }
//         let warnings = state.events
//             .filter { $0.kind == .warning }
//             .map(\.message)
//         for warning in Array(Set(warnings)).sorted() {
//             print(warning.yellow)
//         }
//         if let answer = state.finalAnswer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//             print("")
//             OutputFormatter(format: state.options.outputFormat).printQuietResponseBody(answer)
//         }
//         if let transcriptPath = state.transcriptPath {
//             print("transcript: \(transcriptPath)")
//         }
//         if let restoreError = state.restoreErrorMessage {
//             print("settings restore error: \(restoreError)".red)
//         }
//     }
// 
//     static func reportCodeUsageError(_ message: String, jsonRequested: Bool, exitOnError _: Bool) {
//         if jsonRequested {
//             printJSONError(
//                 command: "code",
//                 message: message,
//                 code: "usage_error",
//                 exitCode: 2
//             )
//         } else {
//             print("Error: \(message)".red)
//         }
//     }
// }
// 
// struct GrokCodeUsageError: LocalizedError {
//     let message: String
// 
//     init(_ message: String) {
//         self.message = message
//     }
// 
//     var errorDescription: String? {
//         message
//     }
// }
// 
// struct GrokCodeAgentSettingsScopeManager: GrokCodeSettingsScopeManaging {
//     func enter(options: GrokCodeOptions) async throws -> String? {
//         guard !options.dryRunSettings else {
//             return nil
//         }
// 
//         let client = try GrokCLIApp.shared.initializeClient()
//         let scope = try await GrokAgentSettingsScope.enter(
//             client: client,
//             config: ConfigManager(),
//             profile: GrokCodeAgentProfile(agents: GrokCodeAgentPrompts.activeAgentCustomizations)
//         )
//         return scope.backupPath
//     }
// 
//     func restore(backupPath: String) async throws {
//         let client = try GrokCLIApp.shared.initializeClient()
//         try await GrokAgentSettingsScope.restore(
//             client: client,
//             backupPath: backupPath,
//             config: ConfigManager()
//         )
//     }
// }
