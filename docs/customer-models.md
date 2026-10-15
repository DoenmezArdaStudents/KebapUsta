# Kundenmodelle mit Blender – Plan (Issue #1)

> Status: **In Arbeit.** Die Kunden sind neu gestaltet (Runde 2, nach Feedback): eigener, leicht
> menschlicher Körper für Frau und Mann, detaillierte 3D-Kleidung pro Körpersegment, Haare/Bärte/Hüte
> für den Dynamic Head, 4 Kundentypen. In Studio ohne Upload getestet (EditableMesh).
> Noch offen: Upload/Import, Einbau in `CustomerService`. Branch `issue-1-customer-models`.
> Ziel aus dem Issue: Die Kunden sollen nach Roblox aussehen, aber stimmig und hübsch statt
> „katastrophal“ – Menschen von heute mit Roblox-Proportionen, zufällig variiert.

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
| ~~`BrowL`/`BrowR`~~ | `setMood` | **Erledigt:** Brauen-Klötze entfernt, Mimik über den Dynamic Head (siehe 4.3) |
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

**Gelenke** (RigAttachments, relativ zum `HumanoidRootPart`): Hals 1.049, Schulter (±1.0, 0.788),
Ellbogen 0.051, Handgelenk −0.718, Taille −0.649, Hüfte (±0.5, −0.95), Knie −1.788, Knöchel −2.744.

**Dynamic Head** (Standardkopf, per Raycast mit `PreciseConvexDecomposition` vermessen): im
Querschnitt rund (Radius 0.58), oben flach mit enger Kante – im Modell ein Superellipsoid mit den
Exponenten 2.0 (waagerecht) / 4.3 (senkrecht). Gesicht relativ zur Kopfmitte: Augen bei ±0.12 /
**+0.27** (0.075 × 0.18), Mund bei −0.34 (Breite 0.38). Der Kopf hat **keine** Augenbrauen; die
Stimmung zeigt der Mund über `FaceControls`.

## 2. Stil

- **Menschen von heute, Roblox-Proportionen:** Körper weich gerundet statt Quader – Schultern,
  Brust, Taille, Hüfte, Waden, Hände mit Daumen. Frau und Mann unterscheiden sich in Schultern,
  Taille, Hüfte und Brust (dezent). Altersgruppen über Größe (`scale`), Frisuren, Haarfarben und
  Kleidung.
- **Moderne Kleidung mit Details als echte Geometrie:** Bündchen, Kragen, Knopfleisten, Taschen,
  Ziernähte, Gürtelschlaufen, Kordeln, Sohlen, Schnürsenkel.
- **Gesicht frei halten:** Haare und Hüte enden vorne über +0.41 (Augen), Bärte bleiben unter dem
  Mund. `build.py` prüft das bei jedem Build und bricht sonst ab.
- **Einfarbig pro Mesh**, Farbe kommt erst im Spiel (`MeshPart.Color`). Mehrfarbige Stücke
  (Sneaker: Obermaterial + Sohle) werden mehrere Meshes. Keine Texturen nötig.
- **Budget:** ≤ 1 500–4 400 Dreiecke pro Mesh (Oberteile am meisten), ein Kunde hat ~25 Meshes und
  ~30 000 Dreiecke. Nichts wird verlustbehaftet reduziert; `build.py` meldet, falls doch.

## 3. Aufbau der Blender-Pipeline

```
tools/blender/
  customer_creator.py      Kern: Rig-Maße, Profile (Querschnitte), Hüllen, Kopf, Registry,
                           Würfeln (roll_look), Zusammenbau, FBX-/Studio-Export, Vorschau
  parts/
    body.py                Körper Mann/Frau (14 Segmente, Kopf liefert Roblox)
    clothing.py            tshirt, hoodie, shirt, tie, blazer, cardigan, jeans, trousers,
                           joggers, skirt, belt, sneakers, dress_shoes
    hair.py                hair_crop, hair_sidepart, hair_curly_top, hair_buzz, hair_receding,
                           hair_long, hair_bob, hair_ponytail, hair_bun, hair_curly_long,
                           hair_perm, beard_full, beard_stubble, cap, beanie, flat_cap,
                           glasses, headphones
    accessories.py         backpack, crossbody, watch, cane
  customers/               Kundentypen (reine Konfiguration): student, business, casual, senior
  build.py                 baut + prüft alles, exportiert, rendert Vorschauen
  studio_preview.luau      Studio-Test ohne Upload (EditableMesh)
  studio_preview.project.json   Rojo-Projekt nur für die Testdaten
  out/                     Build-Ergebnis (gitignored)
```

```sh
blender -b -P tools/blender/build.py -- --seed 42 --preview   # ~30 s
```

Ergebnis in `out/`: `CustomerParts.fbx` (alle 267 Meshes + `Ref_*`-Anker), `Customers.blend`
(8 Beispiel-Kunden), `people*.png`, `preview_<typ>.png`, `studio/` (Daten für den Studio-Test).

### 3.1 Wie die Formen entstehen

