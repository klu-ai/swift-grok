# Grok Code Harness Architecture Plan

## Objective

Create a `grok code` mode for the Swift Grok CLI that replaces the current conversational turn loop with a local coding harness: typed tool use, event-sourced transcript state, permissioned tool execution, and four Grok coding agents running through the user-settings agent customization feature.

The mode should use Grok expert or beta models for thinking-heavy coding work, install four temporary coding personas while the mode is active, move the user's current active agents into the agent library during the session, and restore the original user settings on exit.

## Success Criteria

- [ ] `grok code [options] [task...]` launches a code-mode session without changing the existing `grok chat` and `grok message` behavior.
- [ ] Code mode uses a local harness with explicit turn state, tool requests, tool results, permissions, transcript persistence, and interrupt handling instead of continuing one plain multi-turn Grok conversation.
- [ ] Code mode can run four coding personas: agent 0 strategy/coordinator, agent 1 architecture, agent 2 engineering, and agent 3 security.
- [ ] On code-mode entry, the CLI backs up the raw user settings, appends the current active agents to `agentLibrary.agents`, swaps the four active agent customizations to coding agents, and records a local recovery backup.
- [ ] On normal exit, EOF, thrown error, or supported interrupt, the CLI restores the original active agents and original agent library from the exact backup snapshot.
- [ ] If restore fails, the CLI prints the backup path and a deterministic recovery command without logging credentials or cookies.
- [ ] Code mode defaults to the expert Grok mode and supports a beta alias for `grok-4.3-beta` or the currently resolved beta mode ID.
- [ ] Tool execution is permissioned, produces a result for every tool request, and serializes unsafe tools by default.
- [ ] Tests cover settings backup/restore shape, command parsing, transcript state, tool-result pairing, permission decisions, and code-mode output boundaries.
- [ ] After implementation, run `swift build` and `Scripts/install_cli.sh --user` so the user can test `grok` from PATH.

## Discovery Completed

- [x] Used six focused sub-agents against `/Users/stephenwalker/Code/ecosystem/claude-code/src`.
- [x] Inspected the Swift Grok CLI command flow, interactive session, output formatting, Grok client request layer, user-settings client methods, and existing agent commands.
- [x] Kept the supplied browser headers and cookies out of prompts, files, and command output.
- [x] Confirmed the current worktree is dirty before planning; this plan adds only a new Markdown file.

Useful discovery commands:

```sh
rg --files Sources/GrokCLI Sources/GrokClient Tests plans
rg -n "getUserSettingsResponse|updateAgentCustomizations|agentCustomizations|agentLibrary|preparePayload|modeId|ConversationResponse" Sources/GrokClient Sources/GrokCLI
rg -n "handleChatCommand|handleMessageCommand|InteractiveSession|OutputFormatter|InputReader|ChatSessionState|recognizedTopLevelCommands" Sources/GrokCLI Tests
find /Users/stephenwalker/Code/ecosystem/claude-code/src -maxdepth 2 -type f
```

## Current-State Findings

### Swift Grok CLI Shape

- [x] `Sources/GrokCLI/main.swift` is already a tiny async entrypoint that calls `GrokCLI.main()`.
- [x] `Sources/GrokCLI/Core/TopLevelRouter.swift` owns top-level routing through `recognizedTopLevelCommands`, argument normalization, and command dispatch.
- [x] `Sources/GrokCLI/Interactive/InteractiveSession.swift` owns the current interactive chat loop, slash command switch, auth recovery, rate-limit status, model changes, file attachment commands, and calls into `GrokCLIApp.msg(...)`.
- [x] `Sources/GrokCLI/Commands/MessageCommand.swift` owns one-shot message mode, stdin/prompt-file/audio input, JSON stream events, quiet raw output, and conversation reset before a single message.
- [x] `Sources/GrokCLI/Runtime/GrokCLIApp.swift` keeps mutable app state: `currentConversationId`, `lastResponseId`, web results, personality, mode, workspace, attached files, and a cached `GrokClient`.
- [x] `Sources/GrokCLI/Runtime/GrokCLIApp.swift` sends both new and continuing messages through `msg(...)`, which chooses `client.streamMessage(...)` or `client.continueConversation(...)`. This is the seam where code mode must stop being "one chat thread" and become a harness runner.
- [x] `Sources/GrokCLI/Runtime/ChatSessionState.swift` is small and chat-specific. Code mode needs a separate session state type rather than inflating this one.
- [x] `Sources/GrokCLI/Presentation/OutputFormatter.swift` already renders streamed thinking/activity traces and final answer text; code mode can reuse parts of this output style after it has its own event stream.
- [x] `Sources/GrokCLI/Commands/AgentCommands.swift` already lists, shows, edits, clears, and sets `agentCustomizations.values`, but the logic is command-shaped and does not model a scoped enter/exit lifecycle.
- [x] `Sources/GrokClient/GrokClient.swift` currently models `GrokAgentCustomization` and `GrokAgentCustomizationsResponse` only. It does not preserve full `agentLibrary.agents` or unknown user-settings keys as a first-class snapshot.
- [x] `Sources/GrokClient/GrokClient.swift` has `getUserSettingsResponse()` and `updateAgentCustomizations(_:)` against `/rest/user-settings`. This transport should be reused; credentials and headers should not be duplicated.
- [x] `Sources/GrokClient/GrokClient.swift` builds chat payloads in `preparePayload(...)`; there is no current `agentId` parameter in Swift, so agent-selection payload discovery must be part of implementation before relying on remote agent IDs.
- [x] `Scripts/install_cli.sh` already builds and installs the release `grok` binary and should be the post-implementation install gate.

