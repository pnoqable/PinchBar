import Cocoa

protocol EventTapDelegate: AnyObject {
    func eventTapCreated(_ eventTap: EventTap)
    func eventTapUpdated(_ eventTap: EventTap)
}

class EventTap {
    static let unknownApp: String = "unknown Application"
    
    private var eventTap: CFMachPort?
    
    struct EventMapping: Codable {
        var rawFlags: CGEventFlags.RawValue
        var flags: CGEventFlags { CGEventFlags(rawValue: rawFlags) }
        var sensivity: Double
        static let defaults = EventMapping(rawFlags: CGEventFlags.maskCommand.rawValue, sensivity: 100)
        static let highSens = EventMapping(rawFlags: CGEventFlags.maskCommand.rawValue, sensivity: 250)
    }
    
    struct AppSettings: Codable {
        var eventMap: [CGEventFlags.RawValue: EventMapping]
        static let defaults = AppSettings(eventMap: [0: .defaults, CGEventFlags.maskShift.rawValue: .highSens])
    }
    
    private(set) var appSettings: [String: AppSettings] = ["Cubase": .defaults]
    private(set) var currentApp: String = EventTap.unknownApp
    private      var currentSettings: AppSettings?
    
    var isEnabled: Bool { currentSettings != nil }
    
    weak var delegate: EventTapDelegate?
    
    init() {
        if let settingsString = try? String(data: JSONEncoder().encode(appSettings), encoding: .utf8) {
            UserDefaults.standard.register(defaults: ["appSettings": settingsString])
        }
        
        if let string = UserDefaults.standard.object(forKey: "appSettings") as? String,
           let data = string.data(using: .utf8),
           let settings = try? JSONDecoder().decode([String: AppSettings].self, from: data) {
            self.appSettings = settings
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
        if appSettings.keys.contains(currentApp) {
            appSettings.removeValue(forKey: currentApp)
        } else {
            appSettings[currentApp] = AppSettings.defaults
        }
        
        if let settingsData = try? String(data: JSONEncoder().encode(appSettings), encoding: .utf8) {
            UserDefaults.standard.set(settingsData, forKey: "appSettings")
        }
        
        updateTap()
    }
    
    @objc private func updateTap() {
        currentApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? EventTap.unknownApp
        currentSettings = appSettings[currentApp]
        
        if let eventTap = eventTap {
            if isEnabled != CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: isEnabled)
            }
        } else {
            currentSettings = nil
        }
        
        delegate?.eventTapUpdated(self)
    }
    
    let modifierMask = UInt64.max << 8  // masks out left/right hints of modifier keys flags
    var remainder: Double = 0           // subpixel residue of sent (integer) scroll events
    
    private let field110 = CGEventField(rawValue: 110)! // type
    private let field113 = CGEventField(rawValue: 113)! // magnification
    private let field132 = CGEventField(rawValue: 132)! // phase
    private func tap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            updateTap()
        } else if event.getDoubleValueField(field110) == 8, // type == Magnify
                  let mapping = currentSettings?.eventMap[event.flags.rawValue & modifierMask] {
            
            if event.getDoubleValueField(field132) == 1 { // phase == Began
                remainder = 0
            }
            
            let magnification = event.getDoubleValueField(field113)
            let amount = mapping.sensivity * magnification + remainder
            let wheel = round(amount)
            remainder = amount - wheel
            let newEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                   wheelCount: 1, wheel1: Int32(wheel), wheel2: 0, wheel3: 0)!
            newEvent.flags = mapping.flags
            return Unmanaged.passRetained(newEvent)
        }
        
        return Unmanaged.passUnretained(event)
    }
}
