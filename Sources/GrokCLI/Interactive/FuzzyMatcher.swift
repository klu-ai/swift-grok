import Foundation

enum FuzzyMatcher {
    static func score(query: String, text: String) -> Int? {
        let query = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let text = text.lowercased()

        guard !query.isEmpty else { return 0 }
        if text == query { return 10_000 }
        if text.hasPrefix(query) { return 8_000 - text.count }
        if text.contains(query) { return 6_000 - text.count }

        var score = 0
        var searchStart = text.startIndex
        var previousMatch: String.Index?

        for character in query {
            guard let match = text[searchStart...].firstIndex(of: character) else {
                return nil
            }

            score += 10
            if let previousMatch, text.index(after: previousMatch) == match {
                score += 15
            }
            if match == text.startIndex || text[text.index(before: match)].isWhitespace || text[text.index(before: match)] == "-" || text[text.index(before: match)] == "_" || text[text.index(before: match)] == "/" {
                score += 8
            }

            previousMatch = match
            searchStart = text.index(after: match)
        }

        return score - text.count
    }

    static func ranked<Value>(query: String, items: [PickerItem<Value>]) -> [PickerItem<Value>] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items
            .compactMap { item -> (PickerItem<Value>, Int)? in
                guard let score = score(query: trimmed, text: item.searchText) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title < rhs.0.title
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }
}
