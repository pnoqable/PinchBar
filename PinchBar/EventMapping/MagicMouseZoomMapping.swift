import Cocoa

class MagicMouseZoomMapping: SettingsHolder<MagicMouseZoomMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var onMousepad: Int
        var sensivity: Double
    }
    
    var eventMask: CGEventMask { 1<<22 | 1<<5 }
    
    private lazy var mapScrollToPinch = MapScrollToPinchState(settings.onMousepad)
    
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
        
        if event.type == .mouseMoved, mapScrollToPinch.state == .mapping {
            return [event,
                    CGEvent(magnifyEventSource: nil, magnification: 0, phase: .changed)!.with(flags: event.flags)]
        }
        
        return [event]
    }
}

// MARK: - MapScrollToPinchState

protocol EventStateMachine {
    associatedtype State
    associatedtype Transition
    var state: State { get }
    func feed(_ event: CGEvent) -> Transition
}

class MapScrollToPinchState: EventStateMachine {
    enum State: Equatable {
        case inactive
        case mapping
        case dropMomentum(since: DispatchTime = .now())
        case dropScroll(since: DispatchTime)
        
        var isDropState: Bool {
            switch self {
            case .dropMomentum, .dropScroll: return true
            default:                         return false
            }
        }
    }
    
    enum Transition: Equatable {
        case finishMapping
        case finishDropping
        case other
    }
    
    private(set) var state: State = .inactive
    
    let onMousepad: Int
    
    init(_ onMousepad: Int) {
        self.onMousepad = onMousepad
    }
    
    func feed(_ event: CGEvent) -> Transition {
        let isShortlyAfter = { t in DispatchTime.now() < t + 0.1 }
        
        switch state {
        case .mapping where event.scrollPhase == .ended:
            state = .dropMomentum() // not since event.timestamp as it's broken on apple silicon
            return .finishMapping
        case let .dropMomentum(since: t) where event.scrollPhase == .began && isShortlyAfter(t):
            state = .dropScroll(since: t)
        case let .dropMomentum(since: t) where !event.momentumPhase && !isShortlyAfter(t)
            && Multitouch.onMousepad() != onMousepad:
            state = .inactive
        case let .dropScroll(since: t) where event.scrollPhase == .ended:
            state = .dropMomentum(since: t)
            return .finishDropping
        case let .dropScroll(since: t) where event.scrollPhase == .changed && !isShortlyAfter(t):
            state = .inactive
            event.scrollPhase = .began
        default:
            if event.scrollPhase == .began && Multitouch.onMousepad() == onMousepad {
                state = .mapping
            }
        }
        
        return .other
    }
}
