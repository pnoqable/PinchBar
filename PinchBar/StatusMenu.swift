import Cocoa

class StatusMenu {
    let statusItem: NSStatusItem
    let menu = NSMenu()
    let menuItemPreferences: NSMenuItem
    let menuItemGlobal: NSMenuItem
    let menuItemConfigure: NSMenuItem
    
    weak var settings: Settings?
    
    var observations = [NSKeyValueObservation]()
    
    init(repository: Repository, settings: Settings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = .removalAllowed
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.button?.callback = { NSApplication.shared.activate(ignoringOtherApps: true) }
        statusItem.menu = menu
        menu.autoenablesItems = false
        
        menu.addItem(NSMenuItem(title: "About PinchBar " + repository.version,
                                Weak(repository, Repository.openGitHub).call))
        
        menu.addItem(NSMenuItem(title: "Check for Updates...",
                                Weak(repository, Repository.checkForUpdates <- true).call))
        
        menu.addItem(.separator())
        
        menuItemPreferences = NSMenuItem(title: "Enable Pinchbar in Accessibility") {
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            NSWorkspace.shared.open(URL(string: url)!)
        }
        menu.addItem(menuItemPreferences)
        
        menuItemGlobal = NSMenuItem(title: "Global Mappings")
        menuItemGlobal.isEnabled = false
        menu.addItem(menuItemGlobal)
        
        menuItemConfigure = NSMenuItem()
        menuItemConfigure.isEnabled = false
        menu.addItem(menuItemConfigure)
        
        menu.addItem(.separator())
        
        menu.addItem(NSMenuItem(title: "Export Settings...",
                                Weak(settings, Settings.interactiveExport).call))
        
        menu.addItem(NSMenuItem(title: "Import Settings...",
                                Weak(settings, Settings.interactiveImport).call))
        
        menu.addItem(.separator())
        
        menu.addItem(NSMenuItem(title: "Quit") {
            NSApplication.shared.stop(self)
        })
        
        observations.append(NSApplication.shared.observe(\.modalWindow, options: .new) { [weak self] _, change in
            if let self, let newValue = change.newValue {
                statusItem.menu = newValue == nil ? menu : nil
            }
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
        
        settings.preMappingNames.forEach { pm in
            globalSubmenu.addItem(NSMenuItem(title: pm, isChecked: pm ∉ settings.disabledPMs) {
                [weak settings] in settings?.disabledPMs.formSymmetricDifference([pm])
            })
        }
        
        menuItemGlobal.submenu = globalSubmenu
        
        let presetSubmenu = NSMenu()
        
        let activePreset = settings.appPresets[activeApp]
        
        settings.presetNames.forEach { preset in
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
