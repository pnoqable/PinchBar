# PinchBar – Agent Guide

This repository contains the macOS menu bar app **PinchBar**, which enables continuous pinch-to-zoom for Cubase and similar applications by transforming multitouch gestures into appropriate scroll/key events.

## Project Overview

- **Platform:** macOS (Cocoa/AppKit)
- **Languages:** Swift (primary), Objective-C++ (Multitouch bridge)
- **Entry point:** `PinchBar/AppDelegate.swift`
- **Core domains:**
  - Multitouch event capture (`MultitouchSupport.h`, `MultitouchSupport.mm`)
  - Event tapping and transformation (`EventTap.swift`, `EventMapping.swift`, `PreMapping.swift`, `Preset.swift`)
  - Event state machines (`EventStateMachine.swift`)
  - User defaults-backed configuration (`Settings.swift`, `Extensions.swift` – `UserDefault` machinery)
  - Status bar UI and app integration (`StatusMenu.swift`, `Repository.swift`)

## Building and Running

This is a standard Xcode project.

### Build Commands

```bash
# Open project in Xcode
open PinchBar.xcodeproj

# Build from command line
xcodebuild -project PinchBar.xcodeproj -scheme PinchBar -configuration Debug build
xcodebuild -project PinchBar.xcodeproj -scheme PinchBar -configuration Release build

# Clean build
xcodebuild -project PinchBar.xcodeproj -scheme PinchBar clean
```

### Run from Xcode

- **Scheme:** `PinchBar`
- **Target:** `PinchBar`
- Press Cmd+R to build and run
- On first launch, macOS will prompt for Accessibility permissions (required for event taps)

### No Test Suite

This project has no unit tests or test targets. Manual testing is required with target applications (Cubase, Cubase 13, or any app with scroll-based zoom).

## Code Organization

```
PinchBar/
├── AppDelegate.swift           # Application lifecycle, active app tracking, wires all components
├── EventTap.swift              # CGEvent tap wrapper, owns EventMapping instances
├── EventStateMachine.swift     # Protocol + MapScrollToPinchState for gesture state tracking
├── EventMapping.swift          # EventMapping protocol and concrete implementations
├── PreMapping.swift            # Enum-based pre-mapping configurations
├── Preset.swift                # App-specific preset configurations
├── Settings.swift              # User defaults-backed settings management
├── Repository.swift            # Version checking, GitHub integration, update alerts
├── StatusMenu.swift            # Status bar UI and menus
├── Extensions.swift            # Functional helpers, operators, CGEvent extensions, UserDefault wrapper
├── Extensions.mm               # Objective-C++ bridge helpers
├── MultitouchSupport.h         # Multitouch API header
├── MultitouchSupport.mm        # Objective-C++ bridge to private multitouch APIs
├── Assets.xcassets/            # Images and app icons
└── Info.plist                  # Bundle metadata (LSUIElement=true for menu bar app)

Ressources/                     # App icons and marketing assets (no code)
PinchBar.xcodeproj/             # Xcode project
```

## Key Patterns and Conventions

### Event Taps and Mappings

**EventTap lifecycle:**

1. `AppDelegate.activeAppChanged()` is triggered when frontmost app changes or settings change
2. `settings.mappings(for: activeApp)` returns `[any EventMapping]`
3. Each mapping becomes an `EventTap` instance
4. `EventTap.init`:
   - Creates `CGEvent.tapCreate` with callback to `tap(_:_:)`
   - Adds run loop source to **main run loop** in `.commonModes`
   - For `MiddleClickMapping`, configures `Multitouch.setOnTrackpadTap` with weak reference
   - Starts multitouch support with `Multitouch.start()`
5. `EventTap.tap`:
   - Re-enables tap if disabled by timeout
   - Calls `mapping.map(event)` and posts each returned `CGEvent`

