# Implementierungsplan: Logitech-HID++-USB-Dongle-Backend (Unifying und Bolt)

**Status: Implementiert und live mit einem Unifying-Receiver verifiziert.** Dieser Plan schliesst das in
`docs/logi-hidpp-thumb-buttons-plan.md` beschriebene zweite Backend ab. Er baut auf dem bereits
vorhandenen Bluetooth-Backend auf und macht dessen `LogiMouseZoomMapping` ohne Änderungen auch
für über einen Unifying- oder Bolt-Receiver gekoppelte Mäuse nutzbar.

**Scope:** Ein reines Swift-Backend `LogiUSBButtonSource` auf Basis der öffentlichen
`IOHIDManager`-API. Es erkennt alle Logitech-Receiver mit HID++-Rohkanal, ermittelt die am
Receiver gekoppelten HID++-2.0-Mäuse und liefert deren divertierte CIDs als Down-/Up-Events.
Unterstützt werden mehrere Receiver und mehrere Geräte pro Receiver. Keine Änderungen an
Settings, Status-Menü, `LogiMouseZoomMapping` oder dem öffentlichen
`HIDPPButtonSource`-Protokoll.

**Ergebnis der Umsetzung:** `LogiUSBButtonSource` scannt Receiver-Slots, liest die CID- und
Reporting-Tabellen von HID++-Mäusen, verwaltet deren Divert-Zustand und liefert
`divertedButtonsEvent` als Down-/Up-Callbacks. Der Unifying-Receiver mit einer Maus an Slot
`0x02` wurde mit dem bestehenden `LogiMouseZoomMapping` erfolgreich end-to-end getestet.

**Verbleibende Arbeiten:** Bolt sowie mehrere Receiver/Mäuse sind noch nicht gegen Hardware
verifiziert. Ein Request-Timeout für unbeantwortete Receiver-Slots und die sofortige lokale
Aktualisierung von `HIDPPCidInfo.isDiverted` nach `setDivert` sind sinnvolle Robustheitsarbeiten,
aber für den verifizierten Unifying-Pfad nicht erforderlich.

---

## Verifizierte Ausgangslage

- `PinchBar/HIDPP/HIDPPMessageCodec.swift` arbeitet bereits auf der transportneutralen Ebene
  `[featureIndex, funcId << 4 | swId, params...]` und enthält alle für Feature `0x1B04`
  benötigten Request-/Decoder-Funktionen.
- `HIDPPButtonSource` liefert die benötigte API: `start`, `stop`, Geräte-/CID-Abfrage,
  `setDivert` sowie `onButtonEvent` und `onDeviceReady`.
- `LogiBLEButtonSource` demonstriert den gewünschten Zustandsablauf:
  `Root.getFeature` -> `getCount` -> `getCidInfo*` -> `getCidReporting*` -> bereit. Seine
  Device-State-Maschine kann fachlich übernommen, nicht aber direkt geteilt werden, weil USB
  einen Receiver mit mehreren `devIndex`-Geräten statt einer GATT-Verbindung pro Gerät hat.
- `LogiHIDPP` ist bereits als Liste von Backends aufgebaut; derzeit fehlt nur
  `LogiUSBButtonSource()` in dieser Liste.
- `IOKit.framework` ist schon gelinkt. Es werden keine weiteren Frameworks, Entitlements oder
  Privacy-Usage-Descriptions benötigt.
- Die lokale Referenz `~/Devel/logitech-ipc-protocol/hidpp_thumb_buttons.py` hat das
  Unifying-Framing gegen Hardware verifiziert: kurze Reports `0x10`, lange Reports `0x11`, jeweils
  gefolgt von `devIndex` und der logischen HID++-Nachricht. Der Indexbereich `0x01...0x06` deckt
  die sechs Pairing-Slots eines Unifying-Receivers ab. Der Scan wird auch für Bolt verwendet; die
  Implementierung darf deshalb weder die Produkt-ID `0xC52B` noch den Produktnamen fest verdrahten.

---

## Zielarchitektur

```
PinchBar/HIDPP/
├── HIDPPMessageCodec.swift    unverändert: logische HID++-Nachrichten
├── HIDPPButtonSource.swift    unverändert: Backend-Vertrag
├── LogiBLEButtonSource.swift  unverändert: Backend 1
├── LogiUSBButtonSource.swift  neu: Backend 2, IOHIDManager + Receiver-Framing
└── LogiHIDPP.swift            erweitert: BLE- und USB-Backend starten
```

