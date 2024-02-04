import Cocoa

private let unknownApp: String = "unknown Application"

@main class AppDelegate: NSObject, NSApplicationDelegate {
    var activeApp: String = unknownApp
    
    let repository = Repository()
    let settings = Settings()
    
    lazy var eventTap = EventTap(callWhenStarted: Weak(statusMenu, StatusMenu.enableSubmenu).call)
    lazy var statusMenu = StatusMenu(repository: repository, settings: settings)
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        settings.callWhenMappingsChanged = Weak(self, AppDelegate.activeAppChanged).call
        statusMenu.callWhenPresetSelected = Weak(self, AppDelegate.changePreset).call
        
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
        eventTap.mappings = settings.mappings(for: activeApp)
        statusMenu.updateSubmenu(activeApp: activeApp)
    }
    
    func changePreset(to newPreset: String?) {
        settings.appPresets[activeApp] = newPreset
    }
    
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
