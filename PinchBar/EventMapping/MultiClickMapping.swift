import Cocoa

class MultiClickMapping: SettingsHolder<MultiClickMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var button: CGMouseButton
        var doubleClickFlags: CGEventFlags
        var tripleClickFlags: CGEventFlags
    }
    
    var eventMask: CGEventMask { 0b11001 << 22 }
    
    private var flags: CGEventFlags? = nil
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .otherMouseDown {
            flags = [2: settings.doubleClickFlags, 3: settings.tripleClickFlags][event.mouseClickState]
        } else if let flags, event.type == .scrollWheel {
            return [event.with(flags: flags)]
        } else if event.type == .otherMouseUp {
            flags = nil
        }
        
        return [event]
    }
}
