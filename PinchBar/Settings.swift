import Cocoa

private extension UserDefaults {
    @objc dynamic var appPresets: [String: String]? {
        get { dictionary(forKey: "appPresets") as? [String: String] }
        set { set(newValue, forKey: "appPresets") }
    }
    
    @objc dynamic var presets: [String: Any]? {
        get { dictionary(forKey: "presets") }
        set { set(newValue, forKey: "presets") }
    }
}

class Settings {
    private let defaults = UserDefaults.standard
    var defaultObservers: [NSKeyValueObservation] = []
    var defaultsChanged: Callback?
    
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
        
        defaultObservers.append(defaults.observe(\.appPresets, options: [.initial, .new]) {
            [weak self] _, change in
            if let appPresets = change.newValue! {
                self?.appPresets = appPresets
                self?.defaultsChanged?()
            }
        })

        defaultObservers.append(defaults.observe(\.presets, options: [.initial, .new]) {
            [weak self] _, change in
            if let dict = change.newValue!,
               let json = try? JSONSerialization.data(withJSONObject: dict),
               let presets = try? JSONDecoder().decode(type(of: self?.presets), from: json) {
                self?.presets = presets
                self?.defaultsChanged?()
            }
        })
        
        appPresets.merge(factoryAppPresets, uniquingKeysWith: { userAP, _ in userAP })
        presets.merge(factoryPresets, uniquingKeysWith: { userPreset, _ in userPreset })
    }
    
    func save() {
        if let json = try? JSONEncoder().encode(presets),
           let dict = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
            defaults.appPresets = appPresets
            defaults.presets = dict
        }
    }
}
