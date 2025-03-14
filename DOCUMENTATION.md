# SwiftGrok Documentation

## Project Structure

The project follows the standard Swift Package Manager structure:

- `Sources/GrokClient/`: Contains the main source code
  - `GrokClient.swift`: Main client implementation with error handling, streaming, and data models
  - `Examples.swift`: Example code demonstrating various usage patterns
- `Tests/GrokClientTests/`: Contains test cases
  - `GrokClientTests.swift`: Basic unit tests for the client

### Key Components

1. **GrokError**: An enumeration of possible errors that can occur when using the client
2. **Response Models**: 
   - `StreamingResponse`: Internal model for handling streaming responses
   - `MessageResponse`: Represents a response from the Grok AI (for legacy API)
   - `Conversation`: Represents a conversation (for legacy API)
3. **GrokClient**: The main class for interacting with the API
   - `init(cookies:)`: Initialize with cookie authentication
   - `sendMessage(message:enableReasoning:enableDeepSearch:)`: Main method to send messages to Grok
   - Legacy methods for backward compatibility

## API Reference

### Initialization

```swift
// Initialize with required cookies
let cookies = [
    "x-anonuserid": "your_anon_user_id",
    "x-challenge": "your_challenge_value",
    "x-signature": "your_signature_value"
]
let client = try GrokClient(cookies: cookies)
```

### Main API Methods

#### Send Message

```swift
// Basic usage
let response = try await client.sendMessage(message: "Hello, Grok!")

// With reasoning mode enabled
let responseWithReasoning = try await client.sendMessage(
    message: "Explain quantum computing",
    enableReasoning: true
)

// With deep search enabled
let responseWithDeepSearch = try await client.sendMessage(
    message: "Latest research on LLMs",
    enableDeepSearch: true
)
```

### Legacy API Methods (For Backward Compatibility)

```swift
// Start a conversation (returns a placeholder in the new implementation)
let conversation = try await client.startNewConversation()

// Send a message to a specific conversation (uses the new API under the hood)
let response = try await client.sendMessage(
    conversationId: conversation.id, 
    message: "Hello!"
)
```

### Error Handling

The `GrokError` enum provides detailed error information:

```swift
do {
    let response = try await client.sendMessage(message: "Hello")
} catch GrokError.invalidCredentials {
    // Handle invalid credentials
} catch GrokError.unauthorized {
    // Handle unauthorized access
} catch GrokError.networkError(let error) {
    // Handle network errors
} catch {
    // Handle other errors
}
```

## Request Configuration

### Headers

The client automatically sets the following headers:
- Content-Type: application/json
- User-Agent: Matching a standard browser
- Origin, Referer, Accept headers
- And other browser-like headers

### Payload

The request payload includes:
- `modelName`: Set to "grok-3"
- Various configuration options for image generation, search, etc.
- `isReasoning`: Set based on the enableReasoning parameter
- `deepsearchPreset`: Set based on the enableDeepSearch parameter

## Extracting Cookies

To use this client, you need to extract cookies from your browser after logging into Grok:

1. Log in to https://grok.com
2. Open developer tools (F12)
3. Go to Application > Cookies (in Chrome)
4. Look for the following cookies:
   - x-anonuserid
   - x-challenge
   - x-signature
   - sso (optional)
   - sso-rw (optional)

You can use the included `extractCookiesFromString` function to parse cookie strings from the browser.

## Examples

See the `Examples.swift` file for complete usage examples, including:
- Basic usage
- Reasoning mode
- Deep search mode
- Multiple message sequences
- Cookie extraction

## Opening in Xcode

To open this package in Xcode:

1. Launch Xcode
2. Select "File" > "Open..."
3. Navigate to the root directory of this package (where Package.swift is located)
4. Click "Open"

Xcode will recognize the Swift Package and open it as a project. You can then build and run the package, edit files, and run tests.

Alternatively, you can open it from the command line:

```bash
xed .
```

## Building and Testing

From the command line:

```bash
# Build the package
swift build

# Run tests
swift test
```

## Usage Example

```swift
import GrokClient

// Initialize with credentials extracted from your browser
let credentials = ["cookie_name": "cookie_value"]

do {
    let client = try GrokClient(credentials: credentials)
    
    // Start a new conversation
    let conversation = try await client.startNewConversation()
    
    // Send a message
    let response = try await client.sendMessage(
        conversationId: conversation.id, 
        message: "Hello, Grok!"
    )
    
    print(response.message)
} catch {
    print("Error: \(error)")
}
```

## Extracting Cookies

To extract cookies from your browser:

1. Log in to Grok in your browser
2. Open developer tools (F12 or right-click > Inspect)
3. Go to the Application tab (Chrome) or Storage tab (Firefox)
4. Select Cookies in the left sidebar
5. Find cookies for grok.com
6. Extract the necessary name-value pairs

The `extractCookiesFromString` function in `Examples.swift` provides a utility for parsing cookie strings. 