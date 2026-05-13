# GrokProxy: OpenAI-Compatible Proxy for Grok

This project implements an OpenAI-compatible reverse proxy server for Grok, allowing applications designed to work with OpenAI's Chat Completions API to use Grok instead.

## Features

- OpenAI-compatible API endpoints
  - `/v1/chat/completions` - For generating chat responses
  - `/v1/models` - For listing available models
  - `/models` - Compatibility alias for model listing
- Conversion between OpenAI format and Grok format
- Mapping of temperature to reasoning mode
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
   - Setting a `GROK_COOKIES` environment variable with a JSON string of cookie key-values
   - Creating a `credentials.json` file in the current working directory with Grok cookies
   - Required cookies: `x-anonuserid`, `x-challenge`, `x-signature`, `sso`, `sso-rw`
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

- **temperature**: Values < 0.5 enable "reasoning mode" in Grok
- **system message**: Accepted for OpenAI compatibility but not forwarded as custom instructions; configure instructions in Grok agent settings
- Other parameters (max_tokens, etc.) are currently ignored

## Limitations

- Each request creates a new conversation in Grok (no context persistence)
- Token usage metrics are not accurately reported
- Limited parameter mapping to Grok's API

## License

This project is licensed under the MIT License - see the LICENSE file for details.
