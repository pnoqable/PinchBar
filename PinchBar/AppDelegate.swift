import Cocoa

@main class AppDelegate: NSObject, NSApplicationDelegate {
    let repository = Repository()
    let settings = Settings()
    
    var eventTaps: [EventTap] = []
    lazy var statusMenu = StatusMenu(repository: repository, settings: settings)
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        settings.callWhenMappingsChanged = WeakFunc(self, AppDelegate.activeAppChanged).call
        
        NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(activeAppChanged),
                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        activeAppChanged()
        
        LogiHIDPP.shared.onDeviceReady = { device in
            NSLog("Logitech Mouse connected: \(device.name)")
            if device.name.contains("M720 Triathlon") {
                LogiHIDPP.shared.setDivert(cid: 83, enabled: false, for: device)
                LogiHIDPP.shared.setDivert(cid: 86, enabled: false, for: device)
                NSLog("Disabled Divert of Thumb buttons for \(device.name)")
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusMenu.statusItem.isVisible = true
        return true
    }
    
    @objc func activeAppChanged() {
        if let activeApp = NSWorkspace.shared.frontmostApplication?.localizedName {
            eventTaps = settings.mappings(for: activeApp).compactMap(EventTap.init)
            statusMenu.enableSubmenus(if: !eventTaps.isEmpty)
            statusMenu.updateSubmenus(activeApp: activeApp)
        }
    }
    
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
