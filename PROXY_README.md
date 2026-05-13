# GrokProxy: OpenAI-Compatible Proxy for Grok

This project implements an OpenAI-compatible reverse proxy server for Grok, allowing applications designed to work with OpenAI's Chat Completions API to use Grok instead.

## Features

- OpenAI-compatible API endpoints
  - `/v1/chat/completions` - For generating chat responses
  - `/v1/audio/transcriptions` - For transcribing audio files
  - `/v1/models` - For listing available models
  - `/models` - Compatibility alias for model listing
- Conversion between OpenAI format and Grok format
- Reasoning is always enabled by Grok web modes since the Grok 4 release on 2025-07-09
- Verbose logging option for debugging
- Error handling and validation

## Getting Started

### Prerequisites

- Swift 6.0 or higher
- Vapor 4.x
- GrokClient (from the SwiftGrok package)

### Installation

1. Clone the repository
2. Configure Grok credentials by either:
   - Setting `GROK_COOKIES` to a JSON object of cookie key-values
   - Creating a `credentials.json` file in the process current working directory with the same JSON shape
   - Keeping credential files private; they contain browser cookies and should not be committed
3. Build and run the application:

```bash
swift build
swift run proxy serve
```

### Running with Verbose Logging

For debugging purposes, you can enable verbose logging to see detailed request and response information:

```bash
# Using command line flag
swift run proxy serve --verbose

# With explicit bind settings
swift run proxy serve --hostname 0.0.0.0 --port 8080 --verbose

# Or using environment variable
VERBOSE=true swift run proxy serve
```

## Usage

The server exposes OpenAI-compatible endpoints:

- `GET /`
- `GET /hello`
- `POST /v1/chat/completions`
- `POST /v1/audio/transcriptions`
- `GET /v1/models`
- `GET /models`

### Chat Completions

```
POST /v1/chat/completions
```

Example request:

```json
{
  "model": "fast",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello, who are you?"}
  ],
  "temperature": 0.7
}
```

Response:

```json
{
  "id": "chatcmpl-123abc",
  "object": "chat.completion",
  "created": 1677858242,
  "model": "fast",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! I'm an AI assistant powered by Grok. How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

### Audio Transcriptions

```
POST /v1/audio/transcriptions
```

The proxy accepts OpenAI-style multipart uploads and returns an OpenAI-style transcription response:

```bash
curl http://127.0.0.1:8080/v1/audio/transcriptions \
  -F file=@recording.webm \
  -F model=whisper-1
```

Response:

```json
{
  "text": "transcribed text"
}
```

Optional multipart fields:

| Field | Description |
|-------|-------------|
| `audio_format` | Overrides format inference from the filename or content type, for example `webm`, `wav`, `mp3`, `m4a`, `ogg`, or `flac`. |
| `refinement_level` | Passes the requested Grok transcription refinement level. |
| `response_format` | Supports `json` (default) and `text`. Other formats return `400`. |
| `language` | Accepted for OpenAI compatibility. |
| `prompt` | Accepted for OpenAI compatibility. |

The proxy can also accept JSON with raw base64 audio for clients that cannot send multipart form data:

```bash
AUDIO_BASE64="$(base64 < recording.webm | tr -d '\n')"

curl http://127.0.0.1:8080/v1/audio/transcriptions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"whisper-1\",
    \"audioBase64\": \"${AUDIO_BASE64}\",
    \"audioFormat\": \"webm\"
  }"
```

Do not include a data URL prefix in `audioBase64`; send only the raw base64 audio bytes.

### Models

```
GET /v1/models
GET /models
```

Response:

```json
{
  "object": "list",
  "data": [
    {
      "id": "auto",
      "object": "model",
      "created": 1677858242,
      "owned_by": "grok"
    },
    {
      "id": "fast",
      "object": "model",
      "created": 1677858242,
      "owned_by": "grok"
    },
    {
      "id": "expert",
      "object": "model",
      "created": 1677858242,
      "owned_by": "grok"
    },
    {
      "id": "grok-420-computer-use-sa",
      "object": "model",
      "created": 1677858242,
      "owned_by": "grok"
    },
    {
      "id": "heavy",
      "object": "model",
      "created": 1677858242,
      "owned_by": "grok"
    }
  ]
}
```

## Configuration

### Grok Credentials

The application will try to find Grok credentials in the following order:

1. `GROK_COOKIES` environment variable (JSON string)
2. `credentials.json` file in the process current working directory (JSON object)
3. Fallback to mock cookies (which will likely fail with the actual API)

Both runtime credential sources must decode to a non-empty JSON object with string keys and string values. The proxy does not search the CLI config directory and does not run the CLI import or cookie-extractor validators at startup.

Generated browser credentials normally include the cookies Grok expects for a logged-in web session, such as `sso`, `sso-rw`, `x-anonuserid`, `x-challenge`, and `x-signature`. If you generate credentials with the CLI, use the saved JSON file itself by copying it to the proxy working directory as `credentials.json` or by passing its contents through `GROK_COOKIES`.

Example `credentials.json` file:

```json
{
  "x-anonuserid": "your-anon-user-id",
  "x-challenge": "your-challenge-token",
  "x-signature": "your-signature",
  "sso": "your-sso-token",
  "sso-rw": "your-sso-rw-token"
}
```

### Application Settings

| Option | Environment Variable | Command Line Flag | Description |
|--------|---------------------|-------------------|-------------|
| Verbose Logging | `VERBOSE=true` | `--verbose` | Enables detailed logging of requests and responses |

## Parameter Mapping

- **temperature**: Accepted for OpenAI compatibility but not mapped; reasoning is always enabled by Grok web modes since the Grok 4 release on 2025-07-09
- **system message**: Accepted for OpenAI compatibility but not forwarded as custom instructions; configure instructions in Grok agent settings
- **audio transcription model**: Accepted for OpenAI compatibility but Grok performs the transcription
- Other parameters (max_tokens, etc.) are currently ignored

## Limitations

- Each request creates a new conversation in Grok (no context persistence)
- Token usage metrics are not accurately reported
- Limited parameter mapping to Grok's API

## License

This project is licensed under the MIT License - see the LICENSE file for details.
