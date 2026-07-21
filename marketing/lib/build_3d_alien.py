"""Full-3D Martian alien — the smug little green villain of the MoonLaunch intro.

The 3D upgrade of marketing/characters/alien.svg, built with the such-graphics
PROCEDURAL-BLENDER contract (same as build_3d_sprout / build_3d_tomato): modeled
VOLUMES proud of the head, ONE parametric mouth on the shared A-H/X viseme table,
everything parented to `root`, EEVEE headless, env-driven (SG3D_CUES/OUT/DUR/RES).

Design: green head with a WIDE cranium tapering to a narrow chin (classic martian
silhouette — a wide cranium sphere + a narrow jaw sphere), big dark almond eyes
with small glints, two antennae with little bulb tips, and DOWN-ANGLED brows for
the smug/skeptical look.

Run:
  Blender --background --python build_3d_alien.py -- still
  Blender --background --python build_3d_alien.py -- talk|alpha   (needs SG3D_CUES)
"""
import json
import math
import os
import sys
from pathlib import Path

import bpy

# Reuse the such-graphics creature3d engine's articulated bezier lips for the MOUTH
# (real reshaping lips, not scaled pill-ellipsoids). All of the alien's own head /
# antenna geometry below is unchanged.
sys.path.insert(0, "/Users/johnmurphy/src/such-graphics")
from such_graphics import creature3d as c3d

SP = Path("/private/tmp/claude-501/-Users-johnmurphy-src-WowneroMoonLaunch/"
          "0801bcd3-399b-4237-b990-4df8be9a0d81/scratchpad")
MODE = sys.argv[-1] if sys.argv[-1] in ("still", "talk", "alpha", "hero") else "still"

GREEN = (0.44, 0.75, 0.29)       # martian green
GREEN_D = (0.18, 0.42, 0.14)
GREEN_HI = (0.57, 0.83, 0.41)
ANT = (0.29, 0.58, 0.20)         # antenna stalk
BULB = (0.58, 0.87, 0.44)        # antenna bulb tip
EYE = (0.05, 0.08, 0.05)         # near-black almond eye
GLINT = (0.86, 0.96, 0.82)       # cold glint
BROW = (0.13, 0.34, 0.10)        # dark brow
LIP = (0.20, 0.42, 0.16)         # muted green lip rim
MOUTH_IN = (0.03, 0.035, 0.035)  # near-black cavity

# Viseme table + co-articulation blend come from the engine (4-tuple width/open/
# round/SMILE, shared across the cast). The alien keeps a SMIRKIER rest than the
# doge: override X to a near-flat, faintly-down smile so the snide personality reads
# even with the new expressive lips.
SHAPES = dict(c3d.SHAPES)
SHAPES["X"] = (0.82, 0.02, 0.05, -0.10)   # unimpressed rest, not a warm grin
IDLE = 1.7        # this actor's bob/blink phase (offset from the doge)


def blended_params(t, cues):
    # Engine glide logic, but over the LOCAL table so the smirkier rest is honored.
    for i, c in enumerate(cues):
        if c["start"] <= t < c["end"]:
            a = SHAPES.get(c["value"], SHAPES["X"])
            since = t - c["start"]
            if since < c3d.BLEND and i > 0:
                b = SHAPES.get(cues[i - 1]["value"], SHAPES["X"])
                k = since / c3d.BLEND
                return tuple(b[j] + (a[j] - b[j]) * k for j in range(4))
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
                rgb[0] * 0.85 + 0.02, rgb[1] * 0.62, rgb[2] * 0.34, 1)
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


