# Draw Track: design

Draw a line in the track editor; when you let go, track pieces drop into place along it.

## Decisions (the user's, 2026-10-24)

| Question | Answer |
|---|---|
| What a line becomes | Real track kit pieces joined end to end; the line is the ball's path; turns use curve pieces, never straights faking a curve |
| Height in open space | A level plane at the start height; the wheel / Page Up / Page Down raise and lower it while drawing (slopes) |
| Starting / ending on track | Snap to an open end and carry it on; ending on one joins it; starting on top of a piece starts on its surface |
| Feedback | See-through outlines of the pieces while drawing; on release the pieces drop into place |
| Rideable or literal | Smooth to rideable: wobbles ignored, turns sized to the drawn turn, slopes capped |
| Track type | Picked in the menu (a kit); brush size is the track's width |
| Undo | The editor's own: one line is one step |
| Shared code | A library plugin, Draw Core, used by Inspect Draw and Draw Track |
| Crossings | Lifted over as a bridge (or the line stops before it) |
| First version | Straights, curves and slopes; loops, jumps and banking later |
| Speed | Pieces appear within ~0.5 s of letting go: the fit runs while drawing |

## Parts

- **Draw Core** (`ballest-draw-core`, a library): the stroke. Mouse capture, the cursor path sampled every 4 px,
  points placed on surfaces (the stroke keeps to the surface it started on; gaps bridged by depth), on a level plane,
  or in the air; the see-through layer that keeps the game or editor from taking the clicks while a tool is on; the
  size ring. Clients call `DrawCore_Frame` every frame and read `DrawCore_State/Count/ChangedFrom/Point`.
- **Inspect Draw**: lines in inspect mode on top of Draw Core (tubes, colours, eraser, history, saving).
- **Draw Track**: the editor client. Fitter, ghosts, building.
- **Host** (0.31.0, local): `Editor::SpawnPieces` (the editor's paste, one history step, scale applied with
  `Server_SetActorTransforms` in the same step, optional drop animation), `Editor::GetScale`, `Editor::Undo/Redo`,
  `Camera::Pick/PickOn/Deproject/Inspecting`, `Window.hovered`, picture icon buttons.
