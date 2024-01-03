import Cocoa

protocol EventMapping: Codable {
    associatedtype Settings: Codable
    var settings: Settings { get }
    
    init(_ settings: Settings)
    
    func map(_ event: CGEvent) -> [CGEvent]
}

extension EventMapping {
    init(from decoder: Decoder) throws {
        try self.init(Settings(from: decoder))
    }
    
    func encode(to encoder: Encoder) throws {
        try settings.encode(to: encoder)
    }
}

class SettingsHolder<Settings> {
    let settings: Settings
    
    required init(_ settings: Settings) {
        self.settings = settings
    }
}

class MiddleClickMapping: SettingsHolder<MiddleClickMapping.Settings>, EventMapping {
    struct Settings: Codable {
        var onMousepad: Int
        var onTrackpad: Int
    }
    
    private var mapMiddleClick = false
    private var skipTapEvent = false
    
    private var isTrackpadTapActive: Bool {
        UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")?.bool(forKey: "Clicking") ?? false
    }
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ∈ .leftMouseDown ... .rightMouseUp {
            var justFinished = false
            if event.type ∈ [.leftMouseDown, .rightMouseDown],
               settings.onMousepad > 0 && Multitouch.onMousepad() == settings.onMousepad
                || settings.onTrackpad > 0 && Multitouch.onTrackpad() == settings.onTrackpad {
                mapMiddleClick = true
            } else if mapMiddleClick && event.type ∈ [.leftMouseUp, .rightMouseUp] {
                mapMiddleClick = false
                justFinished = true
            }
            
            if mapMiddleClick || justFinished {
                event.type = event.type ∈ [.leftMouseDown, .rightMouseDown] ? .otherMouseDown : .otherMouseUp
                event.mouseButtonNumber = 2;
                skipTapEvent = true
            }
        }
        
        return [event]
    }
    
    func onTrackpadTap() {
        if skipTapEvent {
            skipTapEvent = false
        } else if Multitouch.lastTouchCount() == settings.onTrackpad && isTrackpadTapActive {
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

class MouseZoomMapping: SettingsHolder<MouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable {
        var sensivity: Double
    }
    
    private var mapScrollToPinch = MapScrollToPinchState()
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type == .scrollWheel {
            let transition = mapScrollToPinch.feed(event)
            
            if mapScrollToPinch.state == .mapping || transition == .finishMapping {
                guard event.scrollPhase != .other else { return [] }
                return [CGEvent(magnifyEventSource: nil,
                                magnification: settings.sensivity * Double(event.scrollPointDeltaAxis1),
                                phase: event.scrollPhase)!.with(flags: event.flags)]
            } else if mapScrollToPinch.state.isDropState || transition == .finishDropping {
                return []
            }
        }
        
        return [event]
    }
}

class MultiTapMapping: SettingsHolder<MultiTapMapping.Settings>, EventMapping {
    struct Settings: Codable {
        var oneAndAHalfTapFlags: CGEventFlags
        var doubleTapFlags: CGEventFlags
    }
    
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

class PinchMapping: SettingsHolder<PinchMapping.Settings>, EventMapping {
    struct Settings: Codable {
        enum Replacement: Codable {
            case wheel
            case keys(codeA: CGKeyCode, codeB: CGKeyCode)
        }
        
        var replaceWith: Replacement?
        var flags: CGEventFlags
        var sensivity: Double
    }
    
    private var remainder: Double = 0 // subpixel residue of sent (integer) scroll events
    
    func map(_ event: CGEvent) -> [CGEvent] {
        guard event.subtype == .magnify else { return [event] }
        
        // when event is not to be replaced, just apply flags and sensivity:
        guard let replacement = settings.replaceWith else {
            event.magnification *= settings.sensivity
            return [event.with(flags: settings.flags)]
        }
        
        if event.magnificationPhase == .began {
            remainder = 0
        }
        
        let magnification = settings.sensivity * event.magnification + remainder
        let steps = round(magnification)
        remainder = magnification - steps
        
        if steps == 0 {
            return event.magnificationPhase != .ended ? [] :
            [CGEvent(flagsChangedEventSource: nil, flags: event.flags)!]
        }
        
        switch replacement {
        case .wheel:
            return [CGEvent(flagsChangedEventSource: nil, flags: settings.flags)!,
                    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: Int32(steps), wheel2: 0, wheel3: 0)!.with(flags: settings.flags),
                    CGEvent(flagsChangedEventSource: nil, flags: event.flags)!]
        case .keys(let codeA, let codeB):
            let code = steps < 0 ? codeA : codeB
            return [CGEvent(flagsChangedEventSource: nil, flags: settings.flags)!,
                    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!.with(flags: settings.flags),
                    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!.with(flags: settings.flags),
                    CGEvent(flagsChangedEventSource: nil, flags: event.flags)!]
        }
    }
}

extension PinchMapping.Settings {
    static func pinchToPinch(flags: CGEventFlags = .maskNoFlags, sensivity: Double = 1) -> Self {
        Self(replaceWith: nil, flags: flags, sensivity: sensivity)
    }
    
    static func pinchToWheel(flags: CGEventFlags = .maskCommand, sensivity: Double = 200) -> Self {
        Self(replaceWith: .wheel, flags: flags, sensivity: sensivity)
    }
    
    static func pinchToKeys(codeA: CGKeyCode = 44, codeB: CGKeyCode = 30,
                            flags: CGEventFlags = .maskCommand, sensivity: Double = 5) -> Self {
        Self(replaceWith: .keys(codeA: codeA, codeB: codeB), flags: flags, sensivity: sensivity)
    }
}
