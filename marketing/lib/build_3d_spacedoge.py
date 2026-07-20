"""Full-3D SpaceDoge — Shiba Inu astronaut, the MoonLaunch hero.

The 3D upgrade of marketing/characters/spacedoge.svg, built with the such-graphics
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

SP = Path("/private/tmp/claude-501/-Users-johnmurphy-src-WowneroMoonLaunch/"
          "0801bcd3-399b-4237-b990-4df8be9a0d81/scratchpad")
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

#            width open round teeth tongue bite  (full 6, shared A-H/X table)
SHAPES = {
    "A": (1.00, 0.02, 0.00, 0, 0, 0), "B": (0.95, 0.22, 0.00, 1, 0, 0),
    "C": (0.86, 0.50, 0.14, 1, 0, 0), "D": (0.74, 0.95, 0.18, 0, 1, 0),
    "E": (0.60, 0.44, 0.58, 0, 0, 0), "F": (0.40, 0.30, 0.95, 0, 0, 0),
    "G": (0.90, 0.18, 0.00, 0, 0, 1), "H": (0.78, 0.48, 0.10, 0, 1, 0),
    "X": (0.88, 0.00, 0.00, 0, 0, 0),
}
BLEND = 0.06
IDLE = 0.0        # this actor's bob/blink phase (doge leads)


def blended_params(t, cues):
    for i, c in enumerate(cues):
        if c["start"] <= t < c["end"]:
            a = SHAPES.get(c["value"], SHAPES["X"])
            since = t - c["start"]
            if since < BLEND and i > 0:
                b = SHAPES.get(cues[i - 1]["value"], SHAPES["X"])
                k = since / BLEND
                return tuple(b[j] + (a[j] - b[j]) * k for j in range(6))
            return a
    return SHAPES["X"]


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
    # a soft highlight streak up-left on the dome
    sphere("helmet_hi", (-0.62, -0.30, 1.15), (0.34, 0.10, 0.20),
           (1.0, 1.0, 1.0), 0.1, parent=root)

    # SUIT — white shoulders below; an orange chest control panel + a light button
    sphere("suit", (0, 0.05, -2.15), (1.55, 1.0, 0.95), SUIT, 0.4, parent=root)
    sphere("collar", (0, -0.15, -1.30), (0.95, 0.55, 0.45), SUIT, 0.4, parent=root)
    sphere("chest", (0, -0.78, -1.70), (0.44, 0.22, 0.32), ORANGE, 0.45,
           parent=root)
    sphere("chest_btn", (0, -0.94, -1.66), (0.10, 0.06, 0.10),
           (0.99, 0.88, 0.72), 0.3, parent=root)

    # EARS — upright pointy Shiba ears on top, poking out over the open helmet.
    # Elongated tapered spheres tilted outward; a dark inner ear proud in front.
    for sx, sgn in ((-0.52, -1), (0.52, 1)):
        ear = sphere(f"ear_{sgn}", (sx, -0.28, 0.98), (0.22, 0.13, 0.52), DOGE,
                     0.5, parent=root)
        ear.rotation_euler = (0, math.radians(18) * sgn, math.radians(6) * sgn)
        inr = sphere(f"ear_in_{sgn}", (sx * 1.02, -0.40, 0.94),
                     (0.11, 0.07, 0.32), DOGE_D, 0.55, parent=root)
        inr.rotation_euler = (0, math.radians(18) * sgn, math.radians(6) * sgn)

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


def build_mouth(root):
    """A clean dark cavity on the muzzle that reshapes per viseme, framed by a thin
    muted-brown upper + lower lip that PART with the jaw. The muzzle is the
    character; the cavity does the talking. No teeth, no stacked pancakes."""
    m = bpy.data.objects.new("mouth", None)
    m.location = (0, -1.02, -0.52)
    bpy.context.collection.objects.link(m)
    m.parent = root
    interior = sphere("mouth_in", (0, 0.02, 0), (0.20, 0.05, 0.09), MOUTH_IN,
                      1.0, parent=m)
    up = sphere("lip_up", (0, -0.03, 0.10), (0.22, 0.05, 0.035), LIP, 0.4,
                parent=m)
    lo = sphere("lip_lo", (0, -0.03, -0.10), (0.21, 0.05, 0.045), LIP, 0.4,
                parent=m)
    return dict(root=m, interior=interior, up=up, lo=lo)


def set_mouth(rig, p):
    """WIDTH sets opening width, OPEN its height, ROUND puckers toward a circle.
    The lips hug the cavity's top/bottom edges and part with the jaw."""
    width, opn, rnd = (list(p) + [0, 0, 0])[:3]
    m = rig["mouth"]
    w = width * (1 - rnd * 0.5)
    cav_x = 0.10 + 0.13 * w
    cav_z = max(0.02 + 0.18 * opn, 0.13 * rnd)
    m["interior"].scale = (cav_x, 0.05, cav_z)
    m["root"].location = (0, -1.02 - rnd * 0.03, -0.52)
    m["up"].scale = (cav_x * 1.0, 0.05, 0.032)
    m["up"].location = (0, -0.03, cav_z + 0.04)
    m["lo"].scale = (cav_x * 0.95, 0.05, 0.04)
    m["lo"].location = (0, -0.03, -(cav_z + 0.045) - opn * 0.08)


def set_blink(rig, k):
    for e in rig["eyes"]:
        e.scale = (0.23, 0.25, max(0.02, 0.27 * k))


def lights_and_cam():
    bpy.ops.object.camera_add(location=(0, -8.6, -0.10),
                              rotation=(math.radians(90), 0, 0))
    bpy.context.scene.camera = bpy.context.active_object
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
