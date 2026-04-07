# ``QueueItKit``

`QueueItKit` is a Swift library designed to integrate the Queue-it virtual waiting room system into your iOS applications. It provides the necessary components to detect Queue-it redirects, display the waiting room, and handle the tokens once the user passes the queue, ensuring a smooth user experience during high-demand events.

Before starting please download the whitepaper "Mobile App Integration" from GO Queue-it Platform. This whitepaper contains the needed information to perform a successful integration.

## Requirements

*   iOS 15.0+
*   Swift 5.0+
*   Xcode 13.0+

## Installation

### Using Swift Package Manager

In Xcode:

1. Open your project
2. Navigate to `File > Add Packages...`
3. Enter the repository URL:
   ```
   https://github.com/queueit/ios-swift-sdk
   ```
4. Select the version (e.g., `1.0.0`)
5. Click `Add Package`

Using `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/queueit/ios-swift-sdk", from: "1.0.1")
]
```

### Using XCFramework (Binary)

Download pre-compiled XCFramework binaries from [GitHub Releases](https://github.com/queueit/ios-swift-sdk/releases).

1. Download the latest `QueueItKit.xcframework.zip` from releases
2. Extract and drag `QueueItKit.xcframework` into your Xcode project
3. Select your target → General → Frameworks, Libraries, and Embedded Content
4. Ensure `QueueItKit.xcframework` is set to "Embed & Sign"

## Overview

As the App developer, you must manage the state (whether the user was previously queued up or not) inside the app's storage.

After you have received the `onQueuePassed` callback, the app must remember to keep the state, possibly with a date/time expiration. When the user wants to navigate to specific screens on the app which needs Queue-it protection, your code should check this state/variable, and only call SDK methods in the case where the user did not previously queue up.

Please note that when the user clicks back to navigate back to a protected screen, the same check needs to be done.


## Getting Started

### Queue Engine Initialization

To initialize the Queue-it engine, you need to provide:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `customerId` | Yes | Your Queue-it customer ID |
| `waitingRoomOrAliasId` | Yes | ID of the waiting room or alias |
| `queueListener` | Yes | Object implementing `QueueListener` to handle callbacks |

Optional parameters include `themeName`, `language`, `options`, `webView`, `waitingRoomDomain`, and `queuePathPrefix`.

### Usage Patterns

QueueItKit provides two main approaches:

- **`run()`** - Starts the queue flow immediately and shows the WebView if queuing is required
- **`tryPass()`** + **`showQueue()`** - Checks queue status first, then optionally shows the WebView based on the result

The `tryPass()` approach gives you more control over when to display the queue UI.

### Basic Example

```swift
class MyViewModel: ObservableObject, QueueListener {
    private var engine: QueueItEngine?
    @Published var manager: QueueItViewManager?
    
    @MainActor func initialize() {
        engine = QueueItEngine(
            customerId: "yourCustomerId",
            waitingRoomOrAliasId: "yourWaitingRoomId",
            queueListener: self
        )
        manager = engine?.viewManager
    }
    
    func onQueuePassed(info: QueuePassedInfo) {
        // Store token: info.queueItToken
        manager?.hideQueue()
    }
    
    func onQueueViewWillOpen() { }
    func onQueueDisabled(info: QueueDisabledInfo) { }
    func onQueueItUnavailable() { }
    func onError(error: QueueError, errorMessage: String) { }
}
```

### Debugging

Enable debug logging to troubleshoot integration issues:

```swift
QueueItLogger.setLogLevel(.debug)
```

Available log levels: `.debug`, `.info`, `.warn`, `.error`, `.fatal`

### Advanced Configuration

#### Queue-it Behind Your CDN

If running Queue-it behind your own CDN or reverse proxy, use the `waitingRoomDomain` parameter:

```swift
engine = QueueItEngine(
    customerId: "yourCustomerId",
    waitingRoomOrAliasId: "yourWaitingRoomId",
    queueListener: self,
    waitingRoomDomain: "queue.yourdomain.com"
)
```

If the waiting room is on the same domain as your website (e.g., `https://yourdomain.com/queue/...`), also provide `queuePathPrefix`:

```swift
engine = QueueItEngine(
    customerId: "yourCustomerId",
    waitingRoomOrAliasId: "yourWaitingRoomId",
    queueListener: self,
    waitingRoomDomain: "yourdomain.com",
    queuePathPrefix: "queue"
)
```

## Topics

### Essentials

- ``QueueItEngine``

The main engine that handles the queue logic and WebView presentation.

- ``QueueListener``

The primary callback interface used by QueueItKit to notify your app about key events during the queue lifecycle.

**Required Methods:**
- `onQueuePassed(_:)` - User successfully passed the queue (retrieve and store queueItToken)
- `onQueueViewWillOpen()` - Queue WebView is about to open
- `onQueueDisabled(_:)` - Queue is in disabled state
- `onQueueItUnavailable()` - Queue-it services cannot be reached
- `onError(_:errorMessage:)` - SDK encountered an error

**Optional Methods:**
- `onWebViewClosed()` - User closed WebView
- `onSessionRestart()` - Queue-it restarted the session
- `onQueueUrlChanged(_:)` - URL changed (useful for analytics)
- `onSSLError(_:)` - SSL issue detected

### Configuration

- ``QueueItEngineOptions``

Configuration options for customizing WebView behavior and user agent.

- ``QueueItViewManager``

Manages the presentation and dismissal of the queue WebView.

### Results and Info

- ``QueuePassedInfo``
- ``QueueDisabledInfo``
- ``QueueTryPassResult``
- ``QueueError``

Data structures containing information about queue states and results.

## See Also

- [GitHub Repository](https://github.com/queueit/ios-swift-sdk)
- [Queue-it Platform](https://queue-it.com)
