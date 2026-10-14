# Kundenmodelle mit Blender – Plan (Issue #1)

> Status: **Plan**, noch nichts umgesetzt. Branch `issue-1-customer-models`.
> Ziel aus dem Issue: Die Kunden sollen weiterhin nach Roblox aussehen, aber stimmig und hübsch
> statt „katastrophal“. Gebaut wird mit Blender: eine `customer-creator.py` mit Methoden und dazu
> 6 Skripte, die verschiedene Kundentypen konfigurieren. Die Kunden sollen zufällig variieren.

## 1. Ausgangslage

**So entstehen Kunden heute** (`Server/CustomerService`, Abschnitt *Appearance*):

- `newRig()` erzeugt einen R15-Rig über `Players:CreateHumanoidModelFromDescription` mit einer
  leeren `HumanoidDescription`. Der Rig hat MeshPart-Körperteile, einen **Dynamic Head** mit
  `FaceControls` (also schon ein Gesicht) und die Standard-Attachments von Roblox
  (`HairAttachment`, `HatAttachment`, `FaceFrontAttachment`, `FaceCenterAttachment`, …) sowie
  `WrapTarget`s für Layered Clothing.
- `randomLook(vip, rng)` würfelt eine `look`-Tabelle (Hautfarbe, Shirt, Hose, Haare, Hut, Brille,
  Bart, Jacke, Schal, Rucksack, Tasche, Uhr, Kopfhörer, Körperskalierung …).
- `dress(rig, look)` färbt die Körperteile und schweißt **einfache `Part`-Quader** als „Accessoires“
  an (z. B. Haare = Quader 1.3×0.45×1.3, Jacke = drei flache Platten, Brille = Quader).
  Diese Teile tragen das Attribut `Accessory = true`, damit `dress` sie beim nächsten Mal wieder
  entfernen kann (Rigs werden über `pool` wiederverwendet).

**Darum sieht es schlecht aus:** Eckige Quader sitzen auf einem runden Mesh-Körper. Haare
schweben als Block über dem Kopf, Jacken sind lose Platten, nichts ist abgerundet, und alle Teile
haben dieselbe Plastikoptik.

**Was beim Umbau erhalten bleiben muss:**

| Abhängigkeit | Wo | Konsequenz |
| --- | --- | --- |
| `lookSeed` → gleiches Aussehen bei jedem Besuch (Stammkunden) | `CustomerService.Spawn` | Auswahl muss deterministisch aus `Random.new(lookSeed)` kommen |
| `BrowL`/`BrowR` mit `BrowWeld` + Attribut `Base` | `setMood` | Augenbrauen bleiben (oder `setMood` wird angepasst) |
| `CustomerService.Dress` mit altem `look`-Format | `EmployeeService.makeWorker`, `LogisticsService` (Fahrer) | Alte Felder (`hat`, `hatColor`, `longHair`, `glasses`, …) weiter unterstützen |
| Attribut `Accessory` zum Aufräumen, Handy-Geste nutzt es auch | `dress`, `idleGesture` | Neue Teile genauso markieren bzw. `Accessory`-Instanzen mit aufräumen |
| Rig-Pool (max. 10 Rigs) | `releaseRig` | `dress` muss alles Alte vollständig entfernen |

**Maße des Standard-Rigs** (in Studio gemessen, Studs, relativ zum `HumanoidRootPart`):

| Teil | Größe (X, Y, Z) | Position (Y) |
| --- | --- | --- |
| Head | 1.159, 1.182, 1.161 | +1.586 |
| UpperTorso | 1.943, 1.698, 1.004 | +0.200 |
| LowerTorso | 1.991, 0.401, 1.004 | −0.800 |
| Upper/LowerArm | 1.001, 1.242 / 1.118, 1.002 | +0.369 / −0.224 (X ±1.5) |
| Hand | 0.984, 0.316, 1.028 | −0.850 |
| Upper/LowerLeg | 0.993, 1.363 / 1.301, 0.973 | −1.421 / −2.201 (X ±0.5) |
| Foot | 1.009, 0.312, 1.001 | −2.850 |

