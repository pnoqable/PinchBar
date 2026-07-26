import Cocoa

class OtherMouseScrollMapping: SettingsHolder<(OtherMouseScrollMapping.Settings)>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var button: CGMouseButton
    }
    
    var eventMask: CGEventMask { 0b111001 << 22 | 0b11011110 }
    
    private var buttonDown = false
    private var deferredEvents: [CGEvent] = []
    private var mouseDeltaAbsSum: Int64 = 0
    private var mapScroll = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ∈ CGEventType.mouseDown, event.mouseButton == settings.button {
            buttonDown = true
            deferredEvents = [event]
            return []
        } else if buttonDown, event.type == .scrollWheel {
            
            if !mapScroll {
                guard deferredEvents.count > 0 else { return [] }
                mapScroll = true
                deferredEvents = []
            }
            
            return [CGEvent(scrollWheelEvent2Source: nil, units: event.scrollUnit, wheelCount: 2,
                            wheel1: event.scrollUnitsDeltaAxis2, wheel2: event.scrollUnitsDeltaAxis1,
                            wheel3: 0)!]
        } else if event.type ∈ CGEventType.mouseDragged, event.mouseButton == settings.button {
            if case let lastEvents = deferredEvents, lastEvents.count > 0 {
                mouseDeltaAbsSum += event.mouseDeltaAbsSum
                if mouseDeltaAbsSum < 5 {
                    deferredEvents = deferredEvents + event
                } else {
                    deferredEvents = []
                    return lastEvents + event
                }
            } else if mapScroll {
                event.type = .mouseMoved
                return [event]
            }
        } else if event.type ∈ CGEventType.mouseUp, event.mouseButton == settings.button {
            buttonDown = false
            if case let lastEvents = deferredEvents, lastEvents.count > 0 {
                deferredEvents = []
                return lastEvents + event
            }
        }
        
        return [event]
    }
}
