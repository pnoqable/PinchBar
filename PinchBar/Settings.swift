import Cocoa

class Settings: WithUserDefaults {
    enum MappingType: String, Codable, CaseIterable {
        case magicMouseZoom, middleClick, multiTap, otherMouseZoom
    }
    
    struct Defaults {
        static let globalMappings = MappingType.allCases
        
        static let magicMouseZoom = MagicMouseZoomMapping(.init(sensivity: 0.005))
        static let middleClick    = MiddleClickMapping(   .init(onMousepad: 2, onTrackpad: 3))
        static let multiTap       = MultiTapMapping(      .init(oneAndAHalfTapFlags: .maskAlternate,
                                                                doubleTapFlags:      .maskCommand))
        static let otherMouseZoom = OtherMouseZoomMapping(.init(button: .center, noClicks: false,
                                                                sensivity: 0.003, minimalDrag: 2))
        
        static let appPresets = ["Cubase": "Cubase"]
        static let presets    = ["Cubase":        Preset(.cubase),
                                 "Cubase 13":     Preset(.cubase13),
                                 "Font Size":     Preset(.fontSize),
                                 "Font Size/cmd": Preset(.fontSizeCmd)]
    }
    
    @UserDefault("globalMappings") var globalMappings = Defaults.globalMappings
    @UserDefault("magicMouseZoom") var magicMouseZoom = Defaults.magicMouseZoom
    @UserDefault("middleClick")    var middleClick    = Defaults.middleClick
    @UserDefault("multiTap")       var multiTap       = Defaults.multiTap
    @UserDefault("otherMouseZoom") var otherMouseZoom = Defaults.otherMouseZoom
    @UserDefault("appPresets")     var appPresets     = Defaults.appPresets
    @UserDefault("presets")        var presets        = Defaults.presets
    
    var globalMappingNames: [String] { globalMappings.map(\.rawValue) }
    var appNames: [String] { appPresets.keys.sorted() }
    var presetNames: [String] { presets.keys.sorted() }
    
    var callWhenMappingsChanged: Callback?
    
    init() {
        // write global mappings to user defaults:
        self.globalMappings = globalMappings
        self.magicMouseZoom = magicMouseZoom
        self.middleClick    = middleClick
        self.multiTap       = multiTap
        self.otherMouseZoom = otherMouseZoom
        
        // upgrade path: merge customized/user presets with newly added default presets
        appPresets.merge(Defaults.appPresets, uniquingKeysWith: { userPreset, _ in userPreset })
        presets.merge(Defaults.presets, uniquingKeysWith: { userPreset, _ in userPreset })
        
        NSLog("globalMappingNames: \(globalMappingNames.joined(separator: ", "))")
        NSLog("appNames: \(appNames.joined(separator: ", "))")
        NSLog("presetNames: \(presetNames.joined(separator: ", "))")
        
        setAllUserDefaultsChangedCallbacks(Weak(self, \.callWhenMappingsChanged).call)
    }
    
    func mappings(for appName: String) -> [any EventMapping] {
        globalMappings.map { switch $0 {
        case .magicMouseZoom: return magicMouseZoom
        case .middleClick:    return middleClick
        case .multiTap:       return multiTap
        case .otherMouseZoom: return otherMouseZoom
        } } + presets[appPresets[appName]]
    }
}