HipHeight 2.19. Vorne ist in Roblox **−Z**.

## 2. Stil

- **Roblox-Look:** wenige, klare Formen, weich abgerundet (Bevel), flache Farben, keine
  realistischen Proportionen oder Texturen. Orientierung: aktuelle Avatar-Shop-Haare und -Hüte.
- **Low-Poly:** grob ≤ 1500 Dreiecke pro Teil, ≤ 6 Teile pro Kunde (bei bis zu 10 Kunden plus
  Passanten).
- **Einfarbig pro Teil**, die Farbe wird erst im Spiel gesetzt (`MeshPart.Color`). So kann ein Mesh
  in beliebig vielen Farbvarianten vorkommen, ohne dass Texturen hochgeladen werden müssen.
  Teile aus zwei Farben (z. B. Brille: Gestell + Gläser) werden zwei Meshes.

## 3. Aufbau der Blender-Pipeline

```
tools/blender/
  customer_creator.py      Bibliothek: Szene, Referenzkörper, Formen, Teile, Export, Vorschau
  customers/
    student.py             6 Kundentypen (Konfiguration + typ-eigene Teile)
    business.py
    worker.py
    senior.py
    tourist.py
    sporty.py
  build.py                 Einstiegspunkt: baut alles, exportiert, rendert Vorschau, erzeugt Luau
  out/                     Build-Ergebnis (gitignored): CustomerParts.fbx, preview_*.png
```

Aufruf ohne Oberfläche:

```sh
blender -b -P tools/blender/build.py -- --seed 42 --preview
```

### 3.1 `customer_creator.py` – Methoden

- **Szene & Einheiten:** `new_scene()` leert die Szene und setzt 1 Blender-Einheit = 1 Stud.
  Blender ist Z-up, Roblox ist Y-up mit −Z vorne. Die Achsen werden **nur beim FBX-Export**
  umgerechnet (`axis_forward="-Z"`, `axis_up="Y"`), modelliert wird ganz normal in Blender.
- **Referenzkörper:** `reference_body()` baut den R15-Rig mit den gemessenen Maßen aus Quadern
  nach. Er dient zum Modellieren und für die Vorschau-Renderings und wird nicht exportiert. Dazu
  kommen **Anker** (`Ref_Head`, `Ref_UpperTorso`, …): kleine Quader mit exakt der Rig-Größe, die
  *mit* exportiert werden. Mit ihnen werden beim Import Maßstab und Position kalibriert
  (siehe 4.2).
- **Grundformen:** `rounded_box`, `capsule`, `sphere`, `torus`, `cylinder`, `shell` (dünne Hülle um
  einen Körperteil, für Jacken/Westen), dazu `bevel`, `mirror_x`, `subdivide`, `smooth_shade`,
  `apply_all` und `decimate_to(tris)` für das Budget.
- **Teile-Builder** (geben je ein Objekt zurück, das korrekt am Referenzkörper sitzt):
  - Haare: `hair_short`, `hair_long`, `hair_bun`, `hair_ponytail`, `hair_curly`, `hair_afro`,
    `hair_mohawk`, `hair_sidepart`, `hair_buzz`
  - Kopf: `cap`, `beanie`, `beret`, `hard_hat`, `headband`, `sun_hat`
  - Gesicht: `glasses_round`, `glasses_square`, `sunglasses`, `beard_full`, `beard_stubble`,
    `mustache`
  - Körper: `jacket_open`, `vest`, `hoodie_hood`, `scarf`, `tie`
  - Extras: `backpack`, `shoulder_bag`, `watch`, `headphones`, `camera`, `cane`
  - Jeder Builder nimmt einen `variant`/`rng`-Parameter, z. B. Haarlänge, Pony links/rechts oder
    Schirm der Kappe. So entstehen von einer Frisur 2–3 Mesh-Varianten.
