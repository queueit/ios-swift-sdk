import Foundation
import Network
import Combine

actor NetworkState {
    private let isConnectedPublisher = CurrentValueSubject<Bool, Never>(false)
    private var startedMonitoring = false

    func getPublisher() -> CurrentValueSubject<Bool, Never> {
        return isConnectedPublisher
    }

    func updateConnectionStatus(_ isConnected: Bool) {
        isConnectedPublisher.send(isConnected)
    }

    func eraseConnectionStatus() -> AnyPublisher<Bool, Never> {
        return isConnectedPublisher.eraseToAnyPublisher()
    }

    func hasStartedMonitoring() -> Bool {
        return startedMonitoring
    }

    func markStarted() -> Bool {
        guard !startedMonitoring else { return false }
        startedMonitoring = true
        return true
    }
}

class NetworkUtils {
    private static let TAG = "NetworkUtils"
    private static let monitor = NWPathMonitor()
    private static let queue = DispatchQueue(label: "NetworkUtilsMonitor")
    static let networkState = NetworkState()

    static func startMonitoring() {
        Task {
            guard await networkState.markStarted() else { return }

            monitor.pathUpdateHandler = { path in
                let isOnline = path.status == .satisfied
                QueueItLogger.debug(TAG, "Network path updated. Status: \(path.status), Is Online: \(isOnline)")
                Task {
                    await networkState.updateConnectionStatus(isOnline)
                }
            }

            monitor.start(queue: queue)
            QueueItLogger.debug(TAG, "Started network monitoring.")
        }
    }

    static func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let currentPath = monitor.currentPath
                let isSatisfied = currentPath.status == .satisfied
                QueueItLogger.debug(TAG, "Synchronous isOnline check: \(isSatisfied)")
                continuation.resume(returning: isSatisfied)
            }
        }
    }
}
