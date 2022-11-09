import Cocoa

extension CGEventFlags: Codable, Hashable {
    static let maskNoFlags = Self([])
    
    // key without left/right info
    static let pureKeyMask = UInt64.max << 8
    
    var purified: Self { Self(rawValue: rawValue & Self.pureKeyMask) }
}

extension CGEventField: Codable {
    static let subType = Self(rawValue: 110)!
    static let magnification = Self(rawValue: 113)!
    static let phase = Self(rawValue: 132)!
}

extension CGEvent {
    enum SubType: Int64 {
        case magnification = 8
        case other
    }
    
    enum Phase: Int64 {
        case began = 1
        case other
    }
    
    var subType: SubType { SubType(rawValue: getIntegerValueField(.subType)) ?? .other }
    
    var magnification: Double {
        get { getDoubleValueField(.magnification) }
        set { setDoubleValueField(.magnification, value: newValue) }
    }
    
    var phase: Phase { Phase(rawValue: getIntegerValueField(.phase)) ?? .other }
}

