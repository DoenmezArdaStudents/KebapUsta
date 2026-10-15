"""
Kebap Usta – modular R15 customer NPC builder for Blender (bpy, runs headless).

Look: classic Roblox R15 blocks (exact default-rig sizes) with small modern touches – rounded
edges, bevelled joints, tight 3D clothing with details only at the edges.

Usage (from the repo root):
    blender -b --factory-startup -P tools/npc/npc_builder.py -- --npc npc01 --upto 7 --render

    --npc     key in CONFIG["npcs"]
    --upto N  run steps 1..N (every run starts from an empty scene)
    --render  render a check sheet after the last step (--views front,side,threeq,back)
    --studio  write mesh data for the Studio preview without upload (out/studio/, see studio_preview.luau)
    --fbx     write out/<npc>.fbx (for the Studio 3D Importer); --fbx-items Tee,Apron,… only those items

Steps
    1 scene, units, collections        5 face, hair, accessories
    2 R15 base body (15 parts)         6 quality check (naming, pivots, tris, normals) + renders
    3 materials / palette              7 export preparation (FBX settings + rig table, no export)
    4 clothing layers

Conventions
    1 Blender unit = 1 stud. Z is up, the character faces -Y, its left side is +X, the feet stand
    on Z = 0, the HumanoidRootPart centre is at Z = 3. Every object's origin sits on the joint of
    the R15 part it belongs to, so clothing pieces share the pivot of their body part.
    Objects are named <Item>_<R15 part> (base body: Body_<part>), the game colours them per Item.
    Roblox MeshParts have a single colour, so every object has exactly one material; coloured
    details are their own objects (e.g. Hoodie_LeftLowerArm + HoodieAccent_LeftLowerArm).
    Left/right pieces are only described for the left side and mirrored.
    Layering rule: garments reuse the ring segments (count and phase) of the body part below them,
    otherwise the corners of the inner layer poke through the flat chords of the outer one.

    The face (eyes + shine, brows, nose, mouth) is real geometry on the Head: small domes and tubes
    that follow the faceted head mesh and are half sunk into it, one object per colour.

New NPCs = a new entry in CONFIG["npcs"] (colours, clothing list, styles, face, hair). The base body in
CONFIG["body"] is shared by all NPCs and must not change. New garment types are new style
functions registered in STYLES (see build_clothing).
"""

import argparse
import base64
import json
import math
import os
import struct
import subprocess
import sys

import bmesh
import bpy
from mathutils import Vector

# ===========================================================================
# CONFIG
# ===========================================================================
# Body parts are rounded boxes ("box"), built as stacks of superellipse rings along Z:
#   half = (x, y_front, y_back), z = (bottom, top), c = (x, y) centre, e = superellipse exponent,
#   bevel = chamfer at both ends, plug = narrower stub that reaches into the neighbour part so no
#   gap opens when the joint rotates, taper = x/y scale at the bottom (1 = straight).
# Sizes and joints are the Roblox default R15 rig (measured in Studio), feet on Z = 0.

