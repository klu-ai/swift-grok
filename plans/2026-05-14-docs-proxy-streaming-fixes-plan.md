# Docs And Proxy Streaming Fixes Plan

Date: 2026-05-14

## Objective

Update the repository so the README and supporting docs match the current code, fix the proxy streaming terminal chunk bug, and keep Docker/proxy credential behavior internally consistent.

This is a plan-only deliverable. No implementation has been executed yet.

## Success Criteria

- [ ] The Swift package install example uses the 0.2 line, specifically `from: "0.2.0"`, and release notes visibly identify the 0.2 release.
- [ ] README model examples no longer imply that bare `model 4` is a valid alias.
- [ ] README documents `GROK_CONFIG_DIR`, `GROK_COOKIE_EXTRACTOR`, and `GROK_BASE_URL`.
- [ ] `Tests/README.md` exists and documents all Swift, Python, and proxy smoke test commands.
- [ ] Proxy streaming emits a correct OpenAI-style terminal chunk with `finish_reason: "stop"` based on `ConversationResponse.isFinal`.
- [ ] Proxy streaming still ends with `data: [DONE]`.
- [ ] Proxy credential docs describe the actual accepted cookie JSON rules without overstating one fixed cookie set for every path.
- [ ] Docker docs and implementation agree on credential precedence.
- [ ] `docker-entrypoint.sh` is either integrated correctly or removed; the recommended path is removal because it is not wired into the current image.
- [ ] The user clarification is honored: do not "fix" the general OpenAI-compatible wording merely because the proxy has limited parameter/role mapping. It is compatible in the sense that an OpenAI client can connect.
- [ ] After implementation, run build and install so the on-path `grok` can be tested.

## Current-State Findings

### Discovery Completed

- [x] Inspected package products and targets in `Package.swift`.
- [x] Read source behavior before reading README.
- [x] Read `README.md`, `PROXY_README.md`, `DOCKER.md`, `RELEASES.md`, Docker files, scripts, tests, and relevant source files.
- [x] Checked local tags with `git tag --list`; no tags were returned.
- [x] Checked remote tags with `git ls-remote --tags origin`; no tags were returned.
- [x] Confirmed the working tree was already dirty before this planning pass.
- [x] Used six sub-agents for independent read-only discovery:
  - README/version/model-mode docs
  - test documentation
  - advanced config and credential docs
  - proxy streaming bug
  - Docker/entrypoint/credential precedence
  - release/version consistency
- [x] Closed completed sub-agents after collecting findings.

### Relevant Commands Used

- `rg --files`
- `find . -maxdepth 3 -type f ...`
- `git status --short`
- `git tag --list | sort -V | tail -20`
- `git ls-remote --tags origin | tail -20`
- `git ls-files -- Sources/GrokClient/GrokCookies.swift README.md PROXY_README.md DOCKER.md Scripts/install_cli.sh Scripts/setup_proxy.sh docker-entrypoint.sh docker-compose.yml Package.swift`
- `nl -ba README.md`
- `nl -ba PROXY_README.md`
- `nl -ba DOCKER.md`
- `nl -ba RELEASES.md`
- `nl -ba Package.swift`
- `nl -ba Sources/GrokClient/GrokClient.swift`
- `nl -ba Sources/GrokCLI/Runtime/ConfigManager.swift`
- `nl -ba Sources/GrokCLI/Runtime/GrokCLIApp.swift`
- `nl -ba Sources/GrokCLI/Interactive/InteractiveModelCommands.swift`
- `nl -ba Sources/GrokProxy/Controllers/ChatCompletionsController.swift`
- `nl -ba Sources/GrokProxy/Models/OpenAI.swift`
- `nl -ba Sources/GrokProxy/Services/GrokConfiguration.swift`
- `nl -ba Dockerfile`
- `nl -ba docker-compose.yml`
- `nl -ba docker-entrypoint.sh`
- `nl -ba Tests/GrokProxyTests/GrokProxyTests.swift`
- `nl -ba Tests/GrokCLIE2ETests/GrokCLIE2ETests.swift`
- `nl -ba Tests/test_cookie_extractor.py`

