import AppKit
import CoreAudio
import OSLog

final class StatusBarController: NSObject, NSMenuDelegate {
    private let audioManager: AudioManager
    private let displayManager: DisplayManager
    private let loginItemManager: LoginItemManager
    private let statusItem: NSStatusItem
    private let logger = Logger(subsystem: "com.barkit.app", category: "StatusBar")
    private let menu = NSMenu()
    private let pinItem = NSMenuItem(title: "Pin Input", action: #selector(togglePin), keyEquivalent: "")
    private let deviceItem = NSMenuItem(title: "Input Device", action: nil, keyEquivalent: "")
    private let deviceMenu = NSMenu(title: "Input Device")
    private let microphoneVolumeItem = NSMenuItem(title: "Microphone Volume", action: nil, keyEquivalent: "")
    private let microphoneVolumeMenu = NSMenu(title: "Microphone Volume")
    private let outputVolumeItem = NSMenuItem(title: "Output Volume", action: nil, keyEquivalent: "")
    private let outputVolumeMenu = NSMenu(title: "Output Volume")
    private let brightnessItem = NSMenuItem(title: "Display Brightness", action: nil, keyEquivalent: "")
    private let brightnessMenu = NSMenu(title: "Display Brightness")
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    private var state = AudioState(
        devices: [],
        defaultDeviceUID: nil,
        defaultOutputDevice: nil,
        pinEnabled: false,
        pinnedDeviceUID: nil,
        pinnedDeviceName: nil
    )
    private var displayState = DisplayState(displays: [])

    init(audioManager: AudioManager, displayManager: DisplayManager, loginItemManager: LoginItemManager) {
        self.audioManager = audioManager
        self.displayManager = displayManager
        self.loginItemManager = loginItemManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureMenu()
        if statusItem.button == nil {
            logger.error("Failed to create the BarKit status-bar button")
        } else {
            logger.notice("Created the BarKit status-bar button")
        }
        audioManager.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        displayManager.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    private func configureMenu() {
        let titleItem = NSMenuItem(title: "BarKit", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        pinItem.target = self
        menu.addItem(pinItem)

        deviceItem.submenu = deviceMenu
        menu.addItem(deviceItem)

        microphoneVolumeItem.submenu = microphoneVolumeMenu
        menu.addItem(microphoneVolumeItem)
        rebuildMicrophoneVolumeMenu()

        outputVolumeItem.submenu = outputVolumeMenu
        menu.addItem(outputVolumeItem)
        rebuildOutputVolumeMenu()

        brightnessItem.submenu = brightnessMenu
        menu.addItem(brightnessItem)
        rebuildBrightnessMenu()

        menu.addItem(.separator())

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit BarKit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon(pinEnabled: false)
        updateLaunchAtLoginItem()
    }

    private func apply(_ state: AudioState) {
        self.state = state
        pinItem.state = state.pinEnabled ? .on : .off
        updateStatusIcon(pinEnabled: state.pinEnabled)
        rebuildDeviceMenu(with: state.devices)
        rebuildMicrophoneVolumeMenu()
        rebuildOutputVolumeMenu()
    }

    private func apply(_ state: DisplayState) {
        displayState = state
        rebuildBrightnessMenu()
    }

    private func rebuildBrightnessMenu() {
        brightnessMenu.removeAllItems()

        if displayState.displays.isEmpty {
            let loadingItem = NSMenuItem(title: "Detecting Displays…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            brightnessMenu.addItem(loadingItem)
            return
        }

        for (index, display) in displayState.displays.enumerated() {
            let item = NSMenuItem()
            item.view = makeBrightnessView(for: display)
            brightnessMenu.addItem(item)
            if index < displayState.displays.count - 1 {
                brightnessMenu.addItem(.separator())
            }
        }
    }

    private func rebuildMicrophoneVolumeMenu() {
        microphoneVolumeMenu.removeAllItems()

        guard let device = state.devices.first(where: { $0.uid == state.defaultDeviceUID }) else {
            addUnavailableMicrophoneVolumeItem("No Input Device")
            return
        }
        guard let volume = device.inputVolume else {
            addUnavailableMicrophoneVolumeItem("Volume control unavailable")
            return
        }

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 58))
        let label = NSTextField(labelWithString: device.name)
        label.frame = NSRect(x: 14, y: 34, width: 242, height: 18)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = device.name
        view.addSubview(label)

        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone volume")
        icon.contentTintColor = .secondaryLabelColor
        view.addSubview(icon)

        let slider = MicrophoneVolumeSlider(
            value: volume,
            minValue: 0,
            maxValue: 1,
            target: self,
            action: #selector(changeMicrophoneVolume(_:))
        )
        slider.deviceID = device.id
        slider.isContinuous = true
        slider.frame = NSRect(x: 38, y: 1, width: 218, height: 28)
        view.addSubview(slider)

        let item = NSMenuItem()
        item.view = view
        microphoneVolumeMenu.addItem(item)
    }

    private func addUnavailableMicrophoneVolumeItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        microphoneVolumeMenu.addItem(item)
    }

    private func rebuildOutputVolumeMenu() {
        outputVolumeMenu.removeAllItems()

        guard let device = state.defaultOutputDevice else {
            addUnavailableOutputVolumeItem("No Output Device")
            return
        }
        guard let volume = device.volume else {
            addUnavailableOutputVolumeItem("Volume control unavailable")
            return
        }

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 58))
        let label = NSTextField(labelWithString: device.name)
        label.frame = NSRect(x: 14, y: 34, width: 242, height: 18)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = device.name
        view.addSubview(label)

        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Output volume")
        icon.contentTintColor = .secondaryLabelColor
        view.addSubview(icon)

