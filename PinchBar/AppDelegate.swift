import Cocoa

private let unknownApp: String = "unknown Application"

@main class AppDelegate: NSObject, NSApplicationDelegate, EventTapDelegate {
    var activeApp: String = unknownApp

    var statusItem: NSStatusItem!
    var menuItemPreferences: NSMenuItem!
    var menuItemConfigure: NSMenuItem!
    
    let eventTap = EventTap()
    let repository = Repository()
    let settings = Settings()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("PinchBar \(repository.version), enabled for: \(settings.apps.keys)")
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.button?.toolTip = "PinchBar"
        statusItem.behavior = .removalAllowed
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        
        let menuItemAbout = NSMenuItem()
        menuItemAbout.title = "About PinchBar " + repository.version
        menuItemAbout.target = self
        menuItemAbout.action = #selector(openGitHub)
        statusItem.menu?.addItem(menuItemAbout)
        
        let menuItemUpdate = NSMenuItem()
        menuItemUpdate.title = "Check for Updates..."
        menuItemUpdate.target = self
        menuItemUpdate.action = #selector(checkForUpdates)
        statusItem.menu?.addItem(menuItemUpdate)
        
        statusItem.menu?.addItem(NSMenuItem.separator())
        
        menuItemPreferences = NSMenuItem()
        menuItemPreferences.title = "Enable Pinchbar in Accessibility"
        menuItemPreferences.target = self
        menuItemPreferences.action = #selector(accessibility)
        statusItem.menu?.addItem(menuItemPreferences)
        
        menuItemConfigure = NSMenuItem()
        menuItemConfigure.title = "Enable for " + activeApp
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
        
        eventTap.delegate = self
        eventTap.start()
        
        repository.openUpdateLink = openGitHub
        repository.checkForUpdates(verbose: false)
        
        NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(updateEventTap),
                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        updateEventTap()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        return true
    }
    
    @objc func openGitHub() {
        let url = "https://github.com/pnoqable/PinchBar"
        NSWorkspace.shared.open(URL(string: url)!)
    }
    
    @objc func checkForUpdates() {
        repository.checkForUpdates(verbose: true)
    }
    
    @objc func accessibility() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: url)!)
    }
    
    @objc func configure() {
        if settings.apps.removeValue(forKey: activeApp) == nil {
            settings.apps[activeApp] = "Common"
        }
        
        settings.save()
        updateEventTap()
    }
    
    func eventTapCreated(_: EventTap) {
        menuItemPreferences.state = .on
        menuItemPreferences.isEnabled = false
        menuItemConfigure.isEnabled = true
    }
    
    @objc func updateEventTap() {
        activeApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? unknownApp
        eventTap.preset = settings.preset(for: activeApp)
        
        statusItem.button?.appearsDisabled = !eventTap.isEnabled
        menuItemConfigure.title = "Enable for " + activeApp
        menuItemConfigure.state = eventTap.isEnabled ? .on : .off
    }
    
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
