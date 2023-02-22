import Cocoa

class EventTap {
    private var eventTap: CFMachPort?
    
    var callWhenCreated: Callback?
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
    
    var mapScrollToPinch = MapScrollToPinchState()
    var isMappingMultitouchClick = false
    
    private func tap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        
        if event.type == .scrollWheel {
            let transition = mapScrollToPinch.feed(event)
            
            if mapScrollToPinch.state == .mapping || transition == .finishMapping {
                guard event.scrollPhase != .other else { return nil }
                return .passRetained(
                    CGEvent(magnifyEventSource: nil,
                            magnification: 0.005 * Double(event.scrollPointDeltaAxis1),
                            phase: event.scrollPhase)?.withFlags(flags: event.flags))
                .flatMap { result in
                    let result = result.takeUnretainedValue()
                    return tap(proxy: proxy, type: result.type, event: result)
                }
            } else if mapScrollToPinch.state.isDropState || transition == .finishDropping {
                return nil
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
            }
        }
        
        if let mapping = preset?[event] {
            return mapping.tap(event, proxy: proxy)
        }
        
        return .passUnretained(event)
    }
}
