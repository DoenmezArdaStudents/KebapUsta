"""Backyard props for Kebap Usta: Pallet, Crate, ACUnit, LampHead (one mesh each, one texture atlas).

    pip install bpy numpy pillow --break-system-packages
    python3 build_backyard.py            (NO_RENDER=1 skips the preview)
Outputs out/kebap_backyard.fbx and out/preview.png. In Studio: 3D Importer -> put the MeshParts into
ServerStorage.Models.Backyard (names as above); Server/BackyardService sizes and places them and
falls back to primitive parts while they are missing. Units: studs, Blender Z up.
"""
import math
import os

import numpy as np
from PIL import Image
import bpy  # before bmesh
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT, TEX = os.path.join(HERE, "out"), os.path.join(HERE, "tex")
os.makedirs(OUT, exist_ok=True)
os.makedirs(TEX, exist_ok=True)
N = 512


def noise(scale, octaves=3, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((N, N)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        g = Image.fromarray((r.random((s + 1, s + 1)) * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        acc += np.asarray(g, float) / 255 * amp; tot += amp; amp *= 0.5
    return acc / tot


def lerp(a, b, t):
    t = t[..., None]
    return np.array(a, float) * (1 - t) + np.array(b, float) * t


yy, xx = np.mgrid[0:N, 0:N] / (N - 1)
# atlas quadrants: TL pallet wood (raw, grain along u) | TR crate wood (darker, stained)
#                  BL white powder-coated AC casing     | BR dark grey metal (lamp, fan grille)
grain = np.sin(yy * 90 + noise(3, 2, 1) * 8) * 0.5 + 0.5
pal = lerp((200, 162, 110), (160, 120, 76), grain * 0.6 + noise(20, 2, 2) * 0.4)
crt = lerp((150, 104, 62), (110, 74, 42), grain * 0.6 + noise(16, 2, 3) * 0.4)
ac = lerp((232, 232, 228), (204, 204, 198), noise(10, 2, 4))
ac = lerp(ac, (150, 140, 120), np.clip((yy - 0.92) * 10, 0, 1) * 0.4)
grille = (np.sin(xx * 220) > 0.2).astype(float)
dm = lerp((60, 62, 66), (36, 38, 40), noise(14, 2, 5) * 0.6 + grille * 0.4)
atlas = np.zeros((N, N, 3))
h = N // 2
atlas[:h, :h] = pal[:h, :h]; atlas[:h, h:] = crt[:h, h:]; atlas[h:, :h] = ac[h:, :h]; atlas[h:, h:] = dm[h:, h:]
Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8)).save(os.path.join(TEX, "backyard.png"))
PAL, CRT, AC, DM = (0.02, 0.52, 0.48, 0.98), (0.52, 0.52, 0.98, 0.98), (0.02, 0.02, 0.48, 0.48), (0.52, 0.02, 0.98, 0.48)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
mat = bpy.data.materials.new("backyard")
mat.use_nodes = True
t = mat.node_tree.nodes.new("ShaderNodeTexImage")
t.image = bpy.data.images.load(os.path.join(TEX, "backyard.png"))
mat.node_tree.links.new(t.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def box(self, c, s, reg):
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        u0, v0, u1, v1 = reg
        P = lambda x, y, z: Vector((cx + x * hx, cy + y * hy, cz + z * hz))
        for pts in ((P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)), (P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)),
                    (P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)), (P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)),
                    (P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)), (P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1))):
            f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
            for l, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                l[self.uv].uv = uv

    def cyl(self, c, r, hgt, reg, seg=16):
        u0, v0, u1, v1 = reg
        a_, b_ = [], []
        for i in range(seg + 1):
            a = 2 * math.pi * i / seg
            a_.append(Vector((c[0] + math.cos(a) * r, c[1] - hgt / 2, c[2] + math.sin(a) * r)))
            b_.append(Vector((c[0] + math.cos(a) * r, c[1] + hgt / 2, c[2] + math.sin(a) * r)))
        for i in range(seg):
            f = self.bm.faces.new([self.bm.verts.new(p) for p in (a_[i], a_[i + 1], b_[i + 1], b_[i])])
            for l, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                l[self.uv].uv = uv
        for ring in (a_, b_):
            ctr = sum(ring[:-1], Vector()) / seg
            for i in range(seg):
                f = self.bm.faces.new([self.bm.verts.new(ctr), self.bm.verts.new(ring[i]), self.bm.verts.new(ring[i + 1])])
                for l in f.loops:
                    l[self.uv].uv = ((u0 + u1) / 2, (v0 + v1) / 2)

    def done(self, name, x):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-4)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me); self.bm.free()
        o = bpy.data.objects.new(name, me)
        o.data.materials.append(mat)
        o.location = (x, 0, 0)
        scene.collection.objects.link(o)
        return o