**Event bitmask (line 21 of EventTap.swift):**
```swift
eventsOfInterest: 1<<29 | 1<<22 | 0b111<<25 | 0b1000011111110
```
This captures magnify events, scroll events, mouse events, and flags changed events.

### EventMapping Protocol

All mappings conform to:

```swift
protocol EventMapping {
    associatedtype Settings: Codable
    var settings: Settings { get }
    init(_ settings: Settings)
    func map(_ event: CGEvent) -> [CGEvent]
}
```

**Concrete implementations:**

- `FixLogiFlags` - Workaround for Logitech mice flag glitches
- `MagicMouseZoomMapping` - Maps scroll to magnify for Magic Mouse
- `MiddleClickMapping` - Simulates middle click from multitouch taps
- `MultiClickMapping` - Maps double/triple clicks to modifier flags
- `MultiTapMapping` - Maps gesture taps (1.5-tap, double-tap) to modifiers
- `OtherMouseScrollMapping` - Maps other mouse buttons to horizontal scroll
- `OtherMouseZoomMapping` - Maps other mouse button + scroll to magnify
- `PinchMapping` - Core mapping: pinch → scroll/keys/pinch with modifiers

All use `SettingsHolder<Settings>` base class for settings storage.

### Settings and User Defaults

**Settings architecture:**

- `Settings` conforms to `WithUserDefaults`
- User properties use `@UserDefault` property wrapper
- Reflection-based export/import via `encodeAllUserDefaultsAsJSON()` / `decodeAllUserDefaults(fromJSON:)`
- Merge strategy on init: user-defined entries override defaults

**Key defaults:**

```swift
@UserDefault("preMappings") var preMappings: [String: PreMapping]
@UserDefault("disabledPMs") var disabledPMs: Set<String>
@UserDefault("presets")     var presets: [String: Preset]
@UserDefault("appPresets")  var appPresets: [String: String]
```

**Change notifications:**

- `callWhenMappingsChanged` callback triggers `activeAppChanged()`
- All `UserDefault` properties auto-wired via `setAllUserDefaultsChangedCallbacks`

**Adding new settings:**

1. Use `@UserDefault` wrapper in `Settings`
2. Add default value to `Settings.Defaults` if auto-merge desired
3. Will automatically appear in export/import via reflection

### Functional Helpers (`Extensions.swift`)

**Custom operators:**

- `<-` - Partial application: `(ab: (A) -> B, a: A) -> () -> B`
- `<--` - Flipped partial application for binary functions
- `∘` - Function composition (Unicode 2218)
- `∈` - Element membership (Unicode 2208)
- `∉` - Not an element (Unicode 2209)

**Common patterns:**

```swift
// Partial application
WeakFunc(repository, Repository.checkForUpdates).call <- true

// Composition
settings.compactMapKeys(CGEventFlags.init ∘ UInt64.init)

// Membership
event.type ∈ .leftMouseDown ... .rightMouseUp
```

**CGEvent extensions:**

- `mouseButton`, `mouseClickState`, `mouseDeltaX/Y`
- `scrollDeltaAxis1`, `scrollPointDeltaAxis1`, `scrollUnit`, `scrollUnitsDeltaAxis1`
- `scrollPhase`, `momentumPhase`
- `subtype` (`.other`, `.magnify`)
- `magnification`, `magnificationPhase`
- Factory functions for flags and magnify events

**Weak reference helper:**

```swift
WeakFunc<T: AnyObject, M>  // Holds weak reference + method getter
.call()                     // Calls method if object still alive
```

Use this for callbacks to avoid retain cycles.

### Multitouch Bridge (`MultitouchSupport.mm`)

**Private API wrapper:**

- Wraps `MTDeviceCreateList`, `MTRegisterContactFrameCallback`, etc.
- Tracks devices, determines trackpad vs mousepad (width > height heuristic)
- Maintains `touchCount`, touch start positions, gesture history
- Thread-safe via `std::recursive_mutex` and `std::lock_guard`