### Evidence Summary

- `README.md` Swift package usage currently uses `from: "1.0.0"` even though local and remote tag checks found no tags. User requested setting versioned references to 0.2.
- `GrokMode.resolve` accepts aliases such as `4.3`, `43`, `grok-4.3-beta`, and `grok-420-computer-use-sa`; it does not accept bare `4` as a model alias.
- `InteractiveModelCommands.promptForModelSelection` accepts numeric picker choices only when the interactive picker is open.
- `ConfigManager` supports:
  - `GROK_CONFIG_DIR` for the CLI credential directory.
  - `GROK_COOKIE_EXTRACTOR` for the cookie extractor path.
  - default credential storage at `$HOME/.config/grok-cli/credentials.json` on macOS and `$HOME/.grok-cli/credentials.json` elsewhere.
- `GrokClient` supports:
  - `GROK_BASE_URL`.
  - `GrokClient(..., baseURL:)`.
  - normalization from host, `/rest`, or `/rest/app-chat` to the app-chat and root REST endpoints.
- CLI credential import validation requires:
  - JSON object.
  - string keys and string values.
  - no empty values.
  - at least one of `sso`, `sso-rw`, `x-userid`, or `x-anonuserid`.
- Cookie generation via `cookie_extractor.py --required` looks for the richer browser-cookie set: `x-anonuserid`, `x-challenge`, `x-signature`, `sso`, and `sso-rw`.
- Proxy `GrokConfiguration` currently accepts a non-empty `[String: String]` from `GROK_COOKIES` first, then process-working-directory `credentials.json`, then mock cookies.
- `DOCKER.md` says Docker checks `/app/credentials.json` before `GROK_COOKIES`, which conflicts with `GrokConfiguration`.
- `Dockerfile` starts `./proxy` directly and does not copy or invoke `docker-entrypoint.sh`.
- `docker-entrypoint.sh` expects Python and `/app/cookie_extractor.py`, neither of which is present in the runtime image.
- `ChatCompletionsController.handleStreamingResponse` checks `webSearchResults` or `xposts` to infer a final chunk instead of using `ConversationResponse.isFinal`.
- `ChatCompletionChunkResponse.createDoneChunk` already exists and produces an empty terminal chunk with `finish_reason: "stop"`.
- Current `GrokProxyTests` cover route/model/validation paths, but not streaming SSE finish behavior.

## Parallel Workstreams

The implementation can run with up to six agents in parallel. Each workstream below has a disjoint primary write scope. Agents are not alone in the codebase and must not revert unrelated edits.

### Workstream 1: README Version And Model Docs

Owner scope:

- `README.md`
- `RELEASES.md`

Tasks:

- [x] Discover stale SwiftPM version example.
- [x] Discover no local or remote git tags exist.
- [x] Discover `model 4` does not resolve as a direct alias.
- [ ] Change the SwiftPM dependency example from `from: "1.0.0"` to `from: "0.2.0"`.
- [ ] Add or adjust release notes so the relevant current entry is visibly tied to `0.2.0`.
- [ ] Replace the interactive model example `model 4` with a valid direct alias, preferably `model 4.3` or `model grok-4.3-beta`.
- [ ] Clarify that numeric selection is available in the interactive model picker, not as arbitrary bare aliases.
- [ ] Expand alias text to include:
  - `auto`
  - `fast`
  - `expert`
  - `reasoning`
  - `think`
  - `grok-4.3-beta`
  - canonical raw ID `grok-420-computer-use-sa`
  - `heavy`
- [ ] Do not add any "not OpenAI-compatible" caveat to the main proxy description from the prior analysis; the user explicitly rejected that framing.

Dependencies:

- Can start immediately.
- Coordinate with Workstream 3 if both edit nearby README sections.

Implementation notes:

