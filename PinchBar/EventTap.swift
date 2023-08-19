import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var mappings: [EventMapping] = []
    
    func start(callWhenCreated: @escaping Callback) {
        let eventMask = CGEventMask(1<<29 | 1<<22 | 0b11110) // trackpad, scroll and click events
        
        let adapter: CGEventTapCallBack = { proxy, _, event, userInfo in
            Unmanaged<EventTap>.fromOpaque(userInfo!).takeUnretainedValue().tap(event, proxy)
            return nil
        }
        
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: eventMask,
                                     callback: adapter,
                                     userInfo: mySelf)
        
        guard let eventTap else {
            let work = Weak(self, EventTap.start <- callWhenCreated).call
            return DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        callWhenCreated()
        
        Multitouch.setOnTrackpadTap {
            [weak self] in self?.mappings.filterForEach(MiddleClickMapping.onTrackpadTap <- ())
        }
        
        if !Multitouch.start() {
            NSLog("Cannot start Multitouch Support")
        }
    }
    
    private func tap(_ event: CGEvent, _ proxy: CGEventTapProxy) {
        if event.type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        } else {
            mappings.reduce([event]) { events, mapping in
                events.flatMap(mapping.map)
            }.forEach(CGEvent.tapPostEvent <- proxy)
        }
    }
}
