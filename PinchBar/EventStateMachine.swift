import Cocoa

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
    
    func feed(_ event: CGEvent) -> Transition {
        let isShortlyAfter = { t in DispatchTime.now() < t + 0.1 }
        
        switch state {
        case .mapping where event.scrollPhase == .ended:
            state = .dropMomentum() // not since event.timestamp as it's broken on apple silicon
            return .finishMapping
        case let .dropMomentum(since: t) where event.scrollPhase == .began && isShortlyAfter(t):
            state = .dropScroll(since: t)
        case let .dropMomentum(since: t) where !event.momentumPhase && !isShortlyAfter(t)
            && Multitouch.onMousepad() != 2:
            state = .inactive
        case let .dropScroll(since: t) where event.scrollPhase == .ended:
            state = .dropMomentum(since: t)
            return .finishDropping
        case let .dropScroll(since: t) where event.scrollPhase == .changed && !isShortlyAfter(t):
            state = .inactive
            event.scrollPhase = .began
        default:
            if event.scrollPhase == .began && Multitouch.onMousepad() == 2 {
                state = .mapping
            }
        }
        
        return .other
    }
}