### Claude Code Lessons To Port

- [x] Lifecycle: `/Users/stephenwalker/Code/ecosystem/claude-code/src/entrypoints/cli.tsx` and `main.tsx` keep bootstrap/classification separate from heavy session launch. Swift should add a typed invocation path for code mode rather than pushing more conditionals into the chat loop.
- [x] Command harness: `commands.ts`, `types/command.ts`, and `utils/processUserInput/processSlashCommand.tsx` model commands as typed behaviors: prompt expansion, local action, and UI flow. Swift code mode should return structured command results rather than mutate the loop from every command.
- [x] Turn guard and queue: `utils/QueryGuard.ts`, `utils/messageQueueManager.ts`, and `utils/queueProcessor.ts` prevent concurrent turns and normalize user, scheduled, task, and remote inputs into a priority queue.
- [x] Messages and context: `types/message.ts`, `query.ts`, and `utils/sessionStorage.ts` use stable message IDs, parent links, append-only transcript entries, and a projected API view. Swift code mode should not use the Grok web conversation ID as the only source of truth.
- [x] Tool contract: `Tool.ts`, `services/tools/toolExecution.ts`, `services/tools/StreamingToolExecutor.ts`, and `services/tools/toolOrchestration.ts` define schema validation, permission checks, execution, progress, result mapping, and conservative concurrency.
- [x] Permissions: `types/permissions.ts`, `utils/permissions/permissions.ts`, and `hooks/toolPermission/PermissionContext.ts` keep global policy separate from tool execution and resolve permission decisions through one owner.
- [x] Bridge/task orchestration: `bridge/remoteBridgeCore.ts`, `bridge/replBridgeTransport.ts`, `bridge/bridgeMessaging.ts`, `tasks/LocalAgentTask/LocalAgentTask.tsx`, and `tasks/LocalMainSessionTask.ts` treat background agents as durable tasks with abort, progress, output, queued follow-ups, and structured notifications.
- [x] Terminal UI: `ink/parse-keypress.ts`, `keybindings/defaultBindings.ts`, `utils/Cursor.ts`, `components/PromptInput/PromptInput.tsx`, `context/overlayContext.tsx`, and `components/StatusLine.tsx` show that prompt editing, keybindings, overlays, notifications, and status output should be layered and data-driven.

## Target User Experience

### Code Mode Entry

```text
$ grok code --model expert "add retries to the proxy streaming path"

Grok Code
model expert | tools default | agents strategy architecture engineering security

> 
```

### Active Harness Output

```text
[strategy] planning tool path
[architecture] identified Sources/GrokProxy/Controllers/ChatCompletionsController.swift
[security] checking credential and logging boundaries
[tool] rg retry Sources/GrokProxy Sources/GrokClient
[tool] read Sources/GrokProxy/Controllers/ChatCompletionsController.swift

Grok Code
The implementation should add retry policy at the client boundary, not inside stream rendering...
```

### Restore Failure Output

```text
Grok Code settings restore failed.
Backup: ~/.grok/code-mode/settings-backups/2026-05-14T04-20-00Z.json
Run: grok code restore --backup ~/.grok/code-mode/settings-backups/2026-05-14T04-20-00Z.json
```

## Target Architecture

### New Command Boundary

Add a new top-level `code` command, with `grok code` separate from `grok chat`.

New files:

- `Sources/GrokCLI/Commands/CodeCommand.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeSession.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeSessionState.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeEvents.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeCommandQueue.swift`

Modified files:

- `Sources/GrokCLI/Core/TopLevelRouter.swift`
- `Sources/GrokCLI/Presentation/HelpText.swift`
- `Sources/GrokCLI/Presentation/JSONOutput.swift`
- `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`

Implementation shape:

