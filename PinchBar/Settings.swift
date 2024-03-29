import Cocoa

class Settings {
    typealias Preset = [CGEventFlags: EventMapping]
    typealias PList = [String: EventMapping]
    
    var appPresets: [String: String] = ["Cubase": "Cubase"]
    var presets: [String: Preset] = ["Cubase": .cubase, "Cubase 13": .cubase13,
                                     "Font Size": .fontSize, "Font Size/cmd": .fontSizeCmd]
    
    var appNames: [String] { appPresets.keys.sorted() }
    var presetNames: [String] { presets.keys.sorted() }
    
    func preset(named name: String?) -> Preset? { name.flatMap{ name in presets[name] } }
    
    private var plists: [String: PList] {
        get { presets.mapValues{ preset in preset.mapKeys{ flags in "\(flags.rawValue)" } } }
        set { presets = newValue.mapValues{ plist in plist.compactMapKeys(CGEventFlags.init) } }
    }
    
    init() {
        if let dict = UserDefaults.standard.dictionary(forKey: "presets"),
           let json = try? JSONSerialization.data(withJSONObject: dict),
           let plists = try? JSONDecoder().decode(type(of:plists), from: json),
           let appPresets = UserDefaults.standard.dictionary(forKey: "appPresets") as? [String:String] {
            self.plists = plists
            self.appPresets = appPresets
        }
    }
    
    func save() {
        if let json = try? JSONEncoder().encode(plists),
           let dict = try? JSONSerialization.jsonObject(with: json) {
            UserDefaults.standard.set(dict, forKey: "presets")
            UserDefaults.standard.set(appPresets, forKey: "appPresets")
        }
    }
}

extension Settings.Preset {
    static let cubase: Self = [.maskNoFlags: .pinchToWheel(),
                               .maskAlternate: .pinchToKeys(flags: .maskAlternate, codeA: 5, codeB: 4),
                               .maskCommand: .pinchToKeys(flags: .maskShift, codeA: 5, codeB: 4)]
    static let cubase13: Self = [.maskNoFlags: .pinchToWheel(),
                                 .maskAlternate: .pinchToWheel(flags: .maskCommand.union(.maskAlternate),
                                                               sensivity: 500),
                                 .maskCommand: .pinchToWheel(flags: .maskCommand.union(.maskShift),
                                                             sensivity: 500)]
    static let fontSize: Self = [.maskNoFlags: .pinchToKeys(flags: .maskCommand, codeA:44, codeB: 30),
                                 .maskCommand: .pinchToPinch()]
    static let fontSizeCmd: Self = [.maskNoFlags: .pinchToPinch(),
                                    .maskCommand: .pinchToKeys(flags: .maskCommand, codeA:44, codeB: 30)]
}
