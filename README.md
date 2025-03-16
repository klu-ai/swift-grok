# SwiftGrok

<img width="922" alt="image" src="https://github.com/user-attachments/assets/f4a72dfd-5c9f-480c-9ef4-c888631cae2f" />

SwiftGrok is a Swift package that provides a client for interacting with the Grok AI API developed by xAI. It includes both a programmatic API through `GrokClient` and a command-line interface (CLI) tool named `grok` for terminal-based interactions with Grok. The package supports features such as multi-turn conversations, reasoning mode, deep search capabilities, and custom instructions, making it suitable for developers building AI-driven applications or users seeking direct command-line access to Grok.

This README provides detailed instructions for installation, usage, and configuration, along with examples to help you get started. The package is designed to be extensible and integrates seamlessly into Swift projects via the Swift Package Manager.

## Package Description

SwiftGrok consists of three primary components:

1. **GrokClient**: A Swift library for programmatic interaction with the Grok API, offering methods to send messages, continue conversations, list past conversations, and retrieve detailed responses. It supports advanced features like reasoning mode, deep search, and custom instructions.
2. **GrokProxy**: An OpenAI-compatible proxy server that routes requests through the Grok API, enabling integration with tools expecting OpenAI's API format.
3. **Grok**: A command-line tool built on top of `GrokClient`, providing an interactive chat interface, one-off query execution, and conversation management directly from the terminal.

The package handles authentication via browser-extracted cookies, supports conversation threading for context preservation, and includes structured response models for handling text, web search results, and X posts.

## Dependencies

SwiftGrok relies on the following dependencies, which are included via the Swift Package Manager:

- **Rainbow**: A Swift library for adding color to terminal output, used in the CLI for enhanced readability. It is automatically included when building the CLI target.

No additional external dependencies are required beyond standard Swift and Foundation libraries. The package is compatible with Swift 6.0 and requires macOS 14.0 or later for CLI usage, with broader platform support (iOS 13.0+, tvOS 13.0+, watchOS 6.0+) for the `GrokClient` library.

## Installation

### Swift Package Manager

To integrate SwiftGrok into your Swift project, add it as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/klu-ai/swift-grok", from: "1.0.0")
]
```

Then, include it in your target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["GrokClient"]
    )
]
```

Run `swift build` to fetch and compile the package.

### CLI Installation

To install the `grok` CLI tool, use the provided installation script:

```bash
git clone https://github.com/klu-ai/swift-grok.git
cd swift-grok
./Scripts/install_cli.sh
```

The script will:
1. Attempt to extract Grok API cookies from your browser (requires Python 3 and the `browsercookie` package).
2. Build the CLI with embedded credentials.
3. Install the `grok` binary to your local bin directory (typically `/usr/local/bin`).

If you prefer to skip automatic cookie extraction, use:

```bash
./Scripts/install_cli.sh -s
```

You will then need to manually configure authentication (see "Authentication" section below).

#### Prerequisites for CLI Installation
- Python 3 (for cookie extraction)
- `pip install browsercookie` (for the cookie extractor script)
- Swift 6.0 toolchain

#### Proxy Installation
To install and run the GrokProxy server, which provides an OpenAI-compatible API endpoint for Grok, use the Docker setup detailed in [DOCKER.md](DOCKER.md). This requires Docker and valid Grok credentials, with options for local or container-based configuration. For additional details, including credential setup and customization, refer to the README in the `Sources/GrokProxy` folder.

## Usage

### Using GrokClient Programmatically

The `GrokClient` class provides a programmatic interface to the Grok API. Below are examples of common use cases.

#### Basic Message Sending

Initialize the client with authentication cookies and send a message:

```swift
import GrokClient

let cookies = [
    "x-anonuserid": "your_anon_user_id",
    "x-challenge": "your_challenge_value",
    "x-signature": "your_signature_value",
    "sso": "your_sso_cookie",
    "sso-rw": "your_sso_rw_cookie"
]

do {
    let client = try GrokClient(cookies: cookies)
    let response = try await client.sendMessage(message: "What is the capital of France?")
    print(response.message)
} catch {
    print("Error: \(error.localizedDescription)")
}
```

#### Multi-Turn Conversation

Continue a conversation by maintaining context:

