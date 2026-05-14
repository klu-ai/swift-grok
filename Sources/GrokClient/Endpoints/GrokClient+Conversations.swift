import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GrokClient Conversations
extension GrokClient {
    /// Fetch a list of past conversations
    /// - Parameters:
    ///   - pageSize: The number of conversations to fetch (default 100)
    ///   - searchQuery: Optional query to search saved conversation threads.
    /// - Returns: An array of Conversation objects
    /// - Throws: Network, decoding, or API errors
    public func listConversations(pageSize: Int = 100, searchQuery: String? = nil) async throws -> [Conversation] {
        var queryItems = [
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        if let searchQuery = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !searchQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "searchQuery", value: searchQuery))
        }

        let path = try endpointPath(["conversations"], queryItems: queryItems)
        let request = try makeRequest(path: path, method: "GET")

        if isDebug {
            print("Debug URL: \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Raw JSON response:")
                print(jsonString)
                if let jsonDict = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Debug: JSON as Dictionary/Array:")
                    print(jsonDict)
                }
            }
        }

        let decoder = JSONDecoder()
        do {
            // new API format
            let conversationsResponse = try decoder.decode(ConversationsResponse.self, from: data)
            return conversationsResponse.conversations
        } catch {
            // old API format
            return try decoder.decode([Conversation].self, from: data)
        }
    }

    public func softDeleteConversation(conversationId: String) async throws {
        let path = try endpointPath(["conversations", "soft", conversationId], queryItems: [])
        try await sendVoid(path: path, method: "DELETE")
    }

    /// Get the response nodes for a conversation
    public func getResponseNodes(conversationId: String, includeThreads: Bool = false) async throws -> [ResponseNode] {
        let queryItems = includeThreads
            ? [URLQueryItem(name: "includeThreads", value: "true")]
            : []
        let path = try endpointPath(["conversations", conversationId, "response-node"], queryItems: queryItems)
        let request = try makeRequest(path: path, method: "GET")

        if isDebug {
            print("Debug URL: \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Response JSON from response-node:")
                print(jsonString)
            }
        }

        let decoder = JSONDecoder()
        do {
            // common wrapper keys
            struct ResponseNodesWrapper: Codable {
                let responseNodes: [ResponseNode]
            }
            struct NodesWrapper: Codable {
                let nodes: [ResponseNode]
            }
            struct ResponsesWrapper: Codable {
                let responses: [ResponseNode]
            }

            do {
                let wrapper = try decoder.decode(ResponseNodesWrapper.self, from: data)
                return wrapper.responseNodes
            } catch {
                do {
                    let wrapper = try decoder.decode(NodesWrapper.self, from: data)
                    return wrapper.nodes
                } catch {
                    do {
                        let wrapper = try decoder.decode(ResponsesWrapper.self, from: data)
                        return wrapper.responses
                    } catch {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            for (_, value) in json {
                                if let nodesArray = value as? [[String: Any]] {
                                    var nodes = [ResponseNode]()
                                    for nodeDict in nodesArray {
                                        if let responseId = nodeDict["responseId"] as? String,
                                           let sender = nodeDict["sender"] as? String {
                                            let parentResponseId = nodeDict["parentResponseId"] as? String
                                            nodes.append(ResponseNode(
                                                responseId: responseId,
                                                sender: sender,
                                                parentResponseId: parentResponseId
                                            ))
                                        }
                                    }
                                    if !nodes.isEmpty {
                                        return nodes
                                    }
                                }
                            }
                        }
                        // fallback
                        return try decoder.decode([ResponseNode].self, from: data)
                    }
                }
            }
        } catch {
            throw GrokError.decodingError(error)
        }
    }

    /// Load the detailed responses for a conversation
    /// - Parameter conversationId: The ID of the conversation
    /// - Parameter specificResponseIds: Optional array of specific response IDs to load, if nil will fetch all
    /// - Returns: An array of Response objects
    /// - Throws: Network, decoding, or API errors
    public func loadResponses(conversationId: String, specificResponseIds: [String]? = nil) async throws -> [Response] {
        var responseIds: [String] = []

        if let specificIds = specificResponseIds, !specificIds.isEmpty {
            responseIds = specificIds
        } else {
            do {
                let responseNodes = try await getResponseNodes(conversationId: conversationId)
                responseIds = responseNodes.map { $0.responseId }
                if isDebug {
                    print("Debug: Found \(responseIds.count) response IDs for this conversation")
                }
            } catch {
                if isDebug {
                    print("Debug: Failed to get response nodes: \(error)")
                }
            }
        }

        var requestBody: [String: Any] = [:]
        if !responseIds.isEmpty {
            requestBody["responseIds"] = responseIds
        }

        let path = try endpointPath(["conversations", conversationId, "load-responses"], queryItems: [])
        let request = try makeRequest(path: path, payload: requestBody)

        if isDebug {
            print("Debug URL: \(request.url?.absoluteString ?? "")")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        if isDebug {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Debug: Response JSON:")
                print(jsonString)
            }
        }

        let decoder = JSONDecoder()
        struct ResponsesWrapper: Codable {
            let responses: [Response]
        }

        do {
            let wrapper = try decoder.decode(ResponsesWrapper.self, from: data)
            return wrapper.responses
        } catch {
            do {
                return try decoder.decode([Response].self, from: data)
            } catch {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responsesArray = json["responses"] as? [[String: Any]] {
                    var responses: [Response] = []
                    for item in responsesArray {
                        if let responseId = item["responseId"] as? String,
                           let message = item["message"] as? String,
                           let sender = item["sender"] as? String,
                           let createTime = item["createTime"] as? String {
                            let parentResponseId = item["parentResponseId"] as? String
                            responses.append(Response(
                                responseId: responseId,
                                message: message,
                                sender: sender,
                                createTime: createTime,
                                parentResponseId: parentResponseId
                            ))
                        }
                    }
                    if !responses.isEmpty {
                        return responses
                    }
                }
                throw GrokError.decodingError(error)
            }
        }
    }

    public func getConversationV2(
        conversationId: String,
        includeWorkspaces: Bool = true,
        includeTaskResult: Bool = true
    ) async throws -> GrokConversationV2Response {
        let path = try endpointPath(
            ["conversations_v2", conversationId],
            queryItems: [
                URLQueryItem(name: "includeWorkspaces", value: String(includeWorkspaces)),
                URLQueryItem(name: "includeTaskResult", value: String(includeTaskResult))
            ]
        )
        let request = try makeRequest(path: path, method: "GET")
        let json = try await jsonObject(for: request)

        return makeConversationsEndpointConversationV2Response(from: json)
    }

    private func makeConversationsEndpointConversationV2Response(from json: Any) -> GrokConversationV2Response {
        let conversation = conversationsEndpointFirstDictionary(from: json, preferredKeys: ["conversation", "data", "result"])
        let conversationId = conversationsEndpointStringValue(conversation, keys: ["conversationId", "conversation_id", "id"])
        return GrokConversationV2Response(conversationId: conversationId, rawJSON: AnyCodable(json))
    }

    private func conversationsEndpointFirstDictionary(
        from json: Any,
        preferredKeys: [String]
    ) -> [String: Any]? {
        if let dictionary = json as? [String: Any] {
            for key in preferredKeys {
                if let nested = dictionary[key] as? [String: Any] {
                    return nested
                }
                if let nested = dictionary[key] as? [String: AnyCodable] {
                    return nested.mapValues(\.value)
                }
            }
            return dictionary
        }

        if let dictionary = json as? [String: AnyCodable] {
            for key in preferredKeys {
                if let nested = dictionary[key]?.value as? [String: Any] {
                    return nested
                }
                if let nested = dictionary[key]?.value as? [String: AnyCodable] {
                    return nested.mapValues(\.value)
                }
            }
            return dictionary.mapValues(\.value)
        }

        return nil
    }

    private func conversationsEndpointStringValue(
        _ dictionary: [String: Any]?,
        keys: [String]
    ) -> String? {
        guard let dictionary else {
            return nil
        }

        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
            if let value = dictionary[key] as? CustomStringConvertible {
                let string = value.description
                if !string.isEmpty {
                    return string
                }
            }
        }

        return nil
    }
}
