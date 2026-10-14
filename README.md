# Kebap Usta (Roblox)

Kebap-Restaurant-Simulator für Roblox. Alle Skripte liegen in `src/` und werden mit **Rojo** live in Roblox Studio synchronisiert.

## Aufbau
| Ordner | In Studio |
|---|---|
| `src/ServerScriptService` | `ServerScriptService` (Main + Services) |
| `src/ReplicatedStorage/Shared` | `ReplicatedStorage.Shared` |
| `src/StarterPlayer/StarterPlayerScripts` | `StarterPlayer.StarterPlayerScripts` (ClientMain + ClientModules) |
| `KebapUsta.rbxl` | ganze Spielwelt inkl. 3D-Modelle (ServerStorage.Models) |
| `art/` | Blender-Skripte, Texturen und FBX-Exporte (Essen, Logistik, Fleischspieß) |

## Einrichten (einmalig)
1. **Rokit** installieren: https://github.com/rojo-rbx/rokit (oder Rojo direkt: https://rojo.space)
2. Im Ordner `rokit install` ausführen (installiert Rojo 7.4.4).
3. In Studio das **Rojo-Plugin** installieren (Toolbox → Plugins → „Rojo“ von rojo-rbx, oder `rojo plugin install`).

## Arbeiten
1. `git pull` – neueste Änderungen von GitHub holen.
2. `rojo serve` im Ordner starten.
3. In Studio: Plugins → Rojo → **Connect**. Alle Skripte aus `src/` sind jetzt live in Studio; jede Änderung an einer Datei erscheint sofort.
4. Veröffentlichen wie gewohnt mit Alt+P.

Wichtig: Skripte nur in den Dateien ändern, nicht direkt in Studio – Rojo überschreibt sie beim Verbinden.
Modelle und die Welt (alles, was kein Skript ist) bleiben in Studio / `KebapUsta.rbxl`.