**Public API (`Multitouch` class):**

```objc
+ (bool)start;                      // Initialize multitouch tracking
+ (NSInteger)onMousepad;            // Current mousepad touch count (0 if trackpad)
+ (NSInteger)onTrackpad;            // Current trackpad touch count (0 if mousepad)
+ (bool)isOneAndAHalfTap;           // Gesture: tap, lift, tap-hold
+ (bool)isDoubleTap;                // Gesture: tap N fingers twice
+ (void)setOnTrackpadTap:(Callback); // Callback for trackpad taps
+ (NSInteger)lastTouchCount;        // Touch count from last completed tap
```

**Gesture detection:**

- Tap detection: fingers lift within `NSEvent.doubleClickInterval`
- Movement tolerance: 2mm in any direction invalidates tap
- One-and-a-half tap: 1 finger tap, then tap-hold with any number
- Double tap: same finger count tapped twice

### Event State Machines

**MapScrollToPinchState:**

Tracks scroll gesture phases to map scroll events to pinch for Magic Mouse.

**States:**
- `.inactive` - No mapping active
- `.mapping` - Currently mapping scroll → pinch
- `.dropMomentum(since:)` - Dropping momentum scroll events
- `.dropScroll(since:)` - Dropping subsequent scroll events

**Transitions:**
- `.finishMapping` - Scroll ended, stop mapping
- `.finishDropping` - Finished dropping momentum
- `.other` - No state change

**Timing:** Uses `DispatchTime.now()` with 0.1s tolerance for phase detection.

## Application Flow

### Startup

1. `AppDelegate.applicationDidFinishLaunching`:
   - Wires `Settings.callWhenMappingsChanged` to `activeAppChanged` via weak reference
   - Subscribes to `NSWorkspace.didActivateApplicationNotification`
   - Calls `activeAppChanged()` immediately

2. `Repository.init`:
   - Logs version
   - Checks for updates from GitHub API (non-verbose)

### Active App Change

1. `activeAppChanged()`:
   - Gets `NSWorkspace.shared.frontmostApplication?.localizedName`
   - Creates new `EventTap` for each mapping from `settings.mappings(for: activeApp)`
   - If taps created, enables status menu submenus
   - Updates status menu for active app
   - Logs applied mappings

2. Old event taps are deallocated (automatic cleanup via `deinit`)

### Settings Change

- Any `UserDefault` property change triggers `callWhenMappingsChanged`
- Triggers full `activeAppChanged()` cycle (recreates event taps)

### Menu Interactions

**Status Menu structure:**

- About / Check for Updates
- Enable PinchBar in Accessibility (disabled after granted)
- Global Mappings submenu (toggle pre-mappings)
- Change Preset for [App] submenu (select preset)
- Export Settings / Import Settings
- Quit

**Visual state:**

- Icon opaque when active (preset assigned)
- Icon greyed when inactive (no preset or accessibility not granted)
- Menu disabled when modal window shown (prevents conflicts)

## Presets and Pre-Mappings

### Presets (App-specific)

Defined in `Preset.Settings`:

- **Cubase**: Pinch → scroll+CMD (horizontal zoom)
  - Alt: G/H keys + Alt (vertical zoom)
  - Cmd: G/H keys + Shift (track height)
- **Cubase 13**: Pinch → scroll+CMD with different sensitivities
- **Font Size**: Pinch → Cmd+minus/equals (font zoom)
- **Font Size/cmd**: Same but only when Cmd held

Each preset maps `CGEventFlags` → `PinchMapping.Settings`.

### Pre-Mappings (Global)

Applied to all apps before preset:

- **Fix Logi Flags**: Workaround for Logitech flag sync issues
- **Magic Mouse Zoom**: Scroll → magnify for Magic Mouse two-finger scroll
- **Middle Click**: 2-finger mousepad or 3-finger trackpad → middle click
- **Multi Click**: Middle button double/triple click → modifier flags
- **Multi Tap**: 1.5-tap / double-tap gestures → modifier flags
- **Other Mouse Scroll**: 4th mouse button → horizontal scroll
- **Other Mouse Zoom**: Center button + scroll → magnify