- **Metadaten:** Jedes Teil bekommt einen Namen (`Hair_Short_A`) und Custom Properties:
  `attach` (Roblox-Attachment, z. B. `HairAttachment`), `slot` (`hair`, `hat`, `face`, …) und
  `colorSlot` (`hair`, `shirt`, `accent`, `fixed:#202020`, …). Diese Daten landen in der erzeugten
  Luau-Datei (3.3), nicht im FBX, weil der Roblox-Importer Custom Properties ignoriert.
- **Export:** `export_fbx(objects, path)` exportiert alle Teile plus Anker in **eine** FBX-Datei
  (ein Import in Studio statt dreißig).
- **Vorschau:** `render_lineup(looks, path)` stellt mehrere zufällige Kunden auf den Referenzkörper
  und rendert sie mit Workbench/EEVEE als PNG. So lässt sich die Zufallsvielfalt beurteilen, ohne
  Studio zu öffnen.

### 3.2 Die 6 Kundentypen (`customers/*.py`)

Jede Datei ist reine Konfiguration und kann optional eigene Teile bauen:

```python
ARCHETYPE = {
    "id": "student",
    "name": {"de": "Student", "en": "Student"},
    "weight": 3,                       # Häufigkeit im Spiel
    "scale": {"height": (0.95, 1.03), "width": (0.9, 1.05)},
    "palettes": {
        "shirt":  ["#3a6fd8", "#d8483a", "#3aa86b", "#f2f2f2", "#2b2b30"],
        "pants":  ["#2f3a55", "#1f1f24", "#5a6e8c"],
        "shoes":  ["#f0f0f0", "#202020"],
        "hair":   ["#1e1914", "#5a3c1e", "#c8a05a"],
        "accent": ["#f0b428", "#7a3c96"],
    },
    "slots": {                          # Gewichte; None = nichts
        "hair": {"hair_short": 3, "hair_curly": 2, "hair_sidepart": 2, "hair_bun": 1},
        "hat":  {None: 6, "beanie": 2, "cap": 2},
        "face": {None: 6, "glasses_round": 2},
    },
    "extras": {"backpack": 0.6, "headphones": 0.35, "watch": 0.2},  # Wahrscheinlichkeiten
}

def build(cc, rng):                     # optional: typ-eigene Teile
    return []
```

| Typ | Erkennungsmerkmale |
| --- | --- |
| `student` | Rucksack, Kopfhörer, Beanie/Kappe, bunte Shirts |
| `business` | Krawatte, Seitenscheitel, dunkle Jacke, Aktentasche/Umhängetasche |
| `worker` | Bauhelm oder Kappe, Warnweste, Bart häufig, kräftigere Statur |
| `senior` | graue/weiße Haare oder Glatze, Brille, Barett, Gehstock, Strickjacke |
| `tourist` | Sonnenhut, Sonnenbrille, Kamera, Umhängetasche, helle Farben |
| `sporty` | Stirnband, Pferdeschwanz/Buzzcut, Hoodie, Sportfarben |

VIP und Kritiker bekommen eigene, feste Regeln (dunkle Kleidung, Barett) wie heute.

### 3.3 `build.py`

1. Alle Kundentypen laden, die benötigten Teile sammeln (Vereinigungsmenge plus die
   typ-eigenen Teile).
2. Jedes Teil einmal bauen und auf das Budget prüfen (Dreiecke, ein Material, Name eindeutig).
3. `out/CustomerParts.fbx` exportieren (Teile + Anker).
4. Mit `--preview`: pro Typ eine Reihe mit ~8 zufälligen Kunden rendern (`out/preview_<typ>.png`).
5. **`src/shared/CustomerLooks.luau` erzeugen.** Das ist der Katalog fürs Spiel: Typen, Gewichte,
   Paletten, Slots, Extras und pro Teil `attach`/`slot`/`colorSlot`. Die Datei bekommt den Kopf
   „generiert von tools/blender/build.py – nicht von Hand ändern“. Dadurch gibt es **eine**
   Quelle der Wahrheit: die Python-Konfiguration. Balancing (Häufigkeiten, Farben) passiert dort.

## 4. Weg ins Spiel

### 4.1 Teile als echte Roblox-`Accessory`

