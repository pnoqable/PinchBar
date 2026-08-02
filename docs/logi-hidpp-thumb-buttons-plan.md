# Entwicklungsplan: Generische Logitech-HID++-Maustasten-Schnittstelle (Bluetooth, USB-erweiterbar)

**Status: ✅ Umgesetzt und live gegen echte Hardware verifiziert** (siehe „Ergebnis der Umsetzung“
unten). Scope-Grenzen des Plans (siehe unten) wurden eingehalten.

**Scope dieser Iteration:** Nur die wiederverwendbare Swift-Schnittstelle (Protokoll + Bluetooth-Backend)
zur Zustandsabfrage beliebiger HID++-CIDs (Maustasten) an beliebigen Logitech-Mäusen, architektonisch
offen für ein späteres USB-Dongle-Backend. **Keine** Einbindung als PinchBar-`EventMapping`/
Settings/StatusMenu in dieser Iteration – das ist als Folgearbeit skizziert.

---

## Ergebnis der Umsetzung

Alle vier geplanten Dateien wurden unter `PinchBar/HIDPP/` angelegt, das Projekt um
`CoreBluetooth.framework` sowie `NSBluetoothAlwaysUsageDescription` in `Info.plist` ergänzt. Build
ist grün, keine Warnungen. **Code-Kommentare und Strings sind auf Englisch** (Entwicklungssprache
von PinchBar) – nur dieser Planungsbericht bleibt auf Deutsch, analog zur bestehenden `TODO.md`.

**Live-Verifikation gegen die echte, per Bluetooth gekoppelte MX Anywhere 3:**
- Codec (`HIDPPMessageCodec`) gegen reale, historische Byte-Sequenzen aus
  `pinchbar-session-handoff.md` geprüft (Root.getFeature, divertedButtonsEvent für Forward/Back/leer,
  getCidReporting, setCidReporting) – alle Werte korrekt dekodiert/kodiert.
- Generische Geräteerkennung über den Vendor-GATT-Service funktioniert ohne Namens-Hardcoding: Von
  zwei gleichzeitig gekoppelten Logitech-Geräten (MX Anywhere 3 + MX Keys) wurde **nur** die Maus
  erkannt, die Tastatur korrekt über den Mouse-Flag-Filter ausgeschlossen.
- CID-Tabelle stimmt exakt mit den bekannten Referenzwerten überein (Left/Right nicht divertierbar;
  Middle/Back/Forward/SmartShift divertierbar; Back/Forward/SmartShift bereits `diverted=true` –
  deckt sich mit dem bekannten Befund aus `pinchbar-session-handoff.md` Abschnitt 4).
- Echte Tastendrücke (Back/Forward/SmartShift) lieferten saubere, korrekt gepaarte DOWN/UP-Events,
  auch bei zeitlich überlappenden Tastendrücken korrekt per Set-Diff verarbeitet.

**Kleine Abweichungen/Ergänzungen gegenüber dem ursprünglichen Plan:**
- `LogiBLEButtonSource` hat einen zusätzlichen `init(delegateQueue: DispatchQueue? = nil)`-Parameter
  (Default weiterhin `nil` = Hauptthread, wie geplant). Grund: Testbarkeit außerhalb einer echten
  Cocoa-App mit laufendem Main-RunLoop (in der Live-Verifikation ohne diesen Parameter lief die
  CoreBluetooth-Callback-Kette in der verwendeten `Xcode_RunCodeSnippet`-Testumgebung nicht an, da
  dort kein echter Main-RunLoop gepumpt wird – im eigentlichen App-Kontext ist `nil` weiterhin die
  richtige Wahl).
- Konkreter `swId`-Wert für eigene Requests: `0x4` (bisher unbenutzt laut bekannter Liste in
  `HIDPPMessageCodec.swift`).

---

## Ausgangslage (aus Recherche)

- `~/Devel/logitech-ipc-protocol/ble_hidpp_thumb_buttons.swift`: funktionierender CoreBluetooth-Prototyp,
  hardcodiert aber Gerätename `"MX Anywhere 3"`, keine Reconnect-Logik, kein Multi-Device-Support, kein
  eigener `setCidReporting` mehr (Divert ist bei dieser Maus dauerhaft aktiv).
