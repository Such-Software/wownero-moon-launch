"""Full-3D SpaceDoge — Shiba Inu astronaut, the MoonLaunch hero.

The 3D upgrade of art/characters/dialogue/spacedoge.svg, built with the such-graphics
PROCEDURAL-BLENDER contract (same as build_3d_sprout / build_3d_tomato): modeled
VOLUMES sitting proud of the head (no craters), ONE parametric mouth driven by the
shared A-H/X viseme table, everything parented to `root` so a head-bob moves the
whole face, EEVEE headless, env-driven (SG3D_CUES/OUT/DUR/RES).

Design: tan/doge-yellow rounded head, cream muzzle + dark nose, upright pointy ears,
a WHITE open-face helmet shell behind the head with a GOLD visor rim around the
opening, an orange chest panel. Cheeks are FLAT sculpted fur ruffs (thin, elongated,
angled) — deliberately NOT big round blush balls.

Run:
  Blender --background --python build_3d_spacedoge.py -- still
  Blender --background --python build_3d_spacedoge.py -- talk|alpha   (needs SG3D_CUES)
"""
import json
import math
import os
import sys
from pathlib import Path

import bpy

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from workspace_paths import marketing_run_root, such_graphics_source

# The such-graphics creature3d engine owns the articulated cupid's-bow bezier lips
# (real reshaping lips, not scaled pill-ellipsoids). Import it for the MOUTH only;
# all of the doge's own head/helmet/ear geometry below is unchanged.
sys.path.insert(0, str(such_graphics_source()))
from such_graphics import creature3d as c3d

SP = marketing_run_root() / "_procedural_3d"
MODE = sys.argv[-1] if sys.argv[-1] in ("still", "talk", "alpha", "hero") else "still"

DOGE = (0.90, 0.61, 0.27)        # doge-yellow / tan head
DOGE_D = (0.70, 0.45, 0.19)
RUFF = (0.94, 0.74, 0.44)        # lighter tan cheek ruff
CREAM = (0.97, 0.90, 0.77)       # muzzle
NOSE = (0.16, 0.11, 0.09)        # dark nose
DARK = (0.05, 0.04, 0.04)        # iris
WHITE = (0.98, 0.99, 0.99)
HELMET = (0.94, 0.96, 1.00)      # white helmet shell
GOLD = (0.86, 0.63, 0.19)        # visor rim
GOLD_D = (0.62, 0.42, 0.10)
ORANGE = (0.93, 0.52, 0.14)      # chest control panel
SUIT = (0.90, 0.92, 0.97)        # white spacesuit
LIP = (0.44, 0.27, 0.20)         # muted brown mouth rim
MOUTH_IN = (0.05, 0.03, 0.03)    # near-black cavity

# Viseme table + co-articulation blend come from the engine now: the 4-tuple
# (width, open, round, SMILE) table drives the bezier lips (rest X = a warm closed
# smile, not a flat line). Shared across the whole cast so it never drifts.
SHAPES = c3d.SHAPES
blended_params = c3d.blended_params
IDLE = 0.0        # this actor's bob/blink phase (doge leads)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for b in list(coll):
            coll.remove(b)


