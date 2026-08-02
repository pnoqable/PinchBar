// Backend 1 (see docs/logi-hidpp-thumb-buttons-plan.md): speaks HID++ 2.0 directly over
// Bluetooth LE to any bonded Logitech mouse, via the vendor-specific GATT channel Logitech uses
// to tunnel HID++ (service 00010000-0000-1000-8000-011F2000046D, characteristic 00010001-...
// with read/write/notify). No Unifying/Bolt dongle required.
//
// Ported from ~/Devel/logitech-ipc-protocol/ble_hidpp_thumb_buttons.swift, generalized:
// - no name hardcoding ("MX Anywhere 3") - generic detection via the vendor service
// - supports multiple simultaneously connected devices
// - non-mouse devices (e.g. a paired MX Keys keyboard) are filtered out via the CID table's
//   mouse flag
// - reconnect handling on disconnect/Bluetooth off-on
//
// Unlike the USB dongle, BLE HID++ framing carries neither a report marker (0x10/0x11) nor a
// devIndex byte, since only one logical device exists per GATT connection (verified bit-exact,
// see pinchbar-session-handoff.md section 4).

import Foundation
import CoreBluetooth

final class LogiBLEButtonSource: NSObject, HIDPPButtonSource {
    /// Logitech's vendor-specific GATT service for the HID++ tunnel. The UUID contains `046D`,
    /// Logitech's USB vendor ID, in its suffix - specific enough to identify Logitech's HID++
    /// channel without needing a device name.
    private static let vendorServiceUUID = CBUUID(string: "00010000-0000-1000-8000-011F2000046D")

    /// Well-known standard services CoreBluetooth uses to find already-connected peripherals via
    /// `retrieveConnectedPeripherals(withServices:)` (that method needs a known service UUID;
    /// the vendor service itself can't reliably be used for this before it has been confirmed at
    /// least once via service discovery). Every Bluetooth mouse/keyboard exposes at least one of
    /// these standard services.
    private static let discoveryServiceUUIDs = [
        CBUUID(string: "1812"), CBUUID(string: "180F"), CBUUID(string: "180A"), CBUUID(string: "1800"),
    ]

    private static let reconnectDelay: TimeInterval = 1
    private static let rescanInterval: TimeInterval = 5

    private final class DeviceState {
        enum Phase: Equatable { case awaitingFeatureIndex, awaitingCidCount, awaitingCidInfo,
                                     awaitingCidReporting, ready, notAMouse }

        let peripheral: CBPeripheral
        var hidppCharacteristic: CBCharacteristic?
        var featureIndex: UInt8?
        var phase: Phase = .awaitingFeatureIndex
        var pressedCids: Set<UInt16> = []

        var remainingCidIndices: [UInt8] = []
        var cidCapabilities: [(cid: UInt16, flags: UInt8)] = []
        var remainingReportingQueries: [(cid: UInt16, flags: UInt8)] = []
        var cidTable: [HIDPPCidInfo] = []

        init(peripheral: CBPeripheral) { self.peripheral = peripheral }

        var deviceID: HIDPPDeviceID {
            HIDPPDeviceID(identifier: peripheral.identifier, name: peripheral.name ?? "Logitech device")
        }
    }
    
    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private lazy var rescanTimer = Timer.scheduledTimer(withTimeInterval: Self.rescanInterval,
                                                        repeats: true) { [weak self] _ in
        guard let self, self.central.state == .poweredOn else { return }
        self.discoverAlreadyConnectedPeripherals(self.central)
    }
    
    private var devices: [UUID: DeviceState] = [:]
    
    var onButtonEvent: ((HIDPPDeviceID, UInt16, Bool) -> Void)?

    override init() {
        super.init()
        
        // start the engines:
        (_, _) = (central, rescanTimer)
        
        RunLoop.main.add(rescanTimer, forMode: .common)
    }
    
