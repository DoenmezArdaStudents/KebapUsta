"""
parts/accessories.py – Accessoires am Körper: Rucksack, Umhängetasche, Uhr, Gehstock.

Sitzen über der Kleidung (Abstand CLOTH) und folgen der Körperform aus parts/body.py.
"""

import math

import customer_creator as cc
from customer_creator import BACK, FRONT
from mathutils import Vector
from parts import body as B
from parts import clothing as C

CLOTH = 0.13  # Abstand über dem Körper, damit Gurte über Pulli/Jacke liegen


def at_x(prof, h, x, front=True, off=0.0):
	"""Oberflächenpunkt (und Normale) auf Höhe h bei Roblox-x, vorne oder hinten."""
	c = FRONT if front else BACK
	lo, hi = c - math.pi / 2 + 0.01, c + math.pi / 2 - 0.01
	for _ in range(40):
		mid = (lo + hi) / 2
		px = prof.point(h, mid, 0).x
		if (px < x) == front:  # vorne wächst x mit u, hinten fällt es
			lo = mid
		else:
			hi = mid
	u = (lo + hi) / 2
	return prof.point(h, u, off), prof.normal(h, u)


def strap(prof, x0, h0, x1, h1, front, off, n=10):
	return [at_x(prof, cc.lerp(h0, h1, i / (n - 1)), cc.lerp(x0, x1, i / (n - 1)), front, off) for i in range(n)]


def band(name, samples, w=0.16, t=0.035):
	"""Flacher Gurt entlang von (Punkt, Normale)-Paaren: liegt flach auf, Breite quer zur Laufrichtung."""
	pts = [p for p, _ in samples]
	nrm = [nn.normalized() for _, nn in samples]
	side = []
	for i in range(len(pts)):
		tan = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
		sd = tan.cross(nrm[i])
		side.append(sd.normalized() if sd.length > 1e-6 else Vector((1, 0, 0)))

	def fn(su, sv, off):
		f = sv * (len(pts) - 1)
		i = min(int(f), len(pts) - 2)
		k = f - i
		p = pts[i].lerp(pts[i + 1], k)
		nn = nrm[i].lerp(nrm[i + 1], k).normalized()
		sd = side[i].lerp(side[i + 1], k).normalized()
		return p + sd * (su - 0.5) * w + nn * off

	return cc.slab(name, fn, 2, len(pts) - 1, lambda su, sv: -0.01, lambda su, sv: t, sharp_angle=40)


@cc.part("backpack", "extra", "accent", per_body=True, max_tris=2400)
def backpack(variant, body):
	"""Rucksack: Hauptfach, Fronttasche mit Reißverschluss, Griff, gepolsterte Träger über die Schultern."""
	prof = C.torso(body)
	back_z = prof.point(0.25, BACK, 0).z + CLOTH
	w = 1.25 if body == "m" else 1.10
	parts = [
		cc.rounded_box("tmp", (w, 0.50, 1.30), cc.rbx(0, 0.22, back_z + 0.25), radius=0.20),
		cc.rounded_box("tmp", (w * 0.74, 0.20, 0.58), cc.rbx(0, -0.05, back_z + 0.55), radius=0.09),
		cc.torus("tmp", cc.rbx(0, 0.88, back_z + 0.18), 0.13, 0.035, axis="X", segments=10, ring_segments=6, arc=(0, math.pi)),
	]
	zipper = [cc.rbx(x, 0.22, back_z + 0.655) for x in (-w * 0.3, 0, w * 0.3)]
	for sx in (-1, 1):
		x = sx * (0.40 if body == "m" else 0.36)
		front = strap(prof, x, -0.15, x, 0.98, True, CLOTH)
		top = [(Vector((x, 1.15, 0.0)), Vector((0, 1, 0)))]
		back = strap(prof, x, 0.98, x * 1.1, 0.70, False, CLOTH)
		parts.append(band("tmp", front + top + back))
	pack = cc.join("tmp", parts)
	trim = cc.join("tmp", [cc.sweep("tmp", zipper, 0.02, segments=5)] + [cc.cylinder("tmp", cc.rbx(sx * 0.2, 0.22, back_z + 0.66), cc.rbx(sx * 0.2, 0.12, back_z + 0.68), 0.03, segments=6) for sx in (-1, 1)])
	return [cc.tag(pack, suffix="Bag", anchor="UpperTorso"), cc.tag(trim, suffix="Zip", anchor="UpperTorso", color="fixed:#2a2a30")]


