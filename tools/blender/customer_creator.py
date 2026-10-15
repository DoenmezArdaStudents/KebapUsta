"""
customer_creator.py – Kern-Bibliothek für die Kundenmodelle (Issue #1, siehe docs/customer-models.md).

Baut prozedural Roblox-Kunden: eigener, leicht menschlicher Körper (Mann/Frau) auf den Gelenken des
Standard-R15-Rigs, 3D-Kleidung pro Körpersegment, Haare/Hüte/Accessoires für den Roblox Dynamic Head.
Die Teile selbst liegen in `parts/` (body, clothing, hair, accessories) und registrieren sich mit `@part`.

Koordinaten: Modelliert wird in Roblox-Koordinaten relativ zum HumanoidRootPart (Y oben, vorne −Z,
+X = rechte Körperseite). `rbx()` rechnet in Blender um (Z oben, Figur schaut nach −Y, Füße auf z = 0).
1 Blender-Einheit = 1 Stud. Erst der FBX-Export stellt die Achsen wieder auf Roblox um.

Körper und Kleidung entstehen aus `Profile`n: Folgen von Querschnitten (Superellipsen) entlang einer
Achse. Kleidung nutzt dieselben Profile mit Abstand nach außen und sitzt deshalb immer am Körper.

Jedes erzeugte Objekt trägt Custom Properties: `part`, `variant`, `body` (m/w/–), `slot`,
`anchor` (Rig-Körperteil, an das es geschweißt wird), `attach` (Roblox-Attachment, nur Kopfteile)
und `colorSlot` (`skin`, `top`, `outer`, `bottom`, `shoes`, `hair`, `accent`, `fixed:#rrggbb`).
"""

import colorsys
import math
import random
import struct

import bmesh
import bpy
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# Rig (Standard-R15, gemessen in Studio)
# ---------------------------------------------------------------------------
H0 = 3.006  # HumanoidRootPart-Höhe über dem Boden

# Standard-Teile: ((Größe X, Y, Z), (Position X, Y)) relativ zum HumanoidRootPart
RIG = {
	"Head": ((1.159, 1.182, 1.161), (0.0, 1.586)),
	"UpperTorso": ((1.943, 1.698, 1.004), (0.0, 0.200)),
	"LowerTorso": ((1.991, 0.401, 1.004), (0.0, -0.800)),
	"LeftUpperArm": ((1.001, 1.242, 1.002), (-1.5, 0.369)),
	"LeftLowerArm": ((1.001, 1.118, 1.002), (-1.5, -0.224)),
	"LeftHand": ((0.984, 0.316, 1.028), (-1.5, -0.850)),
	"RightUpperArm": ((1.001, 1.242, 1.002), (1.5, 0.369)),
	"RightLowerArm": ((1.001, 1.118, 1.002), (1.5, -0.224)),
	"RightHand": ((0.984, 0.316, 1.028), (1.5, -0.850)),
	"LeftUpperLeg": ((0.993, 1.363, 0.973), (-0.5, -1.421)),
	"LeftLowerLeg": ((0.993, 1.301, 0.973), (-0.5, -2.201)),
	"LeftFoot": ((1.009, 0.312, 1.001), (-0.5, -2.850)),
	"RightUpperLeg": ((0.993, 1.363, 0.973), (0.5, -1.421)),
	"RightLowerLeg": ((0.993, 1.301, 0.973), (0.5, -2.201)),
	"RightFoot": ((1.009, 0.312, 1.001), (0.5, -2.850)),
}

# Gelenke (RigAttachments) – um diese Punkte drehen die Animationen die Segmente
JOINT = {
	"Neck": 1.049,
	"Shoulder": (1.0, 0.788),
	"Elbow": 0.051,
	"Wrist": -0.718,
	"Waist": -0.649,
	"Hip": (0.5, -0.95),
	"Knee": -1.788,
	"Ankle": -2.744,
	"Sole": -3.006,
}

# Gesicht des Standard-Dynamic-Head (in Studio vermessen, relativ zur Kopfmitte)
EYE_X, EYE_Y, EYE_W, EYE_H = 0.12, 0.27, 0.075, 0.18
MOUTH_Y, MOUTH_W = -0.34, 0.38
HAIRLINE_MIN = 0.41  # Haare/Hüte bleiben vorne darüber → Augen frei, Mimik sichtbar
MOUTH_CLEAR = 0.10  # Bärte bleiben so weit vom Mund weg

# Hauttöne wie in Server/CustomerService (SKIN)
SKIN = ["#ffdcbe", "#eac0a0", "#cc966e", "#a06e4b", "#6e4b32", "#f5cdaf"]


def rbx(x, y, z=0.0):
	"""Roblox-Koordinate (relativ zum HumanoidRootPart) → Blender-Welt."""
	return Vector((-x, z, y + H0))


def to_rbx(v):
	"""Blender-Welt → Roblox (relativ zum HumanoidRootPart). Umkehrung von rbx()."""
	return Vector((-v.x, v.z - H0, v.y))


def rig_center(name):
	return rbx(*RIG[name][1])


HEAD_C = rig_center("Head")
HEAD_RX, HEAD_RY, HEAD_HH = 1.159 / 2, 1.161 / 2, 1.182 / 2
HEAD_NH, HEAD_NV = 2.0, 4.3  # Form des Dynamic Head (in Studio per Raycast vermessen)


# ---------------------------------------------------------------------------
# Szene & Sammlungen
# ---------------------------------------------------------------------------
def new_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.unit_settings.system = "NONE"
	return scene


def collection(name, parent=None):
	col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
	parent = parent or bpy.context.scene.collection
	if col.name not in parent.children:
		parent.children.link(col)
	return col


_active_col = None


def use_collection(col):
	global _active_col
	_active_col = col


def _link(ob):
	(_active_col or bpy.context.scene.collection).objects.link(ob)
	return ob


# ---------------------------------------------------------------------------
# Farben / Materialien
# ---------------------------------------------------------------------------
def hex_rgb(h):
	h = h.lstrip("#")
	return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))


