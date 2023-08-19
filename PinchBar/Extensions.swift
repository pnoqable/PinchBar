import Cocoa

typealias Callback = () -> ()
typealias UnaryFunc<P, R> = (P) -> R
typealias Setter<P> = UnaryFunc<P, ()>

infix operator <-

func <-<A, B, C>(abc: @escaping (A) -> (B) -> C, b: B) -> (A) -> C {
    { a in abc(a)(b) }
}

func <-<A, B, C>(abc: @escaping (A) -> ((B?) -> C)?, b: B?) -> (A) -> C? {
    { a in abc(a)?(b) }
}

func <-<A, C>(abc: @escaping (A) -> () -> C, b: Void) -> (A) -> C {
    { a in abc(a)() }
}

infix operator ∘ // Unicode 2218 ring operator

func ∘<A, B, C>(bc: @escaping UnaryFunc<B, C>, ab: @escaping UnaryFunc<A, B>) -> UnaryFunc<A, C> {
    { a in bc(ab(a)) }
}

func ∘<A, B, C>(bc: @escaping UnaryFunc<B, C>, ab: @escaping UnaryFunc<A, B?>) -> UnaryFunc<A, C?> {
    { a in ab(a).map(bc) }
}

infix operator ∈: ComparisonPrecedence // Unicode 2208 element of

func ∈<Element: Equatable>(element: Element, sequence: some Sequence<Element>) -> Bool {
    sequence.contains(element)
}

func ∈<Element>(element: Element, range: some RangeExpression<Element>) -> Bool {
    range.contains(element)
}

extension Array {
    static func +(array: Self, optional: Element?) -> Self {
        optional.map { array + [$0] } ?? array
    }
    
    static func +(optional: Element?, array: Self) -> Self {
        optional.map { [$0] + array } ?? array
    }
    
    func filter<T>(_ type: T.Type) -> [T] {
        filter { $0 is T } as! [T]
    }
    
    func filterForEach<T>(_ body: (T) -> ()) {
        filter(T.self).forEach(body)
    }
    
    func filterMap<A, B>(_ transform: UnaryFunc<A, B>) -> [B] {
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
    
    convenience init(title: String, isChecked: Bool = false, _ callback: @escaping Callback) {
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

class Weak<T: AnyObject, R> {
    weak var instance: T?
    let function: UnaryFunc<T, R?>
    
    init(_ instance: T, _ function: @escaping UnaryFunc<T, R?>) {
        self.instance = instance
        self.function = function
    }
    
    private func execute() -> R? { instance.flatMap(function) }
    
    func call   () -> R?                      { execute() }
    func call   ()       where R == ()        { execute() }
    func call   ()       where R == Callback  { execute()?() }
    func call<P>(_ p: P) where R == Setter<P> { execute()?(p) }
}