CONFIG = {
    "collections": ["Base_R15", "Clothing_Top", "Clothing_Bottom", "Clothing_Shoes", "Face", "Hair", "Accessories", "Variants"],
    "smooth_angle": 40,  # degrees – edges sharper than this stay hard (block edges, soles, cuffs)
    "hrp_height": 3.0,  # HumanoidRootPart centre above the floor
    # ---------------------------------------------------------------- base body (shared, fixed)
    "body": {
        # joint positions: midpoint of the parent/child RigAttachments of the default rig
        "joints": {
            "Neck": (0.0, 0.0, 4.03),
            "Waist": (0.0, 0.0, 2.375),
            "Root": (0.0, 0.0, 2.0),
            "LeftShoulder": (0.985, 0.0, 3.793),
            "LeftElbow": (1.5, 0.0, 3.032),
            "LeftWrist": (1.5, 0.0, 2.263),
            "LeftHip": (0.5, 0.0, 2.025),
            "LeftKnee": (0.5, 0.0, 1.171),
            "LeftAnkle": (0.5, 0.0, 0.23),
        },
        "cap": 0.02,  # pole distance beyond the last ring
        "parts": {
            # classic head: rounded cylinder 1.16 wide, 1.18 high (rings: z, r_x, r_front, r_back, cx, cy, e)
            "Head": {"joint": "Neck", "n": 16, "phase": 11.25, "rings": [
                (3.995, 0.42, 0.42, 0.42, 0, 0, 2.0),
                (4.02, 0.52, 0.52, 0.52, 0, 0, 2.0),
                (4.07, 0.565, 0.565, 0.565, 0, 0, 2.0),
                (4.15, 0.58, 0.58, 0.58, 0, 0, 2.0),
                (5.02, 0.58, 0.58, 0.58, 0, 0, 2.0),
                (5.10, 0.565, 0.565, 0.565, 0, 0, 2.0),
                (5.15, 0.52, 0.52, 0.52, 0, 0, 2.0),
                (5.177, 0.42, 0.42, 0.42, 0, 0, 2.0),
            ]},
            "UpperTorso": {"joint": "Waist", "n": 16, "phase": 11.25, "box": {
                "half": (0.97, 0.50, 0.50), "z": (2.375, 4.049), "c": (0, 0), "e": 6.0, "bevel": 0.06,
                "taper": 0.96, "plug": {"bottom": 0.1}}},
            "LowerTorso": {"joint": "Root", "n": 16, "phase": 11.25, "box": {
                "half": (0.995, 0.50, 0.50), "z": (2.0, 2.4), "c": (0, 0), "e": 6.0, "bevel": 0.05}},
            "LeftUpperArm": {"joint": "LeftShoulder", "n": 12, "phase": 15, "box": {
                "half": (0.50, 0.50, 0.50), "z": (3.032, 3.99), "c": (1.5, 0), "e": 5.0, "bevel": 0.06}},
            "LeftLowerArm": {"joint": "LeftElbow", "n": 12, "phase": 15, "box": {
                "half": (0.49, 0.49, 0.49), "z": (2.263, 3.032), "c": (1.5, 0), "e": 5.0, "bevel": 0.05,
                "plug": {"top": 0.12}}},
            "LeftHand": {"joint": "LeftWrist", "n": 12, "phase": 15, "box": {
                "half": (0.47, 0.49, 0.49), "z": (1.992, 2.263), "c": (1.5, 0), "e": 5.0, "bevel": 0.05,
                "plug": {"top": 0.1}}},
            "LeftUpperLeg": {"joint": "LeftHip", "n": 12, "phase": 15, "box": {
                "half": (0.4965, 0.4865, 0.4865), "z": (1.171, 2.0), "c": (0.5, 0), "e": 5.0, "bevel": 0.05,
                "plug": {"top": 0.14}}},
            "LeftLowerLeg": {"joint": "LeftKnee", "n": 12, "phase": 15, "box": {
                "half": (0.49, 0.48, 0.48), "z": (0.23, 1.171), "c": (0.5, 0), "e": 5.0, "bevel": 0.05,
                "plug": {"top": 0.12}}},
            "LeftFoot": {"joint": "LeftAnkle", "n": 12, "phase": 15, "box": {
                "half": (0.5, 0.5, 0.5), "z": (0.0, 0.23), "c": (0.5, 0), "e": 5.0, "bevel": 0.04,
                "plug": {"top": 0.1}}},
        },
    },
    # ---------------------------------------------------------------- palette (Döner shop, urban)
    "palette": {
        "red_dark": "#8C2B2B", "red_accent": "#B5382F",
        "leather": "#5A3E2B", "wood": "#7B5A3F",
        "anthracite": "#2E2E30", "grey_mid": "#6B6D70", "grey_light": "#B8BABD",
        "off_white": "#EDE9E0", "denim": "#2F3B52", "black": "#151516",
        "hair_dark_brown": "#3B2A20", "skin_light_warm": "#E8BE9C",
        "eye_dark": "#231B17", "mouth_dark": "#5A2A24", "white": "#FFFFFF",
    },
    # ---------------------------------------------------------------- garment styles (defaults)
    "styles": {
        "top": {
            "hoodie": {
                "offset": 0.03, "hem_z": 2.06, "band_h": 0.08, "cuff_z": 2.33, "cuff_h": 0.08,
                "pocket": True, "drawstrings": True, "hood": True, "lining": True,
                "rim_r": 0.06, "hood_open_deg": 84,
                # hood lying flat on the back: (z below the shoulder line, half width, thickness)
                "hood_bag": [(0.0, 0.36, 0.035), (-0.18, 0.40, 0.05), (-0.36, 0.30, 0.045), (-0.48, 0.12, 0.025)],
            },
            # work clothes (staff, drivers): short sleeves ending at sleeve_z on the upper arm.
            # No neck rib: the head overhangs the neck opening (it is wider than the torso is deep).
            "tee": {"item": "Tee", "offset": 0.025, "hem_z": 2.10, "sleeve_z": 3.45, "collar": False},
            # polo: collar wings on the chest below the chin (the rest of the collar would be under the head), button placket
            "polo": {"item": "Polo", "offset": 0.025, "hem_z": 2.10, "sleeve_z": 3.45, "collar": True,
                     # wing rows (z, x inner, x outer), top to tip
                     "wing": [(4.035, 0.03, 0.34), (3.92, 0.06, 0.30), (3.80, 0.13, 0.18)],
                     "placket": (3.55, 4.0, 0.055), "buttons": [3.68, 3.86]},
        },
        "outer": {
            "jacket_open": {
                "offset": 0.065, "thickness": 0.02, "sleeve_offset": 0.06, "open_x": 0.27,
                "hem_z": 2.0, "sleeve_end_z": 2.43, "lapels": True, "placket": True, "placket_lower": False,
            },
            # hi-vis vest (drivers): no sleeves; `offset` at front/back, thinner at the sides where the
            # arms hang; reflective stripes (accent) around the torso
            "vest": {"offset": 0.07, "side_off": 0.04, "hem_z": 2.14, "stripes": [(2.50, 2.60), (2.82, 2.92)]},
        },
        "bottom": {
            "jeans": {"offset": 0.025, "turn_up": True, "cuff_z": (0.25, 0.35)},
        },
        "shoes": {
            "sneaker": {"offset": 0.025, "sole_h": 0.075, "stripe": True, "heel_tab": True},
        },
        "face": {
            # classic Roblox face with small modern touches. Positions are (x, z) on the head front
            # (x = left side of the character, z = height); head centre z 4.586, hairline ~4.98.
            "classic_smile": {
                # eyes: upright ovals (half width, half height), dome height; shine = white dot on top
                "eye": {"x": 0.165, "z": 4.69, "rx": 0.05, "rz": 0.085, "h": 0.022},
                "shine": {"dx": 0.016, "dz": 0.032, "r": 0.017, "h": 0.034},
                # brows: tube from the inner to the outer end, arched; radius per path point
                "brow": {"path": [(0.085, 4.835), (0.15, 4.862), (0.215, 4.865), (0.26, 4.845)],
                         "radii": [0.016, 0.024, 0.023, 0.013], "flat": 0.8},
                # nose: soft bump, its tip drops a little (reads from the side and in light)
                "nose": {"z": 4.565, "rx": 0.045, "rz": 0.06, "h": 0.045, "drop": 0.018},
                # mouth: smile line, `curve` = how much the corners rise
                "mouth": {"z": 4.40, "w": 0.15, "curve": 0.05, "r": 0.022, "flat": 0.65},
            },
            # extra pieces for women (used with the classic_smile eyes/nose/mouth): thinner, higher
            # brows and two lash flicks at the upper outer corner of each eye (angle from +x, length)
            "feminine": {
                "eye": {"x": 0.165, "z": 4.69, "rx": 0.05, "rz": 0.085},
                "brow": {"path": [(0.09, 4.85), (0.15, 4.88), (0.21, 4.885), (0.255, 4.862)],
                         "radii": [0.010, 0.016, 0.014, 0.008], "flat": 0.8},
                "lashes": [(20, 0.034), (45, 0.03)], "lash_r": 0.011,
            },
        },
        "hair": {
            "short_crop": {
                # angle from the front (deg) -> hairline z; mirrored to the right side
                "hairline": [(0, 4.98), (24, 4.96), (40, 4.90), (52, 4.76), (64, 4.74), (72, 4.56), (84, 4.56),
                             (92, 4.72), (120, 4.58), (150, 4.44), (180, 4.40)],
                "cols_a": [0, 24, 40, 52, 64, 72, 84, 92, 120, 150, 180],
                "rows": [0.0, 0.45, 1.0],
                "side_off": 0.035, "top_off": 0.07,
                "top_layer": {"cols": 16, "edge": [(0, 5.05), (45, 5.02), (90, 4.95), (135, 4.86), (180, 4.80)],
                              "zig": 0.035, "off": 0.09, "front_lift": 0.04},
                # optional swept-back locks on top: (angle from front, root z, sideways drift, width, lift)
                # e.g. [(-10, 5.03, -0.03, 0.12, 0.06), (11, 5.03, 0.04, 0.12, 0.05)] – off for the block look
                "locks": [],
            },
            # under hats: a thin cap of hair that never pokes through a hat
            "buzz": {
                "hairline": [(0, 4.97), (24, 4.95), (40, 4.90), (52, 4.76), (64, 4.74), (72, 4.56), (84, 4.56),
                             (92, 4.70), (120, 4.56), (150, 4.44), (180, 4.40)],
                "cols_a": "head",
                "rows": [0.0, 0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0],
                "side_off": 0.02, "top_off": 0.026,
            },
            # low ponytail out of the back of the head (for women under hats): path (y, z) + radii
            "tail": {"path": [(0.50, 4.64), (0.66, 4.56), (0.74, 4.36), (0.73, 4.14), (0.67, 4.0)],
                     "radii": [0.13, 0.14, 0.125, 0.095, 0.04], "flat": 0.9},
            # classic Usta moustache: thick over the upper lip, the ends droop past the mouth corners
            # (left half, x from the centre; mirrored)
            "mustache": {"path": [(0.0, 4.478), (0.06, 4.482), (0.12, 4.47), (0.17, 4.44), (0.20, 4.39), (0.21, 4.35)],
                         "radii": [0.030, 0.034, 0.032, 0.027, 0.020, 0.012], "flat": 0.75},
            # short full beard: shell over jaw and chin, up the sides to the sideburns, below the mouth
            # at the front. edge: angle from the front -> upper edge z; worn with the moustache
            "beard": {"cols": [-104, -92, -80, -66, -52, -38, -24, -12, 0, 12, 24, 38, 52, 66, 80, 92, 104],
                      "edge": [(0, 4.34), (13, 4.345), (22, 4.40), (34, 4.48), (50, 4.54), (66, 4.58), (80, 4.63), (92, 4.66)],
                      "rows": [0.0, 0.5, 1.0], "chin": [4.07, 4.02, 3.995],
                      "off": [0.012, 0.03, 0.038, 0.036, 0.025, 0.012], "inner": -0.012},
        },
        "accessory": {
            # bib apron: bib on the chest, straps over the shoulders down the back to the waist tie (bow),
            # skirt split per leg (front panels follow the legs when walking)
            "apron": {"offset": 0.05, "thickness": 0.02, "bib_top": 3.72, "bib_w": (0.62, 0.40),
                      "pocket": (2.95, 3.30, 0.24), "strap_x": 0.66, "strap_r": 0.04, "tie_z": (2.26, 2.36),
                      "skirt_w": 0.93, "skirt_z": 1.25},
            # disposable gloves (Glove, the hand) and the long cuff of rubber gloves (GloveCuff, forearm)
            "gloves": {"offset": 0.018, "cuff_z": 2.66},
            # held in the left hand by its back edge, clip at the front (not mirrored)
            "clipboard": {"board": ((1.5, -0.25, 1.70), (0.03, 0.5, 0.36)),
                          "paper": ((1.535, -0.27, 1.66), (0.008, 0.42, 0.30)),
                          "clip": ((1.5, -0.62, 2.04), (0.055, 0.11, 0.05))},
        },
    },
    # ---------------------------------------------------------------- variants (shared mesh set)
    # Extra pieces built for every NPC but hidden in renders: the game picks them per look
    # (Shared/CustomerLooks). kind = a garment type, "hair", "face" or "accessory"; colours as in the
    # NPC entries (materials from the NPC or from variant_materials). A piece the NPC already wears
    # is not built twice.
    "variants": [
        {"kind": "hair", "style": "buzz", "colors": {"main": "MAT_Hair"}},
        {"kind": "hair", "style": "tail", "colors": {"main": "MAT_Hair"}},
        {"kind": "face", "style": "feminine", "colors": {"brows": "MAT_Hair", "lashes": "MAT_Eyes"}},
        {"kind": "hair", "style": "mustache", "colors": {"main": "MAT_Hair"}},
        {"kind": "hair", "style": "beard", "colors": {"main": "MAT_Hair"}},
        {"kind": "top", "style": "tee", "colors": {"main": "MAT_Uniform"}},
        {"kind": "top", "style": "polo", "colors": {"main": "MAT_Polo", "accent": "MAT_Apron"}},
        {"kind": "outer", "style": "vest", "colors": {"main": "MAT_Vest", "accent": "MAT_Reflect"}},
        {"kind": "accessory", "style": "apron", "colors": {"main": "MAT_Apron"}},
        {"kind": "accessory", "style": "gloves", "colors": {"main": "MAT_Glove"}},
        {"kind": "accessory", "style": "clipboard", "colors": {"main": "MAT_Board", "paper": "MAT_Paper", "clip": "MAT_Metal"}},
    ],
    # materials of the variants (default colours; the game recolours every piece per look)
    "variant_materials": {
        "MAT_Uniform": ("#1E1E20", 0.95), "MAT_Polo": ("#2E2E30", 0.9), "MAT_Apron": ("#9A2E2B", 0.9),
        "MAT_Vest": ("#D9622B", 0.8), "MAT_Reflect": ("#C8CACC", 0.4), "MAT_Glove": ("#151516", 0.5),
        "MAT_Board": ("#7B5A3F", 0.7), "MAT_Paper": ("#EDE9E0", 0.9), "MAT_Metal": ("#B8BABD", 0.35),
    },
    # ---------------------------------------------------------------- NPCs
    "npcs": {
        "npc01": {
            "description": "Young city local ordering at the Döner shop",
            "materials": {  # name -> (hex colour, roughness)
                "MAT_Skin": ("#E8BE9C", 0.85),
                "MAT_Hair": ("#3B2A20", 0.9),
                "MAT_Top_Main": ("#6B6D70", 0.95),
                "MAT_Top_Accent": ("#8C2B2B", 0.95),
                "MAT_Jacket": ("#5A3E2B", 0.6),
                "MAT_Pants": ("#2F3B52", 0.95),
                "MAT_Shoes": ("#B8BABD", 0.9),
                "MAT_Shoes_Sole": ("#EDE9E0", 0.9),
                "MAT_Eyes": ("#231B17", 0.4),
                "MAT_EyeShine": ("#FFFFFF", 0.3),
                "MAT_Mouth": ("#5A2A24", 0.7),
            },
            "skin": "MAT_Skin",
            "clothing": [
                {"type": "top", "style": "hoodie", "enabled": True,
                 "colors": {"main": "MAT_Top_Main", "accent": "MAT_Top_Accent"}},
                {"type": "outer", "style": "jacket_open", "enabled": True,
                 "colors": {"main": "MAT_Jacket"}},
                {"type": "bottom", "style": "jeans", "enabled": True,
                 "colors": {"main": "MAT_Pants"}},
                {"type": "shoes", "style": "sneaker", "enabled": True,
                 "colors": {"main": "MAT_Shoes", "sole": "MAT_Shoes_Sole", "accent": "MAT_Top_Accent"}},
            ],
            "face": {"style": "classic_smile", "enabled": True,
                     "colors": {"eyes": "MAT_Eyes", "shine": "MAT_EyeShine", "brows": "MAT_Hair",
                                "nose": "MAT_Skin", "mouth": "MAT_Mouth"}},
            "hair": {"style": "short_crop", "enabled": True, "colors": {"main": "MAT_Hair"}},
            "accessories": [],
        },
        # check renders of the work clothes (the game builds staff from the npc01 set + variants)
        "staff01": {
            "description": "Kebab carver: work tee, apron, gloves, moustache",
            "materials": {
                "MAT_Skin": ("#C08A62", 0.85), "MAT_Hair": ("#151516", 0.9), "MAT_Pants": ("#232325", 0.95),
                "MAT_Shoes": ("#151516", 0.9), "MAT_Shoes_Sole": ("#2E2E30", 0.9), "MAT_Eyes": ("#231B17", 0.4),
                "MAT_EyeShine": ("#FFFFFF", 0.3), "MAT_Mouth": ("#5A2A24", 0.7),
            },
            "skin": "MAT_Skin",
            "clothing": [
                {"type": "top", "style": "tee", "enabled": True, "colors": {"main": "MAT_Uniform"}},
                {"type": "bottom", "style": "jeans", "enabled": True, "colors": {"main": "MAT_Pants"}},
                {"type": "shoes", "style": "sneaker", "enabled": True,
                 "colors": {"main": "MAT_Shoes", "sole": "MAT_Shoes_Sole", "accent": "MAT_Shoes"}},
            ],
            "face": {"style": "classic_smile", "enabled": True,
                     "colors": {"eyes": "MAT_Eyes", "shine": "MAT_EyeShine", "brows": "MAT_Hair",
                                "nose": "MAT_Skin", "mouth": "MAT_Mouth"}},
            "hair": {"style": "short_crop", "enabled": True, "colors": {"main": "MAT_Hair"}},
            "accessories": [],
            "extras": [
                {"kind": "accessory", "style": "apron", "colors": {"main": "MAT_Apron"}},
                {"kind": "accessory", "style": "gloves", "colors": {"main": "MAT_Glove"}},
                {"kind": "hair", "style": "mustache", "colors": {"main": "MAT_Hair"}},
            ],
        },
        "manager01": {
            "description": "Shift manager: polo, clipboard, beard",
            "materials": {
                "MAT_Skin": ("#E8BE9C", 0.85), "MAT_Hair": ("#5A3E2B", 0.9), "MAT_Pants": ("#2F3B52", 0.95),
                "MAT_Shoes": ("#151516", 0.9), "MAT_Shoes_Sole": ("#2E2E30", 0.9), "MAT_Eyes": ("#231B17", 0.4),
                "MAT_EyeShine": ("#FFFFFF", 0.3), "MAT_Mouth": ("#5A2A24", 0.7),
            },
            "skin": "MAT_Skin",
            "clothing": [
                {"type": "top", "style": "polo", "enabled": True, "colors": {"main": "MAT_Polo", "accent": "MAT_Apron"}},
                {"type": "bottom", "style": "jeans", "enabled": True, "colors": {"main": "MAT_Pants"}},
                {"type": "shoes", "style": "sneaker", "enabled": True,
                 "colors": {"main": "MAT_Shoes", "sole": "MAT_Shoes_Sole", "accent": "MAT_Shoes"}},
            ],
            "face": {"style": "classic_smile", "enabled": True,
                     "colors": {"eyes": "MAT_Eyes", "shine": "MAT_EyeShine", "brows": "MAT_Hair",
                                "nose": "MAT_Skin", "mouth": "MAT_Mouth"}},
            "hair": {"style": "short_crop", "enabled": True, "colors": {"main": "MAT_Hair"}},
            "accessories": [],
            "extras": [
                {"kind": "accessory", "style": "clipboard", "colors": {"main": "MAT_Board", "paper": "MAT_Paper", "clip": "MAT_Metal"}},
                {"kind": "hair", "style": "beard", "colors": {"main": "MAT_Hair"}},
                {"kind": "hair", "style": "mustache", "colors": {"main": "MAT_Hair"}},
            ],
        },
        "driver01": {
            "description": "Delivery driver: tee, hi-vis vest, rubber gloves",
            "materials": {
                "MAT_Skin": ("#9C6B48", 0.85), "MAT_Hair": ("#2B1E16", 0.9), "MAT_Shirt": ("#6B6D70", 0.95),
                "MAT_Pants": ("#2E2E30", 0.95), "MAT_Shoes": ("#5A3E2B", 0.9), "MAT_Shoes_Sole": ("#2E2E30", 0.9),
                "MAT_Eyes": ("#231B17", 0.4), "MAT_EyeShine": ("#FFFFFF", 0.3), "MAT_Mouth": ("#5A2A24", 0.7),
                "MAT_Rubber": ("#D9A93A", 0.5),
            },
            "skin": "MAT_Skin",
            "clothing": [
                {"type": "top", "style": "tee", "enabled": True, "colors": {"main": "MAT_Shirt"}},
                {"type": "outer", "style": "vest", "enabled": True, "colors": {"main": "MAT_Vest", "accent": "MAT_Reflect"}},
                {"type": "bottom", "style": "jeans", "enabled": True, "colors": {"main": "MAT_Pants"}},
                {"type": "shoes", "style": "sneaker", "enabled": True,
                 "colors": {"main": "MAT_Shoes", "sole": "MAT_Shoes_Sole", "accent": "MAT_Shoes"}},
            ],
            "face": {"style": "classic_smile", "enabled": True,
                     "colors": {"eyes": "MAT_Eyes", "shine": "MAT_EyeShine", "brows": "MAT_Hair",
                                "nose": "MAT_Skin", "mouth": "MAT_Mouth"}},
            "hair": {"style": "short_crop", "enabled": True, "colors": {"main": "MAT_Hair"}},
            "accessories": [],
            "extras": [
                {"kind": "accessory", "style": "gloves", "colors": {"main": "MAT_Rubber"}},
            ],
        },
    },
}
NO_MIRROR = {"Clipboard", "ClipboardPaper", "ClipboardClip"}  # one-handed items (built for the left hand)

