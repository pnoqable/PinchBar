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

class MagicMouseZoomMapping: SettingsHolder<MagicMouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable {
        var sensivity: Double
    }
    
    private var mapScrollToPinch = MapScrollToPinchState()
    private var dropRightClick = false
    
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
        
        if .rightMouseDown ... .rightMouseUp ~= event.type {
            var justFinished = false
            if event.type == .rightMouseDown && mapScrollToPinch.state == .mapping {
                dropRightClick = true
            } else if dropRightClick && event.type == .rightMouseUp {
                dropRightClick = false
                justFinished = true
            }
            
            if dropRightClick || justFinished {
                return []
            }
        }
        
        return [event]
    }
}

class MiddleClickMapping: SettingsHolder<MiddleClickMapping.Settings>, EventMapping {
    struct Settings: Codable {
        var onMousepad: Int
        var onTrackpad: Int
    }
    
    private var mapMiddleClick = false
    private var skipTapEvent = false
    
    @UserDefault("Clicking", "com.apple.AppleMultitouchTrackpad") var isTrackpadTapActive = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if .leftMouseDown ... .rightMouseUp ~= event.type {
            var justFinished = false
            if [.leftMouseDown, .rightMouseDown].contains(event.type),
               settings.onMousepad > 0 && Multitouch.onMousepad() == settings.onMousepad
                || settings.onTrackpad > 0 && Multitouch.onTrackpad() == settings.onTrackpad {
                mapMiddleClick = true
            } else if mapMiddleClick && [.leftMouseUp, .rightMouseUp].contains(event.type) {
                mapMiddleClick = false
                justFinished = true
            }
            
            if mapMiddleClick || justFinished {
                event.type = [.leftMouseDown, .rightMouseDown].contains(event.type) ? .otherMouseDown : .otherMouseUp
                event.mouseButton = .center
                skipTapEvent = true
            }
        }
        
        if mapMiddleClick && [.leftMouseDragged, .rightMouseDragged].contains(event.type) {
            event.type = .otherMouseDragged
            event.mouseButton = .center
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
            }
            
            if isOneAndAHalfTap {
                return [CGEvent(flagsChangedEventSource: nil, flags: settings.oneAndAHalfTapFlags)!,
                        event.with(flags: settings.oneAndAHalfTapFlags),
                        CGEvent(flagsChangedEventSource: nil, flags: event.flags)!]
            } else if isDoubleTap {
                return [CGEvent(flagsChangedEventSource: nil, flags: settings.doubleTapFlags)!,
                        event.with(flags: settings.doubleTapFlags),
                        CGEvent(flagsChangedEventSource: nil, flags: event.flags)!]
            }
        }
        
        return [event]
    }
}

class OtherMouseZoomMapping: SettingsHolder<OtherMouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable {
        var button: CGMouseButton
        var noClicks: Bool
        var sensivity: Double
        var minimalDrag: Int
    }
    
    private var clickLocation: CGPoint? = nil
    private var mapScrollToPinch = false
    
    func map(_ event: CGEvent) -> [CGEvent] {
        if event.type ==  .otherMouseDown, event.mouseButton == settings.button {
            clickLocation = event.location
            mapScrollToPinch = false
            if settings.noClicks {
                return []
            }
        } else if event.type == .otherMouseUp, event.mouseButton == settings.button {
            clickLocation = nil
            if mapScrollToPinch {
                mapScrollToPinch = false
                return [CGEvent(magnifyEventSource: nil, magnification: 0, phase: .ended)!]
            } else if settings.noClicks {
                return []
            }
        } else if let lastLocation = clickLocation, event.type == .otherMouseDragged,
                  event.mouseButton == settings.button {
            clickLocation = event.location
            if settings.noClicks {
                return []
            } else if mapScrollToPinch, event.mouseDeltaSumAbs >= settings.minimalDrag {
                mapScrollToPinch = false
                return [CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                mouseCursorPosition: lastLocation, mouseButton: settings.button)!,
                        event]
            }
        } else if let clickLocation, event.type == .scrollWheel {
            guard event.scrollPhase == .other else { return [] }
            let zoom = settings.sensivity * Double(event.scrollPointDeltaAxis1)
            if !mapScrollToPinch {
                mapScrollToPinch = true
                if settings.noClicks {
                    return [CGEvent(magnifyEventSource: nil, magnification: zoom, phase: .began)!]
                } else {
                    return [CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                                    mouseCursorPosition: clickLocation, mouseButton: settings.button)!,
                            CGEvent(magnifyEventSource: nil, magnification: zoom, phase: .began)!]
                }
            } else {
                return [CGEvent(magnifyEventSource: nil, magnification: zoom, phase: .changed)!]
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
        
        guard steps != 0 else { return [] }
        
        switch replacement {
        case .wheel:
            return [CGEvent(flagsChangedEventSource: nil, flags: settings.flags)!,
                    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: Int32(steps), wheel2: 0, wheel3: 0)!.with(flags: settings.flags),
                    CGEvent(flagsChangedEventSource: nil, flags: event.flags)!]
        case .keys(let codeA, let codeB):
            let code = steps < 0 ? codeA : codeB
            return [CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!,
                    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!]
                .map { $0.with(flags: settings.flags) }
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
