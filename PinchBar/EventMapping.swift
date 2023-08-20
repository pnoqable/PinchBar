import Cocoa

protocol EventMapping: Codable {
    func map(_ event: CGEvent) -> [CGEvent]
}

struct MiddleClickMapping: EventMapping {
    private static var isMappingMultitouchClick = false
    private static var skipTapEvent = false
    
    var onMousepad: Int
    var onTrackpad: Int
    
    var isTrackpadTapActive: Bool {
        UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")?.bool(forKey: "Clicking") ?? false
    }
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if .leftMouseDown ... .leftMouseUp ~= event.type {
            var justFinished = false
            if event.type == .leftMouseDown, onMousepad > 0 && Multitouch.onMousepad() == onMousepad
                || onTrackpad > 0 && Multitouch.onTrackpad() == onTrackpad {
                Self.isMappingMultitouchClick = true
            } else if Self.isMappingMultitouchClick && event.type == .leftMouseUp {
                Self.isMappingMultitouchClick = false
                justFinished = true
            }
            
            if Self.isMappingMultitouchClick || justFinished {
                event.type = event.type == .leftMouseDown ? .otherMouseDown : .otherMouseUp
                event.mouseButtonNumber = 2;
                Self.skipTapEvent = true
            }
        }
        
        return [event]
    }
    
    func onTrackpadTap() {
        if Self.skipTapEvent {
            Self.skipTapEvent = false
        } else if Multitouch.lastTouchCount() == onTrackpad && isTrackpadTapActive {
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

struct MouseZoomMapping: EventMapping {
    private static var mapScrollToPinch = MapScrollToPinchState()
    private static var isDroppingRightClick = false
    
    var sensivity: Double
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .scrollWheel {
            let transition = Self.mapScrollToPinch.feed(event)
            
            if Self.mapScrollToPinch.state == .mapping || transition == .finishMapping {
                guard event.scrollPhase != .other else { return [] }
                return [CGEvent(magnifyEventSource: nil,
                               magnification: sensivity * Double(event.scrollPointDeltaAxis1),
                               phase: event.scrollPhase)!.with(flags: event.flags)]
            } else if Self.mapScrollToPinch.isDropEvent || transition == .finishDropping {
                return []
            }
        }
        
        if .rightMouseDown ... .rightMouseUp ~= event.type {
            var justFinished = false
            if event.type == .rightMouseDown && Self.mapScrollToPinch.state == .mapping {
                Self.isDroppingRightClick = true
            } else if Self.isDroppingRightClick && event.type == .rightMouseUp {
                Self.isDroppingRightClick = false
                justFinished = true
            }
            
            if Self.isDroppingRightClick || justFinished {
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

struct PinchMapping: EventMapping {
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
