"""Garbage truck (rear loader) for the paid waste collection – issue #14.

    python3 build_truck.py           (NO_RENDER=1 skips the preview)
Outputs out/kebap_truck.fbx + out/preview_truck.png. One material per mesh (Roblox: one per MeshPart):
  TruckPaint  orange cab shell + compactor body + tailgate
  TruckDark   chassis, bumpers, fenders, hopper mouth, lift bar, grille, mirrors
  TruckGlass  windscreen and side windows
  TruckWhite  reflective side stripes
  TruckWheel  one wheel (tyre + hub), the game places six and spins them
Modelled in Roblox space (front = -Z like the delivery van, ground Y = 0) and converted on export
(Roblox X = -Blender X, Y = Blender Z, Z = Blender Y). Length 18 (Z -9 … 9), width 6.2, height 8.6.
"""
import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def rb(x, y, z):
    return Vector((-x, z, y))


def mat(name, color, rough=0.5, metal=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
    return m


def box(x0, y0, z0, x1, y1, z1, top_shrink=(0, 0)):
    """axis-aligned box in Roblox space; top_shrink = (x, z) inset of the top face"""
    sx, sz = top_shrink
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (x0 + sx, y1, z0 + sz), (x1 - sx, y1, z0 + sz), (x1 - sx, y1, z1), (x0 + sx, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def prism_x(x0, x1, profile):
    """extrude a (y, z) polygon along X"""
    n = len(profile)
    v = [(x0, y, z) for y, z in profile] + [(x1, y, z) for y, z in profile]
    f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    return v, f


def prism_z(z0, z1, profile, scale1=1.0):
    """extrude an (x, y) polygon along Z; the far end can be scaled about the profile's bottom centre"""
    n = len(profile)
    ymin = min(y for _, y in profile)
    v = [(x, y, z0) for x, y in profile] + [(x * scale1, ymin + (y - ymin) * scale1, z1) for x, y in profile]
    f = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        f.append((j, i, n + i, n + j))
    return v, f


def rounded_rect(x0, y0, x1, y1, r, seg=5):
    pts = []
    for cx, cy, a0 in ((x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return [(x0, y0)] + list(reversed(pts)) + [(x1, y0)] if False else [(x1, y0)] + pts + [(x0, y0)]


def merge(blocks):
    V, F = [], []
    for v, f in blocks:
        o = len(V)
        V += v
        F += [tuple(i + o for i in face) for face in f]
    return V, F


def obj(name, blocks, material, bevel=0.0, smooth=False):
    v, f = merge(blocks)
    me = bpy.data.meshes.new(name)
    me.from_pydata([rb(*p) for p in v], [], f)
    me.update()
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    o.data.materials.append(material)
    if bevel > 0:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width, b.segments, b.limit_method = bevel, 2, "ANGLE"
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="bevel")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for fc in bm.faces:
        fc.smooth = smooth
    bm.to_mesh(o.data)
    bm.free()
    return o


W = 3.1  # half width
orange = mat("Orange", (0.95, 0.38, 0.04), 0.4)
dark = mat("Dark", (0.06, 0.06, 0.07), 0.6)
glass = mat("Glass", (0.08, 0.12, 0.16), 0.05, 0.3)
tyre = mat("Tyre", (0.03, 0.03, 0.03), 0.8)

# ------------------------------------------------------------------ paint: cab + compactor body + tailgate
cab_profile = [(1.4, -9.0), (1.4, -4.6), (7.4, -4.6), (7.4, -7.9), (6.9, -8.7), (4.6, -9.2), (1.4, -9.2)]
paint = [
    prism_x(-W, W, cab_profile),
    prism_z(-4.2, 5.6, rounded_rect(-W, 1.9, W, 8.4, 1.5), 0.98),  # rounded compactor body
    prism_x(-W + 0.1, W - 0.1, [(1.6, 5.5), (8.1, 5.5), (7.5, 7.9), (4.3, 9.0), (4.0, 7.6), (1.6, 7.6)]),  # slanted tailgate
]
paint_o = obj("TruckPaint", paint, orange, bevel=0.12)

# ------------------------------------------------------------------ dark parts
darkb = [
    box(-2.4, 0.9, -8.6, 2.4, 1.6, 8.6),  # chassis frame
    box(-W - 0.05, 0.7, -9.6, W + 0.05, 1.6, -9.05),  # front bumper
    box(-W + 0.4, 2.0, -9.28, W - 0.4, 3.6, -9.18),  # grille
    box(-W + 0.3, 1.0, 7.6, W - 0.3, 4.0, 9.0),  # hopper mouth (rear)
    box(-W + 0.1, 3.9, 8.6, W - 0.1, 4.2, 9.05),  # lift bar
    box(-W - 0.02, 0.9, 7.4, W + 0.02, 1.5, 9.1),  # rear step / bumper
]
for z in (-6.9, 1.7, 4.6):  # fenders over the axles
    darkb.append(box(-W - 0.1, 2.15, z - 1.5, W + 0.1, 2.4, z + 1.5))
for s in (-1, 1):  # mirrors on arms
    darkb.append(box(s * (W + 0.05), 5.2, -8.3, s * (W + 0.65), 6.6, -8.05))
    darkb.append(box(s * W, 5.9, -8.25, s * (W + 0.1), 6.0, -8.1))
for s in (-1, 1):  # rear lights housings
    darkb.append(box(s * (W - 0.6), 4.3, 7.55, s * (W - 0.1), 5.2, 7.7))
dark_o = obj("TruckDark", darkb, dark, bevel=0.04)

# ------------------------------------------------------------------ glass
glassb = [
    prism_x(-W + 0.25, W - 0.25, [(5.0, -9.25), (6.85, -8.75), (7.3, -7.95), (7.3, -7.85), (6.8, -8.62), (5.0, -9.12)]),  # windscreen
]
for s in (-1, 1):
    x0, x1 = (s * W, s * (W + 0.03)) if s > 0 else (s * (W + 0.03), s * W)
    glassb.append(prism_x(x0, x1, [(4.6, -8.7), (4.6, -5.0), (7.0, -5.0), (7.0, -7.9)]))
glass_o = obj("TruckGlass", glassb, glass)

# ------------------------------------------------------------------ white reflective stripes on the body
white = mat("White", (0.92, 0.92, 0.9), 0.4)
whiteb = []
for s_ in (-1, 1):
    for y in (3.0, 3.6):
        x0, x1 = (W, W + 0.03) if s_ > 0 else (-W - 0.03, -W)
        whiteb.append(box(x0, y, -4.0, x1, y + 0.3, 5.4))
white_o = obj("TruckWhite", whiteb, white)

# ------------------------------------------------------------------ wheel (axis along X)
seg = 20
wv, wf = [], []
R, HW = 1.1, 0.42
rings = [(R * 0.88, -HW), (R, -HW * 0.7), (R, HW * 0.7), (R * 0.88, HW), (0.55, HW + 0.02), (0.55, -HW - 0.02)]
for r, x in rings:
    for i in range(seg):
        a = i / seg * math.tau
        wv.append((x, math.cos(a) * r, math.sin(a) * r))
for k in range(len(rings) - 1):
    for i in range(seg):
        j = (i + 1) % seg
        wf.append((k * seg + i, k * seg + j, (k + 1) * seg + j, (k + 1) * seg + i))
o0 = len(rings) - 1
wf.append(tuple(o0 * seg + i for i in range(seg)))
wf.append(tuple(i for i in range(seg - 1, -1, -1)))
wheel_o = obj("TruckWheel", [(wv, wf)], tyre, smooth=True)

OBJS = [paint_o, dark_o, glass_o, white_o, wheel_o]
for ob in OBJS:
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c, s = (lo + hi) / 2, hi - lo
    print("ROBLOX %-10s centre (%.3f, %.3f, %.3f) size (%.3f, %.3f, %.3f)" % (ob.name, -c.x, c.z, c.y, s.x, s.z, s.y))

bpy.ops.object.select_all(action="DESELECT")
for ob in OBJS:
    ob.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "kebap_truck.fbx"), use_selection=True, object_types={"MESH"}, mesh_smooth_type="FACE", apply_unit_scale=True, axis_forward="-Z", axis_up="Y")
print("exported")
if os.environ.get("NO_RENDER"):
    raise SystemExit(0)

# preview: wheels at the axles (Roblox z -6.9, 1.7, 4.6; x ±2.75; y 1.1)
wheel_o.hide_render = True
for z in (-6.9, 1.7, 4.6):
    for x in (-2.75, 2.75):
        w2 = wheel_o.copy()
        w2.location = rb(x, 1.1, z)
        w2.hide_render = False
        scene.collection.objects.link(w2)
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
bpy.context.active_object.data.materials.append(mat("Floor", (0.25, 0.25, 0.26), 0.9))
for loc, e in (((-14, -10, 14), 3500), ((12, 8, 6), 900)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    lt = bpy.context.active_object
    lt.data.energy, lt.data.size = e, 8
    lt.rotation_euler = (Vector((0, 0, 3)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
wd = bpy.data.worlds.new("W")
wd.use_nodes = True
wd.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.68, 1)
scene.world = wd
bpy.ops.object.camera_add(location=(-17, -16, 9))
cam = bpy.context.active_object
cam.data.lens = 32
cam.rotation_euler = (Vector((0, 0, 3.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1100, 650
scene.render.filepath = os.path.join(OUT, "preview_truck.png")
bpy.ops.render.render(write_still=True)
print("preview")
