// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// enum GrokCodeToolParseResult: Equatable {
//     case request(GrokCodeToolRequest)
//     case failure(GrokCodeToolResult)
// }
// 
// struct GrokCodeToolParser {
//     private struct Envelope: Decodable {
//         let toolCall: GrokCodeToolRequest
// 
//         private enum CodingKeys: String, CodingKey {
//             case toolCall = "tool_call"
//             case localAction = "local_action"
//         }
// 
//         init(from decoder: Decoder) throws {
//             let container = try decoder.container(keyedBy: CodingKeys.self)
//             if let localAction = try container.decodeIfPresent(GrokCodeToolRequest.self, forKey: .localAction) {
//                 self.toolCall = localAction
//                 return
//             }
//             self.toolCall = try container.decode(GrokCodeToolRequest.self, forKey: .toolCall)
//         }
//     }
// 
//     func parse(_ text: String) -> [GrokCodeToolParseResult] {
//         let candidates = toolCallCandidates(in: text)
//         guard !candidates.isEmpty else {
//             return []
//         }
// 
//         return candidates.map { candidate in
//             do {
//                 guard let data = candidate.data(using: .utf8) else {
//                     return .failure(.failure(requestID: syntheticRequestID(), message: "Local action is not valid UTF-8."))
//                 }
//                 let envelope = try JSONDecoder().decode(Envelope.self, from: data)
//                 guard !envelope.toolCall.id.isEmpty else {
//                     return .failure(.failure(requestID: syntheticRequestID(), message: "Local action id is required."))
//                 }
//                 guard !envelope.toolCall.name.isEmpty else {
//                     return .failure(.failure(requestID: envelope.toolCall.id, message: "Local action name is required."))
//                 }
//                 return .request(envelope.toolCall)
//             } catch {
//                 return .failure(.failure(requestID: syntheticRequestID(), message: "Malformed local action JSON: \(error.localizedDescription)"))
//             }
//         }
//     }
// 
//     func requests(in text: String) -> [GrokCodeToolRequest] {
//         parse(text).compactMap { result in
//             if case .request(let request) = result {
//                 return request
//             }
//             return nil
//         }
//     }
// 
//     private func toolCallCandidates(in text: String) -> [String] {
//         let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
//         if isJSONObject(trimmed), containsActionKey(trimmed) {
//             return [trimmed]
//         }
// 
//         var candidates = fencedJSONBlocks(in: text)
//             .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
//             .filter { containsActionKey($0) }
// 
//         candidates += text
//             .split(separator: "\n", omittingEmptySubsequences: false)
//             .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
//             .filter { isJSONObject($0) && containsActionKey($0) }
// 
//         var seen = Set<String>()
//         return candidates.filter { candidate in
//             seen.insert(candidate).inserted
//         }
//     }
// 
//     private func isJSONObject(_ text: String) -> Bool {
//         text.hasPrefix("{") && text.hasSuffix("}")
//     }
// 
//     private func containsActionKey(_ text: String) -> Bool {
//         text.contains("\"local_action\"") || text.contains("\"tool_call\"")
//     }
// 
//     private func fencedJSONBlocks(in text: String) -> [String] {
//         let pattern = #"(?s)```(?:json)?\s*\n(.*?)\n```"#
//         guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
//             return []
//         }
//         let range = NSRange(text.startIndex..<text.endIndex, in: text)
//         return regex.matches(in: text, options: [], range: range).compactMap { match in
//             guard match.numberOfRanges > 1, let blockRange = Range(match.range(at: 1), in: text) else {
//                 return nil
//             }
//             return String(text[blockRange])
//         }
//     }
// 
//     private func syntheticRequestID() -> String {
//         "synthetic_\(UUID().uuidString.lowercased())"
//     }
// }
