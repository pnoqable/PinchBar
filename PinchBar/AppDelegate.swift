import Cocoa

private let unknownApp: String = "unknown Application"

@main class AppDelegate: NSObject, NSApplicationDelegate {
    var activeApp: String = unknownApp
    
    let eventTap = EventTap()
    let repository = Repository()
    let settings = Settings()
    
    let statusMenu = StatusMenu()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("PinchBar \(repository.version), configured for: \(settings.appNames)")
        
        statusMenu.callWhenPresetSelected = { [weak self] p in self?.changePreset(to: p) }
        statusMenu.create(repository: repository, settings: settings)
        
        eventTap.logEvents = settings.logEvents
        eventTap.callWhenCreated = { [weak statusMenu] in statusMenu?.enableSubmenu() }
        eventTap.start()
        
        repository.checkForUpdates(verbose: false)
        
        NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(activeAppChanged),
                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        activeAppChanged()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusMenu.statusItem.isVisible = true
        return true
    }
    
    @objc func activeAppChanged() {
        activeApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? unknownApp
        changePreset(to: settings.appPresets[activeApp])
    }
    
    func changePreset(to newPreset: String?) {
        settings.appPresets[activeApp] = newPreset
        settings.save()
        
        eventTap.preset = settings.preset(named: newPreset)
        statusMenu.updateSubmenu(activeApp: activeApp, activePreset: newPreset)
    }
    
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
