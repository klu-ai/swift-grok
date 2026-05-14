import Foundation

internal enum GrokRateLimitParser {
    internal typealias JSONDictionary = [String: AnyCodable]

    private static let remainingKeys = [
        "remainingResponses",
        "remainingResponseCount",
        "responsesRemaining",
        "remainingMessages",
        "messagesRemaining",
        "remainingRequests",
        "requestsRemaining",
        "remainingQueries",
        "queriesRemaining",
        "remaining"
    ]

    private static let resetAtKeys = [
        "resetAt",
        "resetsAt",
        "resetTime",
        "resetTimestamp",
        "windowResetAt",
        "rateLimitResetAt",
        "expiresAt",
        "reset"
    ]

    private static let resetAfterKeys = [
        "resetAfterSeconds",
        "secondsUntilReset",
        "resetInSeconds",
        "timeUntilResetSeconds",
        "resetAfter",
        "resetIn",
        "ttlSeconds"
    ]

    private static let windowKeys = [
        "windowSeconds",
        "windowLengthSeconds",
        "windowDurationSeconds",
        "limitWindowSeconds",
        "rateLimitWindowSeconds",
        "periodSeconds",
        "durationSeconds",
        "window",
        "windowLength",
        "windowDuration",
        "limitWindow",
        "rateLimitWindow",
        "period",
        "duration"
    ]

    private static let lookupKeys = [
        "rateLimit",
        "rateLimits",
        "limits",
        "usage",
        "data",
        "result",
        "models",
        "items",
        "values"
    ]

    private static let modelKeys = ["modelName", "model", "modelId", "modeId", "name"]

