// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// extension GrokCodeAgentRole {
//     var agentId: Int {
//         switch self {
//         case .strategy:
//             return 0
//         case .architecture:
//             return 1
//         case .engineering:
//             return 2
//         case .security:
//             return 3
//         }
//     }
//     
//     var slug: String {
//         rawValue
//     }
// 
//     var agentName: String {
//         switch self {
//         case .strategy:
//             return "Grok Code Strategy"
//         case .architecture:
//             return "Grok Code Architecture"
//         case .engineering:
//             return "Grok Code Engineering"
//         case .security:
//             return "Grok Code Security"
//         }
//     }
// 
//     var prompt: String {
//         GrokCodeAgentPrompts.prompt(for: self)
//     }
// 
//     static let reviewOrder: [GrokCodeAgentRole] = [.architecture, .engineering]
//     static let strategyOrder: [GrokCodeAgentRole] = reviewOrder + [.strategy]
// }
