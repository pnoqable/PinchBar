import Cocoa

class OtherMouseZoomMapping: SettingsHolder<OtherMouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var button: CGMouseButton
        var sensivity: Double
    }
    
    var eventMask: CGEventMask { 0b111001 << 22 }
    
    private var buttonDown = false
    private var deferredClick: CGEvent? = nil
    private var mapScrollToPinch = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .otherMouseDown, event.mouseButton == settings.button {
            buttonDown = true
            deferredClick = event
            return []
        } else if buttonDown, event.type == .scrollWheel {
            guard event.scrollPointDeltaAxis1 != 0 else { return [] }
            let phase: CGEvent.Phase = mapScrollToPinch ? .changed : .began
            
            if !mapScrollToPinch {
                guard deferredClick != nil else { return [] }
                mapScrollToPinch = true
                deferredClick = nil
            }
            
            return [CGEvent(magnifyEventSource: nil, 
                            magnification: settings.sensivity * Double(event.scrollPointDeltaAxis1),
                            phase: phase)!.with(flags: event.flags)]
        } else if event.type == .otherMouseDragged, event.mouseButton == settings.button {
            guard event.mouseDeltaX != 0 || event.mouseDeltaY != 0 else { return [] }
            if let lastEvent = deferredClick {
                deferredClick = nil
                return [lastEvent, event]
            } else if mapScrollToPinch {
                event.type = .mouseMoved
                return [event,
                        CGEvent(magnifyEventSource: nil, magnification: 0, phase: .changed)!.with(flags: .maskNoFlags)]
            }
        } else if event.type == .otherMouseUp, event.mouseButton == settings.button {
            buttonDown = false
            if let deferredClick {
                return [deferredClick, event]
            } else if mapScrollToPinch {
                mapScrollToPinch = false
                return [CGEvent(magnifyEventSource: nil, magnification: 0, phase: .ended)!.with(flags: event.flags)]
            }
        }
        
        return [event]
    }
}
