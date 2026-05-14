import Foundation

// MARK: - Response Models
public struct MessageResponse: Codable {
    public let message: String
    public let timestamp: Date?

    public init(message: String, timestamp: Date? = nil) {
        self.message = message
        self.timestamp = timestamp
    }
}

public struct GrokSpeechToTextResponse: Codable {
    public let text: String
    public let rawJSON: AnyCodable

    public init(text: String, rawJSON: AnyCodable) {
        self.text = text
        self.rawJSON = rawJSON
    }
}

public struct GrokRateLimit: Codable {
    public let modelName: String?
    public let remainingResponses: Int?
    public let resetAt: Date?
    public let resetAfterSeconds: Int?
    public let windowSeconds: Int?
    public let fetchedAt: Date
    public let rawJSON: AnyCodable

    public init(
        modelName: String? = nil,
        remainingResponses: Int? = nil,
        resetAt: Date? = nil,
        resetAfterSeconds: Int? = nil,
        windowSeconds: Int? = nil,
        fetchedAt: Date = Date(),
        rawJSON: AnyCodable
    ) {
        self.modelName = modelName
        self.remainingResponses = remainingResponses
        self.resetAt = resetAt
        self.resetAfterSeconds = resetAfterSeconds
        self.windowSeconds = windowSeconds
        self.fetchedAt = fetchedAt
        self.rawJSON = rawJSON
    }

    public var isLow: Bool {
        guard let remainingResponses else {
            return false
        }
        return remainingResponses < 10
    }

    public func secondsUntilReset(from now: Date = Date()) -> Int? {
        if let resetAt {
            return max(0, Int(ceil(resetAt.timeIntervalSince(now))))
        }

        if let resetAfterSeconds {
            let elapsed = now.timeIntervalSince(fetchedAt)
            return max(0, Int(ceil(TimeInterval(resetAfterSeconds) - elapsed)))
        }

        return nil
    }
}
