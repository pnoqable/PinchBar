import Cocoa

class MultiTapMapping: SettingsHolder<MultiTapMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var oneAndAHalfTapFlags: CGEventFlags
        var doubleTapFlags: CGEventFlags
    }
    
    var eventMask: CGEventMask { 1 << 29 }
    
    private var isOneAndAHalfTap = false
    private var isDoubleTap = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.subtype == .magnify {
            if event.magnificationPhase == .began {
                isOneAndAHalfTap = Multitouch.isOneAndAHalfTap()
                isDoubleTap      = Multitouch.isDoubleTap()
            } else if event.magnificationPhase == .ended {
                isOneAndAHalfTap = false
                isDoubleTap      = false
            }
            
            if isOneAndAHalfTap {
                return [event.with(flags: settings.oneAndAHalfTapFlags)]
            } else if isDoubleTap {
                return [event.with(flags: settings.doubleTapFlags)]
            }
        }
        
        return [event]
    }
}