Users can disable individual pre-mappings via status menu.

## Important Gotchas

### Thread Safety

- Event taps invoke callbacks on system threads
- Multitouch callbacks use separate threads
- **Always dispatch UI work to main thread** (see `Repository.asyncAlert`)
- Multitouch state guarded by `std::recursive_mutex`

### Private APIs

- `MultitouchSupport.framework` is a private macOS framework
- Symbol signatures could break on macOS updates
- No stable public API alternative exists
- Framework path: `/System/Library/PrivateFrameworks/MultitouchSupport.framework`

### Memory Management

- Cross-language Swift ↔ ObjC++ boundaries require care
- Use `WeakVar` / `WeakFunc` for callbacks to avoid retain cycles
- Global state in `MultitouchSupport.mm` (static variables, mutex)
- `EventTap` holds `WeakVar<EventTap>` to break retain cycle in C callback

### Accessibility Permissions

- Required for `CGEvent.tapCreate` and `CGEvent.tapPostEvent`
- Without permission, taps silently fail
- Check via System Preferences → Security & Privacy → Accessibility
- Deep link: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`

### Event Tap Timeouts

- System disables taps if callback takes too long
- Re-enable via `CGEvent.tapEnable(tap: eventTap, enable: true)`
- Check for `.tapDisabledByTimeout` event type (handled in `EventTap.tap`)

### State Machine Timing

- `MapScrollToPinchState` uses `DispatchTime.now()` for timing
- Apple Silicon note: `event.timestamp` is broken, don't use
- 0.1s tolerance for phase detection
- Incorrect timing can break gesture feel

### User Defaults Migrations

- Merge logic assumes defaults can be merged safely
- Changing keys or structure may break existing user data
- No explicit migration system exists
- Changes will affect export/import compatibility

## Testing Approach

### No Automated Tests

- No unit test targets or test scripts
- Manual testing required

### Manual Testing Checklist

- **Basic functionality:**
  - Launch app, grant accessibility permission
  - Open Cubase, verify status icon becomes opaque
  - Perform pinch gesture, verify zoom works
  - Switch to other app, verify icon greys out

- **Multiple apps:**
  - Enable PinchBar for different apps via status menu
  - Verify presets persist across app switches
  - Test with apps that don't have presets (should grey out)

- **Settings persistence:**
  - Toggle pre-mappings, verify they persist across restart
  - Export settings to JSON file
  - Import settings, verify all settings restored
  - Check that new defaults merge with existing user settings

- **Edge cases:**
  - Very fast pinch gestures
  - Pinch while scrolling
  - Switching apps mid-gesture
  - Multiple multitouch devices connected
  - Trackpad vs Magic Mouse detection

- **Update check:**
  - Verify update check on launch
  - Test manual update check via menu
  - Verify "Don't show again" checkbox works

### Target Apps for Testing

- Cubase (any version) - primary use case
- Cubase 13 - alternate preset
- Any app with Cmd+scroll zoom (web browsers, etc.)
- Apps that don't respond to scroll+modifier (verify graceful no-op)

## Code Style and Conventions

### Swift Style

- **Functional programming bias:**
  - Extensive use of higher-order functions (map, filter, flatMap)
  - Custom operators for composition and partial application
  - Minimal mutation where possible

- **Type inference:**
  - Explicit types when clarity needed
  - Inference for obvious cases

- **Property observers:**
  - `willSet` / `didSet` rarely used (prefer functional callbacks)

- **Naming:**
  - `EventMapping` not `EventMapper` (protocol named after abstraction)
  - `Settings` not `SettingsManager` (avoid "Manager" suffix)
  - Clear intent: `activeAppChanged` not `handleAppChange`

- **Access control:**
  - `private` for implementation details
  - `private(set)` for internal state with public read
  - No access modifier = internal (module-level)

### Objective-C++ Style

- **Modern C++:**
  - `std::recursive_mutex`, `std::lock_guard`, `std::map`, `std::vector`
  - `auto` for type inference
  - Range-based for loops

- **Naming:**
  - `contactFrameCallback` not `ContactFrameCallback` (C++ convention)
  - `isTrackpad` not `is_trackpad` (Objective-C convention in `.mm`)

- **Thread safety:**
  - Always acquire `mutex` before accessing shared state
  - Use RAII (`std::lock_guard`) not manual lock/unlock

### Commenting

- **Minimal comments:**
  - Code should be self-documenting
  - Comments explain *why*, not *what*
  - Magic numbers explained (e.g., `width > height` heuristic)

- **Pragma marks in Objective-C++:**
  - `#pragma mark linked symbols`
  - `#pragma mark private variables`
  - `#pragma mark implementation`

