// Facade for one or more Logitech HID++ backends (currently only Bluetooth, see
// docs/logi-hidpp-thumb-buttons-plan.md for the planned USB dongle backend). Mirrors the
// `Multitouch` pattern ("one global facade with a simple API"), but in plain Swift, since there
// is no private C API to bridge here.

import Foundation

final class LogiHIDPP {
    static let shared = LogiHIDPP()

    /// One entry per supported transport. A future USB dongle backend is added here simply
    /// (`LogiUSBButtonSource()`), without any consumer code needing to change.
    private let backends: [any HIDPPButtonSource] = [LogiBLEButtonSource()]

    /// Called whenever a diverted button changes state on any backend. Depending on the
    /// transport, this may be called on any thread.
    var onButtonEvent: ((_ device: HIDPPDeviceID, _ cid: UInt16, _ isDown: Bool) -> Void)? {
        didSet { backends.forEach { $0.onButtonEvent = onButtonEvent } }
    }
    
    /// Called whenever a device becomes ready on any backend. See `HIDPPButtonSource.onDeviceReady`.
    var onDeviceReady: ((_ device: HIDPPDeviceID) -> Void)? {
        didSet { backends.forEach { $0.onDeviceReady = onDeviceReady } }
    }

    var connectedDevices: [HIDPPDeviceID] { backends.flatMap(\.connectedDevices) }

    func cidTable(for device: HIDPPDeviceID) -> [HIDPPCidInfo] {
        backends.first { $0.connectedDevices.contains(device) }?.cidTable(for: device) ?? []
    }

    func setDivert(cid: UInt16, enabled: Bool, for device: HIDPPDeviceID) {
        backends.first { $0.connectedDevices.contains(device) }?.setDivert(cid: cid, enabled: enabled, for: device)
    }
}
