import Foundation
import GrokClient

struct CLIJSONError: Encodable {
    let code: String
    let message: String
    let exitCode: Int32
    let recoverable: Bool
    let rawMessage: String?
}

struct CLIJSONResult: Encodable {
    let schema: String
    let ok: Bool
    let command: String
    let subcommand: String?
    let category: String
    let data: AnyCodable?
    let error: CLIJSONError?
    let meta: [String: AnyCodable]

    init(
        ok: Bool,
        command: String,
        subcommand: String? = nil,
        category: String,
        data: AnyCodable? = nil,
        error: CLIJSONError? = nil,
        meta: [String: AnyCodable] = [:]
    ) {
        self.schema = "grok.cli.result.v1"
        self.ok = ok
        self.command = command
        self.subcommand = subcommand
        self.category = category
        self.data = data
        self.error = error
        self.meta = meta
    }
}

struct CLIJSONEvent: Encodable {
    let schema: String
    let sequence: Int
    let event: String
    let data: AnyCodable

    init(sequence: Int, event: String, data: AnyCodable) {
        self.schema = "grok.cli.event.v1"
        self.sequence = sequence
        self.event = event
        self.data = data
    }
}

extension GrokCLI {
    static func isJSONRequested(_ args: [String]) -> Bool {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--json" {
                return true
            }
            if arg.hasPrefix("--format="), String(arg.dropFirst("--format=".count)).lowercased() == "json" {
                return true
            }
            if arg == "--format", index + 1 < args.count, args[index + 1].lowercased() == "json" {
                return true
            }
            index += 1
        }
        return false
    }

    static func defaultJSONMeta(debug: Bool = false, warnings: [String] = []) -> [String: AnyCodable] {
        [
            "format": AnyCodable("json"),
            "version": AnyCodable("1"),
            "debug": AnyCodable(debug),
            "warnings": AnyCodable(warnings)
        ]
    }

    static func printJSONResult(
        command: String,
        subcommand: String? = nil,
        category: String,
        data: AnyCodable,
        debug: Bool = false,
        warnings: [String] = []
    ) throws {
        let result = CLIJSONResult(
            ok: true,
            command: command,
            subcommand: subcommand,
            category: category,
            data: data,
            meta: defaultJSONMeta(debug: debug, warnings: warnings)
        )
        try printEncodedJSON(result, prettyPrinted: true)
    }

    static func printJSONError(
        command: String,
        subcommand: String? = nil,
        message: String,
        code: String = "api_error",
        exitCode: Int32,
        recoverable: Bool = false,
        rawMessage: String? = nil,
        debug: Bool = false
    ) {
        let result = CLIJSONResult(
            ok: false,
            command: command,
            subcommand: subcommand,
            category: "error",
            error: CLIJSONError(
                code: code,
                message: message,
                exitCode: exitCode,
                recoverable: recoverable,
                rawMessage: rawMessage
            ),
            meta: defaultJSONMeta(debug: debug)
        )
        try? printEncodedJSON(result, prettyPrinted: true)
    }

    static func printJSONErrorEvent(
        sequence: Int,
        error: Error,
        exitCode: Int32,
        debug: Bool = false
    ) throws {
        try printJSONErrorEvent(
            sequence: sequence,
            message: jsonErrorMessage(for: error),
            code: jsonErrorCode(for: error),
            exitCode: exitCode,
            recoverable: isRecoverableJSONError(error),
            rawMessage: error.localizedDescription,
            debug: debug
        )
    }

    static func printJSONErrorEvent(
        sequence: Int,
        message: String,
        code: String = "api_error",
        exitCode: Int32,
        recoverable: Bool = false,
        rawMessage: String? = nil,
        debug: Bool = false
    ) throws {
        var data: [String: AnyCodable] = [
            "code": AnyCodable(code),
            "message": AnyCodable(message),
            "exitCode": AnyCodable(Int(exitCode)),
            "recoverable": AnyCodable(recoverable),
            "debug": AnyCodable(debug)
        ]
        if let rawMessage {
            data["rawMessage"] = AnyCodable(rawMessage)
        }
        try printJSONEvent(
            sequence: sequence,
            event: "error",
            data: AnyCodable(data)
        )
    }

    static func printJSONError(
        command: String,
        subcommand: String? = nil,
        error: Error,
        exitCode: Int32,
        debug: Bool = false
    ) {
        printJSONError(
            command: command,
            subcommand: subcommand,
            message: jsonErrorMessage(for: error),
            code: jsonErrorCode(for: error),
            exitCode: exitCode,
            recoverable: isRecoverableJSONError(error),
            rawMessage: error.localizedDescription,
            debug: debug
        )
    }

    static func printJSONEvent(sequence: Int, event: String, data: AnyCodable) throws {
        try printEncodedJSON(
            CLIJSONEvent(sequence: sequence, event: event, data: data),
            prettyPrinted: false
        )
    }

    static func printEncodedJSON<T: Encodable>(_ value: T, prettyPrinted: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw GrokError.apiError("Could not encode JSON output")
        }
        print(json)
        fflush(stdout)
    }

    static func anyCodable<T: Encodable>(_ value: T) throws -> AnyCodable {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return AnyCodable(object)
    }

    static func jsonErrorCode(for error: Error) -> String {
        guard let grokError = error as? GrokError else {
            return "api_error"
        }

        switch grokError {
        case .invalidCredentials, .unauthorized:
            return "auth_error"
        case .accessDenied:
            return "access_denied"
        case .antiBotRejected:
            return "anti_bot_rejected"
        case .networkError:
            return "network_error"
        case .decodingError:
            return "decoding_error"
        case .notFound:
            return "not_found"
        case .apiError:
            return rateLimitMessage(for: error) == nil ? "api_error" : "rate_limit"
        case .streamingError:
            return "streaming_error"
        }
    }

    static func isRecoverableJSONError(_ error: Error) -> Bool {
        guard let grokError = error as? GrokError else {
            return false
        }
        switch grokError {
        case .invalidCredentials, .unauthorized:
            return true
        case .antiBotRejected:
            return true
        case .accessDenied:
            return false
        default:
            return false
        }
    }

    static func jsonErrorMessage(for error: Error) -> String {
        rateLimitMessage(for: error) ?? error.localizedDescription
    }

    private static func rateLimitMessage(for error: Error) -> String? {
        let rawMessage = error.localizedDescription
        let normalized = rawMessage.lowercased()
        let isRateLimited =
            normalized.contains("http error: 429") ||
            normalized.contains("too many requests") && normalized.contains("\"code\":8")

        guard isRateLimited else {
            return nil
        }

        if let waitTime = waitTimeHint(in: rawMessage) {
            return "Message limit reached. Grok is rate limiting this account right now. Wait \(waitTime), then try again."
        }

        return "Message limit reached. Grok is rate limiting this account right now. Wait a few minutes, then try again. The Grok web app may show the exact reset time for your plan."
    }

    private static func waitTimeHint(in message: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\bwait\s+(\d+)\s+(second|minute|hour)s?\b"#
        ) else {
            return nil
        }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let numberRange = Range(match.range(at: 1), in: message),
              let unitRange = Range(match.range(at: 2), in: message) else {
            return nil
        }

        let number = String(message[numberRange])
        let unit = String(message[unitRange]).lowercased()
        let suffix = number == "1" ? "" : "s"
        return "\(number) \(unit)\(suffix)"
    }

    static func modeJSON(_ mode: GrokMode) -> [String: AnyCodable] {
        var json: [String: AnyCodable] = [
            "id": AnyCodable(mode.id),
            "displayName": AnyCodable(mode.displayName),
            "summary": AnyCodable(mode.summary),
            "available": AnyCodable(mode.isAvailable),
            "disabled": AnyCodable(!mode.isAvailable)
        ]
        if let unavailableReason = mode.unavailableReason {
            json["unavailableReason"] = AnyCodable(unavailableReason)
        }
        if let minimumSubscriptionTier = mode.minimumSubscriptionTier {
            json["minimumSubscriptionTier"] = AnyCodable(minimumSubscriptionTier)
        }
        return json
    }

    static func selectedModelJSON(
        currentMode: GrokMode,
        modes: [GrokMode] = GrokMode.knownModes,
        xaiOAuthModelIDs: [String] = [],
        xaiOAuthSelectable: Bool = false
    ) -> [String: AnyCodable] {
        var seenOAuthModelIDs = Set<String>()
        let uniqueOAuthModelIDs = xaiOAuthModelIDs.compactMap { modelID -> String? in
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seenOAuthModelIDs.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
        return [
            "currentModel": AnyCodable(modeJSON(currentMode)),
            "models": AnyCodable(modes.map { mode in
                var item = modeJSON(mode)
                item["selected"] = AnyCodable(mode.id == currentMode.id)
                return item
            }),
            "xaiOAuthModels": AnyCodable(uniqueOAuthModelIDs.map { modelID in
                var json: [String: AnyCodable] = [
                    "id": AnyCodable(modelID),
                    "source": AnyCodable("xai_oauth_api"),
                    "selected": AnyCodable(xaiOAuthSelectable && modelID == currentMode.id),
                    "disabled": AnyCodable(!xaiOAuthSelectable)
                ]
                if !xaiOAuthSelectable {
                    json["unavailableReason"] = AnyCodable("OAuth API model; web chat uses web modes")
                }
                return json
            }),
            "modelSources": AnyCodable([
                "webModes": AnyCodable(modes.count),
                "xaiOAuthModels": AnyCodable(uniqueOAuthModelIDs.count)
            ])
        ]
    }

    static func assistantResponseJSON(
        response: ConversationResponse,
        mode: GrokMode,
        request: [String: AnyCodable],
        input: [String: AnyCodable]? = nil
    ) -> [String: AnyCodable] {
        let visibleMessage = GrokStreamMarkupParser.visibleText(from: response.message)
        var data: [String: AnyCodable] = [
            "message": AnyCodable(visibleMessage),
            "conversationId": AnyCodable(response.conversationId),
            "responseId": AnyCodable(response.responseId),
            "model": AnyCodable(modeJSON(mode)),
            "sources": AnyCodable([
                "webSearchResults": AnyCodable((response.webSearchResults ?? []).map(webSearchResultJSON)),
                "xposts": AnyCodable((response.xposts ?? []).map(xPostJSON))
            ]),
            "request": AnyCodable(request)
        ]
        if visibleMessage != response.message {
            data["rawMessage"] = AnyCodable(response.message)
        }
        if let input {
            data["input"] = AnyCodable(input)
        }
        if let timestamp = response.timestamp {
            data["timestamp"] = AnyCodable(timestamp.timeIntervalSince1970)
        }
        return data
    }

    static func webSearchResultJSON(_ result: WebSearchResult) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "url": AnyCodable(result.url),
            "title": AnyCodable(result.title),
            "preview": AnyCodable(result.preview)
        ]
        if let siteName = result.siteName {
            data["siteName"] = AnyCodable(siteName)
        }
        if let description = result.description {
            data["description"] = AnyCodable(description)
        }
        if let citationId = result.citationId {
            data["citationId"] = AnyCodable(citationId)
        }
        return data
    }

    static func xPostJSON(_ post: XPost) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "username": AnyCodable(post.username),
            "name": AnyCodable(post.name),
            "text": AnyCodable(post.text),
            "postId": AnyCodable(post.postId)
        ]
        if let createTime = post.createTime {
            data["createTime"] = AnyCodable(createTime)
        }
        if let profileImageUrl = post.profileImageUrl {
            data["profileImageUrl"] = AnyCodable(profileImageUrl)
        }
        if let citationId = post.citationId {
            data["citationId"] = AnyCodable(citationId)
        }
        return data
    }

    static func messageRequestJSON(
        reasoning: Bool,
        deepSearch: Bool,
        noSearch: Bool,
        privateMode: Bool,
        stream: Bool,
        workspaceIds: [String],
        fileAttachmentIds: [String]
    ) -> [String: AnyCodable] {
        [
            "reasoning": AnyCodable(reasoning),
            "deepSearch": AnyCodable(deepSearch),
            "noSearch": AnyCodable(noSearch),
            "private": AnyCodable(privateMode),
            "stream": AnyCodable(stream),
            "workspaceIds": AnyCodable(workspaceIds),
            "fileAttachmentIds": AnyCodable(fileAttachmentIds)
        ]
    }

    static func conversationsJSON(_ conversations: [Conversation]) -> [String: AnyCodable] {
        [
            "conversations": AnyCodable(conversations.map { conversation in
                [
                    "conversationId": AnyCodable(conversation.conversationId),
                    "title": AnyCodable(conversation.title),
                    "starred": AnyCodable(conversation.starred),
                    "createTime": AnyCodable(conversation.createTime),
                    "modifyTime": AnyCodable(conversation.modifyTime),
                    "temporary": AnyCodable(conversation.temporary),
                    "mediaTypes": AnyCodable(conversation.mediaTypes)
                ]
            })
        ]
    }

    static func conversationHistoryJSON(conversationId: String, responses: [Response]) -> [String: AnyCodable] {
        [
            "conversationId": AnyCodable(conversationId),
            "responses": AnyCodable(responses.map { response in
                var item: [String: AnyCodable] = [
                    "responseId": AnyCodable(response.responseId),
                    "sender": AnyCodable(response.sender),
                    "message": AnyCodable(response.message),
                    "createTime": AnyCodable(response.createTime)
                ]
                if let parentResponseId = response.parentResponseId {
                    item["parentResponseId"] = AnyCodable(parentResponseId)
                }
                return item
            })
        ]
    }

    static func resourceListJSON(
        resource: String,
        items: [AnyCodable],
        raw: AnyCodable? = nil,
        extra: [String: AnyCodable] = [:]
    ) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "resource": AnyCodable(resource),
            "items": AnyCodable(items)
        ]
        if let raw {
            data["raw"] = raw
        }
        for (key, value) in extra {
            data[key] = value
        }
        return data
    }

    static func resourceMutationJSON(
        resource: String,
        action: String,
        id: String? = nil,
        item: AnyCodable? = nil,
        raw: AnyCodable? = nil,
        extra: [String: AnyCodable] = [:],
        completed: Bool = true
    ) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "resource": AnyCodable(resource),
            "action": AnyCodable(action),
            "completed": AnyCodable(completed)
        ]
        if let id {
            data["id"] = AnyCodable(id)
        }
        if let item {
            data["item"] = item
        }
        if let raw {
            data["raw"] = raw
        }
        for (key, value) in extra {
            data[key] = value
        }
        return data
    }

    static func agentJSON(_ agent: GrokAgentCustomization, includeInstructions: Bool = false) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [
            "agentId": AnyCodable(agent.agentId),
            "name": AnyCodable(agent.name),
            "instructionLength": AnyCodable(agent.instructions.count),
            "instructionsRedacted": AnyCodable(!includeInstructions)
        ]
        if includeInstructions {
            data["instructions"] = AnyCodable(agent.instructions)
        }
        return data
    }

    static func taskJSON(_ task: GrokTask) -> [String: AnyCodable] {
        let raw = jsonDictionary(from: task)
        var data: [String: AnyCodable] = [:]
        if let id = task.taskId ?? task.id ?? stringValue(in: raw, keys: ["taskId", "task_id", "id"]) {
            data["id"] = AnyCodable(id)
        }
        if let taskId = task.taskId ?? stringValue(in: raw, keys: ["taskId", "task_id"]) {
            data["taskId"] = AnyCodable(taskId)
        }
        if let name = task.name ?? stringValue(in: raw, keys: ["name", "title"]) {
            data["name"] = AnyCodable(name)
        }
        if let prompt = task.prompt ?? stringValue(in: raw, keys: ["prompt"]) {
            data["prompt"] = AnyCodable(prompt)
        }
        if let isEnabled = task.isEnabled ?? boolValue(in: raw, keys: ["isEnabled", "is_enabled"]) {
            data["isEnabled"] = AnyCodable(isEnabled)
        }
        if let scheduleIsEnabled = scheduleEnabled(in: raw) {
            data["scheduleIsEnabled"] = AnyCodable(scheduleIsEnabled)
        }
        if let status = taskStatus(task) {
            data["status"] = AnyCodable(status)
        }
        if let schedule = scheduleValue(in: raw) {
            data["schedule"] = AnyCodable(schedule)
        }
        return data
    }

    static func taskResultJSON(_ result: GrokTaskResult) -> [String: AnyCodable] {
        let raw = jsonDictionary(from: result)
        var data: [String: AnyCodable] = [:]
        if let id = result.resultId ?? result.id ?? stringValue(in: raw, keys: ["taskResultId", "task_result_id", "resultId", "result_id", "id"]) {
            data["id"] = AnyCodable(id)
        }
        if let resultId = result.resultId ?? stringValue(in: raw, keys: ["taskResultId", "task_result_id", "resultId", "result_id"]) {
            data["resultId"] = AnyCodable(resultId)
        }
        if let taskId = result.taskId ?? stringValue(in: raw, keys: ["taskId", "task_id"]) {
            data["taskId"] = AnyCodable(taskId)
        }
        if let conversationId = result.conversationId ?? stringValue(in: raw, keys: ["conversationId", "conversation_id"]) {
            data["conversationId"] = AnyCodable(conversationId)
        }
        if let responseId = result.responseId ?? stringValue(in: raw, keys: ["responseId", "response_id"]) {
            data["responseId"] = AnyCodable(responseId)
        }
        if let message = result.message ?? stringValue(in: raw, keys: ["summary", "message", "content", "output", "text", "result"]) {
            data["message"] = AnyCodable(message)
        }
        if let status = result.status ?? stringValue(in: raw, keys: ["status", "state"]) {
            data["status"] = AnyCodable(status)
        }
        if let created = stringValue(in: raw, keys: ["createTime", "createdAt", "created_at", "completedAt", "completed_at", "lastRunAt", "last_run_at"]) {
            data["created"] = AnyCodable(created)
        }
        return data
    }

    static func skillJSON(_ skill: GrokSkill) -> [String: AnyCodable] {
        let raw = jsonDictionary(from: skill)
        var data: [String: AnyCodable] = [:]
        if let id = skill.skillId ?? skill.id ?? stringValue(in: raw, keys: ["skillId", "skill_id", "id"]) {
            data["id"] = AnyCodable(id)
        }
        if let skillId = skill.skillId ?? stringValue(in: raw, keys: ["skillId", "skill_id"]) {
            data["skillId"] = AnyCodable(skillId)
        }
        if let name = skill.name ?? skill.title ?? stringValue(in: raw, keys: ["displayName", "name", "title"]) {
            data["name"] = AnyCodable(name)
        }
        if let title = skill.title {
            data["title"] = AnyCodable(title)
        }
        if let status = stringValue(in: raw, keys: ["status", "state"]) {
            data["status"] = AnyCodable(status)
        }
        if let description = stringValue(in: raw, keys: ["description", "summary"]) {
            data["description"] = AnyCodable(description)
        }
        return data
    }

    static func workspaceJSON(_ workspace: GrokWorkspace) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [:]
        if let id = workspace.workspaceId ?? workspace.id {
            data["id"] = AnyCodable(id)
        }
        if let workspaceId = workspace.workspaceId {
            data["workspaceId"] = AnyCodable(workspaceId)
        }
        if let name = workspace.name ?? workspace.title {
            data["name"] = AnyCodable(name)
        }
        if let title = workspace.title {
            data["title"] = AnyCodable(title)
        }
        if let icon = workspace.icon {
            data["icon"] = AnyCodable(icon)
        }
        if let preferredModel = workspace.preferredModel {
            data["preferredModel"] = AnyCodable(preferredModel)
        }
        if let customPersonality = workspace.customPersonality {
            data["customPersonality"] = AnyCodable(customPersonality)
        }
        return data
    }

    static func assetJSON(_ asset: GrokAsset) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [:]
        if let id = asset.resolvedId {
            data["id"] = AnyCodable(id)
        }
        if let fileName = asset.fileName ?? asset.name {
            data["fileName"] = AnyCodable(fileName)
        }
        if let mimeType = asset.mimeType {
            data["mimeType"] = AnyCodable(mimeType)
        }
        return data
    }

    static func uploadJSON(_ response: GrokFileUploadResponse) -> [String: AnyCodable] {
        var data: [String: AnyCodable] = [:]
        if let id = response.uploadedFileId {
            data["id"] = AnyCodable(id)
        }
        if let fileName = response.fileName {
            data["fileName"] = AnyCodable(fileName)
        }
        if let asset = response.asset {
            data["asset"] = AnyCodable(assetJSON(asset))
        }
        return data
    }
}
