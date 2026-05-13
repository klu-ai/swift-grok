#!/bin/bash

# Test request for the OpenAI-compatible audio transcription endpoint

set -euo pipefail

BASE_URL="${GROK_PROXY_URL:-http://127.0.0.1:8080}"
MODEL="${GROK_TRANSCRIPTION_MODEL:-whisper-1}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <audio-file> [model]" >&2
  echo "Example: $0 Tests/Fixtures/audio/sample.webm whisper-1" >&2
  exit 2
fi

AUDIO_FILE="$1"
if [[ $# -ge 2 ]]; then
  MODEL="$2"
fi

if [[ ! -f "$AUDIO_FILE" ]]; then
  echo "Audio file not found: $AUDIO_FILE" >&2
  exit 2
fi

echo "Testing /v1/audio/transcriptions..."
curl -sS -X POST "$BASE_URL/v1/audio/transcriptions" \
  -F "file=@${AUDIO_FILE}" \
  -F "model=${MODEL}"

echo