```swift
enum GrokCodeInvocation {
    case interactive(GrokCodeOptions)
    case print(GrokCodeOptions, task: String)
    case restoreBackup(path: String)
}

struct GrokCodeOptions {
    var mode: GrokMode
    var permissionMode: GrokCodePermissionMode
    var outputFormat: OutputFormat
    var privateMode: Bool
    var dryRunSettings: Bool
}
```

### Settings Scope

Add a scoped settings owner that is created before the code-mode session starts and torn down when the session exits.

New files:

- `Sources/GrokClient/GrokUserSettings.swift`
- `Sources/GrokClient/GrokSettingsClient.swift`
- `Sources/GrokCLI/Runtime/GrokAgentSettingsScope.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeAgentPrompts.swift`

Modified files:

- `Sources/GrokClient/GrokClient.swift`
- `Sources/GrokCLI/Runtime/ConfigManager.swift`
- `Sources/GrokCLI/Runtime/GrokCLIApp.swift`
- `Sources/GrokCLI/Commands/AgentCommands.swift`

Core requirements:

- [ ] Fetch and preserve a raw user-settings snapshot before any mutation.
- [ ] Parse typed projections from the snapshot for `agentCustomizations.values` and `agentLibrary.agents`.
- [ ] Build a settings patch that appends the current four active agents to `agentLibrary.agents`.
- [ ] Swap `agentCustomizations.values` to the four Grok Code personas.
- [ ] Persist the original raw snapshot locally under `~/.grok/code-mode/settings-backups/`.
- [ ] Add a lock file under `~/.grok/code-mode/active-settings-scope.json` with PID, start time, backup path, and settings hash to prevent concurrent code sessions from trampling each other.
- [ ] Restore the original snapshot on exit.
- [ ] If only partial restore is accepted by `/user-settings`, restore both `agentCustomizations` and `agentLibrary` from the snapshot rather than attempting to replace every unknown setting.

Implementation shape:

```swift
public struct GrokUserSettingsSnapshot: Codable {
    public let rawJSON: AnyCodable
    public let fetchedAt: Date
}

public struct GrokAgentLibraryAgent: Codable, Equatable {
    public var name: String
    public var instructions: String
}

public struct GrokAgentSettingsProjection: Codable, Equatable {
    public var activeAgents: [GrokAgentCustomization]
    public var libraryAgents: [GrokAgentLibraryAgent]
}

struct GrokAgentSettingsScope {
    let backupPath: String

    static func enter(client: GrokClient, config: ConfigManager, profile: GrokCodeAgentProfile) async throws -> GrokAgentSettingsScope
    func restore(client: GrokClient) async throws
}
```

### Agent Invocation

Code mode needs two layers:

- Local role orchestration in Swift.
- Remote Grok messages sent through expert or beta mode, with the active coding personas installed in user settings.

New files:

- `Sources/GrokCLI/CodeMode/GrokCodeAgentRole.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeAgentOrchestrator.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeAgentClient.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeModelProfile.swift`

Open implementation question:

- [ ] Confirm how the Grok web API selects one of the four active custom agents for a conversation request. Search or capture the request payload for an agent selection field before adding a stable `agentId` field to `GrokClient.preparePayload(...)`.

Fallback if the API does not expose stable agent selection:

- [ ] Keep the settings swap for the UI-backed agent customizations.
- [ ] Invoke each role through an isolated temporary conversation that prepends the role prompt as explicit session context.
- [ ] Keep the local transcript as the source of truth, so this fallback does not leak a multi-turn chat design into code mode.

Implementation shape:

```swift
enum GrokCodeAgentRole: Int, CaseIterable {
    case strategy = 0
    case architecture = 1
    case engineering = 2
    case security = 3
}

struct GrokCodeAgentInvocation {
    var role: GrokCodeAgentRole
    var prompt: String
    var mode: GrokMode
    var inputEnvelopeIDs: [UUID]
}

protocol GrokCodeAgentClient {
    func run(_ invocation: GrokCodeAgentInvocation) async throws -> AsyncThrowingStream<GrokCodeAgentEvent, Error>
}
```

### Tool Harness

Add a native Swift tool protocol and executor for code mode. Do not treat tool calls as chat text once parsed.

New files:

- `Sources/GrokCLI/CodeMode/Tools/GrokCodeTool.swift`
- `Sources/GrokCLI/CodeMode/Tools/GrokCodeToolRegistry.swift`
- `Sources/GrokCLI/CodeMode/Tools/GrokCodeToolExecutor.swift`
- `Sources/GrokCLI/CodeMode/Tools/GrokCodeToolParser.swift`
- `Sources/GrokCLI/CodeMode/Tools/GrokCodePermissionController.swift`
- `Sources/GrokCLI/CodeMode/Tools/BuiltinTools.swift`

