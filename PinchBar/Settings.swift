import Cocoa

class Settings: WithUserDefaults {
    enum MappingType: String, Codable {
        case middleClick, mouseZoom, multiTap
    }
    
    struct Defaults {
        static let globalMappings: [MappingType] = [.middleClick, .mouseZoom, .multiTap]
        static let middleClick    = MiddleClickMapping(onMousepad: 2, onTrackpad: 3)
        static let mouseZoom      = MouseZoomMapping(sensivity: 0.005)
        static let multiTap       = MultiTapMapping(oneAndAHalfTapFlags: .maskAlternate,
                                                    doubleTapFlags:      .maskCommand)
        
        static let appPresets     = ["Cubase": "Cubase"]
        static let presets        = ["Cubase":        Preset.cubase,
                                     "Cubase 13":     Preset.cubase13,
                                     "Font Size":     Preset.fontSize,
                                     "Font Size/cmd": Preset.fontSizeCmd]
    }
    
    @UserDefault("globalMappings") var globalMappings = Defaults.globalMappings
    @UserDefault("middleClick")    var middleClick    = Defaults.middleClick
    @UserDefault("mouseZoom")      var mouseZoom      = Defaults.mouseZoom
    @UserDefault("multiTap")       var multiTap       = Defaults.multiTap
    @UserDefault("appPresets")     var appPresets     = Defaults.appPresets
    @UserDefault("presets")        var presets        = Defaults.presets
    
    var globalMappingNames: [String] { globalMappings.map(\.rawValue) }
    var appNames: [String] { appPresets.keys.sorted() }
    var presetNames: [String] { presets.keys.sorted() }
    
    var callWhenMappingsChanged: Callback?
    
    init() {
        // write global mappings to user defaults:
        self.globalMappings = globalMappings
        self.middleClick    = middleClick
        self.mouseZoom      = mouseZoom
        self.multiTap       = multiTap
        
        // upgrade path: merge customized/user presets with newly added default presets
        appPresets.merge(Defaults.appPresets, uniquingKeysWith: { userPreset, _ in userPreset })
        presets.merge(Defaults.presets, uniquingKeysWith: { userPreset, _ in userPreset })
        
        NSLog("globalMappingNames: \(globalMappingNames.joined(separator: ", "))")
        NSLog("appNames: \(appNames.joined(separator: ", "))")
        NSLog("presetNames: \(presetNames.joined(separator: ", "))")
        
        setAllUserDefaultsChangedCallbacks(Weak(self, \.callWhenMappingsChanged).call)
    }
    
    func mappings(for appName: String) -> [EventMapping] {
        globalMappings.map { switch $0 {
        case .middleClick: return middleClick
        case .mouseZoom:   return mouseZoom
        case .multiTap:    return multiTap
        } } + presets[appPresets[appName]]
    }
}