    private static let durationRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#
    )

    private static let iso8601FormatterWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    internal static func makeRateLimitResponse(
        from json: Any,
        requestedModelName: String,
        fetchedAt: Date = Date()
    ) -> GrokRateLimit {
        let rateLimit = matchingRateLimitDictionary(from: json, requestedModelName: requestedModelName)
            ?? rateLimitDictionary(from: json, requestedModelName: requestedModelName)
            ?? [:]
        let lookup = JSONLookup(rateLimit)
        let modelName = lookup.firstString("modelName", "model", "modelId", "modeId")
            ?? (requestedModelName.isEmpty ? nil : requestedModelName)

        return GrokRateLimit(
            modelName: modelName,
            remainingResponses: firstInt(in: rateLimit, keys: remainingKeys),
            resetAt: firstDate(in: rateLimit, keys: resetAtKeys, fetchedAt: fetchedAt),
            resetAfterSeconds: firstDurationSeconds(in: rateLimit, keys: resetAfterKeys),
            windowSeconds: firstDurationSeconds(in: rateLimit, keys: windowKeys),
            fetchedAt: fetchedAt,
            rawJSON: AnyCodable(json)
        )
    }

    internal static func matchingRateLimitDictionary(
        from value: Any,
        requestedModelName: String
    ) -> JSONDictionary? {
        guard !requestedModelName.isEmpty else {
            return nil
        }

        if let dictionary = rawDictionaryIfPresent(from: value) {
            if let nested = dictionary[requestedModelName]?.value,
               let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                return found
            }

            if matchesRateLimitModel(dictionary, requestedModelName: requestedModelName) {
                return dictionary
            }

            for nested in dictionary.values {
                if let found = matchingRateLimitDictionary(from: nested.value, requestedModelName: requestedModelName) {
                    return found
                }
            }
            return nil
        }

        if let array = directArray(from: value) {
            for nested in array {
                if let found = matchingRateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                    return found
                }
            }
        }

        return nil
    }

    internal static func rateLimitDictionary(
        from value: Any,
        requestedModelName: String
    ) -> JSONDictionary? {
        if let dictionary = rawDictionaryIfPresent(from: value) {
            if !requestedModelName.isEmpty,
               let nested = dictionary[requestedModelName]?.value,
               let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                return found
            }

            if matchesRateLimitModel(dictionary, requestedModelName: requestedModelName) {
                return dictionary
            }

            for key in lookupKeys {
                guard let nested = dictionary[key]?.value,
                      let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) else {
                    continue
                }
                return found
            }

            if JSONLookup(dictionary).containsAnyKey(remainingKeys) {
                return dictionary
            }

            for nested in dictionary.values {
                if let found = rateLimitDictionary(from: nested.value, requestedModelName: requestedModelName) {
                    return found
                }
            }
            return nil
        }

        if let array = directArray(from: value) {
            for nested in array {
                if let found = rateLimitDictionary(from: nested, requestedModelName: requestedModelName) {
                    return found
                }
            }
        }

        return nil
    }

    internal static func durationSecondsFromRateLimitValue(_ value: Any?) -> Int? {
        if let int = intFromRateLimitValue(value) {
            return max(0, int)
        }

        if let string = unwrapped(value) as? String {
            return durationSecondsFromString(string)
        }

        if let dictionary = rawDictionaryIfPresent(from: value) {
            for key in ["seconds", "second", "value", "duration"] {
                if let seconds = durationSecondsFromRateLimitValue(dictionary[key]?.value) {
                    return seconds
                }
            }
        }

        return nil
    }

    internal static func dateFromRateLimitValue(_ value: Any?, fetchedAt: Date) -> Date? {
        guard let value = unwrapped(value) else {
            return nil
        }

        if let dictionary = rawDictionaryIfPresent(from: value) {
            for key in ["at", "time", "timestamp", "date", "value", "resetAt", "resetTime"] {
                if let date = dateFromRateLimitValue(dictionary[key]?.value, fetchedAt: fetchedAt) {
                    return date
                }
            }
        }

        if let seconds = doubleFromRateLimitValue(value) {
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1_000)
            }
            if seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
            if seconds >= 0 {
                return fetchedAt.addingTimeInterval(seconds)
            }
        }

        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let date = iso8601FormatterWithFractions.date(from: trimmed) {
            return date
        }

        if let date = iso8601Formatter.date(from: trimmed) {
            return date
        }

        if let duration = durationSecondsFromString(trimmed) {
            return fetchedAt.addingTimeInterval(TimeInterval(duration))
        }

        return nil
    }

    internal static func durationSecondsFromString(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return nil
        }

        if let seconds = Double(trimmed), seconds.isFinite {
            return max(0, Int(seconds))
        }

        let matches = durationRegex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard !matches.isEmpty else {
            return nil
        }

        let total = matches.reduce(0.0) { total, match in
            guard let numberRange = Range(match.range(at: 1), in: trimmed),
                  let unitRange = Range(match.range(at: 2), in: trimmed),
                  let number = Double(trimmed[numberRange]) else {
                return total
            }

            let unit = String(trimmed[unitRange])
            let multiplier: Double
            if unit.hasPrefix("d") {
                multiplier = 86_400
            } else if unit.hasPrefix("h") {
                multiplier = 3_600
            } else if unit.hasPrefix("m") {
                multiplier = 60
            } else {
                multiplier = 1
            }

            return total + number * multiplier
        }

        return max(0, Int(total.rounded(.up)))
    }

    private static func matchesRateLimitModel(_ dictionary: JSONDictionary, requestedModelName: String) -> Bool {
        guard !requestedModelName.isEmpty else {
            return false
        }

        for key in modelKeys {
            guard let value = dictionary[key]?.value else {
                continue
            }
            if stringMatchesRequestedModel(value, requestedModelName: requestedModelName) {
                return true
            }
        }

        return false
    }

    private static func stringMatchesRequestedModel(_ value: Any, requestedModelName: String) -> Bool {
        if let string = unwrapped(value) as? String {
            return string.caseInsensitiveCompare(requestedModelName) == .orderedSame
        }

        if let array = directArray(from: value) {
            return array.contains { stringMatchesRequestedModel($0, requestedModelName: requestedModelName) }
        }

        return false
    }

    private static func firstInt(in value: Any, keys: [String]) -> Int? {
        if let dictionary = rawDictionaryIfPresent(from: value) {
            for key in keys {
                if let int = intFromRateLimitValue(dictionary[key]?.value) {
                    return int
                }
            }

            for nested in dictionary.values {
                if let int = firstInt(in: nested.value, keys: keys) {
                    return int
                }
            }
            return nil
        }

        if let array = directArray(from: value) {
            for nested in array {
                if let int = firstInt(in: nested, keys: keys) {
                    return int
                }
            }
        }

        return nil
    }

    private static func firstDate(in value: Any, keys: [String], fetchedAt: Date) -> Date? {
        if let dictionary = rawDictionaryIfPresent(from: value) {
            for key in keys {
                if let date = dateFromRateLimitValue(dictionary[key]?.value, fetchedAt: fetchedAt) {
                    return date
                }
            }

            for nested in dictionary.values {
                if let date = firstDate(in: nested.value, keys: keys, fetchedAt: fetchedAt) {
                    return date
                }
            }
            return nil
        }

        if let array = directArray(from: value) {
            for nested in array {
                if let date = firstDate(in: nested, keys: keys, fetchedAt: fetchedAt) {
                    return date
                }
            }
        }

        return nil
    }

    private static func firstDurationSeconds(in value: Any, keys: [String]) -> Int? {
        if let dictionary = rawDictionaryIfPresent(from: value) {
            for key in keys {
                if let seconds = durationSecondsFromRateLimitValue(dictionary[key]?.value) {
                    return seconds
                }
            }

            for nested in dictionary.values {
                if let seconds = firstDurationSeconds(in: nested.value, keys: keys) {
                    return seconds
                }
            }
            return nil
        }

        if let array = directArray(from: value) {
            for nested in array {
                if let seconds = firstDurationSeconds(in: nested, keys: keys) {
                    return seconds
                }
            }
        }

        return nil
    }

    private static func intFromRateLimitValue(_ value: Any?) -> Int? {
        guard let value = unwrapped(value) else {
            return nil
        }

        if value is Bool {
            return nil
        }

        if let int = value as? Int {
            return int
        }

        if let double = value as? Double, double.isFinite {
            return Int(double)
        }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let int = Int(trimmed) {
                return int
            }
            if let double = Double(trimmed), double.isFinite {
                return Int(double)
            }
        }

        return nil
    }

    private static func doubleFromRateLimitValue(_ value: Any?) -> Double? {
        guard let value = unwrapped(value) else {
            return nil
        }

        if value is Bool {
            return nil
        }

        if let double = value as? Double, double.isFinite {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = Double(trimmed), double.isFinite {
                return double
            }
        }

        return nil
    }

    private static func rawDictionaryIfPresent(from value: Any?) -> JSONDictionary? {
        guard let value else {
            return nil
        }
        return JSONLookup(value).rawAnyCodable.value as? JSONDictionary
    }

    private static func directArray(from value: Any) -> [Any]? {
        switch unwrapped(value) {
        case let array as [AnyCodable]:
            return array.map(\.value)
        case let array as [Any]:
            return array
        default:
            return nil
        }
    }

    private static func unwrapped(_ value: Any?) -> Any? {
        if let codable = value as? AnyCodable {
            return codable.value
        }
        return value
    }
}

