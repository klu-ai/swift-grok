import Foundation

internal enum GrokTypeaheadParser {
    internal static func makeTypeaheadResponse(from json: Any, maxItems: Int) -> GrokTypeaheadResponse {
        var seen = Set<String>()
        let suggestions = typeaheadValues(from: json)
            .compactMap(makeTypeaheadSuggestion)
            .filter { suggestion in
                seen.insert(suggestion.text.lowercased()).inserted
            }
            .prefix(max(0, maxItems))
            .map { $0 }

        return GrokTypeaheadResponse(
            suggestions: suggestions,
            rawJSON: AnyCodable(json)
        )
    }

    private static func typeaheadValues(from value: Any) -> [Any] {
        if let array = unwrappedArray(value) {
            return array
        }

        guard let dictionary = unwrappedDictionary(value) else {
            return []
        }

        if typeaheadText(in: dictionary) != nil {
            return [dictionary]
        }

        for key in ["suggestions", "items", "results", "data", "result", "queries", "completions"] {
            guard let nested = dictionary[key]?.value else {
                continue
            }
            let values = typeaheadValues(from: nested)
            if !values.isEmpty {
                return values
            }
        }

        return []
    }

    private static func makeTypeaheadSuggestion(from value: Any) -> GrokTypeaheadSuggestion? {
        if let string = unwrappedValue(value) as? String {
            let text = normalizedTypeaheadText(string)
            return text.isEmpty ? nil : GrokTypeaheadSuggestion(text: text)
        }

        guard let dictionary = unwrappedDictionary(value),
              let text = typeaheadText(in: dictionary) else {
            return nil
        }

        let title = JSONLookup(dictionary).string("title", "label", "display", "name")
        return GrokTypeaheadSuggestion(
            text: text,
            title: title == text ? nil : title,
            rawJSON: dictionary
        )
    }

    private static func typeaheadText(in dictionary: [String: AnyCodable]) -> String? {
        for key in ["text", "query", "value", "completion", "suggestion", "title", "name", "label"] {
            guard let value = dictionary[key]?.value as? String else {
                continue
            }
            let text = normalizedTypeaheadText(value)
            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private static func normalizedTypeaheadText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrappedDictionary(_ value: Any) -> [String: AnyCodable]? {
        switch unwrappedValue(value) {
        case let dictionary as [String: AnyCodable]:
            return dictionary
        case let dictionary as [String: Any]:
            return dictionary.mapValues { AnyCodable($0) }
        default:
            return nil
        }
    }

    private static func unwrappedArray(_ value: Any) -> [Any]? {
        switch unwrappedValue(value) {
        case let array as [AnyCodable]:
            return array.map(\.value)
        case let array as [Any]:
            return array
        default:
            return nil
        }
    }

    private static func unwrappedValue(_ value: Any) -> Any {
        if let codable = value as? AnyCodable {
            return codable.value
        }
        return value
    }
}

internal extension GrokClient {
    func makeTypeaheadParserResponse(from json: Any, maxItems: Int) -> GrokTypeaheadResponse {
        GrokTypeaheadParser.makeTypeaheadResponse(from: json, maxItems: maxItems)
    }
}
