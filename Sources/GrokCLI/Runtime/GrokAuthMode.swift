import Foundation

enum GrokAuthMode: String, Codable {
    case web
    case xaiOAuth = "xai-oauth"

    static let environmentKey = "GROK_AUTH_MODE"

    static func parse(_ rawValue: String?) -> GrokAuthMode? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return nil
        }

        switch value.replacingOccurrences(of: "_", with: "-") {
        case "web", "cookie", "cookies", "browser", "grok":
            return .web
        case "oauth", "xai", "xai-oauth", "xai-oauth-api":
            return .xaiOAuth
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .web:
            return "Grok web"
        case .xaiOAuth:
            return "xAI OAuth"
        }
    }
}

