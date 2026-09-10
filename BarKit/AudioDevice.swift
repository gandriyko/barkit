import CoreAudio

struct AudioDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
    let inputVolume: Double?
}

struct AudioVolumeDevice: Equatable {
    let id: AudioDeviceID
    let name: String
    let volume: Double?
}

struct AudioState {
    let devices: [AudioDevice]
    let defaultDeviceUID: String?
    let defaultOutputDevice: AudioVolumeDevice?
    let pinEnabled: Bool
    let pinnedDeviceUID: String?
    let pinnedDeviceName: String?
}
