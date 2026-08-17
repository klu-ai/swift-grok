import Foundation
import GrokClient

struct GrokCodeResponsesToolSchema: Codable {
    var name: String
    var description: String
    var parameters: [String: AnyCodable]
}

struct GrokCodeAgentRequest {
    var sessionID: UUID
    var model: GrokMode
    var cwd: URL
    var prompt: String
    var tools: [GrokCodeResponsesToolSchema]
    var maxTurns: Int
    var streamEvents: Bool
    var storeResponses: Bool
}

struct GrokCodeAgentResult {
    var finalAnswer: String
    var responseID: String?
    var completedTurns: Int
    var events: [GrokCodeEvent]
}

protocol GrokCodeResponsesAgent {
    func run(_ request: GrokCodeAgentRequest) async throws -> GrokCodeAgentResult
}

struct GrokCodeUnavailableResponsesAgent: GrokCodeResponsesAgent {
    func run(_ request: GrokCodeAgentRequest) async throws -> GrokCodeAgentResult {
        let message = """
        Grok Code command/session shell is active, but the Responses function-call transport and local tool executor are not wired in this lane yet.
        Model \(request.model.id) was resolved and the prompt/transcript skeleton was assembled for \(request.cwd.path).
        """
        return GrokCodeAgentResult(
            finalAnswer: message,
            responseID: nil,
            completedTurns: 0,
            events: [
                GrokCodeEvent(
                    sequence: 0,
                    kind: .warning,
                    message: "Responses function-call integration pending",
                    metadata: [
                        "model": AnyCodable(request.model.id),
                        "toolCount": AnyCodable(request.tools.count)
                    ]
                )
            ]
        )
    }
}

struct GrokCodeOAuthResponsesAgent: GrokCodeResponsesAgent {
    var credential: XAIOAuthCredential
    var client: XAIOAuthClient
    var executor: GrokCodeToolExecutor
    var context: GrokCodeToolUseContext

    func run(_ request: GrokCodeAgentRequest) async throws -> GrokCodeAgentResult {
        let tools = request.tools.map {
            XAIResponsesToolDefinition(
                name: $0.name,
                description: $0.description,
                parameters: $0.parameters
            )
        }
        var events: [GrokCodeEvent] = []
        var latestResponseID: String?
        var latestText = ""
        var completedTurns = 0

        var response = try await client.createResponseWithTools(
            using: credential,
            modelID: request.model.id,
            message: request.prompt,
            tools: tools,
            previousResponseID: nil,
            store: request.storeResponses,
            toolChoice: .auto,
            parallelToolCalls: false
        )

        while completedTurns < request.maxTurns {
            completedTurns += 1
            latestResponseID = response.id.nilIfBlank ?? latestResponseID
            if !response.finalText.isEmpty {
                latestText = response.finalText
            }

            let calls = response.functionCalls.filter { !$0.name.isEmpty }
            guard !calls.isEmpty else {
                return GrokCodeAgentResult(
                    finalAnswer: latestText,
                    responseID: latestResponseID,
                    completedTurns: completedTurns,
                    events: events
                )
            }

            let toolOutputs = await execute(calls: calls, events: &events)
            guard let responseID = latestResponseID else {
                throw GrokError.apiError("Responses API returned tool calls without a response id")
            }

            response = try await client.continueResponseWithToolOutputs(
                using: credential,
                modelID: request.model.id,
                previousResponseID: responseID,
                toolOutputs: toolOutputs,
                store: request.storeResponses,
                tools: tools,
                toolChoice: .auto,
                parallelToolCalls: false
            )
        }

        events.append(GrokCodeEvent(
            sequence: events.count + 1,
            kind: .warning,
            message: "Stopped after max turns",
            metadata: [
                "maxTurns": AnyCodable(request.maxTurns),
                "responseId": AnyCodable(latestResponseID ?? "")
            ]
        ))

        return GrokCodeAgentResult(
            finalAnswer: latestText.isEmpty ? "Stopped after \(request.maxTurns) turns before the model returned a final answer." : latestText,
            responseID: latestResponseID,
            completedTurns: completedTurns,
            events: events
        )
    }

    private func execute(
        calls: [XAIResponsesFunctionCall],
        events: inout [GrokCodeEvent]
    ) async -> [XAIResponsesFunctionCallOutput] {
        var outputs: [XAIResponsesFunctionCallOutput] = []
        outputs.reserveCapacity(calls.count)

        for call in calls {
            let requestID = call.callID.nilIfBlank ?? call.id ?? UUID().uuidString
            let parsedArguments = call.argumentsDictionary
            let arguments = (parsedArguments ?? [:]).mapValues(AnyCodable.init)
            let toolRequest = GrokCodeToolRequest(
                id: requestID,
                name: call.name,
                arguments: arguments
            )

            events.append(GrokCodeEvent(
                sequence: events.count + 1,
                kind: .toolCall,
                message: "Calling \(call.name)",
                metadata: [
                    "callId": AnyCodable(requestID),
                    "tool": AnyCodable(call.name)
                ]
            ))

            let result: GrokCodeToolResult
            if parsedArguments == nil, !call.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = .failure(
                    requestID: requestID,
                    message: "Could not parse tool arguments as a JSON object."
                )
            } else {
                result = await executor.execute(request: toolRequest, context: context)
            }

            events.append(GrokCodeEvent(
                sequence: events.count + 1,
                kind: .toolResult,
                message: "\(call.name) \(result.ok ? "completed" : "failed")",
                metadata: [
                    "callId": AnyCodable(requestID),
                    "tool": AnyCodable(call.name),
                    "ok": AnyCodable(result.ok)
                ]
            ))
            outputs.append(XAIResponsesFunctionCallOutput(
                callID: requestID,
                output: Self.outputString(for: result)
            ))
        }

