#!/bin/bash

set -euo pipefail

# Smoke test for OpenAI-compatible streaming responses.
# Requires a running proxy with credentials.

GROK_PROXY_URL="${GROK_PROXY_URL:-http://127.0.0.1:8080}"

run_stream_test() {
  local label="$1"
  local payload="$2"

  echo "Testing streaming response: ${label}"
  local output
  output="$(curl --no-buffer -sS -X POST "${GROK_PROXY_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "${payload}")"

  printf '%s\n' "${output}"

  if ! grep -q '"finish_reason":"stop"' <<< "${output}"; then
    echo "Expected a terminal chunk with finish_reason stop." >&2
    return 1
  fi

  if ! grep -q '^data: \[DONE\]$' <<< "${output}"; then
    echo "Expected final data: [DONE] marker." >&2
    return 1
  fi
}

run_stream_test "fast counting" '{
  "model": "fast",
  "messages": [
    {"role": "user", "content": "Count from 1 to 5 slowly, with a brief pause between each number."}
  ],
  "stream": true,
  "temperature": 0.7,
  "max_tokens": 100
}'

run_stream_test "expert haiku" '{
  "model": "expert",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Write a haiku about programming."}
  ],
  "stream": true
}'

echo "All streaming smoke checks passed."
