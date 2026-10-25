"""Surveys the editor's track pieces for Draw Track's kits, from the game's own geometry (no game needed).

    python tools/survey_kits.py            -> a table of every candidate piece: its ends, turn, radius, profile
    python tools/survey_kits.py --json     -> the same as JSON (used by make_tables.py)

A piece's ends are its flat faces that face sideways (normal within ~11 degrees of level) and span a track's width
(300 cm or more across): the caps of the track's cross-section. For a straight with four such faces (Track S is a
500 x 500 box) the pair along its own X is taken. For each end:
- the joint: the point where the rolling surface meets the end, at the middle of its width: the highest point of the
  cap's outline on its vertical centre line (the top of a flat track; the inside bottom of a round one);
- the direction it faces, its width, and its profile (the cap's outline in (across, up) relative to the joint), so
  pieces can be checked to join seamlessly and for symmetry (a mirrored profile the same: either end of a turn can be
  used, turning left or right).
Between a piece's two ends: how far it turns in plan, its radius (a turn's chord / sqrt 2 for 90 degrees), and
whether it rises.

Source: <project>/ballest-map-builder/catalog (pieces.json + geometry/<mesh>.json, game build 2026-10-06).
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
CATALOG = PROJECT / "ballest-map-builder" / "catalog"

CATEGORIES = ("Tracks", "Pipes", "Misc")
MIN_WIDTH = 300


def rot_matrix(pitch, yaw, roll):
    p, y, r = np.radians([pitch, yaw, roll])
    cp, sp, cy, sy, cr, sr = np.cos(p), np.sin(p), np.cos(y), np.sin(y), np.cos(r), np.sin(r)
    x = np.array([cp * cy, cp * sy, sp])
    yv = np.array([sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp])
    z = np.array([-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp])
    return np.column_stack([x, yv, z])


def load_mesh(piece, meshes):
    main = next((c for c in piece.get("meshComponents", []) if c.get("name") == "Main" and c.get("mesh")), None)
    if not main or main["mesh"] not in meshes:
        return None
    gfile = CATALOG / meshes[main["mesh"]]["geometryFile"]
    if not gfile.exists():
        return None
    g = json.load(open(gfile, encoding="utf-8"))
    P = np.array(g["positions"], float)
    T = np.array(g["indices"], int).reshape(-1, 3)
    s = np.array(main.get("relativeScale") or [1, 1, 1], float)
    R = rot_matrix(*(main.get("relativeRotation") or [0, 0, 0]))
    t = np.array(main.get("relativeLocation") or [0, 0, 0], float)
    P = (R @ (P * s).T).T + t
    if np.prod(s) < 0:                               # a mirrored mesh: keep triangles facing out
        T = T[:, ::-1]
    return P, T


def planar_caps(P, T, max_tilt=0.2):
    """Groups of triangles that lie in one plane with a level normal (its z at most max_tilt), each as (normal, points,
    across, width, triangle count, triangles)."""
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    n = np.cross(b - a, c - a)
    area = np.linalg.norm(n, axis=1)
    ok = area > 1e-6
    n[ok] /= area[ok, None]
    groups = defaultdict(list)
    for i in np.nonzero(ok)[0]:
        if abs(n[i, 2]) > max_tilt:
            continue
        d = float(np.dot(n[i], a[i]))
        key = (round(n[i, 0], 2), round(n[i, 1], 2), round(n[i, 2], 2), round(d / 2) * 2)
        groups[key].append(i)
    # one face whose triangles fell either side of a rounding step: merged
    for key in sorted(groups, key=lambda k: k[3]):
        twin = (*key[:3], key[3] - 2)
        if key in groups and twin in groups:
            groups[key] = groups.pop(twin) + groups[key]
    caps = []
    for key, tris in groups.items():
        idx = np.unique(T[tris].ravel())
        pts = P[idx]
        normal = np.array(key[:3])
        normal /= np.linalg.norm(normal)
        across = np.cross([0, 0, 1], normal)
        across /= np.linalg.norm(across)
        width = np.ptp(pts @ across)
        if width < MIN_WIDTH:
            continue
        caps.append((normal, pts, across, width, len(tris), P[T[tris]]))
    # several faces in one direction (a curve's end can have a second, smaller face in its plane): the widest
    best = {}
    for c in caps:
        key = (round(c[0][0], 1), round(c[0][1], 1))
        if key not in best or c[3] > best[key][3]:
            best[key] = c
    return list(best.values())


def cap_info(normal, pts, across, centre):
    """The joint, outward direction, profile and (across) axis of an end cap."""
    if np.dot(normal, pts.mean(0) - centre) < 0:
        normal = -normal
        across = -across
    up = np.cross(normal, across)                # in the face, square to across (straight up for a level end)
    up /= np.linalg.norm(up)
    u = pts @ across
    mid = (u.min() + u.max()) / 2
    v = pts @ up
    # the outline's highest point near its centre line: where the rolling surface meets the end
    near = np.abs(u - mid) < max(20.0, 0.05 * np.ptp(u))
    top = np.argmax(np.where(near, v, -np.inf)) if near.any() else np.argmax(v)
    joint = pts[top] + across * (mid - pts[top] @ across)
    prof = np.column_stack([u - mid, v - v[top]])
    return joint, normal, prof, across


def raster(tris2d, cell=4.0, lo=(-700, -800), hi=(700, 400)):
    """Cells (cell cm) covered by 2D triangles, as a boolean grid over lo..hi."""
    nx, ny = int((hi[0] - lo[0]) / cell), int((hi[1] - lo[1]) / cell)
    xs = lo[0] + (np.arange(nx) + 0.5) * cell
    ys = lo[1] + (np.arange(ny) + 0.5) * cell
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    grid = np.zeros((nx, ny), bool)
    for a, b, c in tris2d:
        x0, x1 = min(a[0], b[0], c[0]), max(a[0], b[0], c[0])
        y0, y1 = min(a[1], b[1], c[1]), max(a[1], b[1], c[1])
        i0, i1 = max(int((x0 - lo[0]) / cell), 0), min(int((x1 - lo[0]) / cell) + 1, nx)
        j0, j1 = max(int((y0 - lo[1]) / cell), 0), min(int((y1 - lo[1]) / cell) + 1, ny)
        if i0 >= i1 or j0 >= j1:
            continue
        px, py = X[i0:i1, j0:j1], Y[i0:i1, j0:j1]
        d1 = (px - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (py - b[1])
        d2 = (px - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (py - c[1])
        d3 = (px - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (py - a[1])
        neg = (d1 < 0) | (d2 < 0) | (d3 < 0)
        pos = (d1 > 0) | (d2 > 0) | (d3 > 0)
        grid[i0:i1, j0:j1] |= ~(neg & pos)
    return grid


def iou(a, b):
    u = (a | b).sum()
    return float((a & b).sum()) / u if u else 0.0


def cap_2d(tris, joint, across, normal):
    """A cap's triangles in its own (across, up) frame from the joint (up: in the face, square to across)."""
    up = np.cross(normal, across)
    up /= np.linalg.norm(up)
    rel = tris - joint
    return np.stack([rel @ across, rel @ up], axis=-1)


