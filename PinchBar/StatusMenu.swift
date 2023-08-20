import Cocoa

class StatusMenu {
    var statusItem: NSStatusItem!
    var menuItemPreferences: NSMenuItem!
    var menuItemConfigure: NSMenuItem!
    
    weak var settings: Settings?
    
    var callWhenPresetSelected: Setter<String?>?
    
    func create(repository: Repository, settings: Settings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.button?.toolTip = "PinchBar"
        statusItem.behavior = .removalAllowed
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        
        statusItem.menu?.addItem(NSMenuItem(title: "About PinchBar " + repository.version,
                                            WeakCallback(repository, Repository.openGitHub).get))
        
        statusItem.menu?.addItem(NSMenuItem(title: "Check for Updates...",
                                            WeakCallback(repository, Repository.checkForUpdates, true).get))
        
        statusItem.menu?.addItem(.separator())
        
        menuItemPreferences = NSMenuItem(title: "Enable Pinchbar in Accessibility") {
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            NSWorkspace.shared.open(URL(string: url)!)
        }
        statusItem.menu?.addItem(menuItemPreferences)
        
        menuItemConfigure = NSMenuItem()
        menuItemConfigure.isEnabled = false
        statusItem.menu?.addItem(menuItemConfigure)
        
        statusItem.menu?.addItem(.separator())
        
        statusItem.menu?.addItem(NSMenuItem(title: "Quit") {
            NSApplication.shared.stop(self)
        })
        
        self.settings = settings
    }
    
    func enableSubmenu() {
        menuItemPreferences.state = .on
        menuItemPreferences.isEnabled = false
        menuItemConfigure.isEnabled = true
    }
    
    func updateSubmenu(activeApp: String) {
        guard let settings else { fatalError("called before create") }
        
        let submenu = NSMenu()
        let activePreset = settings.appPresets[activeApp]
        
        for preset in settings.presetNames {
            submenu.addItem(NSMenuItem(title: preset, isChecked: activePreset == preset,
                                       WeakCallback(self, \.callWhenPresetSelected, preset).get))
        }
        
        submenu.addItem(.separator())
        
        submenu.addItem(NSMenuItem(title: "None", isChecked: activePreset == nil,
                                   WeakCallback(self, \.callWhenPresetSelected, nil).get))
        
        statusItem.button?.appearsDisabled = activePreset == nil || menuItemPreferences.isEnabled
        menuItemConfigure.title = "Change Preset for " + activeApp
        menuItemConfigure.submenu = submenu
    }
}
