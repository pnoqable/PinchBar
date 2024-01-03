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
        let result = self.copy()!
        result.flags = flags
        return result
    }
}

func CGEvent(flagsChangedEventSource source: CGEventSource?, flags: CGEventFlags ) -> CGEvent? {
    let result = CGEvent(source: source)
    result?.type = .flagsChanged
    result?.flags = flags
    result?.timestamp = DispatchTime.now().uptimeNanoseconds
    return result
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

extension Decodable {
    init(fromPlist obj: Any, options: JSONSerialization.WritingOptions = .fragmentsAllowed) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: options)
        self = try JSONDecoder().decode(Self.self, from: data)
    }
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

extension Encodable {
    var isNil: Bool { self as AnyObject is NSNull } // https://stackoverflow.com/a/68682982
    
    func plist(options opt: JSONSerialization.ReadingOptions = .fragmentsAllowed) throws -> Any? {
        isNil ? nil : try JSONSerialization.jsonObject(with: JSONEncoder().encode(self), options: opt)
    }
}

extension NSMenuItem {
    static private var assotiationKey = "callback".data(using: .utf8)! as NSData
    
    var callback: Callback? {
        get { objc_getAssociatedObject(self, Self.assotiationKey.bytes) as? Callback }
        set { objc_setAssociatedObject(self, Self.assotiationKey.bytes, newValue, .OBJC_ASSOCIATION_RETAIN) }
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

protocol ObservableUserDefault {
    func setChangedCallback(_ callback: Callback?)
}

protocol WithUserDefaults {
}

extension WithUserDefaults {
    var allUserDefaults: [ObservableUserDefault] {
        Mirror(reflecting: self).children.map(\.value).filter(ObservableUserDefault.self)
    }
    
    func setAllUserDefaultsChangedCallbacks(_ callback: Callback?) {
        allUserDefaults.forEach(ObservableUserDefault.setChangedCallback <- callback)
    }
}

@propertyWrapper
class UserDefault<T: Codable>: NSObject, ObservableUserDefault {
    let userDefaults: UserDefaults
    let key: String
    var cachedValue: T
    var cacheInvalid = true
    var callWhenChanged: Callback?
    
    init(wrappedValue: T, _ key: String, _ userDefaults: String? = nil) {
        self.userDefaults = userDefaults.map(\.unsafelyUnwrapped ∘ UserDefaults.init) ?? .standard
        self.cachedValue  = wrappedValue
        self.key          = key
        super.init()
        
        self.userDefaults.addObserver(self, forKeyPath: key, context: nil)
    }
    
    convenience init(_ key: String, userDefaults: String? = nil) where T: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil, key, userDefaults)
    }
    
    var wrappedValue: T {
        get {
            if cacheInvalid, let plist = userDefaults.object(forKey: key) {
                do { cachedValue = try T(fromPlist: plist) }
                catch { NSLog("Couldn't decode \(key): \(error)") }
            }
            
            cacheInvalid = false
            return cachedValue
        }
        set {
            cachedValue = newValue
            do { try userDefaults.set(cachedValue.plist(), forKey: key) }
            catch { NSLog("Couldn't encode \(key): \(error)") }
        }
    }
    
    func setChangedCallback(_ callback: Callback?) {
        callWhenChanged = callback
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        cacheInvalid = true
        callWhenChanged?()
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
