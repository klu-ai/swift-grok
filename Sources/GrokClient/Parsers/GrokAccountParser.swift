import Foundation

internal enum GrokAccountParser {
    internal typealias JSONDictionary = [String: AnyCodable]

    private static let agentCustomizationKeys = [
        "values",
        "agentCustomizations",
        "agent_customizations",
        "userSettings",
        "user_settings",
        "settings",
        "data",
        "result",
        "items"
    ]

    private static let subscriptionKeys = [
        "currentSubscription",
        "current_subscription",
        "activeSubscription",
        "active_subscription",
        "subscription",
        "subscriptions",
        "activeSubscriptions",
        "active_subscriptions",
        "userSubscriptions",
        "user_subscriptions",
        "accountSubscriptions",
        "account_subscriptions",
        "data",
        "result",
        "items"
    ]

    private static let activeSubscriptionStatuses: Set<String> = [
        "active",
        "trialing",
        "current",
        "subscribed",
        "paid"
    ]

    private static let inactiveSubscriptionStatuses: Set<String> = [
        "canceled",
        "cancelled",
        "expired",
        "inactive",
        "pastdue",
        "past_due",
        "unpaid"
    ]

    internal static func makeAgentCustomization(from dictionary: [String: Any]) -> GrokAgentCustomization? {
        makeAgentCustomization(from: rawDictionary(from: JSONLookup(dictionary)))
    }

    internal static func makeAgentCustomization(from dictionary: JSONDictionary) -> GrokAgentCustomization? {
        let lookup = JSONLookup(dictionary)
        guard let agentId = lookup.int("agentId", "agent_id", "id") else {
            return nil
        }

        let nestedAgent = rawDictionaryIfPresent(from: dictionary["agent"]?.value)
        let nestedLookup = nestedAgent.map { JSONLookup($0) }
        let defaultName = GrokAgentCustomization.defaultName(for: agentId)
        return GrokAgentCustomization(
            agentId: agentId,
            name: lookup.string("name") ?? nestedLookup?.string("name") ?? defaultName,
            instructions: lookup.string("instructions", "customInstructions", "custom_instructions") ??
                nestedLookup?.string("instructions", "customInstructions", "custom_instructions") ??
                ""
        )
    }

    internal static func makeAgentCustomizationsResponse(from json: Any) -> GrokAgentCustomizationsResponse {
        let customizations = agentCustomizationDictionaries(from: json)
            .compactMap { makeAgentCustomization(from: $0) }

        return GrokAgentCustomizationsResponse(
            agentCustomizations: customizations.sorted { $0.agentId < $1.agentId },
            rawJSON: AnyCodable(json)
        )
    }

    internal static func agentCustomizationDictionaries(from value: Any) -> [JSONDictionary] {
        if let array = directArray(from: value) {
            let dictionaries = array.compactMap { rawDictionaryIfPresent(from: $0) }
            if dictionaries.contains(where: hasAgentCustomizationIdentity) {
                return dictionaries
            }

            for nested in array {
                let found = agentCustomizationDictionaries(from: nested)
                if !found.isEmpty {
                    return found
                }
            }
            return []
        }

        guard let dictionary = rawDictionaryIfPresent(from: value) else {
            return []
        }

        for key in agentCustomizationKeys {
            guard let nested = dictionary[key]?.value else {
                continue
            }
            let found = agentCustomizationDictionaries(from: nested)
            if !found.isEmpty {
                return found
            }
        }

        for nested in dictionary.values {
            let found = agentCustomizationDictionaries(from: nested.value)
            if !found.isEmpty {
                return found
            }
        }

        return []
    }

    internal static func makeSubscriptionsResponse(from json: Any) -> GrokSubscriptionsResponse {
        let subscriptions = subscriptionDictionaries(from: json)
            .map { makeSubscription(from: $0) }

        return GrokSubscriptionsResponse(
            subscriptions: subscriptions,
            currentSubscription: subscriptions.first(where: \.isActive),
            rawJSON: AnyCodable(json)
        )
    }

    internal static func makeSubscription(from dictionary: [String: Any]) -> GrokSubscription {
        makeSubscription(from: rawDictionary(from: JSONLookup(dictionary)))
    }

    internal static func makeSubscription(from dictionary: JSONDictionary) -> GrokSubscription {
        let lookup = JSONLookup(dictionary)
        return GrokSubscription(
            tier: lookup.firstString([
                "subscriptionTier",
                "subscription_tier",
                "tier",
                "tierName",
                "tier_name",
                "planTier",
                "plan_tier",
                "sku"
            ]),
            name: lookup.firstString([
                "displayName",
                "display_name",
                "name",
                "title",
                "planName",
                "plan_name",
                "productName",
                "product_name"
            ]),
            status: lookup.firstString([
                "status",
                "subscriptionStatus",
                "subscription_status",
                "state"
            ]),
            isActive: isActiveSubscription(dictionary),
            rawJSON: dictionary
        )
    }