- Do not edit `Package.swift` for project versioning; SwiftPM packages do not carry the package release version there.
- Do not create a git tag unless the user explicitly requests publishing/version tagging.
- If using semver in docs, use `0.2.0` rather than vague `0.2`.

### Workstream 2: Test Documentation

Owner scope:

- `Tests/README.md`
- Optional short pointer in `README.md`

Tasks:

- [x] Discover SwiftPM test targets in `Package.swift`.
- [x] Discover Python cookie extractor tests.
- [x] Discover proxy smoke scripts.
- [ ] Create `Tests/README.md`.
- [ ] Document `swift test` as the full Swift test command.
- [ ] Document focused Swift test commands:
  - `swift test --filter GrokClientTests`
  - `swift test --filter GrokProxyTests`
  - `swift test --filter GrokCLIE2ETests`
- [ ] Document `python3 Tests/test_cookie_extractor.py`.
- [ ] Document proxy smoke scripts:
  - `./Scripts/test_proxy_request.sh`
  - `./Scripts/test_proxy_streaming.sh`
  - `./Scripts/test_proxy_models.sh`
  - `./Scripts/test_proxy_transcription.sh <audio-file> [model]`, if present in the current checkout.
- [ ] Document prerequisites for each suite:
  - Swift 6 toolchain.
  - macOS 14 for CLI target assumptions.
  - Python 3 for cookie extractor tests.
  - Running proxy on `http://127.0.0.1:8080` for smoke scripts.
  - `jq` for model smoke script if required.
  - `GROK_PROXY_URL` and `GROK_TRANSCRIPTION_MODEL` for transcription smoke script if present.
- [ ] Add a short "Tests are documented in `Tests/README.md`" pointer in the main README if it does not clutter the top-level docs.

Dependencies:

- Can start immediately.
- Coordinate with Workstream 4 if proxy streaming smoke assertions change.
- Coordinate with Workstream 6 for the final command list.

Implementation notes:

- Keep the file practical: commands first, what they cover second.
- Avoid claiming smoke scripts are hermetic; they require a running proxy and credentials.

### Workstream 3: Advanced Config And Credential Docs

Owner scope:

- `README.md`
- `PROXY_README.md`
- `DOCKER.md` only for credential wording if not owned by Workstream 5

Tasks:

- [x] Discover undocumented `GROK_CONFIG_DIR`.
- [x] Discover undocumented `GROK_COOKIE_EXTRACTOR`.
- [x] Discover undocumented `GROK_BASE_URL`.
- [x] Compare CLI credential validation, cookie extractor `--required`, and proxy credential loading.
- [ ] Add an "Advanced Configuration" section to `README.md`.
- [ ] Document `GROK_CONFIG_DIR`:
  - CLI saved credentials directory override.
  - Default macOS path: `$HOME/.config/grok-cli`.
  - Default non-macOS path: `$HOME/.grok-cli`.
- [ ] Document `GROK_COOKIE_EXTRACTOR`:
  - Explicit path override for `cookie_extractor.py`.
  - Useful for custom installs or test fixtures.
- [ ] Document `GROK_BASE_URL`:
  - Overrides the Grok REST base URL.
  - Accepts host, `/rest`, or `/rest/app-chat`-style values through normalization.
  - Useful for local mock servers and tests.
- [ ] Update auth docs to distinguish:
  - CLI imported credentials validation.
  - Cookie extractor generated credential expectations.
  - Proxy runtime credential loading.
- [ ] In `PROXY_README.md`, avoid saying one exact required cookie set is universally required for every credential source.
- [ ] State that for proxy runtime, `GROK_COOKIES` and `credentials.json` must be a non-empty JSON object of string key/value cookies; generated credentials should normally include `x-anonuserid`, `x-challenge`, `x-signature`, `sso`, and `sso-rw`.
- [ ] Preserve security-sensitive wording: credentials are browser cookies and should not be committed.

Dependencies:

- Coordinate with Workstream 1 for README edits.
- Coordinate with Workstream 5 for Docker credential precedence wording.

