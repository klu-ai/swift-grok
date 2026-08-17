# GrokClient Six-Agent Modular Refactor Plan

Date: 2026-05-14

Execution status: plan only. No implementation, build, test, or install commands were run for this request.

## Objective

Execute the `GrokClient` modularization/refactor as a queue of MECE workstreams processed by up to 6 active implementation agents at a time.

The plan is not "six agents investigate the plan." The plan is an executable production-work queue:

- Many small, mutually exclusive workstreams.
- Clear file ownership for each workstream.
- A priority queue that keeps 6 agents busy whenever 6 unblocked workstreams exist.
- A manager/orchestrator that assigns, closes, and relaunches agents as workstreams complete.
- Integration checkpoints that remove code from the monolith only after replacement files exist.

## Success Criteria

- `Sources/GrokClient/GrokClient.swift` is reduced from a 4,900-line monolith into focused source files.
- Public API behavior is preserved unless an explicitly approved follow-up accepts a breaking change.
- Public and `@testable`-visible model/helper access levels are preserved.
- Transport, HTTP validation, cURL redaction, and request execution are centralized.
- Streaming parsing is a dedicated state machine with independent tests.
- Dynamic JSON lookup and model factory code use one shared internal lookup utility.
- Endpoint methods are separated into domain files.
- URL/path/query construction is normalized and covered by exact URL tests.
- Six workers are kept active whenever the dependency graph allows it.
- After implementation is approved and executed, build, tests, and install run so the CLI is usable from `PATH`.

## Current-State Findings

### Commands Run During Planning

- [x] `wc -l Sources/GrokClient/*.swift Tests/GrokClientTests/GrokClientTests.swift`
- [x] `rg -n "^// MARK:|^public (struct|class|enum|protocol)|^struct |^enum |^extension |^public extension|^private extension|^    public func|^    func|^    private func|^    public static func|^    static func|^    private static func" Sources/GrokClient/GrokClient.swift`
- [x] `rg -n "func test|MockURLProtocol|StreamingURLProtocol|preparePayload|streamResponses|speechToText|uploadFile|listTasks|rateLimits|typeahead|listModes|workspaces|assets|userSettings|subscriptions|shareLink|sendMessage|continueConversation|getResponseNodes|loadResponses|listConversations" Tests/GrokClientTests/GrokClientTests.swift`
- [x] `git diff --stat -- Sources/GrokClient/GrokClient.swift Tests/GrokClientTests/GrokClientTests.swift Sources/GrokClient/GrokSettingsClient.swift Sources/GrokClient/GrokUserSettings.swift Sources/GrokClient/GrokCookieHelper.swift`
- [x] `git ls-files --others --exclude-standard Sources/GrokClient Tests/GrokClientTests plans | sort`

### Codebase Shape

- [x] `Sources/GrokClient/GrokClient.swift` is about 4,900 lines and contains models, client storage/init, transport, dynamic JSON helpers, factories, streaming, endpoints, and cURL debug output.
- [x] `Tests/GrokClientTests/GrokClientTests.swift` is about 1,525 lines and contains both tests and mock URL protocol support.
- [x] Public and internal model definitions occupy roughly `Sources/GrokClient/GrokClient.swift:10-1435`.
- [x] `public class GrokClient` begins around `Sources/GrokClient/GrokClient.swift:1438`.
- [x] Endpoint methods occupy roughly `Sources/GrokClient/GrokClient.swift:3889-4797`.
- [x] `StreamingLineDelegate` and line parsing occupy roughly `Sources/GrokClient/GrokClient.swift:3533-3876`.
- [x] `URLRequest.curlRepresentation` occupies roughly `Sources/GrokClient/GrokClient.swift:4801-4901`.
- [x] Some endpoints still use direct `session.data(for:)` instead of common JSON/void execution helpers.
- [x] `Sources/GrokClient/GrokSettingsClient.swift` and `Sources/GrokClient/GrokUserSettings.swift` are currently untracked/commented disabled settings work and should not be re-enabled as part of this refactor.
- [x] `Sources/GrokClient/GrokCookies.swift` exists locally and must be treated as generated/credential-sensitive/off-limits.
- [x] The worktree is already dirty, including `GrokClient.swift`, `GrokClientTests.swift`, CLI files, docs, and untracked files. Execution must preserve existing user work.

## Execution Model

### Worker Pool Rules

