import Cocoa

typealias Callback = () -> ()

infix operator ∈: ComparisonPrecedence // Unicode 2208 element of

func ∈<Element: Equatable>(element: Element, sequence: some Sequence<Element>) -> Bool {
    sequence.contains(element)
}

func ∈<Element>(element: Element, range: some RangeExpression<Element>) -> Bool {
    range.contains(element)
}

extension Array {
    func callAll() where Element == Callback {
        forEach { $0() }
    }
    
    func filter<T>(_ type: T.Type) -> [T] {
        filter { $0 is T } as! [T]
    }
    
    func filterMap<A, B>(_ transform: (A) -> (B)) -> [B] {
        filter(A.self).map(transform)
    }
}

extension CGEventField: Codable {
    static let subtype = Self(rawValue: 110)!
    static let magnification = Self(rawValue: 113)!
    static let magnificationPhase = Self(rawValue: 132)!
}

extension CGEventFlags: Codable, Hashable {
    static let maskNoFlags = Self([])
    
    // key without left/right info
    static let pureKeyMask = UInt64.max << 8
    
    var purified: Self { Self(rawValue: rawValue & Self.pureKeyMask) }
}

extension CGEventType: Comparable {
    public static func < (lhs: CGEventType, rhs: CGEventType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension CGEvent {
    enum Subtype: Int64 {
        case other = 0
        case magnify = 8
    }
    
    enum Phase: Int64 {
        case other = 0
        case began = 1
        case changed = 2
        case ended = 4
    }
    
    var mouseButtonNumber: Int64 {
        get { getIntegerValueField(.mouseEventButtonNumber) }
        set { setIntegerValueField(.mouseEventButtonNumber, value: newValue) }
    }
    
    var scrollPointDeltaAxis1: Int64 {
        get { getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
        set { setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: newValue) }
    }
    
    var scrollPhase: Phase {
        get { Phase(rawValue: getIntegerValueField(.scrollWheelEventScrollPhase)) ?? .other }
        set { setIntegerValueField(.scrollWheelEventScrollPhase, value: newValue.rawValue) }
    }
    
    var momentumPhase: Bool {
        getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
    }
    
    var subtype: Subtype {
        get { Subtype(rawValue: getIntegerValueField(.subtype)) ?? .other }
        set { setIntegerValueField(.subtype, value: newValue.rawValue) }
    }
    
    var magnification: Double {
        get { getDoubleValueField(.magnification) }
        set { setDoubleValueField(.magnification, value: newValue) }
    }
    
    var magnificationPhase: Phase {
        get { Phase(rawValue: getIntegerValueField(.magnificationPhase)) ?? .other }
        set { setIntegerValueField(.magnificationPhase, value: newValue.rawValue) }
    }
    
    func with(flags: CGEventFlags) -> CGEvent {
        self.flags = flags
        return self
    }
}

func CGEvent(magnifyEventSource source: CGEventSource?, magnification: Double, phase: CGEvent.Phase) -> CGEvent? {
    let result = CGEvent(source: source)
    result?.type = CGEventType(rawValue: 29)!
    result?.subtype = .magnify
    result?.magnification = magnification
    result?.magnificationPhase = phase
    result?.timestamp = DispatchTime.now().uptimeNanoseconds
    return result
}

extension Dictionary {
    func mapKeys<T>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        try .init(uniqueKeysWithValues: map { (k, v) in try (transform(k), v) })
    }
    
    func compactMapKeys<T>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        try .init(uniqueKeysWithValues: compactMap { (k, v) in try transform(k).map { t in (t, v) } })
    }
    
    subscript(key: Key?) -> Value? {
        get { key.flatMap { self[$0] } }
        set { key.map     { self[$0] = newValue } }
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

extension Optional {
    var asArray: [Wrapped] {
        self.map { [$0] } ?? []
    }
}