R15_PARTS = [
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
# R15 Motor6D names and parents (joint name == motor name)
R15_MOTORS = {
    "LowerTorso": ("Root", "HumanoidRootPart"), "UpperTorso": ("Waist", "LowerTorso"),
    "Head": ("Neck", "UpperTorso"),
    "LeftUpperArm": ("LeftShoulder", "UpperTorso"), "LeftLowerArm": ("LeftElbow", "LeftUpperArm"),
    "LeftHand": ("LeftWrist", "LeftLowerArm"),
    "RightUpperArm": ("RightShoulder", "UpperTorso"), "RightLowerArm": ("RightElbow", "RightUpperArm"),
    "RightHand": ("RightWrist", "RightLowerArm"),
    "LeftUpperLeg": ("LeftHip", "LowerTorso"), "LeftLowerLeg": ("LeftKnee", "LeftUpperLeg"),
    "LeftFoot": ("LeftAnkle", "LeftLowerLeg"),
    "RightUpperLeg": ("RightHip", "LowerTorso"), "RightLowerLeg": ("RightKnee", "RightUpperLeg"),
    "RightFoot": ("RightAnkle", "RightLowerLeg"),
}
TYPE_COLLECTION = {"top": "Clothing_Top", "outer": "Clothing_Top", "bottom": "Clothing_Bottom",
                   "shoes": "Clothing_Shoes", "face": "Face", "hair": "Hair", "accessory": "Accessories"}

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TAU = 2.0 * math.pi
D = math.radians
Z = Vector((0, 0, 1))


# ===========================================================================
# Small helpers
# ===========================================================================
def se(t, e):
    """Superellipse term: sign(t) * |t|^(2/e)."""
    return math.copysign(abs(t) ** (2.0 / e), t)


def interp(table, x):
    """Piecewise-linear lookup in [(x, y), ...] sorted by x, clamped at both ends."""
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def bump(x, c, w):
    return math.exp(-((x - c) / w) ** 2)


def hex_to_linear(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb) + (1.0,)


def circle(center, r, n, ry=None, phase=0.0):
    cx, cy, cz = center
    ry = r if ry is None else ry
    return [Vector((cx + r * math.cos(phase + TAU * i / n), cy + ry * math.sin(phase + TAU * i / n), cz)) for i in range(n)]


def front_angle(prof, s, x, off, side=1):
    """Angle on a profile whose surface point has |x| == x on the front (left or right side)."""
    _, ru, _, _, cu, _, e = prof.params(s)
    c = min(1.0, max(0.0, (x - cu) / (ru + off))) ** (e / 2.0)
    th = -math.acos(c)
    return th if side > 0 else math.pi - th


def box_rings(b):
    """Rounded box -> superellipse rings (z, r_x, r_front, r_back, cx, cy, e), bottom to top."""
    hx, hyf, hyb = b["half"]
    zb, zt = b["z"]
    cx, cy = b["c"]
    e, bev, taper, plug = b["e"], b["bevel"], b.get("taper", 1.0), b.get("plug", {})
    scale = lambda z: taper + (1.0 - taper) * max(0.0, min(1.0, (z - zb) / (zt - zb)))
    ring = lambda z, inset, sc: (z, hx * sc - inset, hyf * sc - inset, hyb * sc - inset, cx, cy, e)
    rings = []
    if "bottom" in plug:
        rings.append(ring(zb - plug["bottom"], 0.1, scale(zb)))
    rings += [ring(zb, bev, scale(zb)), ring(zb + bev, 0.0, scale(zb + bev)),
              ring(zt - bev, 0.0, 1.0), ring(zt, bev, 1.0)]
    if "top" in plug:
        rings.append(ring(zt + plug["top"], 0.1, 1.0))
    return rings


# ===========================================================================
# Geometry core
# ===========================================================================
class Profile:
    """Body part surface: a stack of superellipse rings along Z (see CONFIG)."""

    def __init__(self, spec):
        self.spec = spec
        self.n = spec["n"]
        self.phase = D(spec.get("phase", 0.0))
        self.box = spec.get("box")
        self.rings = sorted(box_rings(self.box) if self.box else spec["rings"], key=lambda r: r[0])

    @property
    def stations(self):
        return [r[0] for r in self.rings]

    @property
    def zb(self):
        return self.box["z"][0] if self.box else self.stations[0]

    @property
    def zt(self):
        return self.box["z"][1] if self.box else self.stations[-1]

    @property
    def full(self):
        """(lowest, highest) station with the full, un-bevelled cross-section."""
        bev = self.box["bevel"] if self.box else 0.0
        return self.zb + bev, self.zt - bev

    def params(self, s):
        rs = self.rings
        if s <= rs[0][0]:
            return rs[0]
        for a, b in zip(rs, rs[1:]):
            if s <= b[0]:
                t = (s - a[0]) / (b[0] - a[0])
                return tuple(a[k] + (b[k] - a[k]) * t for k in range(7))
        return rs[-1]

    def u_of(self, s):
        st = self.stations
        if s <= st[0]:
            return 0.0
        for i in range(len(st) - 1):
            if s <= st[i + 1]:
                return i + (s - st[i]) / (st[i + 1] - st[i])
        return float(len(st) - 1)

    def s_of(self, u):
        st = self.stations
        i = max(0, min(int(u), len(st) - 2))
        return st[i] + (st[i + 1] - st[i]) * (u - i)

    def point(self, s, th, off=0.0):
        _, ru, rn, rp, cu, cv, e = self.params(s)
        c, sn = math.cos(th), math.sin(th)
        return Vector((cu + se(c, e) * (ru + off), cv + se(sn, e) * ((rp if sn >= 0 else rn) + off), s))

    def center(self, s):
        p = self.params(s)
        return Vector((p[4], p[5], s))

    def angles(self):
        return [self.phase + TAU * i / self.n for i in range(self.n)]

    def ring(self, s, off=0.0, mod=None, z=None):
        """Ring at station s (inflated by off). z places the same cross-section at another height."""
        pts = [self.point(s, th, off + (mod(s, th) if mod else 0.0)) for th in self.angles()]
        if z is not None:
            for p in pts:
                p.z = z
        return pts

    def pole(self, end, off=0.0):
        """Pole point just beyond the first (end=0) or last (end=1) ring."""
        cap = CONFIG["body"]["cap"] + off
        st = self.stations
        return self.center(st[0]) - Z * cap if end == 0 else self.center(st[-1]) + Z * cap

    def front(self, s, x, off=0.0):
        """Point on the front face at height s and horizontal position x (sign = side)."""
        return self.point(s, front_angle(self, s, abs(x), off, 1 if x >= 0 else -1), off)


class MB:
    """Minimal mesh builder: vertices + quad/tri faces. Every shape it makes is closed."""

    def __init__(self):
        self.v, self.f = [], []

    def add(self, pts):
        i0 = len(self.v)
        self.v.extend(Vector(p) for p in pts)
        return list(range(i0, len(self.v)))

    def bridge(self, a, b, closed=True):
        n = len(a)
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            self.f.append((a[i], a[j], b[j], b[i]))

    def fan(self, ring, center):
        c = self.add([center])[0]
        n = len(ring)
        for i in range(n):
            self.f.append((ring[i], ring[(i + 1) % n], c))

    def loft(self, rings, cap0=None, cap1=None):
        idx = [self.add(r) for r in rings]
        for a, b in zip(idx, idx[1:]):
            self.bridge(a, b)
        if cap0 is not None:
            self.fan(idx[0], cap0)
        if cap1 is not None:
            self.fan(idx[-1], cap1)

    def slab(self, outer, inner, wrap=False):
        """Closed solid between two point grids (rows x cols): patches, shells, strips."""
        O = [self.add(r) for r in outer]
        I = [self.add(r) for r in inner]
        R, C = len(O), len(O[0])
        for r in range(R - 1):
            self.bridge(O[r], O[r + 1], wrap)
            self.bridge(I[r + 1], I[r], wrap)
        self.bridge(I[0], O[0], wrap)
        self.bridge(O[-1], I[-1], wrap)
        if not wrap:
            for c in (0, C - 1):
                self.bridge([O[r][c] for r in range(R)], [I[r][c] for r in range(R)], closed=False)

    def sweep(self, path, radii, n, sx=1.0, sy=1.0, ref=Z, phase=0.0):
        """Tube along a path. sy scales the 'up' axis of the cross-section, sx the side axis."""
        rings, tans = [], []
        for k, p in enumerate(path):
            t = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
            b = t.cross(ref)
            if b.length < 1e-6:
                b = t.cross(Vector((1, 0, 0)))
            b.normalize()
            up = b.cross(t).normalized()
            r = radii[k]
            rings.append([p + up * (math.cos(phase + TAU * i / n) * r * sy) + b * (math.sin(phase + TAU * i / n) * r * sx)
                          for i in range(n)])
            tans.append(t)
        self.loft(rings, path[0] - tans[0] * radii[0] * 0.6, path[-1] + tans[-1] * radii[-1] * 0.6)

    def band(self, rings):
        """Closed ring solid: consecutive rings bridged, the last one back to the first (e.g. inner /
        outer / outer / inner = a flat band with a rectangular cross-section around a body part)."""
        idx = [self.add(r) for r in rings]
        for a, b in zip(idx, idx[1:] + idx[:1]):
            self.bridge(a, b)


def rbox(c, half, e=8.0, bevel=0.012, n=16):
    """Rounded box around centre c with half sizes (x, y, z) – props like the clipboard."""
    prof = Profile({"n": n, "phase": 180.0 / n, "box": {"half": (half[0], half[1], half[1]), "e": e, "bevel": bevel,
                                                         "z": (c[2] - half[2], c[2] + half[2]), "c": (c[0], c[1])}})
    mb = MB()
    mb.loft([prof.ring(s) for s in prof.stations], prof.pole(0), prof.pole(1))
    return mb



# ===========================================================================
# Scene objects
# ===========================================================================
P = {}  # part name -> Profile (left / centre parts only)


def load_profiles():
    P.clear()
    for name, spec in CONFIG["body"]["parts"].items():
        P[name] = Profile(spec)


def joint_pos(part):
    """World position of the joint that drives `part` (right side mirrored)."""
    side = -1 if part.startswith("Right") else 1
    left = part.replace("Right", "Left", 1)
    jname = CONFIG["body"]["parts"][left]["joint"]
    x, y, z = CONFIG["body"]["joints"][jname]
    return Vector((x * side, y, z))


def get_collection(name, parent=None):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(coll)
    return coll


def make_object(name, mb, part, material=None, collection="Base_R15", side=1, props=None):
    origin = joint_pos(part)
    verts = [(v.x * side - origin.x, v.y - origin.y, v.z - origin.z) for v in mb.v]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], mb.f)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.set_sharp_from_angle(angle=D(CONFIG["smooth_angle"]))
    if material is not None:
        me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    ob.location = origin
    coll = collection if isinstance(collection, bpy.types.Collection) else get_collection(collection)
    coll.objects.link(ob)
    ob["r15_part"] = part
    for k, v in (props or {}).items():
        ob[k] = v
    return ob