`LogiUSBButtonSource` besitzt pro physischem Receiver einen `ReceiverState` und darin pro
gefundenem `devIndex` einen `DeviceState`. Der Schlüssel muss Receiver-Identität **plus** Index
sein: `devIndex` allein ist bei zwei gleichzeitig angeschlossenen Receivern nicht eindeutig.

Der Empfangspfad ist:

```
IOHID input report -> USB frame decoder -> (receiver, devIndex, HIDPPMessage)
    -> ausstehende Antwort oder spontane 0x1B04-Nachricht
    -> DeviceState / Set-Diff der gedrückten CIDs -> onButtonEvent
```

Alle `IOHIDManager`-Callbacks und Timer laufen auf dem Main-RunLoop in `.commonModes`. Damit
bleibt die Thread-Annahme des bestehenden `LogiMouseZoomMapping` gültig: dessen HID++-Callback und
der Event-Tap greifen nicht gleichzeitig auf `buttonDown` zu. Kein zusätzlicher Lock ist nötig.

---

## 1. `LogiUSBButtonSource.swift` anlegen

`import Foundation` und `import IOKit.hid` verwenden. Die Klasse implementiert
`HIDPPButtonSource` direkt und erhält keine neue öffentliche API.

### Receiver-Erkennung und Lifecycle

1. `IOHIDManagerCreate` erzeugen und einen Matching-Dictionary mit ausschließlich
   `kIOHIDVendorIDKey = 0x046D` und `kIOHIDPrimaryUsagePageKey = 0xFF00` setzen.
   Die Vendor-Usage-Page selektiert den HID++-Rohkanal und schliesst die normalen Maus-/Tastatur-
   Interfaces des Receivers aus. Produkt-ID, Produktname und Transportart dürfen nicht als Filter
   dienen, damit Unifying und Bolt gemeinsam funktionieren.
2. Device-Matching-, Device-Removal- und Input-Report-Callbacks registrieren, den Manager auf dem
   Main-RunLoop in `.commonModes` schedulen und mit `kIOHIDOptionsTypeNone` öffnen. Kein Seize:
   Die normale HID-Verarbeitung sowie Logi Options+ oder Solaar dürfen weiterlaufen.
3. Beim Hinzufügen einen `ReceiverState` mit `IOHIDDevice`, einer pro Receiver stabil gehaltenen
   Laufzeit-ID, Receivername aus `kIOHIDProductKey` und einem Dictionary `[UInt8: DeviceState]`
   anlegen. Dann den Scan seriell für `0x01...0x06` starten.
4. Beim Entfernen alle Device-States dieses Receivers löschen. Für jede noch gedrückte CID vorher
   ein Up-Event senden, damit ein laufender Zoom sicher endet. `connectedDevices` enthält danach
   keine verwaiste Identität mehr.
5. `stop()` entfernt die Run-Loop-Scheduling, schliesst und released den Manager, verwirft alle
   States und setzt die Callbacks nicht zurück. `start()` muss nach `stop()` erneut funktionieren
   und bei wiederholtem Start ohne Wirkung bleiben.

`HIDPPDeviceID.identifier` wird beim erfolgreichen Finden eines `(ReceiverState, devIndex)` genau
einmal mit `UUID()` erzeugt und bis zur Receiver-Entfernung behalten. Er ist bewusst nicht
persistent, analog zur Bluetooth-UUID-Verwendung im aktuellen POC. Der Name soll für Diagnose und
Status mindestens Receivername und Index enthalten, beispielsweise
`"Logitech USB receiver 0x02"`; ein unsicher erratener Mausname ist nicht sinnvoll.

### USB-Frame-Code strikt kapseln

Direkt in dieser Datei eine private Repräsentation wie
`USBHIDPPFrame { reportMarker, deviceIndex, message }` anlegen. Sie ist die einzige Stelle, die
HID++-USB-Frames kennt:

- `0x10` ist ein kurzer Report: Marker, `devIndex`, zwei Message-Header-Bytes und maximal drei
  Parameterbytes.
- `0x11` ist ein langer Report: Marker, `devIndex`, zwei Message-Header-Bytes und maximal sechzehn
  Parameterbytes.
- Der Decoder entfernt Marker und Index, erstellt `HIDPPMessage(messageBytes:)` und ignoriert
  unbekannte Marker oder unvollständige Frames.
- Der Encoder wählt `0x10`, wenn die logische Nachricht hoechstens drei Parameter hat, sonst
  `0x11`; er pad'det auf die feste HID++-Reportlaenge. `setCidReporting` muss daher als langer
  Report gesendet werden, weil es fünf Parameter hat.