## Common Tasks

### Adding a New EventMapping

1. Define `Settings` struct conforming to `Codable` and `ComparableWithoutOrder`
2. Create class inheriting `SettingsHolder<Settings>` and conforming to `EventMapping`
3. Implement `map(_ event: CGEvent) -> [CGEvent]`
4. Add case to `PreMapping` enum if global, or use in `Preset` if app-specific
5. Update `Settings.Defaults` if new preset
6. Test with target app

### Adding a New Preset

1. Define preset in `Preset.Settings` extension (static let)
2. Map `CGEventFlags` to `PinchMapping.Settings`
3. Add to `Settings.Defaults.presets` dictionary
4. Test with target app

### Modifying Event Tap Interest Mask

Event tap interest mask in `EventTap.swift:21`:

```swift
eventsOfInterest: 1<<29 | 1<<22 | 0b111<<25 | 0b1000011111110
```

- Bit 29: Magnify events (CGEventType.init(rawValue: 29))
- Bit 22: ScrollWheel events
- Bits 25-27: Mouse moved/dragged events
- Bits 1-9: Mouse down/up, flags changed

Add new event types with care—more events = more processing.

### Debugging Event Taps

1. Check accessibility permissions first
2. Add `NSLog` in `EventTap.tap` to see all events
3. Check `EventTap.init` return value (nil if creation failed)
4. Monitor for `.tapDisabledByTimeout` events
5. Use `CGEvent.location` to verify event coordinates
6. Print event type, flags, and relevant fields

### Debugging Multitouch

1. Add logging to `contactFrameCallback` in `MultitouchSupport.mm`
2. Log `touchCount`, `isTrackpad`, `lastTouchCounts`
3. Check `Multitouch.start()` return value
4. Verify devices detected: `CFArrayGetCount(multitouchDevices)`
5. Test on different devices (trackpad, Magic Mouse, regular mouse)

## Git Workflow

Current branch structure (as of latest commits):

- `eventtap-refactoring` - Current development branch
- `experimental` - Experimental features
- Various topic branches for specific features

### Commit Style

Based on git log:

- Prefix with "tmp" for work-in-progress: `tmp eventtap refactoring`
- Descriptive messages: `add functional overkill: function composition...`
- Lowercase, no periods: `add status submenu for global mappings`
- Action verbs: `add`, `fix`, `tmp`, `new`

### No CI/CD

- No GitHub Actions or CI configuration
- No automated build/test/release pipeline
- Manual release process (tag + GitHub release)

## Release Process

Based on `Repository.swift` implementation:

1. Update `CFBundleShortVersionString` in `Info.plist` (or Xcode project settings)
2. Build Release configuration: `xcodebuild -configuration Release`
3. Create git tag with version: `git tag v1.2.3`
4. Push tag: `git push origin v1.2.3`
5. Create GitHub release with tag
6. Attach `PinchBar.app` as `PinchBar.zip`
7. App auto-checks `https://api.github.com/repos/pnoqable/PinchBar/releases/latest`

