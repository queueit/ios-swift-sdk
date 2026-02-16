import Foundation
import WebKit
import SwiftUI
import Combine
import SafariServices
import UIKit

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
    
    var isShowQueueCalled: Bool = false
    
    @MainActor
    init(queueListener: QueueListener?, options: QueueItEngineOptions, webView: WKWebView?) {
        self.queueListener = queueListener
        self.options = options
        self.uriOverrider = UriOverrider()

        if let webView {
            self.webView = webView
        } else {
           
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences.preferredContentMode = .mobile

            self.webView = WKWebView(frame: .zero, configuration: config)
        }
        
        super.init()
        
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        self.setCustomUserAgent(options.webViewUserAgent)
    }

    private func setCustomUserAgent(_ customUA: String?) {
        let defaultWKUA = self.webView.value(forKey: "userAgent") as? String
        let constructedUA = customUA ?? UserAgentManager.getUserAgent(defaultUA: defaultWKUA)
        QueueItLogger.debug(QueueItViewManager.TAG, "Setting custom User Agent: \(constructedUA)")
        self.webView.customUserAgent = constructedUA
    }

    public func showQueue(_ queueTryPassResult: QueueTryPassResult) {
        isShowQueueCalled = true
        guard let queueUrl = queueTryPassResult.queueUrl else {
            QueueItLogger.error(QueueItViewManager.TAG, "Cannot show queue, Queue URL is missing.")
            self.queueListener?.onError(QueueError(.invalidResponse), errorMessage: "Missing Queue URL for display")
            return
        }

        self.currentQueueUrl = queueUrl
        self.currentTargetUrl = queueTryPassResult.targetUrl
        self.userId = UserIdManager.getUserId()
        
        if userId == nil {
            self.queueListener?.onError(QueueError(.deviceIDError), errorMessage: "Failed to retrieve device identifier (IDFV).")
        }

        self.uriOverrider.setQueueUrl(self.currentQueueUrl)
        self.uriOverrider.setTargetUrl(self.currentTargetUrl)
        self.uriOverrider.setUserId(self.userId)

        QueueItLogger.debug(QueueItViewManager.TAG, "Preparing to show queue: \(self.currentQueueUrl ?? "nil")")
        self.queueListener?.onQueueViewWillOpen()

        let delay: Double = options.viewDelayMs > 0 ? Double(options.viewDelayMs)/1000 : 0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.isLoading = true
            self.showWebView = true
            QueueItLogger.info(QueueItViewManager.TAG, "Loading Queue URL after delay: \(self.currentQueueUrl ?? "nil")")
            self.loadUrl()
        }
    }

    public func loadUrl() {
        guard let urlString = self.currentQueueUrl, let url = URL(string: urlString) else {
            QueueItLogger.error(QueueItViewManager.TAG, "Invalid URL for loading: \(self.currentQueueUrl ?? "nil")")
            self.queueListener?.onError(QueueError(.invalidResponse), errorMessage: "Invalid Queue URL for loading")
            self.isLoading = false
            self.showWebView = false
            return
        }

        DispatchQueue.main.async {
            self.webViewError = nil
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-store", forHTTPHeaderField: "Pragma")
            self.isLoading = true
            self.webView.load(request)
        }
    }

    public func hideQueue() {
        QueueItLogger.debug(QueueItViewManager.TAG, "Hiding queue view")
        if self.showWebView {
            DispatchQueue.main.async {
                self.webView.stopLoading()
                self.webView.loadHTMLString("about:blank", baseURL: nil)
               
                self.isLoading = false
                self.showWebView = false
                self.currentQueueUrl = nil
                self.currentTargetUrl = nil
                self.currentWebViewUrl = nil
            }
        }
    }

    public func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        
        guard let url = navigationAction.request.url else {
            QueueItLogger.warn(QueueItViewManager.TAG, "decidePolicyForNavigationAction called without URL.")
            return decisionHandler(.allow, preferences)
        }
        
        QueueItLogger.debug(QueueItViewManager.TAG, "handleUrlIntercept: \(url.absoluteString)")
        
        guard navigationAction.targetFrame?.isMainFrame ?? false else {
            return decisionHandler(.allow, preferences)
        }
        
        let result = self.uriOverrider.handleNavigationRequest(url.absoluteString)

        switch result.action {
        case .loadInWebview:
            QueueItLogger.debug(QueueItViewManager.TAG, "LOAD_IN_WEBVIEW, Intercept: Allow load \(result.modifiedUrl ?? url.absoluteString)")
            self.queueListener?.onQueueUrlChanged(result.modifiedUrl ?? url.absoluteString)
            if let modifiedUrlString = result.modifiedUrl, let modifiedUrl = URL(string: modifiedUrlString), modifiedUrl != url {
                decisionHandler(.cancel, preferences)
                var request = URLRequest(url: modifiedUrl)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue("no-store", forHTTPHeaderField: "Pragma")
                webView.load(URLRequest(url: modifiedUrl))
            } else {
                decisionHandler(.allow, preferences)
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
        QueueItLogger.error(QueueItViewManager.TAG, "didFailProvisionalNavigation: \(error.localizedDescription) URL: \(webView.url?.absoluteString ?? "N/A")")
       
        let queueError: QueueError = (error as NSError).code == NSURLErrorNotConnectedToInternet ? QueueError(.noConnection) : QueueError(.apiError)
        self.webViewError = (queueError, "Network or server error: \(error.localizedDescription)")
        self.queueListener?.onError(queueError, errorMessage: "WebView initial load failed: \(error.localizedDescription)")
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
        let alert = UIAlertController(title: "", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
            completionHandler()
        })
        presentAlert(alert, from: webView)
    }

    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
            completionHandler(true)
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { _ in
            completionHandler(false)
        })
        
        presentAlert(alert, from: webView)
    }

    public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.text = defaultText
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { _ in
            completionHandler(nil)
        })
        
        presentAlert(alert, from: webView)
    }
    
    private func presentAlert(_ alert: UIAlertController, from webView: WKWebView) {
        if let viewController = webView.findViewController() {
            viewController.present(alert, animated: true, completion: nil)
        }
    }

    public func handleBackPress() {
        if !self.showWebView {
            return
        }

        QueueItLogger.debug(QueueItViewManager.TAG, "WebView cannot go back, hiding queue view.")
        self.hideQueue()
        self.queueListener?.onWebViewClosed()
        return
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