def emit(pieces, collection, colors, props=None):
    """pieces: [(item, part, MB, role)] – parts named Left* are mirrored to Right* automatically."""
    made = []
    for item, part, mb, role in pieces:
        if not mb.f:
            continue
        mat = bpy.data.materials.get(colors[role])
        mirror = part.startswith("Left") and item not in NO_MIRROR
        sides = [(part, 1)] + ([(part.replace("Left", "Right", 1), -1)] if mirror else [])
        for pname, side in sides:
            made.append(make_object(f"{item}_{pname}", mb, pname, mat, collection, side, props))
    return made


# ===========================================================================
# STEP 1 – scene, units, collections
# ===========================================================================
def step1_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"  # 1 Blender unit = 1 stud
    scene.unit_settings.scale_length = 1.0
    for name in CONFIG["collections"]:
        get_collection(name)
    load_profiles()


# ===========================================================================
# STEP 2 – R15 base body
# ===========================================================================
def body_part_mb(name):
    prof = P[name]
    mb = MB()
    mb.loft([prof.ring(s) for s in prof.stations], prof.pole(0), prof.pole(1))
    return mb


def step2_base_body(skin=None):
    for part in R15_PARTS:
        mb = body_part_mb(part.replace("Right", "Left", 1))
        make_object(f"Body_{part}", mb, part, skin, "Base_R15", -1 if part.startswith("Right") else 1, {"layer": "base"})


# ===========================================================================
# STEP 3 – materials
# ===========================================================================
def make_material(name, hex_color, roughness):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    rgba = hex_to_linear(hex_color)
    mat.diffuse_color = rgba
    mat.roughness = roughness
    mat.metallic = 0.0
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = 0.0
    mat["hex"] = hex_color
    return mat


def step3_materials(npc):
    for name, (hex_color, rough) in {**CONFIG["variant_materials"], **npc["materials"]}.items():
        make_material(name, hex_color, rough)
    skin = bpy.data.materials[npc["skin"]]
    for ob in get_collection("Base_R15").objects:
        ob.data.materials.clear()
        ob.data.materials.append(skin)


# ===========================================================================
# STEP 4 – clothing
# ===========================================================================
CTX = {"torso_outer": 0.03}
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))


def lip(prof, s, off, depth):
    """Turn a garment edge inwards: [edge ring at `off`] + a shallow pole inside the body.
    depth > 0 points up (use at a lower edge), < 0 down (upper edge)."""
    return [prof.ring(s, off)], prof.center(s + depth * 0.5)


def open_columns(prof, s_ref, x_open, off):
    """Angles for an open-front shell: the body's own ring angles between the two front edges."""
    th_e = front_angle(prof, s_ref, x_open, off, 1)
    inner = sorted(((a + math.pi / 2) % TAU) - math.pi / 2 for a in prof.angles())
    return [a for a in inner if th_e + 0.03 < a < math.pi - th_e - 0.03]


def _top_hoodie(p):
    o = p["offset"]
    UT, LT, UA, LA = P["UpperTorso"], P["LowerTorso"], P["LeftUpperArm"], P["LeftLowerArm"]
    top = UT.zt
    pieces = []

    # --- UpperTorso: body + neckline around the head (main), pocket, hood / cords + lining (accent)
    mb, acc = MB(), MB()
    neck = [circle((0, 0, top + 0.02), 0.50, UT.n, phase=UT.phase), circle((0, 0, top - 0.01), 0.40, UT.n, phase=UT.phase)]
    mb.loft([UT.ring(s, o) for s in UT.stations] + neck, UT.pole(0, o), Vector((0, 0, top - 0.05)))
    if p["pocket"]:
        rows = [(2.47, 0.46), (2.84, 0.36)]
        xs = lambda w: [-w + 2 * w * j / 3 for j in range(4)]
        mb.slab([[UT.front(s, x, o + 0.016) for x in xs(w)] for s, w in rows],
                [[UT.front(s, x, o - 0.01) for x in xs(w)] for s, w in rows])
    if p["drawstrings"]:
        for x in (0.14, -0.14):
            path = [UT.front(top - d, x, o + 0.012) for d in (0.0, 0.12, 0.26, 0.38)]
            acc.sweep(path, [0.02, 0.02, 0.02, 0.028], 4, ref=X)
    if p["hood"]:
        # hood worn down: a soft rim around the head base + a flat hood lying on the back
        base, rr, K = CTX["torso_outer"], p["rim_r"], 7
        t0, t1 = D(-90 + p["hood_open_deg"]), D(270 - p["hood_open_deg"])
        ang = [t0 + (t1 - t0) * k / (K - 1) for k in range(K)]
        R, zr = 0.58 + rr + 0.04, top + base + rr * 0.6
        rim = [Vector((R * math.cos(a), R * math.sin(a), zr)) for a in ang]
        mb.sweep(rim, [rr * (0.5 + 0.5 * math.sin(math.pi * k / (K - 1)) ** 0.5) for k in range(K)], 6)
        rings = []
        for dz, hw, t in p["hood_bag"]:
            z = top + dz
            y0 = UT.point(z, D(90), base).y - 0.005
            rings.append([Vector((hw * se(math.cos(TAU * i / 8), 3.0), y0 + t + t * se(math.sin(TAU * i / 8), 2.0), z))
                          for i in range(8)])
        dz0, _, t0_ = p["hood_bag"][0]
        dz1, _, t1_ = p["hood_bag"][-1]
        mb.loft(rings, Vector((0, UT.point(top + dz0, D(90), base).y + t0_, top + dz0 + 0.03)),
                Vector((0, UT.point(top + dz1, D(90), base).y + t1_, top + dz1 - 0.02)))
        if p["lining"]:
            lin = [Vector(((R - rr * 0.45) * math.cos(a), (R - rr * 0.45) * math.sin(a), zr + rr * 0.45)) for a in ang[1:-1]]
            acc.sweep(lin, [rr * 0.45] * len(lin), 4, sy=0.7, phase=D(45))
    pieces += [("Hoodie", "UpperTorso", mb, "main"), ("HoodieAccent", "UpperTorso", acc, "accent")]

    # --- LowerTorso: down to the rib band (main) + rib band (accent)
    mb, acc = MB(), MB()
    band_top = p["hem_z"] + p["band_h"]
    lo, cap0 = lip(LT, band_top, -0.01, 0.06)
    mb.loft(lo + [LT.ring(band_top, o), LT.ring(LT.full[1], o), LT.ring(LT.zt + 0.03, o - 0.012)],
            cap0, LT.center(LT.zt + 0.03))
    acc.loft([LT.ring(band_top + 0.01, o + 0.004), LT.ring(p["hem_z"], o + 0.012), LT.ring(p["hem_z"], -0.01)],
             LT.center(band_top + 0.02), LT.center(p["hem_z"] + 0.02))
    pieces += [("Hoodie", "LowerTorso", mb, "main"), ("HoodieAccent", "LowerTorso", acc, "accent")]

    # --- sleeves (main) and rib cuffs (accent)
    mb = MB()
    mb.loft([UA.ring(s, o) for s in UA.stations], UA.pole(0, o), UA.pole(1, o))
    pieces.append(("Hoodie", "LeftUpperArm", mb, "main"))
    mb, acc = MB(), MB()
    cuff_top = p["cuff_z"] + p["cuff_h"]
    lo, cap0 = lip(LA, cuff_top, -0.01, 0.06)
    mb.loft(lo + [LA.ring(cuff_top, o)] + [LA.ring(s, o) for s in LA.stations if s > cuff_top], cap0, LA.pole(1, o))
    acc.loft([LA.ring(cuff_top + 0.01, o + 0.006), LA.ring(p["cuff_z"], o + 0.012), LA.ring(p["cuff_z"], -0.01)],
             LA.center(cuff_top + 0.02), LA.center(p["cuff_z"] + 0.02))
    pieces += [("Hoodie", "LeftLowerArm", mb, "main"), ("HoodieAccent", "LeftLowerArm", acc, "accent")]
    return pieces


