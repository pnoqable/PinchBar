import Cocoa

typealias Callback = () -> ()
typealias UnaryFunc<P, R> = (P) -> R
typealias Setter<P> = UnaryFunc<P, ()>

infix operator <-

func <-<A, B>(ab: @escaping (A) -> B, a: A) -> () -> B {
    { ab(a) }
}

infix operator <--

func <--<A, B, C>(abc: @escaping (A) -> (B) -> C, b: B) -> (A) -> C {
    { a in abc(a)(b) }
}

func <--<A, C>(abc: @escaping (A) -> () -> C, b: Void) -> (A) -> C {
    { a in abc(a)() }
}

func <--<A, C>(abc: @escaping (A) -> () throws -> C, b: Void) -> (A) throws -> C {
    { a in try abc(a)() }
}

infix operator ∘: MultiplicationPrecedence // Unicode 2218 ring operator

func ∘<A, B, C>(bc: @escaping UnaryFunc<B, C>, ab: @escaping UnaryFunc<A, B>) -> UnaryFunc<A, C> {
    { a in bc(ab(a)) }
}

func ∘<A, B, C>(bc: @escaping UnaryFunc<B, C>, ab: @escaping UnaryFunc<A, B?>) -> UnaryFunc<A, C?> {
    { a in ab(a).map(bc) }
}

func ∘<A, B, C>(bc: @escaping (B, B) -> C, ab: @escaping UnaryFunc<A, B>) -> (A, A) -> C {
    { a1, a2 in bc(ab(a1), ab(a2)) }
}

infix operator ∈: ComparisonPrecedence // Unicode 2208 element of

func ∈<Element: Equatable>(element: Element, sequence: some Sequence<Element>) -> Bool {
    sequence.contains(element)
}

func ∈<Element>(element: Element, range: some RangeExpression<Element>) -> Bool {
    range.contains(element)
}

infix operator ∉: ComparisonPrecedence // Unicode 2209 ∉ not an element of

func ∉<Element: Equatable>(element: Element, sequence: some Sequence<Element>) -> Bool {
    !(element ∈ sequence)
}

func ∉<Element>(element: Element, range: some RangeExpression<Element>) -> Bool {
    !(element ∈ range)
}

struct ArbitraryCodingKey: CodingKey {
    let stringValue: String
    
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) { nil }
    var intValue: Int? { nil }
}

extension Array {
    static func +(array: Self, optional: Element?) -> Self {
        optional.map { array + [$0] } ?? array
    }
    
    static func +(optional: Element?, array: Self) -> Self {
        optional.map { [$0] + array } ?? array
    }
}

extension CGEventField: Codable {
    static let subtype = Self(rawValue: 110)!
    static let magnification = Self(rawValue: 113)!
    static let magnificationPhase = Self(rawValue: 132)!
}