def build():
    clear()
    root = bpy.data.objects.new("root", None)
    bpy.context.collection.objects.link(root)

    # NECK + SHOULDERS below the head
    sphere("shoulders", (0, 0.10, -1.85), (1.05, 0.66, 0.60), GREEN, 0.45,
           sub=0.1, parent=root)
    sphere("neck", (0, -0.05, -1.15), (0.34, 0.34, 0.42), GREEN, 0.45, sub=0.1,
           parent=root)

    # HEAD — WIDE cranium sphere + a narrow JAW sphere below = the martian taper
    # (wide top, pointy chin). Both waxy-green with subsurface. Front is -Y.
    sphere("cranium", (0, 0.05, 0.28), (1.22, 0.98, 1.02), GREEN, 0.46,
           sub=0.12, parent=root)
    sphere("jaw", (0, -0.16, -0.80), (0.56, 0.66, 0.62), GREEN, 0.46, sub=0.12,
           parent=root)
    # forehead highlight, upper-left
    sphere("brow_hi", (-0.34, -0.60, 0.66), (0.44, 0.14, 0.30), GREEN_HI, 0.5,
           parent=root)

    # ANTENNAE — thin stalks from the crown, each with a bright bulb tip
    for sx, sgn in ((-0.34, -1), (0.34, 1)):
        st = sphere(f"ant_{sgn}", (sx, 0.0, 1.34), (0.055, 0.055, 0.44), ANT,
                    0.5, parent=root)
        st.rotation_euler = (0, math.radians(20) * sgn, 0)
        sphere(f"bulb_{sgn}", (sx + 0.30 * sgn, 0.0, 1.94), (0.15, 0.15, 0.15),
               BULB, 0.4, sub=0.15, parent=root)

    # EYES — big dark ALMONDS tilted (outer corner up), a small cold glint. Placed
    # proud on the face front. The eyes + brows carry the smug read.
    eyes = []
    for sx, sgn in ((-0.44, -1), (0.44, 1)):
        e = sphere(f"eye_{sgn}", (sx, -0.66, 0.06), (0.44, 0.16, 0.28), EYE,
                   0.22, parent=root)
        e.rotation_euler = (0, math.radians(-20) * sgn, 0)   # almond slant
        # glint ON the eye (upper-outer), reads as cold eye-shine not a nostril
        sphere(f"glint_{sgn}", (sx + 0.06 * sgn, -0.88, 0.24),
               (0.07, 0.07, 0.07), GLINT, 0.1, parent=root)
        eyes.append(e)

    # BROWS — DOWN-ANGLED toward the centre (inner ends dip): the smug/skeptical
    # tell. Dark green bars just above the eyes, pushed proud so they read.
    for sx, sgn in ((-0.36, -1), (0.36, 1)):
        b = sphere(f"brow_{sgn}", (sx, -0.82, 0.34), (0.33, 0.07, 0.09), BROW,
                   0.5, parent=root)
        # rotate about Y so the inner (toward-centre) end drops in Z
        b.rotation_euler = (0, math.radians(27) * sgn, 0)

    mouth = build_mouth(root)
    return dict(root=root, eyes=eyes, mouth=mouth)


MOUTH_CENTER = (0, -0.94, -0.46)   # on the lower face, matching the old cavity anchor
SLIT = (0.10, 0.20, 0.10)          # thin dark lip line, faintly green-black

# An ALIEN mouth, not human lips: a thin LIPLESS slit that PARTS symmetrically into a
# dark oval/lens (no jaw, no tongue, no teeth — smooth). The rest line is wide and
# faintly DOWNTURNED (corners below centre) so it reads unimpressed/snide. Both lips
# are near-straight and thin. (x, y, z, per-point radius tapering to points.)
SLIT_BX = 0.22
ALIEN_UPPER = [(-0.22, 0.00, -0.010, 0.12), (-0.10, -0.02, 0.014, 0.55),
               (0.0, -0.024, 0.010, 0.60), (0.10, -0.02, 0.014, 0.55),
               (0.22, 0.00, -0.010, 0.12)]
ALIEN_LOWER = [(-0.22, 0.00, -0.014, 0.12), (-0.09, -0.024, -0.020, 0.55),
               (0.0, -0.028, -0.024, 0.62), (0.09, -0.024, -0.020, 0.55),
               (0.22, 0.00, -0.014, 0.12)]


