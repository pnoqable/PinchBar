import Cocoa

protocol EventMapping {
    func map(_ event: CGEvent) -> [CGEvent]
}

struct MiddleClickMapping: EventMapping {
    private static var mapMiddleClick = false
    
    var onMousepad: Int
    var onTrackpad: Int
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ∈ .leftMouseDown ... .rightMouseUp {
            var justFinished = false
            if event.type ∈ [.leftMouseDown, .rightMouseDown],
               onMousepad > 0 && Multitouch.onMousepad() == onMousepad
                || onTrackpad > 0 && Multitouch.onTrackpad() == onTrackpad {
                Self.mapMiddleClick = true
            } else if Self.mapMiddleClick && event.type ∈ [.leftMouseUp, .rightMouseUp] {
                Self.mapMiddleClick = false
                justFinished = true
            }
            
            if Self.mapMiddleClick || justFinished {
                event.type = event.type ∈ [.leftMouseDown, .rightMouseDown] ? .otherMouseDown : .otherMouseUp
                event.mouseButtonNumber = 2;
            }
        }
        
        return [event]
    }
}

struct MouseZoomMapping: EventMapping {
    private static var mapScrollToPinch = MapScrollToPinchState()
    
    var sensivity: Double
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .scrollWheel {
            let transition = Self.mapScrollToPinch.feed(event)
            
            if Self.mapScrollToPinch.state == .mapping || transition == .finishMapping {
                guard event.scrollPhase != .other else { return [] }
                return [CGEvent(magnifyEventSource: nil,
                                magnification: sensivity * Double(event.scrollPointDeltaAxis1),
                                phase: event.scrollPhase)!.with(flags: event.flags)]
            } else if Self.mapScrollToPinch.state.isDropState || transition == .finishDropping {
                return []
            }
        }
        
        return [event]
    }
}

struct MultiTapMapping: EventMapping {
    var oneAndAHalfTapFlags: CGEventFlags
    var doubleTapFlags: CGEventFlags
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.subtype == .magnify {
            if Multitouch.isOneAndAHalfTap() {
                event.flags = oneAndAHalfTapFlags
            } else if Multitouch.isDoubleTap() {
                event.flags = doubleTapFlags
            }
        }
        
        return [event]
    }
}

struct PinchMapping: EventMapping, Codable {
    enum Replacement: Codable {
        case wheel
        case keys(codeA: CGKeyCode, codeB: CGKeyCode)
    }
    
    var replaceWith: Replacement?
    var flags: CGEventFlags
    var sensivity: Double
    
    private static var remainder: Double = 0 // subpixel residue of sent (integer) scroll events
    
    func map(_ event: CGEvent) -> [CGEvent] {
        guard event.subtype == .magnify else { return [event] }
        
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

extension PinchMapping {
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
