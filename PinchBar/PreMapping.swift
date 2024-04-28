import Foundation

enum PreMapping: Comparable {
    case magicMouseZoom  (MagicMouseZoomMapping.Settings)
    case middleClick     (MiddleClickMapping.Settings)
    case multiTap        (MultiTapMapping.Settings)
    case otherMouseScroll(OtherMouseScrollMapping.Settings)
    case otherMouseZoom  (OtherMouseZoomMapping.Settings)
    
    var mapping: any EventMapping {
        switch self {
        case let .magicMouseZoom  (settings): return MagicMouseZoomMapping  (settings)
        case let .middleClick     (settings): return MiddleClickMapping     (settings)
        case let .multiTap        (settings): return MultiTapMapping        (settings)
        case let .otherMouseScroll(settings): return OtherMouseScrollMapping(settings)
        case let .otherMouseZoom  (settings): return OtherMouseZoomMapping  (settings)
        }
    }
}

extension PreMapping {
    static let magicMouseZoom   = Self.magicMouseZoom  (.init(sensivity: 0.005))
    static let middleClick      = Self.middleClick     (.init(onMousepad: 2, onTrackpad: 3))
    static let multiTap         = Self.multiTap        (.init(oneAndAHalfTapFlags: .maskAlternate,
                                                              doubleTapFlags:      .maskCommand))
    static let otherMouseScroll = Self.otherMouseScroll(.init(button: .fourth, noClicks: true))
    static let otherMouseZoom   = Self.otherMouseZoom  (.init(button: .center, noClicks: false,
                                                              sensivity: 0.003, minimalDrag: 2,
                                                              doubleClickFlags: .maskAlternate,
                                                              tripleClickFlags: .maskCommand))
}

extension PreMapping: Codable {
    enum CodingKeys: CodingKey {
        case magicMouseZoom, middleClick, multiTap, otherMouseScroll, otherMouseZoom
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        guard let key = c.allKeys.first, c.allKeys.count == 1 else {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: c.codingPath, debugDescription:
                                                                "Invalid number of keys found, expected one."))
        }
        
        switch key {
        case .magicMouseZoom:   self = .magicMouseZoom  (try c.decode(MagicMouseZoomMapping.Settings.self,   forKey: key))
        case .middleClick:      self = .middleClick     (try c.decode(MiddleClickMapping.Settings.self,      forKey: key))
        case .multiTap:         self = .multiTap        (try c.decode(MultiTapMapping.Settings.self,         forKey: key))
        case .otherMouseScroll: self = .otherMouseScroll(try c.decode(OtherMouseScrollMapping.Settings.self, forKey: key))
        case .otherMouseZoom:   self = .otherMouseZoom  (try c.decode(OtherMouseZoomMapping.Settings.self,   forKey: key))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case let .magicMouseZoom(settings):   try c.encode(settings, forKey: .magicMouseZoom)
        case let .middleClick(settings):      try c.encode(settings, forKey: .middleClick)
        case let .multiTap(settings):         try c.encode(settings, forKey: .multiTap)
        case let .otherMouseScroll(settings): try c.encode(settings, forKey: .otherMouseScroll)
        case let .otherMouseZoom(settings):   try c.encode(settings, forKey: .otherMouseZoom)
        }
    }
}
