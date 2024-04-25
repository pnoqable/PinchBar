import Cocoa

class StatusMenu {
    var statusItem: NSStatusItem
    var menuItemPreferences: NSMenuItem
    var menuItemGlobal: NSMenuItem
    var menuItemConfigure: NSMenuItem
    
    weak var settings: Settings?
    
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
        
        menuItemGlobal = NSMenuItem(title: "Global Mappings")
        menuItemGlobal.isEnabled = false
        statusItem.menu?.addItem(menuItemGlobal)
        
        menuItemConfigure = NSMenuItem()
        menuItemConfigure.isEnabled = false
        statusItem.menu?.addItem(menuItemConfigure)
        
        statusItem.menu?.addItem(.separator())
        
        statusItem.menu?.addItem(NSMenuItem(title: "Quit") {
            NSApplication.shared.stop(self)
        })
        
        self.settings = settings
    }
    
    func enableSubmenus() {
        menuItemPreferences.state = .on
        menuItemPreferences.isEnabled = false
        menuItemGlobal.isEnabled = true
        menuItemConfigure.isEnabled = true
    }
    
    func updateSubmenus(activeApp: String) {
        guard let settings else { return }
        
        let globalSubmenu = NSMenu()
        
        for mapping in Settings.Defaults.globalMappings {
            let isChecked = mapping ∈ settings.globalMappings
            globalSubmenu.addItem(NSMenuItem(title: mapping.rawValue, isChecked: isChecked) {
                [weak settings] in guard let settings else { return }
                if isChecked {
                    settings.globalMappings.removeAll { $0 == mapping }
                } else {
                    let unsorted = settings.globalMappings + mapping
                    settings.globalMappings = Settings.Defaults.globalMappings.filter { $0 ∈ unsorted }
                }
            })
        }
        
        menuItemGlobal.submenu = globalSubmenu
        
        let presetSubmenu = NSMenu()
        
        let activePreset = settings.appPresets[activeApp]
        
        for preset in settings.presetNames {
            presetSubmenu.addItem(NSMenuItem(title: preset, isChecked: activePreset == preset) {
                [weak settings] in settings?.appPresets[activeApp] = preset
            })
        }
        
        presetSubmenu.addItem(.separator())
        presetSubmenu.addItem(NSMenuItem(title: "None", isChecked: activePreset == nil) {
            [weak settings] in settings?.appPresets[activeApp] = nil
        })
        
        statusItem.button?.appearsDisabled = activePreset == nil || menuItemPreferences.isEnabled
        menuItemConfigure.title = "Change Preset for " + activeApp
        menuItemConfigure.submenu = presetSubmenu
    }
}
