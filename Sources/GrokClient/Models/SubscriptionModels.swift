import Foundation

public struct GrokSubscription {
    public let tier: String?
    public let name: String?
    public let status: String?
    public let isActive: Bool
    public let rawJSON: [String: AnyCodable]

    public init(
        tier: String? = nil,
        name: String? = nil,
        status: String? = nil,
        isActive: Bool = true,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.tier = tier
        self.name = name
        self.status = status
        self.isActive = isActive
        self.rawJSON = rawJSON
    }

    public var displayName: String {
        Self.displayName(tier: tier, name: name, rawJSON: rawJSON)
    }

    public static func displayName(
        tier: String?,
        name: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) -> String {
        let rawValues = [
            "subscriptionTier",
            "subscription_tier",
            "tier",
            "tierName",
            "tier_name",
            "plan",
            "planName",
            "plan_name",
            "productName",
            "product_name",
            "displayName",
            "display_name",
            "name",
            "title",
            "sku"
        ].compactMap { rawJSON[$0]?.value as? String }

        let tokens = ([tier, name].compactMap { $0 } + rawValues)
            .map(normalizedPlanToken)
            .filter { !$0.isEmpty }

        if tokens.contains(where: { $0.contains("heavy") }) {
            return "SuperGrok Heavy"
        }
        if tokens.contains(where: { $0.contains("supergrok") || ($0.contains("super") && $0.contains("grok")) }) {
            return "SuperGrok"
        }
        return "Grok"
    }

    private static func normalizedPlanToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }
}

public struct GrokSubscriptionsResponse {
    public let subscriptions: [GrokSubscription]
    public let currentSubscription: GrokSubscription?
    public let rawJSON: AnyCodable

    public init(
        subscriptions: [GrokSubscription],
        currentSubscription: GrokSubscription?,
        rawJSON: AnyCodable
    ) {
        self.subscriptions = subscriptions
        self.currentSubscription = currentSubscription
        self.rawJSON = rawJSON
    }

    public var displayName: String {
        currentSubscription?.displayName ?? "Grok"
    }
}
