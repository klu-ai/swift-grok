// Grok Code is disabled: the code harness concept will not work with grok.com because tool calls happen server side.
// import Foundation
// import GrokClient
// 
// enum GrokCodeToolError: Error, LocalizedError, Equatable {
//     case invalidInput(String)
//     case permissionDenied(String)
//     case executionFailed(String)
//     case outputLimitExceeded(String)
// 
//     var errorDescription: String? {
//         switch self {
//         case .invalidInput(let message),
//              .permissionDenied(let message),
//              .executionFailed(let message),
//              .outputLimitExceeded(let message):
//             return message
//         }
//     }
// }
// 
// enum GrokCodeContentBlock: Codable, Equatable {
//     case text(String)
//     case json(AnyCodable)
// 
//     private enum CodingKeys: String, CodingKey {
//         case type
//         case text
//         case json
//     }
// 
//     init(from decoder: Decoder) throws {
//         let container = try decoder.container(keyedBy: CodingKeys.self)
//         let type = try container.decode(String.self, forKey: .type)
//         switch type {
//         case "text":
//             self = .text(try container.decode(String.self, forKey: .text))
//         case "json":
//             self = .json(try container.decode(AnyCodable.self, forKey: .json))
//         default:
//             throw DecodingError.dataCorruptedError(
//                 forKey: .type,
//                 in: container,
//                 debugDescription: "Unsupported content block type '\(type)'"
//             )
//         }
//     }
// 
//     func encode(to encoder: Encoder) throws {
//         var container = encoder.container(keyedBy: CodingKeys.self)
//         switch self {
//         case .text(let text):
//             try container.encode("text", forKey: .type)
//             try container.encode(text, forKey: .text)
//         case .json(let json):
//             try container.encode("json", forKey: .type)
//             try container.encode(json, forKey: .json)
//         }
//     }
// 
//     static func == (lhs: GrokCodeContentBlock, rhs: GrokCodeContentBlock) -> Bool {
//         switch (lhs, rhs) {
//         case (.text(let lhsText), .text(let rhsText)):
//             return lhsText == rhsText
//         case (.json(let lhsJSON), .json(let rhsJSON)):
//             return GrokCodeJSONEquivalence.equal(lhsJSON, rhsJSON)
//         default:
//             return false
//         }
//     }
// }
// 
// struct GrokCodeToolRequest: Codable, Equatable {
//     var id: String
//     var name: String
//     var arguments: [String: AnyCodable]
// 
//     init(id: String, name: String, arguments: [String: AnyCodable] = [:]) {
//         self.id = id
//         self.name = name
//         self.arguments = arguments
//     }
// 
//     static func == (lhs: GrokCodeToolRequest, rhs: GrokCodeToolRequest) -> Bool {
//         lhs.id == rhs.id
//             && lhs.name == rhs.name
//             && GrokCodeJSONEquivalence.equal(lhs.arguments, rhs.arguments)
//     }
// }
// 
// struct GrokCodeToolResult: Codable, Equatable {
//     var requestID: String
//     var ok: Bool
//     var content: [GrokCodeContentBlock]
//     var error: String?
// 
//     init(requestID: String, ok: Bool, content: [GrokCodeContentBlock] = [], error: String? = nil) {
//         self.requestID = requestID
//         self.ok = ok
//         self.content = content
//         self.error = error
//     }
// 
//     static func success(requestID: String, text: String) -> GrokCodeToolResult {
//         GrokCodeToolResult(requestID: requestID, ok: true, content: [.text(text)])
//     }
// 
//     static func failure(requestID: String, message: String) -> GrokCodeToolResult {
//         GrokCodeToolResult(requestID: requestID, ok: false, content: [.text(message)], error: message)
//     }
// }
// 
// struct GrokCodeToolUseContext: Sendable {
//     var workingDirectory: URL
//     var permissionMode: GrokCodePermissionMode
//     var outputLimitBytes: Int
//     var fileLimitBytes: Int
//     var shellTimeoutSeconds: TimeInterval
// 
//     init(
//         workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
//         permissionMode: GrokCodePermissionMode = .default,
//         outputLimitBytes: Int = 24_000,
//         fileLimitBytes: Int = 64_000,
//         shellTimeoutSeconds: TimeInterval = 30
//     ) {
//         self.workingDirectory = workingDirectory
//         self.permissionMode = permissionMode
//         self.outputLimitBytes = outputLimitBytes
//         self.fileLimitBytes = fileLimitBytes
//         self.shellTimeoutSeconds = shellTimeoutSeconds
//     }
// }
// 
// protocol GrokCodeTool {
//     associatedtype Input: Decodable
// 
//     var name: String { get }
//     var description: String { get }
//     var isConcurrencySafeByDefault: Bool { get }
//     var requiredPermission: GrokCodeToolPermission { get }
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws
//     func checkPermission(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodePermissionDecision
//     func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult
// }
// 
// extension GrokCodeTool {
//     var isConcurrencySafeByDefault: Bool { true }
//     var requiredPermission: GrokCodeToolPermission { .read }
// 
//     func validate(_ input: Input, context: GrokCodeToolUseContext) throws {}
// 
//     func checkPermission(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodePermissionDecision {
//         GrokCodePermissionController(mode: context.permissionMode).decision(for: requiredPermission)
//     }
// }
// 
// struct AnyGrokCodeTool {
//     let name: String
//     let description: String
//     let isConcurrencySafeByDefault: Bool
//     let requiredPermission: GrokCodeToolPermission
// 
//     private let decodeInput: @Sendable ([String: AnyCodable]) throws -> Any
//     private let validateInput: @Sendable (Any, GrokCodeToolUseContext) throws -> Void
//     private let checkToolPermission: @Sendable (Any, GrokCodeToolUseContext) async throws -> GrokCodePermissionDecision
//     private let runTool: @Sendable (Any, GrokCodeToolUseContext) async throws -> GrokCodeToolResult
// 
//     init<T: GrokCodeTool>(_ tool: T) {
//         self.name = tool.name
//         self.description = tool.description
//         self.isConcurrencySafeByDefault = tool.isConcurrencySafeByDefault
//         self.requiredPermission = tool.requiredPermission
//         self.decodeInput = { arguments in
//             let data = try JSONEncoder().encode(arguments)
//             return try JSONDecoder().decode(T.Input.self, from: data)
//         }
//         self.validateInput = { input, context in
//             guard let typedInput = input as? T.Input else {
//                 throw GrokCodeToolError.invalidInput("Internal tool input type mismatch for \(tool.name)")
//             }
//             try tool.validate(typedInput, context: context)
//         }
//         self.checkToolPermission = { input, context in
//             guard let typedInput = input as? T.Input else {
//                 throw GrokCodeToolError.invalidInput("Internal tool input type mismatch for \(tool.name)")
//             }
//             return try await tool.checkPermission(typedInput, context: context)
//         }
//         self.runTool = { input, context in
//             guard let typedInput = input as? T.Input else {
//                 throw GrokCodeToolError.invalidInput("Internal tool input type mismatch for \(tool.name)")
//             }
//             return try await tool.run(typedInput, context: context)
//         }
//     }
// 
//     func run(request: GrokCodeToolRequest, context: GrokCodeToolUseContext) async -> GrokCodeToolResult {
//         do {
//             let input = try decodeInput(request.arguments)
//             try validateInput(input, context)
//             let decision = try await checkToolPermission(input, context)
//             guard decision.isAllowed else {
//                 return .failure(requestID: request.id, message: decision.reason ?? "Permission denied")
//             }
//             var result = try await runTool(input, context)
//             result.requestID = request.id
//             return result.capped(to: context.outputLimitBytes)
//         } catch {
//             return .failure(requestID: request.id, message: error.localizedDescription)
//         }
//     }
// }
// 
// extension GrokCodeToolResult {
//     func capped(to limit: Int) -> GrokCodeToolResult {
//         guard limit > 0 else {
//             return GrokCodeToolResult(requestID: requestID, ok: ok, content: [], error: error)
//         }
// 
//         var remaining = limit
//         var cappedBlocks: [GrokCodeContentBlock] = []
//         var didTruncate = false
// 
//         for block in content {
//             switch block {
//             case .text(let text):
//                 let bytes = text.utf8.count
//                 if bytes <= remaining {
//                     cappedBlocks.append(block)
//                     remaining -= bytes
//                 } else {
//                     cappedBlocks.append(.text(String(decoding: text.utf8.prefix(remaining), as: UTF8.self)))
//                     didTruncate = true
//                     break
//                 }
//             case .json:
//                 let encoded = (try? JSONEncoder().encode(block)).map { $0.count } ?? limit
//                 if encoded <= remaining {
//                     cappedBlocks.append(block)
//                     remaining -= encoded
//                 } else {
//                     cappedBlocks.append(.text("[json output omitted: output limit exceeded]"))
//                     didTruncate = true
//                     break
//                 }
//             }
//         }
// 
//         if didTruncate {
//             cappedBlocks.append(.text("\n[output truncated to \(limit) bytes]"))
//         }
// 
//         return GrokCodeToolResult(requestID: requestID, ok: ok, content: cappedBlocks, error: error)
//     }
// }
// 
// enum GrokCodeJSONEquivalence {
//     static func equal(_ lhs: AnyCodable, _ rhs: AnyCodable) -> Bool {
//         equal(lhs.value, rhs.value)
//     }
// 
//     static func equal(_ lhs: [String: AnyCodable], _ rhs: [String: AnyCodable]) -> Bool {
//         guard lhs.keys == rhs.keys else { return false }
//         return lhs.allSatisfy { key, lhsValue in
//             guard let rhsValue = rhs[key] else { return false }
//             return equal(lhsValue, rhsValue)
//         }
//     }
// 
//     private static func equal(_ lhs: Any, _ rhs: Any) -> Bool {
//         switch (lhs, rhs) {
//         case (_ as NSNull, _ as NSNull):
//             return true
//         case (let lhs as Bool, let rhs as Bool):
//             return lhs == rhs
//         case (let lhs as Int, let rhs as Int):
//             return lhs == rhs
//         case (let lhs as Double, let rhs as Double):
//             return lhs == rhs
//         case (let lhs as String, let rhs as String):
//             return lhs == rhs
//         case (let lhs as [AnyCodable], let rhs as [AnyCodable]):
//             guard lhs.count == rhs.count else { return false }
//             return zip(lhs, rhs).allSatisfy { equal($0, $1) }
//         case (let lhs as [AnyCodable], let rhs as [Any]):
//             guard lhs.count == rhs.count else { return false }
//             return zip(lhs, rhs).allSatisfy { equal($0.value, $1) }
//         case (let lhs as [Any], let rhs as [AnyCodable]):
//             guard lhs.count == rhs.count else { return false }
//             return zip(lhs, rhs).allSatisfy { equal($0, $1.value) }
//         case (let lhs as [Any], let rhs as [Any]):
//             guard lhs.count == rhs.count else { return false }
//             return zip(lhs, rhs).allSatisfy { equal($0, $1) }
//         case (let lhs as [String: AnyCodable], let rhs as [String: AnyCodable]):
//             return equal(lhs, rhs)
//         default:
//             return false
//         }
//     }
// }
