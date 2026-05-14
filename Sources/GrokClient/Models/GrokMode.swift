import Foundation

public struct GrokMode: Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let summary: String
    public let isAvailable: Bool
    public let unavailableReason: String?
    public let minimumSubscriptionTier: String?

    public init(
        id: String,
        displayName: String? = nil,
        summary: String = "",
        isAvailable: Bool = true,
        unavailableReason: String? = nil,
        minimumSubscriptionTier: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.summary = summary
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
        self.minimumSubscriptionTier = minimumSubscriptionTier
    }

    public var unavailableDescription: String? {
        guard !isAvailable else {
            return nil
        }
        if let unavailableReason, !unavailableReason.isEmpty {
            return unavailableReason
        }
        if let minimumSubscriptionTier, !minimumSubscriptionTier.isEmpty {
            return "Requires \(minimumSubscriptionTier)"
        }
        return "Unavailable for this account"
    }

    public static let auto = GrokMode(
        id: "auto",
        displayName: "Auto",
        summary: "Chooses Fast or Expert"
    )

    public static let fast = GrokMode(
        id: "fast",
        displayName: "Fast",
        summary: "Quick responses"
    )

    public static let expert = GrokMode(
        id: "expert",
        displayName: "Expert",
        summary: "Thinks hard"
    )

    public static let grok43Beta = GrokMode(
        id: "grok-420-computer-use-sa",
        displayName: "Grok 4.3 (beta)",
        summary: "Uses Skills and Connectors"
    )

    public static let heavy = GrokMode(
        id: "heavy",
        displayName: "Heavy",
        summary: "Team of Experts"
    )

    public static let defaultMode = fast
    public static let knownModes = [auto, fast, expert, grok43Beta, heavy]

    public static func resolve(_ rawValue: String?) -> GrokMode {
        guard let rawValue else {
            return defaultMode
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultMode
        }

        let normalized = normalizedToken(trimmed)

        switch normalized {
        case "auto":
            return .auto
        case "fast":
            return .fast
        case "expert", "reasoning", "think":
            return .expert
        case "heavy":
            return .heavy
        case "grok-4.3", "grok-4-3", "grok-43", "4.3", "43", "beta", "grok-4.3-beta", "grok-4-3-beta", "grok-43-beta", "grok-420", "grok-420-computer-use-sa":
            return .grok43Beta
        default:
            return GrokMode(id: trimmed, displayName: trimmed, summary: "Custom web mode ID")
        }
    }

    public static func resolve(_ rawValue: String?, modes: [GrokMode]) -> GrokMode {
        guard let rawValue else {
            return modes.first { $0.id == defaultMode.id } ?? defaultMode
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return modes.first { $0.id == defaultMode.id } ?? defaultMode
        }

        let normalized = normalizedToken(trimmed)
        if let exactMode = modes.first(where: { mode in
            normalizedToken(mode.id) == normalized ||
                normalizedToken(mode.displayName) == normalized
        }) {
            return exactMode
        }

        let resolved = resolve(trimmed)
        if let catalogMode = modes.first(where: { $0.id == resolved.id }) {
            return catalogMode
        }
        return resolved
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
