# PinchBar Refactoring TODO

## 2. MultitouchSupport-Interface verbessern

**Ziel:** Kopplung zwischen `EventTap` und `MultitouchSupport` auflösen.

**Status quo:** `EventTap.init` (Zeilen 40-46) kennt `MiddleClickMapping` by name, ruft `Multitouch.setOnTrackpadTap` auf und startet Multitouch. Das ist konzeptionell falsch platziert.

**Vorschlag:**
- `Multitouch.start()` in `AppDelegate.applicationDidFinishLaunching` verschieben
- Callback-Registrierung: Entweder `MiddleClickMapping` registriert sich selbst im `init`, oder `AppDelegate` orchestriert die Verdrahtung
- Observable-Pattern (z.B. Closure-basierter Publisher auf `Multitouch`) wäre möglich, aber bei nur einem Consumer (`MiddleClickMapping.onTrackpadTap`) vermutlich overengineered
- Einfaches Callback reicht

**Niedrigere Priorität:** Umbau von static Singleton zu echtem Service -- geringer Benefit bei der aktuellen Projektgröße und der ObjC++-Bridge mit globalen C-Variablen.

## 6. Settings-Defaults separieren

**Ziel:** `Settings.Defaults` aus `Settings.swift` in eigene Datei extrahieren.

**Vorteil:** Neue Presets hinzufügen, ohne die Settings-Logik zu berühren.

## 8. Ordnerstruktur

**Status:** Weitgehend umgesetzt. `EventMapping/` und `Utilities/` existieren. Noch offen:
- Ggf. `Settings.swift` + `Settings.Defaults` in eigene `Settings/`-Gruppe (siehe Punkt 6)
- Ggf. `MultitouchSupport.h/.mm` in eigene `Multitouch/`-Gruppe
- Ggf. `Repository.swift`, `StatusMenu.swift`, `AppDelegate.swift` in `App/`-Gruppe -- Mehrwert bei der aktuellen Projektgröße aber fraglich
