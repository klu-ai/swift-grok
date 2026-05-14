import Foundation

internal enum GrokModeParser {
    internal typealias JSONDictionary = [String: AnyCodable]

    internal struct ParsedModeAvailability {
        internal let isAvailable: Bool
        internal let reason: String?
        internal let minimumSubscriptionTier: String?
    }

    private static let modeCollectionKeys = [
        "modes",
        "modeItems",
        "mode_items",
        "models",
        "data",
        "result",
        "items"
    ]

    private static let modeIDKeys = [
        "id",
        "modeId",
        "mode_id",
        "modelId",
        "model_id",
        "slug",
        "value"
    ]

    private static let displayNameKeys = [
        "displayName",
        "display_name",
        "name",
        "title",
        "label"
    ]

    private static let summaryKeys = [
        "summary",
        "description",
        "subtitle"
    ]

    private static let reasonKeys = [
        "message",
        "reason",
        "description"
    ]

    private static let topLevelUnavailableReasonKeys = [
        "unavailableReason",
        "unavailable_reason",
        "reason",
        "message"
    ]

    private static let minimumSubscriptionTierKeys = [
        "minimumSubscriptionTier",
        "minimum_subscription_tier"
    ]

    internal static func modeDictionaries(from value: Any) -> [JSONDictionary] {
        JSONLookup(value).dictionaries(modeCollectionKeys)
    }

    internal static func makeMode(from dictionary: [String: Any]) -> GrokMode? {
        makeMode(from: JSONLookup(dictionary).rawAnyCodable.value as? JSONDictionary ?? [:])
    }

    internal static func makeMode(from dictionary: JSONDictionary) -> GrokMode? {
        let lookup = JSONLookup(dictionary)
        guard let id = lookup.string(modeIDKeys) else {
            return nil
        }

        let availability = modeAvailability(from: dictionary)
        return GrokMode(
            id: id,
            displayName: lookup.string(displayNameKeys),
            summary: lookup.string(summaryKeys) ?? "",
            isAvailable: availability.isAvailable,
            unavailableReason: availability.reason,
            minimumSubscriptionTier: availability.minimumSubscriptionTier
        )
    }

    internal static func modes(from value: Any) -> [GrokMode] {
        modeDictionaries(from: value)
            .compactMap { makeMode(from: $0) }
            .reduce(into: [GrokMode]()) { uniqueModes, mode in
                guard !uniqueModes.contains(where: { $0.id == mode.id }) else {
                    return
                }
                uniqueModes.append(mode)
            }
    }

    internal static func modeAvailability(from dictionary: [String: Any]) -> ParsedModeAvailability {
        modeAvailability(from: JSONLookup(dictionary).rawAnyCodable.value as? JSONDictionary ?? [:])
    }

    internal static func modeAvailability(from dictionary: JSONDictionary) -> ParsedModeAvailability {
        let lookup = JSONLookup(dictionary)

        if let availability = dictionaryValue(dictionary["availability"]?.value) {
            let availabilityLookup = JSONLookup(availability)
            if let availableValue = availability["available"]?.value {
                if let available = availableValue as? Bool {
                    return ParsedModeAvailability(
                        isAvailable: available,
                        reason: available ? nil : availabilityLookup.string(reasonKeys),
                        minimumSubscriptionTier: availabilityLookup.string(minimumSubscriptionTierKeys)
                    )
                }
                return ParsedModeAvailability(isAvailable: true, reason: nil, minimumSubscriptionTier: nil)
            }

            if let requiresUpgrade = dictionaryValue(availability["requiresUpgrade"]?.value) ??
                dictionaryValue(availability["requires_upgrade"]?.value) {
                let requiresUpgradeLookup = JSONLookup(requiresUpgrade)
                return ParsedModeAvailability(
                    isAvailable: false,
                    reason: requiresUpgradeLookup.string(reasonKeys),
                    minimumSubscriptionTier: requiresUpgradeLookup.string(minimumSubscriptionTierKeys)
                )
            }

            if let unavailable = dictionaryValue(availability["unavailable"]?.value) ??
                dictionaryValue(availability["disabled"]?.value) {
                let unavailableLookup = JSONLookup(unavailable)
                return ParsedModeAvailability(
                    isAvailable: false,
                    reason: unavailableLookup.string(reasonKeys),
                    minimumSubscriptionTier: unavailableLookup.string(minimumSubscriptionTierKeys)
                )
            }

            if boolValue(in: availability, keys: ["requiresUpgrade", "requires_upgrade"]) == true {
                return ParsedModeAvailability(
                    isAvailable: false,
                    reason: availabilityLookup.string(reasonKeys),
                    minimumSubscriptionTier: availabilityLookup.string(minimumSubscriptionTierKeys)
                )
            }
        }

        if let isAvailable = boolValue(in: dictionary, keys: ["available", "isAvailable", "is_available"]) {
            return ParsedModeAvailability(
                isAvailable: isAvailable,
                reason: isAvailable ? nil : lookup.string(topLevelUnavailableReasonKeys),
                minimumSubscriptionTier: lookup.string(minimumSubscriptionTierKeys)
            )
        }

        if let disabled = boolValue(in: dictionary, keys: ["disabled", "isDisabled", "is_disabled"]), disabled {
            return ParsedModeAvailability(
                isAvailable: false,
                reason: lookup.string(topLevelUnavailableReasonKeys),
                minimumSubscriptionTier: lookup.string(minimumSubscriptionTierKeys)
            )
        }

        return ParsedModeAvailability(isAvailable: true, reason: nil, minimumSubscriptionTier: nil)
    }

    private static func dictionaryValue(_ value: Any?) -> JSONDictionary? {
        switch value {
        case let dictionary as JSONDictionary:
            return dictionary
        case let dictionary as [String: Any]:
            return JSONLookup(dictionary).rawAnyCodable.value as? JSONDictionary
        default:
            return nil
        }
    }

    private static func boolValue(in dictionary: JSONDictionary, keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key]?.value as? Bool {
                return value
            }
        }
        return nil
    }
}
