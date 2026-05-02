import Foundation
import os.log

final class Logger {
    static let shared = Logger()

    var level: LogLevel = .error

    private let osLog = OSLog(subsystem: "com.motisig.sdk", category: "MotiSig")

    private init() {}

    private func emit(_ tag: String, _ message: String) {
        if MotiSigTestBootstrap.skipPushPermissionAndRegistration {
            print("[MotiSig/\(tag)] \(message)")
        }
    }

    func debug(_ message: @autoclosure () -> String) {
        guard level >= .debug else { return }
        let msg = message()
        os_log(.debug, log: osLog, "%{public}@", msg)
        emit("DEBUG", msg)
    }

    func info(_ message: @autoclosure () -> String) {
        guard level >= .info else { return }
        let msg = message()
        os_log(.info, log: osLog, "%{public}@", msg)
        emit("INFO", msg)
    }

    func error(_ message: @autoclosure () -> String) {
        guard level >= .error else { return }
        let msg = message()
        os_log(.error, log: osLog, "%{public}@", msg)
        emit("ERROR", msg)
    }
}
