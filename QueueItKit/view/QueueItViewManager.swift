import Foundation
import WebKit
import SwiftUI
import Combine
import SafariServices
import UIKit

nonisolated(unsafe) private var sinkKey = 0
nonisolated(unsafe) private var ownerTokenKey = 0

private final class OwnerToken: Sendable {}

@MainActor
final class PageDialog {
    var alert: UIAlertController?
    private var defaultAnswer: (() -> Void)?

    init(defaultAnswer: @escaping () -> Void) {
        self.defaultAnswer = defaultAnswer
    }

    var isAnswered: Bool { defaultAnswer == nil }

    func answer(_ call: () -> Void) {
        guard defaultAnswer != nil else { return }
        defaultAnswer = nil
        alert = nil
        call()
    }

    func cancel() {
        guard let defaultAnswer else { return }
        alert?.dismiss(animated: false)
        answer(defaultAnswer)
    }
}

public class QueueItViewManager: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    private static let TAG = "QueueItViewManager"

    @Published public var isLoading: Bool = false
    @Published public var showWebView: Bool = false
    @Published public var currentWebViewUrl: URL?
    @Published public var webViewError: (QueueError, String)?

    public let webView: WKWebView
    private var uriOverrider: UriOverrider
    public weak var queueListener: QueueListener?
    private var options: QueueItEngineOptions
    private var currentQueueUrl: String?
    private var currentTargetUrl: String?
    private var userId: String?
    private var isTornDown = false
    private var pendingLoadToken: NSObject?
    private var exitReloadUrl: URL?
    private let ownerToken = OwnerToken()

    var pendingDialogs: [PageDialog] = []
    var isShowQueueCalled: Bool = false
    
    @MainActor
    init(queueListener: QueueListener?, options: QueueItEngineOptions, webView: WKWebView?, waitingRoomDomain: String? = nil, queuePathPrefix: String? = nil) {
        self.queueListener = queueListener
        self.options = options
        self.uriOverrider = UriOverrider(waitingRoomDomain: waitingRoomDomain, queuePathPrefix: queuePathPrefix)

        if let webView {
            self.webView = webView
        } else {
           
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences.preferredContentMode = .mobile

            self.webView = WKWebView(frame: .zero, configuration: config)
        }
        
        super.init()
        
        self.attach()

        self.setCustomUserAgent(options.webViewUserAgent)
    }

    deinit {
        let webView = self.webView
        let ownerToken = self.ownerToken
        let dialogs = self.pendingDialogs
        QueueItViewManager.runOnMainThread {
            QueueItViewManager.detach(webView: webView, ownerToken: ownerToken, dialogs: dialogs)
        }
    }

    private nonisolated static func runOnMainThread(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    }

    private func attach() {
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        objc_setAssociatedObject(self.webView, &ownerTokenKey, self.ownerToken, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func detach(webView: WKWebView, ownerToken: OwnerToken, dialogs: [PageDialog]) {
        dialogs.forEach { $0.cancel() }

        guard objc_getAssociatedObject(webView, &ownerTokenKey) as AnyObject? === ownerToken else { return }
        objc_setAssociatedObject(webView, &ownerTokenKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let sink: WebViewSink
        if let existing = objc_getAssociatedObject(webView, &sinkKey) as? WebViewSink {
            sink = existing
        } else {
            sink = WebViewSink()
            objc_setAssociatedObject(webView, &sinkKey, sink, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        webView.navigationDelegate = sink
        webView.uiDelegate = sink
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    private func setCustomUserAgent(_ customUA: String?) {
        let defaultWKUA = self.webView.value(forKey: "userAgent") as? String
        let constructedUA = customUA ?? UserAgentManager.getUserAgent(defaultUA: defaultWKUA)
        QueueItLogger.debug(QueueItViewManager.TAG, "Setting custom User Agent: \(constructedUA)")
        self.webView.customUserAgent = constructedUA
    }

    public func showQueue(_ queueTryPassResult: QueueTryPassResult) {
        QueueItViewManager.runOnMainThread { [self] in
            isShowQueueCalled = true
            guard let queueUrl = queueTryPassResult.queueUrl else {
                QueueItLogger.error(QueueItViewManager.TAG, "Cannot show queue, Queue URL is missing.")
                self.queueListener?.onError(QueueError(.invalidResponse), errorMessage: "Missing Queue URL for display")
                return
            }

            let loadToken = NSObject()
            self.pendingLoadToken = loadToken
            self.currentQueueUrl = queueUrl
            self.currentTargetUrl = queueTryPassResult.targetUrl
            self.userId = UserIdManager.getUserId()

            if userId == nil {
                self.queueListener?.onError(QueueError(.deviceIDError), errorMessage: "Failed to retrieve device identifier (IDFV).")
                guard self.pendingLoadToken === loadToken else { return }
            }

            self.uriOverrider.setQueueUrl(self.currentQueueUrl)
            self.uriOverrider.setTargetUrl(self.currentTargetUrl)
            self.uriOverrider.setUserId(self.userId)

            QueueItLogger.debug(QueueItViewManager.TAG, "Preparing to show queue: \(self.currentQueueUrl ?? "nil")")
            self.queueListener?.onQueueViewWillOpen()

            let delay: Double = options.viewDelayMs > 0 ? Double(options.viewDelayMs)/1000 : 0

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.pendingLoadToken === loadToken else { return }
                self.pendingLoadToken = nil
                self.isTornDown = false
                self.attach()
                self.isLoading = true
                self.showWebView = true
                QueueItLogger.info(QueueItViewManager.TAG, "Loading Queue URL after delay: \(self.currentQueueUrl ?? "nil")")
                self.loadUrl()
            }
        }
    }

    public func loadUrl() {
        QueueItViewManager.runOnMainThread { [self] in
            guard !isTornDown else { return }
            guard let urlString = self.currentQueueUrl, let url = URL(string: urlString) else {
                QueueItLogger.error(QueueItViewManager.TAG, "Invalid URL for loading: \(self.currentQueueUrl ?? "nil")")
                self.queueListener?.onError(QueueError(.invalidResponse), errorMessage: "Invalid Queue URL for loading")
                self.isLoading = false
                self.showWebView = false
                return
            }

            self.webViewError = nil
            self.isLoading = true
            self.webView.load(QueueItViewManager.noCacheRequest(for: url))
        }
    }

    private static func noCacheRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-store", forHTTPHeaderField: "Pragma")
        return request
    }

    public func hideQueue() {
        QueueItLogger.debug(QueueItViewManager.TAG, "Hiding queue view")
        QueueItViewManager.runOnMainThread { [self] in
            self.isTornDown = true
            self.pendingLoadToken = nil
            let dialogs = self.pendingDialogs
            self.pendingDialogs = []
            QueueItViewManager.detach(webView: self.webView, ownerToken: self.ownerToken, dialogs: dialogs)

            self.isLoading = false
            self.showWebView = false
            self.currentQueueUrl = nil
            self.currentTargetUrl = nil
            self.currentWebViewUrl = nil
        }
    }

    public func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        if isMainFrame && navigationAction.request.url?.absoluteString == "about:blank" {
            return decisionHandler(.allow, preferences)
        }

        if isTornDown {
            return decisionHandler(.cancel, preferences)
        }

        guard let url = navigationAction.request.url else {
            QueueItLogger.warn(QueueItViewManager.TAG, "decidePolicyForNavigationAction called without URL.")
            return decisionHandler(.allow, preferences)
        }
        
        QueueItLogger.debug(QueueItViewManager.TAG, "handleUrlIntercept: \(url.absoluteString)")
        
        guard isMainFrame else {
            return decisionHandler(.allow, preferences)
        }
        
        let result = self.uriOverrider.handleNavigationRequest(url.absoluteString)

        let isExitLink = self.uriOverrider.isExitLink(url.absoluteString)
        if isExitLink {
            if url == self.exitReloadUrl {
                self.exitReloadUrl = nil
            } else {
                self.queueListener?.onUserExited()
            }
            if isTornDown {
                return decisionHandler(.cancel, preferences)
            }
        }

        switch result.action {
        case .loadInWebview:
            QueueItLogger.debug(QueueItViewManager.TAG, "LOAD_IN_WEBVIEW, Intercept: Allow load \(result.modifiedUrl ?? url.absoluteString)")
            self.queueListener?.onQueueUrlChanged(result.modifiedUrl ?? url.absoluteString)
            if let modifiedUrlString = result.modifiedUrl, let modifiedUrl = URL(string: modifiedUrlString), modifiedUrl != url {
                decisionHandler(.cancel, preferences)
                if !isTornDown {
                    self.exitReloadUrl = isExitLink ? modifiedUrl : nil
                    webView.load(QueueItViewManager.noCacheRequest(for: modifiedUrl))
                }
            } else {
                decisionHandler(isTornDown ? .cancel : .allow, preferences)
            }

        case .passed:
            QueueItLogger.info(QueueItViewManager.TAG, "Intercept: Queue Passed. Token: \(result.queueItToken ?? "nil")")
            decisionHandler(.cancel, preferences)
            self.hideQueue()
            let queuePassedInfo = QueuePassedInfo(queueItToken: result.queueItToken)
            self.queueListener?.onQueuePassed(queuePassedInfo)

        case .close:
            QueueItLogger.info(QueueItViewManager.TAG, "Intercept: Close requested.")
            decisionHandler(.cancel, preferences)
            self.hideQueue()
            self.queueListener?.onWebViewClosed()

        case .restartSession:
            QueueItLogger.info(QueueItViewManager.TAG, "Intercept: Session Restart requested.")
            decisionHandler(.cancel, preferences)
            self.hideQueue()
            self.queueListener?.onSessionRestart()

        case .openExternal:
            QueueItLogger.info(QueueItViewManager.TAG, "Intercept: Open external \(url.absoluteString)")
            decisionHandler(.cancel, preferences)
            self.tryOpenExternalUrl(url)

        case .block:
            QueueItLogger.debug(QueueItViewManager.TAG, "Intercept: Block load \(url.absoluteString)")
            decisionHandler(.cancel, preferences)

        case .`default`:
            QueueItLogger.debug(QueueItViewManager.TAG, "Intercept: Default load \(url.absoluteString)")
            decisionHandler(.allow, preferences)
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.currentWebViewUrl = webView.url
        self.isLoading = true
        QueueItLogger.debug(QueueItViewManager.TAG, "onPageBegin: \(webView.url?.absoluteString ?? "nil")")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isLoading = false
        QueueItLogger.debug(QueueItViewManager.TAG, "onPageEnd: \(webView.url?.absoluteString ?? "nil")")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.isLoading = false
        if QueueItViewManager.isCancelledLoad(error) {
            QueueItLogger.debug(QueueItViewManager.TAG, "didFail: ignore cancelled load")
            return
        }

        QueueItLogger.error(QueueItViewManager.TAG, "onErrorReceive: \(error.localizedDescription) URL: \(webView.url?.absoluteString ?? "N/A")")
        self.webViewError = (QueueError(.apiError), "Failed to load page: \(error.localizedDescription)")
        self.queueListener?.onError(QueueError(.apiError), errorMessage: "WebView failed to load: \(error.localizedDescription)")
       
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code == 102 {
            QueueItLogger.debug(QueueItViewManager.TAG, "didFailProvisionalNavigation: ignore error 102（NSURLErrorCancelled)")
            return
        }
        
        self.isLoading = false
        if QueueItViewManager.isCancelledLoad(error) {
            QueueItLogger.debug(QueueItViewManager.TAG, "didFailProvisionalNavigation: ignore cancelled load")
            return
        }

        QueueItLogger.error(QueueItViewManager.TAG, "didFailProvisionalNavigation: \(error.localizedDescription) URL: \(webView.url?.absoluteString ?? "N/A")")
       
        let queueError: QueueError = (error as NSError).code == NSURLErrorNotConnectedToInternet ? QueueError(.noConnection) : QueueError(.apiError)
        self.webViewError = (queueError, "Network or server error: \(error.localizedDescription)")
        self.queueListener?.onError(queueError, errorMessage: "WebView initial load failed: \(error.localizedDescription)")
    }

    private static func isCancelledLoad(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var error: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &error)

        if isTrusted {

            completionHandler(.performDefaultHandling, nil)
        } else {
           
            QueueItLogger.error(QueueItViewManager.TAG, "SSL Error detected: \(error?.localizedDescription ?? "Unknown error")")
            
            self.queueListener?.onSSLError("SSL Error detected: \(error?.localizedDescription ?? "Unknown error")")
            
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let dialog = PageDialog(defaultAnswer: { completionHandler() })
        let alert = UIAlertController(title: "", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
            dialog.answer { completionHandler() }
        })
        presentAlert(alert, dialog: dialog, from: webView)
    }

    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let dialog = PageDialog(defaultAnswer: { completionHandler(false) })
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
            dialog.answer { completionHandler(true) }
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { _ in
            dialog.answer { completionHandler(false) }
        })
        
        presentAlert(alert, dialog: dialog, from: webView)
    }

    public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let dialog = PageDialog(defaultAnswer: { completionHandler(nil) })
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.text = defaultText
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
            dialog.answer { completionHandler(alert.textFields?.first?.text) }
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { _ in
            dialog.answer { completionHandler(nil) }
        })
        
        presentAlert(alert, dialog: dialog, from: webView)
    }

    public func webView(_ webView: WKWebView, 
                       createWebViewWith configuration: WKWebViewConfiguration, 
                       for navigationAction: WKNavigationAction, 
                       windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        guard let url = navigationAction.request.url else {
            QueueItLogger.warn(QueueItViewManager.TAG, "createWebViewWith called without URL")
            return nil
        }
        
        QueueItLogger.info(QueueItViewManager.TAG, "Handling target='_blank' link: \(url.absoluteString)")
        
        let result = self.uriOverrider.handleNavigationRequest(url.absoluteString)
        
        if result.action == .openExternal {
            QueueItLogger.info(QueueItViewManager.TAG, "target='_blank' approved for external opening: \(url.absoluteString)")
            self.tryOpenExternalUrl(url)
        } else {
            QueueItLogger.warn(QueueItViewManager.TAG, "target='_blank' blocked, action was: \(result.action)")
        }
        return nil
    }
    
    private func presentAlert(_ alert: UIAlertController, dialog: PageDialog, from webView: WKWebView) {
        dialog.alert = alert
        guard let viewController = webView.findViewController(),
              viewController.presentedViewController == nil,
              viewController.viewIfLoaded?.window != nil else {
            dialog.cancel()
            return
        }
        pendingDialogs.removeAll { $0.isAnswered }
        pendingDialogs.append(dialog)
        viewController.present(alert, animated: true, completion: nil)
    }

    public func handleBackPress() {
        QueueItViewManager.runOnMainThread { [self] in
            if !self.showWebView {
                return
            }

            QueueItLogger.debug(QueueItViewManager.TAG, "WebView cannot go back, hiding queue view.")
            self.hideQueue()
            self.queueListener?.onWebViewClosed()
        }
    }

    private func tryOpenExternalUrl(_ url: URL) {
        QueueItLogger.warn(QueueItViewManager.TAG, "Attempting to open external URL: \(url.absoluteString)")
       
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    QueueItLogger.error(QueueItViewManager.TAG, "Failed to open external URL: \(url.absoluteString)")
                }
            }
        } else {
            QueueItLogger.error(QueueItViewManager.TAG, "Cannot open external URL: \(url.absoluteString)")
        }
    }
}

extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let vc = responder as? UIViewController {
                return vc
            }
            responder = responder?.next
        }
        return nil
    }
}