- [ ] Maintain at most 6 active implementation agents.
- [ ] Assign every agent one workstream ID from the queue below.
- [ ] Close an agent immediately after its workstream is complete and reviewed.
- [ ] Launch the next highest-priority unblocked workstream into the freed slot.
- [ ] Never give agents full conversation history.
- [ ] Give agents clean, file-scoped, workstream-specific commands.
- [ ] Tell every worker it is not alone in the repo, must not revert others' edits, and must respect write ownership.
- [ ] Use `gpt-5.5` or better for implementation workers.
- [ ] The manager/orchestrator handles queue selection, integration checkpoints, and conflict resolution.

### Priority Rule

When a slot opens, assign the highest-priority unblocked workstream in this order:

1. Foundation workstreams.
2. Compile-shape integration workstreams.
3. Endpoint/domain extraction workstreams.
4. Factory/DRY migration workstreams.
5. Test expansion workstreams.
6. Final verification/install workstream.

### Initial Six Active Agents

Start these six immediately after implementation approval:

| Slot | Workstream | Reason |
| --- | --- | --- |
| 1 | W01 Models Extraction | Unblocks most files. |
| 2 | W02 Client Core And Transport | Unblocks endpoint files. |
| 3 | W03 HTTP Validation And Debug Curl | Independent transport-adjacent file ownership. |
| 4 | W04 JSONLookup Skeleton | Unblocks later factory migrations. |
| 5 | W05 Test Support Extraction | Lets test agents work without colliding in one test file. |
| 6 | W06 URL And Options Foundations | Unblocks endpoint normalization and wrapper work. |

When any slot completes, close that agent and assign the next unblocked workstream from the queue.

## Write Ownership Matrix

No two active workstreams may write the same file unless the manager explicitly serializes that handoff.

| Area | Owner Workstreams |
| --- | --- |
| `Sources/GrokClient/GrokClient.swift` removals | Manager/integrator only |
| `Sources/GrokClient/Models/**` | W01 |
| `Sources/GrokClient/GrokClientCore.swift` | W02 |
| `Sources/GrokClient/GrokClientTransport.swift` | W02 |
| `Sources/GrokClient/GrokHTTPValidation.swift` | W03 |
| `Sources/GrokClient/GrokDebugCurl.swift` | W03 |
| `Sources/GrokClient/JSONLookup.swift` | W04 |
| `Sources/GrokClient/Options/**` or `GrokClientOptions.swift` | W06 |
| `Sources/GrokClient/EndpointPath.swift` | W06 |
| `Sources/GrokClient/Streaming/**` | W08, W09 |
| `Sources/GrokClient/Endpoints/GrokClient+Chat.swift` | W10 |
| `Sources/GrokClient/Endpoints/GrokClient+Conversations.swift` | W11 |
| `Sources/GrokClient/Endpoints/GrokClient+Sharing.swift` | W12 |
| `Sources/GrokClient/Endpoints/GrokClient+Tasks.swift` | W13 |
| `Sources/GrokClient/Endpoints/GrokClient+Account.swift` | W14 |
| `Sources/GrokClient/Endpoints/GrokClient+FilesAudio.swift` | W15 |
| `Sources/GrokClient/Endpoints/GrokClient+Workspaces.swift` | W16 |
| `Sources/GrokClient/Parsers/**` | W17-W20 |
| `Tests/GrokClientTests/Support/**` | W05 |
| `Tests/GrokClientTests/*Tests.swift` | W21-W26 |
| `Sources/GrokClient/GrokCookies.swift` | Off-limits |
| `Sources/GrokClient/GrokSettingsClient.swift`, `GrokUserSettings.swift` | Off-limits unless explicitly reassigned |

## Workstream Queue

Each workstream below is MECE: it has a distinct purpose, distinct files, explicit blockers, and acceptance criteria.

### W00 Manager Preflight And Queue Setup

Owner: manager/orchestrator, not a worker slot.

Blockers: none.

Tasks:

- [ ] Run `git status --short` and save the output in implementation notes.
- [ ] Confirm current dirty files and untracked files.
- [ ] Create destination directories.
- [ ] Confirm no agent is assigned to `GrokCookies.swift`.
- [ ] Launch W01-W06 as the initial six active agents.

Acceptance:

- [ ] Six agents are active or fewer if fewer than six are unblocked.
- [ ] Every agent has one workstream ID and disjoint write ownership.

