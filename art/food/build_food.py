"""Builds the food models for Kebap Usta in Blender (bpy) and exports one FBX for Roblox Studio.

Every ingredient is its own low-poly mesh with UVs and a baked-in albedo texture from ./tex
(see make_textures.py). Units are Roblox studs (1 Blender unit = 1 stud), Z is up in Blender and
the FBX exporter converts to Roblox's Y-up.

    python3 make_textures.py && python3 build_food.py
Outputs: out/kebap_food.fbx (+ textures copied next to it) and out/preview.png
"""
import math
import os
import random

import bpy  # must come first: it provides bmesh/mathutils
import bmesh
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# --------------------------------------------------------------------------- helpers
_materials = {}


def material(name, tex_file, roughness=0.6, specular=0.3, sss=0.0):
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    img = bpy.data.images.load(os.path.join(TEX, tex_file))
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if sss > 0 and "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = sss
        bsdf.inputs["Subsurface Radius"].default_value = (0.08, 0.04, 0.02)
    _materials[name] = mat
    return mat


def make_object(name, verts, faces, uvs, mat, smooth=True):
    """verts: list of Vector, faces: list of index tuples, uvs: per-face list of (u,v) tuples."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bv = [bm.verts.new(v) for v in verts]
    bm.verts.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f, fuv in zip(faces, uvs):
        try:
            face = bm.faces.new([bv[i] for i in f])
        except ValueError:
            continue
        face.smooth = smooth
        for loop, uv in zip(face.loops, fuv):
            loop[uv_layer].uv = uv
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def grid_surface(nu, nv, pos_fn, uv_fn, closed_u=False):
    """Quad grid; pos_fn(i,j)->Vector, uv_fn(i,j)->(u,v). Returns verts, faces, uvs."""
    verts, idx = [], {}
    cols = nu if closed_u else nu + 1
    for j in range(nv + 1):
        for i in range(cols):
            idx[(i, j)] = len(verts)
            verts.append(pos_fn(i, j))
    faces, uvs = [], []
    for j in range(nv):
        for i in range(nu):
            i2 = (i + 1) % cols if closed_u else i + 1
            f = (idx[(i, j)], idx[(i2, j)], idx[(i2, j + 1)], idx[(i, j + 1)])
            faces.append(f)
            uvs.append((uv_fn(i, j), uv_fn(i + 1, j), uv_fn(i + 1, j + 1), uv_fn(i, j + 1)))
    return verts, faces, uvs


def merge(*parts):
    """Concatenate several (verts, faces, uvs) blocks."""
    V, F, U = [], [], []
    for v, f, u in parts:
        off = len(V)
        V += v
        F += [tuple(i + off for i in face) for face in f]
        U += u
    return V, F, U


def flipped(block, offset=Vector((0, 0, 0))):
    v, f, u = block
    return [p + offset for p in v], [tuple(reversed(face)) for face in f], [tuple(reversed(x)) for x in u]


def bump(p, amp, freq, seed=0.0):
    return amp * noise.noise(Vector((p.x * freq + seed, p.y * freq, p.z * freq)))


# --------------------------------------------------------------------------- bread (kebab pocket)
# atlas: crust u 0..0.5 | crumb u 0.5..1, v 0..0.5 | sesame u 0.5..1, v 0.5..1
BREAD_LX, BREAD_LY = 0.97, 0.62  # half length / half depth


def bread_half(name, top):
    nu, nv = 40, 10
    hz = 0.36 if top else 0.3

    def shell(scale_xy, scale_z, crust):
        def pos(i, j):
            a = i / nu * math.tau
            t = j / nv  # 0 = rim, 1 = pole
            el = t * math.pi / 2
            x = math.cos(a) * math.cos(el) * BREAD_LX * scale_xy
            y = math.sin(a) * math.cos(el) * BREAD_LY * scale_xy
            z = math.sin(el) * hz * scale_z
            p = Vector((x, y, z if top else -z))
            if crust:
                n = Vector((x / BREAD_LX, y / BREAD_LY, (z / hz) * (1 if top else -1))).normalized()
                p += n * (bump(p, 0.022, 3.2) + bump(p, 0.008, 11))
            return p

        def uv(i, j):
            a = i / nu * math.tau
            t = j / nv
            rr = 1 - t
            if crust:
                return (0.25 + math.cos(a) * rr * 0.24, 0.5 + math.sin(a) * rr * 0.48)
            return (0.75 + math.cos(a) * rr * 0.23, 0.25 + math.sin(a) * rr * 0.23)

        return grid_surface(nu, nv, pos, uv, closed_u=True)

    outer = shell(1.0, 1.0, True)
    inner = shell(0.9, 0.72, False)
    if top:
        # outer surface faces outward when the dome is above the rim
        inner = flipped(inner)
    else:
        outer = flipped(outer)
    # rim band joining outer and inner rim loops (both start at index 0..nu-1)
    ov, _, _ = outer
    iv, _, _ = inner
    rim_v = ov[:nu] + iv[:nu]
    rim_f, rim_u = [], []
    for i in range(nu):
        i2 = (i + 1) % nu
        f = (i, i2, nu + i2, nu + i) if top else (i, nu + i, nu + i2, i2)
        rim_f.append(f)
        rim_u.append(((0.6, 0.1), (0.62, 0.1), (0.62, 0.12), (0.6, 0.12)))
    parts = [outer, inner, (rim_v, rim_f, rim_u)]
    if top:
        # sesame seeds scattered over the upper dome
        for _ in range(42):
            a = random.random() * math.tau
            el = math.radians(random.uniform(28, 82))
            x = math.cos(a) * math.cos(el) * BREAD_LX
            y = math.sin(a) * math.cos(el) * BREAD_LY
            z = math.sin(el) * hz + 0.012
            n = Vector((x / BREAD_LX ** 2, y / BREAD_LY ** 2, z / hz ** 2)).normalized()
            rot = n.to_track_quat("Z", "Y").to_matrix() @ Matrix.Rotation(random.random() * math.tau, 3, "Z")
            seed_v, seed_f, seed_u = [], [], []
            seg, ring = 6, 3
            for rj in range(ring + 1):
                phi = rj / ring * math.pi
                for si in range(seg):
                    th = si / seg * math.tau
                    local = Vector((math.cos(th) * math.sin(phi) * 0.034, math.sin(th) * math.sin(phi) * 0.019, math.cos(phi) * 0.011))
                    seed_v.append(Vector((x, y, z)) + rot @ local)
            for rj in range(ring):
                for si in range(seg):
                    s2 = (si + 1) % seg
                    seed_f.append((rj * seg + si, rj * seg + s2, (rj + 1) * seg + s2, (rj + 1) * seg + si))
                    seed_u.append(((0.7, 0.7), (0.72, 0.7), (0.72, 0.72), (0.7, 0.72)))
            parts.append((seed_v, seed_f, seed_u))
    v, f, u = merge(*parts)
    return make_object(name, v, f, u, material("Bread", "bread_atlas.png", 0.75, 0.25))


bread_bottom = bread_half("BreadBottom", top=False)
bread_top = bread_half("BreadTop", top=True)

# --------------------------------------------------------------------------- dürüm flatbread (flat + rolled)
R_FLAT = 1.15


def duerum_flat():
    rings, seg = 9, 48

    def pos(i, j):
        a = i / seg * math.tau
        r = j / rings * R_FLAT * (1 + 0.03 * math.sin(a * 5 + 1.3))
        p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        p.z = 0.015 * math.sin(r * 9 + a * 2) * (r / R_FLAT) + bump(p, 0.012, 2.5)
        return p

    def uv(i, j):
        a = i / seg * math.tau
        r = j / rings * 0.48
        return (0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r)

    top = grid_surface(seg, rings, pos, uv, closed_u=True)
    bottom = flipped(top, Vector((0, 0, -0.022)))
    v, f, u = merge(top, bottom)
    return make_object("DuerumFlat", v, f, u, material("Duerum", "duerum.png", 0.8, 0.2))


def duerum_rolled():
    turns = 2.4 * math.pi
    nu, nv = 56, 14
    r0, r1, half = 0.23, 0.39, 1.06

    def radius(th, x):
        return r0 + (r1 - r0) * th / turns + 0.006 * math.sin(x * 26 + th * 3)

    def pos(i, j):
        th = i / nu * turns
        x = (j / nv * 2 - 1) * half
        r = radius(th, x)
        return Vector((x, math.cos(th) * r, math.sin(th) * r + r1))

    def uv(i, j):
        return (i / nu, j / nv)

    outer = grid_surface(nu, nv, pos, uv)
    inner = flipped(outer, Vector((0, 0, 0)))
    # push the back side 0.02 inward so the sheet has a little thickness
    iv, fi, ui = inner
    iv = [Vector((p.x, p.y * 0.95, (p.z - r1) * 0.95 + r1)) for p in iv]
    v, f, u = merge(outer, (iv, fi, ui))
    return make_object("DuerumRolled", v, f, u, material("Duerum", "duerum.png", 0.8, 0.2))


duerum_flat_obj = duerum_flat()
duerum_rolled_obj = duerum_rolled()

# --------------------------------------------------------------------------- vegetables


def two_sided(block, gap=0.006):
    v, f, u = block
    back = flipped(block)
    bv = [p - Vector((0, 0, gap)) for p in back[0]]
    return merge(block, (bv, back[1], back[2]))


def lettuce():
    nu, nv, W, L = 10, 14, 0.36, 0.44

    def pos(i, j):
        s = i / nu - 0.5
        t = j / nv
        w = math.sin(math.pi * (0.08 + t * 0.92)) ** 0.75 * W * (1 + 0.12 * math.sin(t * 23))
        x = s * w
        y = (t - 0.5) * L
        z = 0.05 * math.sin(t * 17 + s * 5) * abs(s) * 2 + 0.09 * s * s + bump(Vector((x, y, 0)), 0.018, 9)
        return Vector((x, y, z))

    def uv(i, j):
        return (i / nu, j / nv)

    v, f, u = two_sided(grid_surface(nu, nv, pos, uv))
    return make_object("Lettuce", v, f, u, material("Lettuce", "lettuce.png", 0.45, 0.4, 0.15))


def disc_slice(name, radius, height, tex, rough, seg=24, wobble=0.04):
    rings = 3
    blocks = []
    for side in (1, -1):
        def pos(i, j, side=side):
            a = i / seg * math.tau
            r = j / rings * radius * (1 + wobble * math.sin(a * 3 + 0.7))
            return Vector((math.cos(a) * r, math.sin(a) * r, side * height / 2))

        def uv(i, j):
            a = i / seg * math.tau
            r = j / rings * 0.49
            return (0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r)

        b = grid_surface(seg, rings, pos, uv, closed_u=True)
        blocks.append(b if side == 1 else flipped(b))
    # rim band
    def rpos(i, j):
        a = i / seg * math.tau
        r = radius * (1 + wobble * math.sin(a * 3 + 0.7))
        return Vector((math.cos(a) * r, math.sin(a) * r, (j - 0.5) * height))

    blocks.append(grid_surface(seg, 1, rpos, lambda i, j: (0.5, 0.015), closed_u=True))
    v, f, u = merge(*blocks)
    return make_object(name, v, f, u, material(name, tex, rough, 0.45, 0.1))


def onion_ring():
    seg, ring = 28, 6
    R, rw, rh = 0.12, 0.022, 0.016

    def pos(i, j):
        a = i / seg * math.tau
        b = j / ring * math.tau
        rr = R * (1 + 0.05 * math.sin(a * 2)) + math.cos(b) * rw
        return Vector((math.cos(a) * rr, math.sin(a) * rr * 0.88, math.sin(b) * rh))

    def uv(i, j):
        return (i / seg, 0.5 + 0.45 * math.cos(j / ring * math.tau))

    # closed in both directions: build manually
    verts = [pos(i, j) for j in range(ring) for i in range(seg)]
    faces, uvs = [], []
    for j in range(ring):
        for i in range(seg):
            i2, j2 = (i + 1) % seg, (j + 1) % ring
            faces.append((j * seg + i, j * seg + i2, j2 * seg + i2, j2 * seg + i))
            uvs.append((uv(i, j), uv(i + 1, j), uv(i + 1, j + 1), uv(i, j + 1)))
    return make_object("Onion", verts, faces, uvs, material("Onion", "onion.png", 0.35, 0.5, 0.2))


def strip(name, length, width, curl, tex, rough, nv=12):
    def pos(i, j):
        s = i - 0.5
        t = j / nv
        ang = (t - 0.5) * curl
        rad = length / max(curl, 0.01)
        y = math.sin(ang) * rad
        z = (1 - math.cos(ang)) * rad * 0.6 + 0.01 * math.sin(t * 13)
        x = s * width * (1 + 0.15 * math.sin(t * 9 + i))
        return Vector((x + 0.02 * math.sin(t * 7), y, z))

    v, f, u = two_sided(grid_surface(1, nv, pos, lambda i, j: (i, j / nv)), 0.008)
    return make_object(name, v, f, u, material(name, tex, rough, 0.35))


def meat_shaving():
    nu, nv, W, L = 6, 10, 0.2, 0.42

    def pos(i, j):
        s = i / nu - 0.5
        t = j / nv
        x = s * W * (1 + 0.25 * math.sin(t * 11 + s * 4))
        ang = (t - 0.5) * 2.2
        rad = L / 2.2
        y = math.sin(ang) * rad
        z = (1 - math.cos(ang)) * rad * 0.5 + 0.03 * math.sin(s * 6 + t * 5) + bump(Vector((x, y, 0)), 0.012, 14)
        return Vector((x, y, z))

    v, f, u = two_sided(grid_surface(nu, nv, pos, lambda i, j: (i / nu, j / nv)), 0.022)
    return make_object("MeatShaving", v, f, u, material("Meat", "meat.png", 0.55, 0.35))


def sauce_drizzle():
    n, seg, rad = 64, 6, 0.028
    path = []
    for k in range(n + 1):
        t = k / n
        x = (t - 0.5) * 1.25
        y = 0.16 * math.sin(t * math.tau * 3.5)
        z = 0.012 * math.sin(t * 31)
        path.append(Vector((x, y, z)))
    verts, faces, uvs = [], [], []
    for k, p in enumerate(path):
        tangent = (path[min(k + 1, n)] - path[max(k - 1, 0)]).normalized()
        side = tangent.cross(Vector((0, 0, 1))).normalized()
        up = side.cross(tangent).normalized()
        r = rad * (0.75 + 0.25 * math.sin(k * 0.9)) * (0.4 if k in (0, n) else 1)
        for s in range(seg):
            a = s / seg * math.tau
            verts.append(p + side * math.cos(a) * r + up * math.sin(a) * r * 0.65)
    for k in range(n):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append((k * seg + s, k * seg + s2, (k + 1) * seg + s2, (k + 1) * seg + s))
            uvs.append(((k / n, s / seg), (k / n, (s + 1) / seg), ((k + 1) / n, (s + 1) / seg), ((k + 1) / n, s / seg)))
    return make_object("Sauce", verts, faces, uvs, material("Sauce", "sauce.png", 0.15, 0.6))


lettuce_obj = lettuce()
tomato_obj = disc_slice("Tomato", 0.145, 0.04, "tomato.png", 0.3)
cucumber_obj = disc_slice("Cucumber", 0.115, 0.035, "cucumber.png", 0.35, wobble=0.02)
onion_obj = onion_ring()
cabbage_obj = strip("Cabbage", 0.34, 0.035, 2.4, "cabbage.png", 0.45)
cheese_obj = strip("Cheese", 0.2, 0.025, 1.6, "cheese.png", 0.6, nv=8)
meat_obj = meat_shaving()
sauce_obj = sauce_drizzle()

FOOD = [bread_bottom, bread_top, duerum_flat_obj, duerum_rolled_obj, lettuce_obj, tomato_obj, cucumber_obj, onion_obj, cabbage_obj, cheese_obj, meat_obj, sauce_obj]

# stats
tris = {}
for o in FOOD:
    me = o.data
    me.calc_loop_triangles()
    tris[o.name] = len(me.loop_triangles)
print("triangles:", tris, "total", sum(tris.values()))

# --------------------------------------------------------------------------- export (each object centred at its own origin, laid out in a row)
for o in FOOD:
    bpy.context.view_layer.objects.active = o
for k, o in enumerate(FOOD):
    o.location = Vector(((k % 6) * 2.6, (k // 6) * 2.6, 0))
bpy.ops.object.select_all(action="DESELECT")
for o in FOOD:
    o.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "kebap_food.fbx"),
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
print("exported", os.path.join(OUT, "kebap_food.fbx"))

# --------------------------------------------------------------------------- preview render: an assembled kebap and dürüm
if os.environ.get("NO_RENDER"):
    raise SystemExit(0)
for o in FOOD:
    o.hide_render = True
prev = bpy.data.collections.new("Preview")
scene.collection.children.link(prev)


def place(src, loc, rot=(0, 0, 0), scale=1.0):
    o = src.copy()
    o.data = src.data
    o.hide_render = False
    o.location = Vector(loc)
    o.rotation_euler = rot
    o.scale = (scale, scale, scale)
    prev.objects.link(o)
    return o


# kebab: bottom half, meat, veg, sauce, tilted top
place(bread_bottom, (0, 0, 0.3))
for k in range(9):
    a = k / 9 * math.tau
    place(meat_obj, (math.cos(a) * 0.45, math.sin(a) * 0.22, 0.34 + (k % 3) * 0.03), (0.2 * math.sin(k), 0.2, a))
for k in range(5):
    place(lettuce_obj, (-0.5 + k * 0.25, 0.1 * math.sin(k * 2), 0.43), (0.5, 0.1 * k, 1.2 * k))
for k in range(4):
    place(tomato_obj, (-0.45 + k * 0.3, -0.18 + 0.05 * k, 0.47), (0.35, 0.2, 0))
for k in range(4):
    place(onion_obj, (-0.4 + k * 0.28, 0.2, 0.5), (0.4, 0, k))
for k in range(6):
    place(cabbage_obj, (-0.5 + k * 0.2, 0.0, 0.52), (0.3, 0, 0.6 * k))
place(sauce_obj, (0, 0.0, 0.56), (0, 0, 0.1), 0.85)
place(bread_top, (0, -0.08, 0.66), (math.radians(-28), 0, 0))
# dürüm next to it
place(duerum_rolled_obj, (2.2, 0.2, -0.0), (0, 0, math.radians(20)))
place(duerum_flat_obj, (-2.3, 0.4, 0.02), (0, 0, 0))
for k in range(5):
    place(meat_obj, (-2.5 + k * 0.15, 0.3 + 0.08 * k, 0.06), (0, 0, k))
for k in range(3):
    place(tomato_obj, (-2.0, 0.6 - k * 0.3, 0.1), (0, 0, 0))
    place(cucumber_obj, (-2.6, 0.75 - k * 0.3, 0.1), (0, 0, 0))

# floor (wooden board), lights, camera
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, -0.03))
board = bpy.context.active_object
bm = bpy.data.materials.new("Board")
bm.use_nodes = True
b = bm.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.32, 0.2, 0.12, 1)
b.inputs["Roughness"].default_value = 0.7
board.data.materials.append(bm)
bpy.ops.object.light_add(type="AREA", location=(2.5, -3, 4))
key = bpy.context.active_object
key.data.energy = 600
key.data.size = 3
bpy.ops.object.light_add(type="AREA", location=(-3, 2, 3))
bpy.context.active_object.data.energy = 220
bpy.ops.object.light_add(type="POINT", location=(0, 3, 1))
bpy.context.active_object.data.energy = 60
world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.1, 0.09, 1)
scene.world = world
bpy.ops.object.camera_add(location=(0.4, -4.6, 2.6))
cam = bpy.context.active_object
cam.data.lens = 40
direction = Vector((0, 0.1, 0.4)) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1200
scene.render.resolution_y = 700
scene.render.filepath = os.path.join(OUT, "preview.png")
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)
