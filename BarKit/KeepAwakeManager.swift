import Foundation

final class KeepAwakeManager {
    private var activity: NSObjectProtocol?
    private var expirationTimer: Timer?

    private(set) var endDate: Date?
    private(set) var selectedDuration: TimeInterval?
    var onStateChange: (() -> Void)?

    var isActive: Bool { activity != nil }

    /// A nil duration keeps the Mac awake until the user turns this off or BarKit quits.
    func start(duration: TimeInterval?) {
        stop()

        activity = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled,
            reason: "BarKit Keep Mac Awake"
        )
        selectedDuration = duration

        if let duration {
            endDate = Date().addingTimeInterval(duration)
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                self?.stop()
            }
            expirationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        onStateChange?()
    }

    func stop() {
        expirationTimer?.invalidate()
        expirationTimer = nil
        endDate = nil
        selectedDuration = nil

        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
        onStateChange?()
    }

    deinit {
        expirationTimer?.invalidate()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
}
