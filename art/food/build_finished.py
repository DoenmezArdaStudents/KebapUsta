"""Finished (closed) kebab products for Kebap Usta – issue #4 ("Kebap Model Clean Up").

What the player hands out / carries is no longer assembled from loose ingredient pieces plus box
parts, but built from these dedicated meshes:
  KebapBread    half-moon pide pocket, opened at the top (bread_atlas.png)
  KebapFilling  filling mound + salad / tomato / meat bits sticking out of the pocket (filling.png)
  KebapPaper    wrapping paper around the lower half with the shop's red band (paper.png)
  DuerumFoil    crinkled foil around the back half of a rolled dürüm (foil.png)
  DuerumEnd     the filling visible at the open end of the dürüm (filling.png)
  BoxClosed     styrofoam clamshell box, closed (plain white, no texture)
All share one product origin: ground centre, length along Blender X (= Roblox X, mirrored),
thickness along Blender Y (= Roblox Z), up = Blender Z (= Roblox Y). Because Roblox centres every
MeshPart on its bounding box, the script prints each mesh's bounding-box centre in Roblox
coordinates – FoodPreparationService uses them as offsets (FINISHED table).

    python3 make_textures.py && python3 make_finished_textures.py && python3 build_finished.py
Outputs: out/kebap_finished.fbx and out/preview_finished.png
"""
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
# reuse the helpers (material, make_object, grid_surface, …) and the dürüm roll from build_food.py
_src = open(os.path.join(HERE, "build_food.py")).read().split("# --------------------------------------------------------------------------- export")[0]
_g = {"__file__": os.path.join(HERE, "build_food.py"), "__name__": "build_food"}
exec(compile(_src, "build_food.py", "exec"), _g)

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

material, make_object, grid_surface, merge, flipped, bump = (_g[k] for k in ("material", "make_object", "grid_surface", "merge", "flipped", "bump"))
scene = bpy.context.scene
OUT = os.path.join(HERE, "out")
random.seed(4)
for o in _g["FOOD"]:
    o.hide_render = True
    o.hide_set(True)


def finish(obj, smooth_angle=60):
    """weld duplicate vertices (UVs are per loop, so seams keep their UVs) and fix normals"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0015)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(obj.data)
    bm.free()
    return obj


# --------------------------------------------------------------------------- kebab pocket
R, HH = 0.95, 1.12  # half length, height of the bread (bottom of the arc at z = 0)
NU = 36


def w_of(u):
    return math.sqrt(max(0.0, 1 - u * u))


def ztop(u):
    return HH - 0.07 * (1 - w_of(u))


def zline(u, v):
    """height of the pocket's middle surface: v = 0 top edge … v = 1 bottom rim"""
    zt = ztop(u)
    zb = HH * (1 - w_of(u)) + 0.04
    return zt - (zt - zb) * (v ** 0.95)


def sep(u, v):
    """half opening of the pocket (inner crumb surface)"""
    return 0.29 * (1 - v) ** 0.85 * w_of(u) ** 0.45


def thick(u):
    return 0.13 * w_of(u) ** 0.35 + 0.015


def outer_point(u, v, side):
    """crust surface; side +1 front, -1 back; at v = 1 both sides meet under the bread"""
    k = math.sin(min(1.0, v) * math.pi / 2)
    y = side * (sep(u, v) + thick(u) * math.cos(k * math.pi / 2) ** 0.6 * (1 + 0.15 * math.sin(math.pi * v)))
    z = zline(u, v) - thick(u) * k ** 6 * 0.9
    p = Vector((u * R * (1 + 0.02 * math.sin(v * 3)), y, z))
    n = Vector((0, side, 0.25))
    return p + n.normalized() * (bump(p, 0.018, 3.4) + bump(p, 0.006, 11))


def build_bread():
    nv = 14
    us = [-1 + 2 * i / NU for i in range(NU + 1)]

    # crust: front top → bottom → back top (one continuous strip, phi 0..1)
    def opos(i, j):
        phi = j / (2 * nv)
        side, v = (1, phi * 2) if phi <= 0.5 else (-1, (1 - phi) * 2)
        return outer_point(us[i], v, side)

    def ouv(i, j):
        u = us[i]
        phi = j / (2 * nv)
        return (0.25 + u * 0.23, 0.5 + (phi - 0.5) * 0.92)

    crust = grid_surface(NU, 2 * nv, opos, ouv)

    # crumb inside the pocket: back top → bottom → front top
    def ipos(i, j):
        phi = j / (2 * nv)
        side, v = (-1, phi * 2) if phi <= 0.5 else (1, (1 - phi) * 2)
        u = us[i]
        return Vector((u * R, side * sep(u, v), zline(u, v)))

    def iuv(i, j):
        return (0.75 + us[i] * 0.22, 0.25 + (j / (2 * nv) - 0.5) * 0.4)

    crumb = grid_surface(NU, 2 * nv, ipos, iuv)

    # cut faces of the bread along the top edge (crumb coloured), front and back
    def band(side):
        def pos(i, j):
            u = us[i]
            if j == 0:
                return outer_point(u, 0, side)
            return Vector((u * R, side * sep(u, 0), zline(u, 0)))

        return grid_surface(NU, 1, pos, lambda i, j: (0.75 + us[i] * 0.22, 0.42 + 0.04 * j))

    v, f, u = merge(crust, crumb, band(1), band(-1))
    return finish(make_object("KebapBread", v, f, u, material("Bread", "bread_atlas.png", 0.75, 0.25)))