    deinit {
        rescanTimer.invalidate()
        devices.values.forEach { central.cancelPeripheralConnection($0.peripheral) }
    }

    var connectedDevices: [HIDPPDeviceID] {
        devices.values.filter { $0.phase == .ready }.map(\.deviceID)
    }

    func cidTable(for device: HIDPPDeviceID) -> [HIDPPCidInfo] {
        devices[device.identifier]?.cidTable ?? []
    }

    func setDivert(cid: UInt16, enabled: Bool, for device: HIDPPDeviceID) {
        guard let state = devices[device.identifier], let featureIndex = state.featureIndex,
              let characteristic = state.hidppCharacteristic else { return }
        write(HIDPP.setCidReportingRequest(featureIndex: featureIndex, cid: cid, divert: enabled),
              to: characteristic, on: state.peripheral)
    }

    // MARK: - Discovery

    private func discoverAlreadyConnectedPeripherals(_ central: CBCentralManager) {
        for uuid in [Self.vendorServiceUUID] + Self.discoveryServiceUUIDs {
            for peripheral in central.retrieveConnectedPeripherals(withServices: [uuid]) {
                guard devices[peripheral.identifier] == nil else { continue }
                devices[peripheral.identifier] = DeviceState(peripheral: peripheral)
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            }
        }
    }

    // MARK: - Setup sequence (Root.getFeature -> getCount -> getCidInfo* -> getCidReporting*)

    private func requestNextCidInfo(_ state: DeviceState, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        guard let featureIndex = state.featureIndex, !state.remainingCidIndices.isEmpty else { return }
        let index = state.remainingCidIndices.removeFirst()
        write(HIDPP.getCidInfoRequest(featureIndex: featureIndex, index: index), to: characteristic, on: peripheral)
    }

    private func requestNextCidReporting(_ state: DeviceState, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        guard let featureIndex = state.featureIndex, let next = state.remainingReportingQueries.first else { return }
        write(HIDPP.getCidReportingRequest(featureIndex: featureIndex, cid: next.cid), to: characteristic, on: peripheral)
    }

    private func finishSetup(_ state: DeviceState, isMouse: Bool) {
        if isMouse {
            state.phase = .ready
        } else {
            state.phase = .notAMouse
            central.cancelPeripheralConnection(state.peripheral)
            devices.removeValue(forKey: state.peripheral.identifier)
        }
    }

    private func handleDivertedButtonsEvent(_ message: HIDPPMessage, state: DeviceState) {
        let currentlyPressed = HIDPP.decodeDivertedButtonsEvent(message)
        let newlyDown = currentlyPressed.subtracting(state.pressedCids)
        let newlyUp = state.pressedCids.subtracting(currentlyPressed)
        state.pressedCids = currentlyPressed

        let deviceID = state.deviceID
        newlyDown.forEach { onButtonEvent?(deviceID, $0, true) }
        newlyUp.forEach { onButtonEvent?(deviceID, $0, false) }
    }

    private func write(_ message: HIDPPMessage, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(message.messageBytes), for: characteristic, type: type)
    }
}

extension LogiBLEButtonSource: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        discoverAlreadyConnectedPeripherals(central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        devices.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        devices.removeValue(forKey: peripheral.identifier)
        // The mouse is still bonded, just temporarily unreachable (asleep, out of range, ...) -
        // try again once it's reconnected.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay) { [weak self] in
            self?.discoverAlreadyConnectedPeripherals(central)
        }
    }
}

