import Cocoa

class StatusMenu {
    var statusItem: NSStatusItem
    var menuItemPreferences: NSMenuItem
    var menuItemConfigure: NSMenuItem
    
    weak var settings: Settings?
    
    var callWhenPresetSelected: Setter<String?>?
    
    init(repository: Repository, settings: Settings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.button?.toolTip = "PinchBar"
        statusItem.behavior = .removalAllowed
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        
        statusItem.menu?.addItem(NSMenuItem(title: "About PinchBar " + repository.version,
                                            Weak(repository, Repository.openGitHub).call))
        
        statusItem.menu?.addItem(NSMenuItem(title: "Check for Updates...",
                                            Weak(repository, Repository.checkForUpdates <- true).call))
        
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
                                       Weak(self, \.callWhenPresetSelected <- preset).call))
        }
        
        submenu.addItem(.separator())
        
        submenu.addItem(NSMenuItem(title: "None", isChecked: activePreset == nil,
                                   Weak(self, \.callWhenPresetSelected <- nil).call))
        
        statusItem.button?.appearsDisabled = activePreset == nil || menuItemPreferences.isEnabled
        menuItemConfigure.title = "Change Preset for " + activeApp
        menuItemConfigure.submenu = submenu
    }
}
