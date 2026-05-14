import Foundation
import GrokClient
import Rainbow

class GrokCLIApp {
    static let shared = GrokCLIApp()

    private var client: GrokClient?
    private let configManager = ConfigManager()
    private var isDebug = false
    private var isQuiet = false
    private var currentConversationId: String?
    private var currentConversationTitle: String?
    private var lastResponseId: String?
    private var lastWebSearchResults: [WebSearchResult]?
    private var lastXPosts: [XPost]?
    private var currentPersonality: GrokClient.PersonalityType = .none
    private var currentMode: GrokMode = .defaultMode
    private var cachedModes: [GrokMode]?
    private var cachedSubscriptionDisplayName: String?
    private var lastRateLimit: GrokRateLimit?
    private var lastRateLimitModeId: String?
    private var lastRateLimitResetEstimate: RateLimitResetEstimate?
    private var lastRateLimitResetEstimateModeId: String?
    private var lastLoadedConversationMode: GrokMode?
    private var currentWorkspace: GrokWorkspace?
    private var attachedFileIds: [String] = []

    private init() {}

    // Enable debug mode
    func setDebugMode(_ enabled: Bool) {
        isDebug = enabled
    }

    // Get current debug mode state
    func getDebugMode() -> Bool {
        return isDebug
    }

    func setQuietMode(_ enabled: Bool) {
        isQuiet = enabled
    }

    func getQuietMode() -> Bool {
        isQuiet
    }

    // Reset the current conversation ID
    func resetConversation() {
        currentConversationId = nil
        currentConversationTitle = nil
        lastResponseId = nil
        lastWebSearchResults = nil
        lastXPosts = nil
    }

    func getCurrentWorkspace() -> GrokWorkspace? {
        currentWorkspace
    }

    func setCurrentWorkspace(_ workspace: GrokWorkspace?) {
        currentWorkspace = workspace
    }

    func getCurrentWorkspaceIds() -> [String] {
        guard let workspaceId = currentWorkspace?.workspaceId ?? currentWorkspace?.id else {
            return []
        }
        return [workspaceId]
    }

    func getAttachedFileIds() -> [String] {
        attachedFileIds
    }

    func addAttachedFileId(_ fileId: String) {
        guard !attachedFileIds.contains(fileId) else {
            return
        }
        attachedFileIds.append(fileId)
    }

    func clearAttachedFiles() {
        attachedFileIds.removeAll()
    }

    // Get the current conversation ID
    func getCurrentConversationId() -> String? {
        return currentConversationId
    }

    // Get the last response ID
    func getLastResponseId() -> String? {
        return lastResponseId
    }

    // Get the last web search results
    func getLastWebSearchResults() -> [WebSearchResult]? {
        return lastWebSearchResults
    }

    // Get the last X posts
    func getLastXPosts() -> [XPost]? {
        return lastXPosts
    }

    func shareLinkForCurrentConversation() async throws -> String {
        guard let conversationId = currentConversationId else {
            throw GrokError.apiError("No active conversation to share")
        }

        let client = try initializeClient()
        return try await client.shareLinkURL(conversationId: conversationId, responseId: lastResponseId)
    }

    func deleteCurrentConversation() async throws -> String {
        guard let conversationId = currentConversationId else {
            throw GrokError.apiError("No active conversation to delete")
        }
        let trimmedTitle = currentConversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationDisplayName: String
        if let trimmedTitle, !trimmedTitle.isEmpty {
            conversationDisplayName = trimmedTitle
        } else {
            conversationDisplayName = conversationId
        }

        let client = try initializeClient()
        try await client.softDeleteConversation(conversationId: conversationId)
        resetConversation()
        return conversationDisplayName
    }

    // Get current personality
    func getCurrentPersonality() -> GrokClient.PersonalityType {
        return currentPersonality
    }

    // Set current personality
    func setPersonality(_ personalityType: GrokClient.PersonalityType) {
        self.currentPersonality = personalityType
    }

    // Get current Grok web mode
    func getCurrentMode() -> GrokMode {
        return currentMode
    }