Implementation notes:

- Do not document local ignored `Sources/GrokClient/GrokCookies.swift` as the preferred path. It exists as a fallback/local generated artifact, but JSON credentials are safer.
- It is acceptable to mention `GrokCookies.swift` only as a legacy fallback if the README needs to explain lookup order.

### Workstream 4: Proxy Streaming Finish Chunk Fix

Owner scope:

- `Sources/GrokProxy/Controllers/ChatCompletionsController.swift`
- `Sources/GrokProxy/Models/OpenAI.swift` only if a small helper adjustment is needed
- `Tests/GrokProxyTests/GrokProxyTests.swift`
- `Scripts/test_proxy_streaming.sh`

Tasks:

- [x] Discover streaming branch uses `webSearchResults` or `xposts` instead of `response.isFinal`.
- [x] Discover `ChatCompletionChunkResponse.createDoneChunk` already exists.
- [x] Discover no existing proxy test asserts streaming finish behavior.
- [ ] Change `handleStreamingResponse` to branch on `response.isFinal`.
- [ ] Emit normal assistant deltas for non-final, non-thinking response chunks.
- [ ] Preserve first-token `role: "assistant"` behavior.
- [ ] On final response, emit exactly one terminal OpenAI chunk with `finish_reason: "stop"` and empty delta content, using `createDoneChunk` if possible.
- [ ] Keep `data: [DONE]` after the terminal chunk.
- [ ] Do not duplicate the final answer as both a content delta and terminal chunk unless the stream parser only surfaces final text and no prior deltas were emitted. If fallback content must be sent, send content before the stop chunk, then the stop chunk.
- [ ] Add or adjust tests for:
  - normal final response without sources.
  - final response with sources.
  - terminal chunk contains `finish_reason: "stop"`.
  - terminal chunk has no duplicated final message content.
  - stream ends with `data: [DONE]`.
- [ ] Tighten `Scripts/test_proxy_streaming.sh` to assert `finish_reason` and `[DONE]` when the proxy is live.

Dependencies:

- Can start immediately.
- Coordinate with Workstream 2 to document the updated smoke test behavior.

Implementation notes:

- The cleanest implementation is likely:
  - maintain `isFirstChunk`
  - maintain `emittedContent`
  - for each response:
    - if `response.isFinal`, optionally emit content only when no content was emitted and `response.message` is non-empty, then emit `createDoneChunk`
    - else if `!response.isThinking` and message is non-empty, emit delta
  - after loop, if no terminal chunk was emitted, emit a stop chunk before `[DONE]`
- Error path should emit an SSE error object and end, but should not emit a fake stop chunk.
- The test may require a test-injectable client or a local mock Grok endpoint; choose the smaller pattern already present in the test suite.

### Workstream 5: Docker Credential Order And Entrypoint Cleanup

Owner scope:

- `DOCKER.md`
- `Dockerfile`
- `docker-compose.yml`
- `docker-entrypoint.sh`
- `PROXY_README.md` only for Docker-specific cross-reference wording

Tasks:

- [x] Discover `GrokConfiguration` loads `GROK_COOKIES`, then process-working-directory `credentials.json`, then mock cookies.
- [x] Discover `DOCKER.md` reverses the credential order.
- [x] Discover `docker-entrypoint.sh` is not copied or used by `Dockerfile`.
- [x] Discover runtime image does not install Python or copy `cookie_extractor.py`, so the entrypoint script would not work as-is.
- [ ] Choose implementation/doc alignment path.
- [ ] Recommended path: remove `docker-entrypoint.sh` as orphaned dead code.
- [ ] Update `DOCKER.md` to state canonical Docker credential order:
  - `GROK_COOKIES` environment variable.
  - `/app/credentials.json` mounted from host, because `/app` is the container working directory.
  - mock fallback for startup only; real API calls will likely fail.
