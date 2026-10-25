// Draw Track's fitter, without the game: the tables, then lines drawn with every kit, checked piece by piece.
// Run from the plugin manager's folder (build/asrun.exe is built by tools/tests/run.sh):
//   build/asrun.exe ../ballest-draw-track ../ballest-draw-track/tests/fit_test.as
//
// For each kit: an L, a zigzag, a line over a Track M lying across it (bridged), a slope, a steep climb and drop, a
// line joining a node of its own kit and one ending on another kit's node (not joined). Every line's pieces must all
// be the kit's, each entered where the one before it ends (1 cm), heading on the way it left (0.5 degrees in plan),
// its slope changing at most kKink (5 degrees) from one piece to the next (a sag's ends are tangent to the slopes
// either side), with nothing NaN.

int checks = 0;

void Check(bool ok, const string &in what)
{
    checks++;
    if (!ok)
        Fail(what);
}

bool Near(double a, double b, double tol) { return Math::abs(a - b) <= tol; }

// A stroke as Draw Core gives it: points every 50 cm along the corners given, at the plane's height z.
void Stroke(array<double>@ corners, double z)
{
    lx.resize(0);
    ly.resize(0);
    lz.resize(0);
    for (uint i = 0; i + 3 < corners.length(); i += 2)
    {
        double ax = corners[i], ay = corners[i + 1], bx = corners[i + 2], by = corners[i + 3];
        double d = Math::sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
        int n = int(d / 50);
        for (int s = 0; s < n; s++)
        {
            lx.insertLast(ax + (bx - ax) * s / n);
            ly.insertLast(ay + (by - ay) * s / n);
            lz.insertLast(z);
        }
    }
    lx.insertLast(corners[corners.length() - 2]);
    ly.insertLast(corners[corners.length() - 1]);
    lz.insertLast(z);
}

// A piece's end in the world: where (x, y, z) and which way the track runs out of it there (dx, dy, dz: the end's
// direction through the piece's scale, as a sag stretched along bends less).
void WorldEnd(Placed@ p, bool exitEnd, double &out x, double &out y, double &out z, double &out dx, double &out dy, double &out dz)
{
    KitPiece@ k = kit[p.piece];
    array<double>@ e = (exitEnd != p.viaB) ? k.b : k.a;
    array<double> m(9);
    Axes(p.pitch, p.yaw, m);
    double wx, wy, wz;
    Apply(m, e[0] * p.sx, e[1] * p.sy, e[2] * p.sz, wx, wy, wz);
    x = p.x + wx;
    y = p.y + wy;
    z = p.z + wz;
    Apply(m, e[3] * p.sx, e[4] * p.sy, e[5] * p.sz, dx, dy, dz);
    double len = Math::sqrt(dx * dx + dy * dy + dz * dz);
    dx /= len;
    dy /= len;
    dz /= len;
}

bool Finite(double v) { return v == v && Math::abs(v) < 1e12; }

int sagCount = 0;
double steepest = 0;

