"""Builds Draw Track's data tables from the game's own piece data (run from the project folder's ballest-draw-track).

    python tools/make_tables.py

kit.txt     the kits the fitter builds with (Track, Bevel Half, Bevel Full, Round): each piece's kit, class, kind, its
            two ends (where the rolling surface meets the end: the top of the end face's vertical centre line, and the
            way the end faces, in the piece's own frame, scale 1), the track's width there and the height scale the kit
            uses it at.
ends.txt    every piece's two track ends the same way, with the kit each end belongs to (the kit whose ends it meets
            seamlessly, and at what height scale), for the open ends of the track already in a map.
bounds.txt  every placeable piece's box (its Main mesh's bounds, through the component's relative transform), by
            class name, for keeping a drawn track clear of what is already there.

Ends come from the mesh geometry (tools/survey_kits.py): a piece's ends are its two flat faces that face sideways and
span a track's width. Two ends meet seamlessly when their rolling surfaces (each face's top outline, from the joint)
are within 4 cm of each other over the middle 80% of the width, facing each other. Every pair of ends in a kit is
checked here; the tables are not written if one fails.

Measured (2026-10-24): Track, Bevel Half and Bevel Full meet exactly (their end faces are the same shape, overlap 1.0).
Round Curve's dome is twice as high as Round Straight's (its rolling surface drops 93 cm at the edge to the straight's
47): at half height its rolling surface matches the straight's within 2 cm, so the Round kit uses it at height scale
0.5 (its sides are then 50 cm shorter than the straight's below the rolling surface). The quarter pipes are a curved
wall with no floor (not a track to draw on its own) and are left out; the half pipes, Bevel_C / Bevel_T corners and
S-bends aren't kits (no straight or no 90-degree turn that meet them).

Sources: <project>/ballest-map-builder/catalog/pieces.json and geometry/ (the editor's pieces, every mesh's bounds and
geometry, game build 2026-10-06).
"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(PLUGIN.parent / "scripts"))
import survey_kits as sk  # noqa: E402
import ballest_kit  # noqa: E402

NL = chr(10)

# The kits, in the menu's order: (kit, [(piece name in the editor, kind, height scale)]). Straights are stretched along
# their length to fit; turns are 90 degrees, flat, and scaled evenly in plan with the track's width; sags (the ramps
# "Curve1": level in plan, both ends tilted up 22.5 degrees, a 45-degree upward bend) are stretched along to the bend
# needed. Only Track has sags whose ends are its own: Bevel Full's scoops are half ramps with a 3.7 m end, Round's ramps
# are its double-height dome, and no kit has a crest (a bend downward).
SAG_TILT = 0.75         # a sag's ends tilt up: faces whose normal's z is up to this
KITS = [
    ("Track", [("Track S", "straight", 1), ("Track M", "straight", 1),
               ("Curve S", "turn", 1), ("Curve M", "turn", 1), ("Curve L", "turn", 1),
               ("Curve1 S", "sag", 1), ("Curve1 M", "sag", 1), ("Curve1 L", "sag", 1)]),
    ("Bevel Half", [("Bevel_H Straight", "straight", 1), ("Bevel_H Turn", "turn", 1)]),
    ("Bevel Full", [("Bevel_F Straight", "straight", 1), ("Bevel_F Turn", "turn", 1)]),
    ("Round", [("Round Straight", "straight", 1), ("Round Curve", "turn", 0.5)]),
]
SEAM = 4.0              # cm: the most two ends' rolling surfaces may differ
SAME_SHAPE = 0.95       # an end is a kit's own when its whole face matches the kit's this well (overlap / union)


def kit_of(end, reference):
    """The kit an end belongs to, as kit@1: the kit whose end face it matches whole. Only whole faces: a flat top 5 m
    wide (a half pipe's rim, a platform) meets Track's rolling surface but isn't a track end, and Bevel Full's and
    Bevel Half's rolling surfaces are the same while their faces aren't. Empty for none."""
    grid = sk.raster(end["tris"])
    for kit, ref_top, ref_grid, width in reference:
        if abs(end["width"] - width) < 10 and sk.iou(grid, ref_grid[::-1, :]) >= SAME_SHAPE:
            return f"{kit}@1"
    return ""


def fallback_ends(name, P, T, reference):
    """A piece's two ends the older way (scripts/ballest_kit.py: open faces about 500 x 100, any tilt), for pieces whose
    ends aren't both level faces (ramps, kickers, half pipes): each end's kit from the level face it lies in, if any."""
    try:
        ports = ballest_kit.ports(name)
    except Exception:
        return None
    if len(ports) > 2:
        ports = [p for p in ports if abs(p["normal"][0]) > 0.9]
    if len(ports) != 2:
        return None
    centre = (P.min(0) + P.max(0)) / 2
    caps = sk.planar_caps(P, T)
    out = []
    for p in ports:
        joint = p["pos"] + p["up"] * (p["thickness"] / 2)
        kit = ""
        for c in caps:
            if np.dot(c[0], p["normal"]) > 0.99 or np.dot(c[0], p["normal"]) < -0.99:
                if abs(np.dot(c[0], p["pos"] - c[1].mean(0))) < 2:
                    j, n, prof, across = sk.cap_info(c[0], c[1], c[2], centre)
                    kit = kit_of({"width": float(np.ptp(prof[:, 0])), "tris": sk.cap_2d(c[5], j, across, n)}, reference)
        out.append((joint, p["normal"], kit))
    return out


def fmt(v):
    return " ".join(f"{c:.3f}" for c in v)


def main():
    data = json.load(open(sk.CATALOG / "pieces.json", encoding="utf-8"))
    meshes = {m["meshPath"]: m for m in data["meshes"]}
    pieces = {p["name"]: p for p in data["pieces"] if p.get("inMenu")}

    # the kits: every piece's ends, and every pair of ends in a kit checked to meet
    lines = ["# Draw Track kits: kit|name|class path|kind|end A: x y z dx dy dz|end B: x y z dx dy dz|width|height scale",
             "# (ends: where the rolling surface meets the end and the end's outward direction; cm, scale 1)"]
    reference = []          # (kit, its first straight's end A rolling line, face, width)
    member = {name: (kit, sz) for kit, members in KITS for name, _, sz in members}
    failed = False
    for kit, members in KITS:
        ends = []
        for name, kind, sz in members:
            P, T = sk.load_mesh(pieces[name], meshes)
            two = sk.end_faces(P, T, SAG_TILT if kind == "sag" else 0.2)
            assert two, name
            for e in two:
                ends.append((name, sz, e, sk.end_top(e, sz)))
            a, b = two
            width = (a["width"] + b["width"]) / 2
            lines.append(f"{kit}|{name}|{pieces[name]['classPath']}|{kind}|{fmt(a['joint'])} {fmt(a['normal'])}|"
                         f"{fmt(b['joint'])} {fmt(b['normal'])}|{width:.1f}|{sz:g}")
        worst = 0.0
        for i in range(len(ends)):
            for j in range(i, len(ends)):
                width = min(ends[i][2]["width"], ends[j][2]["width"])
                gap = sk.seam_gap(ends[i][3], ends[j][3], width)
                worst = max(worst, gap)
                if gap > SEAM:
                    failed = True
                    print(f"  {kit}: {ends[i][0]} and {ends[j][0]} don't meet ({gap:.1f} cm)")
        print(f"{kit}: {len(members)} pieces, worst seam {worst:.1f} cm")
        ref = ends[0][2]
        reference.append((kit, ends[0][3], sk.raster(ref["tris"]), ref["width"]))
    if failed:
        sys.exit("a kit's pieces don't meet: tables not written")

    # every piece's ends, each with the kit it meets
    rows = ["# Draw Track ends: class name|end A: x y z dx dy dz|end B: x y z dx dy dz|kit of A|kit of B",
            "# (cm, scale 1; a kit as name@height scale: the end is that kit's when the piece is at that height scale;",
            "# empty: no kit's, an end only for telling which ends are joined)"]
    for name, piece in sorted(pieces.items()):
        mesh = sk.load_mesh(piece, meshes)
        if mesh is None:
            continue
        two = sk.end_faces(*mesh, SAG_TILT if name in member else 0.2)
        if two:
            two = [(e["joint"], e["normal"], kit_of(e, reference)) for e in two]
            if name in member:                          # a kit's own piece: that kit, at the height scale it uses
                two = [(j, n, f"{member[name][0]}@{member[name][1]:g}") for j, n, _ in two]
            elif not two[0][2] and not two[1][2]:
                two = None                              # not track ends (a half pipe's rims): try the older way
        if not two:
            two = fallback_ends(name, *mesh, reference)
        if not two:
            continue
        cls = piece["classPath"].rsplit(".", 1)[-1]
        (ja, na, ka), (jb, nb, kb) = two
        rows.append(f"{cls}|{fmt(ja)} {fmt(na)}|{fmt(jb)} {fmt(nb)}|{ka}|{kb}")
    (PLUGIN / "kit.txt").write_text(NL.join(lines) + NL, encoding="utf-8")
    (PLUGIN / "ends.txt").write_text(NL.join(rows) + NL, encoding="utf-8")

    boxes = ["# Draw Track piece boxes: class name|centre x y z|half size x y z (cm, the piece's own frame, scale 1)"]
    for p in data["pieces"]:
        main = next((c for c in p.get("meshComponents", []) if c.get("name") == "Main" and c.get("mesh")), None)
        if not main or main["mesh"] not in meshes:
            continue
        m = meshes[main["mesh"]]
        o, e = np.array(m["boundsOrigin"], float), np.array(m["boundsExtent"], float)
        s = np.array(main.get("relativeScale") or [1, 1, 1], float)
        R = sk.rot_matrix(*(main.get("relativeRotation") or [0, 0, 0]))
        t = np.array(main.get("relativeLocation") or [0, 0, 0], float)
        corners = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]) * e + o
        world = (R @ (corners * s).T).T + t
        lo, hi = world.min(0), world.max(0)
        cls = p["classPath"].rsplit(".", 1)[-1]
        c, h = (lo + hi) / 2, (hi - lo) / 2
        boxes.append(f"{cls}|{c[0]:.1f} {c[1]:.1f} {c[2]:.1f}|{h[0]:.1f} {h[1]:.1f} {h[2]:.1f}")
    (PLUGIN / "bounds.txt").write_text(NL.join(boxes) + NL, encoding="utf-8")
    print(f"kit.txt: {len(lines) - 2} pieces in {len(KITS)} kits; ends.txt: {len(rows) - 3} pieces; "
          f"bounds.txt: {len(boxes) - 1} pieces")


if __name__ == "__main__":
    main()
