"""European delivery van (Sprinter-style) for Kebap Usta.

    pip install bpy numpy pillow --break-system-packages
    python3 build_van.py              (NO_RENDER=1 skips the preview)
Outputs out/kebap_van.fbx + out/preview.png. Separate meshes so the game can animate them:
  Body (painted shell, bumpers, grille, mirrors, lights baked into one atlas), Glass,
  Wheel (one, the game places four and spins them), DoorL / DoorR (rear cargo doors).
In Studio: 3D Importer -> ServerStorage.Models.Van (MeshParts with exactly these names).
Units are studs. Blender: X = forward (front at +X), Y = left, Z = up, ground at Z = 0.
The van is 13.2 long, 5.6 wide, 7.4 high; rear face at X = -6.6.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import bpy  # before bmesh
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT, TEX = os.path.join(HERE, "out"), os.path.join(HERE, "tex")
os.makedirs(OUT, exist_ok=True)
os.makedirs(TEX, exist_ok=True)
N = 1024
FONT = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"


def noise(n, scale, octaves=3, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        g = Image.fromarray((r.random((s + 1, s + 1)) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        acc += np.asarray(g, float) / 255 * amp; tot += amp; amp *= 0.5
    return acc / tot


# ------------------------------------------------------------------ atlas 1024²
# top half (v 0.5..1): side livery, u = along the van (rear -> front), v = height
# bottom-left: plain paint | bottom-middle: black plastic | bottom-right column: lights & chrome
img = Image.new("RGB", (N, N), (240, 240, 238))
paint = (np.full((N, N, 3), 244.0) - noise(N, 8, 3, 1)[..., None] * 10)
img = Image.fromarray(paint.astype(np.uint8))
d = ImageDraw.Draw(img)
H2 = N // 2
# livery on the side band: red/orange swoosh, company name, phone
d.polygon([(0, int(H2 * 0.62)), (N, int(H2 * 0.48)), (N, int(H2 * 0.58)), (0, int(H2 * 0.74))], fill=(222, 64, 36))
d.polygon([(0, int(H2 * 0.76)), (N, int(H2 * 0.60)), (N, int(H2 * 0.63)), (0, int(H2 * 0.79))], fill=(244, 170, 40))
try:
    big = ImageFont.truetype(FONT, 50)
    small = ImageFont.truetype(FONT, 24)
except OSError:
    big = small = ImageFont.load_default()
d.text((60, int(H2 * 0.26)), "FRISCH-LIEFERDIENST", fill=(200, 48, 30), font=big)
d.text((64, int(H2 * 0.40)), "Gemüse · Fleisch · Getränke  –  0664 / 123 45 67", fill=(60, 60, 64), font=small)
# rocker panel grime at the bottom of the side
grime = np.asarray(img, float)
yy = np.mgrid[0:N, 0:N][0] / N
mask = np.clip((yy - 0.44) * 30, 0, 1) * (yy < 0.5)
grime = grime * (1 - mask[..., None] * 0.35)
img = Image.fromarray(grime.astype(np.uint8))
d = ImageDraw.Draw(img)
# bottom row regions
d.rectangle([0, H2, int(N * 0.45), N], fill=(244, 244, 242))  # plain paint
d.rectangle([int(N * 0.45), H2, int(N * 0.75), N], fill=(34, 34, 36))  # black plastic (bumpers, trims)
d.rectangle([int(N * 0.75), H2, N, int(H2 * 1.25)], fill=(250, 246, 226))  # headlight
d.rectangle([int(N * 0.75), int(H2 * 1.25), N, int(H2 * 1.5)], fill=(200, 30, 30))  # tail light
d.rectangle([int(N * 0.75), int(H2 * 1.5), N, int(H2 * 1.75)], fill=(255, 160, 30))  # indicator
d.rectangle([int(N * 0.75), int(H2 * 1.75), N, N], fill=(190, 192, 196))  # chrome / plate
for i in range(8):  # grille slats inside the black region
    y = H2 + 40 + i * 28
    d.rectangle([int(N * 0.47), y, int(N * 0.73), y + 10], fill=(70, 72, 76))
img = img.filter(ImageFilter.GaussianBlur(0.6))
img.save(os.path.join(TEX, "van.png"))
# UV regions (u0, v0, u1, v1) – Blender v=0 is the image bottom
SIDE = (0.0, 0.5, 1.0, 1.0)
PAINT = (0.02, 0.02, 0.43, 0.48)
BLACK = (0.47, 0.30, 0.73, 0.48)
GRILLE = (0.47, 0.02, 0.73, 0.28)
HEAD = (0.76, 0.38, 0.99, 0.49)
TAIL = (0.76, 0.26, 0.99, 0.37)
IND = (0.76, 0.13, 0.99, 0.24)
CHROME = (0.76, 0.01, 0.99, 0.12)

# second small texture for glass and wheels
g = Image.new("RGB", (256, 256), (30, 40, 48))
gd = ImageDraw.Draw(g)
gd.rectangle([128, 0, 256, 128], fill=(24, 24, 26))  # tyre
gd.rectangle([128, 128, 256, 256], fill=(180, 182, 186))  # rim
for i in range(12):
    gd.line([(128 + i * 11, 0), (128 + i * 11, 128)], fill=(40, 40, 42), width=3)  # tread
g.save(os.path.join(TEX, "van_glass_wheel.png"))
GLASS = (0.02, 0.02, 0.48, 0.98)
TYRE = (0.52, 0.52, 0.98, 0.98)
RIM = (0.52, 0.02, 0.98, 0.48)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def material(name, tex, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(TEX, tex))
    b = m.node_tree.nodes["Principled BSDF"]
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


M_BODY = material("van_body", "van.png", 0.3, 0.35)
M_GW = material("van_glass_wheel", "van_glass_wheel.png", 0.2, 0.3)


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def face(self, pts, uvs, smooth=False):
        f = self.bm.faces.new([self.bm.verts.new(Vector(p)) for p in pts])
        f.smooth = smooth
        for l, uv in zip(f.loops, uvs):
            l[self.uv].uv = uv
        return f

    def box(self, c, s, reg):
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        u0, v0, u1, v1 = reg
        P = lambda x, y, z: (cx + x * hx, cy + y * hy, cz + z * hz)
        uv = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
        for pts in ((P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)), (P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)),
                    (P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)), (P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)),
                    (P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)), (P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1))):
            self.face(pts, uv)

    def cyl_y(self, c, r, w, side_reg, cap_reg, seg=20):
        """cylinder along Y (wheel axle direction)"""
        u0, v0, u1, v1 = side_reg
        a_, b_ = [], []
        for i in range(seg + 1):
            a = 2 * math.pi * i / seg
            a_.append((c[0] + math.cos(a) * r, c[1] - w / 2, c[2] + math.sin(a) * r))
            b_.append((c[0] + math.cos(a) * r, c[1] + w / 2, c[2] + math.sin(a) * r))
        for i in range(seg):
            ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
            self.face((a_[i], a_[i + 1], b_[i + 1], b_[i]), ((ua, v0), (ub, v0), (ub, v1), (ua, v1)), True)
        cu0, cv0, cu1, cv1 = cap_reg
        for ring, flip in ((a_, True), (b_, False)):
            ctr = (c[0], ring[0][1], c[2])
            for i in range(seg):
                pts = [ctr, ring[i], ring[i + 1]]
                if flip:
                    pts = [ctr, ring[i + 1], ring[i]]
                uvs = [((cu0 + cu1) / 2, (cv0 + cv1) / 2)] + [(cu0 + (cu1 - cu0) * (0.5 + 0.5 * math.cos(2 * math.pi * k / seg)), cv0 + (cv1 - cv0) * (0.5 + 0.5 * math.sin(2 * math.pi * k / seg))) for k in ((i + 1, i) if flip else (i, i + 1))]
                self.face(pts, uvs)

    def finish(self, name, mat, bevel=0.0):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-4)
        if bevel:
            edges = [e for e in self.bm.edges if e.calc_face_angle(0) > 0.9]
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, affect="EDGES", profile=0.5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me); self.bm.free()
        o = bpy.data.objects.new(name, me)
        o.data.materials.append(mat)
        scene.collection.objects.link(o)
        return o


L0, L1, W = -6.6, 6.6, 5.6
Z0 = 0.95  # underside of the shell
# side silhouette (x, z) going around: rear-bottom, rear-top, roof, windscreen, bonnet, nose
PROFILE = [(L0, Z0), (L0, 7.25), (2.4, 7.25), (2.9, 7.05), (4.85, 4.55), (6.25, 4.05), (6.6, 3.5), (6.6, Z0)]

body = Mesh()
y0, y1 = -W / 2, W / 2


def side_uv(x, z):
    return (SIDE[0] + (x - L0) / (L1 - L0) * (SIDE[2] - SIDE[0]), SIDE[1] + (z / 7.4) * (SIDE[3] - SIDE[1]))


# two side walls (n-gon each) with the livery
for y, rev in ((y0, False), (y1, True)):
    pts = [(x, y, z) for x, z in PROFILE]
    uvs = [side_uv(x, z) for x, z in PROFILE]
    if rev:  # mirror u on the left side so the lettering reads correctly there too
        uvs = [(SIDE[0] + SIDE[2] - u, v) for u, v in uvs]
        pts, uvs = pts[::-1], uvs[::-1]
    body.face(pts, uvs)
# skin around the profile (roof, windscreen area, bonnet, front, rear, bottom)
for i in range(len(PROFILE)):
    (xa, za), (xb, zb) = PROFILE[i], PROFILE[(i + 1) % len(PROFILE)]
    reg = PAINT
    body.face(((xa, y1, za), (xb, y1, zb), (xb, y0, zb), (xa, y0, za)), ((reg[0], reg[1]), (reg[2], reg[1]), (reg[2], reg[3]), (reg[0], reg[3])))
# bumpers, grille, rocker panels, wheel arch trims, mirrors, lights, plates, handles
body.box((6.75, 0, 1.45), (0.5, W + 0.2, 1.0), BLACK)  # front bumper
body.box((6.62, 0, 2.75), (0.08, 3.2, 1.0), GRILLE)  # grille
body.box((6.6, 0, 3.32), (0.1, 3.4, 0.12), CHROME)  # chrome bar
body.box((L0 - 0.15, 0, 1.25), (0.4, W + 0.2, 0.7), BLACK)  # rear bumper with step
body.box((L0 - 0.35, 0, 1.0), (0.6, 2.6, 0.2), BLACK)  # rear step
for y in (y0 - 0.03, y1 + 0.03):
    body.box((0, y, 1.1), (11.0, 0.08, 0.35), BLACK)  # rocker / side protection strip
    for xw in (-4.2, 4.0):  # wheel arch trims
        body.box((xw, y, 2.25), (2.9, 0.1, 0.22), BLACK)
        body.box((xw - 1.4, y, 1.55), (0.2, 0.1, 1.3), BLACK)
        body.box((xw + 1.4, y, 1.55), (0.2, 0.1, 1.3), BLACK)
    body.box((3.25, y * 1.13, 5.3), (0.25, 0.35, 0.9), BLACK)  # mirror head
    body.box((3.35, y * 1.04, 5.3), (0.12, 0.35, 0.12), BLACK)  # mirror arm
    body.box((-1.2, y + (0.05 if y > 0 else -0.05), 3.9), (0.6, 0.06, 0.14), BLACK)  # sliding door handle
    body.box((3.4, y + (0.05 if y > 0 else -0.05), 3.9), (0.45, 0.06, 0.12), BLACK)  # cab door handle
    body.box((-1.0, y + (0.01 if y > 0 else -0.01), 3.9), (0.04, 0.02, 5.2), BLACK)  # sliding door seam
    body.box((6.05, y * 0.98, 1.95), (0.2, 0.06, 0.25), IND)  # side indicator
for y in (-1.95, 1.95):
    body.box((6.4, y, 3.65), (0.3, 1.1, 0.42), HEAD)  # headlights (follow bonnet edge)
    body.box((L0 - 0.02, y * 1.25, 2.4), (0.08, 0.45, 1.4), TAIL)  # tail lights (on the rear pillars)
    body.box((L0 - 0.02, y * 1.25, 3.25), (0.08, 0.45, 0.35), IND)
body.box((6.98, 0, 1.45), (0.04, 1.6, 0.4), CHROME)  # front plate
body.box((L0 - 0.37, 0, 1.75), (0.04, 1.6, 0.4), CHROME)  # rear plate
body.box((L0 - 0.02, 0, 7.05), (0.06, 1.0, 0.18), TAIL)  # third brake light
body.box((-1.5, 0, 7.32), (8.0, 0.12, 0.12), BLACK)  # roof rail
body.box((-1.5, 1.6, 7.32), (8.0, 0.12, 0.12), BLACK)
body.box((-1.5, -1.6, 7.32), (8.0, 0.12, 0.12), BLACK)
# dark cargo hold behind the rear doors (visible when they open)
body.box((L0 + 0.06, 0, 4.1), (0.06, W - 0.6, 5.6), BLACK)
body_o = body.finish("Body", M_BODY, bevel=0.06)

glass = Mesh()
GL = (GLASS[0], GLASS[1], GLASS[2], GLASS[3])
uvq = ((GL[0], GL[1]), (GL[2], GL[1]), (GL[2], GL[3]), (GL[0], GL[3]))
# windscreen on the slanted part of the profile, inset from the sides
ws = [(2.95, -2.5, 6.95), (2.95, 2.5, 6.95), (4.75, 2.5, 4.68), (4.75, -2.5, 4.68)]
glass.face([(x + 0.03, y, z) for x, y, z in ws][::-1], uvq)
for y in (y0 - 0.03, y1 + 0.03):
    # cab side window (trapezoid following the A-pillar) + a small window in the sliding door
    pts = [(2.9, y, 4.55), (4.6, y, 4.55), (3.1, y, 6.7), (2.9, y, 6.7)] if y > 0 else [(2.9, y, 6.7), (3.1, y, 6.7), (4.6, y, 4.55), (2.9, y, 4.55)]
    glass.face(pts, uvq)
glass_o = glass.finish("Glass", M_GW)

wheel = Mesh()
wheel.cyl_y((0, 0, 0), 1.05, 0.8, TYRE, TYRE, 24)
wheel.cyl_y((0, 0.41, 0), 0.6, 0.06, RIM, RIM, 16)  # rim (outer side)
wheel.cyl_y((0, -0.41, 0), 0.6, 0.06, RIM, RIM, 16)  # rim (inner side, shows when mirrored)
wheel_o = wheel.finish("Wheel", M_GW)
wheel_o.location = (0, -9, 1.05)


def rear_door(name, ysign):
    """one rear wing door, hinge at the outer edge (y = ysign * W/2), closed in the rear face"""
    m = Mesh()
    w = W / 2 - 0.05
    yc = ysign * (W / 2 - w / 2)
    m.box((L0 - 0.06, yc, 4.05), (0.12, w, 6.0), PAINT)
    m.box((L0 - 0.13, yc, 5.6), (0.04, w - 0.5, 1.6), BLACK)  # rear window frame
    m.box((L0 - 0.15, yc, 5.6), (0.03, w - 0.7, 1.4), GLASS[:2] + (0.4, 0.4))
    m.box((L0 - 0.16, ysign * 0.25, 3.6), (0.06, 0.12, 0.6), BLACK)  # handle near the centre gap
    for z in (1.6, 4.0, 6.5):  # hinges on the outer edge
        m.box((L0 - 0.14, ysign * (W / 2 - 0.05), z), (0.12, 0.15, 0.35), BLACK)
    return m.finish(name, M_BODY)


door_l = rear_door("DoorL", 1)  # left = +Y
door_r = rear_door("DoorR", -1)

objs = [body_o, glass_o, wheel_o, door_l, door_r]
print("faces", sum(len(o.data.polygons) for o in objs))
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "kebap_van.fbx"), use_selection=True, object_types={"MESH"},
                         path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE", apply_unit_scale=True, bake_space_transform=False)

if not os.environ.get("NO_RENDER"):
    # preview: four wheels for the picture only
    for i, (x, y) in enumerate(((-4.2, -2.75), (4.0, -2.75), (-4.2, 2.75), (4.0, 2.75))):
        c = wheel_o.copy(); c.location = (x, y, 1.05); scene.collection.objects.link(c)
    wheel_o.location = (100, 0, 0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.location = (14, -16, 7)
    cam.rotation_euler = (math.radians(75), 0, math.radians(40))
    cam.data.lens = 30
    scene.camera = cam
    scene.world = bpy.data.worlds.new("w")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x, scene.render.resolution_y = 1100, 650
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)
print("done")
