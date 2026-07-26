import Cocoa

class OtherMouseZoomMapping: SettingsHolder<OtherMouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var button: CGMouseButton
        var sensivity: Double
    }
    
    var eventMask: CGEventMask { 0b111001 << 22 | 0b11011110 }
    
    private var buttonDown = false
    private var deferredEvents: [CGEvent] = []
    private var mouseDeltaAbsSum: Int64 = 0
    private var mapScrollToPinch = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ∈ CGEventType.mouseDown, event.mouseButton == settings.button {
            buttonDown = true
            deferredEvents = [event]
            mouseDeltaAbsSum = 0
            return []
        } else if buttonDown, event.type == .scrollWheel {
            guard event.scrollPointDeltaAxis1 != 0 else { return [] }
            let phase: CGEvent.Phase = mapScrollToPinch ? .changed : .began
            
            if !mapScrollToPinch {
                guard deferredEvents.count > 0 else { return [] }
                mapScrollToPinch = true
                deferredEvents = []
            }
            
            return [CGEvent(magnifyEventSource: nil, 
                            magnification: settings.sensivity * Double(event.scrollPointDeltaAxis1),
                            phase: phase)!.with(flags: event.flags)]
        } else if event.type ∈ CGEventType.mouseDragged, event.mouseButton == settings.button {
            if case let lastEvents = deferredEvents, lastEvents.count > 0 {
                mouseDeltaAbsSum += event.mouseDeltaAbsSum
                if mouseDeltaAbsSum < 5 {
                    deferredEvents = deferredEvents + event
                } else {
                    deferredEvents = []
                    return lastEvents + event
                }
            } else if mapScrollToPinch {
                event.type = .mouseMoved
                return [event,
                        CGEvent(magnifyEventSource: nil, magnification: 0, phase: .changed)!.with(flags: .maskNoFlags)]
            }
        } else if event.type ∈ CGEventType.mouseUp, event.mouseButton == settings.button {
            buttonDown = false
            if case let lastEvents = deferredEvents, lastEvents.count > 0 {
                deferredEvents = []
                return lastEvents + event
            } else if mapScrollToPinch {
                mapScrollToPinch = false
                return [CGEvent(magnifyEventSource: nil, magnification: 0, phase: .ended)!.with(flags: event.flags)]
            }
        }
        
        return [event]
    }
}
