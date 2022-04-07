import Cocoa

@main class AppDelegate: NSObject, NSApplicationDelegate, EventTapDelegate {
    var statusItem: NSStatusItem!
    var menuItemPreferences: NSMenuItem!
    var menuItemConfigure: NSMenuItem!
    
    let eventTap = EventTap()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("Enabled for: \(eventTap.apps.keys)")
        
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
        menuItemConfigure.title = "Enable for " + eventTap.currentApp
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
        eventTap.toggleApp()
    }
    
    func eventTapCreated(_: EventTap) {
        menuItemPreferences.state = .on
        menuItemPreferences.isEnabled = false
        menuItemConfigure.isEnabled = true
    }
    
    func eventTapUpdated(_ eventTap: EventTap) {
        statusItem.button?.appearsDisabled = !eventTap.isEnabled
        menuItemConfigure.title = "Enable for " + eventTap.currentApp
        menuItemConfigure.state = eventTap.isEnabled ? .on : .off
    }
    
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
