# SwiftGrok

A Swift client for interacting with the Grok AI API. This implementation matches the functionality of the Python client, including streaming responses, reasoning mode, and deep search capabilities.

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

### Basic Usage

```swift
import GrokClient

// Initialize the client with your cookies from browser
let cookies = [
    "x-anonuserid": "your_anon_user_id",
    "x-challenge": "your_challenge_value",
    "x-signature": "your_signature_value",
    "sso": "your_sso_cookie",
    "sso-rw": "your_sso_rw_cookie"
]

do {
    let client = try GrokClient(cookies: cookies)
    
    // Send a message and get the response
    let response = try await client.sendMessage(message: "Hello Grok!")
    print(response)
} catch {
    print("Error: \(error)")
}
```

### Using Reasoning Mode

Reasoning mode enables Grok to show its step-by-step thinking process.

```swift
let response = try await client.sendMessage(
    message: "Solve this math problem: If a train travels at 60 mph, how long will it take to travel 240 miles?",
    enableReasoning: true
)
```

### Using Deep Search

Deep search provides more comprehensive results by performing more extensive research.

```swift
let response = try await client.sendMessage(
    message: "What are the latest advancements in quantum computing?",
    enableDeepSearch: true
)
```

## Cookie Authentication

The GrokClient requires cookies from a logged-in browser session to authenticate with Grok's API. This package includes a cookie extraction script to help automate this process.

### Using the Cookie Extractor

The `cookie_extractor.py` script automatically extracts the necessary cookies from your Chrome or Firefox browser.

#### Prerequisites:
1. Python 3 installed
2. Install the required package: `pip install browsercookie`

#### Running the Extractor:

```bash
# Basic usage (extracts all grok.com cookies)
python cookie_extractor.py

# Check for the required GrokClient cookies
python cookie_extractor.py --required

# Save as JSON
python cookie_extractor.py --format json --output grok_cookies.json

# Output both Swift and JSON formats
python cookie_extractor.py --format both
```

The script will:
1. Extract cookies from Chrome and/or Firefox for grok.com
2. Generate a Swift file named `GrokCookies.swift` with the cookies
3. Print the cookies in Swift dictionary format and/or JSON

### Using the Extracted Cookies

#### Option 1: With the Generated Swift File

1. Add `GrokCookies.swift` to your Swift project
2. Initialize the client with:

```swift
import GrokClient

do {
    let client = try GrokClient.withAutoCookies()
    // Use the client...
    let response = try await client.sendMessage(message: "Hello Grok!")
    print(response)
} catch {
    print("Error: \(error)")
}
```

#### Option 2: From JSON

```swift
import GrokClient

do {
    let client = try GrokClient.fromJSONFile(at: "/path/to/grok_cookies.json")
    // Use the client...
} catch {
    print("Error: \(error)")
}
```

#### Option 3: Direct Initialization

```swift
import GrokClient

let cookies = [
    "x-anonuserid": "your-value-here",
    "x-challenge": "your-value-here",
    "x-signature": "your-value-here",
    "sso": "your-value-here",
    "sso-rw": "your-value-here"
]

do {
    let client = try GrokClient(cookies: cookies)
    // Use the client...
} catch {
    print("Error: \(error)")
}
```

### Required Cookies

The GrokClient needs the following cookies:
- `x-anonuserid`
- `x-challenge`
- `x-signature`
- `sso`
- `sso-rw`

To get these cookies, you need to log in to [grok.com](https://grok.com) in your browser before running the extractor.

## Using the GrokClient

Once initialized with cookies, you can use the client to interact with Grok:

```swift
// Send a message and get a response
let response = try await client.sendMessage(message: "What's the capital of France?")
print(response)

// Use reasoning mode
let reasoningResponse = try await client.sendMessage(
    message: "Solve this step by step: If x+y=10 and x-y=4, what is x*y?", 
    enableReasoning: true
)
print(reasoningResponse)

// Use deep search
let deepSearchResponse = try await client.sendMessage(
    message: "What are the latest advancements in quantum computing?", 
    enableDeepSearch: true
)
print(deepSearchResponse)
```

## Troubleshooting

- **No Cookies Found**: Make sure you're logged in to [grok.com](https://grok.com) in Chrome or Firefox.
- **Missing Required Cookies**: Try logging out and logging back in to refresh your session.
- **Authentication Errors**: Your cookies may have expired. Log in again and re-run the extractor.

## Requirements

- iOS 13.0+ / macOS 14.0+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+

## License

[MIT License](LICENSE) 