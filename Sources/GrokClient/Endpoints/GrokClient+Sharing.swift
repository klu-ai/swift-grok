import Foundation

extension GrokClient {
    private typealias JSONDictionary = [String: Any]

    private static let sharingWrapperKeys = [
        "shareLinks",
        "share_links",
        "items",
        "result",
        "data"
    ]
    private static let sharingURLKeys = [
        "url",
        "shareUrl",
        "share_url",
        "link",
        "shareLink",
        "share_link"
    ]
    private static let sharingIDKeys = [
        "publicId",
        "public_id",
        "token",
        "id",
        "shareId",
        "share_id",
        "shareLinkId",
        "share_link_id"
    ]

    public func shareLinkURL(
        conversationId: String,
        responseId: String? = nil,
        pageSize: Int = 100
    ) async throws -> String {
        try await shareLinkURL(
            conversationId: conversationId,
            responseId: responseId,
            options: GrokShareLinkOptions(pageSize: pageSize)
        )
    }

    public func shareLinkURL(
        conversationId: String,
        responseId: String? = nil,
        options: GrokShareLinkOptions
    ) async throws -> String {
        var queryItems = [
            URLQueryItem(name: "pageSize", value: String(options.pageSize)),
            URLQueryItem(name: "conversationId", value: conversationId)
        ]
        if let responseId, !responseId.isEmpty {
            queryItems.append(URLQueryItem(name: "responseId", value: responseId))
        }

        let path = try endpointPath(["share_links"], queryItems: queryItems)
        let request = try makeRequest(path: path, method: "GET")
        let json = try await jsonObject(for: request)
        if let shareURL = firstShareLinkURL(in: json) {
            return shareURL
        }

        guard let responseId, !responseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.apiError("No existing share link found and no response ID available to create one")
        }

        return try await createShareLinkURL(
            conversationId: conversationId,
            responseId: responseId,
            options: options
        )
    }

    public func createShareLinkURL(conversationId: String, responseId: String) async throws -> String {
        try await createShareLinkURL(
            conversationId: conversationId,
            responseId: responseId,
            options: GrokShareLinkOptions()
        )
    }

    public func createShareLinkURL(
        conversationId: String,
        responseId: String,
        options: GrokShareLinkOptions
    ) async throws -> String {
        let payload: [String: Any] = [
            "responseId": responseId,
            "allowIndexing": options.allowIndexing
        ]
        let request = try makeRequest(
            path: try endpointPath(["conversations", conversationId, "share"], queryItems: []),
            method: "POST",
            payload: payload
        )
        let json = try await jsonObject(for: request)
        return try makeShareLinkURL(from: json)
    }

    private func makeShareLinkURL(from json: Any) throws -> String {
        if let url = firstShareLinkURL(in: json) {
            return url
        }

        throw GrokError.apiError("Share link response did not include a share URL")
    }

    private func firstShareLinkURL(in value: Any) -> String? {
        if let dictionary = value as? JSONDictionary {
            if let url = shareLinkURL(from: dictionary) {
                return url
            }

            for key in Self.sharingWrapperKeys {
                guard let nested = dictionary[key],
                      let url = firstShareLinkURL(in: nested) else {
                    continue
                }
                return url
            }

            for nested in dictionary.values {
                if let url = firstShareLinkURL(in: nested) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let url = firstShareLinkURL(in: nested) {
                    return url
                }
            }
        }

        return nil
    }

    private func shareLinkURL(from dictionary: JSONDictionary) -> String? {
        if let url = firstString(in: dictionary, keys: Self.sharingURLKeys)
            .flatMap(cleanShareLinkURL) {
            return url
        }

        if let shareID = firstString(in: dictionary, keys: Self.sharingIDKeys) {
            return shareLinkURL(fromIdentifier: shareID)
        }

        return nil
    }

    private func cleanShareLinkURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return trimmed
        }

        if trimmed.hasPrefix("grok.com/") {
            return "https://\(trimmed)"
        }

        if trimmed.hasPrefix("/share/") {
            return "https://grok.com\(trimmed)"
        }

        return shareLinkURL(fromIdentifier: trimmed)
    }

    private func shareLinkURL(fromIdentifier value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return trimmed
        }

        if trimmed.hasPrefix("grok.com/") {
            return "https://\(trimmed)"
        }

        if trimmed.hasPrefix("/share/") {
            return "https://grok.com\(trimmed)"
        }

        return "https://grok.com/share/\(encodedPathSegment(trimmed))"
    }

    private func firstString(in value: Any, keys: [String]) -> String? {
        if let dictionary = value as? JSONDictionary {
            for key in keys {
                if let string = dictionary[key] as? String, !string.isEmpty {
                    return string
                }
            }
            for nested in dictionary.values {
                if let string = firstString(in: nested, keys: keys) {
                    return string
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let string = firstString(in: nested, keys: keys) {
                    return string
                }
            }
        }

        return nil
    }
}
