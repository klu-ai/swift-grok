# Releases

## 2026-05-13

- Added and documented CLI JSON mode across commands, including `--json`, `--format json`, JSON-only stdout, NDJSON streaming for `grok message --stream --json`, command examples, and auth generate/import JSON results.

## 2025-07-09

- Deprecated Grok 3 server-side personality presets for Grok 4. The old `grok3_personality_*` `systemPromptName` values are retained in the Swift API for source compatibility, but SwiftGrok no longer sends them to Grok because Grok 4 no longer appears to apply them as distinct personas. Configure instructions in Grok agent settings instead.
- Deprecated local custom instructions for Grok 4. `--no-custom-instructions` is retained as an ignored compatibility flag, local custom-instruction editing commands are no longer advertised or handled, and per-message `customInstructions` no longer sends `customPersonality`; instructions now live in Grok agent settings.
- Deprecated deep research and search configuration for Grok 4. `--deep-search` and `--no-search` are retained as no-op compatibility shims for scripts; `enableDeepSearch` and `disableSearch` remain in the Swift API for source compatibility, but SwiftGrok no longer sends search toggles because search is automatic and no longer configurable. The old interactive search slash commands are no longer advertised or handled.