def top_line(grid, cell=4.0, lo=(-700, -800)):
    """The highest covered height (cm from the joint) of each column of a raster, NaN where it is empty."""
    ys = lo[1] + (np.arange(grid.shape[1]) + 0.5) * cell
    any_ = grid.any(1)
    top = np.full(grid.shape[0], np.nan)
    top[any_] = ys[grid.shape[1] - 1 - np.argmax(grid[any_, ::-1], axis=1)]
    return top


def seam_gap(top_a, top_b, width, cell=4.0, lo=(-700, -800)):
    """How far apart (cm) two ends' rolling surfaces are, worst case over the middle 80% of the track's width, when
    the ends face each other (one is mirrored). Infinite when either has nothing there."""
    xs = lo[0] + (np.arange(len(top_a)) + 0.5) * cell
    mid = np.abs(xs) < 0.4 * width
    d = np.abs(top_a[mid] - top_b[::-1][mid])
    return float(np.inf) if np.isnan(d).any() else float(d.max())


def symmetric(tris2d):
    g = raster(tris2d)
    return iou(g, g[::-1, :]) >= 0.97


def end_faces(P, T, max_tilt=0.2):
    """A piece's two track ends, each a dict (joint, normal, across, width, triangles in the end's own (across, up)
    frame from the joint), or None when it hasn't exactly two."""
    centre = (P.min(0) + P.max(0)) / 2
    caps = planar_caps(P, T, max_tilt)
    if len(caps) > 2:
        along_x = [c for c in caps if abs(c[0][0]) > 0.9]
        if len(along_x) == 2:
            caps = along_x
    if len(caps) != 2:
        return None
    out = []
    for c in caps:
        joint, normal, prof, across = cap_info(c[0], c[1], c[2], centre)
        out.append({"joint": joint, "normal": normal, "across": across, "width": float(np.ptp(prof[:, 0])),
                    "tris": cap_2d(c[5], joint, across, normal)})
    return out