```swift
import GrokClient

do {
    let client = try GrokClient(cookies: cookies)
    
    // Start a conversation
    let initialResponse = try await client.sendMessage(message: "Tell me about Swift programming")
    print("Grok: \(initialResponse.message)")
    
    // Continue the conversation
    let followUp = try await client.continueConversation(
        conversationId: initialResponse.conversationId,
        parentResponseId: initialResponse.responseId,
        message: "How does it compare to Objective-C?"
    )
    print("Grok: \(followUp.message)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

#### Using Reasoning Mode

Enable reasoning mode for step-by-step explanations:

```swift
let response = try await client.sendMessage(
    message: "Solve: If a train travels at 60 mph, how long to go 240 miles?",
    enableReasoning: true
)
print(response.message)
```

#### Using Deep Search

Enable deep search for comprehensive answers:

```swift
let response = try await client.sendMessage(
    message: "Latest advancements in quantum computing?",
    enableDeepSearch: true
)
print(response.message)
if let webResults = response.webSearchResults {
    print("Web Search Results:")
    for result in webResults {
        print("- \(result.title): \(result.url)")
    }
}
```

#### Listing Conversations

Retrieve past conversations:

```swift
let conversations = try await client.listConversations()
for conversation in conversations {
    print("\(conversation.title) (ID: \(conversation.conversationId))")
}
```

### Using GrokCLI

The `grok` CLI tool provides a terminal-based interface to Grok.

#### Interactive Chat

Start an interactive session:

```bash
grok
```

Or with an initial message:

```bash
grok "Hello, Grok!"
```

Available commands in the chat:
- `/new`: Start a new conversation thread
- `/list`: View and load past conversations
- `/reason`: Toggle reasoning mode
- `/search`: Toggle deep search
- `/realtime`: Toggle real-time data
- `/private`: Toggle private mode (conversations not saved)
- `/quit`: Exit the session

#### One-Off Query

Send a single query and exit:

```bash
grok message "What is the meaning of life?"
```

With options:

```bash
grok message --reasoning "Solve this math problem: Convert the point $(0,3)$ in rectangular coordinates to polar coordinates."
```

#### Managing Conversations

List and resume past conversations:

```bash
grok list
```

Follow the prompt to select a conversation by number and continue it with preserved context.

### Authentication

The Grok API requires cookies from a logged-in browser session. SwiftGrok provides tools to extract and configure these credentials.

#### Generating Credentials

Extract cookies from your browser (Chrome or Firefox):

```bash
grok auth generate
```

Ensure you are logged into [grok.com](https://grok.com) in your browser beforehand.

#### Importing Credentials

Import cookies from a JSON file:

```bash
grok auth import /path/to/grok_cookies.json
```

The JSON file should contain a dictionary with the required cookies: `x-anonuserid`, `x-challenge`, `x-signature`, `sso`, and `sso-rw`.

#### Manual Configuration

Alternatively, initialize `GrokClient` with cookies directly in code (see "Basic Message Sending" example above).

## Configuration

### Custom Instructions

For CLI usage, customize Grok's behavior with instructions:

```bash
grok /edit-instructions
```

Enter your instructions and save with Ctrl+D (Unix) or Ctrl+Z (Windows). Reset to defaults with:

```bash
grok /reset-instructions
```

In code, pass custom instructions to `sendMessage` or `continueConversation`:

```swift
let response = try await client.sendMessage(
    message: "Explain AI",
    customInstructions: "Provide a detailed technical explanation."
)
```

### Debugging

Enable debug output in the CLI:

```bash
grok --debug
```

Or in code:

```swift
let client = try GrokClient(cookies: cookies, isDebug: true)
```

## Troubleshooting

- **Authentication Errors**: Ensure cookies are valid and not expired. Re-run `grok auth generate` after logging into [grok.com](https://grok.com).
- **No Cookies Found**: Log into [grok.com](https://grok.com) in your browser before running the cookie extractor.
- **CLI Not Found**: Verify the installation path (`/usr/local/bin`) is in your `$PATH`.

## Requirements

- **GrokClient**: iOS 13.0+, macOS 14.0+, tvOS 13.0+, watchOS 6.0+
- **GrokCLI**: macOS 14.0+
- Swift 6.0+

## License

SwiftGrok is released under the MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please submit pull requests or open issues on the [GitHub repository](https://github.com/klu-ai/swift-grok).

## Project Structure

- **Sources/GrokClient/**: Core library with `GrokClient.swift` and supporting models.
- **Sources/GrokCLI/**: CLI implementation in `main.swift`.
- **Scripts/**: Installation and utility scripts, including `cookie_extractor.py`.
- **Tests/**: Unit tests for `GrokClient` functionality.

For further assistance, refer to the inline documentation in the source files or contact the maintainers via GitHub Issues.
