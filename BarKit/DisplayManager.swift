import AppKit
import CoreGraphics
import Darwin
import IOKit
import OSLog

struct DisplayState: Equatable {
    let displays: [DisplayDevice]
}

private typealias DisplayServicesGetBrightnessFunction = @convention(c) (
    CGDirectDisplayID,
    UnsafeMutablePointer<Float>
) -> Int32
private typealias DisplayServicesSetBrightnessFunction = @convention(c) (
    CGDirectDisplayID,
    Float
) -> Int32

private final class DisplayServicesBrightness {
    private let handle: UnsafeMutableRawPointer?
    private let getBrightness: DisplayServicesGetBrightnessFunction?
    private let setBrightness: DisplayServicesSetBrightnessFunction?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let handle {
            getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map {
                unsafeBitCast($0, to: DisplayServicesGetBrightnessFunction.self)
            }
            setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map {
                unsafeBitCast($0, to: DisplayServicesSetBrightnessFunction.self)
            }
        } else {
            getBrightness = nil
            setBrightness = nil
        }
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func read(displayID: CGDirectDisplayID) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(displayID, &value) == 0 else { return nil }
        return Double(value).clamped(to: 0 ... 1)
    }

    func write(_ value: Double, displayID: CGDirectDisplayID) -> Bool {
        guard let setBrightness else { return false }
        return setBrightness(displayID, Float(value.clamped(to: 0 ... 1))) == 0
    }
}

private final class DDCService {
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    private static let brightnessCommand: UInt8 = 0x10

    let service: IOAVService
    private var maximumBrightness: UInt16 = 100
    private let logger = Logger(subsystem: "com.barkit.app", category: "DDC")

    init(service: IOAVService) {
        self.service = service
    }

    func readBrightness() -> Double? {
        var command = [Self.brightnessCommand]
        var reply = [UInt8](repeating: 0, count: 11)

        guard communicate(send: &command, reply: &reply),
              reply[2] == 0x02,
              reply[3] == 0x00,
              reply[4] == Self.brightnessCommand else {
            return nil
        }

        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0 else { return nil }
        maximumBrightness = maximum
        return (Double(current) / Double(maximum)).clamped(to: 0 ... 1)
    }

    func writeBrightness(_ brightness: Double) -> Bool {
        let value = UInt16((brightness.clamped(to: 0 ... 1) * Double(maximumBrightness)).rounded())
        var command = [
            Self.brightnessCommand,
            UInt8(value >> 8),
            UInt8(value & 0xff),
        ]
        var reply: [UInt8] = []
        return communicate(send: &command, reply: &reply)
    }

    private func communicate(send: inout [UInt8], reply: inout [UInt8]) -> Bool {
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let seed = send.count == 1
            ? UInt8(Self.chipAddress << 1)
            : UInt8(Self.chipAddress << 1) ^ UInt8(Self.dataAddress)
        packet[packet.count - 1] = checksum(seed: seed, bytes: packet.dropLast())

        for _ in 0 ..< 3 {
            var writeResult = kIOReturnError
            for _ in 0 ..< 2 {
                usleep(10_000)
                writeResult = packet.withUnsafeMutableBytes { buffer in
                    IOAVServiceWriteI2C(
                        service,
                        Self.chipAddress,
                        Self.dataAddress,
                        buffer.baseAddress,
                        UInt32(buffer.count)
                    )
                }
            }
            guard writeResult == kIOReturnSuccess else {
                logger.debug("DDC write failed with IOReturn \(writeResult)")
                usleep(20_000)
                continue
            }

            if reply.isEmpty {
                return true
            }

            usleep(50_000)
            let readResult = reply.withUnsafeMutableBytes { buffer in
                IOAVServiceReadI2C(
                    service,
                    Self.chipAddress,
                    0,
                    buffer.baseAddress,
                    UInt32(buffer.count)
                )
            }
            if readResult == kIOReturnSuccess,
               checksum(seed: 0x50, bytes: reply.dropLast()) == reply.last {
                return true
            }
            let replyDescription = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
            logger.debug("DDC read failed or returned an invalid checksum; IOReturn \(readResult), reply \(replyDescription, privacy: .public)")
            usleep(20_000)
        }
        return false
    }

    private func checksum(seed: UInt8, bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(seed, ^)
    }
}

