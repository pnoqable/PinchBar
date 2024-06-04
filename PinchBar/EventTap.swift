import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var mappings: [any EventMapping] = []
    
    init(callWhenStarted: @escaping Callback) {
        start(callWhenStarted: callWhenStarted)
    }
    
    deinit {
        // don't release members of this class, call NSApplication.shared.stop() instead.
        fatalError("ressources leaked")
    }
    
    private func start(callWhenStarted: @escaping Callback) {
        let eventMask = CGEventMask(1<<29 | 1<<22 | 0b111<<25 | 0b1000011011110) // trackpad, scroll, click and drag events
        
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
            let restart = Weak(self, EventTap.start <- callWhenStarted).call
            return DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: restart)
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        callWhenStarted()
        
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