Initial built-in tools:

- [ ] `read_file`
- [ ] `list_files`
- [ ] `search`
- [ ] `shell`
- [ ] `git_diff`
- [ ] `apply_patch`
- [ ] `write_plan`

Implementation shape:

```swift
protocol GrokCodeTool {
    associatedtype Input: Decodable
    var name: String { get }
    var description: String { get }
    var isConcurrencySafeByDefault: Bool { get }

    func validate(_ input: Input, context: GrokCodeToolUseContext) throws
    func checkPermission(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodePermissionDecision
    func run(_ input: Input, context: GrokCodeToolUseContext) async throws -> GrokCodeToolResult
}

struct GrokCodeToolRequest: Codable, Equatable {
    var id: String
    var name: String
    var arguments: [String: AnyCodable]
}

struct GrokCodeToolResult: Codable, Equatable {
    var requestID: String
    var ok: Bool
    var content: [GrokCodeContentBlock]
    var error: String?
}
```

Tool protocol over model text for MVP:

```json
{"tool_call":{"id":"toolu_1","name":"search","arguments":{"query":"preparePayload","paths":["Sources/GrokClient"]}}}
```

Rules:

- [ ] Accept only fenced JSON or one-line JSON objects with a top-level `tool_call` object.
- [ ] Reject malformed calls with a synthetic `tool_result`.
- [ ] Every accepted or rejected tool request must produce exactly one `tool_result`.
- [ ] Only tools marked safe for the parsed input may run concurrently.
- [ ] `shell`, `apply_patch`, and write-capable tools require an explicit permission decision unless the session permission mode allows them.
- [ ] Tool output must be capped and summarized before returning to the agent loop.

### Transcript And Turn Runner

New files:

- `Sources/GrokCLI/CodeMode/Transcript/GrokCodeMessageEnvelope.swift`
- `Sources/GrokCLI/CodeMode/Transcript/GrokCodeTranscriptStore.swift`
- `Sources/GrokCLI/CodeMode/Transcript/GrokCodeContextProjector.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeTurnRunner.swift`
- `Sources/GrokCLI/CodeMode/GrokCodeTurnGuard.swift`

Implementation shape:

```swift
enum GrokCodeMessageKind: String, Codable {
    case user
    case agent
    case toolRequest
    case toolResult
    case system
    case progress
    case summary
}

struct GrokCodeMessageEnvelope: Codable, Identifiable, Equatable {
    var id: UUID
    var sessionID: UUID
    var parentID: UUID?
    var role: GrokCodeAgentRole?
    var kind: GrokCodeMessageKind
    var createdAt: Date
    var content: [GrokCodeContentBlock]
    var isEphemeral: Bool
}

enum GrokCodeTurnEvent {
    case progress(String)
    case agentDelta(role: GrokCodeAgentRole, text: String)
    case toolStarted(GrokCodeToolRequest)
    case toolFinished(GrokCodeToolResult)
    case completed(GrokCodeMessageEnvelope)
}
```

Rules:

- [ ] Persist user prompts before model calls begin.
- [ ] Keep progress events ephemeral by default.
- [ ] Store agent responses, tool requests, and tool results as append-only JSONL records.
- [ ] Build the API view from `GrokCodeContextProjector`, not from raw UI history.
- [ ] Add parent IDs from day one so future resume, rewind, compaction, and parallel tool calls do not require a storage rewrite.

## Grok Code Agent Personas

Store these in `Sources/GrokCLI/CodeMode/GrokCodeAgentPrompts.swift`. They are prompt assets, not final user-facing CLI copy.

### Agent 0 Strategy

```text
You are Grok Code Strategy, the lead coding coordinator for a local CLI programming harness. Your role is to:

0. Describe the overall strategy and why it is the right execution path in 1-2 concise, specific sentences.
1. Read the user instructions and define the target outcome, constraints, and completion evidence.
2. Request focused feedback from the architecture, engineering, and security agents.
3. Compare their feedback, decide the execution order, and identify the smallest safe implementation path.
4. Choose which local tools should be used next and explain why each tool call is needed.
5. Track the current task state, including completed work, remaining work, blockers, and rollback notes.
6. Produce the final user response only after implementation and verification evidence exists.

For each decision:

* State the exact file or subsystem affected.
* Identify which agent feedback informed the decision.
* Note the expected side effect on the codebase or user workflow.
* Avoid speculative work that does not move the current task forward.

You may include short code snippets to specify signatures or patch shapes, but rely on tools for reading and editing files.

Focus on orchestration, sequencing, risk control, and final completion. Do not perform architecture, implementation, or security analysis yourself when those agents have current feedback available.

Include concrete todos as Markdown for every remaining task.

Please proceed based on the following <user instructions>
```

