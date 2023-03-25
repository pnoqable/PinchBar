import Cocoa

class Settings {
    var appPresets: [String: String] = ["Cubase": "Cubase"]
    var presets: [String: Preset] = ["Cubase": .cubase, "Font Size": .fontSize]
    
    var appNames: [String] { appPresets.keys.sorted() }
    var presetNames: [String] { presets.keys.sorted() }
    
    let globalMappings: [EventMapping] = [MouseZoomMapping(sensivity: 0.005),
                                          MiddleClickMapping(onMousepad: 2, onTrackpad: 3)]
    
    func mappings(for appName: String) -> [EventMapping] {
        globalMappings + presets[appPresets[appName]].asArray
    }
    
    init() {
        if let dict = UserDefaults.standard.dictionary(forKey: "presets"),
           let json = try? JSONSerialization.data(withJSONObject: dict),
           let presets = try? JSONDecoder().decode(type(of: presets), from: json),
           let appPresets = UserDefaults.standard.dictionary(forKey: "appPresets") as? [String: String] {
            self.presets = presets
            self.appPresets = appPresets
        }
    }
    
    func save() {
        if let json = try? JSONEncoder().encode(presets),
           let dict = try? JSONSerialization.jsonObject(with: json) {
            UserDefaults.standard.set(dict, forKey: "presets")
            UserDefaults.standard.set(appPresets, forKey: "appPresets")
        }
    }
}
