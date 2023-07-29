import Cocoa

class Settings {
    var appPresets: [String: String] = ["Cubase": "Cubase"]
    
    var presets: [String: Preset] = ["Cubase": .cubase,
                                     "Font Size": .fontSize,
                                     "Font Size/cmd": .fontSizeCmd]
    
    var appNames: [String] { appPresets.keys.sorted() }
    var presetNames: [String] { presets.keys.sorted() }
    
    let globalMappings: [EventMapping] = [MouseZoomMapping(sensivity: 0.005),
                                          MiddleClickMapping(onMousepad: 2, onTrackpad: 3),
                                          MultiTapMapping(oneAndAHalfTapFlags: .maskAlternate,
                                                          doubleTapFlags:      .maskCommand)]
    
    func mappings(for appName: String) -> [EventMapping] {
        globalMappings + presets[appPresets[appName]].asArray
    }
    
    init() {
        let factoryAppPresets = appPresets, factoryPresets = presets
        
        if let dict = UserDefaults.standard.dictionary(forKey: "presets"),
           let json = try? JSONSerialization.data(withJSONObject: dict),
           let presets = try? JSONDecoder().decode(type(of: presets), from: json),
           let appPresets = UserDefaults.standard.dictionary(forKey: "appPresets") as? [String: String] {
            self.presets = presets
            self.appPresets = appPresets
        }
        
        appPresets.merge(factoryAppPresets, uniquingKeysWith: { userAP, _ in userAP })
        presets.merge(factoryPresets, uniquingKeysWith: { userPreset, _ in userPreset })
    }
    
    func save() {
        if let json = try? JSONEncoder().encode(presets),
           let dict = try? JSONSerialization.jsonObject(with: json) {
            UserDefaults.standard.set(dict, forKey: "presets")
            UserDefaults.standard.set(appPresets, forKey: "appPresets")
        }
    }
}
