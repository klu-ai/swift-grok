import Foundation
import GrokClient

struct XAIOAuthResponsesStreamParser {
    private var responseId = ""
    private var accumulatedAnswer = ""
    private var yieldedFinal = false
    private var finished = false

    private typealias JSONDictionary = [String: Any]

    mutating func consume(line: String) throws -> ConversationResponse? {
        guard !finished else { return nil }

        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix(":") ||
            trimmed.hasPrefix("event:") ||
            trimmed.hasPrefix("id:") ||
            trimmed.hasPrefix("retry:") {
            return nil
        }

        if trimmed.hasPrefix("data:") {
            trimmed = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed == "[DONE]" {
            return finish()
        }

        guard trimmed.hasPrefix("{") else {
            return nil
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            return nil
        }

        if let error = json["error"] {
            throw GrokError.apiError(Self.describeAPIError(error))
        }

        let type = Self.stringValue(json, keys: ["type"]) ?? ""
        if type == "response.failed" || type == "response.error" {
            throw GrokError.apiError(Self.describeAPIError(json["error"] ?? json))
        }

        updateResponseId(from: json)

        if let token = outputDelta(from: json, type: type) {
            accumulatedAnswer += token
            return response(message: token, isThinking: false, isFinal: false)
        }

        if let token = reasoningDelta(from: json, type: type) {
            return response(message: token, isThinking: true, isFinal: false)
        }

        if isCompletionEvent(type: type) || (type.isEmpty && looksLikeFullResponse(json)) {
            return finish(message: flattenedText(from: json) ?? accumulatedAnswer)
        }

        return nil
    }

    mutating func finish() -> ConversationResponse? {
        finish(message: accumulatedAnswer)
    }

    private mutating func finish(message: String) -> ConversationResponse? {
        guard !yieldedFinal else {
            finished = true
            return nil
        }

        yieldedFinal = true
        finished = true
        return response(message: message, isThinking: false, isFinal: true)
    }

    private mutating func updateResponseId(from json: JSONDictionary) {
        if let response = Self.dictionary(json["response"]),
           let id = Self.stringValue(response, keys: ["id", "response_id", "responseId"]) {
            responseId = id
            return
        }

        if let id = Self.stringValue(json, keys: ["response_id", "responseId"]) {
            responseId = id
        }
    }

    private func response(message: String, isThinking: Bool, isFinal: Bool) -> ConversationResponse {
        ConversationResponse(
            message: message,
            conversationId: "xai-oauth",
            responseId: responseId,
            timestamp: Date(),
            isThinking: isThinking,
            isFinal: isFinal
        )
    }

    private func outputDelta(from json: JSONDictionary, type: String) -> String? {
        if type == "response.output_text.delta" || type.hasSuffix(".output_text.delta") {
            return Self.stringValueAllowingEmpty(json, keys: ["delta", "text"])
        }

        if type == "chat.completion.chunk",
           let choice = Self.firstDictionary(in: json["choices"]),
           let delta = Self.dictionary(choice["delta"]) {
            return Self.stringValueAllowingEmpty(delta, keys: ["content"])
        }

        return nil
    }

    private func reasoningDelta(from json: JSONDictionary, type: String) -> String? {
        if type == "response.reasoning_summary_text.delta" ||
            type.hasSuffix(".reasoning_summary_text.delta") ||
            (type.contains("reasoning") && type.hasSuffix(".delta")) {
            return Self.stringValueAllowingEmpty(json, keys: ["delta", "text"])
        }

        if type == "chat.completion.chunk",
           let choice = Self.firstDictionary(in: json["choices"]),
           let delta = Self.dictionary(choice["delta"]) {
            return Self.stringValueAllowingEmpty(delta, keys: ["reasoning_content", "reasoningContent"])
        }

        return nil
    }

    private func isCompletionEvent(type: String) -> Bool {
        type == "response.completed" || type == "response.done"
    }

    private func looksLikeFullResponse(_ json: JSONDictionary) -> Bool {
        Self.stringValue(json, keys: ["output_text"]) != nil || Self.dictionary(json["response"]) != nil
    }

    private func flattenedText(from json: JSONDictionary) -> String? {
        let response = Self.dictionary(json["response"]) ?? json
        if let outputText = Self.stringValue(response, keys: ["output_text", "outputText"]) {
            return outputText
        }

        guard let output = response["output"] as? [JSONDictionary] else {
            return nil
        }

        let pieces = output.flatMap { item -> [String] in
            var values: [String] = []
            if let text = Self.stringValue(item, keys: ["text"]) {
                values.append(text)
            }
            if let content = item["content"] as? [JSONDictionary] {
                values.append(contentsOf: content.compactMap {
                    Self.stringValue($0, keys: ["text"])
                })
            }
            return values
        }

        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    private static func dictionary(_ value: Any?) -> JSONDictionary? {
        value as? JSONDictionary
    }

    private static func firstDictionary(in value: Any?) -> JSONDictionary? {
        (value as? [JSONDictionary])?.first
    }

    private static func stringValue(_ dictionary: JSONDictionary?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func stringValueAllowingEmpty(_ dictionary: JSONDictionary?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func describeAPIError(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let dictionary = value as? JSONDictionary {
            for key in ["message", "error_description", "description", "code", "type"] {
                if let string = dictionary[key] as? String, !string.isEmpty {
                    return string
                }
            }
        }
        return String(describing: value)
    }
}
