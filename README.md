# Queue-it iOS Swift SDK

Library for integrating Queue-it's virtual waiting room into an iOS app written in Swift.

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

### Using `Package.swift`:
If you're building a Swift package, add QueueItKit as a dependency:

```swift
dependencies: [
    .package(url: "https://github.com/queueit/ios-swift-sdk", from: "1.0.0")
]
```

Then add it to your target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["QueueItKit"]
    )
]
```

### Using XCFramework (Binary)

Download pre-compiled XCFramework binaries from [GitHub Releases](https://github.com/queueit/ios-swift-sdk/releases).

1. Download the latest `QueueItKit.xcframework.zip` from releases
2. Extract and drag `QueueItKit.xcframework` into your Xcode project
3. Select your target → General → Frameworks, Libraries, and Embedded Content
4. Ensure `QueueItKit.xcframework` is set to "Embed & Sign"

## How to use the library

As the App developer, you must manage the state (whether the user was previously queued up or not) inside the app's storage.

After you have received the `onQueuePassed` callback, the app must remember to keep the state, possibly with a date/time expiration. When the user wants to navigate to specific screens on the app which needs Queue-it protection, your code check this state/variable, and only call SDK methods in the case where the user did not previously queue up.

Please note that when the user clicks back to navigate back to a protected screen, the same check needs to be done.

### QueueListener

QueueListener is the primary callback interface used by QueueItKit to notify your app about key events during the queue lifecycle.

Your ViewModel, ViewController, or Coordinator should conform to this protocol to respond to queue state changes, errors, and WebView events.

#### Purpose
QueueListener enables your application to:

* Respond when the user successfully passes the queue
* Detect when the queue WebView is about to open
* Handle situations where the queue is disabled or unavailable
* Receive errors from the Queue‑it engine
* Optionally react to WebView closure, session restarts, URL changes, and SSL errors

#### Required Methods
* onQueuePassed(_:) - Called when the user has successfully passed the queue. Use this to retrieve and store the queueItToken.
* onQueueViewWillOpen() - Triggered just before the queue WebView opens.
* onQueueDisabled(_:) - Indicates that the queue is in 'disabled' state.
* onQueueItUnavailable() - Called when Queue‑it services cannot be reached.
* onError(_:errorMessage:) - Called when the SDK encounters errors (e.g., network issues or invalid configs).

#### Optional Methods
These include built‑in default empty implementations:

* onWebViewClosed() — Called when user closes WebView with close link (queueit://close)
* onSessionRestart() — Queue-it restarted the session
* onQueueUrlChanged(_ url:) — Useful for logging or analytics
* onSSLError(_ errorMessage:) — Called when the SDK encounters SSL issues inside WebView

### Initialize QueueItEngine

```swift
QueueItEngine(
    customerId: String,
    waitingRoomOrAliasId: String,
    queueListener: QueueItKit.QueueListener,
    themeName: String? = nil,
    language: String? = nil,
    options: QueueItKit.QueueItEngineOptions? = nil,
    webView: WKWebView? = nil,
    waitingRoomDomain: String? = nil,
    queuePathPrefix: String? = nil
)
```

#### QueueItEngine Parameters

| Parameter         | Required (Default value)             | Description                                                                                                                                                                                   |
| ----------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| customerId        | Yes                                  | Your customer ID                                                                                                                                                                              |
| waitingRoomOrAliasId    | Yes                                  | ID of the waiting room or alias                                                                                                                                                               |
| queueListener     | Yes                                  | Object implementing `QueueListener` to handle callbacks                                                                                                                                       |
| themeName        | No (Waiting Room's default theme)    | Custom Theme name to use for the waiting room. If omitted, the Waiting Room's default theme will be used                                                                                           |
| language          | No (Waiting Room's default language) | Language ID to use for the waiting room. If omitted, the Waiting Room's default language will be used                                                                                         |
| options           | No (default options)                 | Configuration for `QueueItEngineOptions`: `webViewUserAgent` (custom user agent string) and `viewDelayMs` (delay in milliseconds before showing WebView)                                      |
| webView           | No (SDK creates one)                 | Provide a custom `WKWebView` instance if you need advanced control                                                                                                                            |
| waitingRoomDomain | No (`{customerId}.queue-it.net`)     | Custom Waiting Room domain to use for the requests from Mobile to Queue-it. Can be a Proxy Domain, if you are running Queue-it Behind Proxy                                                   |
| queuePathPrefix   | No (none)                            | Queue Path Prefix to use, if you are running Waiting Room on same domain as your normal website. Requires `waitingRoomDomain` to also be provided. If not, then this parameter will be ignored |

#### Using Custom WKWebView
```swift
let webView = WKWebView()
engine = QueueItEngine(
    customerId: customerId, 
    waitingRoomOrAliasId: waitingRoomOrAliasId, 
    queueListener: self, 
    webView: webView
)
```

#### Use options to set custom user agent and webView delay.
```swift
var options = QueueItEngineOptions()
options.webViewUserAgent = "CustomUserAgent/1.0"
options.viewDelayMs = 1000

