// Public protocol for backends that deliver HID++ 2.0 mouse button (CID, feature 0x1B04) events,
// regardless of transport. Currently implemented by `LogiBLEButtonSource` (Bluetooth LE, see
// docs/logi-hidpp-thumb-buttons-plan.md). A future USB dongle backend (IOHIDManager) can
// implement the same protocol, so consumer code (e.g. a future EventMapping) doesn't need to
// know anything about the underlying transport.

import Foundation

/// Identifies a single physical device across transports (Bluetooth today, potentially USB
/// dongle later).
struct HIDPPDeviceID: Hashable {
    let identifier: UUID
    let name: String
}

/// An entry from a device's CID table (feature 0x1B04, "Special Keys and Mouse Buttons").
/// `isDivertable`/`isMouseButton` come from the getCidInfo capability flags, `isDiverted` from
/// the current state as queried via getCidReporting.
struct HIDPPCidInfo {
    let cid: UInt16
    let isMouseButton: Bool
    let isDivertable: Bool
    let isDiverted: Bool

    var name: String { HIDPP.cidNames[cid] ?? "CID \(cid)" }
}

/// Delivers mouse button state changes (down/up for arbitrary CIDs) for all recognized devices
/// of a transport.
protocol HIDPPButtonSource: AnyObject {
    /// Called whenever a diverted button changes state. Depending on the transport, this may be
    /// called on any thread - see the concrete backend's documentation.
    var onButtonEvent: ((_ device: HIDPPDeviceID, _ cid: UInt16, _ isDown: Bool) -> Void)? { get set }
    
    /// Called once a device finishes its capability query and is ready (i.e. now included in
    /// `connectedDevices`). Optional hook for consumers to (re-)enable divert for CIDs of
    /// interest via `setDivert`, since not every firmware keeps divert permanently active like
    /// the tested MX Anywhere 3 (see docs/logi-hidpp-thumb-buttons-plan.md).
    var onDeviceReady: ((_ device: HIDPPDeviceID) -> Void)? { get set }

    var connectedDevices: [HIDPPDeviceID] { get }

    /// Returns the cached CID table for the device (empty until it has been fully queried after
    /// connecting).
    func cidTable(for device: HIDPPDeviceID) -> [HIDPPCidInfo]

    /// Diverts (or un-diverts) the given CID. Fallback for mice/firmwares where divert isn't
    /// already permanently active like on the MX Anywhere 3 tested so far (see
    /// pinchbar-session-handoff.md section 6, item 2).
    func setDivert(cid: UInt16, enabled: Bool, for device: HIDPPDeviceID)
}