### Agent 1 Architecture

```text
You are a senior software architect specializing in code design and implementation planning. Your role is to:

0. Describe to the engineer what we are going to be doing and why in 1-2 sentences that are concise yet specific
1. Analyze the requested changes and break them down into clear, actionable steps
2. Create a detailed implementation plan that includes:

   * Files that need to be modified
   * Specific code sections requiring changes
   * New functions, methods, or classes to be added
   * Dependencies or imports to be updated
   * Data structure modifications
   * Interface changes
   * Configuration updates

For each change:

* Describe the exact location in the code where changes are needed
* Explain the logic and reasoning behind each modification
* Provide example signatures, parameters, and return types
* Note any potential side effects or impacts on other parts of the codebase
* Highlight critical architectural decisions that need to be made

You may include short code snippets to illustrate specific patterns, signatures, or structures, but do not implement the full solution.

Focus solely on the technical implementation plan - exclude testing, validation, and deployment considerations unless they directly impact the architecture.

Include concrete todos as MD for everything that needs to be done.

Please proceed with your analysis based on the following <user instructions>
```

### Agent 2 Engineering

```text
You are a senior implementation engineer specializing in precise code changes inside an existing repository. Your role is to:

0. Tell the strategy agent what you will implement and why in 1-2 concise, specific sentences.
1. Inspect the relevant code before proposing edits.
2. Convert the architecture plan into a narrow implementation sequence.
3. Identify exact files, functions, types, imports, and tests affected by the change.
4. Produce patch-ready instructions or tool calls that preserve existing style and avoid unrelated refactors.
5. Call out build errors, API mismatches, missing types, and local behavior that could break the patch.

For each implementation step:

* Name the exact file path and local symbol.
* State whether the change is additive, replacing existing behavior, or moving logic.
* Provide example signatures, enum cases, structs, or call sites where useful.
* Identify data flow from input to output.
* Note any dependency on architecture or security feedback.

When code must be edited, prefer the smallest readable patch that satisfies the requested behavior. Do not rewrite broad areas for style alone.

Include concrete todos as MD for everything that needs to be done.

Please proceed with your implementation analysis based on the following <user instructions>
```

### Agent 3 Security

```text
You are a senior application security engineer reviewing local coding-agent behavior, credentials, file access, shell execution, and remote API mutations. Your role is to:

0. Tell the strategy agent the highest-risk part of the requested change and the required guardrail in 1-2 concise, specific sentences.
1. Identify secrets, credentials, cookies, tokens, and account settings touched by the flow.
2. Identify filesystem, shell, network, and settings-mutation risks.
3. Define permission boundaries for read-only tools, write tools, shell tools, and remote user-settings changes.
4. Specify audit logs, backup files, redaction rules, and recovery behavior.
5. Review rollback paths for settings restore failures and interrupted sessions.

For each risk:

* Name the exact file, component, command, or API boundary.
* State the impact if the risk fails open.
* Provide a concrete mitigation that an engineer can implement.
* Identify whether the mitigation belongs in client transport, CLI runtime, tool executor, transcript storage, or tests.

Focus on practical controls that preserve coding velocity while preventing credential leakage, destructive filesystem behavior, and unrecoverable remote settings drift.

Include concrete todos as MD for every guardrail that needs to be implemented.

Please proceed with your security analysis based on the following <user instructions>
```

## Workstreams

### Workstream 1 Settings Snapshot And Restore

Ownership:

- Own `Sources/GrokClient/GrokUserSettings.swift`.
- Own `Sources/GrokClient/GrokSettingsClient.swift`.
- Own `Sources/GrokCLI/Runtime/GrokAgentSettingsScope.swift`.
- Modify `Sources/GrokClient/GrokClient.swift` only for settings transport and typed projections.
- Do not touch code-mode tool execution.

Todos:

- [ ] Add `GrokUserSettingsSnapshot`, `GrokAgentSettingsProjection`, and `GrokAgentLibraryAgent`.
- [ ] Add raw snapshot GET support that returns full `AnyCodable` JSON from `/rest/user-settings`.
- [ ] Add a narrow user-settings patch method that can send both `agentCustomizations` and `agentLibrary`.
- [ ] Preserve existing `updateAgentCustomizations(_:)` behavior for `grok agents set`.
- [ ] Add projection extraction for `agentCustomizations.values`, nested `agentCustomizations`, and `agentLibrary.agents`.
- [ ] Add code-mode profile generation for four active agents.
- [ ] Append pre-code-mode active agents into the library patch with clear names and no duplicate empty entries.
- [ ] Persist backup snapshots under `ConfigManager` controlled storage.
- [ ] Add active settings lock file creation and stale-lock detection.
- [ ] Implement `restore(client:)` with best-effort exact restoration of `agentCustomizations` and `agentLibrary`.
- [ ] Add unit tests using injected `URLSession` to assert request payloads and no credential logging.