internal extension GrokClient {
    func makeParsedRateLimitResponse(
        from json: Any,
        requestedModelName: String,
        fetchedAt: Date = Date()
    ) -> GrokRateLimit {
        GrokRateLimitParser.makeRateLimitResponse(
            from: json,
            requestedModelName: requestedModelName,
            fetchedAt: fetchedAt
        )
    }

    func parsedMatchingRateLimitDictionary(
        from value: Any,
        requestedModelName: String
    ) -> [String: AnyCodable]? {
        GrokRateLimitParser.matchingRateLimitDictionary(from: value, requestedModelName: requestedModelName)
    }

    func parsedRateLimitDictionary(
        from value: Any,
        requestedModelName: String
    ) -> [String: AnyCodable]? {
        GrokRateLimitParser.rateLimitDictionary(from: value, requestedModelName: requestedModelName)
    }

    func parsedRateLimitDurationSeconds(from value: Any?) -> Int? {
        GrokRateLimitParser.durationSecondsFromRateLimitValue(value)
    }

    func parsedRateLimitDate(from value: Any?, fetchedAt: Date) -> Date? {
        GrokRateLimitParser.dateFromRateLimitValue(value, fetchedAt: fetchedAt)
    }

    func parsedDurationSeconds(from value: String) -> Int? {
        GrokRateLimitParser.durationSecondsFromString(value)
    }
}