QueueItEngine(
    customerId: customerId, 
    waitingRoomOrAliasId: waitingRoomOrAliasId, 
    queueListener: queueListener, 
    options: options
)
```

#### Example of building an engine (SwiftUI)
```swift
class MyAppViewModel: ObservableObject, QueueListener {
    private var engine: QueueItEngine?
    @Published var manager: QueueItViewManager?

    @Published var showWebView: Bool = false

    private var cancellables = Set<AnyCancellable>()

    @MainActor private func createEngine() {            
        engine = QueueItEngine(customerId: customerId, waitingRoomOrAliasId: waitingRoomOrAliasId, queueListener: self, themeName: themeName, language: language)
        manager = engine?.viewManager
        
        cancellables.removeAll()
        manager?.$showWebView
            .receive(on: RunLoop.main)
            .assign(to: \.showWebView, on: self)
            .store(in: &cancellables)
    }

    func onQueuePassed(info: QueuePassedInfo) {
        let token = queuePassedInfo.queueItToken
        manager?.hideQueue()
    }

    func onQueueViewWillOpen() { /* Show loading indicator */ }
    func onQueueDisabled(info: QueueDisabledInfo) { /* Handle queue disabled */ }
    func onQueueItUnavailable() { /* Handle queue service unavailable */ }
    func onError(error: QueueError, errorMessage: String) { /* Handle queue errors */ }
    func onWebViewClosed() { /* User closed queue UI */ }
}
```

#### Example of building an engine (UIKit)
```swift
class MyAppViewModel: ObservableObject, QueueListener {

    var engine: QueueItEngine?
    var manager: QueueItViewManager?
    var delegate: WebViewControlDelegate?
    
    private var cancellables = Set<AnyCancellable>()
    
    @MainActor private func createEngine() {
        engine = QueueItEngine(customerId: customerId, waitingRoomOrAliasId: waitingRoomOrAliasId, queueListener: self, themeName: themeName, language: language)
        manager = engine?.viewManager
        
        cancellables.removeAll()
        manager?.$showWebView
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                if newValue {
                    self?.delegate?.presentWebView()
                } else {
                    self?.delegate?.dismissWebView()
                }
            }
            .store(in: &cancellables)
    }
    
    func onQueuePassed(info: QueuePassedInfo) {
        let token = queuePassedInfo.queueItToken
        manager?.hideQueue()
    }

    func onQueueViewWillOpen() { /* Show loading indicator */ }
    func onQueueDisabled(info: QueueDisabledInfo) { /* Handle queue disabled */ }
    func onQueueItUnavailable() { /* Handle queue service unavailable */ }
    func onError(error: QueueError, errorMessage: String) { /* Handle queue errors */ }
    func onWebViewClosed() { /* User closed queue UI */ }
}
```

### Usage Overview: Separating run(), tryPass(), and showQueue()

*   run(): Starts the normal queue flow immediately.
*   tryPass(): Asks Queue‑it to get status of a waiting room it returns a QueueTryPassResult that you can decide on. If there is no queue situation a queueItToken will be return.
*   showQueue(): If the latest tryPass() result indicates .queue as redirectType, call showQueue() to present the WebView/UI for the waiting room.

#### run()
```swift
@MainActor func run() {
    createEngine()
    Task {
        if enqueueToken != "" {
            await engine?.runWithEnqueueToken(enqueueToken)
        } else if enqueueKey != "" {
            await engine?.runWithEnqueueKey(enqueueKey)
        } else {
            await engine?.run()
        }
    }
}
```

#### tryPass()
```swift
@MainActor func tryPass() {
    createEngine()
    Task {
        if enqueueToken != "" {
            tryPassResult = await engine?.tryPass(enqueueToken: enqueueToken)
        } else if enqueueKey != "" {
            tryPassResult = await engine?.tryPass(enqueueKey: enqueueKey)
        } else {
            tryPassResult = await engine?.tryPass()
        }
    }
}
```

#### showQueue()
```swift
@MainActor func showQueue() {
    if let tryPassResult, tryPassResult.redirectType == .queue {
        engine?.showQueue(queueTryPassResult: tryPassResult)
        self.tryPassResult = nil
    }
}
```

>   This separation gives you explicit control: run the queue now, or pre-check using tryPass() and only show the UI when actually needed.

### Debugging with QueueItLogger

QueueItLogger provides logging capabilities to help you debug integration issues.

#### Enable Debug Logging
```swift
QueueItLogger.setLogLevel(.debug)
```

Available log levels:

* debug
* info
* warn
* error
* fatal

Use .debug during development to see detailed logs about the behavior.

## Queue-it Behind Your CDN (Bring Your Own CDN)

If you are running Queue-it behind your own reverse proxy or CDN, the Mobile Integration can also be setup to run behind your proxy.

To do this, simply use your Proxy Domain as the `waitingRoomDomain` parameter when creating the `QueueItEngine`. If you are running the Queue-it Waiting Room on the same domain as your normal website, you should also provide the `queuePathPrefix` parameter.

### Example with Custom Domain

```swift
engine = QueueItEngine(
    customerId: "yourCustomerId",
    waitingRoomOrAliasId: "yourWaitingRoomId",
    queueListener: self,
    waitingRoomDomain: "queue.yourdomain.com"
)
```

### Example with Custom Domain and Path Prefix

If your waiting room is hosted at `https://yourdomain.com/queue/...`:

