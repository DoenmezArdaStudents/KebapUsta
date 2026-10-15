# NPC builder (Blender, headless)

Modular R15 customer NPCs for Kebap Usta, built procedurally with `bpy`: classic Roblox R15 block
look (exact default-rig sizes, measured in Studio) with small modern touches – rounded edges,
bevelled joints, tight 3D clothing with details at the edges. Replaces the old `tools/blender/`
customer models (not used anymore).

```sh
blender -b --factory-startup -P tools/npc/npc_builder.py -- --npc npc01 --upto 7 --render
```

- `--upto N` runs steps 1..N (1 scene · 2 R15 body · 3 materials · 4 clothing · 5 face/hair ·
  6 quality check · 7 export prep). Output goes to `tools/npc/out/` (gitignored):
  `npc01.blend`, `npc01_report.json` (tris, checks), `npc01_rig.json` (joints, motors, FBX settings),
  `renders/*.png`.
- Nothing is exported to FBX automatically; `export_fbx(path, run=True)` does it on request.

## How it is organised

- `CONFIG["body"]` – the shared base body (15 R15 parts as rounded boxes + classic head + joints).
  Fixed for all NPCs.
- `CONFIG["styles"]` – garment/hair styles with their parameters (`hoodie`, `jacket_open`, `jeans`,
  `sneaker`, `short_crop`). A new garment type = a new function registered in `STYLES`.
- `CONFIG["styles"]["face"]` – the face (`classic_smile`): eyes with a white shine, brows, nose, mouth
  as real geometry on the Head (half sunk, follows the faceted head), one object per colour
  (`Eyes_Head`, `EyeShine_Head`, `Brows_Head`, `Nose_Head`, `Mouth_Head`). Positions/sizes are parameters;
  an NPC can override them via `face.params`.
- `CONFIG["variants"]` – extra pieces of the shared mesh set that npc01 does not wear but the game
  picks per look: `Buzz` (hair under hats), `Tail` (ponytail under hats), `BrowsThin` + `Lashes`
  (women). Hidden in renders, exported with everything else.
- Random looks: `src/shared/CustomerLooks.luau` (which pieces, which colours, from the lookSeed),
  `src/server/Services/CustomerAppearance.luau` (puts a look onto an R15 rig).
- `CONFIG["npcs"]` – one entry per NPC: materials (colour + roughness), clothing list
  (`type`, `style`, `colors`, optional `params` overrides, `enabled`), hair, accessories.
- One material per object (Roblox MeshParts have one colour): `Hoodie_LeftLowerArm` +
  `HoodieAccent_LeftLowerArm`. Every object's origin is the joint of its R15 part.
- Layering rule: garments reuse the ring segments (count and phase) of the body part below them.

## Seeing an NPC in Studio

**Preview without upload (edit mode only):**

1. `blender -b --factory-startup -P tools/npc/npc_builder.py -- --npc npc01 --upto 7 --studio`
   → `out/studio/` (Manifest.json + base64 data).
2. With `rojo serve` connected, temporarily add to `default.project.json` under `ServerStorage`:
   `"NpcPreviewData": {"$className": "Folder", "Data": {"$path": "tools/npc/out/studio/data"},
   "Manifest": {"$path": "tools/npc/out/studio/Manifest.json"}}`.
3. Run `tools/npc/studio_preview.luau` in Studio (MCP `execute_luau` or command bar): builds the mesh
   templates (`ServerStorage.CustomerPartsPreview`), loads the free Roblox catalog items of
   `Shared/CustomerLooks` into `ServerStorage.CustomerAccessories` and lines up customers for `SEEDS`
   in `workspace.CustomerLookPreview`, dressed by `Server/CustomerAppearance` (the game code).
   Then remove the node from the project file again.

Each mesh is welded to its R15 segment by its offset from the segment centre (`offset` in the
manifest), because the current Roblox R15 rig (AnimationConstraints) places its joints slightly
differently from the values in `CONFIG["body"]["joints"]`; the part sizes match exactly.
EditableMesh geometry is **not saved and is lost in a playtest** (checked: `MeshContent` is empty on
server and client), so the preview is only for looking at it in edit mode.

**In the game:** `--fbx` writes `out/<npc>.fbx`. Import it with the Studio 3D Importer (uploads the
meshes, needs upload rights for the game); then the MeshParts can be welded onto a rig and saved to
`assets/` like any other model.

## Into the game (after mesh changes)

1. `blender -b --factory-startup -P tools/npc/npc_builder.py -- --npc npc01 --upto 7 --studio --fbx`
2. Studio → *File → Import 3D* → `out/npc01.fbx`, Name `CustomerPartsImport`, Anchored on,
   Rig Type **No Rig**, Merge Meshes **off** (rest default). Uploads the meshes (needs upload rights).
3. Sync the manifest (temporary node `NpcPreviewData` → `Manifest` in `default.project.json`) and run
   `tools/npc/bake_parts.luau`: sizes / 100 (the importer reads the FBX centimetres as studs),
   attributes Item / Part / Offset → `ServerStorage.CustomerParts`.
4. Export `ServerStorage.CustomerParts` (and `CustomerAccessories` if the catalog list in
   `Shared/CustomerLooks` changed – `studio_preview.luau` loads it) to `assets/ServerStorage/*.rbxm`
   with the CLAUDE.md recipe, check with `rojo build` + lune.
5. Rojo cannot set `MeshId` on MeshParts it creates (see CLAUDE.md): keep the Studio copies that have
   the meshes and delete the empty copies Rojo adds.

The meshes are uploaded to the account that imports them. Studio playtests use your own account, so
check once in a live server that the game may use them (Creator Hub → asset → Permissions).
