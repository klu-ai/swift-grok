import Foundation

// MARK: - Error Handling
public enum GrokError: Error, Equatable, LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case notFound
    case accessDenied(String)
    case antiBotRejected(String)
    case apiError(String)
    case streamingError

    public static func == (lhs: GrokError, rhs: GrokError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidCredentials, .invalidCredentials),
             (.unauthorized, .unauthorized),
             (.notFound, .notFound),
             (.streamingError, .streamingError):
            return true
        case (.apiError(let lhsMessage), .apiError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.accessDenied(let lhsMessage), .accessDenied(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.antiBotRejected(let lhsMessage), .antiBotRejected(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.networkError, .networkError),
             (.decodingError, .decodingError):
            // Note: Cannot compare the associated Error values directly
            // Just checking if they are the same type of error
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid or missing Grok credentials"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Could not decode Grok response: \(error.localizedDescription)"
        case .unauthorized:
            return "Grok rejected the saved cookies. Re-run `grok auth generate` after logging in."
        case .notFound:
            return "Grok API endpoint was not found"
        case .accessDenied(let message):
            return message
        case .antiBotRejected(let message):
            return message
        case .apiError(let message):
            return message
        case .streamingError:
            return "Could not read Grok streaming response"
        }
    }
}
