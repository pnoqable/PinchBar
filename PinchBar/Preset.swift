import Cocoa

struct Preset {
    let mappings: [CGEventFlags: EventMapping]
    
    subscript(event: CGEvent) -> EventMapping? {
        get { EventMapping.canTap(event) ? mappings[event.flags.purified] : nil }
    }
    
    static let fontSize = Self(mappings:
                                [.maskNoFlags: .pinchToKeys(flags: .maskCommand, codeA:44, codeB: 30),
                                 .maskCommand: .pinchToPinch()])
    
    static let cubase = Self(mappings:
                                [.maskNoFlags: .pinchToWheel(),
                                 .maskAlternate: .pinchToKeys(flags: .maskAlternate, codeA: 5, codeB: 4),
                                 .maskCommand: .pinchToKeys(flags: .maskShift, codeA: 5, codeB: 4)])
}

extension Preset: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let plist = try container.decode([String: EventMapping].self)
        self.init(mappings: plist.compactMapKeys(CGEventFlags.init))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(mappings.mapKeys { flags in "\(flags.rawValue)" })
    }
}
