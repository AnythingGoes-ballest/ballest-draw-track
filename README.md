# Draw Track

A plugin for the [Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager): draw a line
in the track editor and track pieces drop into place along it.

- Turn the **pencil** on (the menu at the top of the editor, or **B**) and hold the **left mouse button** to draw.
  Outlines show the pieces the line will make; let go and they drop into place. One line is one step of the editor's
  own undo (**Ctrl+Z**).
- While the pencil is on, every open end of the track already in the map shows as a **node** (a glowing ball). Start
  on one and the new track carries it on (its height, direction and width); let go on one and the track joins it.
- In open space the line runs at the **level** shown in the menu and at the cursor. The **mouse wheel** or **Page Up**
  / **Page Down** while drawing (or the menu's **-** / **+**) raise and lower it, for slopes; the cursor shows how far
  above the start you are.
- The track is real kit pieces joined end to end: straights stretched to fit, 90-degree curves sized to how wide you
  drew each turn (from the curves the kit has), and slopes as steep as you draw them (up to 45 degrees). Track's
  slopes start and end on its own ramp pieces (Ramp Curve1); tops are rounded with short pieces a few degrees apart. Where it would pass through a piece already there, it ramps up over it
  as a bridge; if it can't climb in time, the rest shows red and says to raise the level or go round.
- **Kit** (the menu's list): **Track**, **Bevel Half**, **Bevel Full** or **Round**. A line started on a node is that
  node's kit (the menu switches to it); a line joins only nodes of its own kit (the others show small and grey).
  Round has one curve, a wide one (12.7 m at 5 m wide), so its turns are smoothed more.
- **Width** (2.5 to 10 m) sets the track's width. A **right click** while drawing drops the line.

Needs Draw Core (installed with it) and host 0.31.0. See [DESIGN.md](DESIGN.md) for how the line is fitted.