// The track just fitted: all of kit `k`, joined end to end. Returns how many turns it has.
int CheckChain(int k, const string &in name)
{
    sagCount = 0;
    steepest = 0;
    Check(track.length() > 0, name + ": no pieces");
    int turnCount = 0;
    double px = 0, py = 0, pz = 0, pdx = 0, pdy = 0, pdz = 0;
    for (uint i = 0; i < track.length(); i++)
    {
        Placed@ p = track[i];
        string at = name + " piece " + i + " (" + kit[p.piece].name + ")";
        Check(kit[p.piece].kit == k, at + ": not the kit's");
        Check(Finite(p.x) && Finite(p.y) && Finite(p.z) && Finite(p.pitch) && Finite(p.yaw) && Finite(p.sx) && Finite(p.sy) && Finite(p.sz), at + ": NaN");
        Check(p.sx > 0.05 && p.sy > 0.05, at + ": scaled to nothing");
        Check(Near(p.sz, kit[p.piece].sz, 1e-6), at + ": height scale " + p.sz);
        if (kit[p.piece].sag)
            sagCount++;
        else if (!kit[p.piece].turn && Math::abs(p.pitch) > steepest)
            steepest = Math::abs(p.pitch);
        if (kit[p.piece].turn)
        {
            turnCount++;
            Check(Near(p.pitch, 0, 1e-6), at + ": a turn not level");
            Check(Near(p.sx, p.sy, 1e-6), at + ": a turn not scaled evenly in plan");
        }
        double ix, iy, iz, idx, idy, idz;
        WorldEnd(p, false, ix, iy, iz, idx, idy, idz);
        if (i > 0)
        {
            double gap = Math::sqrt((ix - px) * (ix - px) + (iy - py) * (iy - py) + (iz - pz) * (iz - pz));
            Check(gap < 1, at + ": entry " + formatFloat(gap, "", 0, 2) + " cm from the last piece's exit");
            // facing each other: the entry's outward direction against the last exit's, in plan and in pitch
            double planIn = Deg(Math::atan2(-idy, -idx)), planOut = Deg(Math::atan2(pdy, pdx));
            double d = planIn - planOut;
            while (d > 180) d -= 360;
            while (d < -180) d += 360;
            Check(Math::abs(d) < 0.5, at + ": heading off by " + formatFloat(d, "", 0, 2) + " degrees");
            double kink = Deg(Math::asin(-idz)) - Deg(Math::asin(pdz));
            Check(Math::abs(kink) <= kKink + 0.1, at + ": slope changes " + formatFloat(kink, "", 0, 1) + " degrees");
        }
        WorldEnd(p, true, px, py, pz, pdx, pdy, pdz);
    }
    return turnCount;
}

void Reset(int k)
{
    kitChoice = k;
    UseKit(k);
    @startEnd = null;
    @hoverEnd = null;
    lineWidth = -1;
    widthSetting = (500 - kMinWidth) / (kMaxWidth - kMinWidth);     // 5 m
    obstacles.resize(0);
}

void Tables()
{
    ParseTables(TestRead("kit.txt"), TestRead("bounds.txt"), TestRead("ends.txt"));
    Check(kits.length() == 4, "4 kits, not " + kits.length());
    array<string> names = {"Track", "Bevel Half", "Bevel Full", "Round"};
    array<double> depths = {100, 125, 235, 149.6};
    for (uint i = 0; i < kits.length() && i < names.length(); i++)
    {
        Kit@ k = kits[i];
        Check(k.name == names[i], "kit " + i + " is " + k.name);
        Check(k.straights.length() > 0 && k.turns.length() > 0, k.name + ": a straight and a turn");
        Check(Near(k.width, 500, 1), k.name + ": width " + k.width);
        Check(Near(k.depth, depths[i], 1), k.name + ": depth " + k.depth);
        for (uint t = 0; t < k.turns.length(); t++)
            Check(Near(Math::abs(TurnSide(k.turns[t])), 1, 0), k.name + ": a turn with no side");
        Print(k.name + ": " + k.straights.length() + " straights, " + k.turns.length() + " turns (smallest radius "
              + formatFloat(TurnRadius(k.turns[0]), "", 0, 1) + "), depth " + formatFloat(k.depth, "", 0, 1));
    }
    Check(kit[kits[3].turns[0]].sz == 0.5, "Round's curve at half height");
    // ends: a Round curve is Round's only at half height; a kicker's level end is Track's; a half pipe's are no kit's
    int round = endNames.find("BP_Track_Round_Curve_C");
    Check(round >= 0 && EndKitAt(round, 0, 0.5) == 3 && EndKitAt(round, 0, 1) == -1, "Round curve's ends");
    int kicker = endNames.find("BP_Ramp_Kicker1_C");
    Check(kicker >= 0 && EndKitAt(kicker, 0, 1) == 0 && EndKitAt(kicker, 1, 1) == -1, "kicker's ends");
    int pipe = endNames.find("BP_Pipe_Half1_C");
    Check(pipe >= 0 && EndKitAt(pipe, 0, 1) == -1, "half pipe's ends");
    int bevel = endNames.find("Bevel_Full_Straight_C");
    Check(bevel >= 0 && EndKitAt(bevel, 0, 1) == 2 && EndKitAt(bevel, 1, 1) == 2, "Bevel Full straight's ends");
}

