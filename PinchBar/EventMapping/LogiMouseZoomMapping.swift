// Maps a Logitech HID++ mouse button (CID, feature 0x1B04, see PinchBar/HIDPP/) held down while
// scrolling to a pinch-zoom (magnify) gesture, i.e. "hold thumb button + scroll wheel = zoom".
// See docs/logi-thumb-button-eventmapping-plan.md for the full design rationale.
//
// Unlike other EventMappings, the button itself never arrives as a CGEvent here: once diverted,
// HID++ delivers button state exclusively via LogiHIDPP.onButtonEvent (wired in EventTap.init),
// not as a standard HID report. Only the scroll wheel of the same mouse still produces normal
// CGEvents, so eventMask/map(_:) only need to deal with scrollWheel - the "button down" state is
// fed in externally via onHIDPPButtonEvent(cid:isDown:).

import Cocoa

class LogiMouseZoomMapping: SettingsHolder<LogiMouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var cid: UInt16       // e.g. 86 = Forward, 83 = Back, 196 = SmartShift (see HIDPP.cidNames)
        var sensivity: Double // same meaning as OtherMouseZoomMapping.Settings.sensivity
    }

    var eventMask: CGEventMask { 1 << 22 | 0b100000 }

    private var buttonDown = false
    private var magnifying = false
    
    required init(_ settings: Settings) {
        super.init(settings)
        
        LogiHIDPP.shared.onButtonEvent = { [weak self] _, cid, isDown in
            self?.onHIDPPButtonEvent(cid: cid, isDown: isDown)
        }
    }

    func map(_ event: CGEvent) -> [CGEvent] {
        if buttonDown, event.type == .scrollWheel, event.scrollPointDeltaSum != 0 {
            
            let phase: CGEvent.Phase = magnifying ? .changed : .began
            magnifying = true
            
            return [CGEvent(magnifyEventSource: nil,
                            magnification: settings.sensivity * Double(event.scrollPointDeltaSum),
                            phase: phase)!.with(flags: event.flags)]
        } else if magnifying, event.type == .mouseMoved {
            return [event,
                    CGEvent(magnifyEventSource: nil, magnification: 0, phase: .changed)!
                .with(flags: .maskNoFlags)]
        }
        
        return [event]
    }

    /// Wired up in `EventTap.init` to `LogiHIDPP.shared.onButtonEvent`. Runs on the main thread
    /// (CoreBluetooth's default delegate queue), same as `map(_:)` via the main run loop's
    /// CGEventTap callback - no locking needed between the two.
    func onHIDPPButtonEvent(cid: UInt16, isDown: Bool) {
        guard cid == settings.cid else { return }

        buttonDown = isDown

        if !isDown, magnifying {
            magnifying = false
            CGEvent(magnifyEventSource: nil, magnification: 0, phase: .ended)?
                .post(tap: .cghidEventTap)
        }
    }
}