Dependencies:

- This workstream blocks Workstream 2 session entry and Workstream 4 real agent profile usage.

### Workstream 2 Code Command And Session State

Ownership:

- Own `Sources/GrokCLI/Commands/CodeCommand.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeSession.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeSessionState.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeCommandQueue.swift`.
- Modify `Sources/GrokCLI/Core/TopLevelRouter.swift` and help text.

Todos:

- [ ] Register top-level `code` in `recognizedTopLevelCommands`.
- [ ] Add `grok code --help` with expert/beta model options, permission modes, JSON mode, dry-run settings, and restore backup commands.
- [ ] Parse `grok code [options] [task...]` into `GrokCodeInvocation`.
- [ ] Initialize auth through `GrokCLIApp.initializeClient()` before settings mutation.
- [ ] Enter `GrokAgentSettingsScope` unless `--dry-run-settings` is set.
- [ ] Wrap session execution in `defer`-style restore behavior.
- [ ] Add signal-aware cleanup for SIGINT and SIGTERM where Swift async cleanup can run safely.
- [ ] Add `GrokCodeSessionState` with session ID, cwd, git branch, selected model, permission mode, active task, and active settings scope.
- [ ] Add a turn guard to prevent overlapping code turns.
- [ ] Add a priority queue for user prompts, interrupts, agent notifications, and permission replies.
- [ ] Keep `grok chat` and `grok message` routing unchanged.

Dependencies:

- Needs Workstream 1 for real settings scope.
- Can scaffold with a no-op settings scope while Workstream 1 is in progress.

### Workstream 3 Tool Protocol And Permissions

Ownership:

- Own `Sources/GrokCLI/CodeMode/Tools/*`.
- Modify presentation only for tool events, not chat rendering.
- Do not mutate user settings.

Todos:

- [ ] Add `GrokCodeToolRequest`, `GrokCodeToolResult`, `GrokCodeContentBlock`, and decoding helpers.
- [ ] Add `GrokCodeTool` protocol and erased wrapper for heterogeneous tools.
- [ ] Add `GrokCodeToolRegistry` with aliases and capability filtering.
- [ ] Add `GrokCodeToolParser` for fenced JSON and one-line JSON tool calls.
- [ ] Add synthetic error results for unknown tools, bad JSON, validation failures, denied permissions, thrown errors, and aborted tools.
- [ ] Add `GrokCodePermissionMode` values: `default`, `readOnly`, `acceptEdits`, `bypass`, and `plan`.
- [ ] Add `GrokCodePermissionController` with global deny/ask/allow rules before tool-specific checks.
- [ ] Add read-only tools: `read_file`, `list_files`, `search`, and `git_diff`.
- [ ] Add write-capable tools: `apply_patch` and `write_plan`.
- [ ] Add `shell` with command preview, cwd, timeout, output cap, and explicit approval unless bypassed.
- [ ] Ensure unsafe tools serialize and safe tools may run concurrently only after input-specific safety checks.
- [ ] Add tests for exact one-result-per-tool-request behavior.

Dependencies:

- Needs Workstream 2 state types for context.
- Feeds Workstream 4 turn runner.

### Workstream 4 Agent Orchestration

Ownership:

