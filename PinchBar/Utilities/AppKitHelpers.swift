import Cocoa

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