### W01 Models Extraction

Owned files:

- `Sources/GrokClient/Models/GrokError.swift`
- `Sources/GrokClient/Models/GrokMode.swift`
- `Sources/GrokClient/Models/AnyCodable.swift`
- `Sources/GrokClient/Models/BasicResponses.swift`
- `Sources/GrokClient/Models/SubscriptionModels.swift`
- `Sources/GrokClient/Models/ConversationModels.swift`
- `Sources/GrokClient/Models/DiscoveryModels.swift`
- `Sources/GrokClient/Models/StreamingModels.swift`
- `Sources/GrokClient/Models/TaskModels.swift`
- `Sources/GrokClient/Models/ResourceModels.swift`

Blockers: none.

Tasks:

- [ ] Move `GrokError` to `GrokError.swift`.
- [ ] Move `GrokMode` to `GrokMode.swift`.
- [ ] Move `AnyCodable` to `AnyCodable.swift`.
- [ ] Move basic response/rate-limit models to `BasicResponses.swift`.
- [ ] Move subscription models to `SubscriptionModels.swift`.
- [ ] Move conversation/search/X post models to `ConversationModels.swift`.
- [ ] Move typeahead/modes response models to `DiscoveryModels.swift`.
- [ ] Move internal streaming decode models to `StreamingModels.swift`.
- [ ] Move task models/wrappers to `TaskModels.swift`.
- [ ] Move skill/agent/workspace/asset/file wrappers to `ResourceModels.swift`.
- [ ] Preserve public/internal access levels exactly.
- [ ] Add only needed imports, usually `Foundation`.
- [ ] Do not delete moved code from `GrokClient.swift`; signal W07 when ready.

Acceptance:

- [ ] Destination model files contain complete type definitions.
- [ ] No public initializer/property/conformance was dropped.
- [ ] Internal streaming models remain internal for `@testable` tests.

### W02 Client Core And Transport

Owned files:

- `Sources/GrokClient/GrokClientCore.swift`
- `Sources/GrokClient/GrokClientTransport.swift`

Blockers: none, but coordinate with W03 on validation/debug split.

Tasks:

- [ ] Move or define the core `GrokClient` stored-property/init shape.
- [ ] Preserve cookie non-empty validation.
- [ ] Preserve injected `URLSession` behavior.
- [ ] Preserve default `URLSessionConfiguration` cookie storage setup.
- [ ] Move `RestNamespace`.
- [ ] Move base URL normalization.
- [ ] Move headers, cookie header, Statsig path, and Statsig ID generation.
- [ ] Move `makeRequest`.
- [ ] Add shared `sendJSON`, `sendVoid`, and `decodeJSON<T>` helpers.
- [ ] Make `session` immutable if compatible.
- [ ] Do not migrate endpoint methods here.
- [ ] Signal W07 when replacement core/transport code is ready.

Acceptance:

- [ ] Core transport APIs exist and preserve namespace behavior.
- [ ] Request building still supports mock/injected sessions.
- [ ] Shared execution helpers are available for endpoint workstreams.

### W03 HTTP Validation And Debug Curl

Owned files:

- `Sources/GrokClient/GrokHTTPValidation.swift`
- `Sources/GrokClient/GrokDebugCurl.swift`

Blockers: none, but coordinate with W02 on method names.

Tasks:

- [ ] Move `validateHTTPResponse`.
- [ ] Move HTTP body message extraction.
- [ ] Move auth-failure body detection.
- [ ] Move access-denied message construction.
- [ ] Move generic API error description.
- [ ] Move `URLRequest.curlRepresentation`.
- [ ] Preserve cookie/header redaction.
- [ ] Preserve body redaction for `audioBase64`, `content`, `data`, and `file`.
- [ ] Do not change error wording unless tests are updated.

Acceptance:

- [ ] Transport can call validation helpers.
- [ ] cURL debug output remains redacted.
- [ ] No endpoint-domain code was moved into these files.

### W04 JSONLookup Skeleton

Owned files:

- `Sources/GrokClient/JSONLookup.swift`

Blockers: none.

Tasks:

