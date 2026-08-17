import Foundation
import GrokClient

struct GrokCodeToolSchema: Codable {
    var type: String
    var name: String
    var description: String
    var parameters: [String: AnyCodable]

    init(
        type: String = "function",
        name: String,
        description: String,
        parameters: [String: AnyCodable]
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

enum GrokCodeToolSchemaBuilder {
    static func object(
        properties: [String: [String: AnyCodable]],
        required: [String] = [],
        additionalProperties: Bool = false
    ) -> [String: AnyCodable] {
        [
            "type": AnyCodable("object"),
            "properties": AnyCodable(properties.mapValues { AnyCodable($0) }),
            "required": AnyCodable(required),
            "additionalProperties": AnyCodable(additionalProperties)
        ]
    }

    static func string(_ description: String) -> [String: AnyCodable] {
        [
            "type": AnyCodable("string"),
            "description": AnyCodable(description)
        ]
    }

    static func number(_ description: String) -> [String: AnyCodable] {
        [
            "type": AnyCodable("number"),
            "description": AnyCodable(description)
        ]
    }

    static func boolean(_ description: String) -> [String: AnyCodable] {
        [
            "type": AnyCodable("boolean"),
            "description": AnyCodable(description)
        ]
    }
}
