# Implementierungsplan: `LogiMouseZoomMapping` (POC – Daumentaste + Scrollrad → Pinch-Zoom)

**Status: Implementiert und mit BLE sowie Unifying-USB verifiziert.** Die Umsetzung heißt
`LogiMouseZoomMapping` (nicht `LogiThumbButtonMapping`) und baut auf
`PinchBar/HIDPP/*` auf. Sie schließt die ursprünglich als Follow-up skizzierte Einbindung als
PinchBar-`EventMapping`.

Die nachfolgenden Code-Namen dokumentieren den ursprünglichen Plan. Die Umsetzung verwendet
`LogiMouseZoomMapping`, `logiMouseZoom` und den Menüeintrag `Logi Mouse Zoom`.

**Scope dieser Iteration (POC):** *Eine* fest verdrahtete Aktion – „konfigurierbare Daumentaste
gedrückt halten + Scrollrad drehen → Pinch-Zoom“ – als neues, generisches `PreMapping` (global,
analog zu `Multi Click`/`Multi Tap`). Kein Multi-Device-Handling in der UI (es wird die erste
passende CID über alle verbundenen HID++-Geräte hinweg beobachtet), keine Konfiguration
mehrerer CIDs/Aktionen, kein Settings-UI über den Status-Menü-Toggle hinaus. Diese Grenzen sind
unten unter „Out of Scope“ nochmal explizit aufgeführt.

---

## Ausgangslage

- `PinchBar/HIDPP/` liefert bereits (siehe `docs/logi-hidpp-thumb-buttons-plan.md`):
  - `LogiHIDPP.shared` als Fassade mit `onButtonEvent: ((HIDPPDeviceID, UInt16, Bool) -> Void)?`,
    `start()`/`stop()`, `cidTable(for:)`, `setDivert(cid:enabled:for:)`.
  - Live gegen eine echte MX Anywhere 3 verifiziert: Back/Forward/SmartShift liefern saubere
    DOWN/UP-Events über `onButtonEvent`.
- **Wichtiger Unterschied zu allen bisherigen `EventMapping`s:** Diverted HID++-Tasten erzeugen
  **keine** CGEvents mehr (das ist der Zweck von Divert – die Firmware sendet den Tastendruck nur
  noch über den Vendor-GATT-Kanal statt als normales HID-Report). Der bisherige
  „intercept-transform-repost“-Ansatz (`OtherMouseZoomMapping`, `MiddleClickMapping` für Klicks)
  funktioniert hier also nicht 1:1 – der Tastendruck selbst muss komplett am `CGEventTap` vorbei
  aus dem `LogiHIDPP`-Callback heraus synthetisiert/gesteuert werden. Einzig das Scrollrad der
  Maus liefert weiterhin normale `CGEvent`s (nur die Maustaste wird diverted, nicht das Rad).
- Genau dieses Muster („externes asynchrones Event → Sonderfall-Wiring in `EventTap.init` →
  direktes Posten/Steuern ohne Tap-Proxy“) existiert schon einmal, für Multitouch statt HID++:
  `EventTap.swift:40-42` verdrahtet `Multitouch.setOnTrackpadTap` mit
  `MiddleClickMapping.onTrackpadTap()` (`MiddleClickMapping.swift:43-56`), das dort direkt
  `CGEvent(...).post(tap: .cghidEventTap)` aufruft statt über den Tap-Proxy zu gehen.
- Für die eigentliche Scroll→Magnify-Transformation kann die bestehende Logik aus
  `OtherMouseZoomMapping.swift` fast unverändert übernommen werden – nur dass „Taste gedrückt“
  nicht mehr aus einem `CGEvent.mouseDown` mit `event.mouseButton == settings.button` folgt,
  sondern aus dem HID++-Callback für die konfigurierte `cid`.
- Da die Taste dem Tap nie als Klick-Event begegnet, entfällt das „deferred events“-Pattern aus
  `OtherMouseZoomMapping` komplett (dort nötig, um bei einem reinen Klick ohne Scroll das
  Down/Drag/Up sauber durchzureichen) – es gibt hier schlicht keinen echten Klick, den man
  durchreichen müsste. Das vereinfacht die Implementierung gegenüber dem Vorbild spürbar.

---

## Zielarchitektur

```
PinchBar/EventMapping/
└── LogiThumbButtonMapping.swift   – neu: HID++-CID + Scrollrad → Pinch-Zoom

PinchBar/EventTap.swift            – erweitert um Sonderfall-Wiring (analog Zeile 40-42)
PinchBar/PreMapping.swift          – neuer Case + Default + Codable-Anbindung
PinchBar/Settings.swift            – neuer Eintrag in Defaults.preMappings + disabledPMs
PinchBar/HIDPP/HIDPPButtonSource.swift  – optional (Schritt 2): + onDeviceReady-Callback
PinchBar/HIDPP/LogiBLEButtonSource.swift – optional (Schritt 2): onDeviceReady auslösen
PinchBar/HIDPP/LogiHIDPP.swift          – optional (Schritt 2): onDeviceReady durchreichen
```

