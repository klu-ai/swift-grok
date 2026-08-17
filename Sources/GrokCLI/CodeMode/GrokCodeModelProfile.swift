// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// struct GrokCodeModelProfile: Equatable, Sendable {
//     var mode: GrokMode
// 
//     init(mode: GrokMode = .expert) {
//         self.mode = mode
//     }
// 
//     static let defaultProfile = GrokCodeModelProfile(mode: .expert)
// 
//     static func resolve(_ rawValue: String?, modes: [GrokMode] = GrokMode.knownModes) -> GrokCodeModelProfile {
//         guard let rawValue else {
//             return defaultProfile
//         }
// 
//         let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
//         guard !trimmed.isEmpty else {
//             return defaultProfile
//         }
// 
//         let normalized = normalize(trimmed)
//         if ["beta", "grok-4.3", "grok-43", "4.3", "43", "grok-4.3-beta", "grok-43-beta", "grok-420", "grok-420-computer-use-sa"].contains(normalized) {
//             if let liveBeta = modes.first(where: { normalize($0.id) == normalize(GrokMode.grok43Beta.id) }) {
//                 return GrokCodeModelProfile(mode: liveBeta)
//             }
//             return GrokCodeModelProfile(mode: .grok43Beta)
//         }
// 
//         if normalized == "default" || normalized == "code" {
//             return defaultProfile
//         }
// 
//         let resolved = GrokMode.resolve(trimmed, modes: modes)
//         return GrokCodeModelProfile(mode: resolved)
//     }
// 
//     private static func normalize(_ value: String) -> String {
//         value
//             .lowercased()
//             .replacingOccurrences(of: "_", with: "-")
//             .replacingOccurrences(of: " ", with: "-")
//     }
// }
