// Backend 2: discovers Logitech receivers exposing the HID++ raw channel over USB. HID++
// messages are framed as 0x10/0x11 reports with a receiver-local device index, unlike the BLE
// backend's direct GATT messages. See docs/logi-hidpp-usb-dongle-plan.md.

import Foundation
import IOKit.hid

final class LogiUSBButtonSource: HIDPPButtonSource {
    private static let logitechVendorID: Int = 0x046D
    private static let hidppUsagePage: Int = 0xFF00

    private final class ReceiverState {
        enum Query {
            case feature(UInt8)
            case count(UInt8, UInt8)
            case cidInfo(UInt8, UInt8, UInt8, UInt8, [(UInt16, UInt8)])
            case cidReporting(UInt8, UInt8, [(UInt16, UInt8)], [(UInt16, UInt8)], [HIDPPCidInfo])

            var deviceIndex: UInt8 {
                switch self {
                case let .feature(deviceIndex), let .count(deviceIndex, _), let .cidInfo(deviceIndex, _, _, _, _),
                     let .cidReporting(deviceIndex, _, _, _, _):
                    return deviceIndex
                }
            }
        }

        let device: IOHIDDevice
        let registryID: UInt64
        let name: String
        var nextDeviceIndex: UInt8 = 0x01
        var query: Query?
        var devices: [UUID: DeviceState] = [:]

        init(device: IOHIDDevice) {
            self.device = device
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
            self.registryID = registryID
            name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech USB receiver"
        }
    }

    private final class DeviceState {
        let deviceID: HIDPPDeviceID
        let deviceIndex: UInt8
        let featureIndex: UInt8
        var cidTable: [HIDPPCidInfo]
        var pressedCids: Set<UInt16> = []

        init(receiver: ReceiverState, deviceIndex: UInt8, featureIndex: UInt8, cidTable: [HIDPPCidInfo]) {
            deviceID = HIDPPDeviceID(identifier: UUID(), name: "\(receiver.name) 0x\(String(format: "%02X", deviceIndex))")
            self.deviceIndex = deviceIndex
            self.featureIndex = featureIndex
            self.cidTable = cidTable
        }
    }

    /// USB framing only. IOKit requires the 0x10/0x11 report ID both as `reportID` and as the
    /// first payload byte for devices with multiple report IDs.
    private struct USBHIDPPFrame {
        let marker: UInt8
        let deviceIndex: UInt8
        let message: HIDPPMessage

        init?(reportID: UInt32, payload: [UInt8]) {
            let marker = (payload.first == 0x10 || payload.first == 0x11)
                ? payload[0]
                : UInt8(truncatingIfNeeded: reportID)
            let bytes = payload.first == marker ? payload : [marker] + payload

            guard marker == 0x10 || marker == 0x11, bytes.count >= 4 else { return nil }
            self.marker = marker
            deviceIndex = bytes[1]
            guard let message = HIDPPMessage(messageBytes: Array(bytes.dropFirst(2))) else { return nil }
            self.message = message
        }

        /// Produces the HID++ wire representation including its report-ID marker.
        static func wireBytes(deviceIndex: UInt8, message: HIDPPMessage) -> [UInt8] {
            let marker: UInt8 = message.params.count <= 3 ? 0x10 : 0x11
            let length = marker == 0x10 ? 7 : 20
            let bytes = [marker, deviceIndex] + message.messageBytes
            return bytes + Array(repeating: 0, count: max(0, length - bytes.count))
        }
    }

    private let manager: IOHIDManager
    
    private var receivers: [UInt64: ReceiverState] = [:]
    
    var onButtonEvent: ((HIDPPDeviceID, UInt16, Bool) -> Void)?
    var onDeviceReady: ((HIDPPDeviceID) -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.logitechVendorID,
            kIOHIDPrimaryUsagePageKey: Self.hidppUsagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatched, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputReportCallback(manager, Self.inputReport, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            NSLog("Cannot open Logitech USB HID++ manager")
            return
        }
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        receivers.values.forEach(releasePressedButtons)
        receivers.removeAll()
    }

    var connectedDevices: [HIDPPDeviceID] { receivers.values.flatMap { $0.devices.values.map(\.deviceID) } }

    func cidTable(for device: HIDPPDeviceID) -> [HIDPPCidInfo] {
        receivers.values.flatMap(\.devices.values).first { $0.deviceID == device }?.cidTable ?? []
    }