final class DisplayManager {
    var onStateChange: ((DisplayState) -> Void)?

    private let logger = Logger(subsystem: "com.barkit.app", category: "Displays")
    private let displayServices = DisplayServicesBrightness()
    private let queue = DispatchQueue(label: "com.barkit.app.displays", qos: .userInitiated)
    private var ddcServices: [CGDirectDisplayID: DDCService] = [:]
    private var pendingBrightness: [CGDirectDisplayID: Double] = [:]
    private var scheduledWrites = Set<CGDirectDisplayID>()
    private var generation = 0
    private var isMonitoring = false

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        refresh()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        isMonitoring = false
    }

    func refresh() {
        generation += 1
        let requestedGeneration = generation
        queue.async { [weak self] in
            self?.loadDisplays(generation: requestedGeneration)
        }
    }

    func setBrightness(_ brightness: Double, for displayID: CGDirectDisplayID) {
        let value = brightness.clamped(to: 0 ... 1)

        if CGDisplayIsBuiltin(displayID) != 0 {
            if !displayServices.write(value, displayID: displayID) {
                logger.error("Failed to set built-in display brightness for display \(displayID)")
            }
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.pendingBrightness[displayID] = value
            guard !self.scheduledWrites.contains(displayID) else { return }
            self.scheduledWrites.insert(displayID)
            self.queue.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                guard let self else { return }
                let latestValue = self.pendingBrightness.removeValue(forKey: displayID)
                self.scheduledWrites.remove(displayID)
                guard let latestValue, let service = self.ddcServices[displayID] else { return }
                if !service.writeBrightness(latestValue) {
                    self.logger.error("Failed to set DDC brightness for display \(displayID)")
                }
            }
        }
    }

    private func loadDisplays(generation requestedGeneration: Int) {
        let displayIDs = activeDisplayIDs()
        let externalIDs = displayIDs.filter { CGDisplayIsBuiltin($0) == 0 }
        let services = makeExternalDDCServices()
        var newServices: [CGDirectDisplayID: DDCService] = [:]
        var devices: [DisplayDevice] = []

        for displayID in displayIDs {
            let name = displayName(for: displayID)
            if CGDisplayIsBuiltin(displayID) != 0 {
                let brightness = displayServices.read(displayID: displayID)
                logger.notice("Detected built-in display \(name, privacy: .public), brightness control: \(brightness != nil)")
                devices.append(DisplayDevice(
                    id: displayID,
                    name: name,
                    control: brightness == nil ? .unsupported : .builtIn,
                    brightness: brightness
                ))
                continue
            }

            let index = externalIDs.firstIndex(of: displayID) ?? 0
            guard index < services.count else {
                devices.append(DisplayDevice(id: displayID, name: name, control: .unsupported, brightness: nil))
                continue
            }

            let service = services[index]
            if let brightness = service.readBrightness() {
                logger.notice("Detected DDC display \(name, privacy: .public), brightness: \(brightness, format: .fixed(precision: 2))")
                newServices[displayID] = service
                devices.append(DisplayDevice(id: displayID, name: name, control: .ddc, brightness: brightness))
            } else {
                logger.notice("Display \(name, privacy: .public) does not respond to DDC brightness reads")
                devices.append(DisplayDevice(id: displayID, name: name, control: .unsupported, brightness: nil))
            }
        }

        let ordered = devices.sorted {
            if $0.control == .builtIn && $1.control != .builtIn { return true }
            if $0.control != .builtIn && $1.control == .builtIn { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, requestedGeneration == self.generation else { return }
            self.ddcServices = newServices
            self.onStateChange?(DisplayState(displays: ordered))
        }
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count))).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(displayID) != 0 ? "Built-in Display" : "External Display"
    }

    private func makeExternalDDCServices() -> [DDCService] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceNameMatching("DCPAVServiceProxy"),
            &iterator
        ) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }

        var services: [DDCService] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }

            guard let location = IORegistryEntryCreateCFProperty(
                entry,
                "Location" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String,
            location == "External",
            let unmanaged = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else {
                continue
            }
            services.append(DDCService(service: unmanaged.takeRetainedValue()))
        }
        return services
    }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
    guard flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.setModeFlag),
          let userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        manager.refresh()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