### 1. `LogiThumbButtonMapping.swift` – neues `EventMapping`

```swift
import Cocoa

class LogiThumbButtonMapping: SettingsHolder<LogiThumbButtonMapping.Settings>, EventMapping {
    struct Settings: Codable, ComparableWithoutOrder {
        var cid: UInt16       // z.B. 86 = Forward, 83 = Back, 196 = SmartShift (HIDPP.cidNames)
        var sensivity: Double // wie OtherMouseZoomMapping.Settings.sensivity
    }

    // Nur das Scrollrad muss abgefangen werden - der Tastendruck selbst kommt nie hier an.
    var eventMask: CGEventMask { 1 << 22 }

    private var buttonDown = false
    private var magnifying = false

    func map(_ event: CGEvent) -> [CGEvent] {
        guard buttonDown, event.type == .scrollWheel, event.scrollPointDeltaAxis1 != 0 else {
            return [event]
        }

        let phase: CGEvent.Phase = magnifying ? .changed : .began
        magnifying = true

        return [CGEvent(magnifyEventSource: nil,
                        magnification: settings.sensivity * Double(event.scrollPointDeltaAxis1),
                        phase: phase)!.with(flags: event.flags)]
    }

    /// Von `EventTap` mit `LogiHIDPP.shared.onButtonEvent` verdrahtet (siehe dort). Läuft auf dem
    /// Main-Thread (CoreBluetooth-Default-Queue == Hauptthread bei `delegateQueue: nil|),
    /// genau wie der `map(_:)`-Aufruf über den Haupt-RunLoop - kein Locking nötig.
    func onHIDPPButtonEvent(cid: UInt16, isDown: Bool) {
        guard cid == settings.cid else { return }

        buttonDown = isDown

        if !isDown, magnifying {
            magnifying = false
            CGEvent(magnifyEventSource: nil, magnification: 0, phase: .ended)?
                .post(tap: .cghidEventTap)
        }
    }
}
```

**Designentscheidungen:**
- **Aktion = Pinch-Zoom (Magnify), nicht Modifier-Flags oder synthetische Maustaste:** Zoom ist
  die Kernfunktion von PinchBar; „Daumentaste + Rad = Zoom“ ist die naheliegendste, direkt nutzbare
  POC-Aktion und braucht keine neue Abstraktion für „Aktionstyp“ (im Gegensatz zu z.B. einer
  generischen CID→CGEventFlags- oder CID→otherMouseButton-Emulation, die für einen echten
  Mehrzweck-Mechanismus nötig wäre, siehe „Out of Scope“).
- **Kein `deviceID`-Filter in `Settings`:** `HIDPPDeviceID.identifier` ist eine pro Host/Pairing
  generierte Bluetooth-UUID, keine stabile, exportierbare Kennung – für ein Settings-Export/Import
  (siehe `Settings.interactiveExport/-Import`) wäre eine feste UUID in den Defaults unbrauchbar.
  Für den POC reicht „reagiere auf `cid` X, egal an welchem verbundenen HID++-Gerät“ (Ein-Maus-
  Annahme, deckt sich mit dem bisherigen Verifikationsstand in
  `docs/logi-hidpp-thumb-buttons-plan.md`).
- **Kein „deferred events“-Pattern** (anders als `OtherMouseZoomMapping`): nicht nötig, siehe oben.

### 2. `EventTap.swift` – Sonderfall-Wiring

Analog zum bestehenden Muster für `MiddleClickMapping` (Zeile 40-42), aber mit zwei
Unterschieden: (a) der Callback hat 3 Parameter, `WeakFunc.call` deckt nur 0/1-Parameter-Methoden
ab (`Operators.swift:3-5`) → manuelle `[weak ...]`-Closure statt `WeakFunc`; (b)
`LogiHIDPP.shared.start()` wird **nicht** unconditional wie `Multitouch.start()` aufgerufen,
sondern nur, wenn dieses Mapping tatsächlich aktiv ist (vermeidet CoreBluetooth-Start/
Permission-Prompt für alle Nutzer ohne konfigurierte Logi-Maustaste):

```swift
if let mcMapping = mapping as? MiddleClickMapping {
    Multitouch.setOnTrackpadTap(WeakFunc(mcMapping, MiddleClickMapping.onTrackpadTap).call)
}

