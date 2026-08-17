import Foundation
import GrokClient

struct XAIResponsesToolDefinition: Encodable {
    let type: String
    let name: String
    let description: String?
    let parameters: AnyCodable
    let strict: Bool?

    init(
        name: String,
        description: String? = nil,
        parameters: [String: Any],
        strict: Bool? = nil
    ) {
        self.type = "function"
        self.name = name
        self.description = description
        self.parameters = AnyCodable(parameters)
        self.strict = strict
    }

    init(
        name: String,
        description: String? = nil,
        parameters: [String: AnyCodable],
        strict: Bool? = nil
    ) {
        self.type = "function"
        self.name = name
        self.description = description
        self.parameters = AnyCodable(parameters)
        self.strict = strict
    }
}

enum XAIResponsesToolChoice: Encodable {
    case auto
    case none
    case required
    case function(name: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode("auto")
        case .none:
            try container.encode("none")
        case .required:
            try container.encode("required")
        case .function(let name):
            try container.encode([
                "type": "function",
                "name": name
            ])
        }
    }
}

struct XAIResponsesFunctionCallOutput: Encodable {
    let type: String
    let callID: String
    let output: String

    init(callID: String, output: String) {
        self.type = "function_call_output"
        self.callID = callID
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case output
    }
}

struct XAIResponsesFunctionCall: Decodable {
    let id: String?
    let callID: String
    let name: String
    let arguments: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case callId
        case name
        case arguments
        case status
    }

    init(id: String?, callID: String, name: String, arguments: String, status: String?) {
        self.id = id
        self.callID = callID
        self.name = name
        self.arguments = arguments
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
        let snakeCaseCallID = try container.decodeIfPresent(String.self, forKey: .callID)
        let camelCaseCallID = try container.decodeIfPresent(String.self, forKey: .callId)
        let callID = snakeCaseCallID ?? camelCaseCallID ?? id ?? ""
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let arguments = try Self.decodeArguments(from: container)
        let status = try container.decodeIfPresent(String.self, forKey: .status)

        self.init(id: id, callID: callID, name: name, arguments: arguments, status: status)
    }

    init?(json: [String: Any]) {
        let id = json["id"] as? String
        let callID = json["call_id"] as? String
            ?? json["callId"] as? String
            ?? id
            ?? ""
        let name = json["name"] as? String ?? ""
        let arguments = Self.argumentsString(from: json["arguments"])
        let status = json["status"] as? String

        guard !callID.isEmpty || !name.isEmpty else { return nil }
        self.init(id: id, callID: callID, name: name, arguments: arguments, status: status)
    }

    var argumentsJSON: [String: Any]? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func decodeArguments(from container: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let string = try? container.decode(String.self, forKey: .arguments) {
            return string
        }
        if let value = try? container.decode(AnyCodable.self, forKey: .arguments) {
            return argumentsString(from: value.value)
        }
        return ""
    }

    private static func argumentsString(from value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let dictionary as [String: Any]:
            return Self.jsonString(from: dictionary)
        case let dictionary as [String: AnyCodable]:
            return Self.jsonString(from: dictionary.mapValues(\.value))
        case let array as [Any]:
            return Self.jsonString(from: array)
        case let array as [AnyCodable]:
            return Self.jsonString(from: array.map(\.value))
        case nil:
            return ""
        default:
            return String(describing: value!)
        }
    }

    private static func jsonString(from value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }
}

struct XAIResponsesResult: Decodable {
    let id: String
    let outputText: String?
    let output: [XAIResponsesOutputItem]
    let error: XAIResponsesError?

    enum CodingKeys: String, CodingKey {
        case id
        case outputText = "output_text"
        case outputTextCamel = "outputText"
        case output
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let snakeCaseOutputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        let camelCaseOutputText = try container.decodeIfPresent(String.self, forKey: .outputTextCamel)
        self.outputText = snakeCaseOutputText ?? camelCaseOutputText
        self.output = try container.decodeIfPresent([XAIResponsesOutputItem].self, forKey: .output) ?? []
        self.error = try? container.decodeIfPresent(XAIResponsesError.self, forKey: .error)
    }

    var finalText: String {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let pieces = output.flatMap(\.textPieces)
        return pieces.joined(separator: "\n")
    }

    var functionCalls: [XAIResponsesFunctionCall] {
        output.compactMap(\.functionCall)
    }
}

struct XAIResponsesRequestBody: Encodable {
    let model: String
    let input: [XAIResponsesInputItem]
    let store: Bool
    let previousResponseID: String?
    let maxOutputTokens: Int?
    let stream: Bool?
    let tools: [XAIResponsesToolDefinition]?
    let toolChoice: XAIResponsesToolChoice?
    let parallelToolCalls: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case store
        case previousResponseID = "previous_response_id"
        case maxOutputTokens = "max_output_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
    }
}

struct XAIResponsesOutputItem: Decodable {
    let type: String?
    let text: String?
    let content: [XAIResponsesContentItem]
    let functionCall: XAIResponsesFunctionCall?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try? container.decodeIfPresent(String.self, forKey: .type)
        self.text = try? container.decodeIfPresent(String.self, forKey: .text)
        self.content = (try? container.decodeIfPresent([XAIResponsesContentItem].self, forKey: .content)) ?? []

        if type == "function_call" {
            self.functionCall = try XAIResponsesFunctionCall(from: decoder)
        } else {
            self.functionCall = nil
        }
    }

    var textPieces: [String] {
        var pieces: [String] = []
        if let text, !text.isEmpty {
            pieces.append(text)
        }
        pieces.append(contentsOf: content.compactMap(\.text).filter { !$0.isEmpty })
        return pieces
    }
}

struct XAIResponsesContentItem: Decodable {
    let type: String?
    let text: String?
}

struct XAIResponsesError: Decodable {
    let message: String?
    let type: String?
    let code: String?
}

struct XAIResponsesInputItem: Encodable {
    private let values: [String: AnyCodable]

    private init(_ values: [String: Any]) {
        self.values = values.mapValues(AnyCodable.init)
    }

    static func userMessage(_ message: String, fileAttachmentIDs: [String] = []) -> XAIResponsesInputItem {
        let trimmedIDs = fileAttachmentIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let content: Any
        if trimmedIDs.isEmpty {
            content = message
        } else {
            var items: [[String: Any]] = [
                ["type": "input_text", "text": message]
            ]
            items.append(contentsOf: trimmedIDs.map { fileID in
                ["type": "input_file", "file_id": fileID]
            })
            content = items
        }

        return XAIResponsesInputItem([
            "role": "user",
            "content": content
        ])
    }

    static func functionCallOutput(_ output: XAIResponsesFunctionCallOutput) -> XAIResponsesInputItem {
        XAIResponsesInputItem([
            "type": output.type,
            "call_id": output.callID,
            "output": output.output
        ])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