```swift
engine = QueueItEngine(
    customerId: "yourCustomerId",
    waitingRoomOrAliasId: "yourWaitingRoomId",
    queueListener: self,
    waitingRoomDomain: "yourdomain.com",
    queuePathPrefix: "queue"
)
```

> **Note:** The `queuePathPrefix` parameter requires `waitingRoomDomain` to also be provided. If `waitingRoomDomain` is not set, the `queuePathPrefix` parameter will be ignored.

## Initialize and Integrate (SwiftUI)

1.  The core logic for interacting with Queue-it is typically handled by a `ViewModel`.

    ```swift
    import SwiftUI
    import QueueItKit

    class MyAppViewModel: ObservableObject, QueueListener {
        private var engine: QueueItEngine?
        @Published var manager: QueueItViewManager?

        @Published var showWebView: Bool = false // Controls SwiftUI WKWebView presentation

        private var cancellables = Set<AnyCancellable>()

        init() {
           QueueItLogger.setLogLevel(.debug)
        }

        @MainActor private func createEngine() {            
            engine = QueueItEngine(customerId: customerId, waitingRoomOrAliasId: waitingRoomOrAliasId, queueListener: self, themeName: themeName, language: language)
            manager = engine?.viewManager
            
            cancellables.removeAll()
            manager?.$showWebView
                .receive(on: RunLoop.main)
                .assign(to: \.showWebView, on: self)
                .store(in: &cancellables)
        }
        
        @MainActor func run() {
            createEngine()
            Task {
                if enqueueToken != "" {
                    await engine?.runWithEnqueueToken(enqueueToken)
                } else if enqueueKey != "" {
                    await engine?.runWithEnqueueKey(enqueueKey)
                } else {
                    await engine?.run()
                }
            }
        }
        
        @MainActor func tryPass() {
            createEngine()
            Task {
                if enqueueToken != "" {
                    tryPassResult = await engine?.tryPass(enqueueToken: enqueueToken)
                } else if enqueueKey != "" {
                    tryPassResult = await engine?.tryPass(enqueueKey: enqueueKey)
                } else {
                    tryPassResult = await engine?.tryPass()
                }
            }
        }
        
        @MainActor func showQueue() {
            if let tryPassResult, tryPassResult.redirectType == .queue {
                engine?.showQueue(queueTryPassResult: tryPassResult)
                self.tryPassResult = nil
            }
        }

        // MARK: - QueueListener Conformance
        func onQueuePassed(info: QueuePassedInfo) {
            let token = queuePassedInfo.queueItToken
            manager?.hideQueue()
        }

        func onQueueViewWillOpen() { /* Show loading indicator */ }
        func onQueueDisabled(info: QueueDisabledInfo) { /* Handle queue disabled */ }
        func onQueueItUnavailable() { /* Handle queue service unavailable */ }
        func onError(error: QueueError, errorMessage: String) { /* Handle queue errors */ }
        func onWebViewClosed() { /* User closed queue UI */ }
    }
    ```

    `showWebView` is used to notify UI updates
    ```swift
    manager?.$showWebView
        .receive(on: RunLoop.main)
        .assign(to: \.showWebView, on: self)
        .store(in: &cancellables)
    ```

