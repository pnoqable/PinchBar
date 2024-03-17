import Cocoa

struct EventMapping: Codable {
    enum Replacement: Codable {
        case wheel
        case keys(codeA: CGKeyCode, codeB: CGKeyCode)
    }
    
    var replaceWith: Replacement?
    var flags: CGEventFlags
    var sensivity: Double
    
    func canTap(_ event: CGEvent) -> Bool { event.subType == .magnification }
    
    private static var remainder: Double = 0 // subpixel residue of sent (integer) scroll events
    
    func tap(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        assert(event.subType == .magnification)
        
        // when event is not to be replaced, just apply flags and sensivity:
        guard let replacement = replaceWith else {
            event.flags = flags
            event.magnification *= sensivity
            return .passUnretained(event)
        }
        
        if event.phase == .began {
            Self.remainder = 0
        }
        
        let magnification = sensivity * event.magnification + Self.remainder
        let steps = round(magnification)
        Self.remainder = magnification - steps
        
        guard steps != 0 else { return nil }
            
        switch replacement {
        case .wheel:
            let originalFlags = event.flags
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                wheelCount: 1, wheel1: Int32(steps), wheel2: 0, wheel3: 0)!
            event.flags = flags
            CGEvent(flagsChangedEventSource: nil, flags: flags)!.tapPostEvent(proxy)
            event.tapPostEvent(proxy)
            CGEvent(flagsChangedEventSource: nil, flags: originalFlags)?.tapPostEvent(proxy)
            return nil
        case .keys(let codeA, let codeB):
            let code = steps < 0 ? codeA : codeB
            sendKey(code, down: true, proxy: proxy)
            sendKey(code, down: false, proxy: proxy)
            return nil
        }
    }
    
    private func sendKey(_ code: CGKeyCode, down: Bool, proxy: CGEventTapProxy) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.tapPostEvent(proxy)
    }
}

extension EventMapping {
    static func pinchToPinch(flags: CGEventFlags = .maskNoFlags, sensivity: Double = 1) -> Self {
        Self(replaceWith: nil, flags: flags, sensivity: sensivity)
    }
    
    static func pinchToWheel(flags: CGEventFlags = .maskCommand, sensivity: Double = 200) -> Self {
        Self(replaceWith: .wheel, flags: flags, sensivity: sensivity)
    }
    
    static func pinchToKeys(flags: CGEventFlags = .maskCommand, sensivity: Double = 5,
                            codeA: CGKeyCode = 44, codeB: CGKeyCode = 30) -> Self {
        Self(replaceWith: .keys(codeA: codeA, codeB: codeB), flags: flags, sensivity: sensivity)
    }
}
