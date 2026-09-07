import CoreGraphics

struct DisplayDevice: Equatable {
    enum Control: Equatable {
        case builtIn
        case ddc
        case unsupported
    }

    let id: CGDirectDisplayID
    let name: String
    let control: Control
    let brightness: Double?

    var isSupported: Bool {
        control != .unsupported
    }
}
