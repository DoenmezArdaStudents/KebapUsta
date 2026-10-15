"""
build.py – baut alle Kundenteile, prüft sie, exportiert sie und rendert Vorschauen.

Aufruf (aus dem Repo-Root):
	blender -b -P tools/blender/build.py -- --seed 42 --preview

Ergebnis in tools/blender/out/ (gitignored):
	CustomerParts.fbx     alle Teile + Anker (Ref_*) für den 3D-Importer in Studio
	studio/               Mesh-Daten für den Studio-Test ohne Upload (siehe studio_preview.luau)
	Customers.blend       Beispiel-Kunden (je Typ Frau + Mann) zum Ansehen in Blender
	people*.png           Beispiel-Kunden vorne/hinten               (mit --preview)
	preview_<typ>.png     Reihe zufälliger Kunden pro Typ            (mit --preview)
"""

import argparse
import base64
import importlib.util
import json
import os
import random
import subprocess
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import customer_creator as cc  # noqa: E402
from parts import accessories, body, clothing, hair  # noqa: E402,F401  (registrieren die Teile)

OUT = os.path.join(HERE, "out")
CHUNK = 180_000  # Zeichen pro StringValue (Roblox-Grenze 200 000)


def args():
	argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--seed", type=int, default=42)
	p.add_argument("--preview", action="store_true")
	p.add_argument("--count", type=int, default=8)
	return p.parse_args(argv)


def load_archetypes():
	result = []
	folder = os.path.join(HERE, "customers")
	for fn in sorted(os.listdir(folder)):
		if fn.endswith(".py") and not fn.startswith("_"):
			spec = importlib.util.spec_from_file_location("customers." + fn[:-3], os.path.join(folder, fn))
			mod = importlib.util.module_from_spec(spec)
			spec.loader.exec_module(mod)
			result.append(mod.ARCHETYPE)
	return result


def needed_parts(archs):
	ids = {"body"}

	def collect(table):
		for k, v in table.items():
			if isinstance(v, dict):
				collect(v)
			elif k:
				ids.add(k.split(":")[0])

	for a in archs:
		collect(a["slots"])
		ids |= set(a.get("extras", {}))
	ids |= {pid for pid, spec in cc.PARTS.items() if spec["underHat"]}
	missing = ids - set(cc.PARTS)
	if missing:
		raise SystemExit("unbekannte Teile in customers/*.py: %s" % ", ".join(sorted(missing)))
	return sorted(ids)


def face_check(ob):
	"""Haare/Hüte: vorne über HAIRLINE_MIN. Bärte: unter dem Mund. Gibt Fehlertext oder None zurück."""
	slot = ob["slot"]
	if ob.get("anchor") != "Head" or slot not in ("hair", "hat", "beard"):
		return None
	pts = [ob.location + v.co - cc.HEAD_C for v in ob.data.vertices]
	front = [p for p in pts if p.y < -0.35]
	if slot == "beard":
		zs = [p.z for p in front if abs(p.x) < 0.22]
		if zs and max(zs) > cc.MOUTH_Y - cc.MOUTH_CLEAR:
			return "%s verdeckt den Mund (%.2f)" % (ob.name, max(zs))
		return None
	zs = [p.z for p in front if abs(p.x) < 0.30]
	if zs and min(zs) < cc.HAIRLINE_MIN:
		return "%s verdeckt Augen/Stirn (Unterkante %.2f)" % (ob.name, min(zs))
	return None


def build_library(ids):
	col = cc.collection("Export")
	cc.use_collection(col)
	objs, errors, notes = [], [], []
	print("\n%-34s %-9s %-14s %-22s %6s" % ("Teil", "Slot", "Segment", "Farbe", "Tris"))
	for pid in ids:
		spec = cc.PARTS[pid]
		for b in spec["bodies"] if spec["perBody"] else ("m",):
			for variant in spec["variants"]:
				for ob in cc.build_part(pid, variant, b):
					cc.set_color(ob, "#9a9a9a")
					n, raw = cc.tris(ob), ob["trisRaw"]
					print("%-34s %-9s %-14s %-22s %6d%s" % (ob.name, ob["slot"], ob["anchor"], ob["colorSlot"], n, " (reduziert von %d)" % raw if raw > n else ""))
					if raw > n:
						notes.append("%s: %d → %d Dreiecke" % (ob.name, raw, n))
					err = face_check(ob)
					if err:
						errors.append(err)
					objs.append(ob)
	names = [o.name for o in objs]
	if len(names) != len(set(names)):
		errors.append("doppelte Namen: %s" % sorted({n for n in names if names.count(n) > 1}))
	total = sum(cc.tris(o) for o in objs)
	print("\n%d Teile, %d Dreiecke gesamt" % (len(objs), total))
	for n in notes:
		print("  Hinweis:", n)
	if errors:
		raise SystemExit("Fehler:\n  " + "\n  ".join(errors))
	return objs, col