Die IOKit-Report-ID-Semantik muss vor der finalen Encoder-Signatur mit echter Hardware geloggt und
festgelegt werden: `IOHIDDeviceRegisterInputReportCallback` liefert `reportID` getrennt vom
Buffer, und `IOHIDDeviceSetReport` erhält ihn separat. Der Probe-Log protokolliert daher
`reportID`, Laenge und Hex-Bytes eines empfangenen `0x10`- und `0x11`-Reports. Danach wird zentral
entschieden, ob der IOKit-Buffer den Marker noch enthält oder ob `reportID` als Marker vorangestellt
werden muss, sowie ob `IOHIDDeviceSetReport` den Marker aus dem Payload erwartet. Kein anderer
Code darf diese Fallunterscheidung duplizieren. Der Plan setzt nicht voraus, dass sich dies allein
aus hidapi-Verhalten ableiten laesst.

### Serielle Request-/Response-Maschine

Ein Receiver besitzt nur einen bidirektionalen Reportkanal, auf dem Antworten und spontane
Notifications aller `devIndex` interleaved eintreffen. Deshalb dürfen Requests nicht wie im
Python-Prototyp blockierend gelesen werden.

1. Eine FIFO `pendingRequests` pro Receiver verwaltet Request, Ziel-`devIndex`, erwarteten
   Feature-/Funktions-/Software-ID-Header, Erfolg-Closure und Fehler-Closure. Es wird stets nur
   **ein** Request pro Receiver gleichzeitig gesendet.
2. Nach dem Senden startet ein kurzer `Timer` auf dem Main-RunLoop (z. B. 1 s). Nur eine Antwort
   mit passendem `devIndex` und passendem Header beendet den ausstehenden Request und startet den
   nächsten. Antworten anderer Geräte und spontane Events bleiben davon unberührt.
3. HID++-2.0-Fehler (`featureIndex == 0xFF`) und HID++-1.0-Fehler (`featureIndex == 0x8F`) für den
   erwarteten Request werden als Fehler behandelt. Timeouts und Fehler beim Index-Scan bedeuten
   „nicht belegt oder Feature nicht vorhanden“, nicht einen Abbruch des ganzen Receivers.
4. Die Queue erhält eine Obergrenze und jede Request-Closure prüft, ob ihr Receiver und Device-State
   noch vorhanden sind. Das verhindert, dass verspätete Antworten nach dem Ausstecken oder nach
   einer erneuten Enumeration alten Zustand wiederbeleben.
5. Eingehende `swId == 0`-Events werden niemals als Antworten verbraucht. Für einen bereiten
   Device-State und dessen Feature-Index wird `HIDPP.isDivertedButtonsEvent` verwendet; der
   bestehende Set-Diff-Ansatz liefert pro `devIndex` korrekte Down-/Up-Paare, auch bei
   überlappenden Tasten.

### Geräte-Setup und Capability-Filter

Für jeden Index `0x01...0x06` dieselbe Abfolge wie im BLE-Backend in die Receiver-FIFO einreihen:

1. `HIDPP.getFeatureRequest(featureId: HIDPP.featureIdSpecialKeysAndMouseButtons)` senden. Ein
   Feature-Index `0`, HID++-Fehler oder Timeout verwirft nur diesen Slot.
2. `getCount`, dann für alle Einträge `getCidInfo` ausführen.
3. Nur Geräte behalten, deren Capability-Tabelle mindestens eine CID mit
   `HIDPP.cidFlagIsMouseButton` enthält. Das schliesst Empfaenger-Tastaturen sauber aus, ohne auf
   Back/Forward als unvollständiges Merkmal zu vertrauen.
4. Für jede divertierbare CID `getCidReporting` anfragen und daraus die vollständige
   `[HIDPPCidInfo]` aufbauen; nicht-divertierbare CIDs wie im BLE-Backend danach ergänzen.
5. Erst danach `DeviceState.ready = true` setzen, das Gerät in `connectedDevices` sichtbar machen
   und `onDeviceReady` einmal auslösen. Das bestehende EventTap-Wiring kann so für die konfigurierte
   CID bei Bedarf `setDivert` aufrufen.

`setDivert(cid:enabled:for:)`, `cidTable(for:)` und `connectedDevices` suchen nur in den bereiten
USB-Device-States. `setDivert` legt einen langen Request in die FIFO; es darf keinen direkten,
konkurrierenden Report schreiben. Die CID-Tabelle wird nach erfolgreichem Setzen lokal mit dem
neuen `isDiverted`-Wert aktualisiert.

---

## 2. Fassade registrieren

In `PinchBar/HIDPP/LogiHIDPP.swift` ausschließlich die Backend-Liste erweitern:

