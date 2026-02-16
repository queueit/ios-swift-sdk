import Foundation

public protocol QueueListener: AnyObject {
    func onQueuePassed(_ queuePassedInfo: QueuePassedInfo)
    func onQueueViewWillOpen()
    func onQueueDisabled(_ queueDisabledInfo: QueueDisabledInfo)
    func onQueueItUnavailable()
    func onError(_ error: QueueError, errorMessage: String)

    func onWebViewClosed()
    func onSessionRestart()
    func onQueueUrlChanged(_ url: String)
    func onSSLError(_ errorMessage: String)
}

public extension QueueListener {
    func onWebViewClosed() {}
    func onSessionRestart() {}
    func onQueueUrlChanged(_ url: String) {}
    func onSSLError(_ errorMessage: String) {}
}