- **Koordinaten:** modelliert wird in Roblox-Koordinaten relativ zum `HumanoidRootPart`
  (`rbx()` rechnet nach Blender um). Die Achsen stellt erst der FBX-Export wieder auf Roblox.
- **Profile:** Ein Körpersegment ist eine Folge von Querschnitten (Superellipsen) entlang einer
  Achse, mit Catmull-Rom geglättet. `solid()` macht daraus den Körper, `garment()` eine Hülle mit
  Abstand und Dicke (auch vorne offen für Jacken), `capped_shell()` Ärmel mit geschlossener
  Schulter, `patch()` aufgesetzte Stücke (Taschen, Kragen, Revers), `line()` Nähte und Kordeln.
  Abstände gehen entlang echter 3D-Normalen. **Weil die Kleidung dieselben Profile nutzt wie der
  Körper, sitzt sie immer.**
- **Gelenke:** Die Segmente überlappen an den Gelenken so, dass das untere unter das obere greift
  (keine Stufen, keine flimmernden Nähte). Die Gelenke selbst bleiben die des Standard-Rigs, damit
  die Roblox-Animationen passen.
- **Kopfteile:** `head_shell()` (Haube mit beliebiger Unterkante, Dicke, Volumen, Locken),
  `head_patch()` (Bärte, Haarkranz) auf der vermessenen Kopfform.
- **Metadaten pro Mesh:** `part`, `variant`, `body` (m/w), `slot`, `anchor` (R15-Segment, an das
  es geschweißt wird), `attach` (nur Kopfteile) und `colorSlot` (`skin`, `top`, `outer`,
  `bottom`, `shoes`, `hair`, `accent`, `fixed:#…`, `mix:hair:skin:0.45`, `shade:…`).

### 3.2 Kundentypen (`customers/*.py`)

Je Typ: Gewicht, Körper (m/w), Größenbereich, Farbpaletten und Slot-Tabellen – auch getrennt nach
Körper (`{"m": {...}, "w": {...}}`). `"shirt:A"` erzwingt eine Variante, ein Palettenwert als
String übernimmt die Farbe eines anderen Slots (Anzughose = Sakko). Unter Hüten werden nur
passende Frisuren gewählt (Buzzcut, Haarkranz, Pferdeschwanz).

| Typ | Größe | Erkennungsmerkmale |
| --- | --- | --- |
| `student` | 0.93–0.98 | Hoodie/T-Shirt, Jeans/Jogger/Rock, Sneaker, Rucksack, Kopfhörer, Kappe/Beanie |
| `business` | 0.97–1.03 | Hemd, Sakko, Anzughose/Rock, Krawatte, Lederschuhe, Uhr, eckige Brille |
| `casual` | 0.96–1.03 | T-Shirt/Hoodie/Kurzarmhemd, Strickjacke, Jeans/Chino, Bart, Umhängetasche |
| `senior` | 0.94–0.99 | graue Haare/Haarkranz/Dauerwelle, Strickjacke, Brille, Schiebermütze, Gehstock |

Weitere Typen (z. B. Arbeiter, Tourist, Sportler) sind nur noch eine neue Konfigurationsdatei,
die Teile sind gemeinsam.

## 4. Weg ins Spiel

### 4.1 Aufbau eines Kunden im Spiel

Der Rig bleibt der Standard-R15-Rig (`CreateHumanoidModelFromDescription`), also bleiben
Animationen, Gelenke und der Dynamic Head mit Gesicht. Die 14 Roblox-Körperteile werden
**unsichtbar** (`Transparency = 1`), stattdessen werden die Blender-Meshes (Körper + Kleidung +
Accessoires) per `WeldConstraint` an ihr Segment (`anchor`) geschweißt; Position = Mitte des Meshes
relativ zum `HumanoidRootPart`. Größe über `Model:ScaleTo(scale)`. So getestet in Studio
(`studio_preview.luau`).

### 4.2 Import und „Bake“ (einmalig je Änderung der Meshes)

1. `blender -b -P tools/blender/build.py` → `out/CustomerParts.fbx`.
2. **Manuell in Studio** (braucht Upload-Rechte für das Spiel): *3D Importer* →
   `CustomerParts.fbx` importieren. Die Meshes werden dabei als Assets hochgeladen. Claude kann das
   nicht übernehmen (MCP kann keine Meshes hochladen).
3. **Bake per MCP-Luau:** Maßstab und Ausrichtung über die Anker kalibrieren (`Ref_Head`,
   `Ref_Front` liegt vor dem Gesicht), dann jedes MeshPart mit Attributen `Anchor`/`Center` (aus dem
   Manifest) in `ServerStorage.CustomerParts` ablegen, Anker löschen.
4. Mit dem Export-Rezept aus `CLAUDE.md` nach `assets/ServerStorage/CustomerParts.rbxm` exportieren
   und in `default.project.json` eintragen. Danach braucht niemand mehr Blender – die Teile liegen
   ganz normal im Projekt.

