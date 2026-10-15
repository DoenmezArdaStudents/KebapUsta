"""Back door for Kebap Usta: steel service door (leaf) and its frame, two separate meshes.

    pip install bpy numpy pillow --break-system-packages
    python3 build_backdoor.py            (NO_RENDER=1 skips the preview)
Outputs out/kebap_backdoor.fbx (embedded texture) and out/preview.png.
In Studio: 3D Importer -> put the two MeshParts into ServerStorage.Models.BackDoor as "Leaf" and
"Frame" (Server/BackDoorService sizes and places them; without them it builds primitive parts).
Units are studs, Blender Z up; the leaf is modelled closed, hinge on +X, outside = -Y.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import bpy  # before bmesh
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TEX = os.path.join(HERE, "tex")
os.makedirs(OUT, exist_ok=True)
os.makedirs(TEX, exist_ok=True)

# ------------------------------------------------------------------ texture atlas (512x512)
# left half: green painted steel with scuffs; right top: brushed steel; right bottom: dark frame
N = 512
rng = np.random.default_rng(5)


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


paint = lerp((76, 100, 90), (60, 82, 74), noise(6, 3, 1))
scuff = np.clip((noise(24, 2, 2) - 0.7) * 5, 0, 1)
paint = lerp(paint, (150, 152, 150), scuff * 0.3)
yy = np.mgrid[0:N, 0:N][0] / (N - 1)
paint = lerp(paint, (54, 52, 46), np.clip((yy - 0.9) * 8, 0, 1) * 0.5)  # grime at the bottom
steel = lerp((190, 192, 196), (150, 152, 158), noise(40, 2, 3))
steel *= (0.94 + 0.06 * np.sin(np.mgrid[0:N, 0:N][1] / N * 600))[..., None]
dark = lerp((62, 64, 68), (48, 50, 54), noise(10, 2, 4))
atlas = paint.copy()
atlas[: N // 2, N // 2:] = steel[: N // 2, N // 2:]
atlas[N // 2:, N // 2:] = dark[N // 2:, N // 2:]
img = Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5))
img.save(os.path.join(TEX, "backdoor.png"))
PAINT, STEEL, DARK = (0.02, 0.02, 0.48, 0.98), (0.52, 0.52, 0.98, 0.98), (0.52, 0.02, 0.98, 0.48)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
mat = bpy.data.materials.new("backdoor")
mat.use_nodes = True
nt = mat.node_tree
t = nt.nodes.new("ShaderNodeTexImage")
t.image = bpy.data.images.load(os.path.join(TEX, "backdoor.png"))
bsdf = nt.nodes["Principled BSDF"]
nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Metallic"].default_value = 0.6
bsdf.inputs["Roughness"].default_value = 0.45


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def quad(self, pts, uvs, smooth=False):
        f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        f.smooth = smooth
        for l, uv in zip(f.loops, uvs):
            l[self.uv].uv = uv

    def box(self, c, s, reg):
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        u0, v0, u1, v1 = reg
        P = lambda x, y, z: Vector((cx + x * hx, cy + y * hy, cz + z * hz))
        uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        for pts in (
            (P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)),
            (P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)),
            (P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)),
            (P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)),
            (P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)),
            (P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1)),
        ):
            self.quad(pts, uv)

    def cyl(self, c, r, h, axis, reg, seg=12):
        u0, v0, u1, v1 = reg
        ra, rb = [], []
        for i in range(seg + 1):
            a = 2 * math.pi * i / seg
            x, y = math.cos(a) * r, math.sin(a) * r
            if axis == "z":
                pa, pb = Vector((x, y, -h / 2)), Vector((x, y, h / 2))
            elif axis == "x":
                pa, pb = Vector((-h / 2, x, y)), Vector((h / 2, x, y))
            else:
                pa, pb = Vector((x, -h / 2, y)), Vector((x, h / 2, y))
            ra.append(pa + Vector(c)); rb.append(pb + Vector(c))
        for i in range(seg):
            ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
            self.quad((ra[i], ra[i + 1], rb[i + 1], rb[i]), [(ua, v0), (ub, v0), (ub, v1), (ua, v1)], True)
        for ring in (ra, rb):
            ctr = sum(ring[:-1], Vector()) / seg
            for i in range(seg):
                f = self.bm.faces.new([self.bm.verts.new(ctr), self.bm.verts.new(ring[i]), self.bm.verts.new(ring[i + 1])])
                for l in f.loops:
                    l[self.uv].uv = ((u0 + u1) / 2, (v0 + v1) / 2)

    def finish(self, name, bevel=0.0):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-4)
        if bevel:
            edges = [e for e in self.bm.edges if e.calc_face_angle(0) > 1.2]
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, affect="EDGES", profile=0.5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        o = bpy.data.objects.new(name, me)
        scene.collection.objects.link(o)
        o.data.materials.append(mat)
        return o


# leaf: 3.3 wide (X), 8.1 high (Z), 0.18 thick (Y); hinge side = +X, outside = -Y
W, H, T = 3.3, 8.1, 0.18
leaf = Mesh()
leaf.box((0, 0, 0), (W, T, H), PAINT)
for zc, hh in ((H * 0.22, H * 0.36), (-H * 0.24, H * 0.3)):  # embossed panels both sides
    for y in (-T / 2 - 0.02, T / 2 + 0.02):
        leaf.box((0, y, zc), (W - 0.6, 0.04, hh), PAINT)
for y in (-T / 2 - 0.03, T / 2 + 0.03):  # kick plates
    leaf.box((0, y, -H / 2 + 0.4), (W - 0.1, 0.03, 0.7), STEEL)
leaf.box((0, 0, H * 0.27), (0.95, T + 0.06, 1.45), DARK)  # window frame
leaf.box((0, 0, H * 0.27), (0.8, T + 0.08, 1.3), (0.55, 0.6, 0.6, 0.65))  # wired glass (light steel tone)
# inside (+Y): push bar with two mounts; outside (-Y): pull handle, lock cylinder
leaf.cyl((0.1, T / 2 + 0.22, -0.15), 0.08, W - 0.9, "x", STEEL)
for x in (-W / 2 + 0.45, W / 2 - 0.45):
    leaf.box((x, T / 2 + 0.13, -0.15), (0.2, 0.18, 0.3), DARK)
leaf.cyl((-W / 2 + 0.4, -T / 2 - 0.3, 0), 0.06, 0.9, "z", STEEL)
for z in (0.45, -0.45):
    leaf.cyl((-W / 2 + 0.4, -T / 2 - 0.17, z), 0.05, 0.26, "y", STEEL)
leaf.cyl((-W / 2 + 0.4, -T / 2 - 0.02, -0.75), 0.09, 0.06, "y", (0.6, 0.6, 0.7, 0.7))
leaf.box((W / 2 - 0.7, T / 2 + 0.15, H / 2 - 0.3), (0.9, 0.25, 0.25), DARK)  # door closer
leaf_o = leaf.finish("Leaf", bevel=0.01)

# frame: two jambs + head + three hinge barrels, 3.8 wide x 8.4 high x 1.2 deep, centred
FW, FH, FD = 3.8, 8.4, 1.2
frame = Mesh()
frame.box((-FW / 2 + 0.125, 0, 0), (0.25, FD, FH), DARK)
frame.box((FW / 2 - 0.125, 0, 0), (0.25, FD, FH), DARK)
frame.box((0, 0, FH / 2 - 0.15), (FW, FD, 0.3), DARK)
for x in (-FW / 2 + 0.26, FW / 2 - 0.26):  # stop strips the leaf closes against
    frame.box((x, 0.1, -0.1), (0.04, 0.1, FH - 0.5), STEEL)
for z in (-FH / 2 + 1.0, 0, FH / 2 - 1.0):
    frame.cyl((FW / 2 - 0.25, -0.45, z), 0.08, 0.5, "z", STEEL)
frame_o = frame.finish("Frame", bevel=0.015)
frame_o.location = (5, 0, 0)

print("faces", sum(len(o.data.polygons) for o in (leaf_o, frame_o)))
bpy.ops.object.select_all(action="DESELECT")
for o in (leaf_o, frame_o):
    o.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "kebap_backdoor.fbx"), use_selection=True, object_types={"MESH"},
                         path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE", apply_unit_scale=True, bake_space_transform=False)

if not os.environ.get("NO_RENDER"):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.location = (2.5, -13, 3)
    cam.rotation_euler = (math.radians(84), 0, math.radians(10))
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    scene.world = bpy.data.worlds.new("w")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x, scene.render.resolution_y = 900, 700
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)
print("done")