    // Set current Grok web mode
    func setCurrentMode(_ mode: GrokMode) {
        if currentMode.id != mode.id {
            lastRateLimit = nil
            lastRateLimitModeId = nil
        }
        self.currentMode = mode
    }

    func getLastLoadedConversationMode() -> GrokMode? {
        lastLoadedConversationMode
    }

    func loadModes() async -> [GrokMode] {
        if let cachedModes {
            return cachedModes
        }

        do {
            let client = try initializeClient()
            let modes = try await client.listModes()
            guard !modes.isEmpty else {
                return GrokMode.knownModes
            }
            cachedModes = modes
            return modes
        } catch {
            if isDebug {
                print("Debug: Could not load live modes: \(error.localizedDescription)")
            }
            return GrokMode.knownModes
        }
    }

    func refreshSubscriptionDisplayName() async throws -> String {
        if let cachedSubscriptionDisplayName {
            return cachedSubscriptionDisplayName
        }

        let client = try initializeClient()
        let response = try await client.subscriptionsResponse()
        let displayName = response.displayName
        cachedSubscriptionDisplayName = displayName
        return displayName
    }

    func currentSubscriptionDisplayName() -> String {
        cachedSubscriptionDisplayName ?? "Grok"
    }

    @discardableResult
    func refreshRateLimit(for mode: GrokMode) async -> GrokRateLimit? {
        guard let client else {
            return cachedRateLimit(for: mode)
        }

        do {
            let rateLimit = try await client.rateLimits(mode: mode)
            lastRateLimit = rateLimit
            lastRateLimitModeId = mode.id
            return rateLimit
        } catch {
            if isDebug {
                print("Debug: Could not fetch rate limits: \(error.localizedDescription)")
            }
            return cachedRateLimit(for: mode)
        }
    }

    func refreshRateLimitStatus(for mode: GrokMode) async -> String? {
        guard let rateLimit = await refreshRateLimit(for: mode) else {
            return nil
        }
        return rateLimitStatusText(for: rateLimit)
    }

    func refreshRateLimitSummary(for mode: GrokMode) async -> String {
        guard let rateLimit = await refreshRateLimit(for: mode) else {
            return currentRateLimitSummary(for: mode)
        }

        let estimate = await inferredRateLimitReset(for: rateLimit, mode: mode)
        lastRateLimitResetEstimate = estimate
        lastRateLimitResetEstimateModeId = mode.id
        return rateLimitSummaryText(for: rateLimit, mode: mode, resetEstimate: estimate)
    }

    func currentRateLimitStatus(for mode: GrokMode) -> String? {
        guard let lastRateLimit = cachedRateLimit(for: mode) else {
            return nil
        }
        return rateLimitStatusText(for: lastRateLimit)
    }

    func currentRateLimitSummary(for mode: GrokMode) -> String {
        guard let rateLimit = cachedRateLimit(for: mode) else {
            return """
            Rate limits for \(mode.displayName) (\(mode.id))
            Current rate-limit data is unavailable.
            """
        }

        let resetEstimate = lastRateLimitResetEstimateModeId == mode.id ? lastRateLimitResetEstimate : nil
        return rateLimitSummaryText(for: rateLimit, mode: mode, resetEstimate: resetEstimate)
    }

    func currentRateLimitWarning(for mode: GrokMode) -> String? {
        guard let rateLimit = cachedRateLimit(for: mode),
              let remaining = rateLimit.remainingResponses,
              remaining < 10 else {
            return nil
        }

        let noun = remaining == 1 ? "response" : "responses"
        var warning = "Warning: \(remaining) \(noun) remaining"
        if let reset = resetDurationDescription(for: rateLimit) {
            warning += "; resets in \(reset)"
        }
        return warning + "."
    }

    private func cachedRateLimit(for mode: GrokMode) -> GrokRateLimit? {
        guard lastRateLimitModeId == mode.id else {
            return nil
        }
        return lastRateLimit
    }

    private func rateLimitStatusText(for rateLimit: GrokRateLimit) -> String? {
        guard let remaining = rateLimit.remainingResponses, remaining < 10 else {
            return nil
        }

        var status = "\(remaining) left"
        if let reset = resetDurationDescription(for: rateLimit) {
            status += " | reset \(reset)"
        }
        return status
    }

