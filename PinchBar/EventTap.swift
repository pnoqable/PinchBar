import Cocoa

class EventTap {
    private let eventTap: CFMachPort
    private let runLoopSource: CFRunLoopSource
    private let weakSelf = WeakVar<EventTap>()
    
    let mapping: any EventMapping
    
    init?(mapping: any EventMapping) {
        self.mapping = mapping
        
        let adapter: CGEventTapCallBack = { proxy, _, event, userInfo in
            Unmanaged<WeakVar<EventTap>>.fromOpaque(userInfo!).takeUnretainedValue().instance?.tap(event, proxy)
            return nil
        }
        
        if let eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                            place: .tailAppendEventTap,
                                            options: .defaultTap,
                                            eventsOfInterest: mapping.eventMask,
                                            callback: adapter,
                                            userInfo: Unmanaged.passUnretained(weakSelf).toOpaque()) {
            self.eventTap = eventTap
        } else {
            return nil
        }
        
        if let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) {
            self.runLoopSource = runLoopSource
        } else {
            CFMachPortInvalidate(eventTap)
            return nil
        }
        
        weakSelf.instance = self
        
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    
    deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFMachPortInvalidate(eventTap)
    }
    
    private func tap(_ event: CGEvent, _ proxy: CGEventTapProxy) {
        if event.type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            mapping.map(event).forEach(CGEvent.tapPostEvent <-- proxy)
        }
    }
}