2. Integrate with your SwiftUI View
    ```swift
    import SwiftUI
    import WebKit
    import QueueItKit

    struct MyAppView: View {
        
        @StateObject private var viewModel = MyAppViewModel()

        var body: some View {
            ScrollView {
                if #available(iOS 16.0, *) {
                    content
                        .fullScreenCover(isPresented: $viewModel.showWebView) {
                            if let manager = viewModel.manager {
                                QueueWebViewContainer(viewManager: manager)
                            }
                        }
                } else {
                    content
                        .fullScreenCover(isPresented: $viewModel.showWebView) {
                            if let manager = viewModel.manager {
                                QueueWebViewContainer(viewManager: manager)
                            }
                        }
                }
            }
            .padding()
        }
        
        private var content: some View {
            VStack(spacing: 20) {
                Button("Run") {
                    viewModel.run()
                }
                
                Button("Run(TryPass)") {
                    viewModel.tryPass()
                }

                Button("Show Queue(After TryPass)") {
                    viewModel.showQueue()
                }
            }
        }
    }
    ```

    `QueueWebView` is the SwiftUI view wraps the WKWebView. The color of the loading page can be configured during initialization.
    ```swift
    QueueWebViewContainer(viewManager: manager, progressBackgroundColor: Color, progressColor: Color)
    ```

## Initialize and Integrate (UIKit)

1.  The core logic for interacting with Queue-it is typically handled by a `ViewModel`.

    ```swift
    class MyAppViewModel: ObservableObject, QueueListener {

        var engine: QueueItEngine?
        var manager: QueueItViewManager?
        var delegate: WebViewControlDelegate?
        
        private var cancellables = Set<AnyCancellable>()
        private var tryPassResult: QueueTryPassResult?
        
        init() {
            QueueItLogger.setLogLevel(.debug)
        }

        @MainActor private func createEngine() {
            
            engine = QueueItEngine(customerId: customerId, waitingRoomOrAliasId: waitingRoomOrAliasId, queueListener: self, themeName: themeName, language: language)
            manager = engine?.viewManager
            
            cancellables.removeAll()
            manager?.$showWebView
                .receive(on: RunLoop.main)
                .sink { [weak self] newValue in
                    if newValue {
                        self?.delegate?.presentWebView()
                    } else {
                        self?.delegate?.dismissWebView()
                    }
                }
                .store(in: &cancellables)
        }
        
        @MainActor func run() {
            createEngine()
            Task {
                if enqueueToken != "" {
                    await engine?.runWithEnqueueToken(enqueueToken)
                } else if enqueueKey != "" {
                    await engine?.runWithEnqueueKey(enqueueKey)
                } else {
                    await engine?.run()
                }
            }
        }
        
        @MainActor func tryPass() {
            createEngine()
            Task {
                if enqueueToken != "" {
                    tryPassResult = await engine?.tryPass(enqueueToken: enqueueToken)
                } else if enqueueKey != "" {
                    tryPassResult = await engine?.tryPass(enqueueKey: enqueueKey)
                } else {
                    tryPassResult = await engine?.tryPass()
                }
            }
        }
        
        @MainActor func showQueue() {
            if let tryPassResult, tryPassResult.redirectType == .queue {
                engine?.showQueue(queueTryPassResult: tryPassResult)
                self.tryPassResult = nil
            }
        }
        
        // MARK: - QueueListener Conformance
        func onQueuePassed(info: QueuePassedInfo) {
            let token = queuePassedInfo.queueItToken
            manager?.hideQueue()
        }

        func onQueueViewWillOpen() { /* Show loading indicator */ }
        func onQueueDisabled(info: QueueDisabledInfo) { /* Handle queue disabled */ }
        func onQueueItUnavailable() { /* Handle queue service unavailable */ }
        func onError(error: QueueError, errorMessage: String) { /* Handle queue errors */ }
        func onWebViewClosed() { /* User closed queue UI */ }
    }
    ```

    present or dismiss WKWebView via delegate when `showWebView` is changed.
    ```swift
    manager?.$showWebView
        .receive(on: RunLoop.main)
        .sink { [weak self] newValue in
            if newValue {
                self?.delegate?.presentWebView()
            } else {
                self?.delegate?.dismissWebView()
            }
        }
        .store(in: &cancellables)
    ```