- **Data** (`tools/make_tables.py` with `tools/survey_kits.py`, from `ballest-map-builder/catalog`): `kit.txt` (every
  kit's pieces: two ends each, where the rolling surface meets the end and the outward direction, the width and the
  height scale the kit uses the piece at), `ends.txt` (every piece's two ends and the kit each end is) and `bounds.txt`
  (every piece's box).

## Kits (round 3, 2026-10-24, designed and tested offline: the user was playing, no game)

A kit is a set of pieces whose ends all meet. They were found from the pieces' own geometry (`tools/survey_kits.py`):
a piece's ends are its two flat faces that face sideways and span a track's width; the joint is the top of the face's
vertical centre line (where the ball rolls). `make_tables.py` checks every pair of ends in a kit, facing each other
(one mirrored): their rolling surfaces must be within 4 cm over the middle 80% of the width, or the tables aren't
written.

| Kit | Straights | Turns (radius at 5 m wide) | Depth below the rolling surface | Seams |
|---|---|---|---|---|
| Track | Track S (5 m), Track M (10 m) | Curve S / M / L (3.2 / 6.4 / 12.7 m) | 100 cm | exact |
| Bevel Half | Bevel_H Straight (10 m) | Bevel_H Turn (6.4 m) | 125 cm | exact |
| Bevel Full | Bevel_F Straight (10 m) | Bevel_F Turn (6.4 m) | 235 cm | exact |
| Round | Round Straight (10 m) | Round Curve at half height (12.7 m) | 150 cm | rolling surface within 2 cm |

- **Round**: the curve's dome is twice as high as the straight's (its top drops 93 cm at the edge to the straight's 47).
  At height scale 0.5 its rolling surface is the straight's within 2 cm, so the kit uses it at half height; its sides
  are then 50 cm shorter than the straight's below the rolling surface (only seen from under the track). A rideable
  surface was chosen over matching sides (the user's "smooth to rideable").
- **Left out**: the quarter pipes (a curved wall with no floor: only one end of each meets the other piece's, so a line
  could only turn one way, and there is nothing to roll on without a floor beside it), Quarter Curve Small (95
  degrees), the half pipes, Bevel_C / Bevel_T corners and S-bends (no matching straight and 90-degree turn pair).
- **Which kit a line is**: the menu's, or the node's it starts on (the menu switches to it: the road type carried on,
  as in city builders). A line joins only a node of its own kit; ending on another kit's node, the note says "a line
  joins only its own kind". Nodes of the line's kit are bright, others small and grey.
- **Which kit an end is** (`ends.txt`): the kit whose end face it matches whole (overlap / union 0.95 on a 4 cm grid).
  Whole faces, not just the rolling surface: a half pipe's rim and Bevel Half Platform's top are flat and 5 m wide like
  Track's, and Bevel Full's rolling surface is Bevel Half's. A kit's own pieces are that kit at the height scale it
  uses them at: a Round Curve placed at full height is no kit's (no node), at half height Round's. Ends of no kit
  still count for telling which ends are joined. Pieces whose ends aren't both level faces (ramps, kickers, half
  pipes) get their ends the older way (`scripts/ballest_kit.py`), with the kit of a level end from its face.
- **Per kit in the fitter**: the turns (smallest first) and straights (the one stretched least for each piece; runs cut
  into pieces no longer than the longest), the width a scale of 1 is, and the depth: a bridge needs the obstacle's top
  plus the kit's depth plus 1.6 m for the ball (Track: 2.6 m, as before), and a line started on top of a piece starts
  the kit's depth above it.
- **Tests** (`tests/fit_test.as`, run without the game by the plugin manager's `build/asrun.exe`): the tables (4 kits,
  widths, depths, which kit a Round curve / kicker / half pipe / Bevel Full end is), then for every kit an L, a zigzag
  (4 turns), a 3 m slope, a crossing (bridged, 1.6 m clear under it), a join to its own kind of node (within 1 cm),
  another kit's node (not joined, the note) and a line carried on from a 7.5 m node. Every piece is checked: the kit's,
  entered within 1 cm of where the last one ends, heading on within 0.5 degrees, pitch changes up to 10.5 degrees,
  turns level and even in plan, nothing NaN. 2232 checks pass. Changing the height scale, the join rule or the
  end-kit rule makes them fail.

## The fitter

The kit's flat turns are 90 degrees only (Curve S / M / L: radius 318 / 637 / 1273 cm at width 5 m) and there is no
convex crest piece, so:

1. **Start**: an open end (its position, height and heading), or the line's first point heading the way it was first
   drawn, to 15 degrees.
2. **Legs**: the line is simplified (Ramer-Douglas-Peucker, tolerance half the smallest turn's radius) and each piece
   of it becomes a leg along one of the start heading's four directions; legs the same way merge; a U-turn gets a leg
   across; the first leg leaves the start straight ahead. Each leg runs along the mean of its points across it.
3. **Corners**: each gets the turn whose radius is nearest how wide it was drawn (the corner's distance to the drawn
   line / 0.414), among those that fit between the turns either side; a leg too short for any turn is lengthened (the
   next leg's line moves out).
   Inner legs shorter than twice the smallest turn's radius are merged away (wobbles; points near the horizon jump a
   long way for a pixel).
4. **Joints**: the plan is cut into runs of at most 5 m; a turn's two ends are one joint (turns stay level). Each joint
   takes the height drawn nearest it.
5. **Clearance** (round 2, after the user's bug reports): every run's footprint (a point a metre along it, across its
   width, at the track's and the ball's heights) is tested against the map's pieces as their real shapes: a turned
   box, or for a turn piece the ring sector it covers (its box is far bigger). Each run first picks only the pieces
   whose bounds are near it (a broad phase: 1 to 2 ms a fit). The pieces the line starts from and joins never count. A hit (15 cm
   across, 65 cm up and down) sets the joints either side to need the piece's
   top + 2.6 m; a piece more than 15 m above the line can't be bridged. The line's own pieces count when they end more
   than 4 m back along it (a loop crossing itself), from the first fit's pieces: one pass, no feedback, so nothing
   climbs away (the old bug: raising the drawn heights and fitting again found new overlaps each time).
6. **Profile**: heights are the drawn ones raised to what is needed, ramps pulled up to those within 10 degrees,
   smoothed (each joint towards its neighbours, never below its need) and clamped to 10 degrees from the start (and
   back from a joined end). The start is fixed only when the line carries on a node; a line from open space rises
   from its first piece. A joint still below its need is blocked: the track stops before it and the rest shows red
   with "raise the level (PgUp) or go round".
7. **Pieces**: runs at one pitch merge into Track M / Track S pieces of up to 10 m, stretched to fit; turns level.
8. **Joining a node**: releasing over a node (on screen) makes it the line's end; the start heading lines up with it
   (to 90 degrees) when the start is free; if the plan can't reach it exactly, it is fitted again without the join
   and the note says so.
9. **Limits**: pieces outside the editor's placement bounds are cut off.

## Height changes (round 4, 2026-10-24, the user's answers)

The user wanted height changes made from real ramp pieces, the slope taken from the drawing, and rounded tops; "red /
stops" was what they saw before (10-degree cap). Measured from the geometry: the only vertical-bend pieces whose ends
are a kit's own are Track's ramps **Curve1 S / M / L** (sags: level in plan, both ends tilted up 22.5 degrees, a
45-degree upward bend; their end faces match Track's exactly). Bevel Full's scoops are half ramps with a 3.7 m end,
Round's ramps are its double-height dome, and no kit has a crest (a downward bend).

- **Heights**: as drawn, up to 45 degrees (a sag's bend from level); ramps up to what must be cleared stay 10 degrees;
  the runs next to a turn or the line's ends at most 3 degrees, so the bend there has room. Height joints every 2.5 m.
  No smoothing passes any more: each straight stretch between turns is simplified to grades (within 1.5 m of the
  heights, never below what must be cleared), and the bends between grades are made by pieces.
- **Bends upward**: a sag stretched along so its ends match the grades either side (stretch 0.5 to 6; the largest that
  fits). Stretching tilts its end faces against the straights' (the rolling surface meets exactly; a wedge shows under
  the seam from below).
- **Bends over the top** (and upward where no sag fits, or in kits without sags): short straights around a circle
  (radius up to 20 m), their slopes at most 5 degrees apart. Such a bend passes below the grades' corner: a joint it
  then misses is raised by the shortfall and the heights fitted again (twice at most).
- **The level changed while drawing**: the cursor's point on the raised plane is nearer the camera, which put a sideways
  jog in the line right where it climbed; the points after a change are now moved back by that much, so the line keeps
  its place in plan and only rises.
- Measured in a slot (agent pipe, map `test`): a 6 m climb and drop drawn with Page Up / Page Down built 30 pieces in a
  straight line, a Curve1 S sag at each foot, rounded tops.
- 0.3.1 (the user's reports): scrolling the level while drawing with the mouse still now changes the outline at once:
  the line's open end is at the scrolled level and the line leads up (or down) to it as steep as 45 degrees allows (the
  nearly-level end run is only kept next to a node the line joins or starts from). Heights drawn in steps (the wheel
  turned while drawing) left short grades at the foot, each too short for a sag, so the bend came out as a run of short
  pieces: two bends the same way with a grade under 6 m between them now merge into one where the grades either side
  meet (only where it still clears every need), and a sliver of straight under 60 cm next to a bend of short pieces is
  taken up by that bend. Measured in a slot: 8 m scrolled with the mouse still, the outline rose to the cursor at once,
  and the line built with a Curve1 L at the foot.

## Crests, loops and placing speed (0.4.0, 2026-10-24, the user's reports)

- **Crests**: the Ramp Curve1 pieces are curved slabs of even thickness (measured: 100 cm all along), so rolled 180
  degrees a ramp is a crest ridden on its underside. kit.txt lists each ramp again as a crest (its ends: the faces'
  bottom joints, roll 180), seam-checked like the rest; a bend over the top now uses the largest crest that fits, and
  short pieces only where none does. FindPieces reads a ramp rolled over with its crest ends. A 6 m climb and drop is
  14 pieces (2 sags, 2 crests) where it was 28. In a slot the crest's riding surface shows the ramp's underside finish.
- **Loops**: a line drawn back to its own start (its last point within the track's width, after going further than four
  of the smallest turns away) closes: the start is the end it joins, facing back along the line, at the start's height,
  and the line's first and last 15 m never count as in each other's way. Measured offline: ending short of the start,
  at it, 3 m past it, 2 m off to the side and a small loop all close exactly.
- **The crash**: placing a 94-piece line crashed the user's game at the engine's UObject limit (2,162,688). The
  editor's paste, which SpawnPieces uses, rebuilds the outliner and Details panel once per pasted piece; the objects
  that makes are freed only by the next garbage collection. The host now holds those UI refreshes during SpawnPieces'
  paste and runs each once (from the 2026-10-15 fast-paste work, here only for SpawnPieces; the player's own pastes
  are untouched). Measured on the test map: 14 / 32 / 55 pieces took 685 / 954 / 1950 ms and made 13k / 72k / 161k
  objects before; 110 / 111 / 194 ms and 0 / 0 / 19k after. Undo and redo still take a line as one step.

## Joins, wave placing, one-piece straights, Ctrl+Z, lag (0.5.0, 2026-10-25, the user's reports)

- **Joins as nodes**: every level join between two pieces of one kit is a node too, shown (small, white) only within
  140 px of the cursor, the nearest 24. A line started on one branches off the way it is drawn (whichever of the
  join's two ends faces that way); one ending on one merges in the way it arrives. Both pieces at the join, and
  anything within twice the smallest turn's radius plus the width along the line from it, don't count as in its way
  (it runs along the track it leaves until it has turned off). Offline: branching both ways and merging, all kits.
- **The level over a node**: stepping the level (Page Up / Down, the menu's - / +) with the cursor on a node was undone
  the next frame (the level was set to the node's every frame); it is kept as an offset for that node now, shown in
  the tip ("to +4.0 m"), and the line from it goes there. Measured in a slot: +4 m.
- **One piece per straight**: a straight is one piece, stretched up to 10 times the kit's longest (Track M: 100 m). An L
  is 3 pieces (was 9), a zigzag of 4 turns 9 (19), a loop 9 (29).
- **Placing in a wave**: still one paste (one undo step), but each piece stays hidden until its fall starts, up to
  80 ms after the one before (the whole wave 1.5 s at most), each falling 6 m in 0.35 s.
- **Ctrl+Z**: Draw Track's own undo (for when the editor doesn't get the key) waited 0.25 s and looked at the pieces;
  on a slow map the editor's undo came later and both undid (the line and the step before it). The host now counts
  the editor's undo and redo steps (Editor::HistoryMoves, from its native Undo / Redo); Draw Track undoes only when
  the editor ran none in 0.6 s, with the pencil on or off. Measured in a slot: 72 -> 21 pieces, the editor's own none.
- **Lag**: Draw Core set its ring's corner radius whenever the ring changed size (most frames the cursor moved), and a
  window's look changed builds the whole window again: the user's log had "window built with 0 widgets" ~1000 times
  and the game's objects grew from 93k to 499k in minutes. Draw Core sets it once now, and the host builds a window
  again only when a setter changes something. Draw Track draws its node balls again only when the open ends changed
  (they were all made again every 2 s). Measured in a slot: no window builds while drawing; a 51-piece line placed in
  111 ms.

## Nodes (city builders' road tools as the model)

While the pencil is on, every open end (level, of any track piece with two track ends: ends.txt, 28 pieces) shows as
a small glowing ball; the one under the cursor (within 50 px on screen, or the cursor at its level within half its
track's width) turns lime with a 20 m guide line out of it. An end counts as joined when any end (sloped too) of
another piece is within 40 cm. A line carried on from a node takes its width. The level shows at the cursor ("+3.0
m" from the start while drawing; the node's width over a node). Ctrl+Z is the editor's; if the line just built is
still there 0.25 s after Ctrl+Z (the key may not have reached the editor), Draw Track undoes it through
Editor::Undo (only while the pencil is on: then no other edit can have been made by clicking).

## Edge cases

| Case | What happens |
|---|---|
| Drawing into open space | The plane keeps its height: no jump to anything far away |
| Height above the camera (plane out of view) | The note says so; a click starts 10 m below the camera |
| Cursor near the horizon | Points further than 400 m are ignored |
| Pressing on the arena floor or scenery | Not a piece: the height stays as it was |
| Pressing on top of a piece | The line starts on it (rolling surface 1 m above) |
| Starting at an open end | Carries it on: its height and heading |
| Ending at an open end | Joins it when reachable; otherwise ends there with a note |
| Very short line | Nothing until it is longer than the smallest turn's radius |
| Tight scribble | Smoothed: wobbles under half a turn's radius are ignored |
| Turn drawn too tight for any turn | The smallest turn, with the leg lengthened |
| Line back over itself | Lifted (own pieces ending more than 4 m back along it count) |
| Line through existing track | Lifted over it with ramps (10 degrees), or stops before it in red with a reason |
| Release over a node the plane is far from | The node is the end (what the cursor is on, on screen) |
| A node the plan can't reach exactly | Fitted again without the join; the note says so |
| Slope too steep for the length | Climbs as much as the limits allow; the rest is left |
| Right click while drawing | Drops the line |
| Leaving the editor while drawing | Drops the line (only Draw Track's own) |
| Editor test run | Nothing shows; no drawing |
| Piece budget | None since the game's 2026-10-06 update |

## Measured (slot, the user's unreleased map `test`, 2026-10-24)

- The paste spawns the copied list as one undo step only inside `BeginHistory`/`EndHistory`; a bare `Paste` records
  nothing undoable. It applies each relative transform inverted, and ignores scale (set afterwards in the same step).
- Undo removed a 35-piece line in one step; redo restored it with the right scales.
- An L line (straight, turn, straight), a line carried on from an open end, a crossing lifted over a straight, a short
  slope (+4 m asked, 0.4 m given by the kink limit on 6 m) and a zigzag with four turns (18 pieces) all built joined
  (open ends only at a line's two ends).
- Inspect Draw on Draw Core: draw, erase through the middle, undo, as before.

## Later

Loops (Curve2), jumps with landing ramps, banking, a quarter-pipe wall run beside a floor, a turn's height change
spread over the straights either side, a bridge that holds its height over what it crosses before coming down.

Not yet seen in the game (round 3 was offline): the Bevel and Round pieces placed by the paste at these transforms
(the same paste as Track's; the ends' maths is the same), Round's curve at half height, and the new nodes.