    func setDivert(cid: UInt16, enabled: Bool, for device: HIDPPDeviceID) {
        guard let receiver = receivers.values.first(where: { $0.devices[device.identifier] != nil }),
              let state = receiver.devices[device.identifier] else { return }
        send(HIDPP.setCidReportingRequest(featureIndex: state.featureIndex, cid: cid, divert: enabled),
             to: receiver, deviceIndex: state.deviceIndex)
    }

    private func receiverMatched(_ device: IOHIDDevice) {
        let receiver = ReceiverState(device: device)
        guard receivers[receiver.registryID] == nil else { return }
        receivers[receiver.registryID] = receiver
        sendNextFeatureQuery(to: receiver)
    }

    private func receiverRemoved(_ device: IOHIDDevice) {
        let receiver = ReceiverState(device: device)
        guard let removed = receivers.removeValue(forKey: receiver.registryID) else { return }
        releasePressedButtons(for: removed)
    }

    private func receivedReport(sender: UnsafeMutableRawPointer?, reportID: UInt32, bytes: [UInt8]) {
        guard let frame = USBHIDPPFrame(reportID: reportID, payload: bytes) else { return }

        guard let receiver = receiver(for: sender) else { return }
        handle(frame, from: receiver)
    }

    private func receiver(for sender: UnsafeMutableRawPointer?) -> ReceiverState? {
        guard let sender else { return nil }
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
        return receivers[registryID]
    }

    private func sendNextFeatureQuery(to receiver: ReceiverState) {
        guard receiver.nextDeviceIndex <= 0x06 else { return }
        let deviceIndex = receiver.nextDeviceIndex
        receiver.nextDeviceIndex += 1
        receiver.query = .feature(deviceIndex)
        send(HIDPP.getFeatureRequest(featureId: HIDPP.featureIdSpecialKeysAndMouseButtons),
             to: receiver, deviceIndex: deviceIndex)
    }

    private func send(_ message: HIDPPMessage, to receiver: ReceiverState, deviceIndex: UInt8) {
        let wireBytes = USBHIDPPFrame.wireBytes(deviceIndex: deviceIndex, message: message)
        let result = wireBytes.withUnsafeBytes {
            IOHIDDeviceSetReport(receiver.device, kIOHIDReportTypeOutput, CFIndex(wireBytes[0]),
                                 $0.baseAddress!.assumingMemoryBound(to: UInt8.self), wireBytes.count)
        }
        guard result != kIOReturnSuccess else { return }
        NSLog("Logitech USB HID++ request failed: devIndex=0x%02X result=0x%08X",
              deviceIndex, UInt32(bitPattern: result))
        receiver.query = nil
        sendNextFeatureQuery(to: receiver)
    }