extension CGEventFlags: Codable, Hashable {
    static let maskNoFlags = Self([])
    static let maskModifierKeys = Self([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    var justModifiers: Self { intersection(.maskModifierKeys) }
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
    
    var mouseButton: CGMouseButton {
        get { .init(rawValue: UInt32(getIntegerValueField(.mouseEventButtonNumber)))! }
        set { setIntegerValueField(.mouseEventButtonNumber, value: Int64(newValue.rawValue)) }
    }
    
    var mouseClickState: Int64 {
        get { getIntegerValueField(.mouseEventClickState) }
        set { setIntegerValueField(.mouseEventClickState, value: newValue) }
    }
    
    var mouseDeltaX: Int64 {
        get { getIntegerValueField(.mouseEventDeltaX) }
        set { setIntegerValueField(.mouseEventDeltaX, value: newValue) }
    }
    
    var mouseDeltaY: Int64 {
        get { getIntegerValueField(.mouseEventDeltaY) }
        set { setIntegerValueField(.mouseEventDeltaY, value: newValue) }
    }
    
    var scrollDeltaAxis1: Int64 {
        get { getIntegerValueField(.scrollWheelEventDeltaAxis1) }
        set { setIntegerValueField(.scrollWheelEventDeltaAxis1, value: newValue) }
    }
    
    var scrollPointDeltaAxis1: Int64 {
        get { getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
        set { setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: newValue) }
    }
    
    var scrollUnit: CGScrollEventUnit {
        get { getIntegerValueField(.scrollWheelEventIsContinuous) != 0 ? .pixel : .line }
        set { setIntegerValueField(.scrollWheelEventIsContinuous, value: newValue == .pixel ? 1 : 0) }
    }
    
    var scrollUnitsDeltaAxis1: Int32 {
        get { Int32(scrollUnit == .pixel ? scrollPointDeltaAxis1 : scrollDeltaAxis1) }
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

extension CGMouseButton: Codable {
    static let fourth = Self(rawValue: 3)!
    static let fifth  = Self(rawValue: 4)!
}

extension CodingKey {
//    var description: String { stringValue }
}

extension Collection {
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

protocol ComparableWithoutOrder: Comparable {}
extension ComparableWithoutOrder {
    static func<(lhs: Self, rhs: Self) -> Bool { false }
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
    
    func sortedByValueAndKey() -> [(key: Key, value: Value)] where Key: Comparable, Value: Comparable {
        sorted { (lhs, rhs) in (lhs.value, lhs.key) < (rhs.value, rhs.key) }
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

@objc protocol WithTargetAndAction {
    var target: AnyObject? { get set }
    var action: Selector? { get set }
}

extension NSCell: WithTargetAndAction {}
extension NSControl: WithTargetAndAction {}
extension NSMenuItem: WithTargetAndAction {}

class WithTargetAndActionHelper {
    static let key = ( "callback".data(using: .utf8)! as NSData ).bytes
    
    let callback: Callback
    
    init?(_ callback: Callback?) {
        guard let callback else { return nil }
        self.callback = callback
    }
    
    @objc func call() {
        callback()
    }
}

extension WithTargetAndAction {
    private var callbackHolder: WithTargetAndActionHelper? {
        get { objc_getAssociatedObject(self, WithTargetAndActionHelper.key) as? WithTargetAndActionHelper }
        set { objc_setAssociatedObject(self, WithTargetAndActionHelper.key, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    
    var callback: Callback? {
        get { callbackHolder?.callback }
        set { callbackHolder = WithTargetAndActionHelper(newValue)
            target = callbackHolder
            action = callbackHolder.map { _ in #selector(WithTargetAndActionHelper.call) }
        }
    }
}

extension NSMenuItem {
    convenience init(title: String, isChecked: Bool = false, _ callback: Callback? = nil) {
        self.init()
        self.title = title
        self.callback = callback
        self.state = isChecked ? .on : .off
    }
}

protocol UserDefaultProtocol {
    var key: String { get }
    func setChangedCallback(_ callback: Callback?)
    func decode(_ plist: Any) throws
    func plist() throws -> Any?
}

@propertyWrapper
class UserDefault<T: Codable>: NSObject, UserDefaultProtocol {
    let userDefaults: UserDefaults
    let key: String
    var cachedValue: T
    var cacheInvalid = true
    var callWhenChanged: Callback?
    
    init(wrappedValue: T, _ key: String, _ userDefaults: String? = nil) {
        assert(userDefaults == nil || UserDefaults(suiteName: userDefaults!) != nil)
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
    
    func decode(_ plist: Any) throws {
        wrappedValue = try T(fromPlist: plist)
    }
    
    func plist() throws -> Any? {
        try wrappedValue.plist()
    }
}

class Weak<T: AnyObject, M> {
    weak var instance: T?
    let getter: UnaryFunc<T, M?>
    
    init(_ instance: T, _ getter: @escaping UnaryFunc<T, M?>) {
        self.instance = instance
        self.getter = getter
    }
    
    var method: M? { instance.flatMap(getter) }
    
    func call   ()       where M == Callback  { method?() }
    func call<P>(_ p: P) where M == Setter<P> { method?(p) }
}

protocol WithUserDefaults {
}

extension WithUserDefaults {
    var allUserDefaults: [String: UserDefaultProtocol] {
        Dictionary(grouping: Mirror(reflecting: self).children.map(\.value)
            .filter(UserDefaultProtocol.self), by: \.key).mapValues(\.first.unsafelyUnwrapped)
    }
    
    func setAllUserDefaultsChangedCallbacks(_ callback: Callback?) {
        allUserDefaults.values.forEach(UserDefaultProtocol.setChangedCallback <-- callback)
    }
    
    func decodeAllUserDefaults(fromJSON data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.typeMismatch(Self.self, DecodingError.Context(
                codingPath: [], debugDescription: "Wrong type, expected Dictionary."))
        }
        
        let userDefaults = allUserDefaults
        for (key, plist) in dict {
            guard let userDefault = userDefaults[key] else {
                let codingKey = ArbitraryCodingKey(stringValue: key)
                throw DecodingError.keyNotFound(codingKey, DecodingError.Context(
                    codingPath: [codingKey], debugDescription: "Key not found: \(key)"))
            }
            
            do {
                try userDefault.decode(plist)
            } catch DecodingError.typeMismatch(let type, let context) {
                let codingKey = ArbitraryCodingKey(stringValue: key)
                throw DecodingError.typeMismatch(type, DecodingError.Context(
                    codingPath: codingKey + context.codingPath,
                    debugDescription: context.debugDescription,
                    underlyingError: context.underlyingError))
            }
        }
    }
    
    func encodeAllUserDefaultsAsJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: allUserDefaults
            .mapValues(UserDefaultProtocol.plist <-- ()), options: [.prettyPrinted, .sortedKeys])
    }
}
