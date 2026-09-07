import Foundation

final class Settings {
    private enum Key {
        static let pinEnabled = "pinEnabled"
        static let pinnedDeviceUID = "pinnedDeviceUID"
        static let pinnedDeviceName = "pinnedDeviceName"
        static let didMigrateInputPinSettings = "didMigrateInputPinSettings"
    }

    private static let legacyBundleIdentifier = "com.inputpin.app"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateInputPinSettingsIfNeeded()
    }

    private func migrateInputPinSettingsIfNeeded() {
        guard !defaults.bool(forKey: Key.didMigrateInputPinSettings) else { return }

        if let legacyDefaults = UserDefaults(suiteName: Self.legacyBundleIdentifier) {
            for key in [Key.pinEnabled, Key.pinnedDeviceUID, Key.pinnedDeviceName]
                where defaults.object(forKey: key) == nil {
                if let legacyValue = legacyDefaults.object(forKey: key) {
                    defaults.set(legacyValue, forKey: key)
                }
            }
        }

        defaults.set(true, forKey: Key.didMigrateInputPinSettings)
    }

    var pinEnabled: Bool {
        get { defaults.bool(forKey: Key.pinEnabled) }
        set { defaults.set(newValue, forKey: Key.pinEnabled) }
    }

    var pinnedDeviceUID: String? {
        get { defaults.string(forKey: Key.pinnedDeviceUID) }
        set { defaults.set(newValue, forKey: Key.pinnedDeviceUID) }
    }

    var pinnedDeviceName: String? {
        get { defaults.string(forKey: Key.pinnedDeviceName) }
        set { defaults.set(newValue, forKey: Key.pinnedDeviceName) }
    }
}
