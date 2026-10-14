"""Logistics models for Kebap Usta: delivery van, cardboard box, veg crate, drinks crate, meat
cooler box and a pallet-rack shelf. Units are studs (Blender Z up -> Roblox Y up via FBX).

    python3 make_textures.py && python3 build_logistics.py      (NO_RENDER=1 skips the preview)
Outputs out/kebap_logistics.fbx (embedded textures) and out/preview.png
"""
import math
import os

import bpy  # must come before bmesh
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
_mats = {}


def material(tex_file, rough=0.6):
    if tex_file in _mats:
        return _mats[tex_file]
    m = bpy.data.materials.new(tex_file.split(".")[0])
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(TEX, tex_file))
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    _mats[tex_file] = m
    return m


class Mesh:
    """Accumulates geometry with UVs mapped into atlas regions (u0, v0, u1, v1)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def quad(self, pts, uvs, smooth=False):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.smooth = smooth
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def box(self, c, s, region=(0, 0, 1, 1), side_region=None, top_region=None, open_top=False, open_bottom=False):
        """axis-aligned box; each face maps its two extents onto the region"""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        u0, v0, u1, v1 = region

        def r(reg, a, b):
            q0, w0, q1, w1 = reg
            return (q0 + (q1 - q0) * a, w0 + (w1 - w0) * b)

        P = lambda x, y, z: Vector((cx + x * hx, cy + y * hy, cz + z * hz))
        faces = [
            ((P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)), region),  # front (-Y)
            ((P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)), region),  # back
            ((P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)), side_region or region),  # +X
            ((P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)), side_region or region),  # -X
        ]
        if not open_top:
            faces.append(((P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)), top_region or region))
        if not open_bottom:
            faces.append(((P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1)), top_region or region))
        for pts, reg in faces:
            self.quad(pts, [r(reg, 0, 0), r(reg, 1, 0), r(reg, 1, 1), r(reg, 0, 1)])

    def cylinder(self, c, radius, height, axis="z", seg=16, region=(0, 0, 1, 1), cap_region=None, taper=1.0):
        u0, v0, u1, v1 = region
        ring_a, ring_b = [], []
        for i in range(seg + 1):
            a = 2 * math.pi * i / seg
            x, y = math.cos(a) * radius, math.sin(a) * radius
            pa, pb = Vector((x, y, -height / 2)), Vector((x * taper, y * taper, height / 2))
            if axis == "y":
                pa, pb = Vector((pa.x, pa.z, pa.y)), Vector((pb.x, pb.z, pb.y))
            ring_a.append(pa + Vector(c))
            ring_b.append(pb + Vector(c))
        for i in range(seg):
            ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
            self.quad((ring_a[i], ring_a[i + 1], ring_b[i + 1], ring_b[i]), [(ua, v0), (ub, v0), (ub, v1), (ua, v1)], smooth=True)
        cr = cap_region or region
        cu, cv = (cr[0] + cr[2]) / 2, (cr[1] + cr[3]) / 2
        for ring, flip in ((ring_b, False), (ring_a, True)):
            ctr = self.bm.verts.new(sum(ring[:-1], Vector()) / seg)
            for i in range(seg):
                vs = [ctr, self.bm.verts.new(ring[i]), self.bm.verts.new(ring[i + 1])]
                if flip:
                    vs = [vs[0], vs[2], vs[1]]
                f = self.bm.faces.new(vs)
                for loop in f.loops:
                    p = loop.vert.co - ctr.co
                    loop[self.uv].uv = (cu + p.x / radius * 0.05, cv + p.y / radius * 0.05)

    def sphere(self, c, r, sx=1, sy=1, sz=1, region=(0, 0, 1, 1), seg=10, rings=6):
        u0, v0, u1, v1 = region
        grid = []
        for j in range(rings + 1):
            th = math.pi * j / rings
            row = []
            for i in range(seg + 1):
                ph = 2 * math.pi * i / seg
                row.append(Vector((c[0] + r * sx * math.sin(th) * math.cos(ph), c[1] + r * sy * math.sin(th) * math.sin(ph), c[2] + r * sz * math.cos(th))))
            grid.append(row)
        for j in range(rings):
            for i in range(seg):
                a, b = grid[j][i], grid[j][i + 1]
                cc, d = grid[j + 1][i + 1], grid[j + 1][i]
                uv = [(u0 + (u1 - u0) * i / seg, v1 - (v1 - v0) * j / rings), (u0 + (u1 - u0) * (i + 1) / seg, v1 - (v1 - v0) * j / rings),
                      (u0 + (u1 - u0) * (i + 1) / seg, v1 - (v1 - v0) * (j + 1) / rings), (u0 + (u1 - u0) * i / seg, v1 - (v1 - v0) * (j + 1) / rings)]
                try:
                    self.quad((d, cc, b, a), [uv[3], uv[2], uv[1], uv[0]], smooth=True)
                except ValueError:
                    pass

    def finish(self, name, tex, rough=0.6, bevel=0.0):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-4)
        if bevel > 0:
            edges = [e for e in self.bm.edges if e.calc_face_angle(0) > 1.2]
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, affect="EDGES", profile=0.5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        o = bpy.data.objects.new(name, me)
        scene.collection.objects.link(o)
        o.data.materials.append(material(tex, rough))
        return o


OBJS = []

# ---------------------------------------------------------------- cardboard box 2 x 1.6 x 1.4
m = Mesh()
m.box((0, 0, 0.7), (2, 1.6, 1.4), region=(0, 0, 1, 1), side_region=(0, 0, 0.38, 1))
OBJS.append(m.finish("Box_cardboard", "cardboard.png", 0.85, bevel=0.03))

# ---------------------------------------------------------------- veg crate (open) with produce
m = Mesh()
CR = (0, 0, 0.5, 1)
W, D, H, T = 2.0, 1.6, 1.05, 0.08
m.box((0, -D / 2 + T / 2, H / 2), (W, T, H), CR)
m.box((0, D / 2 - T / 2, H / 2), (W, T, H), CR)
m.box((-W / 2 + T / 2, 0, H / 2), (T, D - 2 * T, H), CR)
m.box((W / 2 - T / 2, 0, H / 2), (T, D - 2 * T, H), CR)
m.box((0, 0, 0.05), (W - 2 * T, D - 2 * T, 0.1), CR)
for x in (-0.55, 0.0, 0.55):  # lettuce heads
    for y in (-0.35, 0.35):
        m.sphere((x, y, H - 0.15), 0.36, 1, 1, 0.8, region=(0.5, 0.5, 1, 1))
for x, y in ((-0.3, 0), (0.3, 0.05), (0.75, -0.4), (-0.78, 0.42)):  # tomatoes on top
    m.sphere((x, y, H + 0.12), 0.17, 1, 1, 0.9, region=(0.5, 0, 1, 0.5), seg=8, rings=5)
OBJS.append(m.finish("Box_veg", "veg_crate.png", 0.55))

# ---------------------------------------------------------------- drinks crate with 12 bottles
m = Mesh()
RD = (0, 0, 0.5, 1)
H = 0.85
m.box((0, -D / 2 + T / 2, H / 2), (W, T, H), RD)
m.box((0, D / 2 - T / 2, H / 2), (W, T, H), RD)
m.box((-W / 2 + T / 2, 0, H / 2), (T, D - 2 * T, H), RD)
m.box((W / 2 - T / 2, 0, H / 2), (T, D - 2 * T, H), RD)
m.box((0, 0, 0.05), (W - 2 * T, D - 2 * T, 0.1), RD)
for i in (-1, 0, 1):  # dividers
    m.box((i * 0.45, 0, H * 0.6), (0.04, D - 2 * T, H * 0.8), RD)
m.box((0, 0, H * 0.6), (W - 2 * T, 0.04, H * 0.8), RD)
for ix in range(4):
    for iy in range(3):
        x, y = -0.67 + ix * 0.45, -0.48 + iy * 0.48
        m.cylinder((x, y, 0.62), 0.17, 1.0, region=(0.5, 0.25, 1, 0.75))
        m.cylinder((x, y, 1.22), 0.17, 0.22, region=(0.5, 0.25, 1, 0.75), taper=0.45)
        m.cylinder((x, y, 1.38), 0.085, 0.1, region=(0.5, 0, 1, 0.25))
OBJS.append(m.finish("Box_drink", "drink_crate.png", 0.35))

# ---------------------------------------------------------------- meat cooler box
m = Mesh()
m.box((0, 0, 0.55), (2, 1.6, 1.1), region=(0, 0.27, 0.5, 1))
m.box((0, -0.805, 0.45), (1.6, 0.02, 0.22), region=(0, 0.02, 0.5, 0.23))  # red band on the front
m.box((0, 0, 1.2), (2.08, 1.68, 0.2), region=(0.5, 0, 1, 1))  # lid
m.box((0, 0, 1.33), (0.9, 0.3, 0.08), region=(0.5, 0, 1, 1))  # lid handle
OBJS.append(m.finish("Box_meat", "meat_box.png", 0.8, bevel=0.025))

# ---------------------------------------------------------------- pallet rack shelf 5 x 1.8 x 8.8
m = Mesh()
ORANGE, STEEL = (0, 0, 0.5, 1), (0.5, 0, 1, 1)
for x in (-2.44, 2.44):
    for y in (-0.82, 0.82):
        m.box((x, y, 4.4), (0.12, 0.14, 8.8), ORANGE)
    for k in range(6):  # side bracing
        z = 0.5 + k * 1.4
        m.box((x, 0, z), (0.06, 1.6, 0.06), ORANGE)
for zt in (0.6, 2.9, 5.2, 7.5):
    for y in (-0.82, 0.82):
        m.box((0, y, zt - 0.09), (4.76, 0.08, 0.18), ORANGE)
    m.box((0, 0, zt - 0.02), (4.76, 1.56, 0.04), STEEL)  # deck
    for k in range(9):  # wire ribs under the deck
        m.box((-2.2 + k * 0.55, 0, zt - 0.07), (0.03, 1.56, 0.06), STEEL)
OBJS.append(m.finish("Shelf", "shelf.png", 0.45))

# ---------------------------------------------------------------- delivery van (13 long, +X = front)
PAINT = (0, 0, 1, 1)
L0, L1, Wv, Z0 = -6.5, 3.2, 6.0, 0.9


def side_uv(p0, p1):
    return PAINT


body = Mesh()
# cargo box: side faces map z onto the paint texture so the stripe runs along the van
body.box((( L0 + L1) / 2, 0, (Z0 + 7.0) / 2), (L1 - L0, Wv, 7.0 - Z0), PAINT, side_region=(0.4, 0.05, 0.6, 0.95), top_region=(0.1, 0.0, 0.3, 0.2))
body.box((4.4, 0, (Z0 + 5.4) / 2), (2.4, Wv - 0.1, 5.4 - Z0), PAINT, top_region=(0.1, 0.0, 0.3, 0.2))  # cab
body.box((6.0, 0, (Z0 + 3.2) / 2), (0.9, Wv - 0.2, 3.2 - Z0), PAINT, top_region=(0.1, 0.0, 0.3, 0.2))  # nose
# cab roof fairing up to the cargo box
body.box((3.9, 0, 6.2), (1.4, Wv - 0.1, 1.6), PAINT, top_region=(0.1, 0.0, 0.3, 0.2))
van_body = body.finish("Van_Body", "van_paint.png", 0.35, bevel=0.12)

glass = Mesh()
# windscreen (slanted), side windows of the cab
p = [Vector((5.62, -2.75, 3.25)), Vector((5.62, 2.75, 3.25)), Vector((4.9, 2.75, 5.25)), Vector((4.9, -2.75, 5.25))]
glass.quad(p, [(0, 0), (1, 0), (1, 1), (0, 1)])
glass.quad(list(reversed(p)), [(0, 1), (1, 1), (1, 0), (0, 0)])
for y in (-3.0, 3.0):
    glass.box((4.35, y, 4.2), (1.8, 0.04, 1.7))
glass.box((L0 - 0.01, -1.4, 5.3), (0.04, 1.2, 1.2))  # rear door windows
glass.box((L0 - 0.01, 1.4, 5.3), (0.04, 1.2, 1.2))
van_glass = glass.finish("Van_Glass", "glass_dark.png", 0.05)

tyres = Mesh()
for x in (-4.4, 4.5):
    for y in (-2.7, 2.7):
        tyres.cylinder((x, y, 1.0), 1.0, 0.8, axis="y", seg=20)
van_tyres = tyres.finish("Van_Tyres", "tyre.png", 0.9)

trim = Mesh()
trim.box((6.5, 0, 1.3), (0.35, Wv + 0.2, 0.7))  # front bumper
trim.box((L0 - 0.15, 0, 1.3), (0.35, Wv + 0.2, 0.7))  # rear bumper
trim.box((6.47, 0, 2.55), (0.06, 2.4, 0.6))  # grille
for y in (-3.05, 3.05):
    trim.box((L0 + 4.5, y, 1.25), (Wv * 0 + 9.0, 0.06, 0.4))  # side skirts
    trim.box((5.0, y * 1.03, 4.7), (0.3, 0.3, 0.25))  # mirrors
for x in (-4.4, 4.5):  # hub caps
    for y in (-3.12, 3.12):
        trim.cylinder((x, y, 1.0), 0.45, 0.05, axis="y", seg=12)
trim.box((L0 - 0.02, 0, 3.95), (0.05, 0.06, 6.0))  # rear door seam
trim.box((-1.0, -3.02, 3.95), (0.06, 0.05, 6.0))  # side sliding door seam
trim.box((-1.6, -3.04, 4.0), (0.5, 0.06, 0.12))  # door handle
van_trim = trim.finish("Van_Trim", "trim.png", 0.5)

lights = Mesh()
for y in (-2.3, 2.3):
    lights.box((6.5, y, 2.6), (0.08, 0.8, 0.5), region=(0, 0, 0.5, 1))  # headlights
    lights.box((L0 - 0.03, y * 1.1, 2.4), (0.06, 0.4, 1.0), region=(0.5, 0, 1, 1))  # tail lights
van_lights = lights.finish("Van_Lights", "lights.png", 0.2)
OBJS += [van_body, van_glass, van_tyres, van_trim, van_lights]


# ---------------------------------------------------------------- döner meat cone (layered slices on a rod)
m = Mesh()
STEELR = (0, 0.0, 1, 0.08)
m.cylinder((0, 0, 0.05), 0.95, 0.1, region=STEELR, seg=20)  # tray
m.cylinder((0, 0, 1.6), 0.07, 3.2, region=STEELR, seg=8)  # rod
import random as _r
_r.seed(3)
layers = 16
for k in range(layers):
    t = k / (layers - 1)
    z0 = 0.12 + t * 2.55
    rad = 0.55 + 0.33 * t + _r.uniform(-0.03, 0.03)  # wider at the top like a real döner
    m.cylinder((0, 0, z0 + 0.08), rad, 0.17, region=(0, 0.1 + t * 0.85, 1, 0.1 + t * 0.85 + 0.05), seg=20, taper=1.0 + _r.uniform(-0.04, 0.05))
m.cylinder((0, 0, 2.86), 0.6, 0.08, region=(0, 0.92, 1, 0.97), seg=20, taper=0.6)  # rounded top
OBJS.append(m.finish("MeatCone", "meat_layers.png", 0.55))

# lay everything out side by side for the preview (Studio places them by script anyway)
offsets = {"Box_cardboard": (-9, -8), "Box_veg": (-6, -8), "Box_drink": (-3, -8), "Box_meat": (0, -8), "Shelf": (5, -8), "MeatCone": (2.6, -8)}
for o in OBJS:
    if o.name in offsets:
        o.location = (*offsets[o.name], 0)

tris = sum(len(o.data.polygons) for o in OBJS)
print("objects", len(OBJS), "faces", tris)

bpy.ops.object.select_all(action="DESELECT")
for o in OBJS:
    o.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "kebap_logistics.fbx"), use_selection=True, object_types={"MESH"},
                         path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE", apply_unit_scale=True, bake_space_transform=False)

if not os.environ.get("NO_RENDER"):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.location = (14, -26, 12)
    cam.rotation_euler = (math.radians(66), 0, math.radians(28))
    cam.data.lens = 32
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sun.data.energy = 3
    scene.collection.objects.link(sun)
    scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.6, 0.65, 0.7)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)
print("done")
