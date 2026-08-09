import Cocoa

class MiddleClickMapping: SettingsHolder<MiddleClickMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var onMousepad: Int
        var onTrackpad: Int
    }
    
    var eventMask: CGEventMask { 0b11011110 }
    
    private var mapMiddleClick = false
    private var skipTapEvent = false
    
    @UserDefault("Clicking", "com.apple.AppleMultitouchTrackpad") var isTrackpadTapActive = false
    
    required init(_ settings: Settings) {
        super.init(settings)
        
        Multitouch.shared?.setOnTrackpadTap(WeakFunc(self, MiddleClickMapping.onTrackpadTap).call)
    }
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ∈ .leftMouseDown ... .rightMouseUp {
            let mt = Multitouch.shared
            var justFinished = false
            if event.type ∈ [.leftMouseDown, .rightMouseDown],
               settings.onMousepad > 0 && mt?.onMousepad() == settings.onMousepad
                || settings.onTrackpad > 0 && mt?.onTrackpad() == settings.onTrackpad {
                mapMiddleClick = true
            } else if mapMiddleClick && event.type ∈ [.leftMouseUp, .rightMouseUp] {
                mapMiddleClick = false
                justFinished = true
            }
            
            if mapMiddleClick || justFinished {
                event.type = event.type ∈ [.leftMouseDown, .rightMouseDown] ? .otherMouseDown : .otherMouseUp
                event.mouseButton = .center
                skipTapEvent = true
            }
        }
        
        if mapMiddleClick && event.type ∈ [.leftMouseDragged, .rightMouseDragged] {
            event.type = .otherMouseDragged
            event.mouseButton = .center
        }
        
        return [event]
    }
    
    func onTrackpadTap() {
        if skipTapEvent {
            skipTapEvent = false
        } else if Multitouch.shared?.lastTouchCount() == settings.onTrackpad && isTrackpadTapActive {
            let event = CGEvent(mouseEventSource: nil,
                                mouseType: .otherMouseDown,
                                mouseCursorPosition: CGEvent(source: nil)!.location,
                                mouseButton: .center)!
            
            event.post(tap: .cghidEventTap)
            event.type = .otherMouseUp
            event.post(tap: .cghidEventTap)
        }
    }
}