def srgb_to_linear(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(hex_color):
	return [srgb_to_linear(c) for c in hex_rgb(hex_color)]


def jitter(hex_color, rng, amount=0.04):
	"""Leichter HSV-Jitter, damit gleiche Palettenfarben nicht identisch wirken."""
	h, s, v = colorsys.rgb_to_hsv(*hex_rgb(hex_color))
	h = (h + rng.uniform(-amount, amount) * 0.25) % 1
	s = min(1, max(0, s + rng.uniform(-amount, amount)))
	v = min(1, max(0, v + rng.uniform(-amount, amount)))
	r, g, b = colorsys.hsv_to_rgb(h, s, v)
	return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def shade(hex_color, factor):
	"""Farbe heller (>1) oder dunkler (<1) – z. B. für Nähte, Bündchen."""
	r, g, b = hex_rgb(hex_color)
	f = lambda c: min(1, max(0, c * factor))  # noqa: E731
	return "#%02x%02x%02x" % tuple(round(f(c) * 255) for c in (r, g, b))


def material(hex_color, roughness=0.6, alpha=1.0):
	name = "M_%s_%d" % (hex_color.lstrip("#"), round(alpha * 100))
	mat = bpy.data.materials.get(name)
	if mat:
		return mat
	mat = bpy.data.materials.new(name)
	mat.diffuse_color = (*lin(hex_color), alpha)
	mat.roughness = roughness
	try:
		mat.use_nodes = True
	except AttributeError:
		pass
	bsdf = mat.node_tree and mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = (*lin(hex_color), 1)
		bsdf.inputs["Roughness"].default_value = roughness
		for key in ("Specular IOR Level", "Specular"):
			if key in bsdf.inputs:
				bsdf.inputs[key].default_value = 0.25
		if alpha < 1:
			bsdf.inputs["Alpha"].default_value = alpha
			for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
				if hasattr(mat, attr):
					setattr(mat, attr, val)
					break
	return mat


def set_color(ob, hex_color, alpha=1.0):
	ob.data.materials.clear()
	ob.data.materials.append(material(hex_color, alpha=alpha))


# ---------------------------------------------------------------------------
# Mesh-Grundlagen
# ---------------------------------------------------------------------------
def to_object(name, bm, smooth=True, sharp_angle=50, recalc=True):
	if recalc:
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	if smooth:
		me.shade_smooth()
		if sharp_angle and hasattr(me, "set_sharp_from_angle"):
			me.set_sharp_from_angle(angle=math.radians(sharp_angle))
	ob = _link(bpy.data.objects.new(name, me))
	center_origin(ob)
	return ob


def center_origin(ob):
	"""Ursprung in die Mitte der Bounding Box (so setzt der Roblox-Importer die Part-Position)."""
	vs = ob.data.vertices
	if not vs:
		return
	lo = Vector((min(v.co[i] for v in vs) for i in range(3)))
	hi = Vector((max(v.co[i] for v in vs) for i in range(3)))
	c = (lo + hi) / 2
	ob.data.transform(Matrix.Translation(-c))
	ob.matrix_basis = ob.matrix_basis @ Matrix.Translation(c)


def join(name, objects):
	"""Mehrere Objekte zu einem Mesh zusammenfassen (Welt-Koordinaten bleiben erhalten)."""
	objects = [o for o in objects if o]
	bpy.context.view_layer.update()
	bm = bmesh.new()
	smooth = []
	for ob in objects:
		me = ob.data.copy()
		me.transform(ob.matrix_world)
		bm.from_mesh(me)
		smooth += [p.use_smooth for p in me.polygons]
		bpy.data.meshes.remove(me)
	for ob in objects:
		bpy.data.objects.remove(ob)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for p, s in zip(me.polygons, smooth):
		p.use_smooth = s
	ob = _link(bpy.data.objects.new(name, me))
	center_origin(ob)
	return ob


def tris(ob):
	return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def apply_all(ob):
	dg = bpy.context.evaluated_depsgraph_get()
	me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
	old = ob.data
	ob.modifiers.clear()
	ob.data = me
	bpy.data.meshes.remove(old)
	return ob


def decimate_to(ob, max_tris):
	n = tris(ob)
	if n <= max_tris:
		return ob
	mod = ob.modifiers.new("Decimate", "DECIMATE")
	mod.ratio = max_tris / n * 0.98
	return apply_all(ob)


def _grid_faces(bm, rows, closed_u, pole=None, flip=False):
	"""rows[i][j]: i läuft quer (u), j längs. Erzeugt Quads und optional einen Fächer zum Pol."""
	nu = len(rows)
	last = nu if closed_u else nu - 1
	for i in range(last):
		a, b = rows[i], rows[(i + 1) % nu]
		for j in range(len(a) - 1):
			q = (a[j], b[j], b[j + 1], a[j + 1])
			bm.faces.new(q[::-1] if flip else q)
		if pole is not None:
			t = (a[-1], b[-1], pole)
			bm.faces.new(t[::-1] if flip else t)


def _spow(x, p):
	return math.copysign(abs(x) ** p, x)


def smoothstep(a, b, x):
	t = max(0.0, min(1.0, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)


def lerp(a, b, t):
	return a + (b - a) * t


# ---------------------------------------------------------------------------
# Grundformen (Blender-Koordinaten)
# ---------------------------------------------------------------------------
def rounded_box(name, size, center, radius=0.12, segments=3):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
	r = min(radius, min(size) * 0.49)
	if r > 0:
		bmesh.ops.bevel(
			bm, geom=list(bm.edges), offset=r, offset_type="OFFSET", segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True
		)
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	return to_object(name, bm)


def sphere(name, center, radius, scale=(1, 1, 1), segments=16, rings=10):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
	r = radius if isinstance(radius, (tuple, list, Vector)) else (radius, radius, radius)
	for v in bm.verts:
		v.co = Vector((v.co.x * r[0] * scale[0], v.co.y * r[1] * scale[1], v.co.z * r[2] * scale[2])) + Vector(center)
	return to_object(name, bm, sharp_angle=None)


def cylinder(name, p0, p1, radius, segments=16, bevel=0.0):
	p0, p1 = Vector(p0), Vector(p1)
	d = p1 - p0
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=d.length)
	if bevel > 0:
		h = d.length / 2
		rim = [e for e in bm.edges if all(abs(abs(v.co.z) - h) < 1e-6 for v in e.verts) and abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
		bmesh.ops.bevel(bm, geom=rim, offset=bevel, offset_type="OFFSET", segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
	rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
	bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts)
	return to_object(name, bm)


def _frames(path, closed):
	n = len(path)
	tangents = []
	for i in range(n):
		a = path[(i - 1) % n] if (closed or i > 0) else path[i]
		b = path[(i + 1) % n] if (closed or i < n - 1) else path[i]
		tangents.append((b - a).normalized())
	ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
	normal = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
	frames = []
	for t in tangents:
		normal = (normal - t * normal.dot(t)).normalized()
		frames.append((t, normal, t.cross(normal)))
	return frames


def sweep(name, path, radius, segments=8, closed=False, caps=True):
	"""Rohr entlang eines Pfads (Blender-Koordinaten). radius: Zahl, (a, b) oder Funktion(i)."""
	path = [Vector(p) for p in path]
	bm = bmesh.new()
	rings = []
	for i, (_, n, b) in enumerate(_frames(path, closed)):
		r = radius(i) if callable(radius) else radius
		ra, rb_ = (r, r) if isinstance(r, (int, float)) else r
		rings.append([bm.verts.new(path[i] + n * math.cos(2 * math.pi * k / segments) * ra + b * math.sin(2 * math.pi * k / segments) * rb_) for k in range(segments)])
	count = len(rings) if closed else len(rings) - 1
	for i in range(count):
		a, b2 = rings[i], rings[(i + 1) % len(rings)]
		for k in range(segments):
			bm.faces.new((a[k], a[(k + 1) % segments], b2[(k + 1) % segments], b2[k]))
	if not closed and caps:
		bm.faces.new(rings[0])
		bm.faces.new(rings[-1][::-1])
	return to_object(name, bm, sharp_angle=70)


def torus(name, center, major, minor, axis="Y", segments=20, ring_segments=8, arc=(0, 2 * math.pi)):
	c = Vector(center)
	full = abs(arc[1] - arc[0] - 2 * math.pi) < 1e-6
	n = segments if full else segments + 1
	pts = []
	for i in range(n):
		a = arc[0] + (arc[1] - arc[0]) * i / segments
		p = {"X": (0, math.cos(a), math.sin(a)), "Y": (math.cos(a), 0, math.sin(a)), "Z": (math.cos(a), math.sin(a), 0)}[axis]
		pts.append(c + Vector(p) * major)
	return sweep(name, pts, minor, segments=ring_segments, closed=full)


# ---------------------------------------------------------------------------
# Profile: Querschnitte entlang einer Achse (Roblox-Koordinaten)
# ---------------------------------------------------------------------------
FRONT = 1.5 * math.pi  # u-Winkel, der nach vorne (−Z) zeigt
BACK = 0.5 * math.pi


class Profile:
	"""
	Körperabschnitt als Folge von Querschnitten. Jeder Ring ist ein dict:
	h (Position auf der Achse), a (halbe Breite X), b (halbe Tiefe bzw. Höhe), optional
	cx/cy/cz (Mittelpunkt), n (Superellipsen-Exponent), front/back (Wölbung nach vorne/hinten).
	axis="y": Ringe liegen waagerecht (Rumpf, Arme, Beine). axis="z": Ringe stehen senkrecht (Füße).
	u = 0 zeigt nach +X, u = FRONT nach vorne (−Z, bei axis="z" nach oben).
	"""

	KEYS = ("h", "a", "b", "cx", "cy", "cz", "n", "front", "back")

	def __init__(self, rings, axis="y", sub=4):
		self.axis = axis
		rings = sorted(
			[{"cx": 0.0, "cy": 0.0, "cz": 0.0, "n": 2.4, "front": 0.0, "back": 0.0, **r} for r in rings], key=lambda r: r["h"]
		)
		self.rings = rings
		self.dense = self._densify(rings, sub)
		self.h0, self.h1 = self.dense[0]["h"], self.dense[-1]["h"]

	@staticmethod
	def _densify(rings, sub):
		"""Catmull-Rom zwischen den Ringen → glatte Übergänge."""
		if len(rings) < 2:
			return rings
		out = []
		for i in range(len(rings) - 1):
			p0, p1, p2, p3 = rings[max(i - 1, 0)], rings[i], rings[i + 1], rings[min(i + 2, len(rings) - 1)]
			for s in range(sub):
				t = s / sub
				t2, t3 = t * t, t * t * t
				r = {}
				for k in Profile.KEYS:
					a, b, c, d = p0[k], p1[k], p2[k], p3[k]
					r[k] = 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
				r["h"] = lerp(p1["h"], p2["h"], t)
				out.append(r)
		out.append(dict(rings[-1]))
		return out

	def at(self, h):
		d = self.dense
		h = max(self.h0, min(self.h1, h))
		lo, hi = 0, len(d) - 1
		while hi - lo > 1:
			mid = (lo + hi) // 2
			if d[mid]["h"] <= h:
				lo = mid
			else:
				hi = mid
		a, b = d[lo], d[hi]
		t = 0 if b["h"] == a["h"] else (h - a["h"]) / (b["h"] - a["h"])
		return {k: lerp(a[k], b[k], t) for k in Profile.KEYS}

	def _base(self, h, u):
		"""Punkt auf der Oberfläche inkl. Wölbungen, plus 2D-Normale im Ring."""
		r = self.at(h)
		n = max(r["n"], 1.2)
		c, s = math.cos(u), math.sin(u)
		e = 2 / n
		a, b = max(r["a"], 1e-4), max(r["b"], 1e-4)
		px, pq = a * _spow(c, e), b * _spow(s, e)
		gx, gq = _spow(px / a, n - 1) / a, _spow(pq / b, n - 1) / b
		gl = math.hypot(gx, gq) or 1.0
		gx, gq = gx / gl, gq / gl
		f = -s  # 1 = vorne (bzw. oben bei axis="z")
		d = r["front"] * max(0.0, f) ** 2 + r["back"] * max(0.0, -f) ** 2
		if self.axis == "y":
			return Vector((r["cx"] + px + gx * d, h, r["cz"] + pq + gq * d)), Vector((gx, 0, gq))
		return Vector((r["cx"] + px + gx * d, r["cy"] - pq - gq * d, h)), Vector((gx, -gq, 0))

	def normal(self, h, u):
		"""Echte 3D-Normale (auch an den runden Enden, z. B. über der Schulter)."""
		e = 1e-3
		p, ring_n = self._base(h, u)
		pu = self._base(h, u + e)[0] - self._base(h, u - e)[0]
		lo, hi = max(self.h0, h - e), min(self.h1, h + e)
		if hi - lo < 1e-7:
			return ring_n
		ph = self._base(hi, u)[0] - self._base(lo, u)[0]
		n = pu.cross(ph)
		if n.length < 1e-9:
			return ring_n
		n.normalize()
		return n if n.dot(ring_n) >= 0 else -n

	def point(self, h, u, off=0.0):
		"""Roblox-Punkt auf der Oberfläche (off = Abstand nach außen entlang der Normalen)."""
		p, _ = self._base(h, u)
		return p if off == 0 else p + self.normal(h, u) * off

	def center(self, h):
		r = self.at(h)
		return Vector((r["cx"], h, r["cz"])) if self.axis == "y" else Vector((r["cx"], r["cy"], h))

	def mirrored(self):
		"""Spiegelung an X (rechte → linke Körperseite)."""
		p = object.__new__(Profile)
		p.axis, p.h0, p.h1 = self.axis, self.h0, self.h1
		p.rings = [dict(r, cx=-r["cx"]) for r in self.rings]
		p.dense = [dict(r, cx=-r["cx"]) for r in self.dense]
		p._mirror = True
		return p

	@property
	def outer_u(self):
		"""u-Winkel der Außenseite eines Arms/Beins."""
		return math.pi if self.is_mirrored else 0.0

	@property
	def is_mirrored(self):
		return getattr(self, "_mirror", False)


def _axis_dir(profile, sign):
	return Vector((0, sign, 0)) if profile.axis == "y" else Vector((0, 0, sign))


def solid(name, profile, h0=None, h1=None, nu=24, nh=None, off=0.0, sharp_angle=None):
	"""Geschlossener Körper aus einem Profil (Enden laufen über die Endringe rund zu)."""
	h0 = profile.h0 if h0 is None else h0
	h1 = profile.h1 if h1 is None else h1
	nh = nh or max(6, int(abs(h1 - h0) / 0.07))
	bm = bmesh.new()
	rows = []
	for i in range(nu):
		u = 2 * math.pi * i / nu
		rows.append([bm.verts.new(rbx(*profile.point(lerp(h0, h1, j / nh), u, off))) for j in range(nh + 1)])
	r0, r1 = profile.at(h0), profile.at(h1)
	k0 = min(r0["a"], r0["b"]) * 0.35
	k1 = min(r1["a"], r1["b"]) * 0.35
	p_lo = bm.verts.new(rbx(*(profile.center(h0) + _axis_dir(profile, -k0))))
	p_hi = bm.verts.new(rbx(*(profile.center(h1) + _axis_dir(profile, k1))))
	_grid_faces(bm, rows, True, p_hi)
	for i in range(nu):
		bm.faces.new((rows[(i + 1) % nu][0], rows[i][0], p_lo))
	return to_object(name, bm, sharp_angle=sharp_angle)


def slab(name, fn, nu, nv, inner, outer, closed_u=False, sharp_angle=60):
	"""
	Allgemeine Platte/Hülle: fn(su, sv, off) → Roblox-Punkt, su/sv ∈ [0, 1].
	inner(su, sv)/outer(su, sv) → Abstände der Innen-/Außenseite. Die Ränder werden geschlossen.
	Grundlage für Kleidung, Taschen, Bündchen, Gürtel …
	"""
	bm = bmesh.new()
	cols = nu if closed_u else nu + 1
	ins = [[bm.verts.new(rbx(*fn(i / nu, j / nv, inner(i / nu, j / nv)))) for j in range(nv + 1)] for i in range(cols)]
	outs = [[bm.verts.new(rbx(*fn(i / nu, j / nv, outer(i / nu, j / nv)))) for j in range(nv + 1)] for i in range(cols)]
	_grid_faces(bm, outs, closed_u)
	_grid_faces(bm, ins, closed_u, flip=True)
	# Ränder
	if closed_u:
		loops = [[(i, 0) for i in range(cols)], [(i, nv) for i in range(cols)][::-1]]
		for loop in loops:
			for k in range(len(loop)):
				(a, b), (c, d) = loop[k], loop[(k + 1) % len(loop)]
				bm.faces.new((ins[a][b], ins[c][d], outs[c][d], outs[a][b]))
	else:
		border = [(i, 0) for i in range(cols)] + [(cols - 1, j) for j in range(1, nv + 1)]
		border += [(i, nv) for i in range(cols - 2, -1, -1)] + [(0, j) for j in range(nv - 1, 0, -1)]
		for k in range(len(border)):
			(a, b), (c, d) = border[k], border[(k + 1) % len(border)]
			bm.faces.new((ins[a][b], ins[c][d], outs[c][d], outs[a][b]))
	return to_object(name, bm, sharp_angle=sharp_angle)


def const(v):
	return lambda su, sv: v


def garment(name, profile, h0, h1, gap, thick, nu=28, nv=None, urange=None, sharp_angle=60):
	"""
	Kleidungshülle über einem Profil von h0 bis h1 (Zahl oder Funktion(u), z. B. Ausschnitt).
	gap/thick: Zahl oder Funktion(h, u).
	urange(h) → (u0, u1) für offene Teile (Jacke vorne offen); sonst rundum geschlossen.
	"""
	f0 = h0 if callable(h0) else (lambda u: h0)
	f1 = h1 if callable(h1) else (lambda u: h1)
	nv = nv or max(4, int(abs(f1(FRONT) - f0(FRONT)) / 0.10))
	g = gap if callable(gap) else (lambda h, u: gap)
	t = thick if callable(thick) else (lambda h, u: thick)

	def uh(su, sv):
		if urange:
			h = lerp(f0(0), f1(0), sv)
			u0, u1 = urange(h)
			return h, lerp(u0, u1, su)
		u = 2 * math.pi * su
		return lerp(f0(u), f1(u), sv), u

	def fn(su, sv, off):
		h, u = uh(su, sv)
		return profile.point(h, u, off)

	inner = lambda su, sv: g(*uh(su, sv))  # noqa: E731
	outer = lambda su, sv: g(*uh(su, sv)) + t(*uh(su, sv))  # noqa: E731
	return slab(name, fn, nu, nv, inner, outer, closed_u=urange is None, sharp_angle=sharp_angle)


def capped_shell(name, profile, h0, h1, gap, thick, nu=24, nv=None, sharp_angle=60):
	"""
	Hülle von h0 bis zum Profilende h1, dort geschlossen (Ärmel über der Schulter).
	Unten ein Rand von gap bis gap+thick; der innere Deckel liegt verborgen im Körper.
	"""
	g = gap if callable(gap) else (lambda h, u: gap)
	t = thick if callable(thick) else (lambda h, u: thick)
	nv = nv or max(5, int(abs(h1 - h0) / 0.07))
	sign = 1 if h1 > h0 else -1
	bm = bmesh.new()
	outer, inner = [], []
	for i in range(nu):
		u = 2 * math.pi * i / nu
		outer.append([bm.verts.new(rbx(*profile.point(lerp(h0, h1, j / nv), u, g(lerp(h0, h1, j / nv), u) + t(lerp(h0, h1, j / nv), u)))) for j in range(nv + 1)])
		inner.append(bm.verts.new(rbx(*profile.point(h0, u, g(h0, u)))))
	r1 = profile.at(h1)
	k = min(r1["a"], r1["b"]) * 0.35 + g(h1, 0) + t(h1, 0)
	pole = bm.verts.new(rbx(*(profile.center(h1) + _axis_dir(profile, sign * k))))
	hidden = bm.verts.new(rbx(*profile.center(h0)))
	_grid_faces(bm, outer, True, pole)
	for i in range(nu):
		j = (i + 1) % nu
		bm.faces.new((inner[i], inner[j], outer[j][0], outer[i][0]))
		bm.faces.new((inner[j], inner[i], hidden))
	return to_object(name, bm, sharp_angle=sharp_angle)


def patch(name, profile, h0, h1, u0, u1, off, thick, nu=8, nv=6, urange=None, sharp_angle=50):
	"""Aufgesetztes Stück auf einer Oberfläche (Tasche, Blende, Kragen). urange(h) überschreibt u0/u1."""
	o = off if callable(off) else (lambda h, u: off)
	t = thick if callable(thick) else (lambda h, u: thick)

	def uh(su, sv):
		h = lerp(h0, h1, sv)
		a, b = urange(h) if urange else (u0, u1)
		return h, lerp(a, b, su)

	def fn(su, sv, d):
		h, u = uh(su, sv)
		return profile.point(h, u, d)

	return slab(
		name, fn, nu, nv, lambda su, sv: o(*uh(su, sv)), lambda su, sv: o(*uh(su, sv)) + t(*uh(su, sv)), sharp_angle=sharp_angle
	)


def line(name, profile, pts, off, radius, segments=6):
	"""Naht/Kordel entlang der Oberfläche: pts = [(h, u), …]."""
	return sweep(name, [rbx(*profile.point(h, u, off)) for h, u in pts], radius, segments=segments)


def ring_line(name, profile, h, off, radius, segments=6, n=32):
	"""Geschlossener Wulst rund um ein Profil (Bündchen, Kragen, Gürtel)."""
	pts = [rbx(*profile.point(h, 2 * math.pi * i / n, off)) for i in range(n)]
	return sweep(name, pts, radius, segments=segments, closed=True)


def on_surface(profile, h, u, off):
	return rbx(*profile.point(h, u, off))


def surface_normal(profile, h, u):
	p0, p1 = profile.point(h, u, 0), profile.point(h, u, 0.05)
	v = to_blender_dir(p1 - p0)
	return v.normalized()


def to_blender_dir(v):
	return Vector((-v.x, v.z, v.y))


def button(name, profile, h, u, off, radius=0.035, depth=0.02):
	"""Knopf als flacher Zylinder auf der Oberfläche."""
	p = on_surface(profile, h, u, off)
	n = surface_normal(profile, h, u)
	return cylinder(name, p, p + n * depth, radius, segments=10, bevel=depth * 0.4)


# ---------------------------------------------------------------------------
# Kopf als Superellipsoid (Form des Dynamic Head) – Grundlage für Haare, Hüte, Gesicht
# ---------------------------------------------------------------------------
def head_point(u, phi):
	"""Punkt auf der Kopfoberfläche (Blender). u: Winkel um die Hochachse (−π/2 = vorne), phi: Breite."""
	c, s = _spow(math.cos(phi), 2 / HEAD_NV), _spow(math.sin(phi), 2 / HEAD_NV)
	return HEAD_C + Vector((HEAD_RX * c * _spow(math.cos(u), 2 / HEAD_NH), HEAD_RY * c * _spow(math.sin(u), 2 / HEAD_NH), HEAD_HH * s))


def _head_f(p):
	q = p - HEAD_C
	h = (abs(q.x / HEAD_RX) ** HEAD_NH + abs(q.y / HEAD_RY) ** HEAD_NH) ** (HEAD_NV / HEAD_NH)
	return h + abs(q.z / HEAD_HH) ** HEAD_NV


def head_normal(p):
	e = 1e-4
	g = Vector(
		(
			_head_f(p + Vector((e, 0, 0))) - _head_f(p - Vector((e, 0, 0))),
			_head_f(p + Vector((0, e, 0))) - _head_f(p - Vector((0, e, 0))),
			_head_f(p + Vector((0, 0, e))) - _head_f(p - Vector((0, 0, e))),
		)
	)
	return g.normalized() if g.length > 1e-9 else Vector((0, 0, 1))


def head_offset(u, phi, off):
	p = head_point(u, phi)
	return p + head_normal(p) * off


def phi_at(z):
	"""Breitenwinkel, auf dem die Kopfoberfläche die Höhe z (relativ zur Kopfmitte) hat."""
	return math.asin(max(-1, min(1, _spow(z / HEAD_HH, HEAD_NV / 2))))


def front_y(x, z=0.0):
	"""y der Kopf-Vorderseite bei (x, z) – zum Aufsetzen von Gesichtsteilen (Blender)."""
	hz = 1 - abs(z / HEAD_HH) ** HEAD_NV
	r = max(0.0, hz) ** (1 / HEAD_NV)
	k = max(0.0, 1 - abs(x / (HEAD_RX * r)) ** HEAD_NH) if r > 0 else 0
	return HEAD_C.y - HEAD_RY * r * k ** (1 / HEAD_NH)


def frontness(u):
	"""Kopf-Winkel: 1 = vorne (−Y), 0 = seitlich, −1 = hinten."""
	return -math.sin(u)


def head_shell(name, cut, thickness, gap=0.015, nu=40, nv=10, bulge=None, top=None):
	"""
	Hülle über dem Kopf (Haare, Mützen). cut(u) → Unterkante (Höhe relativ zur Kopfmitte),
	thickness(u, t) → Dicke (t: 0 = Rand, 1 = Scheitel), bulge(u, t) → zusätzliches Volumen.
	"""
	bm = bmesh.new()
	inner, outer = [], []
	nv_in = 3
	for i in range(nu):
		u = 2 * math.pi * i / nu
		p0 = phi_at(cut(u))
		ri, ro = [], []
		for j in range(nv):
			t = j / nv
			p = head_point(u, p0 + (math.pi / 2 - p0) * t)
			n = head_normal(p)
			extra = bulge(u, t) if bulge else 0.0
			ro.append(bm.verts.new(p + n * (gap + thickness(u, t) + extra)))
			if j == 0:
				ri.append(bm.verts.new(p + n * gap))
		for j in range(1, nv_in):
			t = j / nv_in
			p = head_point(u, p0 + (math.pi / 2 - p0) * t)
			ri.append(bm.verts.new(p + head_normal(p) * gap))
		inner.append(ri)
		outer.append(ro)
	topc = HEAD_C + Vector((0, 0, HEAD_HH))
	ti = bm.verts.new(topc + Vector((0, 0, gap)))
	to = bm.verts.new(topc + Vector((0, 0, gap + thickness(0, 1) + (bulge(0, 1) if bulge else 0))))
	_grid_faces(bm, outer, True, to)
	_grid_faces(bm, inner, True, ti, flip=True)
	for i in range(nu):
		k = (i + 1) % nu
		bm.faces.new((inner[i][0], inner[k][0], outer[k][0], outer[i][0]))
	return to_object(name, bm, sharp_angle=70)


def head_patch(name, u0, u1, z_lo, z_hi, thickness, gap=0.012, nu=24, nv=8, sharp_angle=70):
	"""
	Stück auf der Kopfoberfläche zwischen u0..u1 und z_lo(u)..z_hi(u) (Bärte, Koteletten, Haarkränze).
	thickness(su, sv) → Dicke; an den Rändern auf 0 auslaufen lassen für weiche Übergänge.
	"""

	def fn(su, sv, off):
		u = lerp(u0, u1, su)
		z = lerp(z_lo(u), z_hi(u), sv)
		p = head_point(u, phi_at(z))
		return to_rbx(p + head_normal(p) * off)

	return slab(name, fn, nu, nv, lambda su, sv: gap, lambda su, sv: gap + thickness(su, sv), sharp_angle=sharp_angle)


# ---------------------------------------------------------------------------
# Teile-Registry
# ---------------------------------------------------------------------------
PARTS = {}
BODIES = ("m", "w")


def part(pid, slot, color, variants="A", per_body=False, bodies=BODIES, anchor="Head", attach=None, under_hat=False, max_tris=1500, hat_ok=True):
	"""
	Registriert einen Teile-Builder: fn(variant, body) → Objekt oder Liste.
	per_body=True: Teil wird für jeden Körper (m/w) eigens gebaut (Kleidung). Einzelne Objekte können
	mit tag() eigenes anchor/colorSlot/suffix bekommen.
	"""

	def deco(fn):
		PARTS[pid] = {
			"id": pid,
			"slot": slot,
			"colorSlot": color,
			"variants": variants,
			"perBody": per_body,
			"bodies": bodies,
			"anchor": anchor,
			"attach": attach,
			"underHat": under_hat,
			"hatOk": hat_ok,
			"maxTris": max_tris,
			"build": fn,
		}
		return fn

	return deco


def tag(ob, suffix="", anchor=None, color=None, **extra):
	"""Metadaten an einem Teilstück setzen (Segment, Farbe, Namenszusatz)."""
	if suffix:
		ob["suffix"] = suffix
	if anchor:
		ob["anchor"] = anchor
	if color:
		ob["colorSlot"] = color
	for k, v in extra.items():
		ob[k] = v
	return ob


def part_name(pid, variant, body=None, suffix=""):
	base = "".join(w.capitalize() for w in pid.split("_"))
	parts = [base, variant] + ([body.upper()] if body else []) + ([suffix] if suffix else [])
	return "_".join(parts)


def build_part(pid, variant="A", body="m"):
	spec = PARTS[pid]
	b = body if spec["perBody"] else None
	objs = spec["build"](variant, body)
	objs = [o for o in (objs if isinstance(objs, list) else [objs]) if o]
	for ob in objs:
		ob.name = part_name(pid, variant, b, ob.get("suffix", ""))
		ob.data.name = ob.name
		ob["part"] = pid
		ob["variant"] = variant
		ob["body"] = b or ""
		ob["slot"] = spec["slot"]
		for key in ("anchor", "attach", "colorSlot"):
			if key not in ob.keys() and spec[key] is not None:
				ob[key] = spec[key]
		bake_transform(ob)
		ob["trisRaw"] = tris(ob)
		decimate_to(ob, spec["maxTris"])
	return objs


def bake_transform(ob):
	"""Drehung/Skalierung ins Mesh übernehmen; das Objekt behält nur seine Position (Mitte)."""
	bpy.context.view_layer.update()
	ob.data.transform(ob.matrix_basis)
	ob.matrix_basis = Matrix.Identity(4)
	center_origin(ob)


# ---------------------------------------------------------------------------
# Vorschau: Kopf wie der Dynamic Head mit seinem Standardgesicht
# ---------------------------------------------------------------------------
def head_mesh(name):
	bm = bmesh.new()
	nu, nv = 40, 18
	rows = [[bm.verts.new(head_point(2 * math.pi * i / nu, -math.pi / 2 + math.pi * j / nv)) for j in range(1, nv)] for i in range(nu)]
	bottom = bm.verts.new(HEAD_C - Vector((0, 0, HEAD_HH)))
	top = bm.verts.new(HEAD_C + Vector((0, 0, HEAD_HH)))
	_grid_faces(bm, rows, True, top)
	for i in range(nu):
		bm.faces.new((rows[(i + 1) % nu][0], rows[i][0], bottom))
	return to_object(name, bm, sharp_angle=None)


def preview_face(mood="happy"):
	"""Gesicht des Standard-Dynamic-Head (nur Vorschau, im Spiel bringt der Kopf es mit)."""
	z = HEAD_C.z
	objs = []
	for sx in (-1, 1):
		x = sx * EYE_X
		eye = sphere("Face_Eye", (x, front_y(x, EYE_Y) + 0.012, z + EYE_Y), (EYE_W / 2, 0.02, EYE_H / 2), segments=12, rings=8)
		set_color(eye, "#111114")
		objs.append(eye)
	pts = []
	for i in range(13):
		t = i / 12 - 0.5
		x = t * MOUTH_W
		dz = (0.07 * (1 - (2 * t) ** 2) - 0.035) if mood == "happy" else 0.0
		zz = MOUTH_Y + 0.02 - dz
		pts.append(Vector((x, front_y(x, zz) - 0.004, z + zz)))
	mouth = sweep("Face_Mouth", pts, 0.018, segments=6)
	set_color(mouth, "#111114")
	return objs + [mouth]


# ---------------------------------------------------------------------------
# Kunden würfeln und zusammenbauen (spiegelt das spätere randomLook in Luau)
# ---------------------------------------------------------------------------
def weighted(rng, table):
	items = [(k, w) for k, w in table.items() if w > 0]
	total = sum(w for _, w in items)
	x = rng.uniform(0, total)
	for k, w in items:
		x -= w
		if x <= 0:
			return k
	return items[-1][0]


def roll_look(arch, rng, body=None):
	"""
	Würfelt einen Kunden eines Typs. Slot-Tabellen können je Körper verschieden sein
	({"m": {...}, "w": {...}}), Einträge "teil:B" erzwingen eine Variante. Paletten-Einträge, die
	ein String sind, übernehmen die Farbe eines anderen Slots (z. B. Anzughose = Sakko).
	"""
	body = body or weighted(rng, arch.get("bodies", {"m": 1, "w": 1}))

	def table(key):
		t = arch["slots"].get(key, {None: 1})
		return t.get(body, {None: 1}) if ("m" in t or "w" in t) and all(isinstance(v, dict) for v in t.values()) else t

	pal = arch["palettes"]
	colors = {k: jitter(rng.choice(v), rng) for k, v in pal.items() if not isinstance(v, str)}
	for k, v in pal.items():
		if isinstance(v, str):
			colors[k] = colors[v]
	colors["skin"] = rng.choice(SKIN)

	def pid_of(entry):
		return entry.split(":")[0] if entry else None

	hat = weighted(rng, table("hat"))
	hair = weighted(rng, table("hair"))
	if hat and hair and not PARTS[pid_of(hair)]["underHat"]:
		alt = {k: w for k, w in table("hair").items() if k and PARTS[pid_of(k)]["underHat"]}
		hair = weighted(rng, alt) if alt else None
	entries = [e for e in (hair, hat) if e]
	for key in arch["slots"]:
		if key not in ("hair", "hat"):
			e = weighted(rng, table(key))
			if e:
				entries.append(e)
	for pid, p in arch.get("extras", {}).items():
		p = p.get(body, 0) if isinstance(p, dict) else p
		if rng.random() < p:
			entries.append(pid)
	parts = []
	for e in entries:
		pid, _, forced = e.partition(":")
		spec = PARTS[pid]
		if spec["perBody"] and body not in spec["bodies"]:
			continue
		parts.append((pid, forced or rng.choice(spec["variants"])))
	return {"archetype": arch["id"], "body": body, "colors": colors, "parts": parts, "scale": rng.uniform(*arch["scale"])}


def color_for(slot, colors):
	if slot.startswith("fixed:"):
		return slot[6:]
	if slot.startswith("mix:"):  # mix:<slot a>:<slot b>:<anteil b>
		_, a, b, t = slot.split(":")
		ca, cb = hex_rgb(color_for(a, colors)), hex_rgb(color_for(b, colors))
		return "#%02x%02x%02x" % tuple(round(lerp(x, y, float(t)) * 255) for x, y in zip(ca, cb))
	if slot.startswith("shade:"):  # shade:<slot>:<faktor>
		_, s, f = slot.split(":")
		return shade(color_for(s, colors), float(f))
	return colors.get(slot) or colors.get("top", "#ff00ff")


def assemble(look, name="Customer", mood="happy"):
	"""Baut einen kompletten Kunden (Körper + Vorschau-Kopf + Teile) unter einem Empty."""
	colors = look["colors"]
	objs = []
	for pid, variant in [("body", "A")] + list(look["parts"]):
		for ob in build_part(pid, variant, look["body"]):
			set_color(ob, color_for(ob["colorSlot"], colors), alpha=1 - ob.get("transparency", 0))
			objs.append(ob)
	head = head_mesh("Body_Head")
	set_color(head, colors["skin"])
	objs += [head] + preview_face(mood)
	root = bpy.data.objects.new(name, None)
	_link(root)
	bpy.context.view_layer.update()  # frische Objekte: matrix_world erst nach Update gültig
	for ob in objs:
		mw = ob.matrix_world.copy()
		ob.parent = root
		ob.matrix_world = mw
	s = look["scale"]
	root.scale = (s, s, s)
	root["look"] = repr(look)
	return root


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
def anchors():
	"""Quader in Rig-Größe – werden mitexportiert, um beim Import Maßstab/Lage zu kalibrieren."""
	objs = []
	for name, ((sx, sy, sz), _) in RIG.items():
		bm = bmesh.new()
		bmesh.ops.create_cube(bm, size=1.0)
		for v in bm.verts:
			v.co = Vector((v.co.x * sx, v.co.y * sz, v.co.z * sy)) + rig_center(name)
		objs.append(to_object("Ref_" + name, bm, smooth=False))
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=0.1)
	bmesh.ops.translate(bm, vec=rbx(0, 1.586, -0.9), verts=bm.verts)
	objs.append(to_object("Ref_Front", bm, smooth=False))
	return objs


def export_fbx(objects, path):
	for ob in bpy.context.view_layer.objects:
		ob.select_set(False)
	for ob in objects:
		ob.select_set(True)
	bpy.ops.export_scene.fbx(
		filepath=path,
		use_selection=True,
		object_types={"MESH"},
		axis_forward="-Z",
		axis_up="Y",
		apply_unit_scale=True,
		global_scale=1.0,
		mesh_smooth_type="FACE",
		add_leaf_bones=False,
		bake_anim=False,
	)


def export_studio_data(objects):
	"""
	Kompakte Mesh-Daten für den Studio-Test ohne Upload (studio_preview.luau). Je Teil, little-endian:
	u16 Vertices, u16 Dreiecke, je Vertex i16×3 Position (1/2048 Stud, relativ zur Teil-Mitte) + i8×3
	Normale, je Dreieck u16×3. Rückgabe: (bytes, Manifest).
	"""
	blob, manifest = bytearray(), []
	for ob in objects:
		me = ob.data
		me.calc_loop_triangles()
		mw = ob.matrix_world
		nm = mw.to_3x3().inverted().transposed()
		normals = me.corner_normals if hasattr(me, "corner_normals") else None
		pts = [to_rbx(mw @ v.co) for v in me.vertices]
		lo = Vector((min(p[i] for p in pts) for i in range(3)))
		hi = Vector((max(p[i] for p in pts) for i in range(3)))
		c = (lo + hi) / 2
		verts, index, tris_ = [], {}, []
		for lt in me.loop_triangles:
			tri = []
			for li in lt.loops:
				vi = me.loops[li].vertex_index
				n = (normals[li].vector if normals else me.vertices[vi].normal) if lt.use_smooth else lt.normal
				w = nm @ Vector(n)
				n = Vector((-w.x, w.z, w.y)).normalized()  # Richtung wie to_rbx
				key = (vi, round(n.x * 127), round(n.y * 127), round(n.z * 127))
				if key not in index:
					index[key] = len(verts)
					verts.append((pts[vi] - c, key[1:]))
				tri.append(index[key])
			tris_.append(tri)
		if len(verts) > 65535:
			raise ValueError("%s: zu viele Vertices" % ob.name)
		blob += struct.pack("<HH", len(verts), len(tris_))
		for p, n in verts:
			blob += struct.pack("<hhhbbb", *(round(x * 2048) for x in p), *n)
		for t in tris_:
			blob += struct.pack("<HHH", *t)
		manifest.append(
			{
				"name": ob.name,
				"part": ob.get("part"),
				"body": ob.get("body", ""),
				"slot": ob.get("slot"),
				"anchor": ob.get("anchor"),
				"attach": ob.get("attach", ""),
				"colorSlot": ob.get("colorSlot"),
				"transparency": ob.get("transparency", 0),
				"center": [round(x, 4) for x in c],
			}
		)
	return bytes(blob), manifest


# ---------------------------------------------------------------------------
# Vorschau-Rendering
# ---------------------------------------------------------------------------
def setup_stage(width=1600, height=1600, samples=48):
	scene = bpy.context.scene
	for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
		try:
			scene.render.engine = engine
			break
		except TypeError:
			continue
	scene.render.resolution_x, scene.render.resolution_y = width, height
	scene.view_settings.view_transform = "Standard"
	if hasattr(scene, "eevee"):
		for attr, val in (("taa_render_samples", samples), ("use_shadows", True), ("use_gtao", True)):
			if hasattr(scene.eevee, attr):
				setattr(scene.eevee, attr, val)
	world = bpy.data.worlds.new("Sky")
	scene.world = world
	world.color = lin("#a9d4f5")
	try:
		world.use_nodes = True
	except AttributeError:
		pass
	bg = world.node_tree and world.node_tree.nodes.get("Background")
	if bg:
		bg.inputs["Color"].default_value = (*lin("#a9d4f5"), 1)
		bg.inputs["Strength"].default_value = 0.9
	sun = bpy.data.lights.new("Sun", "SUN")
	sun.energy = 3.0
	sun.angle = math.radians(10)
	sun_ob = _link(bpy.data.objects.new("Sun", sun))
	sun_ob.rotation_euler = (math.radians(50), math.radians(-12), math.radians(-35))
	fill = bpy.data.lights.new("Fill", "AREA")
	fill.energy = 300
	fill.size = 10
	fill_ob = _link(bpy.data.objects.new("Fill", fill))
	fill_ob.location = (-6, -9, 7)
	fill_ob.rotation_euler = Vector((6, 9, -4)).to_track_quat("Z", "Y").to_euler()
	bm = bmesh.new()
	bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=80)
	floor = to_object("Baseplate", bm, smooth=False)
	mat = bpy.data.materials.new("M_Baseplate")
	try:
		mat.use_nodes = True
	except AttributeError:
		pass
	nt = mat.node_tree
	if nt:
		checker = nt.nodes.new("ShaderNodeTexChecker")
		checker.inputs["Scale"].default_value = 40
		checker.inputs["Color1"].default_value = (*lin("#a3a7ab"), 1)
		checker.inputs["Color2"].default_value = (*lin("#9a9ea3"), 1)
		bsdf = nt.nodes.get("Principled BSDF")
		nt.links.new(checker.outputs["Color"], bsdf.inputs["Base Color"])
		bsdf.inputs["Roughness"].default_value = 0.8
	floor.data.materials.append(mat)
	return scene


def camera(location, target, lens=50, ortho_scale=None):
	cam = bpy.data.cameras.get("Camera") or bpy.data.cameras.new("Camera")
	cam.lens = lens
	cam.type = "ORTHO" if ortho_scale else "PERSP"
	if ortho_scale:
		cam.ortho_scale = ortho_scale
	ob = bpy.data.objects.get("Camera") or _link(bpy.data.objects.new("Camera", cam))
	ob.location = location
	ob.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
	bpy.context.scene.camera = ob
	return ob


def render(path, size=None):
	scene = bpy.context.scene
	if size:
		scene.render.resolution_x, scene.render.resolution_y = size
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


def lineup(looks, prefix, spacing=4.2):
	"""Stellt Kunden nebeneinander auf und gibt ihre Wurzel-Objekte zurück."""
	roots = []
	for i, look in enumerate(looks):
		root = assemble(look, "%s_%02d" % (prefix, i + 1))
		root.location.x = (i - (len(looks) - 1) / 2) * spacing
		roots.append(root)
	return roots
