import Cocoa

protocol EventTapDelegate: AnyObject {
    func eventTapCreated(_ eventTap: EventTap)
    func eventTapUpdated(_ eventTap: EventTap)
}

class EventTap {
    static let unknownApp: String = "unknown Application"
    
    private var eventTap: CFMachPort?
    
    private(set) var apps: [String:Bool] = ["Cubase":true]
    private(set) var currentApp: String = EventTap.unknownApp
    private(set) var isEnabled: Bool = false
    
    weak var delegate: EventTapDelegate?
    
    init() {
        UserDefaults.standard.register(defaults: ["apps":apps])
        if let apps = UserDefaults.standard.object(forKey: "apps") as? [String:Bool] {
            self.apps = apps
        }
        
        NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(updateTap),
                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    func start() {
        let adapter: CGEventTapCallBack = { _, type, event, userInfo in
            let mySelf = Unmanaged<EventTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return mySelf.tap(type: type, event: event)
        }
        
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest:  1<<29,
                                     callback: adapter,
                                     userInfo: mySelf)
        
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            delegate?.eventTapCreated(self)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: start)
        }
        
        updateTap()
    }
    
    func toggleApp() {
        if apps.keys.contains(currentApp) {
            apps.removeValue(forKey: currentApp)
        } else {
            apps[currentApp] = true
        }
        
        UserDefaults.standard.set(apps, forKey: "apps")
        
        updateTap()
    }
    
    @objc private func updateTap() {
        currentApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? EventTap.unknownApp
        isEnabled = apps.keys.contains(currentApp)
        
        if let eventTap = eventTap {
            if isEnabled != CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: isEnabled)
            }
        } else {
            isEnabled = false
        }
        
        delegate?.eventTapUpdated(self)
    }
    
    private func tap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            updateTap()
        } else if let nsEvent = NSEvent.init(cgEvent: event), nsEvent.type == .magnify {
            let amount = Int32(round(nsEvent.deltaZ))
            let newEvent = CGEvent.init(scrollWheelEvent2Source: nil, units: .pixel,
                                        wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0)!
            newEvent.flags = .maskCommand
            return Unmanaged.passRetained(newEvent)
        }
        
        return Unmanaged.passUnretained(event)
    }
}
