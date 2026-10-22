import Foundation
import IOKit.ps

final class KeepAwakeManager {
    private let settings: Settings
    private var activity: NSObjectProtocol?
    private var expirationTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var wasOnPower = false

    private(set) var endDate: Date?
    private(set) var selectedDuration: TimeInterval?
    /// True when connecting the power adapter started this session, so disconnecting it ends the session.
    private(set) var isStartedByPower = false
    var onStateChange: (() -> Void)?

    var isActive: Bool { activity != nil }

    var keepsDisplayAwake: Bool {
        get { settings.keepDisplayAwake }
        set {
            settings.keepDisplayAwake = newValue
            restartActivity()
        }
    }

    var startsOnPower: Bool {
        get { settings.keepAwakeOnPower }
        set {
            settings.keepAwakeOnPower = newValue
            if newValue, wasOnPower, !isActive {
                start(duration: nil, byPower: true)
            } else if !newValue, isStartedByPower {
                stop()
            }
        }
    }

    init(settings: Settings) {
        self.settings = settings
        wasOnPower = Self.isOnPower

        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<KeepAwakeManager>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
        }, context)?.takeRetainedValue()
        if let powerSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }

        if settings.keepAwakeOnPower, wasOnPower {
            start(duration: nil, byPower: true)
        }
    }

    /// A nil duration keeps the Mac awake until the user turns this off or BarKit quits.
    func start(duration: TimeInterval?, byPower: Bool = false) {
        stop()

        activity = beginActivity()
        selectedDuration = duration
        isStartedByPower = byPower

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
        isStartedByPower = false

        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
        onStateChange?()
    }

    private func beginActivity() -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: settings.keepDisplayAwake ? [.idleSystemSleepDisabled, .idleDisplaySleepDisabled] : .idleSystemSleepDisabled,
            reason: "BarKit Keep Mac Awake"
        )
    }

    /// Swaps the running activity for one with the current display setting, keeping the timer as is.
    private func restartActivity() {
        guard let oldActivity = activity else { return }
        activity = beginActivity()
        ProcessInfo.processInfo.endActivity(oldActivity)
    }

    private func powerSourceChanged() {
        // The notification also fires on battery level changes, so react only to plugging in or out.
        let isOnPower = Self.isOnPower
        guard isOnPower != wasOnPower else { return }
        wasOnPower = isOnPower

        guard settings.keepAwakeOnPower else { return }
        if isOnPower, !isActive {
            start(duration: nil, byPower: true)
        } else if !isOnPower, isStartedByPower {
            stop()
        }
    }

    private static var isOnPower: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        return IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String == kIOPSACPowerValue
    }

    deinit {
        expirationTimer?.invalidate()
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
}