- [ ] Remove or update any `GENERATE_CREDENTIALS` guidance because the current runtime image does not support browser-cookie extraction in-container.
- [ ] Confirm `docker-compose.yml` examples match the documented order and mount path.
- [ ] If the implementation path is integration rather than removal, explicitly add:
  - copy `docker-entrypoint.sh`
  - install Python 3
  - copy `cookie_extractor.py`
  - set `ENTRYPOINT ["./docker-entrypoint.sh"]`
  - pass through to `./proxy`
  - document browser-cookie volume requirements
- [ ] Prefer removal unless the user explicitly asks for in-container credential generation.

Dependencies:

- Coordinate with Workstream 3 for credential wording in `PROXY_README.md`.
- Can run in parallel with Workstream 4 because code scopes are disjoint.

Implementation notes:

- Deleting `docker-entrypoint.sh` is a destructive file removal, but it is directly requested as one acceptable fix path by the user: "either integrate or remove."
- Do not change proxy credential precedence unless deciding to make mounted file override env. The least risky path is to keep implementation as-is and fix docs.

### Workstream 6: Verification, Build, Install, And Release Gate

Owner scope:

- No primary source ownership.
- May update `Tests/README.md` after Workstream 2 if commands differ.
- Owns final verification notes.

Tasks:

- [ ] Run focused tests after Workstream 4:
  - `swift test --filter GrokProxyTests`
- [ ] Run full Swift tests:
  - `swift test`
- [ ] Run Python cookie extractor tests:
  - `python3 Tests/test_cookie_extractor.py`
- [ ] Build debug products:
  - `swift build`
- [ ] Build/install CLI so user can test on path:
  - `Scripts/install_cli.sh --user`
  - or use the install mode that matches the user's current setup if discovered during implementation.
- [ ] Optionally build proxy release if Docker/proxy code changed:
  - `swift build -c release --product proxy`
- [ ] Optionally validate Docker build if Docker files changed and local Docker is available:
  - `docker compose build`
- [ ] Optionally run proxy smoke scripts only if valid credentials and a running proxy are available:
  - `./Scripts/test_proxy_models.sh`
  - `./Scripts/test_proxy_request.sh`
  - `./Scripts/test_proxy_streaming.sh`
- [ ] Record any skipped verification with exact reason.
- [ ] Confirm final docs have no lingering `from: "1.0.0"` or invalid `model 4` example.

Dependencies:

- Runs after Workstreams 1 through 5 land.
- Should be the final integration step.

Implementation notes:

- Because the worktree is already dirty, use `git diff -- <owned files>` to review only intended changes.
- Do not revert user changes in unrelated files.
- Do not create a git commit or tag unless requested.

## Concrete Execution Sequence

1. Start Workstreams 1 through 5 in parallel, each with the ownership boundaries above.
2. Hold Workstream 6 until the first five workstreams report ready.
3. Resolve any README conflicts between Workstreams 1 and 3 by letting Workstream 1 own version/model text and Workstream 3 own auth/config text.
4. Resolve any docs conflicts between Workstreams 3 and 5 by letting Workstream 5 own Docker-specific order, while Workstream 3 owns general proxy credential rules.
5. Integrate the streaming bug fix and tests before changing the smoke script, so the smoke script asserts the new real behavior.
6. Review all diffs for accidental credential exposure, especially `Sources/GrokClient/GrokCookies.swift` and generated credential files.
7. Run verification gates in Workstream 6.
8. Install the CLI after successful build/test gates so the user can test the on-path `grok`.

## Test And Verification Gates

Required:

- [ ] `swift test --filter GrokProxyTests`
- [ ] `swift test`
- [ ] `python3 Tests/test_cookie_extractor.py`
- [ ] `swift build`
- [ ] `Scripts/install_cli.sh --user` or equivalent install path

Recommended if Docker is available:

- [ ] `docker compose build`

Recommended if valid credentials and a running proxy are available:

- [ ] `./Scripts/test_proxy_models.sh`
- [ ] `./Scripts/test_proxy_request.sh`
- [ ] `./Scripts/test_proxy_streaming.sh`

