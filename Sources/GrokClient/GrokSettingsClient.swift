// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.

// import Foundation
// 
// public struct GrokUserSettingsPatch {
//     public var agentCustomizations: [GrokAgentCustomization]?
//     public var agentLibraryAgents: [GrokAgentLibraryAgent]?
// 
//     public init(
//         agentCustomizations: [GrokAgentCustomization]? = nil,
//         agentLibraryAgents: [GrokAgentLibraryAgent]? = nil
//     ) {
//         self.agentCustomizations = agentCustomizations
//         self.agentLibraryAgents = agentLibraryAgents
//     }
// 
//     var payload: [String: Any] {
//         var payload: [String: Any] = [:]
// 
//         if let agentCustomizations {
//             payload["agentCustomizations"] = [
//                 "values": agentCustomizations
//                     .sorted { $0.agentId < $1.agentId }
//                     .map { customization in
//                         [
//                             "agentId": customization.agentId,
//                             "name": customization.agentId == 0 ? "Grok" : customization.name,
//                             "instructions": customization.instructions
//                         ] as [String: Any]
//                     }
//             ]
//         }
// 
//         if let agentLibraryAgents {
//             payload["agentLibrary"] = [
//                 "agents": agentLibraryAgents.map { agent in
//                     var value = agent.rawJSON.mapValues(\.value)
//                     value["name"] = agent.name
//                     value["instructions"] = agent.instructions
//                     return value
//                 }
//             ]
//         }
// 
//         return payload
//     }
// }
// 
// public struct GrokUserSettingsResponse {
//     public let snapshot: GrokUserSettingsSnapshot
//     public let projection: GrokAgentSettingsProjection
// 
//     public init(snapshot: GrokUserSettingsSnapshot) {
//         self.snapshot = snapshot
//         self.projection = snapshot.projection
//     }
// }
// 
// public extension GrokClient {
//     func getUserSettingsSnapshot() async throws -> GrokUserSettingsSnapshot {
//         let request = try makeRequest(path: "/user-settings", method: "GET", namespace: .root)
//         let json = try await jsonObject(for: request)
//         return GrokUserSettingsSnapshot(rawJSON: AnyCodable(json))
//     }
// 
//     func getFullUserSettingsResponse() async throws -> GrokUserSettingsResponse {
//         let snapshot = try await getUserSettingsSnapshot()
//         return GrokUserSettingsResponse(snapshot: snapshot)
//     }
// 
//     @discardableResult
//     func updateUserSettings(_ patch: GrokUserSettingsPatch) async throws -> GrokUserSettingsResponse {
//         let request = try makeRequest(path: "/user-settings", payload: patch.payload, namespace: .root)
//         let json = try await jsonObject(for: request)
//         return GrokUserSettingsResponse(snapshot: GrokUserSettingsSnapshot(rawJSON: AnyCodable(json)))
//     }
// 
//     @discardableResult
//     func updateAgentSettings(
//         agentCustomizations: [GrokAgentCustomization],
//         agentLibraryAgents: [GrokAgentLibraryAgent]
//     ) async throws -> GrokUserSettingsResponse {
//         try await updateUserSettings(GrokUserSettingsPatch(
//             agentCustomizations: agentCustomizations,
//             agentLibraryAgents: agentLibraryAgents
//         ))
//     }
// }