- [ ] Add internal `JSONLookup` wrapper over `Any?`.
- [ ] Support `AnyCodable`, `[String: AnyCodable]`, `[AnyCodable]`, `[String: Any]`, `[Any]`.
- [ ] Implement direct lookup APIs: `string`, `stringAllowingEmpty`, `bool`, `int`, `double`.
- [ ] Implement recursive lookup APIs: `firstString`, `firstBool`, `firstInt`.
- [ ] Implement dictionary traversal APIs: `firstDictionary`, `dictionaries`, `allDictionaries`.
- [ ] Implement `containsAnyKey` and raw `AnyCodable` conversion.
- [ ] Keep direct and recursive lookup behavior distinct.
- [ ] Do not migrate factories yet.

Acceptance:

- [ ] `JSONLookup` compiles independently once W01 model extraction is integrated.
- [ ] API is sufficient for W17-W20 parser migrations.

### W05 Test Support Extraction

Owned files:

- `Tests/GrokClientTests/Support/MockURLProtocol.swift`
- `Tests/GrokClientTests/Support/StreamingURLProtocol.swift`
- `Tests/GrokClientTests/Support/MockSessionFactory.swift`

Blockers: none.

Tasks:

- [ ] Extract `MockURLProtocol`.
- [ ] Extract `StreamingURLProtocol`.
- [ ] Extract mock session factory helpers.
- [ ] Keep current request/body capture behavior.
- [ ] Keep queued response behavior.
- [ ] Do not rewrite production tests yet.

Acceptance:

- [ ] Test support files exist.
- [ ] Existing tests can be updated by later test workstreams without redefining support classes.

### W06 URL And Options Foundations

Owned files:

- `Sources/GrokClient/EndpointPath.swift`
- `Sources/GrokClient/GrokClientOptions.swift`

Blockers: none.

Tasks:

- [ ] Add `encodedPathSegment(_:)`.
- [ ] Add `endpointPath(_ segments: [String], queryItems: [URLQueryItem]) throws -> String`.
- [ ] Ensure path segment encoding handles `/`, `?`, `&`, spaces, and unicode.
- [ ] Add additive option types only, no behavior changes:
  - [ ] `GrokMessageOptions`
  - [ ] `GrokTaskCreateOptions`
  - [ ] `GrokWorkspaceCreateOptions`
  - [ ] `GrokWorkspaceListOptions`
  - [ ] `GrokAssetListOptions`
  - [ ] `GrokSpeechToTextOptions`
  - [ ] `GrokShareLinkOptions`
- [ ] Do not update endpoint methods yet.

Acceptance:

- [ ] Path helper and option types are available to endpoint workstreams.
- [ ] No old public method signature was removed.

### W07 Monolith Foundation Integration

Owner: manager/integrator, not parallel with W01-W03 touching source definitions.

Blockers: W01, W02, W03.

Tasks:

- [ ] Remove moved model definitions from `GrokClient.swift`.
- [ ] Remove moved transport/validation/debug definitions from `GrokClient.swift`.
- [ ] Keep a small `GrokClient` anchor or core file, whichever W02 chose.
- [ ] Resolve imports.
- [ ] Resolve duplicate symbols.
- [ ] Run the first compile gate after duplicates are gone.

Acceptance:

- [ ] No duplicate model/transport/debug definitions remain.
- [ ] Foundation compile errors are limited to downstream endpoints/parsers/tests.

### W08 Stream Parser State Machine

Owned files:

- `Sources/GrokClient/Streaming/GrokStreamParser.swift`

Blockers: W01, W04, W07.

Tasks:

- [ ] Create explicit parser state: conversation ID, response ID, accumulated message, yielded final, finished.
- [ ] Implement `consume(line:)`.
- [ ] Implement `finish()`.
- [ ] Preserve blank-line ignore behavior.
- [ ] Preserve `data:` stripping.
- [ ] Preserve current `[DONE]` semantics unless tests intentionally change them.
- [ ] Preserve API error extraction.
- [ ] Preserve token/final/fallback/thinking behavior.
- [ ] Move terminal empty-token marker logic into parser.

Acceptance:

- [ ] Parser is independent from network line transport.
- [ ] Existing stream parser tests can target it through `streamResponses(from:)`.

### W09 Streaming Line Transport

Owned files:

- `Sources/GrokClient/Streaming/GrokStreamingLineReader.swift`
- `Sources/GrokClient/Streaming/GrokClient+Streaming.swift`

Blockers: W02, W03, W07.

Tasks:

