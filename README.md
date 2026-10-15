# KebapUsta

Roblox kebab-restaurant simulator, managed with [Rojo](https://rojo.space).

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in this folder:
   ```sh
   rokit install
   ```
   This installs the pinned versions of rojo, lune, selene and stylua (`rokit.toml`).
2. Install the Rojo Studio plugin (Studio → Plugins, or `rojo plugin install`).
3. Recommended VS Code extensions are listed in `.vscode/extensions.json`.

## Working with Studio

```sh
rojo serve
```

In Studio open the place (Team Create), open the Rojo plugin and click **Connect**. Changes to
files in `src/` sync into Studio live.

> Rojo overwrites everything mapped in `default.project.json` – including the models in `assets/`.
> If you changed a model directly in Studio, export it back to its `.rbxm` file first.

## Building a place file

```sh
rojo build -o KebapUsta.rbxl
```

Place files are gitignored – the repo is the source of truth.

## Structure

| Path          | Studio location                          |
| ------------- | ---------------------------------------- |
| `src/server`  | ServerScriptService                      |
| `src/shared`  | ReplicatedStorage.Shared                 |
| `src/client`  | StarterPlayer.StarterPlayerScripts       |
| `assets/`     | Models (.rbxm) for Workspace, ServerStorage, StarterCharacter, Lighting, TextChatService |
| `art/`        | Blender sources (not synced): `food/` (bread, veg, meat, sauces) and `logistics/` (van, boxes, crates, cooler, shelf, meat cone). `python3 make_textures.py && python3 build_*.py` (needs `pip install bpy`) writes the FBX to `out/`; import it in Studio via 3D Importer into `ServerStorage.Models` |

See [CLAUDE.md](CLAUDE.md) for architecture and conventions.
