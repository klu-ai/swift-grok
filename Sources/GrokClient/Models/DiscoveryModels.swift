import Foundation

public struct GrokTypeaheadSuggestion: Codable {
    public let text: String
    public let title: String?
    public let rawJSON: [String: AnyCodable]

    public init(text: String, title: String? = nil, rawJSON: [String: AnyCodable] = [:]) {
        self.text = text
        self.title = title
        self.rawJSON = rawJSON
    }
}

public struct GrokTypeaheadResponse: Codable {
    public let suggestions: [GrokTypeaheadSuggestion]
    public let rawJSON: AnyCodable

    public init(suggestions: [GrokTypeaheadSuggestion], rawJSON: AnyCodable) {
        self.suggestions = suggestions
        self.rawJSON = rawJSON
    }
}

public struct GrokModesResponse {
    public let modes: [GrokMode]
    public let rawJSON: AnyCodable

    public init(modes: [GrokMode], rawJSON: AnyCodable) {
        self.modes = modes
        self.rawJSON = rawJSON
    }
}
