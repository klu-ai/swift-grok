import Foundation
import GrokClient

struct XAIOAuthResponsesStreamParser {
    private var responseId = ""
    private var accumulatedAnswer = ""
    private var yieldedFinal = false
    private var finished = false
    private(set) var functionCalls: [XAIResponsesFunctionCall] = []
    private var pendingFunctionCalls: [String: PendingFunctionCall] = [:]

    private typealias JSONDictionary = [String: Any]

    private struct PendingFunctionCall {
        var id: String?
        var callID: String
        var name: String
        var arguments: String
        var status: String?

        var functionCall: XAIResponsesFunctionCall? {
            guard !callID.isEmpty || !name.isEmpty else { return nil }
            return XAIResponsesFunctionCall(
                id: id,
                callID: callID,
                name: name,
                arguments: arguments,
                status: status
            )
        }
    }

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
        captureFunctionCalls(from: json, type: type)

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

    private mutating func captureFunctionCalls(from json: JSONDictionary, type: String) {
        if let response = Self.dictionary(json["response"]),
           let result = Self.responsesResult(from: response) {
            appendFunctionCalls(result.functionCalls)
        } else if let result = Self.responsesResult(from: json) {
            appendFunctionCalls(result.functionCalls)
        }

        if let item = Self.dictionary(json["item"]) ?? Self.dictionary(json["output_item"]) {
            captureFunctionCallItem(item, finalize: type.hasSuffix(".done") || type == "response.output_item.done")
        }

        if type.contains("function_call_arguments") {
            captureFunctionCallArgumentsEvent(json, type: type)
        } else if type.contains("function_call"),
                  let call = XAIResponsesFunctionCall(json: json) {
            appendFunctionCalls([call])
        }
    }

    private mutating func captureFunctionCallItem(_ item: JSONDictionary, finalize: Bool) {
        guard Self.stringValue(item, keys: ["type"]) == "function_call" else {
            return
        }

        let id = Self.stringValue(item, keys: ["id"])
        let callID = Self.stringValue(item, keys: ["call_id", "callId"]) ?? id ?? ""
        let key = id ?? callID
        guard !key.isEmpty else {
            if let call = XAIResponsesFunctionCall(json: item) {
                appendFunctionCalls([call])
            }
            return
        }

        var pending = pendingFunctionCalls[key] ?? PendingFunctionCall(
            id: id,
            callID: callID,
            name: "",
            arguments: "",
            status: nil
        )
        pending.id = id ?? pending.id
        pending.callID = callID.isEmpty ? pending.callID : callID
        pending.name = Self.stringValue(item, keys: ["name"]) ?? pending.name
        pending.arguments = Self.stringValueAllowingEmpty(item, keys: ["arguments"]) ?? pending.arguments
        pending.status = Self.stringValue(item, keys: ["status"]) ?? pending.status
        pendingFunctionCalls[key] = pending

        if finalize, let call = pending.functionCall {
            appendFunctionCalls([call])
            pendingFunctionCalls.removeValue(forKey: key)
        }
    }

    private mutating func captureFunctionCallArgumentsEvent(_ json: JSONDictionary, type: String) {
        let key = Self.stringValue(json, keys: ["item_id", "itemId", "call_id", "callId", "output_index", "outputIndex"])
        guard let key, !key.isEmpty else {
            return
        }

        var pending = pendingFunctionCalls[key] ?? PendingFunctionCall(
            id: Self.stringValue(json, keys: ["item_id", "itemId"]),
            callID: Self.stringValue(json, keys: ["call_id", "callId"]) ?? "",
            name: Self.stringValue(json, keys: ["name"]) ?? "",
            arguments: "",
            status: Self.stringValue(json, keys: ["status"])
        )
        pending.callID = Self.stringValue(json, keys: ["call_id", "callId"]) ?? pending.callID
        pending.name = Self.stringValue(json, keys: ["name"]) ?? pending.name
        pending.status = Self.stringValue(json, keys: ["status"]) ?? pending.status

        if let delta = Self.stringValueAllowingEmpty(json, keys: ["delta", "arguments_delta", "argumentsDelta"]) {
            pending.arguments += delta
        }
        if let arguments = Self.stringValueAllowingEmpty(json, keys: ["arguments"]) {
            pending.arguments = arguments
        }

        pendingFunctionCalls[key] = pending
        if type.hasSuffix(".done"), let call = pending.functionCall {
            appendFunctionCalls([call])
            pendingFunctionCalls.removeValue(forKey: key)
        }
    }

    private mutating func appendFunctionCalls(_ calls: [XAIResponsesFunctionCall]) {
        for call in calls where !call.callID.isEmpty || !call.name.isEmpty {
            if let index = functionCalls.firstIndex(where: { existing in
                (!call.callID.isEmpty && existing.callID == call.callID) ||
                    (call.callID.isEmpty && !call.name.isEmpty && existing.name == call.name)
            }) {
                functionCalls[index] = call
            } else {
                functionCalls.append(call)
            }
        }
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

    private static func responsesResult(from dictionary: JSONDictionary) -> XAIResponsesResult? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(XAIResponsesResult.self, from: data)
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