def _outer_jacket_open(p):
    o, t, xo = p["offset"], p["thickness"], p["open_x"]
    UT, LT, UA, LA = P["UpperTorso"], P["LowerTorso"], P["LeftUpperArm"], P["LeftLowerArm"]
    top = UT.zt
    pieces = []

    def shell(prof, rows, off_out, off_in, neck=None):
        interior = open_columns(prof, rows[-1], xo, off_out(rows[-1]))
        cols = lambda s, off: [front_angle(prof, s, xo, off, 1)] + interior + [front_angle(prof, s, xo, off, -1)]
        outer = [[prof.point(s, a, off_out(s)) for a in cols(s, off_out(s))] for s in rows]
        inner = [[prof.point(s, a, off_in(s)) for a in cols(s, off_out(s))] for s in rows]
        if neck:  # extra row that closes the shoulders around the head
            r, z = neck
            a0 = math.acos(min(1.0, (xo + 0.06) / r))
            span = [-a0 + (math.pi + 2 * a0) * j / (len(outer[0]) - 1) for j in range(len(outer[0]))]
            outer.append([Vector((r * math.cos(a), r * math.sin(a), z)) for a in span])
            inner.append([Vector((r * math.cos(a), r * math.sin(a), z - t)) for a in span])
        mb = MB()
        mb.slab(outer, inner)
        return mb

    # --- UpperTorso shell (closes over the shoulders), lapels, plackets
    rows = [s for s in UT.stations if s >= UT.zb]
    mb = shell(UT, rows, lambda s: o, lambda s: o - t, neck=(0.64, top + 0.075))
    if p["placket"]:
        for sgn in (1, -1):
            xs = [sgn * xo, sgn * (xo + 0.045)]
            mb.slab([[UT.front(s, x, o + 0.01) for x in xs] for s in rows],
                    [[UT.front(s, x, o - t - 0.004) for x in xs] for s in rows])
    if p["lapels"]:
        lrows = [(3.40, 0.01), (3.72, 0.12), (top - 0.02, 0.19)]
        for sgn in (1, -1):
            mb.slab([[UT.front(s, sgn * (xo + w * k), o + 0.024 - 0.008 * k) for k in (0, 1)] for s, w in lrows],
                    [[UT.front(s, sgn * (xo + w * k), o + 0.004) for k in (0, 1)] for s, w in lrows])
    pieces.append(("Jacket", "UpperTorso", mb, "main"))

    # --- LowerTorso shell (tucks under the UpperTorso piece at the top)
    rows = [p["hem_z"]] + [s for s in LT.stations if p["hem_z"] < s < LT.zt] + [LT.zt + 0.02]
    tuck = lambda s: -0.012 if s > LT.zt else 0.0
    mb = shell(LT, rows, lambda s: o + tuck(s), lambda s: o - t + tuck(s))
    if p["placket"] and p["placket_lower"]:
        for sgn in (1, -1):
            xs = [sgn * xo, sgn * (xo + 0.045)]
            mb.slab([[LT.front(s, x, o + 0.01) for x in xs] for s in rows[:-1]],
                    [[LT.front(s, x, o - t - 0.004) for x in xs] for s in rows[:-1]])
    pieces.append(("Jacket", "LowerTorso", mb, "main"))

    # --- sleeves (end above the hoodie cuff, with a slightly thicker sleeve band)
    so = p["sleeve_offset"]
    mb = MB()
    mb.loft([UA.ring(s, so) for s in UA.stations], UA.pole(0, so), UA.pole(1, so))
    pieces.append(("Jacket", "LeftUpperArm", mb, "main"))
    mb = MB()
    e = p["sleeve_end_z"]
    lo, cap0 = lip(LA, e, so - 0.018, 0.06)
    mb.loft(lo + [LA.ring(e, so + 0.008), LA.ring(e + 0.08, so + 0.008)]
            + [LA.ring(s, so) for s in LA.stations if s > e + 0.1], cap0, LA.pole(1, so))
    pieces.append(("Jacket", "LeftLowerArm", mb, "main"))
    return pieces


def _bottom_jeans(p):
    o = p["offset"]
    LT, UL, LL = P["LowerTorso"], P["LeftUpperLeg"], P["LeftLowerLeg"]
    pieces = []
    for item, prof in (("LowerTorso", LT), ("LeftUpperLeg", UL)):
        mb = MB()
        mb.loft([prof.ring(s, o) for s in prof.stations], prof.pole(0, o), prof.pole(1, o))
        pieces.append(("Pants", item, mb, "main"))

    # --- LowerLeg with a turned-up cuff that overlaps the shoe
    mb = MB()
    full = LL.full[0]
    z0, z1 = p["cuff_z"]
    if p["turn_up"]:
        bottom = [LL.ring(full, -0.01, z=z0), LL.ring(full, o + 0.025, z=z0),
                  LL.ring(full, o + 0.025, z=z1), LL.ring(full, o, z=z1)]
    else:
        bottom = [LL.ring(full, -0.01, z=z0), LL.ring(full, o, z=z0)]
    mb.loft(bottom + [LL.ring(s, o) for s in LL.stations if s > z1], LL.center(z0 + 0.04), LL.pole(1, o))
    pieces.append(("Pants", "LeftLowerLeg", mb, "main"))
    return pieces


def _shoes_sneaker(p):
    o, h = p["offset"], p["sole_h"]
    F = P["LeftFoot"]
    full = (F.full[0] + F.full[1]) / 2
    upper, sole, acc = MB(), MB(), MB()

    # --- upper: the foot block, standing in the sole
    collar = F.zt + 0.05
    upper.loft([F.ring(full, o, z=h - 0.02)] + [F.ring(s, o) for s in F.stations if h < s < F.zt]
               + [F.ring(full, o, z=collar), F.ring(full, -0.02, z=collar)], F.center(h - 0.03), F.center(collar - 0.03))

    # --- sole: slightly wider band with rounded edges
    sole.loft([F.ring(full, o - 0.004, z=0.0), F.ring(full, o + 0.018, z=0.012),
               F.ring(full, o + 0.018, z=h), F.ring(full, o + 0.004, z=h + 0.01)],
              F.center(0.0) - Z * 0.005, F.center(h + 0.01))

    # --- red accent: stripe on the outer side, rising to the front; pull tab at the heel
    if p["stripe"]:
        cols = [D(a) for a in (35, 15, -5, -25, -45)]  # back -> front along the outer side
        rise = [0.0, 0.012, 0.025, 0.04, 0.055]
        lo_z, hi_z = h + 0.025, h + 0.06
        acc.slab([[F.point(z + r, a, o + 0.008) for a, r in zip(cols, rise)] for z in (lo_z, hi_z)],
                 [[F.point(z + r, a, o - 0.006) for a, r in zip(cols, rise)] for z in (lo_z, hi_z)])
    if p["heel_tab"]:
        y = F.point(0.1, D(90), o).y + 0.008
        cx = F.center(0.1).x
        acc.sweep([Vector((cx, y, h + 0.01)), Vector((cx, y + 0.004, h + 0.06)), Vector((cx, y + 0.006, h + 0.11))],
                  [0.05, 0.05, 0.045], 4, sx=0.22, sy=1.0, ref=X, phase=D(45))
    return [("Shoe", "LeftFoot", upper, "main"), ("ShoeSole", "LeftFoot", sole, "sole"),
            ("ShoeAccent", "LeftFoot", acc, "accent")]


def fz(prof, z, x, off, s=None):
    """Point on the front at horizontal position x with the cross-section of station s (default: z,
    clamped to the full, un-bevelled part) placed at height z – flat panels that ignore the bevels."""
    lo, hi = prof.full
    pt = prof.front(min(hi, max(lo, z)) if s is None else s, x, off)
    pt.z = z
    return pt


def _top_shirt(p):
    """Short-sleeved work shirt (tee / polo), worn over the jeans like the hoodie. The polo adds
    collar wings below the chin and a button placket with buttons (accent)."""
    o, item = p["offset"], p["item"]
    UT, LT, UA = P["UpperTorso"], P["LowerTorso"], P["LeftUpperArm"]
    top = UT.zt
    pieces = []

    # --- UpperTorso: closed around the neck like the hoodie
    mb, acc = MB(), MB()
    neck = [circle((0, 0, top + 0.02), 0.50, UT.n, phase=UT.phase), circle((0, 0, top - 0.01), 0.40, UT.n, phase=UT.phase)]
    mb.loft([UT.ring(s, o) for s in UT.stations] + neck, UT.pole(0, o), Vector((0, 0, top - 0.05)))
    if p["collar"]:
        rows = p["wing"]
        for sgn in (1, -1):
            mb.slab([[UT.front(z, sgn * x, o + 0.022) for x in (x0, x1)] for z, x0, x1 in rows],
                    [[UT.front(z, sgn * x, o + 0.004) for x in (x0, x1)] for z, x0, x1 in rows])
        z0, z1, w = p["placket"]
        zs = [z0, (z0 + z1) / 2, z1]
        mb.slab([[UT.front(z, x, o + 0.01) for x in (-w, w)] for z in zs],
                [[UT.front(z, x, o - 0.006) for x in (-w, w)] for z in zs])
        for z in p["buttons"]:
            c = UT.front(z, 0.0, o + 0.006)
            acc.sweep([c, c + Vector((0, -0.016, 0))], [0.022, 0.022], 8, ref=X)
    pieces += [(item, "UpperTorso", mb, "main"), (item + "Accent", "UpperTorso", acc, "accent")]

    # --- LowerTorso: down to a plain hem over the jeans
    mb = MB()
    hem = p["hem_z"]
    lo, cap0 = lip(LT, hem, -0.01, 0.06)
    mb.loft(lo + [LT.ring(hem, o + 0.006), LT.ring(hem + 0.04, o)]
            + [LT.ring(s, o) for s in LT.stations if hem + 0.05 < s <= LT.full[1]] + [LT.ring(LT.zt + 0.03, o - 0.012)],
            cap0, LT.center(LT.zt + 0.03))
    pieces.append((item, "LowerTorso", mb, "main"))

    # --- short sleeve with a slightly thicker hem
    mb = MB()
    e = p["sleeve_z"]
    lo, cap0 = lip(UA, e, -0.01, 0.06)
    mb.loft(lo + [UA.ring(e, o + 0.008), UA.ring(e + 0.05, o + 0.008)] + [UA.ring(s, o) for s in UA.stations if s > e + 0.07],
            cap0, UA.pole(1, o))
    pieces.append((item, "LeftUpperArm", mb, "main"))
    return pieces


def _outer_vest(p):
    """Hi-vis vest over a shirt: no sleeves, `offset` at front and back but only side_off at the
    sides (the arms hang there), reflective stripes (accent) around the torso."""
    UT, LT = P["UpperTorso"], P["LowerTorso"]
    top, side = UT.zt, p["side_off"]
    extra = p["offset"] - side
    mod = lambda s, th: extra * abs(math.sin(th))

    # --- UpperTorso: from the waist over the shoulders; the neck opening is hidden by the head
    mb, acc = MB(), MB()
    rows = [UT.ring(s, side, mod) for s in UT.stations if UT.zb <= s < UT.zt]
    neck = [circle((0, 0, top + 0.05), 0.56, UT.n, phase=UT.phase), circle((0, 0, top), 0.46, UT.n, phase=UT.phase)]
    mb.loft([UT.ring(UT.zb, side - 0.03)] + rows + [UT.ring(UT.zt, side, mod, z=top + 0.035)] + neck,
            UT.center(UT.zb + 0.05), Vector((0, 0, top - 0.05)))
    for z0, z1 in p["stripes"]:
        acc.band([UT.ring(z0, side - 0.004, mod), UT.ring(z0, side + 0.012, mod),
                  UT.ring(z1, side + 0.012, mod), UT.ring(z1, side - 0.004, mod)])
    pieces = [("Vest", "UpperTorso", mb, "main"), ("VestStripe", "UpperTorso", acc, "accent")]

    # --- LowerTorso: down to the hem (tucks under the UpperTorso piece at the top)
    mb = MB()
    hem = p["hem_z"]
    mb.loft([LT.ring(hem, -0.01), LT.ring(hem, side + 0.004, mod)]
            + [LT.ring(s, side, mod) for s in LT.stations if hem + 0.03 < s <= LT.full[1]]
            + [LT.ring(LT.zt + 0.04, side - 0.01, mod)], LT.center(hem + 0.03), LT.center(LT.zt + 0.04))
    pieces.append(("Vest", "LowerTorso", mb, "main"))
    return pieces