def end_top(end, sz=1.0):
    """An end's rolling-surface line (top_line) with the piece scaled sz in height."""
    t = end["tris"].copy()
    t[..., 1] *= sz
    return top_line(raster(t))


def survey():
    data = json.load(open(CATALOG / "pieces.json", encoding="utf-8"))
    meshes = {m["meshPath"]: m for m in data["meshes"]}
    out = []
    for piece in data["pieces"]:
        if not piece.get("inMenu") or piece.get("category") not in CATEGORIES:
            continue
        mesh = load_mesh(piece, meshes)
        if mesh is None:
            continue
        P, T = mesh
        centre = (P.min(0) + P.max(0)) / 2
        caps = planar_caps(P, T)
        if len(caps) > 2:
            along_x = [c for c in caps if abs(c[0][0]) > 0.9]
            if len(along_x) == 2:
                caps = along_x
        rec = {"name": piece["name"], "class": piece["classPath"].rsplit(".", 1)[-1], "classPath": piece["classPath"],
               "category": piece["category"], "caps": len(caps)}
        if len(caps) == 2:
            ends = [cap_info(c[0], c[1], c[2], centre) for c in caps]
            (ja, na, pa, xa), (jb, nb, pb, xb) = ends
            ta, tb = cap_2d(caps[0][5], ja, xa, na), cap_2d(caps[1][5], jb, xb, nb)
            fa = -na                                   # into the piece at A
            heading_a = np.degrees(np.arctan2(fa[1], fa[0]))
            heading_b = np.degrees(np.arctan2(nb[1], nb[0]))
            turn = (heading_b - heading_a + 180) % 360 - 180
            chord = np.linalg.norm((jb - ja)[:2])
            lat = np.cross(np.append(fa[:2], 0), np.append((jb - ja)[:2], 0))[2]
            rec.update({
                "endA": [*ja.round(3).tolist(), *na.round(4).tolist()],
                "endB": [*jb.round(3).tolist(), *nb.round(4).tolist()],
                "widthA": float(np.ptp(pa[:, 0])), "widthB": float(np.ptp(pb[:, 0])),
                "turn": round(float(turn), 2),
                "length": round(float(chord), 1),
                "radius": round(float(chord / np.sqrt(2)), 1) if abs(abs(turn) - 90) < 1 else None,
                "rise": round(float(jb[2] - ja[2]), 1),
                "sideOffset": round(float(lat / max(chord, 1e-6)), 3),
                "symmetricA": symmetric(ta), "symmetricB": symmetric(tb),
                "profileA": pa.round(1).tolist(), "profileB": pb.round(1).tolist(),
                "depth": round(float(-pa[:, 1].min()), 1),
            })
        out.append(rec)
    return out


def main():
    rows = survey()
    if "--json" in sys.argv:
        print(json.dumps(rows))
        return
    for r in rows:
        if r["caps"] != 2:
            print(f"{r['category']:7} {r['name']:28} caps {r['caps']}")
            continue
        print(f"{r['category']:7} {r['name']:28} width {r['widthA']:6.0f}/{r['widthB']:6.0f} turn {r['turn']:7.2f} "
              f"len {r['length']:7.1f} rad {str(r['radius']):>7} rise {r['rise']:6.1f} sym {r['symmetricA']!s:5}/{r['symmetricB']!s:5} "
              f"jointZ {r['endA'][2]:6.1f}/{r['endB'][2]:6.1f} depth {r['depth']:6.1f}")


if __name__ == "__main__":
    main()
