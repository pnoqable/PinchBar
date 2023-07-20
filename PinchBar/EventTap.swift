import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var callWhenCreated: Callback?
    var logEvents: Bool = false
    var preset: Preset?
    
    func start() {
        let adapter: CGEventTapCallBack = { proxy, type, event, userInfo in
            let mySelf = Unmanaged<EventTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return mySelf.tap(proxy: proxy, type: type, event: event)
        }
        
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        let eventMask = CGEventMask(1<<29 | 1<<22 | 0b11110) // trackpad, scroll and click events
        
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: eventMask,
                                     callback: adapter,
                                     userInfo: mySelf)
        
        guard let eventTap else {
            return DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: start)
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        callWhenCreated?()
        
        if !MultitouchSupportStart() {
            NSLog("Cannot start Multitouch Support")
        }
    }
    
    enum MapScrollToPinchState {
        case inProgress
        case dropMomentum(since: CGEventTimestamp)
        case dropScroll(since: CGEventTimestamp)
        case inactive(since: CGEventTimestamp)
        
        var isInProgress: Bool {
            switch self {
            case .inProgress: return true
            default: return false
            }
        }
        
        var dropEvent: Bool {
            switch self {
            case .dropMomentum(_), .dropScroll(_): return true
            default: return false
            }
        }
        
        func alreadyTimeFor(_ event: CGEvent) -> Bool {
            switch self {
            case .inProgress: return false
            case let .dropMomentum(t), let .dropScroll(t), let .inactive(t):
                return event.timestamp - t > 100_000_000
            }
        }
    }
    
    var mapScrollToPinchState = MapScrollToPinchState.inactive(since: 0)
    var isDroppingRightClick = false
    var isMappingMultitouchClick = false
    
    private func tap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        
        if event.type == .scrollWheel {
            var justFinishedMap = false
            var justFinishedDrop = false
            if event.scrollPhase == .began && MultitouchSupportIsTouchCount(-1, 2) &&
                mapScrollToPinchState.alreadyTimeFor(event) {
                mapScrollToPinchState = .inProgress
            } else if case .inProgress = mapScrollToPinchState, event.scrollPhase == .ended {
                mapScrollToPinchState = .dropMomentum(since: event.timestamp)
                justFinishedMap = true
            } else if case .dropMomentum = mapScrollToPinchState, !event.momentumPhase,
                      mapScrollToPinchState.alreadyTimeFor(event) {
                mapScrollToPinchState = .inactive(since: event.timestamp)
            } else if case let .dropMomentum(t) = mapScrollToPinchState, event.scrollPhase == .began,
                      !mapScrollToPinchState.alreadyTimeFor(event) {
                mapScrollToPinchState = .dropScroll(since: t)
            } else if case let .dropScroll(t) = mapScrollToPinchState, event.scrollPhase == .ended {
                mapScrollToPinchState = .dropMomentum(since: t)
                justFinishedDrop = true
            }
            
            if mapScrollToPinchState.isInProgress || justFinishedMap {
                guard event.scrollPhase != .other else { return nil }
                return logResult(.passRetained(
                    CGEvent(magnifyEventSource: nil,
                            magnification: 0.005 * Double(event.scrollPointDeltaAxis1),
                            phase: event.scrollPhase)?.withFlags(flags: event.flags)))
                .flatMap { result in
                    let result = result.takeUnretainedValue()
                    return tap(proxy: proxy, type: result.type, event: result)
                }
            } else if mapScrollToPinchState.dropEvent || justFinishedDrop {
                return logResult(nil)
            }
        }
        
        if .rightMouseDown ... .rightMouseUp ~= event.type {
            var justFinished = false
            if event.type == .rightMouseDown && mapScrollToPinchState.isInProgress {
                isDroppingRightClick = true
            } else if isDroppingRightClick && event.type == .rightMouseUp {
                isDroppingRightClick = false
                justFinished = true
            }
            
            if isDroppingRightClick || justFinished {
                return logResult(nil)
            }
        }
        
        if .leftMouseDown ... .leftMouseUp ~= event.type {
            var justFinished = false
            if event.type == .leftMouseDown && MultitouchSupportIsTouchCount(3, 2) {
                isMappingMultitouchClick = true
            } else if isMappingMultitouchClick && event.type == .leftMouseUp {
                isMappingMultitouchClick = false
                justFinished = true
            }
            
            if isMappingMultitouchClick || justFinished {
                event.type = event.type == .leftMouseDown ? .otherMouseDown : .otherMouseUp
                event.mouseButtonNumber = 2;
                logEvent(event)
            }
        }
        
        if let mapping = preset?[event] {
            return logResult(mapping.tap(event, proxy: proxy))
        }
        
        return .passUnretained(event)
    }
    
    var indicies: Set<Int> = []
    
    func logEvent(_ event: CGEvent?) {
        guard logEvents else { return }
        guard let event else { return NSLog("dropped...") }
        
        let pairs = (0 ..< 256).map { i in
            (i, event.getDoubleValueField(CGEventField(rawValue: i)!))
        }
        
        for (i, v) in pairs where v != 0 {
            indicies.insert(Int(i))
        }
        
        var strings = indicies.sorted().map { pairs[$0] }.map { (i,v) in "\(i)=\(v)" }
        
        if let nsEvent = NSEvent(cgEvent: event) {
            strings.append(nsEvent.debugDescription)
        }
        
        NSLog(strings.joined(separator: "\t"))
    }
    
    func logResult(_ event: Unmanaged<CGEvent>?) -> Unmanaged<CGEvent>? {
        logEvent(event?.takeUnretainedValue())
        return event
    }
}