        let slider = OutputVolumeSlider(
            value: volume,
            minValue: 0,
            maxValue: 1,
            target: self,
            action: #selector(changeOutputVolume(_:))
        )
        slider.deviceID = device.id
        slider.isContinuous = true
        slider.frame = NSRect(x: 38, y: 1, width: 218, height: 28)
        view.addSubview(slider)

        let item = NSMenuItem()
        item.view = view
        outputVolumeMenu.addItem(item)
    }

    private func addUnavailableOutputVolumeItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        outputVolumeMenu.addItem(item)
    }

    private func makeBrightnessView(for display: DisplayDevice) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: display.isSupported ? 58 : 38))
        let label = NSTextField(labelWithString: display.name)
        label.frame = NSRect(x: 14, y: display.isSupported ? 34 : 11, width: 242, height: 18)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = display.name
        view.addSubview(label)

        guard display.isSupported, let brightness = display.brightness else {
            let unsupported = NSTextField(labelWithString: "Brightness control unavailable")
            unsupported.textColor = .secondaryLabelColor
            unsupported.font = .systemFont(ofSize: 11)
            unsupported.frame = NSRect(x: 14, y: -2, width: 242, height: 16)
            view.frame.size.height = 54
            label.frame.origin.y = 28
            view.addSubview(unsupported)
            return view
        }

        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness")
        icon.contentTintColor = .secondaryLabelColor
        view.addSubview(icon)

        let slider = BrightnessSlider(value: brightness, minValue: 0, maxValue: 1, target: self, action: #selector(changeBrightness(_:)))
        slider.displayID = display.id
        slider.isContinuous = true
        slider.frame = NSRect(x: 38, y: 1, width: 218, height: 28)
        view.addSubview(slider)
        return view
    }

    private func rebuildDeviceMenu(with devices: [AudioDevice]) {
        deviceMenu.removeAllItems()

        if state.pinEnabled,
           let pinnedUID = state.pinnedDeviceUID,
           !devices.contains(where: { $0.uid == pinnedUID }) {
            let pinnedName = state.pinnedDeviceName ?? "Saved Input Device"
            let pinnedItem = NSMenuItem(
                title: "Pinned: \(pinnedName) — Unavailable",
                action: nil,
                keyEquivalent: ""
            )
            pinnedItem.isEnabled = false
            deviceMenu.addItem(pinnedItem)
            if !devices.isEmpty {
                deviceMenu.addItem(.separator())
            }
        }

        if devices.isEmpty {
            let unavailableItem = NSMenuItem(title: "No Input Devices", action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            deviceMenu.addItem(unavailableItem)
            return
        }

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == state.defaultDeviceUID ? .on : .off
            deviceMenu.addItem(item)
        }
    }

    private func updateStatusIcon(pinEnabled: Bool) {
        let symbolName = pinEnabled ? "mic.fill" : "mic.slash"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BarKit")
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)

        guard let button = statusItem.button else { return }
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.toolTip = pinEnabled ? "BarKit: Pin On" : "BarKit: Pin Off"
    }

    @objc private func togglePin() {
        audioManager.setPinEnabled(!state.pinEnabled)
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        audioManager.selectInputDevice(uid: uid)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginItem()
        audioManager.refresh()
        displayManager.refresh()
    }

    @objc private func changeBrightness(_ sender: BrightnessSlider) {
        displayManager.setBrightness(sender.doubleValue, for: sender.displayID)
    }

    @objc private func changeMicrophoneVolume(_ sender: MicrophoneVolumeSlider) {
        audioManager.setInputVolume(sender.doubleValue, for: sender.deviceID)
    }

    @objc private func changeOutputVolume(_ sender: OutputVolumeSlider) {
        audioManager.setOutputVolume(sender.doubleValue, for: sender.deviceID)
    }

    private func updateLaunchAtLoginItem() {
        switch loginItemManager.status {
        case .enabled:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .on
            launchAtLoginItem.isEnabled = true
        case .disabled:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = true
        case .requiresApproval:
            launchAtLoginItem.title = "Launch at Login — Approval Required"
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = true
        case .unavailable:
            launchAtLoginItem.title = "Launch at Login — Unavailable"
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = loginItemManager.status != .enabled
        _ = loginItemManager.setEnabled(shouldEnable)
        updateLaunchAtLoginItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class BrightnessSlider: NSSlider {
    var displayID: CGDirectDisplayID = 0
}

private final class MicrophoneVolumeSlider: NSSlider {
    var deviceID: AudioDeviceID = kAudioObjectUnknown
}

private final class OutputVolumeSlider: NSSlider {
    var deviceID: AudioDeviceID = kAudioObjectUnknown
}