- `~/Devel/logitech-ipc-protocol/hidpp_thumb_buttons.py`: Referenz für das USB/Unifying-Dongle-Framing
  (`0x10`/`0x11`-Reports + `devIndex`), zeigt dass Root.GetFeature/CID-Tabelle/divertedButtonsEvent
  transportunabhängig gleich funktionieren, nur das Byte-Framing unterscheidet sich.
- `pinchbar-session-handoff.md` Abschnitt 4/6: BLE-Framing bit-genau verifiziert
  (`[featureIndex][funcId<<4|swId][params...]`, kein Marker/kein devIndex), Divert bei Back/Forward
  läuft dauerhaft, Mehrfach-Listener (Options+ + eigenes Tool) unproblematisch.
- PinchBar-Architektur: `EventTap.swift:40-46` zeigt bereits das Muster „Sonderfall-Cast auf konkreten
  Mapping-Typ → externe Callback-Quelle koppeln“ (analog `MiddleClickMapping`).
  `MiddleClickMapping.onTrackpadTap()` zeigt das Muster „asynchrones externes Event → direkt
  `CGEvent(...).post(tap: .cghidEventTap)`, ohne Umweg über den Tap-Proxy“. `MultitouchSupport.mm` zeigt
  das Architekturmuster (gekapselter globaler Zustand + Mutex + C-Callback), das hier aber **nicht** 1:1
  übernommen wird, da CoreBluetooth eine moderne öffentliche Swift-API ist (kein ObjC++-Bridging nötig).
- Weder `CoreBluetooth` noch `IOHIDManager` sind aktuell in PinchBar eingebunden; keine Sandbox/
  Entitlements vorhanden → nur `NSBluetoothAlwaysUsageDescription` in `Info.plist` nötig.

---

## Zielarchitektur

```
PinchBar/HIDPP/
├── HIDPPMessageCodec.swift   – transport-unabhängige HID++-2.0-Nachrichtenschicht         ✅
├── HIDPPButtonSource.swift   – öffentliches Protokoll + Modelltypen                       ✅
├── LogiBLEButtonSource.swift – Backend 1: CoreBluetooth-GATT-Implementierung              ✅
└── LogiHIDPP.swift           – Fassade (Singleton, "Multitouch"-artige API, reines Swift)  ✅
```

**Designentscheidung (Begründung):** Reiner Swift-Service statt ObjC++-Bridge wie
`MultitouchSupport.mm`, weil CoreBluetooth eine öffentliche, typsichere Swift/Cocoa-API ist – anders als
die private Multitouch-C-API gibt es keinen Grund für eine Sprachbrücke. Die strukturelle Idee
(gekapselter Zustand, Singleton-Fassade, Callback-Registrierung) wird aber übernommen.

### 1. `HIDPPMessageCodec.swift` – reine Byte-Logik, transportunabhängig ✅

- `struct HIDPPMessage { let featureIndex: UInt8; let funcId: UInt8; let swId: UInt8; let params: [UInt8] }`
- Encode/Decode auf **Nachrichtenebene** (ohne Transport-Marker):
  - Root.getFeature-Request/-Response (Feature-ID → Feature-Index)
  - `getCount`/`getCidInfo` → CID-Tabelle (`cid`, `flags`; Bit0 = „ist Maustaste“ – wichtig, um z.B. eine
    parallel gekoppelte MX Keys-Tastatur zu unterscheiden, siehe `hidpp_thumb_buttons.py:217`/Kommentar
    zu Device-Index 0x01)
  - `getCidReporting`/`setCidReporting` (divert/persist/rawXY/remap-Flags, portiert aus
    `ble_hidpp_check_divert_state.swift`/`ble_hidpp_reset_divert.swift`)
  - `divertedButtonsEvent`-Decoder (bis 4 CIDs als BE16, Liste endet bei `cid==0`)
