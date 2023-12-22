import Cocoa

typealias Callback = () -> ()

extension CGEventFlags: Codable, Hashable {
    static let maskNoFlags = Self([])
    
    init?(_ string: String) {
        guard let i = UInt64(string) else { return nil }
        self = Self(rawValue: i)
    }
    
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

func CGEvent(flagsChangedEventSource source: CGEventSource?, flags: CGEventFlags ) -> CGEvent? {
    let result = CGEvent(source: source)
    result?.type = .flagsChanged
    result?.flags = flags
    return result
}

extension Dictionary {
    func mapKeys<T>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        try .init(uniqueKeysWithValues: map{ (k, v) in try (transform(k), v) })
    }
    func compactMapKeys<T>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        try .init(uniqueKeysWithValues: compactMap{ (k, v) in try transform(k).map{ t in (t, v) } })
    }
}

extension NSMenuItem {
    static private var assotiationKey = "callback"
    
    var callback: Callback? {
        get { objc_getAssociatedObject(self, &Self.assotiationKey) as? Callback }
        set { objc_setAssociatedObject(self, &Self.assotiationKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    
    convenience init(title: String, isChecked: Bool = false, callback: @escaping Callback) {
        self.init(title: title, action: #selector(callback(sender:)), keyEquivalent: "")
        self.callback = callback
        self.target = self
        self.state = isChecked ? .on : .off
    }
    
    @objc private func callback(sender: Any) {
        callback?()
    }
}