- [ ] Move `streamResponses(from:)` and keep it internal.
- [ ] Move `streamResponses(for:)`.
- [ ] Move `streamingLines(for:)`.
- [ ] Move `StreamingLineDelegate`.
- [ ] Replace front-removal `Data.removeSubrange` loop with offset-based line reader.
- [ ] Preserve final partial-line flush.
- [ ] Add cancellation linkage for unstructured stream tasks.
- [ ] Avoid weak validation closures that can silently skip HTTP error validation.

Acceptance:

- [ ] Streaming line transport is separate from parser state machine.
- [ ] HTTP error responses still validate buffered error body.

### W10 Chat Endpoint And Message Options

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+Chat.swift`

Blockers: W02, W06, W08, W09.

Tasks:

- [ ] Move `preparePayload`.
- [ ] Move `streamMessage`.
- [ ] Move `sendMessage`.
- [ ] Move `continueConversation`.
- [ ] Add options overloads using `GrokMessageOptions`.
- [ ] Keep old signatures as wrappers.
- [ ] Preserve deprecated parameter compatibility.
- [ ] Preserve payload body shape.

Acceptance:

- [ ] Old chat methods still compile and call the same endpoints.
- [ ] Options overloads reduce internal duplication without source break.

### W11 Conversations Endpoint

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+Conversations.swift`

Blockers: W02, W06, W07.

Tasks:

- [ ] Move `listConversations`.
- [ ] Move `softDeleteConversation`.
- [ ] Move `getResponseNodes`.
- [ ] Move `loadResponses`.
- [ ] Move `getConversationV2`.
- [ ] Replace direct `session.data(for:)` with shared transport helpers where possible.
- [ ] Normalize path/query building.
- [ ] Preserve current decode fallbacks.

Acceptance:

- [ ] Exact existing URL tests pass.
- [ ] Conversation response decode fallbacks remain.

### W12 Sharing Endpoint

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+Sharing.swift`

Blockers: W02, W04, W06, W07.

Tasks:

- [ ] Move `shareLinkURL`.
- [ ] Move `createShareLinkURL`.
- [ ] Move share-link URL parsing helpers.
- [ ] Add `GrokShareLinkOptions` overload if useful.
- [ ] Normalize path/query building.
- [ ] Preserve fallback create behavior when lookup is empty.

Acceptance:

- [ ] Existing share lookup/create tests pass.
- [ ] URL-from-identifier behavior is unchanged.

### W13 Tasks Endpoint

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+Tasks.swift`

Blockers: W02, W06, W07.

Tasks:

- [ ] Move `listTasksResponse`.
- [ ] Move `listTasks`.
- [ ] Move `listInactiveTasksResponse`.
- [ ] Move `listInactiveTasks`.
- [ ] Move `taskResultsResponse`.
- [ ] Move `taskResults`.
- [ ] Move `latestTaskResult`.
- [ ] Move both `createTask` overloads.
- [ ] Move `archiveTask`.
- [ ] Add options overloads using `GrokTaskCreateOptions`.
- [ ] Keep old signatures as wrappers.

Acceptance:

- [ ] Task endpoint URL/body tests pass.
- [ ] Old create-task signatures remain source-compatible.

### W14 Account, Discovery, Modes, Settings

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+Account.swift`

Blockers: W02, W06, W07.

Tasks:

- [ ] Move `typeahead`.
- [ ] Move `listSkillsResponse` and `listSkills`.
- [ ] Move `listUserSkillsResponse` and `listUserSkills`.
- [ ] Move `getUserSettingsResponse`.
- [ ] Move `updateAgentCustomizations`.
- [ ] Move `subscriptionsResponse` and `currentSubscription`.
- [ ] Move `rateLimits` overloads.
- [ ] Move `listModesResponse` and `listModes`.
- [ ] Preserve root/web namespace behavior.
- [ ] Do not re-enable disabled settings snapshot files.

Acceptance:

- [ ] Modes, rate limits, subscriptions, typeahead, and settings tests pass.
- [ ] Disabled settings files remain out of scope.

### W15 Files, Audio, Assets

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+FilesAudio.swift`

Blockers: W02, W06, W07.

Tasks:

- [ ] Move `defaultSpeechRefinementLevel`.
- [ ] Move `inferAudioFormat`.
- [ ] Move all `speechToText` overloads.
- [ ] Move `uploadFile` overloads.
- [ ] Move `listAssetsResponse` and `listAssets`.
- [ ] Move `deleteAsset`.
- [ ] Add options overloads for speech-to-text and asset list.
- [ ] Preserve base64 redaction behavior through W03 debug curl.