STYLES = {
    ("top", "hoodie"): _top_hoodie,
    ("top", "tee"): _top_shirt,
    ("top", "polo"): _top_shirt,
    ("outer", "jacket_open"): _outer_jacket_open,
    ("outer", "vest"): _outer_vest,
    ("bottom", "jeans"): _bottom_jeans,
    ("shoes", "sneaker"): _shoes_sneaker,
}


def build_clothing(item_type, style, colors, params=None):
    """Build one garment from the base-body measurements. New garments = new STYLES entries;
    new variants of a garment = new parameter sets in CONFIG["styles"]."""
    p = dict(CONFIG["styles"][item_type][style])
    p.update(params or {})
    pieces = STYLES[(item_type, style)](p)
    parent = get_collection(TYPE_COLLECTION[item_type])
    item_names = sorted({item for item, *_ in pieces})
    coll = get_collection(f"{item_type.capitalize()}_{style}", parent)
    return emit(pieces, coll, colors, {"layer": item_type, "style": style, "items": ",".join(item_names)})


def step4_clothing(npc):
    tops = [c for c in npc["clothing"] if c["enabled"] and c["type"] in ("top", "outer")]
    CTX["torso_outer"] = max([CONFIG["styles"][c["type"]][c["style"]]["offset"] for c in tops] + [0.0])
    order = {"bottom": 0, "shoes": 1, "top": 2, "outer": 3}
    for item in sorted(npc["clothing"], key=lambda c: order.get(c["type"], 9)):
        if item["enabled"]:
            build_clothing(item["type"], item["style"], item["colors"], item.get("params"))


# ===========================================================================
# STEP 5 – face, hair, accessories
# ===========================================================================
def head_front(x, z, off=0.0):
    """Point on the front of the head *mesh* (the faceted ring, not the ideal cylinder) at (x, z),
    pushed out by `off` along the smooth normal. Valid on the straight part of the head."""
    H = P["Head"]
    r = H.params(z)[1]
    pts = [H.point(z, a) for a in H.angles()]
    for a, b in zip(pts, pts[1:] + pts[:1]):
        if a.y < 0 and b.y < 0 and min(a.x, b.x) <= x <= max(a.x, b.x) and a.x != b.x:
            p = a.lerp(b, (x - a.x) / (b.x - a.x))
            break
    else:
        raise ValueError(f"x={x} is not on the head front")
    sx = max(-1.0, min(1.0, x / r))
    return p + Vector((sx, -math.sqrt(1.0 - sx * sx), 0.0)) * off


def face_dome(mb, cx, cz, rx, rz, h, base=-0.012, drop=0.0, n=12, k=3):
    """Oval dome on the head front: outline (rx, rz) around (cx, cz), height h, sunk to `base` so no
    gap shows on the faceted head. `drop` moves the top down (nose tip)."""
    ring = lambda s, off, dz: [head_front(cx + rx * s * math.cos(TAU * i / n), cz + rz * s * math.sin(TAU * i / n) - dz, off)
                               for i in range(n)]
    rings = [ring(1.0, base, 0.0)]
    for j in range(k):
        phi = (math.pi / 2) * j / k
        rings.append(ring(math.cos(phi), h * math.sin(phi), drop * j / k))
    mb.loft(rings, head_front(cx, cz, base - 0.006), head_front(cx, cz - drop, h))


def face_tube(mb, pts, radii, flat):
    """Tube along (x, z) points on the head front, half sunk; `flat` squashes it towards the head."""
    mb.sweep([head_front(x, z) for x, z in pts], radii, 6, sx=flat, sy=1.0)


def _face_classic_smile(p):
    eyes, shine, brows, nose, mouth = MB(), MB(), MB(), MB(), MB()
    e, sh, b = p["eye"], p["shine"], p["brow"]
    for sgn in (1, -1):
        face_dome(eyes, sgn * e["x"], e["z"], e["rx"], e["rz"], e["h"])
        # shine: same corner on both eyes (one light source), poking out of the eye dome
        face_dome(shine, sgn * e["x"] + sh["dx"], e["z"] + sh["dz"], sh["r"], sh["r"], sh["h"], base=0.0, n=8, k=2)
        face_tube(brows, [(sgn * x, z) for x, z in b["path"]], b["radii"], b["flat"])
    n = p["nose"]
    face_dome(nose, 0.0, n["z"], n["rx"], n["rz"], n["h"], drop=n["drop"], k=4)
    m = p["mouth"]
    xs = [m["w"] * (-1 + 2 * i / 8) for i in range(9)]
    radii = [m["r"] * (0.45 + 0.55 * math.sin(math.pi * i / 8) ** 0.6) for i in range(9)]
    face_tube(mouth, [(x, m["z"] + m["curve"] * (x / m["w"]) ** 2) for x in xs], radii, m["flat"])
    return [("Eyes", "Head", eyes, "eyes"), ("EyeShine", "Head", shine, "shine"), ("Brows", "Head", brows, "brows"),
            ("Nose", "Head", nose, "nose"), ("Mouth", "Head", mouth, "mouth")]


def _face_feminine(p):
    brows, lashes = MB(), MB()
    e, b = p["eye"], p["brow"]
    for sgn in (1, -1):
        face_tube(brows, [(sgn * x, z) for x, z in b["path"]], b["radii"], b["flat"])
        for a, length in p["lashes"]:
            c, s_ = math.cos(D(a)), math.sin(D(a))
            x0, z0 = e["x"] + e["rx"] * c * 0.9, e["z"] + e["rz"] * s_ * 0.9
            d = D(a + 18)
            pts = [(x0, z0), (x0 + length * 0.6 * math.cos(d), z0 + length * 0.6 * math.sin(d)),
                   (x0 + length * math.cos(d + 0.2), z0 + length * math.sin(d + 0.2))]
            face_tube(lashes, [(sgn * x, z) for x, z in pts], [p["lash_r"], p["lash_r"] * 0.8, p["lash_r"] * 0.4], 0.8)
    return [("BrowsThin", "Head", brows, "brows"), ("Lashes", "Head", lashes, "lashes")]


FACE_STYLES = {"classic_smile": _face_classic_smile, "feminine": _face_feminine}


def _hair_base_layer(mb, p):
    """Hair shell following the hairline, thin at the sides and a bit thicker on top."""
    H = P["Head"]
    u_top = len(H.stations) - 1
    top_pole = H.pole(1)

    def off_at(s):
        k = max(0.0, min(1.0, (s - 4.85) / 0.25))
        return p["side_off"] + (p["top_off"] - p["side_off"]) * k

    # base layer: short sides/back, follows the hairline. cols_a == "head": the head mesh's own
    # columns, so a very thin shell never cuts the faceted head (buzz cut)
    A = p["cols_a"]
    if A == "head":
        cols = [(th, abs(((math.degrees(th) + 90 + 180) % 360) - 180)) for th in H.angles()]
    else:
        cols = [(D(-90 + a), a) for a in A] + [(D(270 - a), a) for a in reversed(A[1:-1])]
    rings = []
    for f in p["rows"]:
        ring = []
        for th, a in cols:
            u = H.u_of(interp(p["hairline"], a))
            s = H.s_of(u + (u_top - u) * f)
            ring.append(H.point(s, th, off_at(s)))
        rings.append(ring)
    edge_in = [H.point(interp(p["hairline"], a), th, -0.012) for th, a in cols]
    mb.loft([edge_in] + rings, Vector((0, 0, 4.7)), top_pole + Z * p["top_off"] * 0.55)
    return off_at


def _hair_short_crop(p):
    H = P["Head"]
    mb = MB()
    u_top = len(H.stations) - 1
    top_pole = H.pole(1)
    off_at = _hair_base_layer(mb, p)

    # top layer: thicker, zig-zag edge = layered locks, lifted at the front
    tl = p["top_layer"]
    C = tl["cols"]
    rings_o, edge_in = [[], [], []], []
    for j in range(C):
        th = D(-90) + TAU * j / C
        a = abs(((math.degrees(th) + 90 + 180) % 360) - 180)  # angle from the front, 0..180
        z_edge = interp(tl["edge"], a) - (tl["zig"] if j % 2 else 0.0)
        u0 = H.u_of(z_edge)
        lift = tl["front_lift"] * max(0.0, 1 - a / 70.0)
        for r, f in enumerate((0.0, 0.5, 1.0)):
            s = H.s_of(u0 + (u_top - u0) * f)
            off = tl["off"] * (0.55 if r == 0 else 1.0) + lift * (0.4 if r == 0 else 1.0)
            rings_o[r].append(H.point(s, th, off))
        edge_in.append(H.point(z_edge, th, off_at(z_edge) - 0.01))
    mb.loft([edge_in] + rings_o, Vector((0, 0, 4.85)), top_pole + Z * tl["off"] * 0.55)

    # swept-back locks: flat tapered strands from the front over the top layer
    for a, z, drift, w, lift in p["locks"]:
        th = D(-90 + a)
        u0 = H.u_of(z)
        path = []
        for f in (0.0, 0.45, 0.85):
            s = H.s_of(u0 + (u_top - u0) * f)
            pt = H.point(s, th, tl["off"] + tl["front_lift"] * (1 - f) + lift * math.sin(math.pi * min(1.0, f * 1.4)))
            path.append(pt + Vector((drift * f, 0, 0)))
        mb.sweep(path, [w, w * 0.8, w * 0.2], 3, sx=1.0, sy=0.35, phase=D(90))
    return [("Hair", "Head", mb, "main")]


def _hair_buzz(p):
    mb = MB()
    _hair_base_layer(mb, p)
    return [("Buzz", "Head", mb, "main")]


def _hair_tail(p):
    mb = MB()
    mb.sweep([Vector((0, y, z)) for y, z in p["path"]], p["radii"], 8, sx=p["flat"], ref=X)
    return [("Tail", "Head", mb, "main")]


def _hair_mustache(p):
    half, r = p["path"], p["radii"]
    mb = MB()
    face_tube(mb, [(-x, z) for x, z in reversed(half[1:])] + list(half), list(reversed(r[1:])) + list(r), p["flat"])
    return [("Mustache", "Head", mb, "main")]


def _hair_beard(p):
    """Shell over the head mesh: from the upper edge (per column) down the straight part of the head
    and under the chin; thin at the edge so it blends into the skin."""
    H = P["Head"]
    z_base = H.stations[3]  # lower end of the straight part
    outer, inner = [], []
    for a in p["cols"]:
        th, ze = D(-90 + a), interp(p["edge"], abs(a))
        zs = [ze + (z_base - ze) * f for f in p["rows"]] + p["chin"]
        outer.append([H.point(z, th, off) for z, off in zip(zs, p["off"])])
        inner.append([H.point(z, th, p["inner"]) for z in zs])
    mb = MB()
    mb.slab([list(r) for r in zip(*outer)], [list(r) for r in zip(*inner)])  # rows x cols
    return [("Beard", "Head", mb, "main")]