def leaf(cx, cy, cz, yaw, tilt, size, uv0, curl=0.08, span=0.42):
    """small curved two-sided quad patch (lettuce leaf / tomato slice / meat shaving) in the filling atlas"""
    nu, nv = 4, 5
    rot = Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(tilt, 3, "X")

    def pos(i, j):
        s, t = i / nu - 0.5, j / nv - 0.5
        x = s * size[0] * (1 - 0.35 * abs(t * 2) ** 2)
        y = t * size[1]
        z = curl * (s * s * 4) + 0.03 * math.sin(t * 9 + s * 4)
        return Vector((cx, cy, cz)) + rot @ Vector((x, z, y))

    def uv(i, j):
        return (uv0[0] + i / nu * span, uv0[1] + j / nv * span)

    blk = grid_surface(nu, nv, pos, uv)
    back = flipped(blk)
    return merge(blk, ([p - rot @ Vector((0, 0.008, 0)) for p in back[0]], back[1], back[2]))


MIX, LET, TOM, MEAT = (0.04, 0.04), (0.54, 0.04), (0.04, 0.54), (0.54, 0.54)


def build_filling():
    nk, nu = 12, 30
    us = [-0.93 + 1.86 * i / nu for i in range(nu + 1)]

    def pos(i, j):
        u = us[i]
        k = j / nk
        s0 = sep(u, 0) * 0.97
        # front wall (hidden in the pocket) → mound over the opening → back wall
        y = s0 * math.cos(math.pi * k)
        mound = (0.17 + 0.05 * math.sin(u * 7)) * math.sin(math.pi * k) * w_of(u) ** 0.6
        z = ztop(u) - 0.02 + mound + bump(Vector((u * 3, y * 3, 0)), 0.03, 4)
        return Vector((u * R * 0.98, y, z))

    def uv(i, j):
        return (0.02 + 0.46 * i / nu, 0.02 + 0.46 * j / nk)

    top = grid_surface(nu, nk, pos, uv)

    # walls down into the pocket so no gap shows between filling and crumb
    def wall(side):
        def wpos(i, j):
            u = us[i]
            return Vector((u * R * 0.98, side * sep(u, 0.25 * j) * 0.97, ztop(u) - 0.02 - 0.25 * j))

        return grid_surface(nu, 1, wpos, lambda i, j: (0.02 + 0.46 * i / nu, 0.02 + 0.2 * j))

    parts = [top, wall(1), flipped(wall(-1))]
    rnd = random.Random(9)
    # salad leaves hanging over the front and back edge
    for k in range(14):
        u = -0.8 + 1.6 * (k // 2) / 6 + rnd.uniform(-0.06, 0.06)
        side = 1 if k % 2 == 0 else -1
        lu = (LET[0] + rnd.uniform(0, 0.2), LET[1] + rnd.uniform(0, 0.2))
        parts.append(leaf(u * R, side * (sep(u, 0) + thick(u) * 0.6), ztop(u) + 0.05, rnd.uniform(-0.4, 0.4), -side * math.radians(rnd.uniform(30, 50)), (rnd.uniform(0.24, 0.32), rnd.uniform(0.18, 0.24)), lu, 0.13, 0.22))
    # tomato slices standing in the filling
    for k in range(4):
        u = -0.55 + 1.1 * k / 3
        parts.append(leaf(u * R, rnd.uniform(-0.08, 0.08), ztop(u) + 0.14, rnd.uniform(-0.3, 0.3), math.radians(rnd.uniform(-15, 15)), (0.26, 0.24), TOM, 0.02))
    # meat shavings on top
    for k in range(10):
        u = rnd.uniform(-0.75, 0.75)
        parts.append(leaf(u * R, rnd.uniform(-0.15, 0.15), ztop(u) + 0.15 * w_of(u) + 0.03, rnd.uniform(0, math.pi), math.radians(rnd.uniform(70, 88)), (0.26, 0.14), MEAT, 0.015, 0.3))
    v, f, u = merge(*parts)
    obj = make_object("KebapFilling", v, f, u, material("Filling", "filling.png", 0.55, 0.35))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for fc in bm.faces:
        fc.smooth = True
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def build_paper():
    nv, v0 = 10, 0.38
    us = [-1 + 2 * i / NU for i in range(NU + 1)]

    def pos(i, j):
        phi = j / (2 * nv)
        side, t = (1, phi * 2) if phi <= 0.5 else (-1, (1 - phi) * 2)
        u = us[i]
        v = v0 + (1 - v0) * t
        p = outer_point(u * 0.985, v, side)
        if j == 0 or j == 2 * nv:
            p.z += 0.03 * math.sin(u * 9)  # slightly uneven torn edge
        return Vector((p.x * 1.02, p.y * 1.12 + side * 0.02, p.z - 0.012))

    def uv(i, j):
        phi = j / (2 * nv)
        u = (us[i] + 1) / 2
        if phi <= 0.5:
            return (1 - u, 0.96 - phi * 2 * 0.62)  # front (+Y): seen from +Y, +X runs to the left
        return (u, 0.96 - (1 - phi) * 2 * 0.62)

    outer = grid_surface(NU, 2 * nv, pos, uv)
    iv, fi, ui = flipped(outer)
    inner = ([Vector((p.x * 0.995, p.y * 0.97, p.z + 0.004)) for p in iv], fi, ui)
    v, f, u = merge(outer, inner)
    obj = make_object("KebapPaper", v, f, u, material("Paper", "paper.png", 0.85, 0.15))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for fc in bm.faces:
        fc.smooth = True
    bm.to_mesh(obj.data)
    bm.free()
    return obj


# --------------------------------------------------------------------------- dürüm parts (roll: DuerumRolled, centre z = 0.39)
DR, DHALF, DZ = 0.39, 1.06, 0.39


def build_foil():
    nu, na = 16, 36
    x0, x1 = -DHALF - 0.04, -0.02

    def pos(i, j):
        t = i / nu
        a = j / na * math.tau
        x = x0 + (x1 - x0) * t
        r = DR + 0.035 + 0.015 * noise.noise(Vector((x * 6, math.cos(a) * 3, math.sin(a) * 3)))
        if i == nu:
            x += 0.05 * math.sin(a * 5)  # crumpled open edge
        return Vector((x, math.cos(a) * r, DZ + math.sin(a) * r))

    def uv(i, j):
        return (i / nu, j / na)

    tube = grid_surface(nu, na, pos, uv)
    # closed, slightly twisted cap at the back end
    cap_v = [Vector((x0 - 0.12, 0, DZ))] + [pos(0, j) for j in range(na)]
    cap_f = [(0, 1 + (j + 1) % na, 1 + j) for j in range(na)]
    cap_u = [((0.5, 0.5), (0.5 + 0.4 * math.cos((j + 1) / na * math.tau), 0.5), (0.5, 0.5 + 0.4 * math.sin(j / na * math.tau))) for j in range(na)]
    v, f, u = merge(tube, (cap_v, cap_f, cap_u))
    iv, fi, ui = flipped((v, f, u))
    inner = ([Vector((p.x, p.y * 0.97, DZ + (p.z - DZ) * 0.97)) for p in iv], fi, ui)
    v, f, u = merge((v, f, u), inner)
    obj = make_object("DuerumFoil", v, f, u, material("Foil", "foil.png", 0.25, 0.8))
    return obj


def build_duerum_end():
    nr, na = 5, 28
    rmax = DR * 0.82

    def pos(i, j):
        r = i / nr * rmax
        a = j / na * math.tau
        bulge = 0.12 * (1 - (r / rmax) ** 2) + bump(Vector((r * math.cos(a) * 4, r * math.sin(a) * 4, 0)), 0.02, 5)
        return Vector((DHALF - 0.06 + bulge, math.cos(a) * r, DZ + math.sin(a) * r))

    def uv(i, j):
        a = j / na * math.tau
        r = i / nr * 0.21
        return (0.25 + math.cos(a) * r, 0.25 + math.sin(a) * r)

    disc = grid_surface(na, nr, lambda j, i: pos(i, j), lambda j, i: uv(i, j), closed_u=True)
    parts = [disc]
    rnd = random.Random(5)
    for k in range(5):
        a = k / 5 * math.tau + 0.4
        parts.append(leaf(DHALF + 0.02, math.cos(a) * rmax * 0.8, DZ + math.sin(a) * rmax * 0.8, math.pi / 2, math.radians(rnd.uniform(50, 80)), (0.22, 0.18), LET, 0.06))
    v, f, u = merge(*parts)
    return finish(make_object("DuerumEnd", v, f, u, material("Filling", "filling.png", 0.55, 0.35)))


# --------------------------------------------------------------------------- closed styrofoam box
def build_box():
    bpy.ops.mesh.primitive_cube_add(size=1)
    base = bpy.context.active_object
    base.name = "BoxClosed"
    bm = bmesh.new()
    bm.from_mesh(base.data)
    for vv in bm.verts:
        x, y, z = vv.co
        top = z > 0
        # tapered tray: wider at the top seam
        sx = 1.9 if top else 1.72
        sy = 1.4 if top else 1.24
        vv.co = Vector((x * sx, y * sy, 0.5 if top else 0.0))
    bm.to_mesh(base.data)
    bm.free()
    bev = base.modifiers.new("b", "BEVEL")
    bev.width, bev.segments = 0.08, 3
    bpy.ops.object.modifier_apply(modifier="b")
    # lid: slightly larger, domed
    bpy.ops.mesh.primitive_cube_add(size=1)
    lid = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(lid.data)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=4, use_grid_fill=True)
    for vv in bm.verts:
        x, y, z = vv.co
        top = z > 0
        dome = 0.07 * (1 - (2 * x) ** 2) * (1 - (2 * y) ** 2) if top else 0
        vv.co = Vector((x * (1.96 if not top else 1.84), y * (1.46 if not top else 1.36), (0.5 if not top else 0.66 + dome)))
    bm.to_mesh(lid.data)
    bm.free()
    bev = lid.modifiers.new("b", "BEVEL")
    bev.width, bev.segments = 0.05, 3
    bpy.ops.object.modifier_apply(modifier="b")
    # front clasp tab
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.74, 0.5))
    tab = bpy.context.active_object
    tab.scale = (0.3, 0.06, 0.12)
    bpy.ops.object.transform_apply(scale=True)
    for o in (base, lid, tab):
        o.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    mat = bpy.data.materials.new("Styro")
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.92, 0.92, 0.9, 1)
    b.inputs["Roughness"].default_value = 0.8
    base.data.materials.clear()
    base.data.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(base.data)
    for fc in bm.faces:
        fc.smooth = False
    bm.to_mesh(base.data)
    bm.free()
    return base


