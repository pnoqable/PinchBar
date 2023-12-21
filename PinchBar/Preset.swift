import Cocoa

struct Preset: EventMapping {
    let mappings: [CGEventFlags: PinchMapping]
    
    func map(_ event: CGEvent) -> [CGEvent] {
        mappings[event.flags.purified]?.map(event) ?? [event]
    }
    
    static let cubase = Self(mappings:
                                [.maskNoFlags: .pinchToWheel(),
                                 .maskAlternate: .pinchToKeys(flags: .maskAlternate, codeA: 5, codeB: 4),
                                 .maskCommand: .pinchToKeys(flags: .maskShift, codeA: 5, codeB: 4)])
    
    static let cubase13 = Self(mappings:
                                [.maskNoFlags: .pinchToWheel(),
                                 .maskAlternate: .pinchToWheel(flags: .maskCommand.union(.maskAlternate), sensivity: 500),
                                 .maskCommand: .pinchToWheel(flags: .maskCommand.union(.maskShift), sensivity: 500)])
    
    static let fontSize = Self(mappings:
                                [.maskNoFlags: .pinchToKeys(flags: .maskCommand, codeA:44, codeB: 30),
                                 .maskCommand: .pinchToPinch()])
    
    static let fontSizeCmd = Self(mappings:
                                    [.maskCommand: .pinchToKeys(flags: .maskCommand, codeA:44, codeB: 30)])
}

extension Preset: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let plist = try container.decode([String: PinchMapping].self)
        self.init(mappings: plist.compactMapKeys(CGEventFlags.init ∘ UInt64.init))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(mappings.mapKeys(String.init ∘ \.rawValue))
    }
}