    private func rateLimitSummaryText(
        for rateLimit: GrokRateLimit,
        mode: GrokMode,
        resetEstimate: RateLimitResetEstimate? = nil
    ) -> String {
        var lines = ["Rate limits for \(mode.displayName) (\(mode.id))"]
        if let modelName = rateLimit.modelName, !modelName.isEmpty, modelName != mode.id {
            lines.append("API model: \(modelName)")
        }

        if let remaining = rateLimit.remainingResponses {
            let noun = remaining == 1 ? "response" : "responses"
            lines.append("Remaining responses: \(remaining) \(noun)")
        } else {
            lines.append("Remaining responses: unavailable")
        }

        if let reset = resetDurationDescription(for: rateLimit) {
            lines.append("Resets in \(reset)")
        } else if rateLimit.resetAt != nil || rateLimit.resetAfterSeconds != nil {
            lines.append("Resets now")
        } else if let resetEstimate {
            let reset = durationDescription(seconds: resetEstimate.secondsUntilReset)
            lines.append("Resets in about \(reset)")
            lines.append("Window: rolling \(durationDescription(seconds: resetEstimate.windowSeconds))")
        } else if rateLimit.windowSeconds != nil {
            lines.append("Resets as messages age out of the rolling \(durationDescription(seconds: rateLimit.windowSeconds ?? 0)) window.")
        }

        return lines.joined(separator: "\n")
    }

    private struct RateLimitResetEstimate {
        let secondsUntilReset: Int
        let windowSeconds: Int
    }

    private func inferredRateLimitReset(for rateLimit: GrokRateLimit, mode: GrokMode) async -> RateLimitResetEstimate? {
        guard rateLimit.resetAt == nil,
              rateLimit.resetAfterSeconds == nil,
              rateLimit.remainingResponses != nil,
              let windowSeconds = rateLimit.windowSeconds,
              windowSeconds > 0,
              let client else {
            return nil
        }

        do {
            let now = Date()
            let windowStart = now.addingTimeInterval(-TimeInterval(windowSeconds))
            let conversations = try await client.listConversations(pageSize: 20)
                .filter { !$0.temporary }
            var timestamps: [Date] = []

            for conversation in conversations.prefix(10) {
                let responses = try await client.loadResponses(conversationId: conversation.conversationId)
                let userResponses = responses.filter(Self.isUserResponse)
                timestamps.append(contentsOf: candidateRateLimitDates(
                    from: userResponses.map(\.createTime),
                    since: windowStart,
                    through: now
                ))
            }

            guard let oldest = timestamps.min() else {
                return nil
            }

            let resetAt = oldest.addingTimeInterval(TimeInterval(windowSeconds))
            return RateLimitResetEstimate(
                secondsUntilReset: max(0, Int(ceil(resetAt.timeIntervalSince(now)))),
                windowSeconds: windowSeconds
            )
        } catch {
            if isDebug {
                print("Debug: Could not infer rate-limit reset for \(mode.id): \(error.localizedDescription)")
            }
            return nil
        }
    }

    private func candidateRateLimitDates(from values: [String], since windowStart: Date, through now: Date) -> [Date] {
        values.compactMap(parseGrokTimestamp).filter { date in
            date >= windowStart && date <= now
        }
    }

    private func parseGrokTimestamp(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let formatterWithFractions = ISO8601DateFormatter()
        formatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractions.date(from: trimmed) {
            return date
        }

        return ISO8601DateFormatter().date(from: trimmed)
    }

    private func resetDurationDescription(for rateLimit: GrokRateLimit) -> String? {
        guard let seconds = rateLimit.secondsUntilReset() else {
            return nil
        }
        return durationDescription(seconds: seconds)
    }

    private func durationDescription(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds == 0 {
            return "now"
        }
        if seconds < 60 {
            return "\(seconds)s"
        }

        let totalMinutes = Int(ceil(Double(seconds) / 60.0))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 24 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
    }