Statt Quader anzuschweißen wird jedes Teil ein `Accessory` mit einem `Handle` (MeshPart) und einem
Attachment, das so heißt wie das passende Rig-Attachment. `Humanoid:AddAccessory()` verschweißt es
dann automatisch an der richtigen Stelle und berücksichtigt die Körperskalierung
(`BodyHeightScale` usw.). Zuordnung:

| Slot | Attachment am Rig |
| --- | --- |
| Haare | `HairAttachment` |
| Hüte | `HatAttachment` |
| Brille, Bart | `FaceFrontAttachment` |
| Schal, Krawatte | `NeckAttachment` |
| Rucksack | `BodyBackAttachment` |
| Jacke/Weste | `BodyFrontAttachment` (starre Hülle, siehe 4.4) |
| Tasche | `LeftCollarAttachment` / `WaistBackAttachment` |
| Uhr | `LeftWristRigAttachment` |

### 4.2 Import und „Bake“ (einmalig je Änderung der Meshes)

1. `blender -b -P tools/blender/build.py` ausführen → `out/CustomerParts.fbx`.
2. **Manuell in Studio** (braucht Upload-Rechte für das Spiel): *Avatar/3D Importer* →
   `CustomerParts.fbx` importieren → als Model in den Workspace. Die Meshes werden dabei als Assets
   hochgeladen. Diesen Schritt kann Claude nicht übernehmen, MCP kann keine Meshes hochladen.
3. **Bake per MCP-Luau** (`execute_luau`):
   - Maßstab aus dem Anker bestimmen: `s = 1.159 / Ref_Head.Size.X`. Der Importer kann die
     Einheiten umrechnen, die Anker gleichen das aus.
   - Für jedes MeshPart: Größe mal `s`, Position relativ zum Anker seines Körperteils →
     `Accessory` + `Handle` + Attachment mit dem passenden `CFrame` bauen. Die Daten kommen aus
     `Shared/CustomerLooks` (`attach`, `slot`).
   - Anker löschen, Ergebnis als Ordner `ServerStorage.CustomerParts` ablegen.
4. Mit dem Export-Rezept aus `CLAUDE.md` nach `assets/ServerStorage/CustomerParts.rbxm` exportieren
   und in `default.project.json` eintragen (`ServerStorage.CustomerParts`).
5. Prüfen: `rojo build`, Teile-Anzahl und Namen zwischen Studio und Build vergleichen.

### 4.3 Änderungen im Code

- **`Server/CustomerService`:**
  - `randomLook(vip, rng)` → Typ nach `weight` ziehen, dann Farben aus den Paletten (mit leichtem
    HSV-Jitter), Slots nach Gewicht, Extras nach Wahrscheinlichkeit und Skalierung im Bereich des
    Typs. Alles über das übergebene `rng`, damit `lookSeed` deterministisch bleibt. Rückgabe:
    `{ archetype, skin, shirt, pants, shoes, colors = {...}, parts = {"Hair_Curly_B", ...}, scale }`.
  - `dress(rig, look)` → Körper färben wie bisher, alte Accessoires entfernen (`Accessory`-Attribut
    **und** `Accessory`-Instanzen), Teile aus `ServerStorage.CustomerParts` klonen, nach `colorSlot`
    einfärben, `Humanoid:AddAccessory()`. Augenbrauen bleiben, ihre Farbe kommt aus `hair`.
  - **Altes Format weiter unterstützen:** Fehlt `look.parts`, wird es aus den alten Feldern
    abgeleitet (`hat` → `Cap`, `longHair` → `Hair_Long`, `glasses` → `Glasses_Square`,
    `vip` → `Beret`, …). Dann laufen `EmployeeService` und `LogisticsService` ohne Änderung weiter
    und sehen trotzdem besser aus.
  - Fallback: Fehlt `ServerStorage.CustomerParts` (z. B. noch nicht importiert), wird wie bisher
    mit Quadern angezogen, damit das Spiel nie kaputtgeht.
- **`Shared/CustomerLooks`** (generiert): reine Daten, keine Seiteneffekte (Regel für `Shared/`).
- **`Main.server.luau`:** Studio-Debug-Befehl `start` (Session ohne Lobby-UI starten). Damit lassen
  sich Kunden in automatischen Playtests spawnen und prüfen.