    private func handle(_ frame: USBHIDPPFrame, from receiver: ReceiverState) {
        if let state = receiver.devices.values.first(where: { $0.deviceIndex == frame.deviceIndex && $0.featureIndex == frame.message.featureIndex }),
           HIDPP.isDivertedButtonsEvent(frame.message) {
            let current = HIDPP.decodeDivertedButtonsEvent(frame.message)
            let deviceID = state.deviceID
            current.subtracting(state.pressedCids).forEach { onButtonEvent?(deviceID, $0, true) }
            state.pressedCids.subtracting(current).forEach { onButtonEvent?(deviceID, $0, false) }
            state.pressedCids = current
            return
        }
        guard let query = receiver.query, frame.deviceIndex == query.deviceIndex else { return }

        if frame.message.featureIndex == 0x8F || frame.message.featureIndex == 0xFF {
            receiver.query = nil
            sendNextFeatureQuery(to: receiver)
            return
        }

        switch query {
        case let .feature(deviceIndex):
            guard let featureIndex = HIDPP.decodeGetFeatureResponse(frame.message) else { return }
            receiver.query = .count(deviceIndex, featureIndex)
            send(HIDPP.getCountRequest(featureIndex: featureIndex), to: receiver, deviceIndex: deviceIndex)

        case let .count(deviceIndex, featureIndex):
            guard frame.message.featureIndex == featureIndex, frame.message.funcId == 0x00,
                  frame.message.swId == HIDPP.ourSwId else { return }
            let count = frame.message.params.first ?? 0
            guard count > 0 else {
                receiver.query = nil
                sendNextFeatureQuery(to: receiver)
                return
            }
            receiver.query = .cidInfo(deviceIndex, featureIndex, 0, count, [])
            send(HIDPP.getCidInfoRequest(featureIndex: featureIndex, index: 0), to: receiver, deviceIndex: deviceIndex)

        case let .cidInfo(deviceIndex, featureIndex, index, count, entries):
            guard frame.message.featureIndex == featureIndex, frame.message.funcId == 0x01,
                  frame.message.swId == HIDPP.ourSwId, let entry = HIDPP.decodeCidInfoResponse(frame.message) else { return }
            let updatedEntries = entries + [entry]
            let nextIndex = index + 1
            if nextIndex < count {
                receiver.query = .cidInfo(deviceIndex, featureIndex, nextIndex, count, updatedEntries)
                send(HIDPP.getCidInfoRequest(featureIndex: featureIndex, index: nextIndex), to: receiver, deviceIndex: deviceIndex)
            } else {
                finishCapabilities(updatedEntries, receiver: receiver, deviceIndex: deviceIndex, featureIndex: featureIndex)
            }

        case let .cidReporting(deviceIndex, featureIndex, capabilities, remaining, table):
            guard frame.message.featureIndex == featureIndex, frame.message.funcId == 0x02,
                  frame.message.swId == HIDPP.ourSwId, let reporting = HIDPP.decodeCidReportingResponse(frame.message),
                  let index = remaining.firstIndex(where: { $0.0 == reporting.cid }) else { return }
            let updatedRemaining = remaining.enumerated().compactMap { $0.offset == index ? nil : $0.element }
            let flags = remaining[index].1
            let updatedTable = table + [HIDPPCidInfo(cid: reporting.cid,
                                                      isMouseButton: flags & HIDPP.cidFlagIsMouseButton != 0,
                                                      isDivertable: true, isDiverted: reporting.divert)]
            if let next = updatedRemaining.first {
                receiver.query = .cidReporting(deviceIndex, featureIndex, capabilities, updatedRemaining, updatedTable)
                send(HIDPP.getCidReportingRequest(featureIndex: featureIndex, cid: next.0), to: receiver, deviceIndex: deviceIndex)
            } else {
                registerDevice(capabilities, table: updatedTable, receiver: receiver, deviceIndex: deviceIndex, featureIndex: featureIndex)
            }
        }
    }

    private func finishCapabilities(_ capabilities: [(UInt16, UInt8)], receiver: ReceiverState, deviceIndex: UInt8, featureIndex: UInt8) {
        guard capabilities.contains(where: { $0.1 & HIDPP.cidFlagIsMouseButton != 0 }) else {
            receiver.query = nil
            sendNextFeatureQuery(to: receiver)
            return
        }
        let reporting = capabilities.filter { $0.1 & HIDPP.cidFlagIsDivertableCapability != 0 }
        guard let next = reporting.first else {
            registerDevice(capabilities, table: [], receiver: receiver, deviceIndex: deviceIndex, featureIndex: featureIndex)
            return
        }
        receiver.query = .cidReporting(deviceIndex, featureIndex, capabilities, reporting, [])
        send(HIDPP.getCidReportingRequest(featureIndex: featureIndex, cid: next.0), to: receiver, deviceIndex: deviceIndex)
    }

    private func registerDevice(_ capabilities: [(UInt16, UInt8)], table: [HIDPPCidInfo], receiver: ReceiverState, deviceIndex: UInt8, featureIndex: UInt8) {
        let nonDivertable = capabilities.filter { $0.1 & HIDPP.cidFlagIsDivertableCapability == 0 }.map {
            HIDPPCidInfo(cid: $0.0, isMouseButton: $0.1 & HIDPP.cidFlagIsMouseButton != 0, isDivertable: false, isDiverted: false)
        }
        let state = DeviceState(receiver: receiver, deviceIndex: deviceIndex, featureIndex: featureIndex, cidTable: table + nonDivertable)
        receiver.devices[state.deviceID.identifier] = state
        receiver.query = nil
        onDeviceReady?(state.deviceID)
        sendNextFeatureQuery(to: receiver)
    }

    private func releasePressedButtons(for receiver: ReceiverState) {
        receiver.devices.values.forEach { state in
            state.pressedCids.forEach { onButtonEvent?(state.deviceID, $0, false) }
            state.pressedCids.removeAll()
        }
    }

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<LogiUSBButtonSource>.fromOpaque(context).takeUnretainedValue().receiverMatched(device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<LogiUSBButtonSource>.fromOpaque(context).takeUnretainedValue().receiverRemoved(device)
    }

    private static let inputReport: IOHIDReportCallback = { context, _, sender, _, reportID, report, length in
        guard let context, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        Unmanaged<LogiUSBButtonSource>.fromOpaque(context).takeUnretainedValue()
            .receivedReport(sender: sender, reportID: reportID, bytes: bytes)
    }
}