    internal static func subscriptionDictionaries(from value: Any) -> [JSONDictionary] {
        if let array = directArray(from: value) {
            return array.flatMap { nested -> [JSONDictionary] in
                if let dictionary = rawDictionaryIfPresent(from: nested) {
                    return [dictionary]
                }
                return subscriptionDictionaries(from: nested)
            }
        }

        guard let dictionary = rawDictionaryIfPresent(from: value) else {
            return []
        }

        for key in subscriptionKeys {
            guard let nested = dictionary[key]?.value else {
                continue
            }

            let found = subscriptionDictionaries(from: nested)
            if !found.isEmpty {
                return found
            }
        }

        if looksLikeSubscription(dictionary) {
            return [dictionary]
        }

        for nested in dictionary.values {
            let found = subscriptionDictionaries(from: nested.value)
            if !found.isEmpty {
                return found
            }
        }

        return []
    }

    private static func looksLikeSubscription(_ dictionary: JSONDictionary) -> Bool {
        JSONLookup(dictionary).containsAnyKey([
            "subscriptionTier",
            "subscription_tier",
            "tier",
            "tierName",
            "tier_name",
            "planName",
            "plan_name",
            "productName",
            "product_name",
            "subscriptionStatus",
            "subscription_status",
            "currentPeriodEnd",
            "current_period_end"
        ])
    }

    private static func isActiveSubscription(_ dictionary: JSONDictionary) -> Bool {
        if let isActive = firstSubscriptionBool(in: dictionary, keys: [
            "isActive",
            "is_active",
            "active",
            "current",
            "isCurrent",
            "is_current",
            "subscribed",
            "isSubscribed",
            "is_subscribed",
            "hasActiveSubscription",
            "has_active_subscription"
        ]) {
            return isActive
        }

        if let status = JSONLookup(dictionary).firstString([
            "status",
            "subscriptionStatus",
            "subscription_status",
            "state"
        ]) {
            let normalized = status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")

            if activeSubscriptionStatuses.contains(normalized) {
                return true
            }
            if inactiveSubscriptionStatuses.contains(normalized) {
                return false
            }
        }

        return true
    }

    private static func firstSubscriptionBool(in value: Any, keys: [String]) -> Bool? {
        if let dictionary = rawDictionaryIfPresent(from: value) {
            for key in keys {
                if let bool = boolFromSubscriptionValue(dictionary[key]?.value) {
                    return bool
                }
            }

            for nested in dictionary.values {
                if let bool = firstSubscriptionBool(in: nested.value, keys: keys) {
                    return bool
                }
            }
            return nil
        }

        if let array = directArray(from: value) {
            for nested in array {
                if let bool = firstSubscriptionBool(in: nested, keys: keys) {
                    return bool
                }
            }
        }

        return nil
    }

    private static func boolFromSubscriptionValue(_ value: Any?) -> Bool? {
        switch unwrapped(value) {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int != 0
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1", "active", "current", "subscribed":
                return true
            case "false", "no", "0", "inactive", "expired", "canceled", "cancelled":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func hasAgentCustomizationIdentity(_ dictionary: JSONDictionary) -> Bool {
        JSONLookup(dictionary).containsAnyKey("agentId", "agent_id", "id")
    }

    private static func rawDictionary(from lookup: JSONLookup) -> JSONDictionary {
        (lookup.rawAnyCodable.value as? JSONDictionary) ?? [:]
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
    func makeAccountAgentCustomization(from dictionary: [String: Any]) -> GrokAgentCustomization? {
        GrokAccountParser.makeAgentCustomization(from: dictionary)
    }

    func makeAccountAgentCustomizationsResponse(from json: Any) -> GrokAgentCustomizationsResponse {
        GrokAccountParser.makeAgentCustomizationsResponse(from: json)
    }

    func parsedAccountAgentCustomizationDictionaries(from value: Any) -> [[String: AnyCodable]] {
        GrokAccountParser.agentCustomizationDictionaries(from: value)
    }

    func makeAccountSubscriptionsResponse(from json: Any) -> GrokSubscriptionsResponse {
        GrokAccountParser.makeSubscriptionsResponse(from: json)
    }

    func makeAccountSubscription(from dictionary: [String: Any]) -> GrokSubscription {
        GrokAccountParser.makeSubscription(from: dictionary)
    }

    func parsedAccountSubscriptionDictionaries(from value: Any) -> [[String: AnyCodable]] {
        GrokAccountParser.subscriptionDictionaries(from: value)
    }
}
