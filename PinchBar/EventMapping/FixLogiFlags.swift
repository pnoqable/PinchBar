import Cocoa

class FixLogiFlags: SettingsHolder<FixLogiFlags.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {}
    
    var eventMask: CGEventMask { 1<<22 | 1<<12 }
    
    private var currentModifiers: CGEventFlags?
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .flagsChanged {
            currentModifiers = event.flags.justModifiers
        } else if let currentModifiers, currentModifiers != event.flags.justModifiers {
            event.flags = currentModifiers
        }
        
        return [event]
    }
}