- `cidNames`-Tabelle, `featureIdSpecialKeysAndMouseButtons`-Konstante, dedizierte `ourSwId`-Konstante
  (Kollisionsvermeidung – bekannt belegt: `0x1`/`0x2`/`0x5` eigene Dev-Prototypen, `0x7` OpenRGB,
  `0xA` LGSTrayEx, `0xB` Solaar, `0xD` G HUB, `0xF` Firmware, `0xC` Options+ auf BLE; **gewählt: `0x4`**).
- Bewusst **kein** Bluetooth-Code hier → später 1:1 auch vom USB-Backend nutzbar (das nur ein anderes
  Byte-Framing drumherum legt: `0x10`/`0x11`-Marker + `devIndex`).
- Verifiziert unabhängig von Hardware über `Xcode_RunCodeSnippet` mit realen historischen Byte-Arrays
  aus `pinchbar-session-handoff.md` (kein Testtarget im Projekt vorhanden, siehe AGENTS.md).

### 2. `HIDPPButtonSource.swift` – öffentliches Protokoll ✅

```swift
struct HIDPPDeviceID: Hashable { let identifier: UUID; let name: String }
struct HIDPPCidInfo { let cid: UInt16; let isMouseButton: Bool; let isDivertable: Bool; let isDiverted: Bool }

protocol HIDPPButtonSource: AnyObject {
    var onButtonEvent: ((_ device: HIDPPDeviceID, _ cid: UInt16, _ isDown: Bool) -> Void)? { get set }
    func start()
    func stop()
    var connectedDevices: [HIDPPDeviceID] { get }
    func cidTable(for device: HIDPPDeviceID) -> [HIDPPCidInfo]
    func setDivert(cid: UInt16, enabled: Bool, for device: HIDPPDeviceID)
}
```

`setDivert` bleibt als Fallback erhalten (Handoff Abschnitt 6, Punkt 2: nicht jede Maus/Firmware hat
Divert dauerhaft aktiv wie die getestete MX Anywhere 3) – Default-Verhalten bleibt aber „nur lauschen“,
analog zum aktuellen Prototyp.

### 3. `LogiBLEButtonSource.swift` – Backend 1 (CoreBluetooth) ✅

Portierung von `ble_hidpp_thumb_buttons.swift`, generalisiert:

- **Geräteerkennung generisch statt namensbasiert:** Vendor-GATT-Service
  `00010000-0000-1000-8000-011F2000046D` (enthält `046D` = Logitechs USB-Vendor-ID im UUID-Suffix –
  eindeutig genug). Vorgehen: zuerst `retrieveConnectedPeripherals(withServices: [vendorUUID])`
  versuchen; falls leer, Fallback über die bekannten Standard-UUIDs (`1812`/`180F`/`180A`/`1800`) wie im
  Prototyp, danach per Service-Discovery exakt auf die Vendor-UUID prüfen (nicht nur
  „UUID-String-Länge > 4“-Heuristik). **Live bestätigt.**
- **Mouse- vs. Keyboard-Filter:** Nach Root.getFeature + CID-Tabellenabruf prüfen, ob mind. eine CID das
  „mouse“-Flag (Bit 0) trägt – sonst Gerät ignorieren (relevant, da z. B. eine parallel gekoppelte
  MX Keys denselben Vendor-Service exponiert). **Live bestätigt** (MX Keys wurde bei gleichzeitiger
  Kopplung korrekt ignoriert).
- **Multi-Device-fähig:** State (Feature-Index, zuletzt gedrückte CIDs) pro `CBPeripheral.identifier` in
  einem Dictionary, nicht wie im Prototyp als Einzel-Property.
- **Reconnect-Handling:** `centralManager(_:didDisconnectPeripheral:error:)` implementiert → erneuter
  `connect()`; `centralManagerDidUpdateState` reagiert auf `.poweredOn`-Übergänge mit erneutem
  Discovery-Durchlauf (Bluetooth aus/an, Maus-Schlafmodus). Zusätzlich periodischer Re-Scan-Timer
  (alle 5s) für den Fall, dass ein Gerät erst nach App-Start verbunden wird.
