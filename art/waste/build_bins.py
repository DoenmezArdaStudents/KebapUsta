"""Outdoor waste containers (660 l, four castors) for the backyard waste area – issue #12.

    python3 build_bins.py            (NO_RENDER=1 skips the preview)
Outputs out/kebap_bins.fbx + out/preview_bins.png with three meshes:
  BinBody  tapered container with rim, ribs, side handles, castors (plain material: the game
           colours it – grey "Restmüll", yellow "Plastik", brown "Bio")
  BinLid   domed lid with front grip, separate so the game can swing it open (hinge at the back)
  BinCastors  the four black castor wheels (static)
  BinBag   a tied full garbage bag (carried by players / the garbage collector)
Modelled directly in Roblox space and converted on export (Roblox X = -Blender X, Y = Blender Z,
Z = Blender Y), so the MeshParts need no extra rotation in the game. The bin's front faces +X;
ground at Y = 0. Body 2.2 (X) × 3.4 (Z) × 3.25 (Y); lid on top up to Y ≈ 3.55.
"""
import math
import os

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def rb(x, y, z):
    """Roblox coordinates -> Blender"""
    return Vector((-x, z, y))


def mat(name, color, rough=0.6, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def mesh_from(name, verts, faces, material, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata([rb(*v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = smooth
    return o


def box(x0, y0, z0, x1, y1, z1, taper=(1.0, 1.0)):
    """box in Roblox space; taper scales the bottom face (x, z)"""
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    hx, hz = (x1 - x0) / 2, (z1 - z0) / 2
    tx, tz = taper
    v = [
        (cx - hx * tx, y0, cz - hz * tz), (cx + hx * tx, y0, cz - hz * tz), (cx + hx * tx, y0, cz + hz * tz), (cx - hx * tx, y0, cz + hz * tz),
        (cx - hx, y1, cz - hz), (cx + hx, y1, cz - hz), (cx + hx, y1, cz + hz), (cx - hx, y1, cz + hz),
    ]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def cylinder_z(cx, cy, cz, r, half, seg=14):
    """cylinder with its axis along Roblox Z (castor wheels)"""
    v, f = [], []
    for s in (-1, 1):
        for i in range(seg):
            a = i / seg * math.tau
            v.append((cx + math.cos(a) * r, cy + math.sin(a) * r, cz + s * half))
    for i in range(seg):
        j = (i + 1) % seg
        f.append((i, j, seg + j, seg + i))
    f.append(tuple(range(seg - 1, -1, -1)))
    f.append(tuple(range(seg, 2 * seg)))
    return v, f


def merge(*blocks):
    V, F = [], []
    for v, f in blocks:
        o = len(V)
        V += v
        F += [tuple(i + o for i in face) for face in f]
    return V, F


def finish(o, bevel=0.0, seg=2):
    if bevel > 0:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width, b.segments, b.limit_method = bevel, seg, "ANGLE"
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="bevel")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


plastic = mat("BinPlastic", (0.35, 0.36, 0.38), 0.55)
dark = mat("Dark", (0.05, 0.05, 0.05), 0.7)
bagmat = mat("Bag", (0.03, 0.03, 0.035), 0.35)

# ------------------------------------------------------------------ body
D, W, H = 2.2, 3.4, 3.25  # depth (X), width (Z), height (Y)
parts = [box(-D / 2, 0.42, -W / 2, D / 2, H, W / 2, taper=(0.86, 0.9))]
# top rim
parts.append(box(-D / 2 - 0.08, H - 0.18, -W / 2 - 0.08, D / 2 + 0.08, H, W / 2 + 0.08))
# vertical ribs on the front
for z in (-1.1, -0.37, 0.37, 1.1):
    parts.append(box(D / 2 * 0.9 - 0.02, 0.6, z - 0.07, D / 2 * 0.98 + 0.06, H - 0.3, z + 0.07, taper=(0.88, 1)))
# side handles (bars) and the back hinge rail
for s in (-1, 1):
    parts.append(box(-0.5, H - 0.75, s * (W / 2 + 0.02) - 0.07, 0.5, H - 0.6, s * (W / 2 + 0.02) + 0.07))
parts.append(box(-D / 2 - 0.16, H - 0.2, -W / 2 + 0.2, -D / 2 - 0.02, H - 0.02, W / 2 - 0.2))
# castor forks + wheels
for x in (-0.65, 0.65):
    for z in (-1.25, 1.25):
        parts.append(box(x - 0.12, 0.28, z - 0.16, x + 0.12, 0.44, z + 0.16))
body_v, body_f = merge(*parts)
body = finish(mesh_from("BinBody", body_v, body_f, plastic), bevel=0.04)
wheels_v, wheels_f = merge(*[cylinder_z(x, 0.19, z, 0.19, 0.08) for x in (-0.65, 0.65) for z in (-1.25, 1.25)])
castors = mesh_from("BinCastors", wheels_v, wheels_f, dark, smooth=True)  # separate MeshPart: one material per mesh

# ------------------------------------------------------------------ lid (hinge along the back top edge)
lv, lf = [], []
nx, nz = 8, 10
LX0, LX1, LZ = -D / 2 - 0.1, D / 2 + 0.16, W / 2 + 0.12
for j in range(nz + 1):
    for i in range(nx + 1):
        x = LX0 + (LX1 - LX0) * i / nx
        z = -LZ + 2 * LZ * j / nz
        u, w = (i / nx) * 2 - 1, (j / nz) * 2 - 1
        lv.append((x, H + 0.1 + 0.16 * (1 - u * u) * (1 - w ** 4), z))
top = len(lv)
for j in range(nz + 1):
    for i in range(nx + 1):
        x, y, z = lv[j * (nx + 1) + i]
        lv.append((x, H + 0.02, z))
for j in range(nz):
    for i in range(nx):
        a = j * (nx + 1) + i
        lf.append((a, a + 1, a + nx + 2, a + nx + 1))
        b = top + a
        lf.append((b, b + nx + 1, b + nx + 2, b + 1))
# skirt around the edge
ring = [j * (nx + 1) for j in range(nz + 1)] + [nz * (nx + 1) + i for i in range(1, nx + 1)] + [j * (nx + 1) + nx for j in range(nz - 1, -1, -1)] + [i for i in range(nx - 1, 0, -1)]
for k in range(len(ring)):
    a, b = ring[k], ring[(k + 1) % len(ring)]
    lf.append((a, b, top + b, top + a))
gv, gf = box(LX1 - 0.04, H - 0.12, -0.9, LX1 + 0.08, H + 0.1, 0.9)  # front grip
o = len(lv)
lv += gv
lf += [tuple(i + o for i in face) for face in gf]
lid = finish(mesh_from("BinLid", lv, lf, plastic, smooth=False), bevel=0.0)

# ------------------------------------------------------------------ garbage bag
bv, bf = [], []
rings, seg = 9, 16
for r in range(rings + 1):
    t = r / rings
    y = 0.05 + t * 1.25
    rad = 0.62 * math.sin(math.pi * min(1, t * 1.05)) ** 0.6 * (1 - 0.75 * max(0, t - 0.78) / 0.22) + 0.06
    for i in range(seg):
        a = i / seg * math.tau
        wob = 1 + 0.08 * math.sin(a * 3 + t * 7) + 0.05 * math.sin(a * 5 - t * 3)
        bv.append((math.cos(a) * rad * wob, y, math.sin(a) * rad * wob * 0.9))
for r in range(rings):
    for i in range(seg):
        j = (i + 1) % seg
        bf.append((r * seg + i, r * seg + j, (r + 1) * seg + j, (r + 1) * seg + i))
bf.append(tuple(range(seg - 1, -1, -1)))
o = len(bv)
for i in range(seg):  # knot
    a = i / seg * math.tau
    bv.append((math.cos(a) * 0.1, 1.42, math.sin(a) * 0.1))
bf.append(tuple(range(o, o + seg)))
for i in range(seg):
    j = (i + 1) % seg
    bf.append((rings * seg + i, rings * seg + j, o + j, o + i))
bag = finish(mesh_from("BinBag", bv, bf, bagmat, smooth=True))

OBJS = [body, castors, lid, bag]
for ob in OBJS:
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c, s = (lo + hi) / 2, hi - lo
    print("ROBLOX %-8s centre (%.3f, %.3f, %.3f) size (%.3f, %.3f, %.3f) tris %d" % (ob.name, -c.x, c.z, c.y, s.x, s.z, s.y, sum(len(p.vertices) - 2 for p in ob.data.polygons)))

bpy.ops.object.select_all(action="DESELECT")
for ob in OBJS:
    ob.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "kebap_bins.fbx"), use_selection=True, object_types={"MESH"}, mesh_smooth_type="FACE", apply_unit_scale=True, axis_forward="-Z", axis_up="Y")
print("exported")
if os.environ.get("NO_RENDER"):
    raise SystemExit(0)

# ------------------------------------------------------------------ preview: three coloured bins, one open, a bag
COLORS = {"Restmüll": (0.18, 0.19, 0.2), "Plastik": (0.85, 0.65, 0.05), "Bio": (0.3, 0.17, 0.08)}
for k, (n, col) in enumerate(COLORS.items()):
    for src in (body, lid, castors):
        ob = src.copy()
        ob.data = src.data.copy()
        m = mat(n + src.name, col, 0.5)
        ob.data.materials[0] = m
        ob.location = rb(0, 0, (k - 1) * 3.9)
        scene.collection.objects.link(ob)
        if src is lid and k == 2:
            # open about the hinge (back top edge, Roblox x = LX0, y = H + 0.02)
            pivot = rb(LX0, H + 0.02, 0)
            ob.location = ob.location + pivot
            ob.data.transform(__import__("mathutils").Matrix.Translation(-pivot))
            ob.rotation_euler = (0, math.radians(-95), 0)
b2 = bag.copy()
b2.location = rb(2.4, 0, 0.5)
scene.collection.objects.link(b2)
for ob in OBJS:
    ob.hide_render = True
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
fl = bpy.context.active_object
fl.data.materials.append(mat("Floor", (0.35, 0.34, 0.32), 0.9))
for loc, e in (((-6, -6, 8), 1500), ((5, 4, 4), 500)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    lt = bpy.context.active_object
    lt.data.energy, lt.data.size = e, 5
    lt.rotation_euler = (Vector((0, 0, 1.5)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
w = bpy.data.worlds.new("W")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.68, 1)
scene.world = w
bpy.ops.object.camera_add(location=(-11, -6.5, 5.5))
cam = bpy.context.active_object
cam.data.lens = 35
cam.rotation_euler = (Vector((0, 0, 1.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1100, 650
scene.render.filepath = os.path.join(OUT, "preview_bins.png")
bpy.ops.render.render(write_still=True)
print("preview")