Acceptance:

- [ ] Speech-to-text request/body tests pass.
- [ ] Upload/list/delete asset tests pass or are added.

### W16 Workspaces Endpoint

Owned files:

- `Sources/GrokClient/Endpoints/GrokClient+Workspaces.swift`

Blockers: W02, W06, W07.

Tasks:

- [ ] Move `createWorkspace`.
- [ ] Move `listWorkspacesResponse`.
- [ ] Move `listWorkspaces`.
- [ ] Move `deleteWorkspace`.
- [ ] Move `addConversationToWorkspace`.
- [ ] Add options overloads for create/list.
- [ ] Normalize path/query building.

Acceptance:

- [ ] Workspace endpoints compile and exact URL tests pass.

### W17 Low-Risk Factory Migration

Owned files:

- `Sources/GrokClient/Parsers/GrokResourceParsers.swift`
- `Sources/GrokClient/Parsers/GrokTypeaheadParser.swift`

Blockers: W01, W04, W07.

Tasks:

- [ ] Migrate `makeSkill` to `JSONLookup`.
- [ ] Migrate `makeWorkspace` to `JSONLookup`.
- [ ] Migrate `makeAsset` to `JSONLookup`.
- [ ] Migrate `makeFileUploadResponse` to `JSONLookup`.
- [ ] Migrate `makeTypeaheadResponse` to `JSONLookup`.
- [ ] Preserve raw JSON output shape.

Acceptance:

- [ ] Resource/typeahead factory tests pass.
- [ ] Endpoint files call parser helpers instead of duplicating lookup logic.

### W18 Mode And Discovery Factory Migration

Owned files:

- `Sources/GrokClient/Parsers/GrokModeParser.swift`

Blockers: W01, W04, W07.

Tasks:

- [ ] Migrate `modeDictionaries`.
- [ ] Migrate `makeMode`.
- [ ] Migrate `modeAvailability`.
- [ ] Preserve mode dedupe behavior.
- [ ] Preserve current non-bool availability behavior.

Acceptance:

- [ ] Mode parsing tests pass.
- [ ] Mode availability edge cases are explicitly covered.

### W19 Task Factory Migration

Owned files:

- `Sources/GrokClient/Parsers/GrokTaskParser.swift`

Blockers: W01, W04, W07, W13.

Tasks:

- [ ] Migrate `makeTask`.
- [ ] Migrate schedule merge helpers.
- [ ] Migrate `makeTasksResponse`.
- [ ] Migrate `makeTaskResult`.
- [ ] Migrate task result wrapper traversal.
- [ ] Preserve active/inactive/default enabled behavior.

Acceptance:

- [ ] Nested active/inactive task tests pass.
- [ ] Singular wrapped task result tests pass.

### W20 Account Factory Migration

Owned files:

- `Sources/GrokClient/Parsers/GrokAccountParser.swift`
- `Sources/GrokClient/Parsers/GrokRateLimitParser.swift`

Blockers: W01, W04, W07, W14.

Tasks:

- [ ] Migrate `makeAgentCustomization`.
- [ ] Migrate agent customization traversal.
- [ ] Migrate subscription parsing.
- [ ] Migrate rate-limit parsing.
- [ ] Cache ISO8601 date formatters.
- [ ] Cache duration regex.
- [ ] Preserve requested-model matching priority.

Acceptance:

- [ ] Subscription tests pass.
- [ ] Rate-limit nested/string/window tests pass.
- [ ] Requested model wins over unrelated nested model.

### W21 Model And Transport Tests

Owned files:

- `Tests/GrokClientTests/GrokClientModelTests.swift`
- `Tests/GrokClientTests/GrokClientRequestBuildingTests.swift`

Blockers: W01, W02, W03, W05, W07.

Tasks:

- [ ] Move/preserve model tests from monolithic test file.
- [ ] Add base URL normalization tests.
- [ ] Add header/cookie/request ID/statsig tests.
- [ ] Add GET header omission tests.
- [ ] Add validation error mapping tests.
- [ ] Add cURL redaction tests.

Acceptance:

- [ ] Model and request-building tests pass in focused filter.

### W22 Streaming Tests

Owned files:

- `Tests/GrokClientTests/GrokClientStreamingTests.swift`

Blockers: W05, W08, W09, W10.

Tasks:

