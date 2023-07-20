import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var preset: Preset?
    
    var callWhenCreated: Callback?
    
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
    }
    
    enum Zooming {
        case not
        case inTransaction
        case finished
    }
    
    var zooming = Zooming.not
    
    private func tap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        } else if let mapping = preset?[event] {
            debugEvent(event)
            let newEvent = mapping.tap(event, proxy: proxy)
            (newEvent?.takeUnretainedValue()).flatMap(debugEvent)
            return newEvent
        }
        
        if event.type == .scrollWheel {
            if event.scrollPhase == .began {
                if event.flags.isSuperset(of: .init(arrayLiteral: .maskCommand, .maskAlternate)) {
                    zooming = .inTransaction
                } else {
                    zooming = .not
                }
            }
            
            if zooming != .not && event.scrollPhase == .other {
                return nil
            }
            
            if zooming == .inTransaction {
                zooming = event.scrollPhase != .ended ? .inTransaction : .finished
                debugEvent(event)
                let newEvent = CGEvent(magnifyEventSource: nil,
                                       magnification: 0.005 * Double(event.scrollPointDeltaAxis1),
                                       phase: event.scrollPhase)?.withFlags(flags: .maskNoFlags)
                newEvent.flatMap(debugEvent)
                return .passRetained(newEvent)
            }
        }
        
        if .leftMouseDown ... .rightMouseUp ~= event.type {
            debugEvent(event)
            if zooming == .inTransaction {
                return nil
            }
        }
        
        return .passUnretained(event)
    }
    
    var indicies: Set<Int> = []
    
    func debugEvent(_ event: CGEvent) {
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
}