if let thumbMapping = mapping as? LogiThumbButtonMapping {
    LogiHIDPP.shared.onButtonEvent = { [weak thumbMapping] _, cid, isDown in
        thumbMapping?.onHIDPPButtonEvent(cid: cid, isDown: isDown)
    }
    LogiHIDPP.shared.start()
}
```

**Hinweis Lifecycle:** `activeAppChanged()` erzeugt bei jedem App-Wechsel alle `EventTap`s neu
(`AppDelegate.swift:27`). `LogiHIDPP.shared.start()` ist bereits idempotent
(`guard central == nil else { return }`, `LogiBLEButtonSource.swift:80`), ein wiederholter Aufruf
bei jedem App-Wechsel ist also unschädlich – analog zu `Multitouch.start()`, das ebenfalls nie
wieder gestoppt wird. Kein `LogiHIDPP.shared.stop()` in `EventTap.deinit` vorgesehen (gleiche
Begründung: einmal gestartet, bleibt es wie bei Multitouch aktiv, kein Bluetooth-Auf/Ab bei jedem
App-Wechsel).

### 3. `PreMapping.swift` – neuer Case

```swift
case logiThumbZoom(LogiThumbButtonMapping.Settings)
```

- `mapping`-Switch: `case let .logiThumbZoom(settings): return LogiThumbButtonMapping(settings)`
- Default: `static let logiThumbZoom = Self.logiThumbZoom(.init(cid: 86, sensivity: 0.003))`
  (CID 86 = Forward, gleiche Sensitivität wie `otherMouseZoom5th`)
- `CodingKeys`/`init(from:)`/`encode(to:)` um `logiThumbZoom` ergänzen (gleiches Boilerplate-Muster
  wie die bestehenden sieben Cases).

### 4. `Settings.swift` – Registrierung

```swift
static let preMappings = [..., "Logi Thumb Zoom": PreMapping.logiThumbZoom]
```

**Standardmäßig deaktiviert** (analog `"Other Mouse Zoom Mid"`):

```swift
@UserDefault("disabledPMs") var disabledPMs = Set<String>(["Other Mouse Zoom Mid", "Logi Thumb Zoom"])
```

Begründung: Ohne kompatible Logitech-Maus ist die Funktion wirkungslos; ein standardmäßig aktiver
Bluetooth-Scan (inkl. erstmaligem Permission-Prompt) für alle Nutzer ist nicht gerechtfertigt.
Nutzer mit passender Maus aktivieren die Funktion selbst über „Global Mappings“ im Status-Menü
(kein UI-Code nötig – das Menü wird bereits generisch aus `preMappingNames` gebaut,
`StatusMenu.swift:79-83`).

---

## Schritt 2 (empfohlen, aber optional für den POC): Divert automatisch sicherstellen

Die bisher einzige verifizierte Maus (MX Anywhere 3) hat Divert für Back/Forward/SmartShift
**dauerhaft aktiv** (siehe `docs/logi-hidpp-thumb-buttons-plan.md`, Abschnitt „Ergebnis der
Umsetzung“). Andere Mäuse/Firmwares könnten das nicht tun (`HIDPPButtonSource.setDivert` existiert
explizit als Fallback dafür). Für einen robusten POC über die eine getestete Maus hinaus:

**`HIDPPButtonSource.swift`** – neuer optionaler Callback:

```swift
/// Called once a device finishes its capability query and is ready (i.e. now included in
/// `connectedDevices`). Optional hook for consumers to (re-)enable divert for CIDs of interest,
/// since not every firmware keeps divert permanently active like the tested MX Anywhere 3.
var onDeviceReady: ((HIDPPDeviceID) -> Void)? { get set }
```

**`LogiBLEButtonSource.swift`** – in `finishSetup(_:isMouse:)`, direkt nachdem `state.phase = .ready`
gesetzt wurde: `onDeviceReady?(state.deviceID)` aufrufen.

**`LogiHIDPP.swift`** – analog zu `onButtonEvent` durchreichen (`didSet` auf alle `backends`
verteilen).

**`EventTap.swift`** – im selben `if let thumbMapping = mapping as? LogiThumbButtonMapping`-Block:

```swift
LogiHIDPP.shared.onDeviceReady = { [weak thumbMapping] device in
    guard let thumbMapping else { return }
    LogiHIDPP.shared.setDivert(cid: thumbMapping.settings.cid, enabled: true, for: device)
}
```

Ohne diesen Schritt funktioniert der POC weiterhin für jede Maus, deren Divert-Zustand für die
gewählte CID bereits (dauerhaft oder durch ein anderes Tool wie Options+/Solaar) aktiv ist – wie
bei der bisher einzigen getesteten Hardware.

---

## Thread-Safety

- `LogiBLEButtonSource` ruft `onButtonEvent` auf der `CBCentralManager`-Delegate-Queue auf; per
  Default (`delegateQueue: nil`) ist das laut CoreBluetooth-Doku die **Hauptqueue**.
- `EventTap`s `CGEventTapCallBack` läuft über den am Haupt-RunLoop registrierten
  `CFRunLoopSource` (`EventTap.swift:38`) ebenfalls auf dem **Hauptthread**.
- Da `buttonDown`/`magnifying` in `LogiThumbButtonMapping` nur von `map(_:)` (Tap-Callback) und
  `onHIDPPButtonEvent(_:_:)` (HID++-Callback) gelesen/geschrieben werden und beide auf dem
  Hauptthread laufen, ist **kein zusätzliches Locking nötig** – ein bewusster Unterschied zu
  `MultitouchSupport.mm`, das für den C-Callback aus einem Fremd-Thread einen
  `std::recursive_mutex` braucht.

---

## Xcode-Projektänderungen

1. Neue Datei `PinchBar/EventMapping/LogiThumbButtonMapping.swift` zum Target hinzufügen.
2. Keine neuen Frameworks/Entitlements nötig – `CoreBluetooth.framework` und
   `NSBluetoothAlwaysUsageDescription` sind bereits aus der HIDPP-Basisarbeit vorhanden.

---

## Manuelle Verifikation (kein Testtarget vorhanden, siehe AGENTS.md)

1. App bauen/starten, MX Anywhere 3 per Bluetooth gekoppelt lassen.
2. Status-Menü → „Global Mappings“ → „Logi Thumb Zoom“ aktivieren (Default: aus) und prüfen, dass
   **erst jetzt** der Bluetooth-Permission-Prompt erscheint (falls noch nicht erteilt) – bestätigt,
   dass `LogiHIDPP.shared.start()` wirklich erst bei aktivem Mapping läuft.
3. Forward-Taste (CID 86, Default) gedrückt halten + Scrollrad drehen in einer beliebigen App →
   Zoom-Verhalten prüfen (Lupe/Zoom je nach App, analog zu bestehendem Verhalten von
   `Other Mouse Zoom 5th` mit einer echten Maustaste).
4. Taste **während** des Scrollens loslassen → prüfen, dass der Zoom sauber mit `.ended`
   abgeschlossen wird (kein hängender `.changed`-Zustand).
5. Scrollrad drehen, **ohne** die Taste zu halten → normales Scrollen darf nicht beeinflusst
   werden (insbesondere kein Leaken von `magnifying`-Zustand zwischen Sessions).
6. Taste halten, aber **nicht** scrollen → keine Zoom-Events, kein Seiteneffekt (kein Klick, keine
   Navigation - da divertiert, sollte ohnehin nichts anderes mehr passieren).
7. Falls Schritt 2 umgesetzt wird: Divert testweise über `setDivert(cid:enabled:false:for:)`
   deaktivieren (z.B. per Debug-Snippet), Mapping neu aktivieren/App neu starten, prüfen dass es
   sich selbst wieder aktiviert (`onDeviceReady` greift).
8. Settings-Export/Import: `Logi Thumb Zoom`-Konfiguration (cid/sensivity) muss im JSON auftauchen
   und nach Import erhalten bleiben (`Settings.interactiveExport/-Import`).

---

## Verbleibender Scope außerhalb dieses POCs

- **Konfigurations-UI für `cid`/Aktionstyp** über den reinen An/Aus-Toggle im Status-Menü hinaus
  (kein Sub-Menü zur Tastenauswahl, keine Sensitivitätsregler) – deckt sich mit dem offenen
  Roadmap-Punkt „Settings window“ in `README.md`.
  Aktuell nur über direktes Bearbeiten der `Settings.Defaults`/exportiertes JSON änderbar.
- **Mehrere gleichzeitige CID→Aktion-Zuordnungen** (z.B. Back = Zoom, Forward = horizontales
  Scrollen, SmartShift = Modifier-Flag) – bräuchte ein generischeres `Settings`-Modell
  (`[UInt16: Action]` statt einzelner `cid`) und eine `Action`-Enum (Magnify/Flags/OtherMouseButton).
- **Geräte-spezifische Zuordnung** (verschiedene CIDs/Aktionen für unterschiedliche gleichzeitig
  gekoppelte Logi-Mäuse) – bräuchte eine stabile, exportierbare Geräte-Identifikation statt der
  transienten Bluetooth-`UUID` in `HIDPPDeviceID`.
- **Bolt- und Multi-Receiver-Verifikation:** `LogiUSBButtonSource` ist umgesetzt und der
  Unifying-Pfad live verifiziert. Die Mapping-Schicht bleibt transportagnostisch; Bolt und mehrere
  Receiver/Mäuse benötigen nur noch Hardware-Tests, keine Mapping-Änderung.
- **App-spezifisches Scoping** (`Preset` statt `PreMapping`) – die Daumentaste ist als globale
  Geräteeigenschaft modelliert, nicht als App-spezifisches Zoom-Verhalten wie `PinchMapping`.