- [ ] Move existing stream tests.
- [ ] Add arbitrary chunk-split test.
- [ ] Add CRLF test.
- [ ] Add final partial-line test.
- [ ] Add non-2xx streaming error-body test.
- [ ] Add invalid UTF-8 test.
- [ ] Add explicit `[DONE]` semantics test.
- [ ] Add cancellation test if implementation exposes a reliable assertion.

Acceptance:

- [ ] Streaming tests pass.
- [ ] Incremental first-token behavior is preserved.

### W23 JSON And Factory Tests

Owned files:

- `Tests/GrokClientTests/GrokClientJSONLookupTests.swift`
- `Tests/GrokClientTests/GrokClientFactoryTests.swift`

Blockers: W04, W17, W18, W19, W20.

Tasks:

- [ ] Add direct vs recursive lookup tests.
- [ ] Add AnyCodable nested conversion tests.
- [ ] Add wrapper traversal tests.
- [ ] Add factory regression tests for resources, modes, tasks, subscriptions, and rate limits.

Acceptance:

- [ ] JSON lookup and factory tests pass.

### W24 Endpoint Tests

Owned files:

- `Tests/GrokClientTests/GrokClientChatTests.swift`
- `Tests/GrokClientTests/GrokClientConversationTests.swift`
- `Tests/GrokClientTests/GrokClientSharingTests.swift`
- `Tests/GrokClientTests/GrokClientTasksTests.swift`
- `Tests/GrokClientTests/GrokClientAccountTests.swift`
- `Tests/GrokClientTests/GrokClientFilesAudioTests.swift`
- `Tests/GrokClientTests/GrokClientWorkspaceTests.swift`

Blockers: W05, W10-W16.

Tasks:

- [ ] Move existing endpoint tests from monolithic file.
- [ ] Add exact path/query tests for spaces, `/`, `?`, `&`, and unicode in IDs/search strings.
- [ ] Add old-signature vs options-overload body equivalence tests.
- [ ] Preserve existing endpoint URL/body assertions.

Acceptance:

- [ ] All endpoint tests pass.
- [ ] Old public signatures remain covered.

### W25 CLI And Proxy Compatibility Sweep

Owned files:

- `Sources/GrokCLI/**` only if compile errors require it.
- `Sources/GrokProxy/**` only if compile errors require it.
- `Tests/GrokProxyTests/**` only if compile errors require it.
- `Tests/GrokCLIE2ETests/**` only if compile errors require it.

Blockers: W10-W16, W21-W24.

Tasks:

- [ ] Build enough to identify source compatibility issues.
- [ ] Fix only compile fallout from `GrokClient` refactor.
- [ ] Do not refactor CLI/proxy behavior.
- [ ] Keep `@preconcurrency import GrokClient` usage working.

Acceptance:

- [ ] CLI and proxy compile with the refactored client.
- [ ] Any required downstream changes are minimal and explained.

### W26 Final Verification And Install

Owner: manager/orchestrator or final verification worker.

Blockers: all production/test workstreams.

Tasks:

- [ ] Run `git diff --check`.
- [ ] Run `swift build`.
- [ ] Run `swift test --filter GrokClientTests`.
- [ ] Run `swift test --filter GrokProxyTests`.
- [ ] Run `swift test --filter GrokCLIE2ETests`.
- [ ] Run `swift test`.
- [ ] Run `python3 Tests/test_cookie_extractor.py`.
- [ ] Run `Scripts/install_cli.sh`.
- [ ] Run `grok --help`.
- [ ] Run `grok models`.
- [ ] Run `grok test hello`.
- [ ] Record any blocker exactly if a command cannot run.

Acceptance:

- [ ] Build passes or blocker is documented.
- [ ] Tests pass or blocker is documented.
- [ ] Install completes or blocker is documented.
- [ ] Installed `grok` is runnable from `PATH` or blocker is documented.

## Continuous Six-Agent Scheduling

Use this queue discipline during execution:

1. Launch W01-W06.
2. When W01-W03 complete, run W07 immediately.
3. While W07 runs, keep other slots filled with unblocked test scaffolding or `JSONLookup` follow-ups.
4. After W07 completes, fill all six slots with W08-W13.
5. As W08-W13 complete, launch W14-W20 in priority order.
6. As production workstreams complete, launch W21-W24 test workstreams.
7. Launch W25 only after enough compile shape exists to find downstream fallout.
8. Launch W26 only after all production and test workstreams are complete.

