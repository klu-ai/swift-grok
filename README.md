# SwiftGrok

A Swift client for interacting with the Grok AI API.

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/swift-grok.git", from: "1.0.0"),
]
```

And then include it as a dependency in your target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["GrokClient"]),
]
```

## Usage

```swift
import GrokClient

// Initialize the client with your credentials
let credentials = ["cookieName": "cookieValue"] // Extract from browser
do {
    let client = try GrokClient(credentials: credentials)
    
    // Start a new conversation
    let conversation = try await client.startNewConversation()
    
    // Send a message
    let response = try await client.sendMessage(conversationId: conversation.id, message: "Hello!")
    print(response.message)
} catch {
    print("Error: \(error)")
}
```

## Cookie Authentication

Since the Grok API uses cookie-based authentication, you'll need to extract the relevant cookies from your browser after logging into the Grok website.

1. Log in to Grok in your browser
2. Open the developer tools (F12)
3. Go to the "Application" tab (Chrome) or "Storage" tab (Firefox)
4. Look for "Cookies" in the left sidebar
5. Find the cookies for the grok.com domain
6. Extract the name and value pairs needed for authentication

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift 5.5+

## License

[MIT License](LICENSE) 