```swift
private let backends: [any HIDPPButtonSource] = [
    LogiBLEButtonSource(),
    LogiUSBButtonSource(),
]
```

Die vorhandenen `didSet`-Weiterleitungen für `onButtonEvent` und `onDeviceReady` bleiben
unverändert. Auch `EventTap.swift`, `LogiMouseZoomMapping.swift`, `PreMapping.swift` und
`Settings.swift` benötigen keine Änderung: Das Mapping konsumiert bereits die transportagnostische
Fassade.

---

## 3. Diagnostik und Fehlerverhalten

- Beim Finden/Entfernen eines Receivers, beim erfolgreichen Setup eines `devIndex`, bei HID++-
  Fehlern und Request-Timeouts eine knappe `NSLog`-Zeile ausgeben. Rohreport-Hexdumps nur hinter
  einem privaten Debug-Schalter, damit Button-Events das Log nicht fluten.
- Ein fehlerhafter oder nicht-HID++-fähiger Logitech-USB-Controller darf weder den Manager noch den
  Scan anderer Receiver beeinträchtigen.
- Mehrfaches `onDeviceReady` für denselben noch angeschlossenen Slot verhindern. Bei Receiver-
  Reconnect darf es nach einer neuen Enumeration einmal erneut auftreten, damit Divert wieder
  gesetzt werden kann.
- Alle Eingangsdaten validieren: Marker, Mindestlaenge, `devIndex`, Feature-Index und
  Request-Header. Ungültige Frames werden geloggt und verworfen, nie per Force-Unwrap verarbeitet.

---

## Manuelle Verifikation

Ein Testtarget existiert nicht. Die Codec-Logik bleibt unverändert; der Schwerpunkt liegt daher auf
echter Unifying- und Bolt-Hardware.

1. Build ohne Warnungen ausführen; sicherstellen, dass kein neues Framework und keine
   Berechtigungsabfrage hinzugekommen ist.
2. Unifying-Receiver ohne gekoppelte HID++-Maus einstecken: Der `0x01...0x06`-Scan muss sauber
   durchlaufen, keine Geräte und keine wiederholten Timeouts nach Abschluss.
3. Unifying-Receiver mit einer Maus und optional einer Tastatur testen: Nur die Maus erscheint nach
   dem Mouse-Capability-Filter, die CID-Tabelle stimmt mit dem BLE-Backend bzw. Logitech-Tools
   überein.
4. Back, Forward und SmartShift einzeln sowie überlappend drücken: Die Logs müssen je Gerät exakt
   ein Down und ein Up pro Zustandswechsel liefern.
5. Für eine nicht bereits divertierte CID `setDivert(..., true, ...)` über das bestehende
   `onDeviceReady`-Wiring auslösen; kontrollieren, dass danach Events eintreffen und die Taste
   nicht zugleich ihre Standardaktion ausführt. Mapping deaktivieren und Verhalten nach einem
   neuen App-Start prüfen.
6. Zwei Mäuse am selben Receiver testen. Ihre gleichen CIDs müssen getrennte `DeviceState`
   besitzen, damit ein Up der ersten Maus keinen Zoom der zweiten beendet.
7. Zwei Receiver gleichzeitig testen (mindestens Unifying plus Bolt, falls verfügbar). Events und
   Setup-Antworten dürfen nicht receiverübergreifend zugeordnet werden.
8. Einen Receiver während gedrückter Taste abziehen: Ein synthetisches Up beendet den Magnify-
   Zustand; Wiedereinstecken entdeckt die Geräte erneut und aktiviert Divert erneut.
9. Bolt-Receiver mit derselben Sequenz prüfen. Besonders die Report-ID-/Payload-Probe aus Schritt 1
   dokumentieren; falls Bolt ein abweichendes IOKit-Reportlayout zeigt, wird ausschließlich der
   gekapselte USB-Frame-Adapter erweitert, nicht der Codec oder die Consumer-API.
10. End-to-end mit aktivem `Logi Mouse Zoom`: konfigurierte Taste halten und scrollen erzeugt
    Magnify; ohne Taste bleibt normales Scrollen erhalten.

---

## Nicht Teil dieses Plans

- Persistente, benutzerlesbare Identifikation einer über Dongle gekoppelten Maus. `devIndex` ist ein
  Pairing-Slot und keine exportierbare Geräteidentität.
- Eine UI zur Auswahl von Receiver, Maus, CID oder Divert-Verhalten.
- Unterstützung von Logitech-Gaming-Receivern oder beliebigen Vendor-HID-Interfaces außerhalb des
  HID++-Kanals `usagePage 0xFF00`.
- Änderungen am HID++-Codec für weitere Features als `0x1B04`.
