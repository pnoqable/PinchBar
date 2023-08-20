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
        case dropMomentum(since: CGEventTimestamp)
        case dropScroll(since: CGEventTimestamp)
    }
    
    enum Transition: Equatable {
        case finishMapping
        case finishDropping
        case other
    }
    
    private(set) var state: State = .inactive
    
    var isDropEvent: Bool {
        switch state {
        case .dropMomentum, .dropScroll: return true
        default: return false
        }
    }
    
    func feed(_ event: CGEvent) -> Transition {
        let isShortlyAfter = { t in event.timestamp - t < 100_000_000 }
        
        switch state {
        case .mapping where event.scrollPhase == .ended:
            state = .dropMomentum(since: event.timestamp)
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