objs = []
# Euro pallet 4 x 3.2 x 0.5: top deck boards, three stringers with blocks, bottom boards
m = Mesh()
for i in range(5):
    m.box(((i - 2) * 0.83, 0, 0.45), (0.7, 3.2, 0.1), PAL)
for y in (-1.4, 0, 1.4):
    m.box((0, y, 0.36), (4, 0.4, 0.08), PAL)
    for x in (-1.6, 0, 1.6):
        m.box((x, y, 0.18), (0.6, 0.4, 0.28), PAL)
for x in (-1.6, 0, 1.6):
    m.box((x, 0, 0.02), (0.6, 3.2, 0.04), PAL)
objs.append(m.done("Pallet", 0))
# slatted wooden crate 2.2 x 2.2 x 1.8 with corner posts
m = Mesh()
for z in (0.25, 0.75, 1.25, 1.65):
    for s in (-1, 1):
        m.box((0, s * 1.05, z), (2.2, 0.1, 0.32), CRT)
        m.box((s * 1.05, 0, z), (0.1, 2.0, 0.32), CRT)
for sx in (-1, 1):
    for sy in (-1, 1):
        m.box((sx * 1.0, sy * 1.0, 0.9), (0.22, 0.22, 1.8), CRT)
m.box((0, 0, 0.05), (2.1, 2.1, 0.1), CRT)
objs.append(m.done("Crate", 5))
# split AC outdoor unit 3.4 x 1.6 x 2.4 with a round fan grille and side valves
m = Mesh()
m.box((0, 0, 1.2), (3.4, 1.6, 2.4), AC)
m.cyl((-0.6, -0.82, 1.2), 0.85, 0.06, DM, 24)
m.cyl((-0.6, -0.86, 1.2), 0.18, 0.08, AC, 12)
for i in range(5):
    m.box((1.2, -0.81, 0.5 + i * 0.35), (0.7, 0.04, 0.12), DM)
m.box((1.75, 0.2, 0.6), (0.12, 0.5, 0.5), DM)
objs.append(m.done("ACUnit", 9))
# street lamp head 1.6 x 0.9 x 0.5, slightly tapered housing with a lip
m = Mesh()
m.box((0, 0, 0.3), (1.6, 0.9, 0.25), DM)
m.box((0, 0, 0.12), (1.45, 0.8, 0.14), DM)
m.box((-0.95, 0, 0.32), (0.4, 0.3, 0.2), DM)
objs.append(m.done("LampHead", 13))

print("faces", sum(len(o.data.polygons) for o in objs))
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "kebap_backyard.fbx"), use_selection=True, object_types={"MESH"},
                         path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE", apply_unit_scale=True, bake_space_transform=False)
if not os.environ.get("NO_RENDER"):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.location = (6.5, -14, 6)
    cam.rotation_euler = (math.radians(68), 0, 0)
    scene.camera = cam
    scene.world = bpy.data.worlds.new("w")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x, scene.render.resolution_y = 1000, 500
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)
print("done")
