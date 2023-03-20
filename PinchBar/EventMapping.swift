import Cocoa

struct EventMapping: Codable {
    enum Replacement: Codable {
        case wheel
        case keys(codeA: CGKeyCode, codeB: CGKeyCode)
    }
    
    var replaceWith: Replacement?
    var flags: CGEventFlags
    var sensivity: Double
    
    static func canTap(_ event: CGEvent) -> Bool { event.subtype == .magnify }
    
    private static var remainder: Double = 0 // subpixel residue of sent (integer) scroll events
    
    func tap(_ event: CGEvent) -> [CGEvent] {
        assert(event.subtype == .magnify)
        
        // when event is not to be replaced, just apply flags and sensivity:
        guard let replacement = replaceWith else {
            event.magnification *= sensivity
            return [event.with(flags: flags)]
        }
        
        if event.magnificationPhase == .began {
            Self.remainder = 0
        }
        
        let magnification = sensivity * event.magnification + Self.remainder
        let steps = round(magnification)
        Self.remainder = magnification - steps
        
        guard steps != 0 else { return [] }
            
        switch replacement {
        case .wheel:
            return [CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: Int32(steps), wheel2: 0, wheel3: 0)!.with(flags: flags)]
        case .keys(let codeA, let codeB):
            let code = steps < 0 ? codeA : codeB
            return [CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!,
                    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!]
                .map { $0.with(flags: flags) }
        }
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
