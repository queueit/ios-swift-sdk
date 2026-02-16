import SwiftUI
import WebKit

struct QueueWebView: UIViewRepresentable {
    
    @ObservedObject var viewManager: QueueItViewManager
    
    public init(viewManager: QueueItViewManager) {
        self.viewManager = viewManager
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        return viewManager.webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
    }

}
