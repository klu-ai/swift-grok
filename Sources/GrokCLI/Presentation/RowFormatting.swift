import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func printPrettyJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static func printLabeledParts(_ parts: [(String, String?)]) {
        let text = parts.compactMap { label, value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return "\(label): \(value)"
        }

        print(text.isEmpty ? "(no summary available)" : text.joined(separator: " | "))
    }

    static func jsonDictionary<T: Encodable>(from value: T) -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    static func anyDictionary(from value: AnyCodable) -> [String: Any] {
        jsonDictionary(from: value)
    }

    static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
            if let value = dictionary[key] as? CustomStringConvertible {
                return value.description
            }
        }
        return nil
    }

    static func boolValue(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }
        return nil
    }

    static func firstDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    static func arrayCount(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? [Any] {
                return value.count
            }
        }
        return nil
    }

    static func enabledStatus(_ isEnabled: Bool?) -> String? {
        guard let isEnabled else {
            return nil
        }
        return isEnabled ? "enabled" : "archived"
    }

    static func scheduleValue(in dictionary: [String: Any]) -> String? {
        if let value = stringValue(in: dictionary, keys: ["schedule", "scheduledTime", "scheduledAt"]) {
            return value
        }

        let schedule = dictionary["schedule"] as? [String: Any] ?? dictionary
        let day = stringValue(in: schedule, keys: ["dayOfYear", "date"])
        let time = stringValue(in: schedule, keys: ["timeOfDay", "time"])
        let timezone = stringValue(in: schedule, keys: ["timezone", "timeZone"])

        let joined = [day, time, timezone].compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
