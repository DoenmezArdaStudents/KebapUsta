# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## Project

**Kebap Usta** – a Roblox kebab-restaurant simulator (place id `124098714209687`, Team Create).
Players run a shared kebab shop: take orders, prepare food at stations, carve meat, manage stock,
staff and expansions. UI and dialogue are bilingual (German / English).

The repo is the source of truth and is synced into Studio with **Rojo**. The whole place
(code *and* world) can be rebuilt from the repo with `rojo build`.

## ⚠️ WICHTIG: Rojo niemals im Team-Create-Place verbinden

Wenn ihr Rojo im echten Spiel verbindet (also im Team-Create-Place, auf dem wir alle zusammen
arbeiten), überschreibt ihr den Code von anderen! Stattdessen immer zuerst eine eigene lokale
Kopie bauen und **dort** arbeiten:

```sh
rojo build -o KebapUsta.rbxl
```

`KebapUsta.rbxl` in Studio öffnen, dann `rojo serve` + Rojo-Plugin → **Connect**. Diese Datei ist
nur für euch, nicht für alle – so stören wir uns nicht gegenseitig.

*(EN: Never connect `rojo serve` to the shared Team Create place – it overwrites other people's
work. Build a local copy with `rojo build -o KebapUsta.rbxl`, open that in Studio and connect Rojo
there.)*

## Getting started (new machine / new team member)

1. Install [Rokit](https://github.com/rojo-rbx/rokit) (installs to `~/.rokit/bin`; make sure that is
   on `PATH` *before* any Homebrew `rojo`, so the pinned version wins).
2. In the repo: `rokit install` → installs the exact tool versions from `rokit.toml`.
3. Install the Rojo plugin in Studio (`rojo plugin install` or the Creator Store). The plugin
   version must match the pinned rojo version (7.7.x).
4. Build your own local copy with `rojo build -o KebapUsta.rbxl` and open **that file** in Studio
   (not the Team Create place – see the warning above). Run `rojo serve` in the repo, open the
   Rojo plugin → **Connect**. From then on, edits to files sync into Studio live.
5. Optional: install the VS Code extensions from `.vscode/extensions.json` and run
   `rojo sourcemap -o sourcemap.json` so luau-lsp resolves `require`s.

