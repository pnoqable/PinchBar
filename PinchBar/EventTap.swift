import Cocoa

protocol EventTapDelegate: AnyObject {
    func eventTapCreated(_ eventTap: EventTap)
    func eventTapUpdated(_ eventTap: EventTap)
}

class EventTap {
    static let unknownApp: String = "unknown Application"
    
    private var eventTap: CFMachPort?
    
    struct AppSettings : Codable, Hashable {
        var eventMap: [CGEventFlags: EventMapping]
           
        func mapping(_ event: CGEvent) -> EventMapping? { eventMap[event.flags.purified] }
        
        static let defaults = Self(eventMap: [.maskNoFlags: .pinchToKeys(), .maskCommand: .pinchToPinch()])
        static let cubase = Self(eventMap: [.maskNoFlags: .pinchToWheel(),
                                            .maskAlternate: .pinchToKeys(flags: .maskAlternate, codeA: 5, codeB: 4),
                                            .maskCommand: .pinchToKeys(flags: .maskShift, codeA: 5, codeB: 4)])
    }
    
    private(set) var appSettings: [String: AppSettings] = ["Cubase": .cubase]
    
    private var groupedAppSettings: [[String]: AppSettings] {
        get {
            let inverse = Dictionary(appSettings.map { app, settings in (settings, [app]) }, uniquingKeysWith: +)
            return Dictionary(uniqueKeysWithValues: inverse.map { settings, apps in (apps, settings) })
        }
        set(newSettings) {
            let pairs = newSettings.flatMap { apps, settings in apps.map { app in (app, settings) } }
            appSettings = Dictionary(uniqueKeysWithValues: pairs)
        }
    }
    
    private(set) var currentApp: String = unknownApp
    private      var currentSettings: AppSettings?
    
    var isEnabled: Bool { currentSettings != nil }
    
    weak var delegate: EventTapDelegate?
    
    init() {
        if let settingsString = try? String(data: JSONEncoder().encode(appSettings), encoding: .utf8) {
            UserDefaults.standard.register(defaults: ["appSettings": settingsString])
        }
        
        if let string = UserDefaults.standard.object(forKey: "appSettings") as? String,
           let data = string.data(using: .utf8),
           let settings = try? JSONDecoder().decode([[String]:AppSettings].self, from: data) {
            self.groupedAppSettings = settings
        }
        
        NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(updateTap),
                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    func start() {
        let adapter: CGEventTapCallBack = { proxy, type, event, userInfo in
            let mySelf = Unmanaged<EventTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return mySelf.tap(proxy: proxy, type: type, event: event)
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
            updateTap()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: start)
        }
    }
    
    func toggleApp() {
        if appSettings.keys.contains(currentApp) {
            appSettings.removeValue(forKey: currentApp)
        } else {
            appSettings[currentApp] = .defaults
        }
        
        if let settingsData = try? String(data: JSONEncoder().encode(groupedAppSettings), encoding: .utf8) {
            UserDefaults.standard.set(settingsData, forKey: "appSettings")
        }
        
        updateTap()
    }
    
    @objc private func updateTap() {
        currentApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? Self.unknownApp
        
        if let eventTap = eventTap {
            currentSettings = appSettings[currentApp]
            if isEnabled != CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: isEnabled)
            }
        } else {
            currentSettings = nil
        }
        
        delegate?.eventTapUpdated(self)
    }
    
    private func tap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            updateTap()
        } else if let mapping = currentSettings?.mapping(event), mapping.canTap(event) {
            return mapping.tap(event, proxy: proxy)
        }
        
        return .passUnretained(event)
    }
}
