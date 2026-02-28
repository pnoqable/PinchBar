import Foundation

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
