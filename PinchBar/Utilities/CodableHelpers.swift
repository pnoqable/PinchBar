import Foundation

struct ArbitraryCodingKey: CodingKey {
    let stringValue: String
    
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) { nil }
    var intValue: Int? { nil }
}

extension Decodable {
    init(fromPlist obj: Any, options: JSONSerialization.WritingOptions = .fragmentsAllowed) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: options)
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}

extension Encodable {
    var isNil: Bool { self as AnyObject is NSNull } // https://stackoverflow.com/a/68682982
    
    func plist(options opt: JSONSerialization.ReadingOptions = .fragmentsAllowed) throws -> Any? {
        isNil ? nil : try JSONSerialization.jsonObject(with: JSONEncoder().encode(self), options: opt)
    }
}