# --------------------------------------------------------------------------- build + report
PRODUCTS = [build_bread(), build_filling(), build_paper(), build_foil(), build_duerum_end(), build_box()]
tris = {}
for o in PRODUCTS:
    o.data.calc_loop_triangles()
    tris[o.name] = len(o.data.loop_triangles)
print("triangles:", tris, "total", sum(tris.values()))
# bounding-box centre and size in Roblox coordinates (X = -bx, Y = bz, Z = by)
for o in PRODUCTS:
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c, s = (lo + hi) / 2, hi - lo
    print("ROBLOX %-13s centre (%.3f, %.3f, %.3f) size (%.3f, %.3f, %.3f)" % (o.name, -c.x, c.z, c.y, s.x, s.z, s.y))

# --------------------------------------------------------------------------- export
bpy.ops.object.select_all(action="DESELECT")
for o in PRODUCTS:
    o.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "kebap_finished.fbx"),
    use_selection=True,
    object_types={"MESH"},
    path_mode="COPY",
    embed_textures=True,
    mesh_smooth_type="FACE",
    apply_unit_scale=True,
    bake_space_transform=False,
    axis_forward="-Z",
    axis_up="Y",
)
print("exported", os.path.join(OUT, "kebap_finished.fbx"))

if os.environ.get("NO_RENDER"):
    raise SystemExit(0)

