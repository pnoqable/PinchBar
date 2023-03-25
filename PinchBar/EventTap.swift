import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var callWhenCreated: Callback?
    var mappings: [EventMapping] = []
    
    func start() {
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
            return DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: start)
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        callWhenCreated?()
        
        if !MultitouchSupportStart() {
            NSLog("Cannot start Multitouch Support")
        }
    }
    
    private func tap(_ event: CGEvent, _ proxy: CGEventTapProxy) {
        if event.type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        } else {
            mappings.reduce([event]) { events, mapping in
                events.flatMap(mapping.map)
            }.forEach { tappedEvent in
                tappedEvent.tapPostEvent(proxy)
            }
        }
    }
}