### 4.4 Kleidung – stufenweise

1. **Phase 1:** Körperteile einfärben (wie heute) plus starre Mesh-Accessoires (Weste, offene
   Jacke als Hülle, Schal, Krawatte). Das ist schnell und robust und sieht schon deutlich besser
   aus als die Platten.
2. **Phase 2 (optional):** Klassische `Shirt`/`Pants`-Texturen (585×559-Template) in Blender
   rendern, z. B. Knöpfe, Taschen, Kragen, Streifen. Die Bilder werden über Studio hochgeladen.
   Das bringt Details ohne zusätzliche Meshes.
3. **Phase 3 (optional, aufwendig):** Layered Clothing (`WrapLayer` mit Cage-Meshes), damit sich
   Jacken und Hoodies beim Laufen mitverformen. Der Rig hat die `WrapTarget`s schon. Die Cages zu
   bauen ist aber deutlich mehr Arbeit, deshalb erst, wenn Phase 1 steht.

## 5. Zufall und Vielfalt

Zufall gibt es auf zwei Ebenen:

- **In Blender:** mehrere Mesh-Varianten pro Teil (`variant`), gesteuert über `--seed`.
- **Im Spiel (pro Kunde, aus `lookSeed`):** Typ, Hautton, Farben je Slot plus Jitter, Frisur,
  Hut ja/nein, Gesichtsteile, 0–2 Extras und die Körperskalierung.

Gegen Doppelgänger: Wie bei `recentOrders` merkt sich der Service die letzten ~5 Kombinationen aus
Typ und Frisur. Wiederholt sich eine, wird einmal neu gewürfelt. Wichtig: nicht für Stammkunden mit
festem `lookSeed`.

Grob gerechnet ergeben 6 Typen × ~6 Frisuren × ~5 Hüte × ~4 Gesichtsteile × Farben weit über
10 000 sichtbar verschiedene Kunden.

## 6. Arbeitsschritte

- [ ] `tools/blender/` anlegen, `out/` in `.gitignore`
- [ ] `customer_creator.py`: Szene, Referenzkörper + Anker, Grundformen, Export, Vorschau
- [ ] Erste Teile (2 Frisuren, Kappe, Brille), Testimport in Studio, Bake-Skript fertig machen
      → **prüft die ganze Pipeline früh**, bevor viele Teile gebaut werden
- [ ] Restliche Teile-Builder
- [ ] 6 Typ-Konfigurationen + Vorschau-Renderings, mit dem Team abstimmen
- [ ] `build.py` erzeugt `Shared/CustomerLooks.luau`
- [ ] Import + Bake + Export nach `assets/ServerStorage/CustomerParts.rbxm`, Eintrag in
      `default.project.json`
- [ ] `CustomerService`: neues `randomLook`/`dress`, Kompatibilität mit altem Format, Fallback
- [ ] Debug-Befehl `start`, Playtest: 10 Kunden + Passanten spawnen, Screenshots, Konsole ohne Fehler
- [ ] Aufräumen, `CLAUDE.md` um den Blender-Workflow ergänzen

## 7. Offene Fragen

1. **Wer importiert?** Der 3D-Importer lädt Meshes als Assets hoch. Das muss jemand mit
   Upload-Rechten für das Spiel bzw. die Gruppe machen.
2. **Gesichter:** Der Dynamic Head hat schon ein Gesicht. Reicht das, oder sollen verschiedene
   Gesichter (Decals/Köpfe) dazukommen?
3. **Kundentypen:** Passen die 6 Vorschläge (Student, Business, Arbeiter, Rentner, Tourist,
   Sportler)?
4. **Mitarbeiter und Fahrer:** Sollen sie auch eigene Blender-Teile bekommen (Kochmütze, Schürze,
   Lieferanten-Kappe) oder nur automatisch über das alte Format profitieren?
5. **Layered Clothing (Phase 3):** gewünscht oder bewusst weglassen?
