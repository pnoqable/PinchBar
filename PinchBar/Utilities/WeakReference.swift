import Foundation

class WeakVar<T: AnyObject> {
    weak var instance: T?
    
    init(_ instance: T? = nil) {
        self.instance = instance
    }
}

class WeakFunc<T: AnyObject, M>: WeakVar<T> {
    let getter: UnaryFunc<T, M?>
    
    init(_ instance: T, _ getter: @escaping UnaryFunc<T, M?>) {
        self.getter = getter
        super.init(instance)
    }
    
    var method: M? { instance.flatMap(getter) }
    
    func call   ()       where M == Callback  { method?() }
    func call<P>(_ p: P) where M == Setter<P> { method?(p) }
}