## Dependencies

### System Frameworks

- `Cocoa.framework` - UI and app lifecycle
- `IOKit.framework` - I/O Kit device notifications
- `MultitouchSupport.framework` (private) - Multitouch tracking

### Third-Party Dependencies

None. Pure macOS system frameworks.

### Swift Version

Determined by Xcode version. No explicit Swift version constraint in project.

## Useful Xcode Settings

From project inspection:

- **Product Name:** PinchBar
- **Bundle Identifier:** (check in Xcode project settings)
- **LSUIElement:** `true` (menu bar app without dock icon)
- **Deployment Target:** (check in Xcode project settings)
- **Architectures:** Universal (Intel + Apple Silicon)

## Resources

- **User Documentation:** `README.md`
- **License:** `LICENSE.md`
- **Project Homepage:** https://github.com/pnoqable/PinchBar
- **Steinberg Forum Thread:** https://forums.steinberg.net/t/pinch-to-zoom-with-a-touchpad/129419

## Tips for AI Agents

### Before Making Changes

1. **Understand the functional style:**
   - Familiarize with `∘`, `<-`, `<--` operators
   - Recognize `WeakFunc` / `WeakVar` patterns
   - Don't fight the style—extend it

2. **Study event flow:**
   - Trace an event from `CGEvent.tapCreate` → `tap` → `map` → `CGEvent.tapPostEvent`
   - Understand state machine transitions
   - Note timing-dependent behavior

3. **Check memory safety:**
   - Look for retain cycles in callbacks
   - Verify weak references used appropriately
   - Ensure mutex held when accessing multitouch state

### When Adding Features

1. **Follow existing patterns:**
   - Use `SettingsHolder` for new mappings
   - Use `@UserDefault` for persistence
   - Use `WeakFunc` for callbacks
   - Use operators for composition

2. **Maintain thread safety:**
   - Dispatch UI work to main thread
   - Guard shared state with mutex (in ObjC++)
   - Test with multiple rapid app switches

3. **Test extensively:**
   - No automated tests mean manual testing is critical
   - Test on different devices (trackpad, mice)
   - Test edge cases (fast gestures, app switching)

### When Debugging

1. **Enable verbose logging:**
   - Add `NSLog` liberally in Swift
   - Add `NSLog` in ObjC++ (or `std::cout` if needed)
   - Log event types, flags, counts, states

2. **Check system logs:**
   - Console.app → filter by "PinchBar"
   - Check for permission errors
   - Look for Framework loading failures

3. **Verify assumptions:**
   - Accessibility permission granted?
   - Event tap created successfully?
   - Multitouch devices detected?
   - Mapping applied to correct app?

### Common Pitfalls

1. **Don't block event tap callbacks:**
   - Keep `map(_:)` fast
   - No network calls, disk I/O, or heavy computation
   - System will disable tap if too slow

2. **Don't assume event order:**
   - Events can arrive out of order
   - State machines must handle unexpected transitions
   - Test rapid gesture changes

3. **Don't break export/import:**
   - Keep `Settings` types `Codable`
   - Test JSON round-trip after changes
   - Consider backward compatibility

4. **Don't hardcode system behavior:**
   - Use `NSEvent.doubleClickInterval` not magic numbers
   - Respect system settings where possible
   - Test on different macOS versions if possible

## Future Roadmap

From `README.md`:

- ✅ Proof of concept
- ✅ Update check
- ✅ First release
- ✅ Readme file
- ⏳ Adjustable sensitivity
- ⏳ Vertical zoom with modifier
- ⏳ Settings window

When implementing these:

- **Adjustable sensitivity:** Add UI for `sensivity` fields in mappings
- **Vertical zoom:** Add axis parameter to `PinchMapping.Settings`
- **Settings window:** Consider SwiftUI for modern UI, or stick with AppKit for consistency
