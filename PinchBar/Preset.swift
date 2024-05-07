import Cocoa

struct Preset: EventMapping {
    typealias Settings = [String: PinchMapping.Settings]
    
    let mappings: [CGEventFlags: PinchMapping]
    var settings: Settings { mappings.mapKeys(String.init ∘ \.rawValue).mapValues(\.settings) }
    
    init(_ settings: Settings) {
        mappings = settings.compactMapKeys(CGEventFlags.init ∘ UInt64.init).mapValues(PinchMapping.init)
    }
    
    func map(_ event: CGEvent) -> [CGEvent] {
        mappings[event.flags.justModifiers]?.map(event) ?? [event]
    }
}

extension Preset.Settings {
    init(_ settings: [CGEventFlags: PinchMapping.Settings]) {
        self = settings.mapKeys(String.init ∘ \.rawValue)
    }
    
    static let cubase = Self([.maskNoFlags: .pinchToWheel(),
                              .maskAlternate: .pinchToKeys(codeA: 5, codeB: 4, flags: .maskAlternate),
                              .maskCommand: .pinchToKeys(codeA: 5, codeB: 4, flags: .maskShift)])
    
    static let cubase13 = Self([.maskNoFlags: .pinchToWheel(),
                                .maskAlternate: .pinchToWheel(flags: .maskCommand.union(.maskAlternate), sensivity: 500),
                                .maskCommand: .pinchToWheel(flags: .maskCommand.union(.maskShift), sensivity: 500)])
    
    static let fontSize = Self([.maskNoFlags: .pinchToKeys(codeA:44, codeB: 30, flags: .maskCommand),
                                .maskCommand: .pinchToPinch()])
    
    static let fontSizeCmd = Self([.maskCommand: .pinchToKeys(codeA:44, codeB: 30, flags: .maskCommand)])
}

extension Preset: Codable {
    init(from decoder: Decoder) throws {
        self = try Self(.init(from: decoder))
    }
    
    func encode(to encoder: Encoder) throws {
        try settings.encode(to: encoder)
    }
}
