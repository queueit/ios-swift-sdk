import Foundation
import os

public enum LogLevel: Int, CaseIterable, CustomStringConvertible, Sendable {
    case debug = 0
    case info
    case warn
    case error
    case fatal

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }

    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        case .fatal: return .fault
        }
    }
}

actor LoggerState {
    private var logLevel: LogLevel = .warn

    func getLogLevel() -> LogLevel {
        return logLevel
    }

    func setLogLevel(_ level: LogLevel) {
        logLevel = level
    }
}

public final class QueueItLogger {
    private static let subsystem = "QueueItKit"
    private static let prefix = "[QueueItKit]"
    private static let state = LoggerState()

    private static func log(_ level: LogLevel, tag: String, message: String) {
        Task {
            let currentLevel = await state.getLogLevel()
            guard level.rawValue >= currentLevel.rawValue else { return }

            let fullMessage = "\(prefix)\(tag) \(message)"
            let log = OSLog(subsystem: subsystem, category: level.description)
            os_log("%{public}@", log: log, type: level.osLogType, fullMessage)
        }
    }

    // MARK: - Public Logging Methods

    static func debug(_ tag: String, _ message: String) {
        log(.debug, tag: tag, message: message)
    }

    static func info(_ tag: String, _ message: String) {
        log(.info, tag: tag, message: message)
    }

    static func warn(_ tag: String, _ message: String) {
        log(.warn, tag: tag, message: message)
    }

    static func error(_ tag: String, _ message: String) {
        log(.error, tag: tag, message: message)
    }

    static func fatal(_ tag: String, _ message: String) {
        log(.fatal, tag: tag, message: message)
    }

    public static func setLogLevel(_ level: LogLevel) {
        Task {
            await state.setLogLevel(level)
        }
    }
}
