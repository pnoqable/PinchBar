import Cocoa

extension CGEventField: @retroactive Codable {
    static let subtype = Self(rawValue: 110)!
    static let magnification = Self(rawValue: 113)!
    static let magnificationPhase = Self(rawValue: 132)!
}

extension CGEventFlags: @retroactive Codable, @retroactive Hashable {
    static let maskNoFlags = Self([])
    static let maskModifierKeys = Self([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    var justModifiers: Self { intersection(.maskModifierKeys) }
}

extension CGEventType: @retroactive Comparable {
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

extension CGMouseButton: @retroactive Codable {
    static let fourth = Self(rawValue: 3)!
    static let fifth  = Self(rawValue: 4)!
}