# --------------------------------------------------------------------------- preview: kebab, dürüm, box
prev = []


def place(src, offset):
    o = src.copy()
    o.data = src.data
    o.location = src.location + Vector(offset)
    scene.collection.objects.link(o)
    o.hide_render = False
    prev.append(o)


for o in PRODUCTS:
    o.hide_render = True
for o in PRODUCTS[:3]:
    place(o, (0, 0, 0))
roll = _g["duerum_rolled_obj"]
roll.location = Vector((0, 0, 0))
for o in (roll, PRODUCTS[3], PRODUCTS[4]):
    place(o, (2.6, 0.6, 0))
place(PRODUCTS[5], (-2.6, 0.6, 0))
bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, -0.005))
fl = bpy.context.active_object
fm = bpy.data.materials.new("Floor")
fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.2, 0.13, 1)
fl.data.materials.append(fm)
for loc, e in (((3, -4, 5), 700), ((-4, 2, 3), 260), ((0, 4, 2), 120)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    lt = bpy.context.active_object
    lt.data.energy, lt.data.size = e, 4
    lt.rotation_euler = (Vector((0, 0, 0.4)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.45, 0.47, 1)
scene.world = world
bpy.ops.object.camera_add(location=(1.2, -5.2, 3.4))
cam = bpy.context.active_object
cam.data.lens = 38
cam.rotation_euler = (Vector((0, 0.3, 0.45)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1200, 650
scene.render.filepath = os.path.join(OUT, os.environ.get("PREVIEW", "preview_finished.png"))
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)