def look_pieces(look, parts):
	"""Welche Teilstücke (Objektnamen) ein Kunde trägt, mit fertig aufgelöster Farbe."""
	out = []
	for pid, variant in [("body", "A")] + list(look["parts"]):
		for ob in parts:
			if ob["part"] == pid and ob["variant"] == variant and ob["body"] in (look["body"], ""):
				out.append({"name": ob.name, "color": cc.color_for(ob["colorSlot"], look["colors"]), "transparency": ob.get("transparency", 0)})
	return {"archetype": look["archetype"], "body": look["body"], "skin": look["colors"]["skin"], "scale": round(look["scale"], 3), "pieces": out}


def write_studio_data(parts, looks):
	"""Mesh-Daten für den Studio-Test (studio_preview.project.json → ServerStorage.CustomerPreviewData)."""
	folder = os.path.join(OUT, "studio")
	data_dir = os.path.join(folder, "data")
	os.makedirs(data_dir, exist_ok=True)
	for fn in os.listdir(data_dir):
		os.remove(os.path.join(data_dir, fn))
	blob, manifest = cc.export_studio_data(parts)
	raw = os.path.join(folder, "CustomerParts.bin")
	with open(raw, "wb") as f:
		f.write(blob)
	compressed = False
	try:
		subprocess.run(["zstd", "-19", "-q", "-f", raw, "-o", raw + ".zst"], check=True)
		raw, compressed = raw + ".zst", True
	except (OSError, subprocess.CalledProcessError):
		print("zstd nicht gefunden – Daten unkomprimiert")
	with open(raw, "rb") as f:
		text = base64.b64encode(f.read()).decode()
	chunks = [text[i : i + CHUNK] for i in range(0, len(text), CHUNK)]
	for i, c in enumerate(chunks, 1):
		with open(os.path.join(data_dir, "Data_%03d.txt" % i), "w") as f:
			f.write(c)
	with open(os.path.join(folder, "Manifest.json"), "w") as f:
		json.dump({"compressed": compressed, "chunks": len(chunks), "parts": manifest, "looks": [look_pieces(lk, parts) for lk in looks]}, f, indent=1)
	print("Studio-Daten: %d Teile, %d KB, %d Blöcke" % (len(manifest), len(text) // 1024, len(chunks)))


def hide(col, hidden=True):
	layer = bpy.context.view_layer.layer_collection.children.get(col.name)
	if layer:
		layer.exclude = hidden


def remove_collection(col):
	for ob in list(col.all_objects):
		bpy.data.objects.remove(ob)
	bpy.data.collections.remove(col)
	for me in [m for m in bpy.data.meshes if m.users == 0]:
		bpy.data.meshes.remove(me)


def main():
	a = args()
	os.makedirs(OUT, exist_ok=True)
	archs = load_archetypes()
	cc.new_scene()
	parts, lib = build_library(needed_parts(archs))
	# Beispiel-Kunden: je Typ eine Frau und ein Mann
	looks = []
	for arch in archs:
		for b in ("w", "m"):
			looks.append(cc.roll_look(arch, random.Random("%d/%s/%s" % (a.seed, arch["id"], b)), body=b))
	cc.export_fbx(parts + cc.anchors(), os.path.join(OUT, "CustomerParts.fbx"))
	write_studio_data(parts, looks)
	hide(lib)

	people = cc.collection("Customers")
	cc.use_collection(people)
	roots = cc.lineup(looks, "Customer", spacing=4.4)
	for root, look in zip(roots, looks):
		root.name = "Customer_%s_%s" % (look["archetype"], look["body"])
		print("  %-26s %s" % (root.name, ", ".join("%s/%s" % p for p in look["parts"])))

	if a.preview:
		stage = cc.collection("Stage")
		cc.use_collection(stage)
		cc.setup_stage()
		width = len(looks) * 4.4 + 1.0
		cc.camera((0, -60, 11), (0, 0, 2.9), ortho_scale=width)
		cc.render(os.path.join(OUT, "people.png"), (3600, 1250))
		cc.camera((0, 60, 11), (0, 0, 2.9), ortho_scale=width)
		cc.render(os.path.join(OUT, "people_back.png"), (3600, 1250))
		half = len(looks) // 2
		for k, name in ((0, "people_a.png"), (1, "people_b.png")):
			cx = ((k * half + (half - 1) / 2) - (len(looks) - 1) / 2) * 4.4
			cc.camera((cx - 5.5, -17, 6.5), (cx, 0, 2.8), lens=40)
			cc.render(os.path.join(OUT, name), (2800, 1600))
	bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Customers.blend"))
	print("Beispiel-Kunden gespeichert: Customers.blend")

	if a.preview:
		hide(people)
		for arch in archs:
			col = cc.collection("Lineup_" + arch["id"])
			cc.use_collection(col)
			rng = random.Random("%d/%s" % (a.seed, arch["id"]))
			random_looks = [cc.roll_look(arch, rng) for _ in range(a.count)]
			cc.lineup(random_looks, arch["id"], spacing=4.4)
			cc.camera((0, -60, 11), (0, 0, 2.9), ortho_scale=a.count * 4.4 + 1.0)
			cc.render(os.path.join(OUT, "preview_%s.png" % arch["id"]), (3600, 1250))
			remove_collection(col)
	print("fertig →", OUT)


main()
