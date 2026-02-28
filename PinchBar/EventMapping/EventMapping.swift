import Cocoa

protocol EventMapping {
    associatedtype Settings: Codable
    var settings: Settings { get }
    
    init(_ settings: Settings)
    
    var eventMask: CGEventMask { get }
    
    func map(_ event: CGEvent) -> [CGEvent]
}

class SettingsHolder<Settings> {
    let settings: Settings
    
    required init(_ settings: Settings) {
        self.settings = settings
    }
}
