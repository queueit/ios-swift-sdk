import UIKit
import WebKit
import XCTest
@testable import QueueItKit

@MainActor
final class QueueItViewManagerMonitoringProxyTests: XCTestCase {
    private enum Ending {
        case passed
        case closed
        case released
    }

    private func verifyTeardown(mode: ProxyMode, ending: Ending, file: StaticString = #filePath, line: UInt = #line) async {
        let listener = MockListener()
        let webView = RecordingWebView()
        var manager: QueueItViewManager? = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: webView)
        manager!.showQueue(makeQueueResult(target: "https://example.com/target"))
        let shown = await waitUntil { manager!.showWebView }
        XCTAssertTrue(shown, file: file, line: line)
        webView.wrapDelegates(mode: mode)

        func askThroughProxy(_ url: String) -> Bool {
            var answered = false
            webView.navigationDelegate?.webView?(webView, decidePolicyFor: StubNavigationAction(url: url), preferences: WKWebpagePreferences()) { _, _ in answered = true }
            return answered
        }

        switch ending {
        case .passed:
            XCTAssertTrue(askThroughProxy("https://example.com/target?queueittoken=abc"), file: file, line: line)
        case .closed:
            XCTAssertTrue(askThroughProxy("queueit://close"), file: file, line: line)
        case .released:
            break
        }
        weak var released = manager
        manager = nil
        XCTAssertNil(released, file: file, line: line)

        for url in ["about:blank", "https://customer.queue-it.net/queue?c=c", "https://other.example.com/"] {
            XCTAssertTrue(askThroughProxy(url), "no answer for \(url)", file: file, line: line)
        }
        XCTAssertEqual(webView.loadedRequests.count, 1, file: file, line: line)
        XCTAssertEqual(webView.loadedHTML.count, 1, file: file, line: line)
    }

    func testGivenProxyPassingNilThrough_WhenQueuePassed_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .passNilThrough, ending: .passed)
    }

    func testGivenProxyPassingNilThrough_WhenQueueClosed_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .passNilThrough, ending: .closed)
    }

    func testGivenProxyPassingNilThrough_WhenManagerReleased_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .passNilThrough, ending: .released)
    }

    func testGivenProxyWrappingEverySet_WhenQueuePassed_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .wrapEverySet, ending: .passed)
    }

    func testGivenProxyWrappingEverySet_WhenQueueClosed_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .wrapEverySet, ending: .closed)
    }

    func testGivenProxyWrappingEverySet_WhenManagerReleased_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .wrapEverySet, ending: .released)
    }

    func testGivenProxyStayingInstalledOnNil_WhenQueuePassed_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .stayInstalledOnNil, ending: .passed)
    }

    func testGivenProxyStayingInstalledOnNil_WhenQueueClosed_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .stayInstalledOnNil, ending: .closed)
    }

    func testGivenProxyStayingInstalledOnNil_WhenManagerReleased_ThenDecisionsFindLiveTarget() async {
        await verifyTeardown(mode: .stayInstalledOnNil, ending: .released)
    }
}