Warum nicht ohne Upload (EditableMesh)? Das geht nur im Studio-Test: im Spiel muss die API extra
freigeschaltet werden, und vor allem werden EditableMesh-Inhalte vom Server **nicht** an die Clients
repliziert.

### 4.3 Änderungen im Code

- **Erledigt – Mimik:** Brauen-Klötze `BrowL`/`BrowR` entfernt. `setMood` setzt nur noch das
  Attribut `Mood` am Kunden-Model; `Client/CustomerFaces` überblendet daraus die `FaceControls`
  des Dynamic Head (Werte in `Shared/MoodFaces`). Grund: `FaceControls`-Werte werden **nicht**
  vom Server zu den Clients repliziert (in einem Playtest geprüft), Attribute schon.
- **Offen – `Server/CustomerService`:**
  - `randomLook(vip, rng)` → Logik von `roll_look` aus Python übernehmen (Typ nach Gewicht, Körper,
    Paletten mit Jitter, Slots, Extras, Größe), alles über `rng`, damit `lookSeed` bleibt.
    Den Katalog erzeugt `build.py` als `Shared/CustomerLooks.luau` (eine Quelle der Wahrheit).
  - `dress(rig, look)` → Körperteile unsichtbar, alte Teile entfernen, Meshes aus
    `ServerStorage.CustomerParts` klonen, färben, anschweißen (4.1).
  - Altes `look`-Format (EmployeeService, LogisticsService) weiter unterstützen bzw. ableiten;
    Fallback auf die alten Quader, falls `CustomerParts` fehlt.

### 4.4 Leistung

~25 Meshes und ~30 000 Dreiecke pro Kunde, bei 10 Kunden ~300 000 Dreiecke plus Passanten.
MeshParts haben automatisches LOD; alle Teile sind `Massless`, ohne Kollision und Abfragen.
Spätere Optimierung, falls nötig: verdeckte Körpersegmente (Oberkörper unter Pulli) weglassen und
gleichfarbige Stücke eines Segments zusammenfassen.

## 5. Zufall und Vielfalt

- **Pro Kunde (aus `lookSeed`):** Typ, Frau/Mann, Hautton, Farben je Slot plus Jitter, Frisur,
  Bart, Hut, Brille, Oberteil, Jacke, Hose/Rock, Schuhe, Extras, Größe.
- **Varianten in Blender:** z. B. `hoodie` A/B (mit Reißverschluss), `jeans` A/B (Umschlag),
  `cap` A/B (rückwärts), `glasses` A/B (rund/eckig).
- Gegen Doppelgänger: die letzten ~5 Kombinationen aus Typ, Körper und Frisur merken und einmal neu
  würfeln (nicht bei Stammkunden mit festem `lookSeed`).

## 6. Arbeitsschritte

- [x] Pipeline `tools/blender/` (Kern, Teile-Module, Kundentypen, `build.py`), `out/` gitignored
- [x] Runde 1: einfacher Kunde auf Klötzchen-Rig – vom Team als „nicht schön“ bewertet
- [x] Runde 2: eigener Körper m/w, 3D-Kleidung (13 Stücke), 18 Kopfteile, 4 Accessoires,
      4 Kundentypen, Prüfungen (Budget, Augen frei, Mund frei, Namen eindeutig)
- [x] Gelenke und Dynamic Head in Studio vermessen, Kopfform danach korrigiert
- [x] Studio-Test ohne Upload: `rojo serve tools/blender/studio_preview.project.json` verbinden,
      `tools/blender/studio_preview.luau` ausführen → 8 Beispiel-Kunden in
      `workspace.CustomerPreviewTest` auf echten R15-Rigs
- [x] Mimik über `FaceControls` (Attribut `Mood` + `Client/CustomerFaces`), Brauen-Klötze entfernt
- [ ] Mit dem Team abstimmen: Aussehen, Typen, Farben
- [ ] Upload/Import in Studio, Bake, `assets/ServerStorage/CustomerParts.rbxm`
- [ ] `build.py` erzeugt `Shared/CustomerLooks.luau`
- [ ] `CustomerService`: neues `randomLook`/`dress`, altes Format, Fallback
- [ ] Playtest mit 10 Kunden + Passanten (Laufen, Sitzen, Gesten), Konsole ohne Fehler
- [ ] Aufräumen, `CLAUDE.md` um den Blender-Workflow ergänzen

## 7. Offene Fragen

1. **Wer importiert?** Der 3D-Importer lädt Meshes als Assets hoch – das braucht Upload-Rechte für
   das Spiel bzw. die Gruppe.
2. **Mitarbeiter und Fahrer:** auch auf die neuen Körper umstellen (Kochjacke, Schürze,
   Lieferanten-Kappe als neue Teile)?
3. **Weitere Kundentypen** (Arbeiter, Tourist, Sportler) und VIP/Kritiker-Outfits?
4. **Röcke** sind starr am Becken; beim Laufen schneiden die Beine leicht hinein. Reicht das, oder
   später Layered Clothing?
