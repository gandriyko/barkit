import CoreAudio
import Foundation
import OSLog

final class AudioManager {
    typealias StateHandler = (AudioState) -> Void

    private let settings: Settings
    private let audioQueue = DispatchQueue(label: "com.barkit.app.audio")
    private let queueKey = DispatchSpecificKey<Void>()
    private let logger = Logger(subsystem: "com.barkit.app", category: "CoreAudio")

    private var defaultInputListener: AudioObjectPropertyListenerBlock!
    private var deviceListListener: AudioObjectPropertyListenerBlock!
    private var defaultListenerRegistered = false
    private var deviceListListenerRegistered = false

    var onStateChange: StateHandler?

    init(settings: Settings) {
        self.settings = settings
        audioQueue.setSpecific(key: queueKey, value: ())

        defaultInputListener = { [weak self] _, _ in
            self?.performOnAudioQueue {
                self?.refreshState(enforcePin: true)
            }
        }

        deviceListListener = { [weak self] _, _ in
            self?.performOnAudioQueue {
                self?.refreshState(enforcePin: true)
            }
        }
    }

    deinit {
        stopMonitoringSynchronously()
    }

    func getInputDevices() -> [AudioDevice] {
        performSynchronously { readInputDevices() }
    }

    func getDefaultInputDevice() -> AudioDevice? {
        performSynchronously {
            guard let defaultID = readDefaultInputDeviceID() else { return nil }
            return readInputDevices().first { $0.id == defaultID }
        }
    }

    @discardableResult
    func setDefaultInputDevice(_ device: AudioDevice) -> Bool {
        performSynchronously { writeDefaultInputDeviceID(device.id) }
    }

    func findDeviceByUID(_ uid: String) -> AudioDevice? {
        performSynchronously {
            readInputDevices().first { $0.uid == uid }
        }
    }

    func startMonitoring() {
        performOnAudioQueue { [weak self] in
            guard let self else { return }
            self.registerListenersIfNeeded()
            self.refreshState(enforcePin: true)
        }
    }

    func stopMonitoring() {
        performSynchronously {
            removeListenersIfNeeded()
        }
    }

    func selectInputDevice(uid: String) {
        performOnAudioQueue { [weak self] in
            guard let self else { return }
            let devices = self.readInputDevices()
            guard let device = devices.first(where: { $0.uid == uid }) else {
                self.logger.error("Selected input device is no longer available: \(uid, privacy: .public)")
                self.publishState(devices: devices)
                return
            }

            self.settings.pinnedDeviceUID = device.uid
            self.settings.pinnedDeviceName = device.name
            self.settings.pinEnabled = true
            _ = self.writeDefaultInputDeviceID(device.id)
            self.publishState()
        }
    }

    func setPinEnabled(_ enabled: Bool) {
        performOnAudioQueue { [weak self] in
            guard let self else { return }

            if !enabled {
                self.settings.pinEnabled = false
                self.publishState()
                return
            }

            let devices = self.readInputDevices()
            let savedDevice = self.settings.pinnedDeviceUID.flatMap { uid in
                devices.first { $0.uid == uid }
            }
            let currentDevice = self.readDefaultInputDeviceID().flatMap { id in
                devices.first { $0.id == id }
            }

            if let device = savedDevice ?? currentDevice {
                self.settings.pinnedDeviceUID = device.uid
                self.settings.pinnedDeviceName = device.name
                self.settings.pinEnabled = true
                _ = self.ensureDefaultInput(device)
            } else {
                self.settings.pinEnabled = true
                self.logger.notice("Pin enabled while no input device is currently available")
            }

            self.publishState()
        }
    }

    private func refreshState(enforcePin: Bool) {
        let devices = readInputDevices()

        if enforcePin,
           settings.pinEnabled,
           let pinnedUID = settings.pinnedDeviceUID,
           let pinnedDevice = devices.first(where: { $0.uid == pinnedUID }) {
            _ = ensureDefaultInput(pinnedDevice)
        }

        publishState()
    }