@cc.part("crossbody", "extra", "fixed:#5a3a28", per_body=True, max_tris=1600)
def crossbody(variant, body):
	"""Umhängetasche quer über den Oberkörper (Gurt rechte Schulter → linke Hüfte)."""
	prof = C.torso(body)
	sx = 0.42 if body == "m" else 0.38
	front = strap(prof, sx, 0.98, -0.55, -0.55, True, CLOTH, n=12)
	back = strap(prof, -0.55, -0.55, sx, 0.98, False, CLOTH, n=12)
	top = [(Vector((sx, 1.14, 0.0)), Vector((0, 1, 0)))]
	belt_ = band("tmp", front[::-1] + top + back[::-1], w=0.10, t=0.025)
	p, _ = at_x(prof, -0.62, -0.62, True, CLOTH + 0.10)
	bag = cc.rounded_box("tmp", (0.55, 0.18, 0.42), cc.rbx(p.x, p.y, p.z), radius=0.07)
	flap = cc.rounded_box("tmp", (0.56, 0.05, 0.24), cc.rbx(p.x, p.y + 0.08, p.z - 0.10), radius=0.03, segments=2)
	clasp = cc.rounded_box("tmp", (0.08, 0.03, 0.08), cc.rbx(p.x, p.y - 0.02, p.z - 0.13), radius=0.01, segments=2)
	return [cc.tag(cc.join("tmp", [belt_, bag, flap]), suffix="Bag", anchor="UpperTorso"), cc.tag(clasp, suffix="Clasp", anchor="UpperTorso", color="fixed:#c9a94c")]


@cc.part("watch", "extra", "fixed:#26262a", per_body=True, max_tris=800)
def watch(variant, body):
	"""Armbanduhr am linken Handgelenk (unter langen Ärmeln verdeckt)."""
	prof = B.profile(body, "LeftLowerArm")
	band = cc.garment("tmp", prof, -0.68, -0.58, 0.012, 0.03, nu=24, nv=2)
	n = prof.point(-0.63, FRONT, 0)
	face = cc.cylinder("tmp", cc.rbx(n.x, -0.63, n.z - 0.02), cc.rbx(n.x, -0.63, n.z - 0.08), 0.10, segments=16, bevel=0.015)
	glass = cc.cylinder("tmp", cc.rbx(n.x, -0.63, n.z - 0.075), cc.rbx(n.x, -0.63, n.z - 0.085), 0.075, segments=16)
	return [cc.tag(cc.join("tmp", [band, face]), suffix="Band", anchor="LeftLowerArm"), cc.tag(glass, suffix="Face", anchor="LeftLowerArm", color="fixed:#dfe6ea")]


@cc.part("cane", "extra", "fixed:#5a3a24", per_body=True, max_tris=900)
def cane(variant, body):
	"""Gehstock in der rechten Hand, gebogener Griff."""
	cx = B.profile(body, "RightHand").at(-0.9)["cx"]
	top = Vector((cx, -0.86, -0.18))
	stick = cc.cylinder("tmp", cc.rbx(top.x, top.y, top.z), cc.rbx(top.x, -3.0, top.z), 0.045, segments=10, bevel=0.01)
	hook = cc.torus("tmp", cc.rbx(top.x, top.y, top.z + 0.14), 0.14, 0.045, axis="X", segments=12, ring_segments=8, arc=(0, math.pi))
	tip = cc.cylinder("tmp", cc.rbx(top.x, -2.94, top.z), cc.rbx(top.x, -3.0, top.z), 0.055, segments=10)
	return [cc.tag(cc.join("tmp", [stick, hook]), suffix="Stick", anchor="RightHand"), cc.tag(tip, suffix="Tip", anchor="RightHand", color="fixed:#1d1d1d")]
