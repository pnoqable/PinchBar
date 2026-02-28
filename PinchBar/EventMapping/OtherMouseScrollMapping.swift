import Cocoa

class OtherMouseScrollMapping: SettingsHolder<(OtherMouseScrollMapping.Settings)>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var button: CGMouseButton
        var noClicks: Bool
    }
    
    var eventMask: CGEventMask { 0b111001 << 22 }
    
    private var buttonDown = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .otherMouseDown, event.mouseButton == settings.button {
            buttonDown = true
            if settings.noClicks {
                return []
            }
        } else if event.type == .otherMouseUp, event.mouseButton == settings.button {
            buttonDown = false
            if settings.noClicks {
                return []
            }
        } else if buttonDown, event.type == .scrollWheel {
            return [CGEvent(scrollWheelEvent2Source: nil, units: event.scrollUnit, wheelCount: 2,
                            wheel1: 0, wheel2: event.scrollUnitsDeltaAxis1, wheel3: 0)!]
        } else if buttonDown, event.type == .otherMouseDragged,
                  event.mouseButton == settings.button, settings.noClicks {
            return []
        }
        
        return [event]
    }
}