    private func ensureDefaultInput(_ device: AudioDevice) -> Bool {
        guard readDefaultInputDeviceID() != device.id else { return true }
        return writeDefaultInputDeviceID(device.id)
    }

    private func publishState(devices suppliedDevices: [AudioDevice]? = nil) {
        let defaultID = readDefaultInputDeviceID()
        let devices = (suppliedDevices ?? readInputDevices()).map { device in
            AudioDevice(
                id: device.id,
                uid: device.uid,
                name: device.name,
                isDefault: device.id == defaultID
            )
        }
        let state = AudioState(
            devices: devices,
            defaultDeviceUID: devices.first(where: { $0.isDefault })?.uid,
            pinEnabled: settings.pinEnabled,
            pinnedDeviceUID: settings.pinnedDeviceUID,
            pinnedDeviceName: settings.pinnedDeviceName
        )

        guard let handler = onStateChange else { return }
        DispatchQueue.main.async {
            handler(state)
        }
    }

    private func readInputDevices() -> [AudioDevice] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize)
        guard status == noErr else {
            logError(status, operation: "read device-list size")
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        status = deviceIDs.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, buffer.baseAddress!)
        }
        guard status == noErr else {
            logError(status, operation: "read device list")
            return []
        }

        let defaultID = readDefaultInputDeviceID()
        return deviceIDs.compactMap { deviceID in
            guard inputChannelCount(for: deviceID) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID),
                  let name = stringProperty(kAudioObjectPropertyName, for: deviceID) else {
                return nil
            }
            return AudioDevice(id: deviceID, uid: uid, name: name, isDefault: deviceID == defaultID)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readDefaultInputDeviceID() -> AudioDeviceID? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr else {
            logError(status, operation: "read default input")
            return nil
        }
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    private func writeDefaultInputDeviceID(_ deviceID: AudioDeviceID) -> Bool {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isSettable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(systemObject, &address, &isSettable)
        guard settableStatus == noErr else {
            logError(settableStatus, operation: "check default-input mutability")
            return false
        }
        guard isSettable.boolValue else {
            logger.error("The CoreAudio default-input property is not settable")
            return false
        }

        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
        guard status == noErr else {
            logError(status, operation: "set default input")
            return false
        }
        return true
    }

    private func inputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPointer)
        guard status == noErr else { return 0 }

        let audioBufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(audioBufferList).reduce(0) {
            $0 + $1.mNumberChannels
        }
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, for objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func registerListenersIfNeeded() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        if !defaultListenerRegistered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectAddPropertyListenerBlock(
                systemObject,
                &address,
                audioQueue,
                defaultInputListener
            )
            if status == noErr {
                defaultListenerRegistered = true
            } else {
                logError(status, operation: "register default-input listener")
            }
        }

        if !deviceListListenerRegistered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectAddPropertyListenerBlock(
                systemObject,
                &address,
                audioQueue,
                deviceListListener
            )
            if status == noErr {
                deviceListListenerRegistered = true
            } else {
                logError(status, operation: "register device-list listener")
            }
        }
    }

    private func removeListenersIfNeeded() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        if defaultListenerRegistered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &address,
                audioQueue,
                defaultInputListener
            )
            if status == noErr {
                defaultListenerRegistered = false
            } else {
                logError(status, operation: "remove default-input listener")
            }
        }

        if deviceListListenerRegistered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &address,
                audioQueue,
                deviceListListener
            )
            if status == noErr {
                deviceListListenerRegistered = false
            } else {
                logError(status, operation: "remove device-list listener")
            }
        }
    }

    private func stopMonitoringSynchronously() {
        performSynchronously {
            removeListenersIfNeeded()
        }
    }

    private func performOnAudioQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            audioQueue.async(execute: work)
        }
    }

    private func performSynchronously<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return work()
        }
        return audioQueue.sync(execute: work)
    }

    private func logError(_ status: OSStatus, operation: String) {
        logger.error("CoreAudio failed to \(operation, privacy: .public): OSStatus \(status)")
    }
}
