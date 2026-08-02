// Transport-independent HID++ 2.0 message layer (feature 0x1B04 "Special Keys and Mouse
// Buttons"). Only knows the logical message [featureIndex, funcId<<4|swId, params...], not the
// transport-specific framing around it (BLE: no extra bytes needed; USB dongle: 0x10/0x11 report
// marker + devIndex, see docs/logi-hidpp-thumb-buttons-plan.md and
// ~/Devel/logitech-ipc-protocol/hidpp_thumb_buttons.py). This lets a future USB dongle backend
// reuse the same logic and only wrap its own byte framing around it.
//
// Reference: https://lekensteyn.nl/files/logitech/x1b04_specialkeysmsebuttons.html

import Foundation

/// A single HID++ 2.0 message at the logical level, without any transport prefix.
struct HIDPPMessage {
    var featureIndex: UInt8
    var funcId: UInt8
    var swId: UInt8
    var params: [UInt8]

    init(featureIndex: UInt8, funcId: UInt8, swId: UInt8, params: [UInt8] = []) {
        self.featureIndex = featureIndex
        self.funcId = funcId
        self.swId = swId
        self.params = params
    }

    /// Decodes already transport-stripped bytes: [featureIndex, funcId<<4|swId, param0, ...]
    init?(messageBytes bytes: [UInt8]) {
        guard bytes.count >= 2 else { return nil }
        featureIndex = bytes[0]
        funcId = bytes[1] >> 4
        swId = bytes[1] & 0x0F
        params = Array(bytes.dropFirst(2))
    }

    /// Encodes to transport-stripped bytes (without any transport prefix).
    var messageBytes: [UInt8] {
        [featureIndex, (funcId << 4) | (swId & 0x0F)] + params
    }
}

enum HIDPP {
    static let rootFeatureIndex: UInt8 = 0x00
    static let featureIdSpecialKeysAndMouseButtons: UInt16 = 0x1B04

    /// Software ID for our own requests. Known IDs already in use (do not reuse): 0x1/0x2/0x5
    /// (our own dev prototypes in ~/Devel/logitech-ipc-protocol), 0x7 OpenRGB, 0xA LGSTrayEx,
    /// 0xB Solaar, 0xD Logitech G HUB, 0xF firmware, 0xC Logi Options+ (on BLE).
    static let ourSwId: UInt8 = 0x4

    static let cidNames: [UInt16: String] = [
        80: "Left", 81: "Right", 82: "Middle", 83: "Back", 86: "Forward", 196: "SmartShift",
    ]

    // MARK: getCidInfo capability flags (funcId 0x01, feature table entry per CID)

    static let cidFlagIsMouseButton: UInt8 = 0x01
    static let cidFlagIsDivertableCapability: UInt8 = 0x20 // bit5
    static let cidFlagIsPersistCapability: UInt8 = 0x40 // bit6

    // MARK: Root.getFeature (featureIndex=0, funcId=0x00)

    static func getFeatureRequest(featureId: UInt16) -> HIDPPMessage {
        HIDPPMessage(featureIndex: rootFeatureIndex, funcId: 0x00, swId: ourSwId,
                     params: [UInt8(featureId >> 8), UInt8(featureId & 0xFF)])
    }

    /// Returns the feature index from a Root.getFeature response, or nil if the message doesn't
    /// match or the feature isn't supported (resulting featureIndex 0).
    static func decodeGetFeatureResponse(_ message: HIDPPMessage) -> UInt8? {
        guard message.featureIndex == rootFeatureIndex, message.funcId == 0x00, message.swId == ourSwId,
              let index = message.params.first, index != 0 else { return nil }
        return index
    }

    // MARK: getCount / getCidInfo -> CID table (funcId 0x00 resp. 0x01 on feature 0x1B04)

    static func getCountRequest(featureIndex: UInt8) -> HIDPPMessage {
        HIDPPMessage(featureIndex: featureIndex, funcId: 0x00, swId: ourSwId)
    }

    static func getCidInfoRequest(featureIndex: UInt8, index: UInt8) -> HIDPPMessage {
        HIDPPMessage(featureIndex: featureIndex, funcId: 0x01, swId: ourSwId, params: [index])
    }

    /// Decodes a getCidInfo response into (cid, capabilityFlags). Only cid and the first flags
    /// byte are needed (see hidpp_thumb_buttons.py:get_cid_table).
    static func decodeCidInfoResponse(_ message: HIDPPMessage) -> (cid: UInt16, flags: UInt8)? {
        guard message.params.count >= 5 else { return nil }
        let cid = UInt16(message.params[0]) << 8 | UInt16(message.params[1])
        return (cid, message.params[4])
    }

    // MARK: getCidReporting / setCidReporting (funcId 0x02 / 0x03) - current divert state

    static func getCidReportingRequest(featureIndex: UInt8, cid: UInt16) -> HIDPPMessage {
        HIDPPMessage(featureIndex: featureIndex, funcId: 0x02, swId: ourSwId,
                     params: [UInt8(cid >> 8), UInt8(cid & 0xFF)])
    }

    /// Decodes a getCidReporting response. Note: this is a different flags byte than getCidInfo
    /// (there: capabilities, here: current state) - see ble_hidpp_check_divert_state.swift.
    static func decodeCidReportingResponse(_ message: HIDPPMessage)
        -> (cid: UInt16, divert: Bool, persist: Bool, rawXY: Bool, remap: UInt16)? {
        guard message.params.count >= 5 else { return nil }
        let cid = UInt16(message.params[0]) << 8 | UInt16(message.params[1])
        let flags = message.params[2]
        let remap = UInt16(message.params[3]) << 8 | UInt16(message.params[4])
        return (cid, flags & 0x01 != 0, flags & 0x04 != 0, flags & 0x10 != 0, remap)
    }

    static func setCidReportingRequest(featureIndex: UInt8, cid: UInt16, divert: Bool) -> HIDPPMessage {
        let flags: UInt8 = 0b0000_0010 | (divert ? 0b0000_0001 : 0) // bit1=dvalid, bit0=divert
        return HIDPPMessage(featureIndex: featureIndex, funcId: 0x03, swId: ourSwId,
                            params: [UInt8(cid >> 8), UInt8(cid & 0xFF), flags, 0, 0])
    }

    // MARK: divertedButtonsEvent (funcId=0x00, swId=0x00 - spontaneous event, not a reply)

    /// divertedButtonsEvent carries swId==0 (spontaneous event), which reliably distinguishes it
    /// from replies to our own requests (which always echo our `ourSwId`).
    static func isDivertedButtonsEvent(_ message: HIDPPMessage) -> Bool {
        message.funcId == 0x00 && message.swId == 0x00
    }

    /// Decodes up to 4 currently pressed CIDs (BE16 each, list ends at cid==0).
    static func decodeDivertedButtonsEvent(_ message: HIDPPMessage) -> Set<UInt16> {
        var pressed: Set<UInt16> = []
        var i = 0
        while i + 1 < message.params.count {
            let cid = UInt16(message.params[i]) << 8 | UInt16(message.params[i + 1])
            if cid == 0 { break }
            pressed.insert(cid)
            i += 2
        }
        return pressed
    }
}