HAIR_STYLES = {"short_crop": _hair_short_crop, "buzz": _hair_buzz, "tail": _hair_tail,
               "mustache": _hair_mustache, "beard": _hair_beard}


def _acc_apron(p):
    o, t = p["offset"], p["thickness"]
    UT, LT = P["UpperTorso"], P["LowerTorso"]
    top = UT.zt
    pieces = []

    # --- bib with a chest pocket, straps over the shoulders and down the back to the waist tie
    mb = MB()
    w0, w1 = p["bib_w"]
    rows = [2.32, 2.9, 3.4, p["bib_top"]]
    xs = lambda z: [(w0 + (w1 - w0) * (z - rows[0]) / (rows[-1] - rows[0])) * (-1 + 2 * j / 6) for j in range(7)]
    mb.slab([[fz(UT, z, x, o + t / 2) for x in xs(z)] for z in rows], [[fz(UT, z, x, o - t / 2) for x in xs(z)] for z in rows])
    z0, z1, w = p["pocket"]
    mb.slab([[fz(UT, z, x, o + t / 2 + 0.014) for x in (-w, 0, w)] for z in (z0, z1)],
            [[fz(UT, z, x, o) for x in (-w, 0, w)] for z in (z0, z1)])
    sx, r = p["strap_x"], p["strap_r"]
    for sgn in (1, -1):
        fr = lambda z, x: fz(UT, z, sgn * x, o + 0.005)
        bk = lambda z, x: (lambda v: Vector((v.x, -v.y, v.z)))(fr(z, x))
        path = [fr(p["bib_top"] - 0.04, w1 - 0.04), fr(3.95, sx - 0.06),
                Vector((sgn * sx, -0.50, top + 0.02)), Vector((sgn * sx, -0.15, top + 0.03)),
                Vector((sgn * sx, 0.15, top + 0.03)), Vector((sgn * sx, 0.50, top + 0.02)),
                bk(3.95, sx - 0.06), bk(3.2, sx - 0.12), bk(2.36, sx - 0.2)]
        mb.sweep(path, [r] * len(path), 6, sx=0.35, ref=X)
    pieces.append(("Apron", "UpperTorso", mb, "main"))

    # --- LowerTorso: waist tie all around with a bow at the back, top of the skirt at the front
    mb = MB()
    tz0, tz1 = p["tie_z"]
    mb.band([LT.ring(tz0, o - 0.012), LT.ring(tz0, o + 0.008), LT.ring(tz1, o + 0.008), LT.ring(tz1, o - 0.012)])
    W = p["skirt_w"]
    xs = [W * (-1 + 2 * j / 8) for j in range(9)]
    zs = [1.97, 2.12, 2.30]
    mb.slab([[fz(LT, z, x, o + t / 2, s=2.2) for x in xs] for z in zs], [[fz(LT, z, x, o - t / 2, s=2.2) for x in xs] for z in zs])
    yb = LT.point(2.3, D(90), o + 0.008).y + 0.012
    for sgn in (1, -1):
        loop = [Vector((sgn * x, yb, z)) for x, z in ((0.02, 2.30), (0.10, 2.37), (0.19, 2.34), (0.20, 2.27), (0.10, 2.25), (0.03, 2.29))]
        mb.sweep(loop, [0.022] * len(loop), 6, sy=0.45, ref=Y)
        tail = [Vector((sgn * x, yb, z)) for x, z in ((0.03, 2.28), (0.07, 2.12), (0.10, 1.98))]
        mb.sweep(tail, [0.03, 0.03, 0.026], 6, sy=0.35, ref=Y)
    mb.sweep([Vector((-0.04, yb, 2.30)), Vector((0.04, yb, 2.30))], [0.035, 0.035], 6, sy=0.6, ref=Y)
    pieces.append(("Apron", "LowerTorso", mb, "main"))

    # --- skirt below the hips: one panel per leg, same curve as the LowerTorso part
    mb = MB()
    xs = [0.004] + [W * j / 4 for j in range(1, 5)]
    zs = [2.03, 1.65, p["skirt_z"]]
    mb.slab([[fz(LT, z, x, o + t / 2, s=2.2) for x in xs] for z in zs], [[fz(LT, z, x, o - t / 2, s=2.2) for x in xs] for z in zs])
    pieces.append(("Apron", "LeftUpperLeg", mb, "main"))
    return pieces


def _acc_gloves(p):
    o = p["offset"]
    H, LA = P["LeftHand"], P["LeftLowerArm"]
    zt = H.zt
    mb = MB()
    mb.loft([H.ring(s, o) for s in H.stations if s < zt]
            + [H.ring(H.full[1], o + 0.012, z=zt + 0.02), H.ring(H.full[1], o + 0.012, z=zt + 0.07), H.ring(H.full[1], -0.01, z=zt + 0.07)],
            H.pole(0, o), H.center(zt + 0.03))
    cuff = MB()
    f, z0, z1 = LA.full[0], LA.zb - 0.02, p["cuff_z"]
    cuff.loft([LA.ring(f, o + 0.004, z=z0), LA.ring(f, o + 0.006, z=z1 - 0.07), LA.ring(f, o + 0.026, z=z1), LA.ring(f, -0.01, z=z1)],
              LA.center(z0) - Z * 0.02, LA.center(z1 - 0.04))
    return [("Glove", "LeftHand", mb, "main"), ("GloveCuff", "LeftLowerArm", cuff, "main")]


def _acc_clipboard(p):
    return [("Clipboard", "LeftHand", rbox(*p["board"]), "main"),
            ("ClipboardPaper", "LeftHand", rbox(*p["paper"], bevel=0.003), "paper"),
            ("ClipboardClip", "LeftHand", rbox(*p["clip"]), "clip")]


ACCESSORY_STYLES = {"apron": _acc_apron, "gloves": _acc_gloves, "clipboard": _acc_clipboard}


def build_piece(kind, style, colors, collection, props):
    """One configured piece of any kind (garment type, "hair", "face", "accessory"). Objects that
    already exist (the NPC wears the piece) are not built again."""
    if kind == "hair":
        build = HAIR_STYLES[style]
    elif kind == "face":
        build = FACE_STYLES[style]
    elif kind == "accessory":
        build = ACCESSORY_STYLES[style]
    else:
        build = STYLES[(kind, style)]
    p = {k: (dict(x) if isinstance(x, dict) else x) for k, x in CONFIG["styles"][kind][style].items()}
    pieces = [pc for pc in build(p) if f"{pc[0]}_{pc[1]}" not in bpy.data.objects]
    return emit(pieces, collection, colors, props)


def step5_head_hair(npc):
    face = npc.get("face")
    if face and face["enabled"]:
        p = {k: dict(v) for k, v in CONFIG["styles"]["face"][face["style"]].items()}
        for k, v in face.get("params", {}).items():
            p[k].update(v)
        emit(FACE_STYLES[face["style"]](p), get_collection("Face"), face["colors"], {"layer": "face", "style": face["style"]})
    hair = npc.get("hair")
    if hair and hair["enabled"]:
        p = dict(CONFIG["styles"]["hair"][hair["style"]])
        p.update(hair.get("params", {}))
        emit(HAIR_STYLES[hair["style"]](p), get_collection("Hair"), hair["colors"], {"layer": "hair", "style": hair["style"]})
    for x in npc.get("extras", []):  # further visible pieces of any kind (check renders of the variants)
        coll = get_collection(TYPE_COLLECTION.get(x["kind"], "Accessories"))
        build_piece(x["kind"], x["style"], x["colors"], coll, {"layer": x["kind"], "style": x["style"]})
    variants = get_collection("Variants")
    for v in CONFIG["variants"]:
        for ob in build_piece(v["kind"], v["style"], v["colors"], variants, {"layer": "variant", "style": v["style"]}):
            ob.hide_render = True
    for acc in npc.get("accessories", []):
        if acc.get("enabled", True):
            p = dict(CONFIG["styles"]["accessory"][acc["style"]])
            emit(ACCESSORY_STYLES[acc["style"]](p), get_collection("Accessories"), acc["colors"], {"layer": "accessory"})


# ===========================================================================
# STEP 6 – quality check + renders
# ===========================================================================
def mesh_objects():
    return sorted((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: (o.users_collection[0].name, o.name))


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def inspect_mesh(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    info = {
        "ngons": sum(1 for f in bm.faces if len(f.verts) > 4),
        "loose": sum(1 for v in bm.verts if not v.link_faces) + sum(1 for e in bm.edges if not e.link_faces),
        "non_manifold": sum(1 for e in bm.edges if not e.is_manifold),
        "doubles": len(bmesh.ops.find_doubles(bm, verts=bm.verts, dist=1e-5)["targetmap"]),
    }
    # outward normals: every connected island must enclose a positive volume
    seen, inward, islands = set(), 0, 0
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        islands += 1
        stack, vol = [f0], 0.0
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        if vol <= 0:
            inward += 1
    info["islands"], info["inward_islands"] = islands, inward
    bm.free()
    return info


def step6_check():
    expected_base = {f"Body_{p}" for p in R15_PARTS}
    rows, problems, total = [], [], 0
    for ob in mesh_objects():
        part = ob.get("r15_part")
        info = inspect_mesh(ob)
        tris = tri_count(ob)
        total += tris
        pivot_ok = part in R15_MOTORS and (Vector(ob.location) - joint_pos(part)).length < 1e-6
        rot_ok = all(abs(a) < 1e-9 for a in ob.rotation_euler)
        scale_ok = all(abs(s - 1.0) < 1e-9 for s in ob.scale)
        name_ok = ob.name == f"Body_{part}" if ob.users_collection[0].name == "Base_R15" else ob.name.endswith("_" + str(part))
        mats = [m.name for m in ob.data.materials if m]
        row = {"name": ob.name, "collection": ob.users_collection[0].name, "part": part, "tris": tris,
               "material": mats[0] if mats else None, **info}
        rows.append(row)
        for label, ok in (("name", name_ok), ("pivot", pivot_ok), ("rotation", rot_ok), ("scale", scale_ok),
                          ("one material", len(mats) == 1), ("ngons", info["ngons"] == 0), ("loose", info["loose"] == 0),
                          ("non-manifold", info["non_manifold"] == 0), ("doubles", info["doubles"] == 0),
                          ("normals", info["inward_islands"] == 0)):
            if not ok:
                problems.append(f"{ob.name}: {label}")
    missing = expected_base - {o.name for o in bpy.data.objects}
    problems += [f"missing base part {m}" for m in sorted(missing)]
    per_layer = {}
    for r in rows:
        per_layer[r["collection"]] = per_layer.get(r["collection"], 0) + r["tris"]
    return {"objects": rows, "total_tris": total, "per_collection": per_layer, "problems": problems,
            "materials": sorted({r["material"] for r in rows if r["material"]})}


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.1, 0.1, 0.1)
    sh.show_cavity = True
    sh.cavity_type = "WORLD"
    sh.show_specular_highlight = False
    scene.display.render_aa = "8"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.62, 0.64, 0.67)
    scene.render.resolution_percentage = 100
    cam = bpy.data.objects.get("CheckCam")
    if cam is None:
        cam = bpy.data.objects.new("CheckCam", bpy.data.cameras.new("CheckCam"))
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scene.camera = cam
    return cam