        return outputs
    }

    private static func outputString(for result: GrokCodeToolResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8) else {
            return result.error ?? result.content.compactMap { block in
                if case .text(let text) = block {
                    return text
                }
                return nil
            }.joined(separator: "\n")
        }
        return string
    }
}

struct GrokCodeSession {
    var options: GrokCodeOptions
    var promptAssembler: GrokCodePromptAssembler
    var agent: any GrokCodeResponsesAgent
    var toolRegistry: GrokCodeToolRegistry

    init(
        options: GrokCodeOptions,
        promptAssembler: GrokCodePromptAssembler = GrokCodePromptAssembler(),
        agent: any GrokCodeResponsesAgent = GrokCodeUnavailableResponsesAgent(),
        toolRegistry: GrokCodeToolRegistry? = nil
    ) {
        self.options = options
        self.promptAssembler = promptAssembler
        self.agent = agent
        self.toolRegistry = toolRegistry ?? Self.makeToolRegistry(options: options)
    }

    func run(task: String?) async throws -> GrokCodeSessionState {
        guard let model = options.resolvedModel else {
            throw GrokError.apiError("Grok Code model was not resolved")
        }

        var state = GrokCodeSessionState(
            cwd: options.cwd,
            model: model,
            options: options
        )
        let transcriptURL = GrokCodeTranscriptStore.defaultURL(sessionID: state.id)
        let transcriptStore = GrokCodeTranscriptStore(url: transcriptURL)
        state.transcriptPath = transcriptURL.path
        state.appendEvent(kind: .sessionStarted, "Started Grok Code session", metadata: [
            "cwd": AnyCodable(options.cwd.path),
            "model": AnyCodable(model.id)
        ])
        state.appendEvent(kind: .modelResolved, "Resolved Grok Code model", metadata: [
            "model": AnyCodable(model.id)
        ])

        if let task {
            try state.appendEnvelope(
                role: .user,
                content: task,
                metadata: ["source": AnyCodable("task")],
                store: transcriptStore
            )
        }

        let transcript = try transcriptStore.readAll()
        let prompt = promptAssembler.assemble(task: task, state: state, transcript: transcript)
        state.promptCharacterCount = prompt.count
        try state.appendEnvelope(
            role: .system,
            kind: .prompt,
            content: prompt,
            isEphemeral: true,
            metadata: ["promptVersion": AnyCodable("grok-code-shell-v1")],
            store: transcriptStore
        )
        state.appendEvent(kind: .promptAssembled, "Assembled Grok Code prompt", metadata: [
            "characters": AnyCodable(prompt.count)
        ])

        let request = GrokCodeAgentRequest(
            sessionID: state.id,
            model: model,
            cwd: options.cwd,
            prompt: prompt,
            tools: toolSchemas(),
            maxTurns: options.maxTurns,
            streamEvents: options.outputFormat == .streamingJSON,
            storeResponses: !options.privateMode
        )

        state.appendEvent(kind: .agentStarted, "Calling Responses agent interface")
        let result = try await agent.run(request)
        state.completedTurns = result.completedTurns
        state.finalAnswer = result.finalAnswer
        state.responseID = result.responseID
        for event in result.events {
            state.appendEvent(kind: event.kind, event.message, metadata: event.metadata)
        }
        try state.appendEnvelope(
            role: .assistant,
            content: result.finalAnswer,
            metadata: ["responseId": AnyCodable(result.responseID ?? "")],
            store: transcriptStore
        )
        state.appendEvent(kind: .agentCompleted, "Responses agent interface completed")
        return state
    }

    static func makeToolRegistry(options: GrokCodeOptions) -> GrokCodeToolRegistry {
        GrokCodeToolRegistry.builtin().filtered(
            allowedTools: Set(options.activeToolNames),
            disallowedTools: Set(options.disallowedTools),
            permissionMode: nil
        )
    }

    private func toolSchemas() -> [GrokCodeResponsesToolSchema] {
        toolRegistry.schemas.map { schema in
            GrokCodeResponsesToolSchema(
                name: schema.name,
                description: schema.description,
                parameters: schema.parameters
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension XAIResponsesFunctionCall {
    var argumentsDictionary: [String: Any]? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}
