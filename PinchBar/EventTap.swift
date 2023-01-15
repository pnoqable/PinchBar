import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var preset: Settings.Preset?
    
    var callWhenCreated: Callback?
    
    func start() {
        let adapter: CGEventTapCallBack = { proxy, type, event, userInfo in
            let mySelf = Unmanaged<EventTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return mySelf.tap(proxy: proxy, type: type, event: event)
        }
        
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest:  1<<29, // trackpad events only
                                     callback: adapter,
                                     userInfo: mySelf)
        
        guard let eventTap else {
            return DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: start)
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        callWhenCreated?()
    }
    
    private func tap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        } else if let mapping = preset?[event.flags.purified], mapping.canTap(event) {
            return mapping.tap(event, proxy: proxy)
        }
        
        return .passUnretained(event)
    }
}
