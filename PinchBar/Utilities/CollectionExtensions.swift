import Foundation

extension Array {
    static func +(array: Self, optional: Element?) -> Self {
        optional.map { array + [$0] } ?? array
    }
    
    static func +(optional: Element?, array: Self) -> Self {
        optional.map { [$0] + array } ?? array
    }
}

extension Collection {
    func filter<T>(_ type: T.Type) -> [T] {
        compactMap { $0 as? T }
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