def build_mouth(root):
    """A thin lipless alien SLIT that opens into a dark oval. Uses the engine's
    bezier_tube primitive but alien-shaped near-straight profiles + a symmetric-part
    driver (set_mouth) — NOT human cupid's-bow lips, no tongue/teeth."""
    m = c3d._empty("mouth", MOUTH_CENTER, root)
    interior = sphere("mouth_in", (0, 0.03, 0), (0.16, 0.05, 0.03), MOUTH_IN, 1.0,
                      parent=m)
    up = c3d.bezier_tube("lip_up", ALIEN_UPPER, 0.012, SLIT, m)
    lo = c3d.bezier_tube("lip_lo", ALIEN_LOWER, 0.012, SLIT, m)
    return dict(kind="alien", root=m, interior=interior, up=up, lo=lo,
                _center=MOUTH_CENTER)


def set_mouth(rig, p):
    """Drive the alien slit from (width, open, round, smile). Both thin lips PART
    symmetrically into a lens (no jaw/tongue); round narrows it toward a small oval.
    Smile is largely ignored — the alien stays deadpan."""
    width, opn, rnd, smile = (list(p) + [0, 0, 0, 0])[:4]
    m = rig["mouth"]
    sx = (0.92 + 0.14 * width) * (1.0 - rnd * 0.42)   # narrows to an oval on round
    part = 0.02 + 0.34 * opn
    c3d._shape_lip(m["up"], ALIEN_UPPER, sx, part * 0.85, smile * 0.15, rnd * 0.02, 1.0)
    c3d._shape_lip(m["lo"], ALIEN_LOWER, sx, -part, smile * 0.05, rnd * 0.03, 1.0)
    m["interior"].scale = (0.14 * sx + 0.02, 0.05, max(0.02, part * 0.9))


def set_blink(rig, k):
    for e in rig["eyes"]:
        # keep the almond slant while the lid drops on Z
        e.scale = (0.44, 0.16, max(0.02, 0.28 * k))


def lights_and_cam():
    bpy.ops.object.camera_add(location=(0, -8.4, 0.18),
                              rotation=(math.radians(90), 0, 0))
    bpy.context.scene.camera = bpy.context.active_object
    bpy.ops.object.light_add(type="AREA", location=(-3.4, -4.2, 4.2))
    k = bpy.context.active_object
    k.data.energy = 1150
    k.data.size = 4.5
    k.data.color = (1.0, 0.96, 0.86)
    k.data.use_contact_shadow = True
    bpy.ops.object.light_add(type="AREA", location=(4.2, -3.2, 1.0))
    f = bpy.context.active_object
    f.data.energy = 120
    f.data.size = 6
    f.data.color = (0.82, 0.92, 1.0)
    bpy.ops.object.light_add(type="AREA", location=(1.5, 4.0, 4.5))
    r = bpy.context.active_object
    r.data.energy = 700
    r.data.size = 4
    r.data.color = (0.80, 1.0, 0.85)
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
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.12, 0.14, 1)
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
            sc.render.filepath = str(SP / f"alien3d_v_{vis}.png")
            bpy.ops.render.render(write_still=True)
            print(f"RESULT wrote alien3d_v_{vis}.png")
        return

    cues = json.load(open(os.environ["SG3D_CUES"]))["cues"]
    fps = 30
    _dur = os.environ.get("SG3D_DUR")
    dur = float(_dur) if _dur else (max(c["end"] for c in cues) + 0.4)
    outdir = Path(os.environ.get("SG3D_OUT",
                  str(SP / ("_3dframes_alien_alpha" if MODE == "alpha" else "_3dframes_alien"))))
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
        rig["root"].rotation_euler = (0, 0, math.sin((t + IDLE) * 1.3) * 0.045)
        sc.render.filepath = str(outdir / f"f_{i:05d}.png")
        bpy.ops.render.render(write_still=True)
    print(f"RESULT rendered {n} frames -> {outdir.name}")


main()
