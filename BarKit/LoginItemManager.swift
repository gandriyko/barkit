import Foundation
import OSLog
import ServiceManagement

final class LoginItemManager {
    enum Status {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    private let service = SMAppService.mainApp
    private let logger = Logger(subsystem: "com.barkit.app", category: "LoginItem")

    var status: Status {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return true
        } catch {
            logger.error("Failed to update Launch at Login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
