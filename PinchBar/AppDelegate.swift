import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var menuItemPreferences: NSMenuItem!
    var menuItemConfigure: NSMenuItem!
    var eventTap: CFMachPort?
    
    var apps: [String:Bool] = ["Cubase":true]
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        UserDefaults.standard.register(defaults: ["apps":apps])
        apps = UserDefaults.standard.object(forKey: "apps") as! [String:Bool]
        
        NSLog("Enabled for: \(apps.keys)")
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.button?.toolTip = "PinchBar"
        statusItem.behavior = .removalAllowed
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        
        let menuItemAbout = NSMenuItem()
        menuItemAbout.title = "About PinchBar"
        menuItemAbout.target = self
        menuItemAbout.action = #selector(openGitHub)
        statusItem.menu?.addItem(menuItemAbout)
        
        statusItem.menu?.addItem(NSMenuItem.separator())
        
        menuItemPreferences = NSMenuItem()
        menuItemPreferences.title = "Enable Pinchbar in Accessibility"
        menuItemPreferences.target = self
        menuItemPreferences.action = #selector(accessibility)
        statusItem.menu?.addItem(menuItemPreferences)
        
        menuItemConfigure = NSMenuItem()
        menuItemConfigure.title = "Enable for Application"
        menuItemConfigure.target = self
        menuItemConfigure.action = #selector(configure)
        menuItemConfigure.isEnabled = false
        statusItem.menu?.addItem(menuItemConfigure)
        
        statusItem.menu?.addItem(NSMenuItem.separator())
        
        let menuItemQuit = NSMenuItem()
        menuItemQuit.title = "Quit"
        menuItemQuit.target = NSApplication.shared
        menuItemQuit.action = #selector(NSApplication.stop)
        statusItem.menu?.addItem(menuItemQuit)
        
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(self,
                                       selector: #selector(updateEventTap),
                                       name: NSWorkspace.didActivateApplicationNotification,
                                       object: nil)
        
        createEventTap()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        return true
    }
    
    @objc func openGitHub() {
        let url = "https://github.com/pnoqable/PinchBar"
        NSWorkspace.shared.open(URL(string: url)!)
    }
    
    @objc func accessibility() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: url)!)
    }
    
    @objc func configure() {
        let appName : String! = NSWorkspace.shared.frontmostApplication?.localizedName
        
        if (apps.keys.contains(appName)) {
            apps.removeValue(forKey: appName)
        } else {
            apps[appName] = true
        }
        
        UserDefaults.standard.set(apps, forKey: "apps")
        
        updateEventTap()
    }
    
    func createEventTap() {
        let callback: CGEventTapCallBack = { _, type, event, _ in
            AppDelegate.tapEvent( type: type, event: event )
        }
        
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest:  1<<29,
                                     callback: callback,
                                     userInfo: nil)
        
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            menuItemPreferences.state = .on
            menuItemPreferences.isEnabled = false
            menuItemConfigure.isEnabled = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: createEventTap)
        }
        
        updateEventTap()
    }
    
    @objc func updateEventTap() {
        let appName : String! = NSWorkspace.shared.frontmostApplication?.localizedName
        var enable = apps.keys.contains(appName)
        
        if let eventTap = eventTap {
            if enable != CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: enable)
            }
        } else {
            enable = false
        }
        
        statusItem.button?.appearsDisabled = !enable
        menuItemConfigure.title = "Enable for " + appName
        menuItemConfigure.state = enable ? .on : .off
    }
    
    static func tapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let instance = NSApplication.shared.delegate as! AppDelegate
            instance.updateEventTap()
        } else {
            let nsEvent = NSEvent(cgEvent: event)
            if nsEvent?.type == .magnify {
                event.type = .scrollWheel
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(round(nsEvent!.deltaZ)))
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
                event.flags = .maskCommand
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
