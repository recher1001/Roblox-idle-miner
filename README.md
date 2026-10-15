# ⛏ Idle Miner Tycoon – Roblox (Rojo-Projekt)

Ein Idle-Miner-Tycoon im Stil von *Idle Miner Tycoon*, kombiniert mit Mechaniken aus den aktuell
meistgespielten Roblox-Spielen (Stehlen & Verteidigen, Sammeln mit Seltenheiten, Server-Events,
tägliche Belohnungen). Der komplette Code liegt als Luau-Dateien vor und wird mit **Rojo** in
Roblox Studio synchronisiert. Die Welt, die Mine und die gesamte UI werden per Code erzeugt –
es werden **keine externen Assets** benötigt.

---

## Inhalt

1. [Features](#features)
2. [Installation (Rojo)](#installation-rojo)
3. [Projekt starten & mit Studio verbinden](#projekt-starten--mit-studio-verbinden)
4. [Wichtige Studio-Einstellungen](#wichtige-studio-einstellungen)
5. [Spiel testen](#spiel-testen)
6. [Projektstruktur](#projektstruktur)
7. [Balancing (Config.luau)](#balancing-configluau)
8. [Eigene Modelle, Sounds, Robux-Produkte](#eigene-modelle-sounds-robux-produkte)
9. [Architektur & Sicherheit](#architektur--sicherheit)
10. [Code prüfen (selene / StyLua)](#code-prüfen-selene--stylua)

---

## Features

| Bereich | Was drin ist |
|---|---|
| **Mining** | Bis zu 10 Ebenen (Kohle → Mythril). Kumpel bauen Erz ab → Schachtlager → Aufzug → Aufzugslager → Händler → Geld |
| **Selbst arbeiten** | Ohne Manager startet jede Station nur, wenn du sie antippst („👆 TIPPEN!“-Hinweis) |
| **Upgrades** | Pro Station eigene Tracks (Tempo, Erzwert, Kapazität, Verkaufspreis) – x1 / x10 / MAX, exponentielle Kosten, Meilenstein-Boni |
| **Manager** | Einstellen für Geld, 5 Seltenheiten (Gewöhnlich → Mythisch) mit Reveal-Animation, automatisieren die Station, passiver Tempo-Bonus + aktive Fähigkeit (Turbo, Goldader, Schwerlast, Sparfuchs), „Alle boosten“ |
| **Freunde-Avatare** | Manager und Kumpel tragen die echten Roblox-Avatare deiner **Freunde** mit Bauarbeiterhelm (Manager-Helm in Seltenheitsfarbe) |
| **Stehlen** | Halte **E** am Aufzugslager eines anderen Spielers, um einen Teil zu klauen. Schutz: Cooldowns, Neulingsschutz, Schild, Bewachen, **Basis abschließen** |
| **Rebirth** | Fortschritt zurücksetzen → Prestige-Punkte → dauerhafter Einkommens-Multiplikator + Gems |
| **Offline-Einnahmen** | Beim Beitreten: Popup mit dem Verdienst seit dem letzten Besuch (max. 8 h, mit Gamepass 24 h), x2 für Gems |
| **Shop** | Gem-Boosts (2x Geld, 2x Tempo, Schild, Geldkoffer), Robux-Produkte & Gamepasses (IDs in der Config) |
| **Retention** | Tägliche Login-Serie (7 Tage), Gems für Spielzeit, Server-Events „Goldrausch“ / „Arbeitsfieber“, Bestenliste (leaderstats) |
| **Große Zahlen** | Eigenes BigNum (Mantisse + Exponent), Anzeige wie `1.5K`, `2.3M`, `4.1B`, `12.3ab` |
| **Speichern** | DataStore mit Session-Locking, Retry + Backoff, Autosave (60 s), Speichern beim Verlassen & BindToClose |
| **UI** | Komplett per Code: Farbverläufe, Outlines, abgerundete Ecken, Hover/Klick/Pop-Tweens, hochzählendes Geld, Floating-Text, Partikel, mobile-tauglich (UIScale) |
| **Game Feel** | Schwingende Spitzhacken, Gesteinspartikel, fliegende Erzbrocken, fahrender Aufzug, Wagen auf Schienen, Münzregen, atmosphärisches Licht, **Minenansicht** (Querschnitt-Kamera) |

---

## Installation (Rojo)

Du brauchst **Roblox Studio** und **Rojo 7** (CLI + Studio-Plugin).

### Variante A – mit Aftman (empfohlen)

1. Aftman installieren: <https://github.com/LPGhatguy/aftman/releases> (oder Rokit: <https://github.com/rojo-rbx/rokit>)
2. Im Projektordner:
   ```bash
   aftman install
   ```
   Das installiert die in `aftman.toml` festgelegten Versionen von `rojo`, `selene` und `stylua`.

### Variante B – nur Rojo

- Rojo herunterladen: <https://github.com/rojo-rbx/rojo/releases> (Version 7.x) und die
  ausführbare Datei in den `PATH` legen,
- **oder** die VS-Code-Erweiterung **„Rojo – Roblox Studio Sync“** installieren (bringt Rojo mit).

### Studio-Plugin installieren

```bash
rojo plugin install
```
Danach Roblox Studio (neu) starten – im Reiter **Plugins** erscheint **Rojo**.

---

## Projekt starten & mit Studio verbinden

1. Terminal im Projektordner öffnen und den Rojo-Server starten:
   ```bash
   rojo serve
   ```
   Ausgabe: `Rojo server listening on port 34872`.
2. Roblox Studio öffnen → **neue leere Baseplate** (File → New → Baseplate).
   *Tipp:* Die Standard-Baseplate und die SpawnLocation kannst du löschen – das Spiel baut seine eigene Welt.
3. **Plugins → Rojo → Connect** klicken.
4. Fertig: `ReplicatedStorage.Shared`, `ServerScriptService.Server` und
   `StarterPlayer.StarterPlayerScripts.Client` werden live synchronisiert. Jede Änderung an einer
   `.luau`-Datei erscheint sofort in Studio.

**Alternative ohne Live-Sync:** Eine Place-Datei bauen und in Studio öffnen:
```bash
rojo build -o IdleMiner.rbxlx
```

---

## Wichtige Studio-Einstellungen

| Einstellung | Wo | Warum |
|---|---|---|
| **Enable Studio Access to API Services** | Game Settings → Security | DataStore (Speichern) und Freunde-Avatare in Studio. Ohne: Spiel läuft trotzdem, aber mit temporären Daten (Warnung im Output) |
| **Max. Spieler = 6** | Creator Dashboard → Places → Server Size | Es gibt 6 Plots (`Config.World.MaxPlots`). Mehr Spieler als Plots werden gekickt |
| Spiel veröffentlichen | File → Publish to Roblox | DataStores funktionieren nur in veröffentlichten Spielen |

---

## Spiel testen

### Schnelltest (Einzelspieler)

1. In Studio **Play (F5)** drücken.
2. Du spawnst vor deiner eigenen Mine. Oben siehst du dein Geld, links das Menü (2×3 Buttons).
3. **Spielablauf zum Ausprobieren:**
   1. Tippe auf **Ebene 1** (oder auf den grünen „👆 TIPPEN!“-Hinweis) → die Kumpel bauen ab.
   2. Tippe den **Aufzug** an → er holt das Erz nach oben ins Aufzugslager.
   3. Tippe den **Händler** an → der Wagen verkauft das Erz → **+$** fliegt hoch.
   4. **👔 Manager** → einen Manager einstellen → Reveal-Animation → die Station läuft jetzt automatisch.
   5. **⬆️ Upgrades** oder der gelbe **⬆**-Button neben einer Station → Level kaufen.
   6. **🎥 Ansicht** → seitliche Minenansicht. Scrollen mit Mausrad / Wischen / ▲▼.

### Admin-Menü (🛠 Admin, oben links)

Das Admin-Menü ist **nur für den Owner und für Admins** sichtbar – auch im veröffentlichten Spiel.
Der Owner ist `Config.Admin.OwnerName` (**recher1001**). Optional kannst du in
`Config.Admin.OwnerUserId` deine Roblox-UserId eintragen (sicherer, falls du deinen Namen änderst).
In Studio ist jeder Test-Spieler Owner (`Config.Admin.StudioEveryoneOwner`).

| Reiter | Inhalt |
|---|---|
| 🎯 Spieler | Ziel wählen (dich oder andere Spieler), Geld geben / x1000 / halbieren / auf 0, Gems geben / auf 0, alle Ebenen, Manager überall, Cooldowns weg, Daily neu, Offline-Test, Kicken, Spielstand zurücksetzen |
| ⚡ Kräfte | OP-Kräfte geben oder wegnehmen: 🧞 Fliegender Teppich, ⚡ Super-Speed, 🦘 Mega-Sprung, 🛡️ Unbestehlbar, 🚀 Turbo-Mine (3x), 💰 Goldener Händler (3x Geld) |
| 🌍 Server | Events (Goldrausch, Arbeitsfieber) für alle starten |
| 👑 Admins | **nur Owner:** Spieler zum Admin machen/entfernen und pro Admin einzeln einstellen, was er darf |

Regeln (vom Server erzwungen):
- Der Owner hat immer alle Rechte und kann **nicht** entfernt werden.
- Admins können dem Owner nichts wegnehmen, ihn nicht kicken und nicht zurücksetzen.
- Nur der Owner kann Admins ernennen und Rechte vergeben. Die Admin-Liste wird gespeichert
  und gilt in allen Servern.
- Kräfte werden im Spielstand gespeichert. Mit dem 🧞 Teppich fliegst du:
  Laufen = Richtung, Leertaste/E bzw. ▲ = hoch, Q/Strg bzw. ▼ = runter.

Chat-Befehle für Admins (wenn der Chat sie durchlässt): `/cash 1e9`, `/gems 100`, `/unlockall`,
`/managers`, `/cooldowns`, `/event`.

### Mehrspieler testen (Stehlen, Abschließen)

1. Reiter **Test** → bei *Clients and Servers* **2 Players** auswählen → **Start**.
2. Mit Spieler 1 Geld verdienen (Aufzug laufen lassen, damit das **Aufzugslager** gefüllt ist).
3. Mit Spieler 2 zum Aufzugslager (goldene Kiste links neben dem Aufzug) von Spieler 1 laufen und
   **E halten**. Hinweis: Neue Spieler haben 10 Minuten **Neulingsschutz**. Zum Testen
   `Config.Steal.NewPlayerProtection = 0` setzen.
4. Spieler 1 bekommt eine Warnung und kann den Diebstahl verhindern, indem er bei seinem Aufzug steht
   oder rechts auf **🔒 Abschließen** klickt.

### Offline-Einnahmen echt testen

DataStore-Zugriff aktivieren (siehe oben) → spielen und Manager einstellen → Play beenden →
mindestens 1 Minute warten → wieder Play: Das Popup „Willkommen zurück!“ erscheint.

### Freunde-Avatare

Die Freundesliste wird beim Beitreten geladen (funktioniert auch in Studio mit deinem Account,
API-Zugriff muss aktiv sein). Kumpel und neu eingestellte Manager tragen dann die Avatare deiner
Freunde mit Bauarbeiterhelm. Ohne Freunde wird dein eigener Avatar genutzt, schlägt das Laden
fehl, bleibt die Block-Figur. Abschalten: `Config.Avatars.Enabled = false`.

---

## Projektstruktur

```
default.project.json        Rojo-Projekt (Rojo 7)
aftman.toml                 Tool-Versionen (rojo, selene, stylua)
selene.toml / stylua.toml   Linter / Formatter
src/
├─ shared/                  → ReplicatedStorage.Shared
│  ├─ Config.luau           ALLE Balancing-Werte
│  ├─ BigNum.luau           Große Zahlen + Formatierung
│  ├─ Formulas.luau         Spielformeln (Server rechnet, Client zeigt an)
│  ├─ Types.luau            Gemeinsame Typen
│  ├─ Net.luau              Remote-Definitionen
│  ├─ Clock / Signal / Maid Hilfsmodule
├─ server/                  → ServerScriptService.Server
│  ├─ Main.server.luau      Startet alle Services
│  ├─ Modules/              DataTemplate (Standarddaten + Bereinigung), RateLimiter
│  ├─ World/                MineBuilder (prozedurale Mine), WorldSetup (Licht, Welt)
│  └─ Services/
│     ├─ DataService        DataStore, Session-Lock, Retry, Autosave, BindToClose
│     ├─ SessionService     Spieler-Sessions, Hooks, Sync, leaderstats
│     ├─ NetService         RemoteFunction mit Validierung + Rate-Limit
│     ├─ PlotService        Plots, Klicks, Schilder, Füllstände
│     ├─ MineService        Simulation (Zyklen, Automatisierung, Verkauf)
│     ├─ UpgradeService     Upgrades, Ebenen freischalten
│     ├─ ManagerService     Manager einstellen/zuweisen/Fähigkeiten
│     ├─ AvatarService      Freunde-Avatare mit Bauarbeiterhelm
│     ├─ RebirthService     Prestige
│     ├─ OfflineService     Offline-Einnahmen
│     ├─ ShopService        Gem-Boosts, Gamepasses, Developer Products
│     ├─ StealService       Stehlen, Bewachen, Basis abschließen
│     ├─ RewardService      Tägliche Belohnung, Spielzeit-Gems
│     ├─ EventService       Server-Events
│     └─ AdminService       Owner/Admins, Rechte, OP-Kräfte, fliegender Teppich
└─ client/                  → StarterPlayerScripts.Client
   ├─ Main.client.luau      Baut UI + startet Controller
   ├─ ClientState / Remote / PlotLocator
   ├─ UI/                   Theme, Util, Components, Root, HUD, PanelManager,
   │  │                     Popups, Toasts, FloatingText
   │  └─ Panels/            Upgrades, Managers, Rebirth, Shop, Daily, Admin
   └─ Controllers/          Effects, MineVisuals, StationBadges, CameraController, CarpetController, Sounds
```

---

## Balancing (Config.luau)

Alle Zahlen stehen in `src/shared/Config.luau` – du musst keinen anderen Code anfassen:

- `Config.Shafts` – Ebenen: Name, Erzfarbe, Freischaltkosten, Ertrag, Zyklusdauer
- `Config.Tracks` – Upgrade-Tracks pro Station: Basiskosten, Wachstum, Wirkung pro Level, Meilensteine
- `Config.Managers` – Einstellkosten, Seltenheiten (Chance, Boni, Dauer, Abklingzeit), Fähigkeiten
- `Config.Rebirth` – Mindestverdienst, Punkte-Formel, Multiplikator pro Punkt
- `Config.Offline` – Obergrenze, Effizienz, x2-Preis
- `Config.Steal` – Beute, Cooldowns, Schutzzeiten, Abschließen
- `Config.Daily`, `Config.Gems`, `Config.Events`, `Config.Shop`
- `Config.Lighting` – Atmosphäre, Bloom, Farbkorrektur
- `Config.RateLimits` – Exploit-Schutz pro Aktion

Mit den Standardwerten (simuliert): alle Stationen automatisiert nach ~4 Min., erster Rebirth
nach ~20 Min., Ebene 8 nach gut 2 Stunden.

---

## Eigene Modelle, Sounds, Robux-Produkte

**Eigene Modelle:** Lege in Studio `ServerStorage/MineAssets` an und füge Models mit diesen Namen
ein. Sie ersetzen automatisch die Platzhalter:
`Miner` (optional mit Teil-Model `Pickaxe`), `Manager`, `Crate`, `Depot`, `Cabin`, `Warehouse`, `Cart`.
Die Models werden mit `PivotTo` platziert (Pivot = Unterseite, Blickrichtung −Z).

**Sounds:** `Config.Sounds` – eigene IDs eintragen (`"rbxassetid://123456"`). Zusätzlich feuert
`Sounds.Played` (Client) bei jedem Sound-Ereignis, falls du eigene Effekte anhängen willst.

**Robux:** Im Creator Dashboard Developer Products / Gamepasses anlegen und die IDs in
`Config.Shop.Products[*].ProductId` bzw. `Config.Shop.Passes[*].GamePassId` eintragen.
Solange die ID `0` ist, zeigt der Shop „Bald verfügbar“.

---

## Architektur & Sicherheit

- **Server-autoritativ:** Geld, Zyklen, Kosten, Belohnungen – alles wird nur auf dem Server
  berechnet. Der Client schickt nur Anfragen („Upgrade kaufen“) und zeigt an, was der Server sendet.
- **Eine RemoteFunction** (`Request`) mit Aktions-Registry: Schema-Validierung (Typen, endliche
  Zahlen, kurze Strings, keine unbekannten Felder), Token-Bucket-Rate-Limit pro Spieler und Aktion,
  Handler in `pcall`.
- **Datenschutz:** Session-Lock verhindert, dass zwei Server denselben Spielstand überschreiben.
  Wenn das Laden fehlschlägt, wird **nie** gespeichert. Robux-Käufe sind idempotent
  (PurchaseId wird gespeichert) und werden sofort gesichert.
- **Cleanup:** Jede Session hat eine `Maid`. Connections, Plot-Klicks und Prompts werden beim
  Verlassen getrennt, der Plot wird wieder frei.
- **Clients animieren** anhand von Attributen (`CycleStart`, `CycleEnd`, …) → flüssige Animationen
  ohne zusätzlichen Netzwerkverkehr, auch für die Minen der anderen Spieler.

---

## Code prüfen (selene / StyLua)

```bash
selene generate-roblox-std   # einmalig: erzeugt roblox.yml für selene
selene src                   # Linter
stylua src                   # Formatieren (stylua --check src zum Prüfen)
rojo build -o test.rbxlx     # Projekt baut fehlerfrei?
```

Für Typprüfung im Editor empfiehlt sich die VS-Code-Erweiterung **Luau Language Server**
(`rojo sourcemap -o sourcemap.json` aktiviert die Auflösung von `require`).
