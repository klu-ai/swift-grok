import Foundation
import GrokClient

final class RemoteTypeaheadController {
    private struct CacheEntry {
        let suggestions: [InputTypeaheadSuggestion]
        let expiresAt: Date
    }

    private let app: GrokCLIApp
    private let minQueryLength: Int
    private let maxItems: Int
    private let debounceNanoseconds: UInt64
    private let cacheTTL: TimeInterval
    private let lock = NSLock()

    private var cache: [String: CacheEntry] = [:]
    private var activeQuery: String?
    private var latestQuery: String?
    private var latestSuggestions: [InputTypeaheadSuggestion] = []
    private var latestVersion = 0
    private var pendingQuery: String?
    private var scheduledTask: Task<Void, Never>?

    init(
        app: GrokCLIApp,
        minQueryLength: Int = 2,
        maxItems: Int = 3,
        debounceNanoseconds: UInt64 = 250_000_000,
        cacheTTL: TimeInterval = 60
    ) {
        self.app = app
        self.minQueryLength = minQueryLength
        self.maxItems = maxItems
        self.debounceNanoseconds = debounceNanoseconds
        self.cacheTTL = cacheTTL
    }

    deinit {
        scheduledTask?.cancel()
    }

    var version: Int {
        lock.lock()
        defer { lock.unlock() }
        return latestVersion
    }

    func suggestions(for buffer: String) -> [InputTypeaheadSuggestion] {
        guard let query = normalizedQuery(buffer) else {
            return []
        }

        lock.lock()
        defer { lock.unlock() }
        if latestQuery == query {
            return latestSuggestions
        }
        return displaySuggestionsLocked(for: query)
    }

    func isPending(for buffer: String) -> Bool {
        guard let query = normalizedQuery(buffer) else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }
        return pendingQuery == query
    }

    func observe(buffer: String) {
        guard let query = normalizedQuery(buffer) else {
            clear()
            return
        }

        lock.lock()
        if let cached = cache[query], cached.expiresAt > Date() {
            scheduledTask?.cancel()
            activeQuery = query
            pendingQuery = nil
            updateLatestLocked(query: query, suggestions: displaySuggestionsLocked(for: query))
            lock.unlock()
            return
        }

        if activeQuery == query {
            updateLatestLocked(query: query, suggestions: displaySuggestionsLocked(for: query))
            lock.unlock()
            return
        }

        scheduledTask?.cancel()
        activeQuery = query
        pendingQuery = query
        updateLatestLocked(query: query, suggestions: displaySuggestionsLocked(for: query))
        scheduledTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
                let suggestions = try await fetchSuggestions(query: query)
                store(query: query, suggestions: suggestions)
            } catch {
                store(query: query, suggestions: [])
            }
        }
        lock.unlock()
    }

    func reset() {
        clear()
    }

    private func fetchSuggestions(query: String) async throws -> [InputTypeaheadSuggestion] {
        let client = try app.initializeClient()
        let response = try await client.typeahead(query: query, maxItems: maxItems)
        return response.suggestions
            .map { suggestion in
                InputTypeaheadSuggestion(
                    display: normalizedSuggestionText(suggestion.text),
                    insertText: normalizedSuggestionText(suggestion.text),
                    description: suggestion.title ?? ""
                )
            }
            .filter { !$0.insertText.isEmpty }
    }

    private func store(query: String, suggestions: [InputTypeaheadSuggestion]) {
        lock.lock()
        cache[query] = CacheEntry(
            suggestions: Array(suggestions.prefix(maxItems)),
            expiresAt: Date().addingTimeInterval(cacheTTL)
        )
        if pendingQuery == query {
            pendingQuery = nil
        }
        if activeQuery == query {
            scheduledTask = nil
            updateLatestLocked(query: query, suggestions: displaySuggestionsLocked(for: query))
        }
        lock.unlock()
    }

    private func clear() {
        lock.lock()
        scheduledTask?.cancel()
        activeQuery = nil
        pendingQuery = nil
        if latestQuery != nil || !latestSuggestions.isEmpty {
            latestQuery = nil
            latestSuggestions = []
            latestVersion += 1
        }
        lock.unlock()
    }

    private func displaySuggestionsLocked(for query: String) -> [InputTypeaheadSuggestion] {
        let now = Date()
        if let exact = cache[query], exact.expiresAt > now, !exact.suggestions.isEmpty {
            return exact.suggestions
        }

        let normalizedQuery = query.lowercased()
        if let latestQuery,
           normalizedQuery.hasPrefix(latestQuery.lowercased()),
           !latestSuggestions.isEmpty {
            let suggestions = compatibleSuggestions(latestSuggestions, for: normalizedQuery)
            if !suggestions.isEmpty {
                return suggestions
            }
        }

        let prefixKeys = cache.keys
            .filter { key in
                guard let entry = cache[key], entry.expiresAt > now, !entry.suggestions.isEmpty else {
                    return false
                }
                return normalizedQuery.hasPrefix(key.lowercased())
            }
            .sorted { $0.count > $1.count }

        for key in prefixKeys {
            let suggestions = compatibleSuggestions(cache[key]?.suggestions ?? [], for: normalizedQuery)
            if !suggestions.isEmpty {
                return suggestions
            }
        }

        return []
    }

    private func compatibleSuggestions(
        _ suggestions: [InputTypeaheadSuggestion],
        for normalizedQuery: String
    ) -> [InputTypeaheadSuggestion] {
        suggestions.filter { suggestion in
            suggestion.insertText.lowercased().hasPrefix(normalizedQuery) ||
                suggestion.display.lowercased().hasPrefix(normalizedQuery)
        }
    }

    private func updateLatestLocked(query: String, suggestions: [InputTypeaheadSuggestion]) {
        guard latestQuery != query || latestSuggestions != suggestions else {
            return
        }
        latestQuery = query
        latestSuggestions = suggestions
        latestVersion += 1
    }

    private func normalizedQuery(_ buffer: String) -> String? {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minQueryLength,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("[Pasted content "),
              !trimmed.contains("\n"),
              !trimmed.contains("\r") else {
            return nil
        }
        return trimmed
    }

    private func normalizedSuggestionText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