2. Integrate with your ViewController

    ```swift
    import UIKit
    import Combine
    import WebKit
    import QueueItKit

    class MyAppView: UIViewController, WebViewControlDelegate {
        
        private var presentedWebVC: UIViewController?
        
        private let viewModel = ApiDemoViewModel()
        private var cancellables = Set<AnyCancellable>()
        
        override func viewDidLoad() {
            super.viewDidLoad()
            viewModel.delegate = self
        }
        
        @IBAction func run(_ sender: Any) {
            viewModel.run()
        }
        
        @IBAction func runTryPass(_ sender: Any) {
            viewModel.tryPass()
        }
        
        @IBAction func showQueue(_ sender: Any) {
            viewModel.showQueue()
        }
        
        func presentWebView() {
            guard presentedWebVC == nil, let manager = viewModel.manager else { return }
            let webVC = QueueWebViewController(viewManager: manager)
            webVC.modalPresentationStyle = .fullScreen
            presentedWebVC = webVC
            present(webVC, animated: true)
            
        }
        
        func dismissWebView() {
            guard let webVC = presentedWebVC else { return }
            webVC.dismiss(animated: true) {
                self.presentedWebVC = nil
            }
        }
    }
    ```

    `QueueWebViewController` is the ViewController view wraps the WKWebView. The color of the loading page can be configured during initialization.
    ```swift
    QueueWebViewController(viewManager: manager, progressBackgroundColor: UIColor, progressColor: UIColor)
    ```

## Using Queue-it server-side connector (KnownUser) to protect APIs, consumed by mobile app

If you are using Queue-it's server-side connector (KnownUser) to protect your API, you utilize this in your mobile app, to run a hybrid setup.

This greatly increases the protection and prevents visitors from bypassing the client-side Queue-it integration.

The flow in this setup is the following (simplified):
1. Mobile app calls API endpoints and includes the special Queue-it header
   Endpoint is protected by Queue-it connector
2. Queue-it connector has Trigger/Condition setup to match an Integration Action/Rule, with Queue action-type
3. Queue-it connector intercepts the requests to API and immediately responds with another special Queue-it header, containing information needed to show the Waiting Room
4. Mobile app shows the waiting room using the header from the Queue-it server-side connector

### Implementation

To integrate with a protected API we need to handle the validation responses that we may get in case the user should be queued.

All calls to protected APIs need to include the `x-queueit-ajaxpageurl` header with a non-empty value and a Queue-it accepted cookie (if present).
The integration can be described in the following steps:

1. API Request with `x-queueit-ajaxpageurl` *or* Queue-it accepted cookie is made
2. We get a response which may either be the API response or an intercepted response from the Queue-it connector
3. Scenario 1, user should not be queued (response does not have the `x-queueit-redirect` header)
    1. We store the Queue-it cookies from the response, to include in later API calls
4. Scenario 2, user should be queued
    1. If the user should be queued we'll get a `200 Ok` response with a `x-queueit-redirect` header. We need to extract the `c`(Customer ID) and `e` (Waiting Room ID) query string parameters from the `x-queueit-redirect` header and create a `QueueItEngine` with them, then call `run()`, just as you would normally do with the SDK
    2. We wait for the `onQueuePassed` callback and we store the QueueItToken passed to the callback
    3. We can repeat the API request, this time appending the `queueittoken={QueueItToken}` query string parameter, to prevent the server-side connector from intercepting the call again
    4. We store the Queue-it cookies from the final response, so they can be set in other API calls

### Client-side and server-side mobile integration (hybrid) with Queue-it Bring Your Own CDN

> Note: This only applies if you are using the Mobile SDK as a client-side protection *and* are using server-side protection using the Queue-it KnownUser Connector.

> If you are only using client-side protection, using the Mobile SDK, refer to the [How to use the library](#how-to-use-the-library) section above.

If you are running Queue-it behind your own reverse proxy the Mobile Integration can also be setup to run behind your proxy. For the hybrid setup, your KnownUser connector will also need to run in "Bring Your Own CDN" mode. Please contract Queue-it Support, for any questions the KnownUser Connector Bring Your Own CDN Setup.

#### Setup Mobile SDK with Bring Your Own CDN, with protected API

To do this simply use your Proxy Domain as the `waitingRoomDomain` parameter when creating the `QueueItEngine`, after getting the Queue-it intercepted response back from your API.

If you are running Queue-it Waiting Room on the same domain as your normal website, you also need to provide the `queuePathPrefix` parameter, to ensure your proxy can route the request to Queue-it origin.

This means in above [Implementation](#implementation) section, point 4.1, you must also provide `waitingRoomDomain` and optionally `queuePathPrefix` when creating the `QueueItEngine`, to serve the Waiting Room through your reverse proxy.

## License

MIT License - see LICENSE file for details

## Support

For support, please visit [Queue-it's support portal](https://support.queue-it.com/) or contact support@queue-it.com