Manual doc checks:

- [ ] `rg -n '1\\.0\\.0|model 4|docker-entrypoint|GENERATE_CREDENTIALS|GROK_CONFIG_DIR|GROK_COOKIE_EXTRACTOR|GROK_BASE_URL' README.md PROXY_README.md DOCKER.md RELEASES.md Tests/README.md Dockerfile docker-compose.yml`
- [ ] Confirm `README.md` still presents the proxy as OpenAI-client-connectable.
- [ ] Confirm `Tests/README.md` does not imply live credentials are needed for hermetic unit tests.

## Risks And Edge Cases

- Proxy streaming may currently rely on the final response carrying the full message. If only final text is emitted for some responses, the implementation must avoid dropping content.
- Some OpenAI clients tolerate only `[DONE]`; others also expect a final chunk with `finish_reason`. The fix should provide both.
- Vapor streaming tests may need a test seam for `GrokClient`. If mocking `GrokClient` directly is awkward, use a local `GROK_BASE_URL` mock endpoint or a small protocol abstraction scoped to proxy tests.
- Removing `docker-entrypoint.sh` could surprise anyone using it manually outside Dockerfile. The docs should make host-side credential generation the supported path.
- Changing docs to `0.2.0` without creating a tag still leaves publishing work outside this implementation. The user asked to set everything to version 0.2, but tag creation should be separate unless explicitly requested.
- README and PROXY_README credential wording must avoid encouraging people to commit cookie JSON.
- The local ignored `Sources/GrokClient/GrokCookies.swift` appears to contain credentials. Implementers should not add or expose it.

## Rollback Notes

- Documentation-only changes can be reverted file-by-file:
  - `README.md`
  - `RELEASES.md`
  - `PROXY_README.md`
  - `DOCKER.md`
  - `Tests/README.md`
- Proxy streaming code can be rolled back by reverting `ChatCompletionsController.swift`, `OpenAI.swift` if touched, and the associated proxy tests.
- If deleting `docker-entrypoint.sh` causes unexpected downstream use, restore the file and instead mark it unsupported in docs until a real integration is built.
- If `Scripts/test_proxy_streaming.sh` becomes too strict for live Grok variance, keep the unit test as the correctness gate and make smoke assertions tolerant but still check `[DONE]`.

## Final Completion Checklist

Mapping user requirements to evidence after implementation:

- [ ] "Set everything to version 0.2" is satisfied by `README.md` SwiftPM example using `from: "0.2.0"` and `RELEASES.md` showing `0.2.0`.
- [ ] "Fix model 4" is satisfied by README examples using valid aliases and explaining picker-only numeric selection.
- [ ] "Write test docs as README in tests folder" is satisfied by `Tests/README.md`.
- [ ] "Add advanced config to README" is satisfied by README entries for `GROK_CONFIG_DIR`, `GROK_COOKIE_EXTRACTOR`, and `GROK_BASE_URL`.
- [ ] "Fix streaming bug" is satisfied by proxy streaming tests showing `finish_reason: "stop"` and `data: [DONE]`.
- [ ] "Fix credential documentation" is satisfied by docs distinguishing CLI validation, generated cookies, and proxy runtime cookie JSON.
- [ ] "Fix Docker docs/implementation mismatch" is satisfied by `DOCKER.md` matching `GROK_COOKIES` first, then `/app/credentials.json`, then mock fallback, unless implementation is intentionally changed instead.
- [ ] "Fix docker-entrypoint.sh, either integrate or remove" is satisfied by removing the orphan script or fully wiring it into Docker. Recommended evidence: file deleted and Docker docs updated.
- [ ] "Before doing anything, create a parallel plan" is satisfied by this file and its six owner-scoped workstreams.
- [ ] Project instruction "After completing a plan, run build and install so user can test on path" is satisfied during implementation by `swift build` and `Scripts/install_cli.sh --user` or the appropriate install path.