def mat(name, rgb, rough=0.5, sub=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    if sub > 0 and "Subsurface" in b.inputs:
        b.inputs["Subsurface"].default_value = sub
        if "Subsurface Color" in b.inputs:
            b.inputs["Subsurface Color"].default_value = (
                rgb[0] * 0.9 + 0.03, rgb[1] * 0.6, rgb[2] * 0.4, 1)
    return m


def sphere(name, loc, radii, rgb, rough=0.5, sub=0.0, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = radii
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat(name + "_m", rgb, rough, sub))
    if parent:
        o.parent = parent
    return o


def torus(name, loc, major, minor, rgb, rough=0.3, parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     location=loc, major_segments=40,
                                     minor_segments=12)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = (math.radians(90), 0, 0)   # ring opening faces camera (-Y)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat(name + "_m", rgb, rough))
    if parent:
        o.parent = parent
    return o


def build():
    clear()
    root = bpy.data.objects.new("root", None)
    bpy.context.collection.objects.link(root)

    # HELMET SHELL — a big white dome seated BEHIND + above the head (its near cap
    # sits behind the face front, so the face is open to camera). Reads as an
    # open-face astronaut helmet, opaque (robust on alpha film — no glass z-sort).
    sphere("helmet", (0, 0.82, 0.22), (1.46, 1.42, 1.52), HELMET, 0.18,
           parent=root)

    # SUIT — white shoulders below; an orange chest control panel + a light button
    sphere("suit", (0, 0.05, -2.15), (1.55, 1.0, 0.95), SUIT, 0.4, parent=root)
    sphere("collar", (0, -0.15, -1.30), (0.95, 0.55, 0.45), SUIT, 0.4, parent=root)
    sphere("chest", (0, -0.78, -1.70), (0.44, 0.22, 0.32), ORANGE, 0.45,
           parent=root)
    sphere("chest_btn", (0, -0.94, -1.66), (0.10, 0.06, 0.10),
           (0.99, 0.88, 0.72), 0.3, parent=root)

    # EARS — ONE upright pointy Shiba ear per side, poking out over the open helmet.
    # The dark inner ear is nested ON THE FRONT of the outer ear (same axis, smaller,
    # further forward) so it reads as inner-ear detail, NOT a second ear.
    for sx, sgn in ((-0.52, -1), (0.52, 1)):
        rot = (0, math.radians(18) * sgn, math.radians(6) * sgn)
        ear = sphere(f"ear_{sgn}", (sx, -0.28, 0.98), (0.22, 0.13, 0.52), DOGE,
                     0.5, parent=root)
        ear.rotation_euler = rot
        inr = sphere(f"ear_in_{sgn}", (sx, -0.37, 0.99), (0.105, 0.055, 0.31),
                     DOGE_D, 0.55, parent=root)
        inr.rotation_euler = rot

    # HEAD — rounded tan doge head (front is -Y)
    sphere("head", (0, 0, 0), (1.06, 0.94, 1.02), DOGE, 0.5, sub=0.05, parent=root)

    # EYES — set high-ish on the face; dark glossy iris + a bright glint
    eyes = []
    for sx, nm in ((-0.38, "eye_l"), (0.38, "eye_r")):
        e = sphere(nm, (sx, -0.82, 0.20), (0.23, 0.25, 0.27), WHITE, 0.28,
                   parent=root)
        sphere(nm + "_iris", (sx, -1.00, 0.19), (0.145, 0.145, 0.15), DARK,
               0.2, parent=root)
        sphere(nm + "_glint", (sx - 0.055 * (sx / abs(sx)), -1.08, 0.28),
               (0.055, 0.055, 0.06), WHITE, 0.1, parent=root)
        eyes.append(e)

    # BROWS — small friendly tan bars, barely angled (doge is soft, not stern)
    for sx, rz in ((-0.38, 0.06), (0.38, -0.06)):
        b = sphere(f"brow_{sx}", (sx, -0.95, 0.52), (0.15, 0.05, 0.045), DOGE_D,
                   0.5, parent=root)
        b.rotation_euler = (0, rz, 0)

    # CHEEK RUFFS — FLAT sculpted fur tufts (thin in depth, elongated + angled),
    # low + outside the muzzle. Deliberately not spherical blush balls.
    for sx, sgn in ((-0.66, -1), (0.66, 1)):
        r = sphere(f"ruff_{sgn}", (sx, -0.50, -0.16), (0.17, 0.085, 0.36), RUFF,
                   0.6, parent=root)
        r.rotation_euler = (0, math.radians(20) * sgn, math.radians(24) * sgn)

    # MUZZLE — cream ellipsoid proud on the lower face; dark nose on its top
    sphere("muzzle", (0, -0.52, -0.20), (0.60, 0.60, 0.48), CREAM, 0.42,
           sub=0.05, parent=root)
    sphere("nose", (0, -1.06, 0.05), (0.17, 0.13, 0.12), NOSE, 0.25, parent=root)

    # HELMET RIM — a GOLD visor rim ringing the open face + a thin white seal
    torus("visor_rim", (0, -0.18, 0.12), 1.16, 0.065, GOLD, 0.28, parent=root)
    torus("visor_seal", (0, -0.02, 0.10), 1.14, 0.03, HELMET, 0.3, parent=root)

    mouth = build_mouth(root)
    return dict(root=root, eyes=eyes, mouth=mouth)


MOUTH_CENTER = (0, -1.02, -0.52)   # on the muzzle, matching the old cavity anchor
DOG_LIP = (0.12, 0.075, 0.065)     # thin DARK muzzle lip line (the dog "flews")
TONGUE = (0.83, 0.40, 0.42)        # pink tongue

# A DOG mouth, not human lips. Modeled at half-width DOG_BX: a WIDE upper flews line
# that HUMPS up either side of a soft centre PHILTRUM dip (the classic dog/"3"/omega
# upper lip), and a lower jaw edge. Animals talk by dropping the JAW, so the upper
# barely moves and the lower drops — very different from the tomato's symmetric
# cupid's-bow. (x, y, z, per-point radius that tapers to points at the corners.)
DOG_BX = 0.24
DOG_UPPER = [(-0.24, -0.005, 0.000, 0.16), (-0.145, -0.028, 0.052, 0.55),
             (-0.055, -0.033, 0.030, 0.42), (0.0, -0.030, 0.014, 0.30),
             (0.055, -0.033, 0.030, 0.42), (0.145, -0.028, 0.052, 0.55),
             (0.24, -0.005, 0.000, 0.16)]
DOG_LOWER = [(-0.205, -0.005, -0.010, 0.15), (-0.10, -0.03, -0.040, 0.44),
             (0.0, -0.038, -0.052, 0.55), (0.10, -0.03, -0.040, 0.44),
             (0.205, -0.005, -0.010, 0.15)]


def build_mouth(root):
    """A shiba MUZZLE mouth: thin dark upper flews (wide, philtrum-dipped) + a lower
    jaw that drops open, a dark cavity, and a pink tongue that rises into view when
    the jaw opens. Uses the engine's bezier_tube primitive but dog-shaped profiles +
    a jaw-drop driver (set_mouth), NOT the human cupid's-bow lips."""
    m = c3d._empty("mouth", MOUTH_CENTER, root)
    interior = sphere("mouth_in", (0, 0.03, 0), (0.17, 0.05, 0.05), MOUTH_IN, 1.0,
                      parent=m)
    tongue = sphere("tongue", (0, 0.01, -0.04), (0.12, 0.04, 0.03), TONGUE, 0.5,
                    parent=m)
    up = c3d.bezier_tube("lip_up", DOG_UPPER, 0.015, DOG_LIP, m)
    lo = c3d.bezier_tube("lip_lo", DOG_LOWER, 0.016, DOG_LIP, m)
    return dict(kind="dog", root=m, interior=interior, tongue=tongue, up=up, lo=lo,
                _center=MOUTH_CENTER)


def set_mouth(rig, p):
    """Drive the dog muzzle from (width, open, round, smile). The upper flews barely
    move (a small smile curl); the JAW (lower lip) drops for open visemes, growing a
    dark cavity with the tongue rising into it. Round narrows the mouth (dogs don't
    pucker human-style)."""
    width, opn, rnd, smile = (list(p) + [0, 0, 0, 0])[:4]
    m = rig["mouth"]
    sx = (0.92 + 0.16 * width) * (1.0 - rnd * 0.30)   # wide; narrows a touch on round
    drop = 0.02 + 0.42 * opn                          # jaw drop
    c3d._shape_lip(m["up"], DOG_UPPER, sx, 0.006 * opn, smile * 0.6, 0.0, 1.0)
    c3d._shape_lip(m["lo"], DOG_LOWER, sx, -drop, smile * 0.25, rnd * 0.03,
                   1.0 - opn * 0.08)
    m["interior"].scale = (0.15 * sx + 0.02, 0.05, max(0.02, drop * 0.85))
    m["tongue"].scale = (0.11 * sx, 0.04, 0.02 + 0.05 * opn)
    m["tongue"].location = (0, 0.01, -drop * 0.42)


def set_blink(rig, k):
    for e in rig["eyes"]:
        e.scale = (0.23, 0.25, max(0.02, 0.27 * k))


def lights_and_cam():
    # SG3D_CLOSEUP pushes the camera in on the face (longer lens = flatter, flattering)
    # for a solo HOOK shot; the default is the wide duo framing (unchanged).
    if os.environ.get("SG3D_CLOSEUP"):
        _cam_loc, _lens = (0, -6.1, 0.12), 90.0   # ears in frame, flatter lens
    else:
        _cam_loc, _lens = (0, -8.6, -0.10), 50.0
    bpy.ops.object.camera_add(location=_cam_loc,
                              rotation=(math.radians(90), 0, 0))
    bpy.context.scene.camera = bpy.context.active_object
    bpy.context.scene.camera.data.lens = _lens
    bpy.ops.object.light_add(type="AREA", location=(-3.4, -4.2, 4.2))
    k = bpy.context.active_object
    k.data.energy = 1150
    k.data.size = 4.5
    k.data.color = (1.0, 0.96, 0.88)
    k.data.use_contact_shadow = True
    bpy.ops.object.light_add(type="AREA", location=(4.2, -3.2, 1.0))
    f = bpy.context.active_object
    f.data.energy = 130
    f.data.size = 6
    f.data.color = (0.82, 0.90, 1.0)
    bpy.ops.object.light_add(type="AREA", location=(1.5, 4.0, 4.5))
    r = bpy.context.active_object
    r.data.energy = 700
    r.data.size = 4
    r.data.color = (1.0, 0.94, 0.86)
    r.data.use_contact_shadow = True
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    ev = sc.eevee
    ev.use_gtao = True
    ev.gtao_distance = 0.5
    ev.gtao_factor = 1.1
    if hasattr(ev, "use_soft_shadows"):
        ev.use_soft_shadows = True
    if hasattr(ev, "shadow_cube_size"):
        ev.shadow_cube_size = "2048"
    if MODE == "alpha":
        res = os.environ.get("SG3D_RES", "620x820").split("x")
        sc.render.resolution_x, sc.render.resolution_y = int(res[0]), int(res[1])
        sc.render.film_transparent = True
    elif MODE == "talk":
        sc.render.resolution_x, sc.render.resolution_y = 560, 740
    else:
        sc.render.resolution_x, sc.render.resolution_y = 620, 820
    if hasattr(sc.eevee, "use_ssr"):
        sc.eevee.use_ssr = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.11, 0.16, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.35


def main():
    SP.mkdir(parents=True, exist_ok=True)
    rig = build()
    set_mouth(rig, SHAPES["X"])
    lights_and_cam()
    sc = bpy.context.scene
    total = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print(f"RESULT built {total} faces")

    if MODE == "still":
        for vis in ("X", "A", "B", "C", "D", "F"):
            set_mouth(rig, SHAPES[vis])
            sc.render.filepath = str(SP / f"doge3d_v_{vis}.png")
            bpy.ops.render.render(write_still=True)
            print(f"RESULT wrote doge3d_v_{vis}.png")
        return

    cues = json.load(open(os.environ["SG3D_CUES"]))["cues"]
    fps = 30
    _dur = os.environ.get("SG3D_DUR")
    dur = float(_dur) if _dur else (max(c["end"] for c in cues) + 0.4)
    outdir = Path(os.environ.get("SG3D_OUT",
                  str(SP / ("_3dframes_doge_alpha" if MODE == "alpha" else "_3dframes_doge"))))
    outdir.mkdir(parents=True, exist_ok=True)
    for f in outdir.glob("*.png"):
        f.unlink()
    n = int(dur * fps)
    for i in range(n):
        t = i / fps
        set_mouth(rig, blended_params(t, cues))
        ph = (t + 3.4 * 0.45 + IDLE) % 3.4 / 3.4
        set_blink(rig, 0.1 if ph < 0.035 else 1.0)
        rig["root"].location = (0, 0, math.sin((t + IDLE) * 2.1) * 0.035)
        rig["root"].rotation_euler = (0, 0, math.sin((t + IDLE) * 1.3) * 0.04)
        sc.render.filepath = str(outdir / f"f_{i:05d}.png")
        bpy.ops.render.render(write_still=True)
    print(f"RESULT rendered {n} frames -> {outdir.name}")


main()
