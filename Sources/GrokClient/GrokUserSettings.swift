// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.

// import Foundation
// 
// public struct GrokUserSettingsSnapshot: Codable {
//     public let rawJSON: AnyCodable
//     public let fetchedAt: Date
// 
//     public init(rawJSON: AnyCodable, fetchedAt: Date = Date()) {
//         self.rawJSON = rawJSON
//         self.fetchedAt = fetchedAt
//     }
// 
//     public var projection: GrokAgentSettingsProjection {
//         GrokAgentSettingsProjection(snapshot: self)
//     }
// }
// 
// public struct GrokAgentLibraryAgent: Codable, Equatable {
//     public var name: String
//     public var instructions: String
//     public var rawJSON: [String: AnyCodable]
// 
//     public init(name: String, instructions: String, rawJSON: [String: AnyCodable] = [:]) {
//         self.name = name
//         self.instructions = instructions
//         self.rawJSON = rawJSON
//     }
// 
//     private enum CodingKeys: String, CodingKey {
//         case name
//         case instructions
//     }
// 
//     public init(from decoder: Decoder) throws {
//         let rawJSON = (try? [String: AnyCodable](from: decoder)) ?? [:]
//         let container = try decoder.container(keyedBy: CodingKeys.self)
//         self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
//         self.instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
//         self.rawJSON = rawJSON
//     }
// 
//     public func encode(to encoder: Encoder) throws {
//         if rawJSON.isEmpty {
//             var container = encoder.container(keyedBy: CodingKeys.self)
//             try container.encode(name, forKey: .name)
//             try container.encode(instructions, forKey: .instructions)
//             return
//         }
// 
//         var merged = rawJSON
//         merged["name"] = AnyCodable(name)
//         merged["instructions"] = AnyCodable(instructions)
//         try merged.encode(to: encoder)
//     }
// 
//     public static func == (lhs: GrokAgentLibraryAgent, rhs: GrokAgentLibraryAgent) -> Bool {
//         lhs.name == rhs.name && lhs.instructions == rhs.instructions
//     }
// }
// 
// public struct GrokAgentSettingsProjection: Codable, Equatable {
//     public var activeAgents: [GrokAgentCustomization]
//     public var libraryAgents: [GrokAgentLibraryAgent]
// 
//     public init(
//         activeAgents: [GrokAgentCustomization] = [],
//         libraryAgents: [GrokAgentLibraryAgent] = []
//     ) {
//         self.activeAgents = activeAgents
//         self.libraryAgents = libraryAgents
//     }
// 
//     public init(snapshot: GrokUserSettingsSnapshot) {
//         self.init(rawJSON: snapshot.rawJSON)
//     }
// 
//     public init(rawJSON: AnyCodable) {
//         let value = Self.plainValue(rawJSON.value)
//         self.activeAgents = Self.agentCustomizations(from: value)
//         self.libraryAgents = Self.agentLibraryAgents(from: value)
//     }
// 
//     public var agentLibraryPatchValue: [String: Any] {
//         [
//             "agents": libraryAgents.map { agent in
//                 var value = agent.rawJSON.mapValues(\.value)
//                 value["name"] = agent.name
//                 value["instructions"] = agent.instructions
//                 return value
//             }
//         ]
//     }
// 
//     private static func agentCustomizations(from value: Any) -> [GrokAgentCustomization] {
//         agentCustomizationDictionaries(from: value)
//             .compactMap(makeAgentCustomization)
//             .sorted { $0.agentId < $1.agentId }
//     }
// 
//     private static func agentLibraryAgents(from value: Any) -> [GrokAgentLibraryAgent] {
//         guard let library = nestedValue(from: value, path: ["agentLibrary"]) ??
//             nestedValue(from: value, path: ["agent_library"]) else {
//             return []
//         }
// 
//         let agentsValue = nestedValue(from: library, path: ["agents"]) ?? library
//         return dictionaries(from: agentsValue).map { dictionary in
//             let rawJSON = dictionary.mapValues { AnyCodable($0) }
//             let nestedAgent = dictionary["agent"] as? [String: Any]
//             let nestedAgentJSON = nestedAgent.map { $0.mapValues { AnyCodable($0) } }
//             return GrokAgentLibraryAgent(
//                 name: stringValue(rawJSON, keys: ["name"]) ??
//                     nestedAgentJSON.flatMap { stringValue($0, keys: ["name"]) } ??
//                     "",
//                 instructions: stringValue(rawJSON, keys: ["instructions", "customInstructions", "custom_instructions"]) ??
//                     nestedAgentJSON.flatMap { stringValue($0, keys: ["instructions", "customInstructions", "custom_instructions"]) } ??
//                     "",
//                 rawJSON: rawJSON
//             )
//         }
//     }
// 
//     private static func makeAgentCustomization(from dictionary: [String: Any]) -> GrokAgentCustomization? {
//         let rawJSON = dictionary.mapValues { AnyCodable($0) }
//         guard let agentId = intValue(rawJSON, keys: ["agentId", "agent_id", "id"]) else {
//             return nil
//         }
// 
//         let nestedAgent = dictionary["agent"] as? [String: Any]
//         let nestedAgentJSON = nestedAgent.map { $0.mapValues { AnyCodable($0) } }
//         return GrokAgentCustomization(
//             agentId: agentId,
//             name: stringValue(rawJSON, keys: ["name"]) ??
//                 nestedAgentJSON.flatMap { stringValue($0, keys: ["name"]) } ??
//                 GrokAgentCustomization.defaultName(for: agentId),
//             instructions: stringValue(rawJSON, keys: ["instructions", "customInstructions", "custom_instructions"]) ??
//                 nestedAgentJSON.flatMap { stringValue($0, keys: ["instructions", "customInstructions", "custom_instructions"]) } ??
//                 ""
//         )
//     }
// 
//     private static func agentCustomizationDictionaries(from value: Any) -> [[String: Any]] {
//         if let array = value as? [[String: Any]],
//            array.contains(where: isAgentCustomizationDictionary) {
//             return array
//         }
// 
//         if let array = value as? [Any] {
//             let dictionaries = array.compactMap { $0 as? [String: Any] }
//             if dictionaries.contains(where: isAgentCustomizationDictionary) {
//                 return dictionaries
//             }
// 
//             for nested in array {
//                 let found = agentCustomizationDictionaries(from: nested)
//                 if !found.isEmpty {
//                     return found
//                 }
//             }
//         }
// 
//         guard let dictionary = value as? [String: Any] else {
//             return []
//         }
// 
//         for key in ["values", "agentCustomizations", "agent_customizations", "userSettings", "user_settings", "settings", "data", "result", "items"] {
//             guard let nested = dictionary[key] else {
//                 continue
//             }
//             let found = agentCustomizationDictionaries(from: nested)
//             if !found.isEmpty {
//                 return found
//             }
//         }
// 
//         for nested in dictionary.values {
//             let found = agentCustomizationDictionaries(from: nested)
//             if !found.isEmpty {
//                 return found
//             }
//         }
// 
//         return []
//     }
// 
//     private static func isAgentCustomizationDictionary(_ dictionary: [String: Any]) -> Bool {
//         dictionary["agentId"] != nil || dictionary["agent_id"] != nil || dictionary["id"] != nil
//     }
// 
//     private static func dictionaries(from value: Any) -> [[String: Any]] {
//         if let dictionaries = value as? [[String: Any]] {
//             return dictionaries
//         }
//         if let array = value as? [Any] {
//             return array.compactMap { $0 as? [String: Any] }
//         }
//         if let dictionary = value as? [String: Any] {
//             for key in ["agents", "values", "data", "result", "items"] {
//                 if let nested = dictionary[key] {
//                     let found = dictionaries(from: nested)
//                     if !found.isEmpty {
//                         return found
//                     }
//                 }
//             }
//         }
//         return []
//     }
// 
//     private static func nestedValue(from value: Any, path: [String]) -> Any? {
//         guard let first = path.first else {
//             return value
//         }
//         guard let dictionary = value as? [String: Any],
//               let nested = dictionary[first] else {
//             return nil
//         }
//         return nestedValue(from: nested, path: Array(path.dropFirst()))
//     }
// 
//     private static func plainValue(_ value: Any) -> Any {
//         if let codable = value as? AnyCodable {
//             return plainValue(codable.value)
//         }
//         if let dictionary = value as? [String: AnyCodable] {
//             return dictionary.mapValues { plainValue($0.value) }
//         }
//         if let dictionary = value as? [String: Any] {
//             return dictionary.mapValues { plainValue($0) }
//         }
//         if let array = value as? [AnyCodable] {
//             return array.map { plainValue($0.value) }
//         }
//         if let array = value as? [Any] {
//             return array.map { plainValue($0) }
//         }
//         return value
//     }
// 
//     private static func stringValue(_ dictionary: [String: AnyCodable], keys: [String]) -> String? {
//         for key in keys {
//             if let value = dictionary[key]?.value as? String, !value.isEmpty {
//                 return value
//             }
//         }
//         return nil
//     }
// 
//     private static func intValue(_ dictionary: [String: AnyCodable], keys: [String]) -> Int? {
//         for key in keys {
//             switch dictionary[key]?.value {
//             case let value as Bool:
//                 return value ? 1 : 0
//             case let value as Int:
//                 return value
//             case let value as Double:
//                 return Int(value)
//             case let value as String:
//                 return Int(value)
//             default:
//                 continue
//             }
//         }
//         return nil
//     }
// }
// 
// extension GrokAgentCustomization: Equatable {
//     public static func == (lhs: GrokAgentCustomization, rhs: GrokAgentCustomization) -> Bool {
//         lhs.agentId == rhs.agentId &&
//             lhs.name == rhs.name &&
//             lhs.instructions == rhs.instructions
//     }
// }
