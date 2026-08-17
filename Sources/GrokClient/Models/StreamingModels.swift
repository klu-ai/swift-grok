import Foundation

// MARK: - Streaming Response Models
internal struct StreamingResponse: Codable {
    let result: StreamingResult?
}

internal struct StreamingResult: Codable {
    let response: ResponseContent?
    let modelResponse: ModelResponse?
    let conversation: ConversationData?
    let responseId: String?
    let isThinking: Bool?
    let isSoftStop: Bool?
    let token: String?
    let userResponse: UserResponse?
    let finalMetadata: FinalMetadata?
}

internal struct ConversationData: Codable {
    let conversationId: String?
}

internal struct ResponseContent: Codable {
    let token: String?
    let modelResponse: ModelResponse?
    let responseId: String?
    let isThinking: Bool?
    let isSoftStop: Bool?
    let finalMetadata: FinalMetadata?
}

internal struct FinalMetadata: Codable {
    let followUpSuggestions: [String]?
    let feedbackLabels: [String]?
    let disclaimer: String?
    let toolsUsed: [String: AnyCodable]?
}

internal struct UserResponse: Codable {
    let responseId: String?
    let message: String?
    let sender: String?
}

// Add internal models for web search results and X posts
internal struct WebSearchResultInternal: Codable {
    let url: String
    let title: String
    let preview: String
    let searchEngineText: String
    let description: String
    let siteName: String
    let metadataTitle: String
    let creator: String
    let image: String
    let favicon: String
    let citationId: String
}

internal struct XPostInternal: Codable {
    let username: String
    let name: String
    let text: String
    let createTime: String
    let profileImageUrl: String
    let postId: String
    let citationId: String
    // Additional fields like parent, quote, viewCount are omitted for simplicity
}

internal struct ModelResponse: Codable {
    let message: String
    let responseId: String?
    let sender: String?
    let createTime: String?
    let parentResponseId: String?
    let webSearchResults: [WebSearchResultInternal]?
    let xposts: [XPostInternal]?

    // Helper functions to convert internal models to public models
    func extractWebSearchResults() -> [WebSearchResult]? {
        guard let results = webSearchResults else { return nil }

        // Filter out empty results and convert to public model
        return results.compactMap { result in
            // Skip empty URL entries
            guard !result.url.isEmpty else { return nil }

            return WebSearchResult(
                url: result.url,
                title: result.title,
                preview: result.preview,
                siteName: result.siteName.isEmpty ? nil : result.siteName,
                description: result.description.isEmpty ? nil : result.description,
                citationId: result.citationId.isEmpty ? nil : result.citationId
            )
        }
    }

    func extractXPosts() -> [XPost]? {
        guard let posts = xposts else { return nil }

        // Filter out empty posts and convert to public model
        return posts.compactMap { post in
            guard !post.username.isEmpty else { return nil }
            return XPost(
                username: post.username,
                name: post.name,
                text: post.text,
                postId: post.postId,
                createTime: post.createTime.isEmpty ? nil : post.createTime,
                profileImageUrl: post.profileImageUrl.isEmpty ? nil : post.profileImageUrl,
                citationId: post.citationId.isEmpty ? nil : post.citationId
            )
        }
    }
}
