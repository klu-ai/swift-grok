# GrokProxy: OpenAI-Compatible Proxy for Grok

This project implements an OpenAI-compatible reverse proxy server for Grok, allowing applications designed to work with OpenAI's Chat Completions API to use Grok instead.

## Features

- OpenAI-compatible API endpoints
- Conversion between OpenAI format and Grok format
- Support for system messages (as custom instructions for Grok)
- Mapping of temperature to reasoning mode
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
   - Creating a `credentials.json` file in the parent directory with Grok cookies
   - Required cookies: `x-anonuserid`, `x-challenge`, `x-signature`, `sso`, `sso-rw`
3. Build and run the application:

```bash
swift build
swift run
```

## Usage

The server exposes an OpenAI-compatible endpoint at:

```
POST /v1/chat/completions
```

Example request:

```json
{
  "model": "gpt-3.5-turbo",
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
  "model": "gpt-3.5-turbo",
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

## Configuration

The application will try to find Grok credentials in the following order:

1. `GROK_COOKIES` environment variable (JSON string)
2. `../credentials.json` file (JSON object)
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

## Parameter Mapping

- **temperature**: Values < 0.5 enable "reasoning mode" in Grok
- **system message**: Mapped to Grok's "customInstructions"
- Other parameters (max_tokens, etc.) are currently ignored

## Limitations

- Each request creates a new conversation in Grok (no context persistence)
- Token usage metrics are not accurately reported
- Limited parameter mapping to Grok's API

## License

This project is licensed under the MIT License - see the LICENSE file for details. 