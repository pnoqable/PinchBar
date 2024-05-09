import Cocoa

class Settings: WithUserDefaults {
    struct Defaults {
        static let preMappings = ["Magic Mouse Zoom":   PreMapping.magicMouseZoom,
                                  "Middle Click":       PreMapping.middleClick,
                                  "Multi Tap":          PreMapping.multiTap,
                                  "Other Mouse Scroll": PreMapping.otherMouseScroll,
                                  "Other Mouse Zoom":   PreMapping.otherMouseZoom]
        
        static let presets    = ["Cubase":        Preset(.cubase),
                                 "Cubase 13":     Preset(.cubase13),
                                 "Font Size":     Preset(.fontSize),
                                 "Font Size/cmd": Preset(.fontSizeCmd)]
        
        static let appPresets = ["Cubase": "Cubase"]
    }
    
    @UserDefault("preMappings") var preMappings = Defaults.preMappings
    @UserDefault("disabledPMs") var disabledPMs = Set<String>()
    @UserDefault("presets")     var presets     = Defaults.presets
    @UserDefault("appPresets")  var appPresets  = Defaults.appPresets
    
    var preMappingsSorted: [(key: String, value: PreMapping)] { preMappings.sortedByValueAndKey() }
    var preMappingNames: [String] { preMappingsSorted.map(\.key) }
    var presetNames: [String] { presets.keys.sorted() }
    var appNames: [String] { appPresets.keys.sorted() }
    
    var callWhenMappingsChanged: Callback?
    
    init() {
        // upgrade path: merge customized/user presets with newly added default presets
        preMappings.merge(Defaults.preMappings, uniquingKeysWith: { userPreMap, _ in userPreMap })
        presets.merge(Defaults.presets, uniquingKeysWith: { userPreset, _ in userPreset })
        appPresets.merge(Defaults.appPresets, uniquingKeysWith: { userPreset, _ in userPreset })
        
        NSLog("preMappingNames: \(preMappingNames.joined(separator: ", "))")
        NSLog("disabledPMs: \(disabledPMs.sorted().joined(separator: ", "))")
        NSLog("presetNames: \(presetNames.joined(separator: ", "))")
        NSLog("appNames: \(appNames.joined(separator: ", "))")
        
        setAllUserDefaultsChangedCallbacks(Weak(self, \.callWhenMappingsChanged).call)
    }
    
    var enabledPreMappings: [any EventMapping] {
        preMappingsSorted.filter((!) ∘ disabledPMs.contains ∘ \.key).map(\.value.mapping)
    }
    
    func mappings(for appName: String) -> [any EventMapping] {
        enabledPreMappings + presets[appPresets[appName]]
    }
    
    func interactiveExport() {
        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.nameFieldStringValue = "PinchBar Settings.json"
        panel.allowedFileTypes = ["json"]
        
        if panel.runModal() == .OK, let url = panel.url {
            do { try self.encodeAllUserDefaultsAsJSON().write(to: url) }
            catch { NSApplication.shared.presentError(error) }
        }
    }
    
    func interactiveImport() {
        let panel = NSOpenPanel()
        panel.title = "Import Settings"
        panel.allowedFileTypes = ["json"]
        
        if panel.runModal() == .OK, let url = panel.url {
            do { try self.decodeAllUserDefaults(fromJSON: Data(contentsOf: url)) }
            catch { NSApplication.shared.presentError(error) }
        }
    }
}