GitHub: `DoenmezArdaStudents/KebapUsta`, branch `main`. Pushing needs collaborator write access
(a "Permission denied" on push means the account hasn't been added yet – ask the repo owner).

## Daily workflow

- **Code:** edit `.luau` files in `src/` (not in Studio) while `rojo serve` is connected. Edits made
  to synced scripts inside Studio are *not* written back to disk and get overwritten.
- **World / models:** see "World / assets workflow" below – Studio edits must be exported to
  `assets/` before anyone syncs.
- **Before committing:** `rojo build -o /tmp/check.rbxl` must succeed; run `selene src`.
- Never commit `.rbxl`/`.rbxlx` files – they are gitignored; the repo itself is the place file.

## Toolchain

Tools are pinned in `rokit.toml` (install with `rokit install`):

| Tool   | Use                                    |
| ------ | -------------------------------------- |
| rojo   | sync / build (`default.project.json`)  |
| lune   | standalone Luau scripts (e.g. reading/writing `.rbxm`) |
| selene | linter (`selene src`)                  |
| stylua | formatter (`stylua src`)               |

Common commands:

```sh
rojo serve                                  # live-sync into Studio (Rojo plugin → Connect)
rojo build -o KebapUsta.rbxl                # build the full place file (gitignored)
rojo sourcemap -o sourcemap.json            # for luau-lsp
selene src                                  # lint
stylua src                                  # format
```

Note: the existing code has not been run through stylua yet. Formatting the whole tree is a
separate, dedicated commit – don't mix it into feature changes.

## Layout

```
default.project.json     Rojo tree (also holds service properties: Lighting, StarterPlayer, Workspace)
src/server/              → ServerScriptService
  Main.server.luau         server entry: builds world if missing, starts services, lobby vs. game
  Services/*.luau          one ModuleScript per service, each exposes Init()
src/shared/              → ReplicatedStorage.Shared   (pure data + logic, used by server & client)
src/client/              → StarterPlayer.StarterPlayerScripts
  ClientMain.client.luau   client entry
  ClientModules/*.luau     presentation modules (UI, Laptop, FirstPerson, …)
assets/                  binary models (.rbxm), mapped 1:1 in default.project.json
  Workspace/               Restaurant, kebap_food, Baseplate
  ServerStorage/           Models (food meshes, döner spit)
  StarterPlayer/           StarterCharacter (incl. its Animate script)
  Lighting/                Sky, Atmosphere and post effects
  TextChatService/         chat configuration
```

File naming follows Rojo: `X.server.luau` = Script, `X.client.luau` = LocalScript,
`X.luau` = ModuleScript. Code comments refer to modules as `Server/…`, `Shared/…`, `Client/…`.

## Architecture

- **Server-authoritative.** Clients only send *intents* (which station, which customer); the server
  decides money, stock, results. Never trust client-sent amounts.
- **Networking** goes through `src/server/Services/Net.luau`. It creates `ReplicatedStorage.Remotes`
  at runtime (RemoteEvents listed in `EVENTS` + one `Request` RemoteFunction), with per-player
  token-bucket rate limiting and `pcall`-wrapped handlers. Add new remotes to `EVENTS` / `LIMITS`;
  register handlers with `Net.On` / `Net.OnRequest`.
- **Lobby vs. game servers.** Public servers are lobbies (`LobbyService`); the game runs in reserved
  servers created by the lobby teleport. `ReplicatedStorage` attribute `Mode` (`"lobby"`/`"game"`)
  tells the client which UI to start.
- **Stations** in the world are tagged `Station` (CollectionService) with attributes; services attach
  behaviour to them. Other tags: `SeatPoint`, `Spit`, `SpitRotor`, `Fan`, `LaptopScreen`, `Unlockable`.
- **Tuning** lives in `src/shared/Config.luau`; catalogs in `Business`, `Progression`, `MenuData`,
  `IngredientData`. Balance changes belong there, not in service code.
- **Localization:** every player-facing string is a `{de, en}` pair (`Localization.luau`,
  `DialogueConfig.luau`). Add both languages.
- **Persistence:** `DataService` (DataStores with retries; degrades to session data if unavailable).
- **Studio debug hook:** in Studio only, `Main.server.luau` creates `ServerStorage.KebapDebug`
  (BindableFunction) for automated playtests (`state`, `spawn`, `setData`, …).

## World / assets workflow

- `Workspace.Restaurant` and `StarterCharacter` are generated by `WorldBuilder` / `CharacterBuilder`
  and baked into `assets/`. At runtime the builders only run if those instances are missing.
  `ExpansionBuilder` adds `Restaurant.Expansion` stages at runtime.
- **Rojo owns everything mapped in `default.project.json`.** Connecting `rojo serve` replaces the
  Studio copies of those instances with the repo version. If someone edits the Restaurant (or any
  other asset) directly in Studio, re-export it to `assets/…/*.rbxm` *before* anyone syncs, or the
  change is lost.
- To change world geometry from code: edit `WorldBuilder.luau`, delete `workspace.Restaurant` in
  Studio, run the builder in Edit mode, then re-export the model to `assets/Workspace/Restaurant.rbxm`.
- `.rbxm` files are binary – they can't be merged. Coordinate who edits which asset.
- Unmapped instances (Workspace.Camera/Terrain, runtime-created Remotes, Lobby, …) are not managed.
- **Exporting a model by hand:** in Studio right-click the instance → *Save to File…* → save as
  `.rbxm` over the matching file in `assets/`. One root instance per file (Rojo requirement).
- **New asset:** export it to `assets/<Service>/<Name>.rbxm` and add a node with `$path` to
  `default.project.json`, otherwise Rojo ignores it (and `rojo build` won't contain it).
- **Service properties** (Lighting, StarterPlayer, Workspace) are set via `$properties` in
  `default.project.json`. Changing them in Studio is not saved to the repo – update the JSON.
- Studio also contains an empty `Rojo` ModuleScript directly under `game` (`return { API = nil }`),
  a plugin leftover. It is intentionally not part of the repo.

## Roblox Studio MCP (notes for Claude)

The Roblox Studio MCP server (`mcp__Roblox_Studio__*`) connects Claude to a running Studio.

- Call `list_roblox_studios` first; pick the instance named `Kebap Usta (placeId: 124098714209687)`
  and pass its id as `studio_id`. Several Studio instances may be listed.
- **Prefer editing files in `src/` over editing scripts in Studio** – with Rojo connected, the file
  is the source of truth. Use MCP for reading live state, playtesting (`start_stop_play`,
  `get_console_output`, `ServerStorage.KebapDebug`) and exporting assets.
- `execute_luau` restrictions observed: no `HttpService` requests (HTTP is disabled in the
  experience settings – don't enable it), some properties are unreadable (e.g. `Lighting.Technology`).
- **Exporting models to `.rbxm` via MCP** (lossless, no user action needed):
  1. In `execute_luau`: `SerializationService:SerializeInstancesAsync({inst})` → buffer in rbxm
     format. For many/large items, bundle them, compress with
     `EncodingService:CompressBuffer(buf, Enum.CompressionAlgorithm.Zstd, 19)`, then
     `EncodingService:Base64Encode(...)`, and keep the string in `shared.<Name>` between calls.
  2. Tool output is capped at ~100k characters. Return the base64 in ≤90k-char chunks wrapped in
     markers (e.g. `BEGIN[i]:…:END`); results that large are auto-saved to a file under
     `~/.claude/projects/…/tool-results/`. Pad small final chunks so they get saved to a file too.
  3. Reassemble the chunks with a small Python script (check the total length), base64-decode,
     `zstd -d`, and write the files. Never retype base64 by hand.
  4. Verify: `rojo build`, then compare against Studio – e.g. script source length + checksum and
     `#GetDescendants()` per container, computed the same way in Studio (`execute_luau`) and on the
     built place (`lune` with `@lune/roblox`). They must match exactly.
- Scripts can be read directly with `script_read` / `script_grep`; no export needed for code.

## Conventions

- Luau with type annotations where useful; tabs for indentation; double quotes.
- Services: `local X = {}` … `function X.Init()` … `return X`; started from `Main.server.luau`.
- Shared modules must stay side-effect free (data + pure helpers).
- Keep the header comment at the top of each module up to date – it is the module's documentation.
