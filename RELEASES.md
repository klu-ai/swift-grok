# Releases

## 2025-07-09

- Deprecated Grok 3 server-side personality presets for Grok 4. The old `grok3_personality_*` `systemPromptName` values are retained in the Swift API for source compatibility, but SwiftGrok no longer sends them to Grok because Grok 4 no longer appears to apply them as distinct personas. Use explicit custom instructions instead.
