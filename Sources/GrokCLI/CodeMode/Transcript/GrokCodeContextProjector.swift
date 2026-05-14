// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// struct GrokCodeProjectionOptions: Equatable {
//     var maxMessages: Int
//     var maxTotalCharacters: Int
//     var maxContentCharacters: Int
//     var includeEphemeral: Bool
//     var redactSensitiveValues: Bool
// 
//     static let `default` = GrokCodeProjectionOptions(
//         maxMessages: 80,
//         maxTotalCharacters: 48_000,
//         maxContentCharacters: 8_000,
//         includeEphemeral: false,
//         redactSensitiveValues: true
//     )
// }
// 
// struct GrokCodeProjectedMessage: Codable, Equatable {
//     var id: UUID
//     var parentID: UUID?
//     var role: GrokCodeRole
//     var agentRole: GrokCodeAgentRole?
//     var kind: GrokCodeMessageKind
//     var content: String
//     var wasTruncated: Bool
// }
// 
// enum GrokCodeContextProjector {
//     static func project(
//         _ envelopes: [GrokCodeMessageEnvelope],
//         options: GrokCodeProjectionOptions = .default
//     ) -> [GrokCodeProjectedMessage] {
//         guard options.maxMessages > 0, options.maxTotalCharacters > 0 else {
//             return []
//         }
// 
//         let visible = envelopes
//             .filter { options.includeEphemeral || !$0.isEphemeral }
//             .suffix(options.maxMessages)
// 
//         var projectedReversed: [GrokCodeProjectedMessage] = []
//         var remainingCharacters = options.maxTotalCharacters
// 
//         for envelope in visible.reversed() {
//             guard remainingCharacters > 0 else { break }
// 
//             var content = envelope.content
//             if options.redactSensitiveValues {
//                 content = redact(content)
//             }
// 
//             let capped = cap(content, limit: min(options.maxContentCharacters, remainingCharacters))
//             remainingCharacters -= capped.value.count
// 
//             projectedReversed.append(GrokCodeProjectedMessage(
//                 id: envelope.id,
//                 parentID: envelope.parentID,
//                 role: envelope.role,
//                 agentRole: envelope.agentRole,
//                 kind: envelope.kind,
//                 content: capped.value,
//                 wasTruncated: capped.truncated
//             ))
//         }
// 
//         return projectedReversed.reversed()
//     }
// 
//     private static func cap(_ value: String, limit: Int) -> (value: String, truncated: Bool) {
//         guard limit > 0 else {
//             return ("", !value.isEmpty)
//         }
//         guard value.count > limit else {
//             return (value, false)
//         }
// 
//         let suffix = "\n[output truncated]"
//         let budget = max(0, limit - suffix.count)
//         return (String(value.prefix(budget)) + suffix, true)
//     }
// 
//     static func redact(_ value: String) -> String {
//         var redacted = value
//         let patterns = [
//             #"(?i)(authorization:\s*bearer\s+)[^\s]+"#,
//             #"(?i)(cookie:\s*)[^\n\r]+"#,
//             #"(?i)((?:api[_-]?key|token|password|secret)\s*[:=]\s*)[^\s'"]+"#
//         ]
// 
//         for pattern in patterns {
//             redacted = replaceMatches(in: redacted, pattern: pattern) { captures in
//                 captures.count > 1 ? captures[1] + "[REDACTED]" : "[REDACTED]"
//             }
//         }
//         return redacted
//     }
// 
//     private static func replaceMatches(
//         in value: String,
//         pattern: String,
//         replacement: ([String]) -> String
//     ) -> String {
//         guard let regex = try? NSRegularExpression(pattern: pattern) else {
//             return value
//         }
// 
//         let nsValue = value as NSString
//         let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed()
//         var result = value
//         for match in matches {
//             let captures = (0..<match.numberOfRanges).map { index -> String in
//                 let range = match.range(at: index)
//                 guard range.location != NSNotFound else { return "" }
//                 return nsValue.substring(with: range)
//             }
//             if let range = Range(match.range, in: result) {
//                 result.replaceSubrange(range, with: replacement(captures))
//             }
//         }
//         return result
//     }
// }