- Own `Sources/GrokCLI/CodeMode/GrokCodeAgentPrompts.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeAgentRole.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeAgentOrchestrator.swift`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeAgentClient.swift`.
- Modify `Sources/GrokClient/GrokClient.swift` only if agent selection payload support is confirmed.

Todos:

- [ ] Add four code agent prompts exactly as prompt assets.
- [ ] Add `GrokCodeAgentRole` with IDs 0 through 3.
- [ ] Add `GrokCodeAgentProfile` that maps active agent customizations to role names and instructions.
- [ ] Add expert and beta model profile resolution.
- [ ] Run an API discovery spike to confirm stable agent selection in `/conversations/new` and continuation payloads.
- [ ] If confirmed, add optional `agentId` to `preparePayload(...)`, `streamMessage(...)`, `continueConversation(...)`, and call sites used by code mode.
- [ ] If not confirmed, run each role through a temporary isolated conversation with explicit role prompt context.
- [ ] Add `GrokCodeAgentOrchestrator` that asks architecture, engineering, and security for feedback, then has strategy choose execution.
- [ ] Stream role progress into `GrokCodeTurnEvent`.
- [ ] Feed parsed tool requests into Workstream 3 executor and return tool results to the correct agent turn.
- [ ] Prevent raw sub-agent feedback from being pasted directly to the user; strategy must summarize and decide.
- [ ] Add tests with mocked agent streams for agent ordering, failed agent recovery, and tool-result feedback.

Dependencies:

- Uses Workstream 1 profile.
- Uses Workstream 3 tool executor.
- Feeds Workstream 5 output.

### Workstream 5 Transcript, Context, And Output

Ownership:

- Own `Sources/GrokCLI/CodeMode/Transcript/*`.
- Own `Sources/GrokCLI/CodeMode/GrokCodeRenderer.swift`.
- Modify `Sources/GrokCLI/Presentation/OutputFormatter.swift` only for reusable formatting helpers.

Todos:

- [ ] Add `GrokCodeMessageEnvelope` with UUID, parent ID, session ID, role, kind, created date, content blocks, and ephemeral flag.
- [ ] Add JSONL transcript storage under `~/.grok/code-mode/sessions/`.
- [ ] Persist user messages before agent calls.
- [ ] Persist agent messages, tool requests, and tool results.
- [ ] Exclude transient progress from parent-chain transcript unless explicitly configured.
- [ ] Add `GrokCodeContextProjector` to build bounded agent inputs from transcript plus summaries.
- [ ] Add output renderer for role progress, tool start/finish, permission prompts, final answer, and JSON mode.
- [ ] Add output caps for tool results and transcript replay.
- [ ] Add resume metadata shape, even if full resume is deferred.
- [ ] Add tests for transcript append, projection, parent links, and output redaction.

Dependencies:

- Needs Workstream 2 session state.
- Needs Workstream 4 events.

### Workstream 6 Verification, Docs, And Install

Ownership:

- Own README and test updates.
- Own final build/install gate.
- Do not broaden implementation scope.

Todos:

- [ ] Add README section for `grok code`, settings backup behavior, restore command, and permission modes.
- [ ] Add `grok code --help` assertions to E2E tests.
- [ ] Add mocked user-settings tests to `Tests/GrokClientTests/GrokClientTests.swift`.
- [ ] Add code-mode parser/permission/transcript tests to `Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift` or a new code-mode test target if needed.
- [ ] Add manual verification notes for before/after `grok agents list --include-instructions`.
- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `Scripts/install_cli.sh --user`.
- [ ] Record any skipped verification with exact reason and command.

Dependencies:

- Runs after Workstreams 1 through 5 land.

## Implementation Sequence

### Phase 0 API Confirmation

- [ ] Confirm whether Grok conversation payloads can select `agentId`.
- [ ] Confirm whether `/rest/user-settings` accepts partial patches containing both `agentCustomizations` and `agentLibrary`.
- [ ] Add failing tests or fixtures for both shapes before implementation.

### Phase 1 Add Non-Invasive Scaffolding

- [ ] Add code-mode command registration and help text.
- [ ] Add code-mode session/state/event types.
- [ ] Add prompt assets and profile types.
- [ ] Add transcript envelope and JSONL storage types.
- [ ] Keep runtime behavior behind `grok code` only.

### Phase 2 Implement Settings Scope

- [ ] Add raw settings snapshot fetch.
- [ ] Add local backup persistence.
- [ ] Add active session lock.
- [ ] Add settings patch for moving current agents into library and installing coding agents.
- [ ] Add restore command and automatic scope restore.

### Phase 3 Implement Tools And Permissions

- [ ] Add tool request parser.
- [ ] Add registry and built-in read-only tools.
- [ ] Add write and shell tools behind permission checks.
- [ ] Add one-result-per-request guarantee.
- [ ] Add output caps and redaction.

### Phase 4 Implement Agent Loop

- [ ] Add isolated agent invocation client.
- [ ] Add role feedback cycle.
- [ ] Add strategy synthesis cycle.
- [ ] Feed tool calls back into the loop until completion or max turns.
- [ ] Add interrupt and abort handling.

### Phase 5 Render, Test, Install

- [ ] Render code-mode events in human output.
- [ ] Render code-mode events in JSON output.
- [ ] Update docs.
- [ ] Run tests, build, and install.

## Test And Verification Gates

Automated gates:

```sh
swift test --filter GrokClientTests
swift test --filter GrokCLIE2ETests
swift test
swift build
Scripts/install_cli.sh --user
```

Focused test cases:

- [ ] `grok code --help` prints code-mode usage and does not enter settings scope.
- [ ] `grok code restore --backup <path>` sends restore patch without requiring a live code session.
- [ ] Settings backup JSON omits cookies and request headers.
- [ ] Settings swap appends previous active agents to library and installs four coding personas.
- [ ] Restore returns active agents and library to the original snapshot.
- [ ] Concurrent code session detects lock and refuses to start unless the lock is stale.
- [ ] Tool parser accepts valid tool JSON and rejects malformed JSON with a synthetic result.
- [ ] Permission controller denies unsafe shell commands in read-only mode.
- [ ] Tool executor emits exactly one result for every request.
- [ ] Agent orchestrator runs architecture, engineering, security feedback before strategy finalization.
- [ ] Transcript store persists user prompt before first agent response.
- [ ] Human output does not print raw settings JSON.
- [ ] JSON output is machine-readable and does not include human HUD lines.

Manual gates:

```sh
grok agents list --include-instructions
grok code --dry-run-settings "inspect the repo and propose next steps"
grok code --model expert "make a harmless README wording change"
grok agents list --include-instructions
```

## Risks And Mitigations

### Remote Settings Drift

Risk:

- `/rest/user-settings` is a global account mutation. A crash or rejected restore could leave coding personas active.

Mitigations:

- [ ] Persist a raw backup before mutation.
- [ ] Add a lock file with backup path and PID.
- [ ] Restore in `defer` and from explicit `grok code restore`.
- [ ] Print backup path loudly on failure.
- [ ] Never log cookies, request headers, or full user-settings JSON in normal output.

### Agent Selection Ambiguity

Risk:

- Swift currently has no verified `agentId` field for chat payloads.

Mitigations:

- [ ] Make agent payload discovery a Phase 0 task.
- [ ] Keep a prompt-context fallback for role isolation.
- [ ] Keep local transcript and role IDs independent from Grok conversation IDs.

### Destructive Tool Use

Risk:

- Shell, patch, and write tools can destroy local work or leak secrets.

Mitigations:

- [ ] Default permission mode asks before write/shell.
- [ ] Read-only mode blocks write/shell.
- [ ] Require command preview and cwd display for shell.
- [ ] Cap output and redact credential-looking values.
- [ ] Never run destructive git commands unless the user explicitly requested them.

### Dirty Worktree Conflicts

Risk:

- The repo often has active user changes.

Mitigations:

- [ ] Add tool context that checks `git status --short` before write-capable tools.
- [ ] Do not revert unrelated files.
- [ ] Require patches to apply cleanly to the current worktree.

### Transcript Growth

Risk:

- Tool outputs and agent feedback can grow quickly.

Mitigations:

- [ ] Cap tool output before returning to agents.
- [ ] Store full local output only when useful and refer to file paths.
- [ ] Add context projection from transcript rather than sending full history.

## Rollback Notes

- [ ] Remove top-level `code` from `recognizedTopLevelCommands` to disable the feature quickly.
- [ ] Leave `grok code restore --backup` available even if normal code mode is disabled.
- [ ] Restore user settings from `~/.grok/code-mode/settings-backups/<timestamp>.json`.
- [ ] Delete only code-mode files and tests if reverting the harness; do not touch existing chat/message commands.
- [ ] If install published a bad binary, rerun `Scripts/install_cli.sh --user` after reverting or rebuilding the prior commit.

## Final Completion Checklist

- [ ] Requirement: use six sub-agents for Claude Code analysis. Evidence: six read-only analysis lanes completed and were synthesized into this plan.
- [ ] Requirement: analyze `/Users/stephenwalker/Code/ecosystem/claude-code/src`. Evidence: findings cite lifecycle, tools, session, bridge, terminal UI, and settings lessons from that tree.
- [ ] Requirement: create a Grok harness architecture. Evidence: Target Architecture, workstreams, types, and implementation sequence define the harness.
- [ ] Requirement: enable as `grok code`. Evidence: Workstream 2 adds `CodeCommand.swift` and top-level routing.
- [ ] Requirement: replace current multi-turn chat in code mode. Evidence: transcript, turn runner, tool protocol, and agent orchestration replace direct `GrokCLIApp.msg(...)` loop for `grok code`.
- [ ] Requirement: use thinking agents with expert or beta. Evidence: model profile work supports expert default and beta alias.
- [ ] Requirement: customize four coding agents. Evidence: persona prompts for strategy, architecture, engineering, and security are included.
- [ ] Requirement: agent 0 owns overall strategy based on other feedback. Evidence: Agent 0 Strategy prompt and Workstream 4 ordering require it.
- [ ] Requirement: move existing agents to library and swap dev agents in. Evidence: Workstream 1 settings patch appends active agents to `agentLibrary.agents` and installs active coding personas.
- [ ] Requirement: swap coding agents out on exit. Evidence: Settings Scope restore and rollback sections require exact backup restoration.
- [ ] Requirement: avoid credential leakage. Evidence: settings scope, tests, and risks require raw backup redaction and no cookie logging.
- [ ] Requirement: plan only, no implementation. Evidence: this file is the only planned artifact for this request.
