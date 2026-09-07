import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.barkit.app", category: "Application")
    private var audioManager: AudioManager?
    private var displayManager: DisplayManager?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("BarKit application did finish launching")
        NSApp.setActivationPolicy(.accessory)

        let manager = AudioManager(settings: Settings())
        let displays = DisplayManager()
        audioManager = manager
        displayManager = displays
        statusBarController = StatusBarController(
            audioManager: manager,
            displayManager: displays,
            loginItemManager: LoginItemManager()
        )
        manager.startMonitoring()
        displays.startMonitoring()
        logger.notice("BarKit monitoring started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.notice("BarKit application will terminate")
        audioManager?.stopMonitoring()
        displayManager?.stopMonitoring()
    }
}