    // Centralized error handling method
    @discardableResult
    func handleError(
        _ error: Error,
        debug: Bool,
        statusLine: CLIOutput.TransientStatusLine? = nil
    ) async -> Bool {
        func write(_ message: String = "") {
            if isQuiet {
                CLIOutput.stderr(message)
            } else {
                print(message)
            }
        }

        if statusLine == nil, !isQuiet, GrokCLI.stdoutIsTTY() {
            print("\r\u{001B}[2K", terminator: "")
        }
        let displayMessage = userFriendlyErrorMessage(for: error)
        if let statusLine {
            statusLine.update(text: "Error: \(displayMessage)".red)
        } else {
            write("Error: \(displayMessage)".red)
        }
        if debug {
            statusLine?.clear()
            if displayMessage != error.localizedDescription {
                write("Debug: Raw error: \(error.localizedDescription)".cyan)
            }
            write("Debug: Error details: \(error)".cyan)
            write("Debug: Error type: \(type(of: error))".cyan)
        }

        guard isAuthenticationError(error) else {
            if statusLine != nil {
                statusLine?.finish(finalText: "Error: \(displayMessage)".red)
            }
            return false
        }

        client = nil
        cachedModes = nil
        cachedSubscriptionDisplayName = nil
        if let statusLine {
            statusLine.update(text: "Authentication failed; refreshing browser cookies...".yellow)
        } else {
            write("Authentication failed. Your saved Grok browser cookies may have expired.".yellow)
            write("Trying to refresh credentials from your browser...".cyan)
        }

        do {
            statusLine?.update(text: "Extracting cookies from browser...".cyan)
            let credentialsPath = try await generateCredentials(
                args: statusLine == nil ? [] : ["--quiet"],
                suppressOutput: statusLine != nil
            )
            if let statusLine {
                statusLine.update(text: "Credentials refreshed".green)
            } else {
                write("Successfully refreshed credentials from browser.".green)
                write("Saved to: \(credentialsPath)".cyan)
                write("Retry your last message or command.".yellow)
            }
            return true
        } catch {
            let refreshMessage = "Automatic browser credential refresh failed: \(error.localizedDescription)"
            if let statusLine {
                statusLine.finish(finalText: refreshMessage.red)
            } else {
                write(refreshMessage.red)
                write("Please log in to Grok in your browser, then run 'auth' here or 'grok auth' from your shell.".yellow)
            }
            return false
        }
    }

    private func userFriendlyErrorMessage(for error: Error) -> String {
        if let rateLimitMessage = rateLimitMessage(for: error) {
            return rateLimitMessage
        }
        return error.localizedDescription
    }

