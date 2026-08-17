import Foundation

internal struct JSONLookup {
    private let value: Any?

    internal init(_ value: Any?) {
        self.value = value
    }

    internal init(_ value: AnyCodable) {
        self.value = value.value
    }

    internal init(_ value: [String: AnyCodable]) {
        self.value = value
    }

    internal init(_ value: [AnyCodable]) {
        self.value = value
    }

    internal init(_ value: [String: Any]) {
        self.value = value
    }

    internal init(_ value: [Any]) {
        self.value = value
    }

    internal var rawAnyCodable: AnyCodable {
        AnyCodable(Self.normalizedValue(value) ?? NSNull())
    }

    internal func anyCodable() -> AnyCodable {
        rawAnyCodable
    }

    internal func string(_ keys: String...) -> String? {
        string(keys)
    }

    internal func string(_ keys: [String]) -> String? {
        guard let string = stringAllowingEmpty(keys),
              !string.isEmpty else {
            return nil
        }
        return string
    }

    internal func stringAllowingEmpty(_ keys: String...) -> String? {
        stringAllowingEmpty(keys)
    }

    internal func stringAllowingEmpty(_ keys: [String]) -> String? {
        firstDirectValue(for: keys).flatMap(Self.stringValue)
    }

    internal func bool(_ keys: String...) -> Bool? {
        bool(keys)
    }

    internal func bool(_ keys: [String]) -> Bool? {
        firstDirectValue(for: keys).flatMap(Self.boolValue)
    }

    internal func int(_ keys: String...) -> Int? {
        int(keys)
    }

    internal func int(_ keys: [String]) -> Int? {
        firstDirectValue(for: keys).flatMap(Self.intValue)
    }

    internal func double(_ keys: String...) -> Double? {
        double(keys)
    }

    internal func double(_ keys: [String]) -> Double? {
        firstDirectValue(for: keys).flatMap(Self.doubleValue)
    }

    internal func firstString(_ keys: String...) -> String? {
        firstString(keys)
    }

    internal func firstString(_ keys: [String]) -> String? {
        firstValue(for: keys, in: value).flatMap(Self.stringValue).flatMap { $0.isEmpty ? nil : $0 }
    }

    internal func firstBool(_ keys: String...) -> Bool? {
        firstBool(keys)
    }

    internal func firstBool(_ keys: [String]) -> Bool? {
        firstValue(for: keys, in: value).flatMap(Self.boolValue)
    }

    internal func firstInt(_ keys: String...) -> Int? {
        firstInt(keys)
    }

    internal func firstInt(_ keys: [String]) -> Int? {
        firstValue(for: keys, in: value).flatMap(Self.intValue)
    }

    internal func firstDictionary(_ keys: String...) -> [String: AnyCodable]? {
        firstDictionary(keys)
    }

    internal func firstDictionary(_ keys: [String]) -> [String: AnyCodable]? {
        dictionaries(keys).first
    }

    internal func dictionaries(_ keys: String...) -> [[String: AnyCodable]] {
        dictionaries(keys)
    }

    internal func dictionaries(_ keys: [String]) -> [[String: AnyCodable]] {
        if let array = Self.arrayValue(value) {
            return array.flatMap(Self.directDictionaries)
        }

        guard let dictionary = Self.dictionaryValue(value) else {
            return []
        }

        // 1. Direct array matches: if dictionary[key] is directly an array
        for key in keys {
            guard let nested = dictionary[key]?.value else {
                continue
            }
            if let array = Self.arrayValue(nested) {
                let items = array.flatMap(Self.directDictionaries)
                if !items.isEmpty {
                    return items
                }
            }
        }

        // 2. Recursive matches: if dictionary[key] is a wrapper object that contains an array or nested matches under keys
        for key in keys {
            guard let nested = dictionary[key]?.value else {
                continue
            }
            if Self.dictionaryValue(nested) != nil {
                let nestedDictionaries = JSONLookup(nested).dictionaries(keys)
                if !nestedDictionaries.isEmpty {
                    return nestedDictionaries
                }
            }
        }

        // 3. Single object match fallback: if dictionary[key] is a single leaf dictionary
        for key in keys {
            guard let nested = dictionary[key]?.value,
                  let dict = Self.dictionaryValue(nested) else {
                continue
            }
            return [dict]
        }

        return []
    }

    internal func allDictionaries(_ keys: String...) -> [[String: AnyCodable]] {
        allDictionaries(keys)
    }

