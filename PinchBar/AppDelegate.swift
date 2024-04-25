import Cocoa

@main class AppDelegate: NSObject, NSApplicationDelegate {
    let repository = Repository()
    let settings = Settings()
    
    lazy var eventTap = EventTap(callWhenStarted: Weak(statusMenu, StatusMenu.enableSubmenus).call)
    lazy var statusMenu = StatusMenu(repository: repository, settings: settings)
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        settings.callWhenMappingsChanged = Weak(self, AppDelegate.activeAppChanged).call
        
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
        if let activeApp = NSWorkspace.shared.frontmostApplication?.localizedName {
            eventTap.mappings = settings.mappings(for: activeApp)
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
