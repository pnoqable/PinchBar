import Cocoa

class MultiClickMapping: SettingsHolder<MultiClickMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var button: CGMouseButton
        var doubleClickFlags: CGEventFlags
        var tripleClickFlags: CGEventFlags
    }
    
    var eventMask: CGEventMask { 0b11001 << 22 | 0b11110 }
    
    private var flags: CGEventFlags? = nil
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ∈ CGEventType.mouseDown && event.mouseButton == settings.button {
            flags = [2: settings.doubleClickFlags, 3: settings.tripleClickFlags][event.mouseClickState]
        } else if let flags, event.type == .scrollWheel {
            return [event.with(flags: flags)]
        } else if event.type ∈ CGEventType.mouseUp && event.mouseButton == settings.button {
            flags = nil
        }
        
        return [event]
    }
}