    internal func allDictionaries(_ keys: [String]) -> [[String: AnyCodable]] {
        Self.allDictionaries(from: value, keys: Set(keys))
    }

    internal func containsAnyKey(_ keys: String...) -> Bool {
        containsAnyKey(keys)
    }

    internal func containsAnyKey(_ keys: [String]) -> Bool {
        guard let dictionary = Self.dictionaryValue(value) else {
            return false
        }
        return keys.contains { dictionary.keys.contains($0) }
    }

    private func firstDirectValue(for keys: [String]) -> Any? {
        guard let dictionary = Self.dictionaryValue(value) else {
            return nil
        }
        for key in keys {
            if let value = dictionary[key]?.value {
                return value
            }
        }
        return nil
    }

    private func firstValue(for keys: [String], in value: Any?) -> Any? {
        guard let value = Self.unwrappedValue(value) else {
            return nil
        }

        if let dictionary = Self.dictionaryValue(value) {
            for key in keys {
                if let value = dictionary[key]?.value {
                    return value
                }
            }

            for nested in dictionary.values {
                if let value = firstValue(for: keys, in: nested.value) {
                    return value
                }
            }
            return nil
        }

        if let array = Self.arrayValue(value) {
            for nested in array {
                if let value = firstValue(for: keys, in: nested) {
                    return value
                }
            }
        }

        return nil
    }

    private static func directDictionaries(from value: Any?) -> [[String: AnyCodable]] {
        guard let value = unwrappedValue(value) else {
            return []
        }

        if let array = arrayValue(value) {
            return array.flatMap(directDictionaries)
        }

        if let dictionary = dictionaryValue(value) {
            return [dictionary]
        }

        return []
    }

    private static func allDictionaries(from value: Any?, keys: Set<String>) -> [[String: AnyCodable]] {
        guard let value = unwrappedValue(value) else {
            return []
        }

        if let array = arrayValue(value) {
            return array.flatMap { allDictionaries(from: $0, keys: keys) }
        }

        guard let dictionary = dictionaryValue(value) else {
            return []
        }

        var results: [[String: AnyCodable]] = []
        for (key, nested) in dictionary {
            if keys.contains(key) {
                results.append(contentsOf: directDictionaries(from: nested.value))
            } else {
                results.append(contentsOf: allDictionaries(from: nested.value, keys: keys))
            }
        }
        return results
    }

    private static func stringValue(_ value: Any?) -> String? {
        unwrappedValue(value) as? String
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch unwrappedValue(value) {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int != 0
        case let double as Double:
            return double != 0
        case let string as String:
            switch string.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch unwrappedValue(value) {
        case let bool as Bool:
            return bool ? 1 : 0
        case let int as Int:
            return int
        case let double as Double where double.isFinite:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch unwrappedValue(value) {
        case let bool as Bool:
            return bool ? 1 : 0
        case let int as Int:
            return Double(int)
        case let double as Double:
            return double
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func dictionaryValue(_ value: Any?) -> [String: AnyCodable]? {
        switch unwrappedValue(value) {
        case let dictionary as [String: AnyCodable]:
            return dictionary
        case let dictionary as [String: Any]:
            return dictionary.mapValues { AnyCodable(normalizedValue($0) ?? NSNull()) }
        default:
            return nil
        }
    }

    private static func arrayValue(_ value: Any?) -> [Any]? {
        switch unwrappedValue(value) {
        case let array as [AnyCodable]:
            return array.map(\.value)
        case let array as [Any]:
            return array
        default:
            return nil
        }
    }

    private static func unwrappedValue(_ value: Any?) -> Any? {
        guard let value else {
            return nil
        }

        if let codable = value as? AnyCodable {
            return codable.value
        }

        return value
    }

    private static func normalizedValue(_ value: Any?) -> Any? {
        guard let value = unwrappedValue(value) else {
            return nil
        }

        if let dictionary = value as? [String: AnyCodable] {
            return dictionary.mapValues { AnyCodable(normalizedValue($0.value) ?? NSNull()) }
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { AnyCodable(normalizedValue($0) ?? NSNull()) }
        }

        if let array = value as? [AnyCodable] {
            return array.map { AnyCodable(normalizedValue($0.value) ?? NSNull()) }
        }

        if let array = value as? [Any] {
            return array.map { AnyCodable(normalizedValue($0) ?? NSNull()) }
        }

        return value
    }
}