VIEWS = {
    "front": ((0, -20, 2.6), (0, 0, 2.6), 5.8),
    "side": ((20, 0, 2.6), (0, 0, 2.6), 5.8),
    "threeq": ((13, -15, 6.5), (0, 0, 2.6), 5.8),
    "back": ((0, 20, 2.6), (0, 0, 2.6), 5.8),
    "head_front": ((0, -20, 4.7), (0, 0, 4.7), 1.7),
    "head_threeq": ((12, -14, 7.0), (0, 0, 4.7), 1.7),
    "head_back": ((-10, 14, 6.0), (0, 0, 4.7), 1.7),
    "head_side": ((20, 0, 4.6), (0, 0, 4.6), 1.7),
    "feet": ((8, -12, 2.0), (0.0, -0.1, 0.3), 1.9),
    "shoe_side": ((20, -0.1, 0.25), (0.38, -0.1, 0.25), 1.1),
    "chest": ((6, -16, 4.0), (-0.3, 0, 3.6), 1.6),
    "hem": ((3, -16, 2.6), (0, 0, 2.25), 1.2),
    "hem_back": ((-6, 16, 2.6), (0.4, 0, 2.15), 1.2),
    "chest_back": ((-4, 16, 5.0), (0, 0, 3.6), 1.8),
}


def render_sheet(tag, views=("front", "side", "threeq", "back"), size=(560, 820)):
    import numpy as np

    scene = bpy.context.scene
    cam = setup_render()
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = size
    tiles = []
    for v in views:
        loc, target, scale = VIEWS[v]
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = scale
        path = os.path.join(OUT, "renders", f"_{v}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path, check_existing=False)
        arr = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
        tiles.append(arr)
        bpy.data.images.remove(img)
        os.remove(path)
    sheet = np.concatenate(tiles, axis=1)
    h, w = sheet.shape[:2]
    out = bpy.data.images.new(f"sheet_{tag}", w, h, alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(OUT, "renders", f"{tag}.png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    return os.path.join(OUT, "renders", f"{tag}.png")


# ===========================================================================
# STEP 7 – export preparation (nothing is exported here)
# ===========================================================================
FBX_SETTINGS = {
    "axis_forward": "-Z", "axis_up": "Y",
    "bake_space_transform": True,  # "Apply Transform"
    "global_scale": 1.0, "apply_unit_scale": True, "apply_scale_options": "FBX_SCALE_NONE",
    "object_types": {"MESH"}, "use_selection": True, "use_mesh_modifiers": True,
    "mesh_smooth_type": "FACE", "use_tspace": False, "use_custom_props": False,
    "add_leaf_bones": False, "bake_anim": False, "path_mode": "AUTO", "embed_textures": False,
}


def item_of(ob):
    return ob.name[:-len(ob["r15_part"]) - 1]


def export_fbx(filepath, run=False, items=None):
    """Select every mesh object (only those of `items` if given) and (only with run=True) write the
    FBX with FBX_SETTINGS."""
    for ob in bpy.data.objects:
        ob.select_set(ob.type == "MESH" and (items is None or item_of(ob) in items))
    if run:
        bpy.ops.export_scene.fbx(filepath=filepath, **FBX_SETTINGS)
    return filepath


def to_roblox(v):
    """Blender (x, y, z) -> Roblox, relative to the HumanoidRootPart centre, character facing -Z."""
    return (round(-v[0], 4), round(v[2] - CONFIG["hrp_height"], 4), round(v[1], 4))


def step7_export_prep(npc_key):
    rig = {"hrp": {"size": [2, 2, 1], "hip_height": CONFIG["hrp_height"] - 1.0}, "parts": {}, "attachments": {}}
    for part in R15_PARTS:
        motor, parent = R15_MOTORS[part]
        rig["parts"][part] = {"motor": motor, "parent": parent, "joint_blender": list(joint_pos(part)),
                              "joint_roblox": to_roblox(joint_pos(part))}
    for ob in mesh_objects():
        if ob.users_collection[0].name != "Base_R15":
            rig["attachments"][ob.name] = {"part": ob["r15_part"], "material": ob.data.materials[0].name}
    rig["fbx_settings"] = {k: (sorted(v) if isinstance(v, set) else v) for k, v in FBX_SETTINGS.items()}
    rig["fbx_path"] = os.path.join(OUT, f"{npc_key}.fbx")
    with open(os.path.join(OUT, f"{npc_key}_rig.json"), "w") as fh:
        json.dump(rig, fh, indent=1)
    export_fbx(rig["fbx_path"], run=False)
    return rig


# ===========================================================================
# Studio preview data (EditableMesh in Studio, no upload – see studio_preview.luau)
# ===========================================================================
STUDIO_CHUNK = 100_000  # characters of base64 per StringValue


def part_center(part):
    """Centre of an R15 body part's box (= the Roblox part's CFrame position), Blender world space."""
    prof = P[part.replace("Right", "Left", 1)]
    x, y = prof.rings[0][4], prof.rings[0][5]
    return Vector((-x if part.startswith("Right") else x, y, (prof.zb + prof.zt) / 2))


def export_studio(npc_key):
    """Compact mesh data per object, little-endian: u16 vertices, u16 triangles, per vertex i16x3
    position (1/2048 stud, Roblox axes, relative to the object's bounding-box centre) + i8x3 normal,
    per triangle u16x3. zstd + base64, split into out/studio/data/Data_NNN.txt + Manifest.json.
    Each object is placed by `offset`: its centre relative to the centre of its R15 part (Roblox
    axes), so it follows the part whatever joint layout the Roblox rig uses."""
    bpy.context.view_layer.update()  # matrix_world of freshly built objects
    rbx = lambda v: Vector((-v.x, v.z, v.y))
    folder, blob, parts = os.path.join(OUT, "studio"), bytearray(), []
    data_dir = os.path.join(folder, "data")
    os.makedirs(data_dir, exist_ok=True)
    for fn in os.listdir(data_dir):
        os.remove(os.path.join(data_dir, fn))
    for ob in mesh_objects():
        me = ob.data
        me.calc_loop_triangles()
        mw = ob.matrix_world
        nm = mw.to_3x3().inverted().transposed()
        world = [mw @ v.co for v in me.vertices]
        lo = Vector([min(p[i] for p in world) for i in range(3)])
        hi = Vector([max(p[i] for p in world) for i in range(3)])
        c = (lo + hi) / 2
        pts = [rbx(p - c) for p in world]
        verts, index, tris = [], {}, []
        for lt in me.loop_triangles:
            tri = []
            for li in lt.loops:
                vi = me.loops[li].vertex_index
                w = nm @ Vector(me.corner_normals[li].vector)
                n = Vector((-w.x, w.z, w.y)).normalized()
                key = (vi, round(n.x * 127), round(n.y * 127), round(n.z * 127))
                if key not in index:
                    index[key] = len(verts)
                    verts.append((pts[vi], key[1:]))
                tri.append(index[key])
            tris.append(tri)
        assert len(verts) < 65536, ob.name
        blob += struct.pack("<HH", len(verts), len(tris))
        for p, n in verts:
            blob += struct.pack("<hhhbbb", *(round(x * 2048) for x in p), *n)
        for t in tris:
            blob += struct.pack("<HHH", *t)
        mat = ob.data.materials[0]
        parts.append({"name": ob.name, "item": item_of(ob), "part": ob["r15_part"],
                      "color": mat.get("hex", "#FFFFFF"),
                      "size": [round(abs(x), 4) for x in rbx(hi - lo)],
                      "roughness": round(mat.roughness, 2),
                      "offset": [round(x, 4) for x in rbx(c - part_center(ob["r15_part"]))]})
    raw = os.path.join(folder, f"{npc_key}.bin")
    with open(raw, "wb") as fh:
        fh.write(blob)
    subprocess.run(["zstd", "-19", "-q", "-f", raw, "-o", raw + ".zst"], check=True)
    with open(raw + ".zst", "rb") as fh:
        text = base64.b64encode(fh.read()).decode()
    chunks = [text[i:i + STUDIO_CHUNK] for i in range(0, len(text), STUDIO_CHUNK)]
    for i, chunk in enumerate(chunks, 1):
        with open(os.path.join(data_dir, f"Data_{i:03d}.txt"), "w") as fh:
            fh.write(chunk)
    with open(os.path.join(folder, "Manifest.json"), "w") as fh:
        json.dump({"npc": npc_key, "chunks": len(chunks), "bytes": len(blob), "parts": parts}, fh, indent=1)
    return f"{len(parts)} objects, {len(blob) // 1024} KB raw, {len(text) // 1024} KB base64, {len(chunks)} chunk(s)"


# ===========================================================================
# Main
# ===========================================================================
def scene_summary():
    out = []
    for ob in mesh_objects():
        out.append(f"  {ob.users_collection[0].name:<22} {ob.name:<34} tris {tri_count(ob):>5}  "
                   f"pivot {tuple(round(c, 3) for c in ob.location)}  mat {ob.data.materials[0].name if ob.data.materials else '-'}")
    return "\n".join(out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--npc", default="npc01")
    ap.add_argument("--upto", type=int, default=7)
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--views", default="front,side,threeq,back")
    ap.add_argument("--tag", default=None)
    ap.add_argument("--studio", action="store_true")
    ap.add_argument("--fbx", action="store_true")
    ap.add_argument("--fbx-items", default=None, help="comma-separated items: only export these to the FBX")
    args = ap.parse_args(argv)
    npc = CONFIG["npcs"][args.npc]
    os.makedirs(OUT, exist_ok=True)

    step1_scene()
    print("STEP 1 ok: collections", [c.name for c in bpy.context.scene.collection.children], "units", bpy.context.scene.unit_settings.system)
    if args.upto >= 2:
        step2_base_body()
        print("STEP 2 ok: base body")
    if args.upto >= 3:
        step3_materials(npc)
        print("STEP 3 ok: materials", [m.name for m in bpy.data.materials])
    if args.upto >= 4:
        step4_clothing(npc)
        print("STEP 4 ok: clothing")
    if args.upto >= 5:
        step5_head_hair(npc)
        print("STEP 5 ok: face + hair")
    print(scene_summary())
    report = step6_check()
    print("TOTAL TRIS", report["total_tris"], "PER COLLECTION", report["per_collection"])
    print("PROBLEMS", report["problems"] or "none")
    if args.upto >= 6:
        with open(os.path.join(OUT, f"{args.npc}_report.json"), "w") as fh:
            json.dump(report, fh, indent=1)
    if args.upto >= 7:
        rig = step7_export_prep(args.npc)
        print("STEP 7 ok: rig table + FBX settings prepared (not exported):", rig["fbx_path"])
    if args.studio:
        print("STUDIO", export_studio(args.npc))
    if args.fbx:
        items = set(args.fbx_items.split(",")) if args.fbx_items else None
        print("FBX", export_fbx(os.path.join(OUT, f"{args.npc}.fbx"), run=True, items=items))
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"{args.npc}.blend"))
    if args.render:
        tag = args.tag or f"{args.npc}_step{args.upto}"
        print("RENDER", render_sheet(tag, tuple(args.views.split(","))))


if __name__ == "__main__":
    main()
