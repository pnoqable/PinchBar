import Foundation

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

prefix func !<A>(f: @escaping (A) -> Bool) -> (A) -> Bool {
    (!) ∘ f
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

func returnFirst<A, B>(_ first: A, _: B) -> A {
    return first
}
