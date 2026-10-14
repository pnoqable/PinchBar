import Cocoa

/// Maps the right Option key to the right Control key, so shortcuts like
/// Ctrl+←/→ (switch desktop) work on keyboards without a right Control key.
class RightOptToCtrlMapping: SettingsHolder<RightOptToCtrlMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {}
    
    var eventMask: CGEventMask { 1<<12 | 1<<11 | 1<<10 } // flagsChanged, keyUp, keyDown
    
    private static let rightOption:  CGKeyCode = 0x3D // kVK_RightOption
    private static let rightControl: CGKeyCode = 0x3E // kVK_RightControl
    
    func map(_ event: CGEvent) -> [CGEvent] {
        let flags = event.flags.mappingRightOptionToControl
        
        // modifier keys only emit flagsChanged events, so the key code has to be translated as well
        if event.type == .flagsChanged, event.keyCode == Self.rightOption {
            let result = event.with(flags: flags)
            result.keyCode = Self.rightControl
            return [result]
        }
        
        guard flags != event.flags else { return [event] }
        return [event.with(flags: flags)]
    }
}

extension CGEventFlags {
    /// Replaces a held right Option with right Control, keeping left Option intact when both are pressed.
    /// Needed because subsequent key events carry the raw hardware flags, not the translated ones.
    var mappingRightOptionToControl: Self {
        guard contains(.deviceRightOption) else { return self }
        
        var flags = subtracting(.deviceRightOption)
        flags.insert(.deviceRightControl)
        flags.insert(.maskControl)
        
        if !contains(.deviceLeftOption) {
            flags.remove(.maskAlternate)
        }
        
        return flags
    }
}
