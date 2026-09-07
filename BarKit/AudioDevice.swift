import CoreAudio

struct AudioDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
}

struct AudioState {
    let devices: [AudioDevice]
    let defaultDeviceUID: String?
    let pinEnabled: Bool
    let pinnedDeviceUID: String?
    let pinnedDeviceName: String?
}
