// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// 
// enum GrokCodeQueuedCommandKind: String, Codable {
//     case userTask
//     case slashCommand
//     case restore
// }
// 
// struct GrokCodeQueuedCommand: Codable, Identifiable {
//     let id: UUID
//     let kind: GrokCodeQueuedCommandKind
//     let text: String
//     let createdAt: Date
// 
//     init(
//         id: UUID = UUID(),
//         kind: GrokCodeQueuedCommandKind,
//         text: String,
//         createdAt: Date = Date()
//     ) {
//         self.id = id
//         self.kind = kind
//         self.text = text
//         self.createdAt = createdAt
//     }
// }
// 
// struct GrokCodeCommandQueue: Codable {
//     private(set) var pending: [GrokCodeQueuedCommand] = []
// 
//     var isEmpty: Bool {
//         pending.isEmpty
//     }
// 
//     mutating func enqueue(_ command: GrokCodeQueuedCommand) {
//         pending.append(command)
//     }
// 
//     mutating func enqueueUserTask(_ task: String) {
//         enqueue(GrokCodeQueuedCommand(kind: .userTask, text: task))
//     }
// 
//     mutating func dequeue() -> GrokCodeQueuedCommand? {
//         guard !pending.isEmpty else {
//             return nil
//         }
//         return pending.removeFirst()
//     }
// }