- **Kein eigener SIGINT-Handler nötig** (läuft als Teil der App), aber sauberes `stop()` für
  Testzwecke/Lifecycle.
- CoreBluetooth-Delegate-Queue: `nil` (Hauptthread) im Default – konsistent mit dem Rest von PinchBar,
  das komplett auf dem Main-RunLoop läuft; vermeidet zusätzliche Locking-Komplexität. Zusätzlich per
  `init(delegateQueue:)` injizierbar (siehe „Ergebnis der Umsetzung“ oben).

### 4. `LogiHIDPP.swift` – Fassade ✅

Singleton mit statischer, `Multitouch`-artiger API (`LogiHIDPP.shared.start()`, `.onButtonEvent = ...`),
verwaltet aktuell nur `LogiBLEButtonSource` als Backend, aber als Array/Liste von `HIDPPButtonSource`,
damit ein zweites Backend später einfach ergänzt werden kann, ohne Consumer-Code zu ändern.

---

## Xcode-Projektänderungen ✅

1. `CoreBluetooth.framework` zum Target gelinkt.
2. `Info.plist`: `NSBluetoothAlwaysUsageDescription` ergänzt (englischer Berechtigungsdialog-Text).

---

## Manuelle Verifikation ✅ (kein Testtarget vorhanden, siehe AGENTS.md)

1. Codec-Logik per `Xcode_RunCodeSnippet` gegen reale historische Byte-Sequenzen geprüft – korrekt.
2. Geräteerkennung + CID-Tabelle per `Xcode_RunCodeSnippet` gegen echte, gekoppelte Hardware
   (MX Anywhere 3 + MX Keys) geprüft:
   - Nur MX Anywhere 3 erkannt, MX Keys korrekt gefiltert. ✅
   - CID-Tabelle (Left/Right nicht divertierbar; Middle/Back/Forward/SmartShift divertierbar;
     Back/Forward/SmartShift bereits diverted) stimmt exakt. ✅
3. Echte Tastendrücke (Back/Forward/SmartShift) während eines Live-Tests lieferten korrekte,
   sauber gepaarte DOWN/UP-Events, inkl. korrekter Verarbeitung überlappender Tastendrücke. ✅
4. **Nicht separat getestet** (keine zweite Bluetooth-HID++-Maus verfügbar, kein Bluetooth-Ein-/Aus-Test
   während der Session, kein Schlafmodus-Test): Reconnect-Verhalten nach Disconnect/Bluetooth aus-an,
   Verhalten mit einer zweiten Logitech-BLE-Maus. Code-Pfad ist implementiert und plausibel, aber noch
   nicht live bestätigt – bei Gelegenheit nachholen.

---

## Ausblick: Backend 2 (USB-Dongle) – nur grob skizziert, keine Detailplanung jetzt

- `LogiUSBButtonSource: HIDPPButtonSource` auf Basis von `IOHIDManager` (öffentliche IOKit-API;
  `IOKit.framework` ist bereits gelinkt), analog `hidpp_thumb_buttons.py`:
  - Geräte-Matching über `vendorID 0x046D` + `usagePage 0xFF00`.
  - Kurze/Lange HID++-Reports (`0x10`/`0x11` + `devIndex`) – nutzt dieselbe `HIDPPMessageCodec`, nur
    anderes Framing drumherum.
  - Device-Index-Scan 0x01–0x06 + CID-Tabellen-Abgleich zur Mausidentifikation (wie
    `find_mx_anywhere_3` in der Python-Referenz).
- Gleiche `HIDPPButtonSource`-Schnittstelle → `LogiHIDPP` kann später beide Backends parallel betreiben;
  Consumer-Code bleibt unverändert.
- **Nicht Teil dieser Umsetzung** – weiterhin offen, kein Code vorhanden.

## Follow-up – umgesetzt

`LogiMouseZoomMapping` ist als globales `PreMapping` umgesetzt. Es kombiniert eine konfigurierte
HID++-CID mit dem Scrollrad zu Magnify-Events und arbeitet transportagnostisch über
`LogiHIDPP`, also sowohl mit BLE als auch mit USB-Receivern.