void Lines(int k)
{
    string kn = kits[k].name;
    double z = 1000;

    // an L: a straight, a turn, a straight
    Reset(k);
    Stroke({0, 0, 4000, 0, 4000, 4000}, z);
    Refit();
    int turns1 = CheckChain(k, kn + " L");
    Check(turns1 == 1, kn + " L: " + turns1 + " turns");
    Check(stopped < 0, kn + " L: stopped");
    Print(kn + " L: " + track.length() + " pieces, " + turns1 + " turn" + (fitNote != "" ? " (" + fitNote + ")" : ""));

    // a zigzag: four turns, left and right
    Reset(k);
    Stroke({0, 0, 3000, 0, 3000, 3000, 6000, 3000, 6000, 6000, 9000, 6000}, z);
    Refit();
    int turns2 = CheckChain(k, kn + " zigzag");
    Check(turns2 == 4, kn + " zigzag: " + turns2 + " turns");
    Print(kn + " zigzag: " + track.length() + " pieces, " + turns2 + " turns");

    // a slope: the level raised 3 m over the second half
    Reset(k);
    Stroke({0, 0, 8000, 0}, z);
    for (uint i = lz.length() / 2; i < lz.length(); i++)
        lz[i] = z + 300;
    Refit();
    CheckChain(k, kn + " slope");
    Placed@ last = track[track.length() - 1];
    Check(last.ez > z + 150, kn + " slope: ends at " + formatFloat(last.ez - z, "", 0, 1) + " cm up");
    Print(kn + " slope: " + track.length() + " pieces, up " + formatFloat(last.ez - z, "", 0, 1) + " cm");

    // a steep climb and drop drawn: the level up 6 m at a third of the way, back down at two thirds
    Reset(k);
    Stroke({0, 0, 9000, 0}, z);
    for (uint i = lz.length() / 3; i < 2 * lz.length() / 3; i++)
        lz[i] = z + 600;
    Refit();
    CheckChain(k, kn + " climb");
    Check(stopped < 0, kn + " climb: stopped (" + fitNote + ")");
    double top = -1e9;
    for (uint i = 0; i < track.length(); i++)
        if (track[i].ez > top)
            top = track[i].ez;
    Check(top > z + 550, kn + " climb: up only " + formatFloat(top - z, "", 0, 1) + " cm");
    Check(Near(track[track.length() - 1].ez, z, 30), kn + " climb: ends at " + formatFloat(track[track.length() - 1].ez - z, "", 0, 1) + " cm");
    Check(kits[k].sags.length() == 0 || sagCount >= 2, kn + " climb: " + sagCount + " sags");
    Print(kn + " climb: " + track.length() + " pieces, up " + formatFloat(top - z, "", 0, 1) + " cm, steepest "
          + formatFloat(steepest, "", 0, 1) + " degrees, " + sagCount + " sags");

    // the level scrolled up 3 m at the cursor without moving it (only the newest point is higher): the line's end
    // rises to it at once, the line leading up to it
    Reset(k);
    Stroke({0, 0, 4000, 0}, z);
    lz[lz.length() - 1] = z + 300;
    Refit();
    CheckChain(k, kn + " scrolled at the end");
    double endRise = track[track.length() - 1].ez - z;
    Check(Near(endRise, 300, 5), kn + " scrolled at the end: the end rose " + formatFloat(endRise, "", 0, 1) + " cm");
    Print(kn + " scrolled at the end: the end rose " + formatFloat(endRise, "", 0, 1) + " cm");

    // a climb drawn in steps, as the wheel turned while drawing gives it (2 m up every 3 m, 15 m in all): one bend at
    // the foot, a sag where the kit has them (the steps' short grades merged), not a run of short pieces
    Reset(k);
    Stroke({0, 0, 8000, 0}, z);
    for (uint i = 0; i < lz.length(); i++)
        if (lx[i] >= 2000)
            lz[i] = z + 200 * (int((lx[i] < 5000 ? lx[i] : 5000) - 2000) / 300 + 1);
    Refit();
    CheckChain(k, kn + " steps");
    int footPieces = 0;
    for (uint i = 0; i < track.length() && !kit[track[i].piece].sag && track[i].pitch < 30; i++)
        if (track[i].pitch > 0.5)
            footPieces++;
    Check(kits[k].sags.length() == 0 || (sagCount >= 1 && footPieces == 0), kn + " steps: " + sagCount + " sags, " + footPieces + " short pieces at the foot");
    Print(kn + " steps: " + track.length() + " pieces, " + sagCount + " sags");

    // over a Track M lying across the line at the line's height: bridged, clear of it
    Reset(k);
    Obstacle o;
    o.piece = 1;
    o.x = 4000;
    o.y = 0;
    o.z = z - 100;
    Axes(0, 90, o.m);
    BoxFor("BP_Track_Mid1_C", o);
    o.top = BoxTop(o);
    Bound(o);
    obstacles.insertLast(o);
    Stroke({0, 0, 8000, 0}, z);
    Refit();
    CheckChain(k, kn + " crossing");
    double over = -1e9;
    for (uint i = 0; i < track.length(); i++)
    {
        Placed@ p = track[i];
        // the rolling surface where the line crosses the piece (x 3750 to 4250)
        if ((p.jx - 4000) * (p.ex - 4000) <= 0 || Math::abs(p.jx - 4000) < 250 || Math::abs(p.ex - 4000) < 250)
        {
            double t = Math::abs(p.ex - p.jx) < 1 ? 0 : (4000 - p.jx) / (p.ex - p.jx);
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            double zz = p.jz + (p.ez - p.jz) * t;
            if (over < -1e8 || zz < over)
                over = zz;
        }
    }
    double clear = over - kitDepth - o.top;
    Check(stopped < 0, kn + " crossing: stopped (" + fitNote + ")");
    Check(clear >= 150, kn + " crossing: " + formatFloat(clear, "", 0, 1) + " cm under the bridge");
    Print(kn + " crossing: " + track.length() + " pieces, " + formatFloat(clear, "", 0, 1) + " cm clear under it (" + fitNote + ")");

    // joining a node of its own kit: an end facing back at the line's end, 40 m along and 20 m across
    Reset(k);
    OpenEnd n;
    n.x = 4000 + TurnRadius(kits[k].turns[1 < kits[k].turns.length() ? 1 : 0]) * 0;
    n.x = 4000;
    n.y = 3000;
    n.z = z;
    n.heading = -90;            // facing back toward the line (its way out of its piece)
    n.width = 500;
    n.kit = k;
    n.level = true;
    n.piece = 7;
    @hoverEnd = n;
    Stroke({0, 0, 4000, 0, 4000, 3000}, z);
    Refit();
    CheckChain(k, kn + " join");
    Placed@ end = track[track.length() - 1];
    double miss = Math::sqrt((end.ex - n.x) * (end.ex - n.x) + (end.ey - n.y) * (end.ey - n.y) + (end.ez - n.z) * (end.ez - n.z));
    Check(miss < 20, kn + " join: ends " + formatFloat(miss, "", 0, 1) + " cm from the node (" + fitNote + ")");
    Print(kn + " join: " + track.length() + " pieces, " + formatFloat(miss, "", 0, 1) + " cm from the node (" + fitNote + ")");

    // the same node as another kit's: not joined, and the note says why
    Reset(k);
    n.kit = (k + 1) % kits.length();
    @hoverEnd = n;
    Stroke({0, 0, 4000, 0, 4000, 3000}, z);
    Refit();
    CheckChain(k, kn + " other kit's node");
    Check(fitNote.findFirst("its own kind") >= 0, kn + " other kit's node: note \"" + fitNote + "\"");

    // carried on from a node of this kit, 7.5 m wide: the node's width and heading
    Reset(k);
    OpenEnd s;
    s.x = 0;
    s.y = 0;
    s.z = z;
    s.heading = 0;
    s.width = kits[k].width * 1.5;
    s.kit = k;
    s.piece = 9;
    @startEnd = s;
    lineWidth = s.width;
    Stroke({0, 0, 4000, 0, 4000, -4000}, z);
    Refit();
    CheckChain(k, kn + " from a node");
    Check(Near(track[0].jx, 0, 1) && Near(track[0].jy, 0, 1) && Near(track[0].jz, z, 1), kn + " from a node: doesn't start on it");
    Check(Near(track[0].sy, 1.5, 1e-6), kn + " from a node: width scale " + track[0].sy);
}

void Test()
{
    Tables();
    for (uint k = 0; k < kits.length(); k++)
        Lines(int(k));
    Print(checks + " checks");
}