Expected high-throughput assignment sequence:

```text
Batch 1: W01 W02 W03 W04 W05 W06
Integration gate: W07 as soon as W01 W02 W03 are ready
Rolling queue after W07: W08 W09 W10 W11 W12 W13
Next rolling queue: W14 W15 W16 W17 W18 W21
Next rolling queue: W19 W20 W22 W23 W24 W25
Final gate: W26
```

This is a logical sequence, not a fixed barrier schedule. If W12 finishes before W10, close W12's agent and launch the next unblocked workstream immediately. If a test workstream such as W21 becomes unblocked before a production workstream, launch it rather than leaving an agent slot idle.

## Verification Gates

Do not run build/test/install for this plan-only request. During approved implementation, run these gates.

### Early Compile Gates

- [ ] After W07: `swift build`
- [ ] After W08-W10: `swift test --filter GrokClientStreamingTests`
- [ ] After W11-W16: `swift test --filter GrokClientTests`

### Final Gates

```bash
git diff --check
swift build
swift test --filter GrokClientTests
swift test --filter GrokProxyTests
swift test --filter GrokCLIE2ETests
swift test
python3 Tests/test_cookie_extractor.py
Scripts/install_cli.sh
grok --help
grok models
grok test hello
```

Optional proxy smoke tests require explicit approval if they may use real credentials or services:

```bash
swift run proxy serve
./Scripts/test_proxy_models.sh
./Scripts/test_proxy_streaming.sh
./Scripts/test_proxy_request.sh
```

## Risk And Rollback

### Risks

- [ ] `GrokClient.swift` conflict storm if multiple workers delete from it. Mitigation: only W07/integrator removes from the monolith.
- [ ] Access-control fallout from moving private helpers. Mitigation: keep endpoint-specific helpers co-located and make shared helpers `internal`, not `public`.
- [ ] Public API drift. Mitigation: old signatures remain wrappers.
- [ ] Streaming regression. Mitigation: W22 protects incremental/final/fallback/cancellation behavior.
- [ ] URL drift. Mitigation: W06 helper plus W24 exact URL tests.
- [ ] Recursive JSON lookup false positives. Mitigation: direct vs recursive API split and W23 tests.
- [ ] Dirty worktree loss. Mitigation: preflight status and no broad reset/checkout.
- [ ] Credential leakage. Mitigation: `GrokCookies.swift` and credential files are off-limits.

### Rollback Checkpoints

- [ ] Checkpoint 0: before W01-W06, record `git status --short`.
- [ ] Checkpoint 1: after W07 foundation integration.
- [ ] Checkpoint 2: after W08-W16 production endpoint split.
- [ ] Checkpoint 3: after W17-W20 factory migration.
- [ ] Checkpoint 4: after W21-W24 tests pass.
- [ ] Checkpoint 5: after W26 final verification/install.

Rollback rule: revert by workstream-owned files only. Do not use `git reset --hard` or broad checkout.

## Final Completion Checklist

Modular decomposition:

- [ ] Evidence: `GrokClient.swift` is small and no longer owns models, streaming, endpoints, and debug curl all at once.
- [ ] Evidence: model, transport, streaming, endpoint, parser, option, and test files exist in their owned locations.

Elegant/DRY/performance refactor:

- [ ] Evidence: common transport helpers replace duplicated direct `session.data(for:)` paths or documented exceptions remain.
- [ ] Evidence: `JSONLookup` replaces duplicated lookup helper families.
- [ ] Evidence: stream parser is isolated and line buffering avoids repeated front removal.
- [ ] Evidence: date formatters/regex are cached.
- [ ] Evidence: options overloads reduce repeated long signatures while preserving compatibility wrappers.

Six-agent execution:

- [ ] Evidence: implementation log shows at most 6 active agents at any time.
- [ ] Evidence: agents were closed and replaced as workstreams completed.
- [ ] Evidence: workstream IDs map to disjoint file ownership.

Verification and install:

- [ ] Evidence: build completed or blocker was documented.
- [ ] Evidence: focused and full tests completed or blocker was documented.
- [ ] Evidence: install completed or blocker was documented.
- [ ] Evidence: installed `grok` ran from `PATH` or blocker was documented.

Safety:

- [ ] Evidence: no generated credential/cookie file was modified.
- [ ] Evidence: existing user changes were preserved.