extension LogiBLEButtonSource: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let vendorService = peripheral.services?.first(where: { $0.uuid == Self.vendorServiceUUID }) else {
            // No HID++ vendor service - not a supported Logitech device, give up on it.
            central.cancelPeripheralConnection(peripheral)
            devices.removeValue(forKey: peripheral.identifier)
            return
        }
        peripheral.discoverCharacteristics(nil, for: vendorService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, service.uuid == Self.vendorServiceUUID, let state = devices[peripheral.identifier],
              let characteristic = service.characteristics?.first(where: {
                  $0.properties.contains(.notify) && $0.properties.contains(.write)
              }) else { return }
        state.hidppCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let state = devices[peripheral.identifier], characteristic === state.hidppCharacteristic else { return }
        write(HIDPP.getFeatureRequest(featureId: HIDPP.featureIdSpecialKeysAndMouseButtons), to: characteristic, on: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value, let message = HIDPPMessage(messageBytes: [UInt8](value)),
              let state = devices[peripheral.identifier] else { return }

        switch state.phase {
        case .awaitingFeatureIndex:
            guard let featureIndex = HIDPP.decodeGetFeatureResponse(message) else { return }
            state.featureIndex = featureIndex
            state.phase = .awaitingCidCount
            write(HIDPP.getCountRequest(featureIndex: featureIndex), to: characteristic, on: peripheral)

        case .awaitingCidCount:
            guard message.featureIndex == state.featureIndex, message.funcId == 0x00, message.swId == HIDPP.ourSwId else { return }
            let count = message.params.first ?? 0
            if count == 0 {
                finishSetup(state, isMouse: false)
            } else {
                state.remainingCidIndices = Array(0..<count)
                state.phase = .awaitingCidInfo
                requestNextCidInfo(state, characteristic: characteristic, peripheral: peripheral)
            }

        case .awaitingCidInfo:
            guard message.featureIndex == state.featureIndex, message.funcId == 0x01, message.swId == HIDPP.ourSwId,
                  let (cid, flags) = HIDPP.decodeCidInfoResponse(message) else { return }
            state.cidCapabilities.append((cid, flags))
            if state.remainingCidIndices.isEmpty {
                state.remainingReportingQueries = state.cidCapabilities.filter {
                    $0.flags & HIDPP.cidFlagIsDivertableCapability != 0
                }
                state.phase = .awaitingCidReporting
                if state.remainingReportingQueries.isEmpty {
                    finishCidTable(state)
                } else {
                    requestNextCidReporting(state, characteristic: characteristic, peripheral: peripheral)
                }
            } else {
                requestNextCidInfo(state, characteristic: characteristic, peripheral: peripheral)
            }

        case .awaitingCidReporting:
            guard message.featureIndex == state.featureIndex, message.funcId == 0x02, message.swId == HIDPP.ourSwId,
                  let reporting = HIDPP.decodeCidReportingResponse(message),
                  let index = state.remainingReportingQueries.firstIndex(where: { $0.cid == reporting.cid }) else { return }
            let flags = state.remainingReportingQueries.remove(at: index).flags
            state.cidTable.append(HIDPPCidInfo(cid: reporting.cid,
                                                isMouseButton: flags & HIDPP.cidFlagIsMouseButton != 0,
                                                isDivertable: true,
                                                isDiverted: reporting.divert))
            if state.remainingReportingQueries.isEmpty {
                finishCidTable(state)
            } else {
                requestNextCidReporting(state, characteristic: characteristic, peripheral: peripheral)
            }

        case .ready:
            guard message.featureIndex == state.featureIndex, HIDPP.isDivertedButtonsEvent(message) else { return }
            handleDivertedButtonsEvent(message, state: state)

        case .notAMouse:
            break
        }
    }

    /// Adds non-divertable CIDs (only known from the capability flags) and completes setup.
    private func finishCidTable(_ state: DeviceState) {
        for (cid, flags) in state.cidCapabilities where flags & HIDPP.cidFlagIsDivertableCapability == 0 {
            state.cidTable.append(HIDPPCidInfo(cid: cid, isMouseButton: flags & HIDPP.cidFlagIsMouseButton != 0,
                                                isDivertable: false, isDiverted: false))
        }
        finishSetup(state, isMouse: state.cidCapabilities.contains { $0.flags & HIDPP.cidFlagIsMouseButton != 0 })
    }
}
