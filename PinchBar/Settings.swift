import Cocoa

class Settings {
    typealias Preset = [CGEventFlags: EventMapping]
    typealias PList = [String: EventMapping]
    
    var presets: [String: Preset] = ["Common": .defaults, "Cubase": .cubase]
    var apps: [String: String] = ["Cubase":"Cubase"]
    
    func preset(for app: String) -> Preset? { apps[app].flatMap{ preset in presets[preset] } }
    
    var plists: [String: PList] {
        get { presets.mapValues{ preset in preset.mapKeys{ flags in "\(flags.rawValue)" } } }
        set { presets = newValue.mapValues{ plist in plist.compactMapKeys(CGEventFlags.init) } }
    }
    
    init() {
        if let dict = UserDefaults.standard.dictionary(forKey: "presets"),
           let json = try? JSONSerialization.data(withJSONObject: dict),
           let plists = try? JSONDecoder().decode(type(of:plists), from: json),
           let apps = UserDefaults.standard.dictionary(forKey: "apps") as? [String:String] {
            self.plists = plists
            self.apps = apps
        }
    }
    
    func save() {
        if let json = try? JSONEncoder().encode(plists),
           let dict = try? JSONSerialization.jsonObject(with: json) {
            UserDefaults.standard.set(dict, forKey: "presets")
            UserDefaults.standard.set(apps, forKey: "apps")
        }
    }
}

extension Settings.Preset {
    static let defaults: Self = [.maskNoFlags: .pinchToKeys(), .maskCommand: .pinchToPinch()]
    static let cubase: Self = [.maskNoFlags: .pinchToWheel(),
                               .maskAlternate: .pinchToKeys(flags: .maskAlternate, codeA: 5, codeB: 4),
                               .maskCommand: .pinchToKeys(flags: .maskShift, codeA: 5, codeB: 4)]
}