    private func rateLimitMessage(for error: Error) -> String? {
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

    private func waitTimeHint(in message: String) -> String? {
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

    func isAuthenticationError(_ error: Error) -> Bool {
        guard let grokError = error as? GrokError else {
            return false
        }

        switch grokError {
        case .invalidCredentials, .unauthorized:
            return true
        case .accessDenied:
            return false
        case .apiError(let message):
            let normalized = message.lowercased()
            return normalized.contains("http error: 401") ||
                normalized.contains("unauthorized") ||
                normalized.contains("unauthenticated") ||
                normalized.contains("not authenticated") ||
                normalized.contains("authentication required") ||
                normalized.contains("login required") ||
                normalized.contains("log in") ||
                (normalized.contains("cookie") && (normalized.contains("invalid") || normalized.contains("expired"))) ||
                normalized.contains("csrf") ||
                normalized.contains("sso")
        default:
            return false
        }
    }

    // Load cookies directly from GrokCookies.swift file
    internal func getCookiesFromFile() throws -> [String: String] {
        // Try to find GrokCookies.swift in standard locations
        let potentialPaths = ["./GrokCookies.swift", "../GrokCookies.swift", "../../GrokCookies.swift"]

        for path in potentialPaths {
            if FileManager.default.fileExists(atPath: path) {
                if isDebug {
                    print("Debug: Found GrokCookies.swift at \(path)")
                }

                // Read file content
                let fileContent = try String(contentsOfFile: path)

                // Very simple parser for Swift dictionary literals
                let cookieRegex = try NSRegularExpression(pattern: #""([^"]+)":\s*"([^"]+)""#)
                let cookies = cookieRegex.matches(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent)).reduce(into: [String: String]()) { result, match in
                    guard let keyRange = Range(match.range(at: 1), in: fileContent),
                          let valueRange = Range(match.range(at: 2), in: fileContent) else { return }
                    let key = String(fileContent[keyRange])
                    let value = String(fileContent[valueRange])
                    result[key] = value
                }

                if !cookies.isEmpty {
                    if isDebug {
                        print("Debug: Successfully extracted \(cookies.count) cookies from file")
                    }
                    return cookies
                }
            }
        }

        throw GrokError.invalidCredentials
    }

    // Initialize the Grok client using available authentication methods
    func initializeClient() throws -> GrokClient {
        if let existingClient = client {
            return existingClient
        }

        if isDebug {
            print("Debug: Attempting to initialize GrokClient...")
        }

        // Try different authentication methods in order of preference
        if let savedCredentialsPath = configManager.getSavedCredentialsPath() {
            if isDebug {
                print("Debug: Found saved credentials at \(savedCredentialsPath)")
            }
            do {
                client = try GrokClient.fromJSONFile(at: savedCredentialsPath, isDebug: isDebug)
                return client!
            } catch {
                if isDebug {
                    print("Debug: Saved credentials failed: \(error.localizedDescription)")
                }
            }
        }

        do {
            if isDebug {
                print("Debug: Trying to load cookies directly from GrokCookies.swift file...")
            }

            let cookies = try getCookiesFromFile()
            client = try GrokClient(cookies: cookies, isDebug: isDebug)
            return client!
        } catch {
            if isDebug {
                print("Debug: Could not load cookies from file: \(error.localizedDescription)")
            }
        }

        do {
            if isDebug {
                print("Debug: Trying to initialize with auto cookies...")
            }
            client = try GrokClient.withAutoCookies(isDebug: isDebug)
            return client!
        } catch {
            if isDebug {
                print("Debug: Auto cookies failed: \(error.localizedDescription)")
                print("Debug: No usable credentials found")
            }
            throw GrokError.invalidCredentials
        }
    }

    // Send a message and get a streaming response
    func msg(message: String, enableReasoning _: Bool = true, enableDeepSearch: Bool = false, disableSearch: Bool = false, customInstructions: String = "", temporary: Bool = false, personalityType: GrokClient.PersonalityType? = nil, mode: GrokMode? = nil, fileAttachments: [String] = [], workspaceIds: [String] = [], disabledConnectorIds: [String] = [], streamOutput: Bool = true) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        let personality = personalityType ?? currentPersonality
        let selectedMode = mode ?? currentMode
        currentMode = selectedMode

        if isDebug {
            print("Debug: Sending message to Grok:")
            print("Debug: - Message: \(message)")
            print("Debug: - Reasoning: always enabled")
            print("Debug: - Deep Search requested: \(enableDeepSearch) (ignored)")
            print("Debug: - Disable Search requested: \(disableSearch) (ignored)")
            print("Debug: - Instruction override requested: \(customInstructions.isEmpty ? "none" : "provided") (ignored)")
            print("Debug: - Private Mode: \(temporary ? "ON" : "OFF")")
            print("Debug: - Personality: \(personality.displayName)")
            print("Debug: - Model: \(selectedMode.displayName) (\(selectedMode.id))")
            print("Debug: - File Attachments: \(fileAttachments.count)")
            print("Debug: - Workspaces: \(workspaceIds.count)")
            print("Debug: - Stream Output: \(streamOutput ? "YES" : "NO")")
            if let conversationId = currentConversationId {
                print("Debug: - Conversation ID: \(conversationId)")
                if let responseId = lastResponseId {
                    print("Debug: - Parent Response ID: \(responseId)")
                }
            } else {
                print("Debug: - Starting new conversation")
            }
        }

        let client = try initializeClient()

        if isDebug {
            print("Debug: Client initialized, starting stream...")
        }

        // Handle both new conversations and continuing existing ones
        return AsyncThrowingStream<ConversationResponse, Error> { continuation in
            let forwardingTask = Task {
                do {
                    let stream: AsyncThrowingStream<ConversationResponse, Error>
                    if let conversationId = currentConversationId {
                        // For existing conversations, use continueConversation with streaming API
                        stream = try await client.continueConversation(
                            conversationId: conversationId,
                            parentResponseId: lastResponseId,
                            message: message,
                            enableReasoning: true,
                            enableDeepSearch: false,
                            disableSearch: false,
                            customInstructions: "",
                            temporary: temporary,
                            personalityType: personality,
                            modeId: selectedMode.id,
                            fileAttachments: fileAttachments,
                            workspaceIds: workspaceIds,
                            disabledConnectorIds: disabledConnectorIds
                        )
                    } else {
                        // For new conversations, use streamMessage
                        stream = try await client.streamMessage(
                            message: message,
                            enableReasoning: true,
                            enableDeepSearch: false,
                            disableSearch: false,
                            customInstructions: "",
                            temporary: temporary,
                            personalityType: personality,
                            modeId: selectedMode.id,
                            fileAttachments: fileAttachments,
                            workspaceIds: workspaceIds,
                            disabledConnectorIds: disabledConnectorIds
                        )
                    }

                    // Forward all responses from the stream to our continuation
                    for try await response in stream {
                        if currentConversationId == nil {
                            currentConversationId = response.conversationId
                        }
                        lastResponseId = response.responseId
                        lastWebSearchResults = response.webSearchResults
                        lastXPosts = response.xposts

                        if isDebug {
                            print("Debug: Stream chunk received, length: \(response.message.count) characters")
                            print("Debug: Conversation ID: \(response.conversationId)")
                            print("Debug: Response ID: \(response.responseId)")
                            print("Debug: Web Search Results: \(response.webSearchResults?.count ?? 0)")
                            print("Debug: X Posts: \(response.xposts?.count ?? 0)")
                        }

                        continuation.yield(response)
                        if response.isFinal {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    if isDebug {
                        print("Debug: Error in msg: \(error.localizedDescription)")
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                forwardingTask.cancel()
            }
        }
    }

    func createSkillConversation(
        prompt: String,
        temporary: Bool = false,
        fileAttachments: [String] = [],
        workspaceIds: [String] = [],
        streamOutput: Bool = true
    ) async throws -> AsyncThrowingStream<ConversationResponse, Error> {
        resetConversation()
        let message = "skill-creator skill \(prompt)"
        // Skills/connectors are only available through the Grok 4.3 web mode.
        let skillMode = GrokMode.grok43Beta
        return try await msg(
            message: message,
            enableReasoning: true,
            enableDeepSearch: false,
            disableSearch: false,
            customInstructions: "",
            temporary: temporary,
            mode: skillMode,
            fileAttachments: fileAttachments,
            workspaceIds: workspaceIds,
            streamOutput: streamOutput
        )
    }

    /// Loads a conversation by its ID and sets up context for continuing it
    /// - Parameter conversationId: The ID of the conversation to load
    /// - Returns: An array of Response objects containing the conversation history
    /// - Throws: Network, decoding, or API errors
    func loadConversation(conversationId: String, title: String? = nil) async throws -> [Response] {
        let client = try initializeClient()
        let responses = try await client.loadResponses(conversationId: conversationId)

        // Set conversation context
        self.currentConversationId = conversationId
        self.currentConversationTitle = title
        self.lastResponseId = Self.continuationParentResponseId(in: responses)
        self.lastLoadedConversationMode = nil

        let modes = await loadModes()
        if let mode = Self.mostRecentMode(in: responses, modes: modes) {
            setCurrentMode(mode)
            lastLoadedConversationMode = mode
        }

        if isDebug {
            print("Debug: Loaded conversation \(conversationId) with \(responses.count) responses")
            if let lastId = lastResponseId {
                print("Debug: Last response ID: \(lastId)")
            } else {
                print("Debug: No responses in conversation")
            }
            if let lastLoadedConversationMode {
                print("Debug: Resumed model: \(lastLoadedConversationMode.displayName) (\(lastLoadedConversationMode.id))")
            }
        }

        return responses
    }

    private static func mostRecentMode(in responses: [Response], modes: [GrokMode]) -> GrokMode? {
        for response in responses.reversed() {
            let ids = [response.modeId, response.modelId].compactMap(cleanModeToken)
            for id in ids {
                if let exactMode = exactMode(for: id, modes: modes) {
                    return exactMode
                }
            }
            for id in ids {
                let resolved = GrokMode.resolve(id, modes: modes)
                if isKnownMode(resolved, requestedValue: id, modes: modes) {
                    return resolved
                }
            }
            if let id = ids.first {
                return GrokMode.resolve(id, modes: modes)
            }

            for name in [response.modeName, response.modelName].compactMap(cleanModeToken) {
                let resolved = GrokMode.resolve(name, modes: modes)
                if isKnownMode(resolved, requestedValue: name, modes: modes) {
                    return resolved
                }
            }
        }

        return nil
    }

    private static func continuationParentResponseId(in responses: [Response]) -> String? {
        let parentIds = Set(responses.compactMap { cleanModeToken($0.parentResponseId) })
        let indexedResponses = responses.enumerated().map { ($0.offset, $0.element) }

        let assistantLeaves = indexedResponses.filter {
            isAssistantResponse($0.1) && !parentIds.contains($0.1.responseId)
        }
        if let response = latestResponse(in: assistantLeaves) {
            return response.responseId
        }

        let leaves = indexedResponses.filter { !parentIds.contains($0.1.responseId) }
        if let response = latestResponse(in: leaves) {
            return response.responseId
        }

        let assistants = indexedResponses.filter { isAssistantResponse($0.1) }
        if let response = latestResponse(in: assistants) {
            return response.responseId
        }

        return latestResponse(in: indexedResponses)?.responseId
    }

    private static func latestResponse(in candidates: [(Int, Response)]) -> Response? {
        candidates.max { lhs, rhs in
            let lhsDate = responseDate(lhs.1)
            let rhsDate = responseDate(rhs.1)
            if lhsDate == rhsDate {
                return lhs.0 < rhs.0
            }
            return lhsDate < rhsDate
        }?.1
    }

    private static func isAssistantResponse(_ response: Response) -> Bool {
        let sender = response.sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sender == "assistant" || sender == "grok" || sender == "model"
    }

    private static func isUserResponse(_ response: Response) -> Bool {
        let sender = response.sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sender == "human" || sender == "user"
    }

    private static func responseDate(_ response: Response) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: response.createTime) {
            return date
        }

        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: response.createTime) {
            return date
        }

        return .distantPast
    }

    private static func exactMode(for value: String, modes: [GrokMode]) -> GrokMode? {
        let normalized = normalizedModeToken(value)
        return modes.first { normalizedModeToken($0.id) == normalized } ??
            GrokMode.knownModes.first { normalizedModeToken($0.id) == normalized }
    }

    private static func isKnownMode(_ mode: GrokMode, requestedValue: String, modes: [GrokMode]) -> Bool {
        if modes.contains(where: { $0.id == mode.id }) ||
            GrokMode.knownModes.contains(where: { $0.id == mode.id }) {
            return true
        }

        return normalizedModeToken(mode.id) != normalizedModeToken(requestedValue)
    }

    private static func cleanModeToken(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedModeToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    // Save credentials for future use
    func saveCredentials(from jsonPath: String) throws {
        try configManager.saveCredentialsPath(jsonPath)
        client = nil
        cachedModes = nil
        cachedSubscriptionDisplayName = nil
    }

    // Generate new credentials using cookie extractor
    func generateCredentials(args: [String] = [], suppressOutput: Bool = false) async throws -> String {
        // Return path to generated credentials
        let path = try await configManager.runCookieExtractor(extraArgs: args, suppressOutput: suppressOutput)
        client = nil
        cachedModes = nil
        cachedSubscriptionDisplayName = nil
        return path
    }
}
