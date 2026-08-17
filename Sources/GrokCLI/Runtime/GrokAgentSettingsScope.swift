// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.

// import Foundation
// import GrokClient
// 
// struct GrokCodeAgentProfile {
//     var agents: [GrokAgentCustomization]
// 
//     init(agents: [GrokAgentCustomization]) {
//         self.agents = agents
//     }
// }
// 
// struct GrokAgentSettingsScope: Codable {
//     let backupPath: String
//     let lockPath: String
//     let settingsHash: String
//     let startedAt: Date
//     let processID: Int32
// 
//     static func enter(
//         client: GrokClient,
//         config: ConfigManager,
//         profile: GrokCodeAgentProfile
//     ) async throws -> GrokAgentSettingsScope {
//         let lockURL = try config.activeCodeModeSettingsScopePath()
//         guard !FileManager.default.fileExists(atPath: lockURL.path) else {
//             throw GrokError.apiError("Grok Code settings scope is already active. Restore or remove \(lockURL.path) before starting another code session.")
//         }
// 
//         _ = try normalizedCodeAgents(from: profile)
//         let codeLibraryAgents = GrokCodeAgentPrompts.libraryAgents
//         let snapshot = try await client.getUserSettingsSnapshot()
//         let projection = snapshot.projection
//         let backupURL = try backupURL(in: config)
//         try writeBackup(snapshot, to: backupURL)
//         let activeCodeAgents = codeModeActiveAgents(
//             existing: projection.activeAgents,
//             codeLibraryAgents: codeLibraryAgents
//         )
// 
//         let libraryAgents = codeModeLibraryAgents(
//             existing: projection.libraryAgents,
//             activeAgents: projection.activeAgents,
//             codeLibraryAgents: codeLibraryAgents,
//             reservedNames: activeCodeAgents.map(\.name)
//         )
// 
//         let scope = GrokAgentSettingsScope(
//             backupPath: backupURL.path,
//             lockPath: lockURL.path,
//             settingsHash: settingsHash(for: snapshot.rawJSON),
//             startedAt: Date(),
//             processID: ProcessInfo.processInfo.processIdentifier
//         )
// 
//         do {
//             try writeLock(scope, to: lockURL)
//             try await client.updateAgentSettings(
//                 agentCustomizations: activeCodeAgents,
//                 agentLibraryAgents: libraryAgents
//             )
//             return scope
//         } catch {
//             try? FileManager.default.removeItem(at: lockURL)
//             throw error
//         }
//     }
// 
//     static func restore(
//         client: GrokClient,
//         backupPath: String,
//         config: ConfigManager? = nil
//     ) async throws {
//         let lockPath: String
//         if let config {
//             lockPath = try config.activeCodeModeSettingsScopePath().path
//         } else {
//             lockPath = ""
//         }
//         let scope = GrokAgentSettingsScope(
//             backupPath: backupPath,
//             lockPath: lockPath,
//             settingsHash: "",
//             startedAt: Date(),
//             processID: ProcessInfo.processInfo.processIdentifier
//         )
//         try await scope.restore(client: client)
//     }
// 
//     func restore(client: GrokClient) async throws {
//         let snapshot = try Self.readBackup(at: URL(fileURLWithPath: backupPath))
//         let projection = snapshot.projection
//         try await client.updateAgentSettings(
//             agentCustomizations: projection.activeAgents,
//             agentLibraryAgents: Self.restoredLibraryAgents(
//                 backupLibraryAgents: projection.libraryAgents,
//                 codeLibraryAgents: GrokCodeAgentPrompts.libraryAgents
//             )
//         )
// 
//         let resolvedLockPath = lockPath.trimmingCharacters(in: .whitespacesAndNewlines)
//         if !resolvedLockPath.isEmpty {
//             try? FileManager.default.removeItem(atPath: resolvedLockPath)
//         }
//     }
// 
//     private static func restoredLibraryAgents(
//         backupLibraryAgents: [GrokAgentLibraryAgent],
//         codeLibraryAgents: [GrokAgentLibraryAgent]
//     ) -> [GrokAgentLibraryAgent] {
//         mergedLibraryAgents(
//             existing: backupLibraryAgents,
//             activeBackupAgents: [],
//             codeLibraryAgents: codeLibraryAgents
//         )
//     }
// 
//     static func codeModeLibraryAgents(
//         existing: [GrokAgentLibraryAgent],
//         activeAgents: [GrokAgentCustomization],
//         codeLibraryAgents: [GrokAgentLibraryAgent],
//         reservedNames: [String] = []
//     ) -> [GrokAgentLibraryAgent] {
//         mergedLibraryAgents(
//             existing: existing,
//             activeBackupAgents: backupLibraryAgents(
//                 from: activeAgents,
//                 reservedNames: existing.map(\.name) + reservedNames
//             ),
//             codeLibraryAgents: codeLibraryAgents
//         )
//     }
// 
//     private static func normalizedCodeAgents(from profile: GrokCodeAgentProfile) throws -> [GrokAgentCustomization] {
//         let agents = profile.agents.sorted { $0.agentId < $1.agentId }
//         let ids = agents.map(\.agentId)
//         guard ids == [0, 1, 2, 3] else {
//             throw GrokError.apiError("Grok Code agent profile must include exactly agent IDs 0, 1, 2, and 3.")
//         }
//         return agents
//     }
// 
//     private static func normalizedCodeLibraryAgents(from profile: GrokCodeAgentProfile) -> [GrokAgentLibraryAgent] {
//         let byId = Dictionary(uniqueKeysWithValues: profile.agents.map { ($0.agentId, $0) })
// 
//         return GrokCodeAgentRole.allCases.map { role in
//             let fallback = byId[role.agentId]
//             return GrokAgentLibraryAgent(
//                 name: role.agentName,
//                 instructions: fallback?.instructions ?? role.prompt
//             )
//         }
//     }
// 
//     static func codeModeActiveAgents(
//         existing: [GrokAgentCustomization],
//         codeLibraryAgents: [GrokAgentLibraryAgent]
//     ) -> [GrokAgentCustomization] {
//         let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.agentId, $0) })
//         let preservedGrok = existingById[0] ?? GrokAgentCustomization(
//             agentId: 0,
//             name: "Grok",
//             instructions: ""
//         )
//         let architecture = codeModeAgent(agentId: 1, role: .architecture, libraryAgents: codeLibraryAgents)
//         let engineering = codeModeAgent(agentId: 2, role: .engineering, libraryAgents: codeLibraryAgents)
//         let strategy = codeModeAgent(agentId: 3, role: .strategy, libraryAgents: codeLibraryAgents)
// 
//         return [preservedGrok, architecture, engineering, strategy]
//     }
// 
//     private static func codeModeAgent(
//         agentId: Int,
//         role: GrokCodeAgentRole,
//         libraryAgents: [GrokAgentLibraryAgent]
//     ) -> GrokAgentCustomization {
//         let byName = Dictionary(uniqueKeysWithValues: libraryAgents.map { ($0.name, $0) })
//         let libraryAgent = byName[role.agentName]
//         return GrokAgentCustomization(
//             agentId: agentId,
//             name: libraryAgent?.name ?? role.agentName,
//             instructions: libraryAgent?.instructions ?? role.prompt
//         )
//     }
// 
//     private static func mergedLibraryAgents(
//         existing: [GrokAgentLibraryAgent],
//         activeBackupAgents: [GrokAgentLibraryAgent],
//         codeLibraryAgents: [GrokAgentLibraryAgent]
//     ) -> [GrokAgentLibraryAgent] {
//         var merged: [GrokAgentLibraryAgent] = []
//         let backupPrefixes = legacyBackupNamePrefixes()
// 
//         for agent in existing {
//             guard !codeLibraryAgents.contains(where: { $0.name == agent.name }) else {
//                 continue
//             }
//             guard !backupPrefixes.contains(where: { agent.name.hasPrefix($0) }) else {
//                 continue
//             }
//             appendIfMissing(agent, to: &merged)
//         }
// 
//         for agent in activeBackupAgents {
//             appendIfMissing(agent, to: &merged)
//         }
// 
//         for agent in codeLibraryAgents {
//             appendIfMissing(agent, to: &merged)
//         }
// 
//         return merged
//     }
// 
//     private static func backupLibraryAgents(
//         from activeAgents: [GrokAgentCustomization],
//         reservedNames: [String]
//     ) -> [GrokAgentLibraryAgent] {
//         var usedNames = Set(reservedNames)
//         return activeAgents
//             .sorted { $0.agentId < $1.agentId }
//             .map { agent in
//                 let name = backupName(for: agent, usedNames: &usedNames)
//                 return GrokAgentLibraryAgent(
//                     name: name,
//                     instructions: agent.instructions
//                 )
//             }
//     }
// 
//     private static func legacyBackupNamePrefixes() -> [String] {
//         (0...3).flatMap { agentId in
//             [
//                 "GCBak\(agentId) ",
//                 "Grok Code Backup \(agentId) "
//             ]
//         }
//     }
// 
//     private static func backupName(for agent: GrokAgentCustomization, usedNames: inout Set<String>) -> String {
//         let fallbackName = GrokAgentCustomization.defaultName(for: agent.agentId)
//         let trimmedName = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
//         let preferredName = String((trimmedName.isEmpty ? fallbackName : trimmedName).prefix(32))
//         if !usedNames.contains(preferredName) {
//             usedNames.insert(preferredName)
//             return preferredName
//         }
// 
//         let namedBackup = String("\(preferredName) Backup".prefix(32))
//         if namedBackup != preferredName, !usedNames.contains(namedBackup) {
//             usedNames.insert(namedBackup)
//             return namedBackup
//         }
// 
//         let fallbackBackupName = String("Grok Code Backup \(agent.agentId)".prefix(32))
//         if !usedNames.contains(fallbackBackupName) {
//             usedNames.insert(fallbackBackupName)
//             return fallbackBackupName
//         }
// 
//         let uniqueName = String("Grok Code Backup \(agent.agentId) \(UUID().uuidString.prefix(4))".prefix(32))
//         usedNames.insert(uniqueName)
//         return uniqueName
//     }
// 
//     private static func appendIfMissing(_ agent: GrokAgentLibraryAgent, to agents: inout [GrokAgentLibraryAgent]) {
//         guard !agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
//             return
//         }
//         guard !agents.contains(where: { $0.name == agent.name }) else {
//             return
//         }
//         agents.append(agent)
//     }
// 
//     private static func backupURL(in config: ConfigManager) throws -> URL {
//         let directory = try config.codeModeSettingsBackupsDirectory()
//         let formatter = ISO8601DateFormatter()
//         formatter.formatOptions = [.withInternetDateTime]
//         let timestamp = formatter.string(from: Date())
//             .replacingOccurrences(of: ":", with: "-")
//         return directory.appendingPathComponent("\(timestamp)-user-settings.json")
//     }
// 
//     private static func writeBackup(_ snapshot: GrokUserSettingsSnapshot, to url: URL) throws {
//         let encoder = JSONEncoder()
//         encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
//         encoder.dateEncodingStrategy = .iso8601
//         let data = try encoder.encode(snapshot)
//         try data.write(to: url, options: [.atomic])
//         try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
//     }
// 
//     private static func readBackup(at url: URL) throws -> GrokUserSettingsSnapshot {
//         let data = try Data(contentsOf: url)
//         let decoder = JSONDecoder()
//         decoder.dateDecodingStrategy = .iso8601
//         return try decoder.decode(GrokUserSettingsSnapshot.self, from: data)
//     }
// 
//     private static func writeLock(_ scope: GrokAgentSettingsScope, to url: URL) throws {
//         let encoder = JSONEncoder()
//         encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
//         encoder.dateEncodingStrategy = .iso8601
//         let data = try encoder.encode(scope)
//         try data.write(to: url, options: [.atomic])
//         try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
//     }
// 
//     private static func settingsHash(for rawJSON: AnyCodable) -> String {
//         let data = (try? JSONEncoder().encode(rawJSON)) ?? Data()
//         var hash: UInt64 = 14_695_981_039_346_656_037
//         for byte in data {
//             hash ^= UInt64(byte)
//             hash &*= 1_099_511_628_211
//         }
//         return String(format: "%016llx", hash)
//     }
// }
