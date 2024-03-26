import Cocoa

class Settings {
    enum MappingType: String, Codable {
        case magicMouseZoom, middleClick, multiTap, otherMouseHori, otherMouseZoom
    }
    
    struct Defaults {
        static let globalMappings: [MappingType] = [.magicMouseZoom, .middleClick, .multiTap,
                                                    .otherMouseHori, .otherMouseZoom]
        static var magicMouseZoom: MagicMouseZoomMapping { .init(.init(sensivity: 0.005)) }
        static var middleClick:    MiddleClickMapping    { .init(.init(onMousepad: 2, onTrackpad: 3)) }
        static var multiTap:       MultiTapMapping       { .init(.init(oneAndAHalfTapFlags: .maskAlternate,
                                                                       doubleTapFlags:      .maskCommand)) }
        static var otherMouseHori: OtherMouseHoriScroll  { .init(.init(button: .fourth, noClicks: true))}
        static var otherMouseZoom: OtherMouseZoomMapping { .init(.init(button: .center, noClicks: false,
                                                                       sensivity: 0.003, minimalDrag: 2,
                                                                       doubleClickFlags: .maskCommand,
                                                                       tripleClickFlags: .maskAlternate)) }
        
        static let appPresets = ["Cubase": "Cubase"]
        static var presets : [String: Preset] { ["Cubase":        .init(.cubase),
                                                 "Cubase 13":     .init(.cubase13),
                                                 "Font Size":     .init(.fontSize),
                                                 "Font Size/cmd": .init(.fontSizeCmd)] }
    }
    
    @UserDefault("globalMappings") var globalMappings = Defaults.globalMappings
    @UserDefault("magicMouseZoom") var magicMouseZoom = Defaults.magicMouseZoom
    @UserDefault("middleClick")    var middleClick    = Defaults.middleClick
    @UserDefault("multiTap")       var multiTap       = Defaults.multiTap
    @UserDefault("otherMouseHori") var otherMouseHori = Defaults.otherMouseHori
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
        self.otherMouseHori = otherMouseHori
        self.otherMouseZoom = otherMouseZoom
        
        // upgrade path: merge customized/user presets with newly added default presets
        appPresets.merge(Defaults.appPresets, uniquingKeysWith: { userPreset, _ in userPreset })
        presets.merge(Defaults.presets, uniquingKeysWith: { userPreset, _ in userPreset })
        
        // write (app) presets to user defaults:
        self.appPresets = appPresets
        self.presets    = presets
        
        NSLog("globalMappingNames: \(globalMappingNames.joined(separator: ", "))")
        NSLog("appNames: \(appNames.joined(separator: ", "))")
        NSLog("presetNames: \(presetNames.joined(separator: ", "))")
        
        Mirror(reflecting: self).children.map(\.value)
            .filterMap(ObservableUserDefault.setChangedCallback)
            .callAll(with: WeakCallback(self, \.callWhenMappingsChanged).call)
    }
    
    func mappings(for appName: String) -> [any EventMapping] {
        globalMappings.map { switch $0 {
        case .magicMouseZoom: return magicMouseZoom
        case .middleClick:    return middleClick
        case .multiTap:       return multiTap
        case .otherMouseHori: return otherMouseHori
        case .otherMouseZoom: return otherMouseZoom
        } } + presets[appPresets[appName]]
    }
}
