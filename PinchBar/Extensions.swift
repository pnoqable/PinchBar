import Cocoa

typealias Callback = () -> ()
typealias Setter<P> = (P) -> ()
typealias UnaryFunc<P, R> = (P) -> R

infix operator °

func °<A, B, C>(bc: @escaping UnaryFunc<B, C>, ab: @escaping UnaryFunc<A, B>) -> UnaryFunc<A, C> {
    { bc(ab($0)) }
}

func °<A, B, C>(bc: @escaping UnaryFunc<B, C>, ab: @escaping UnaryFunc<A, B?>) -> UnaryFunc<A, C?> {
    { ab($0).map(bc) }
}

extension Array {
    static func +(array: Self, optional: Element?) -> Self {
        optional.map { array + [$0] } ?? array
    }
    
    static func +(optional: Element?, array: Self) -> Self {
        optional.map { [$0] + array } ?? array
    }
    
    func callAll() where Element == Callback {
        forEach { $0() }
    }
    
    func callAll<P>(with p: P) where Element == Setter<P> {
        forEach { $0(p) }
    }
    
    func filter<T>(_ type: T.Type) -> [T] {
        filter { $0 is T } as! [T]
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

protocol ObservableUserDefault {
    func setChangedCallback(_ callback: Callback?)
}

@propertyWrapper
class UserDefault<T: Codable>: NSObject, ObservableUserDefault {
    let userDefaults = UserDefaults.standard
    let key: String
    var cachedValue: T
    var cacheInvalid = true
    var callWhenChanged: Callback?
    
    init(wrappedValue: T, _ key: String) {
        self.cachedValue = wrappedValue
        self.key         = key
        super.init()
        
        userDefaults.addObserver(self, forKeyPath: key, context: nil)
    }
    
    convenience init(_ key: String) where T: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil, key)
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

class WeakMethod<T: AnyObject, M> {
    weak var instance: T?
    let method: (T) -> M
    
    init(_ instance: T, _ method: @escaping (T) -> M) {
        self.instance = instance
        self.method = method
    }
}

class WeakCallback<T: AnyObject>: WeakMethod<T, Callback?> {
    func get() { instance.map(method)??() }
}

extension WeakCallback {
    convenience init<P>(_ instance: T, _ method: @escaping (T) -> Setter<P>?, _ p: P) {
        self.init(instance) { instance in { method(instance)?(p) } }
    }
}

class WeakSetter<T: AnyObject, P>: WeakMethod<T, Setter<P>> {
    func set(param: P) { instance.map(method)?(param) }
}
