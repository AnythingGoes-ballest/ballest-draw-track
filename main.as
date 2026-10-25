// Draw Track: draw a line in the track editor and track pieces fall into place along it when you let go.
//
// With the pencil on (the menu, or B), hold the left mouse button and draw. The line runs on a level plane at the
// track's height: where you start on an existing track's open end, that end's height (and the new track carries it
// on); on top of a piece, just above it; in open space, the height you used last. The mouse wheel (or Page Up and
// Page Down) raises and lowers the line while you draw, for slopes. See-through outlines show the pieces the line
// will make; let go and they drop into place, all in one step of the editor's own undo. A right click while drawing
// drops the line.
//
// The line becomes real kit pieces joined end to end (straights stretched to fit, 90-degree curves, slopes from pitched
// straights): the closest track to what was drawn that the ball can ride. A kit is a set of pieces whose ends all meet
// (Track, Bevel Half, Bevel Full, Round), picked in the menu; a line carried on from a node is that node's kit. Turns
// are smoothed to the curve whose size best matches how wide the turn was drawn; slopes follow the heights drawn (up to
// 45 degrees), bend up through the kit's own ramp pieces (sags) and over the top through the same ramps turned upside
// down (crests) where it has them, else through short pieces a few degrees apart, and turns stay level.
//
// While the pencil is on, every open end of the track already in the map shows as a node: a line started on one
// carries it on (its height, heading and width), and a line ending on one joins it when the pieces can meet it exactly.
// The joins between pieces already in the map are nodes too, shown near the cursor: a line started on one branches off
// there (the way it is drawn), one ending on one merges in. A line drawn back to its own start closes into a loop.
// Where the track would pass through a piece already there (or itself), it rises over it as a bridge with ramps either
// side, or ends before it when it can't climb in time or the piece is too tall.
//
// The shape of it follows how city builders' road tools work: nodes shown and snapped to, the road type carried on
// from a node, an explicit level changed a step at a time and shown at the cursor, clearance needed under bridges,
// and a placement that can't be made shown in red with the reason rather than forced.
//
// The drawing itself (the mouse, the plane, the layer that keeps the editor from taking the clicks, the ring) is
// Draw Core's; the kits (kit.txt), every piece's ends (ends.txt) and boxes (bounds.txt) come from the game's own data
// (tools/make_tables.py).

import void DrawCore_Frame(bool, bool, bool, int, double, double, double, double, double) from "draw-core";
import int DrawCore_State() from "draw-core";
import int DrawCore_Count() from "draw-core";
import int DrawCore_ChangedFrom() from "draw-core";
import void DrawCore_Point(int, double &out, double &out, double &out) from "draw-core";
import void DrawCore_Cancel() from "draw-core";
import bool DrawCore_OnPlane(float, float, double, double &out, double &out, double &out, double &out) from "draw-core";

const int kPlacePlane = 1;                      // Draw Core's placement on a level plane
const int kStateDrawing = 1, kStateFinished = 2;

// ---------------------------------------------------------------- the kit

class KitPiece
{
    int kit;                    // which kit (kits)
    string name;
    string classPath;
    bool turn;
    bool sag;                   // a ramp curve: level in plan, bending the track upward (its ends both tilt up)
    bool crest;                 // a ramp curve rolled over: bending the track downward, ridden on its underside
    double roll = 0;            // degrees, as placed (a crest: 180; its ends are in its frame before the roll)
    array<double> a(6);         // end A: x y z (where the rolling surface meets it), outward dx dy dz
    array<double> b(6);
    double width = 500;         // the track's width at scale 1
    double sz = 1;              // the height scale the kit uses it at (Round's curve: half)
}

array<KitPiece@> kit;

// A kit: pieces whose ends all meet (checked by tools/make_tables.py), straights stretched to fit and 90-degree turns.
class Kit
{
    string name;
    array<int> straights;       // kit indexes, shortest first
    array<int> turns;           // kit indexes, smallest first
    array<int> sags;            // kit indexes, largest first
    array<int> crests;          // kit indexes, largest first
    double width = 500;         // the track's width at scale 1
    double depth = 100;         // how far a piece reaches below its rolling surface (scale 1)
}
array<Kit@> kits;
int kitChoice = 0;              // the menu's kit
int lineKit = 0;                // the line's: its node's when it carries one on, else the menu's
array<int> straights, turns, sags, crests;  // the line's kit's, for the fitter (UseKit)
double kitWidth = 500, kitDepth = 100;

void UseKit(int k)
{
    lineKit = k;
    straights = kits[k].straights;
    turns = kits[k].turns;
    sags = kits[k].sags;
    crests = kits[k].crests;
    kitWidth = kits[k].width;
    kitDepth = kits[k].depth;
}

// Every track piece's two ends (ends.txt), by class name: for the open ends of the track already in the map. An end
// is a kit's (a node a line can carry on or join) when the piece is at that kit's height scale for it.
array<string> endNames;
array<array<double>@> endA, endB;
array<int> endKitA, endKitB;            // kit index, or -1
array<double> endScaleA, endScaleB;

class Box                       // a piece's box, by class name: centre and half size in its own frame
{
    double cx, cy, cz, hx, hy, hz;
}
array<string> boxNames;        // by class name (Box at the same index)
array<Box@> boxList;

// ---------------------------------------------------------------- the track being drawn

// One piece of the fitted track: which kit piece, entered by which end, and where it goes.
class Placed
{
    int piece;
    bool viaB;                  // entered by end B (a turn the other way)
    double x, y, z;             // the piece's location
    double pitch, yaw;          // degrees
    double roll = 0;            // degrees (a crest: 180)
    double sx, sy, sz;          // scale
    double jx, jy, jz;          // where its entry is (the joint)
    double ex, ey, ez;          // where its exit is
    double length;              // along the track, in plan (cm)
    bool curved = false;        // a sag: its rolling surface bends from the entry's slope to the exit's
    double cx, cy, cz;          // a sag's corner: where the entry's and the exit's slopes meet
    double pathEnd;             // distance along the track to its exit
    bool blocked;               // cuts through something it couldn't be lifted over
}

// An open end of the track already in the map: where the rolling surface meets it, and which way it faces.
class OpenEnd
{
    double x, y, z;
    double heading;             // degrees: the way out of the piece, in plan
    double width;               // the track's width there (cm)
    bool level = true;          // only a level end is a node (a sloped one still counts as joining its neighbour)
    int kit = -1;               // the kit it is (only a kit's end is a node; any end counts as joining its neighbour)
    int piece;
    bool joined = false;        // another piece's end is on it: a join between two pieces (a node shown near the cursor)
    OpenEnd@ twin;              // a join's other end (the other piece's, facing the other way)
}

// One part of the line's plan: a straight (its length in plan) or a 90-degree turn.
class Seg
{
    bool turn;
    double length;
    int piece;
    bool viaB;
    int side;
    int first, last;            // the line's points it came from
}

const double kSnapPixels = 40;          // an open end this close to the cursor on screen is where a line starts/ends
const double kHeightStep = 50;          // cm per wheel notch
const double kFarthest = 40000;         // cm: the line's points no further from the camera than this
const double kMinWidth = 250, kMaxWidth = 1000;
// the editor's placement limits (the game's own bounds, measured): pieces outside them aren't placed
const double kMinX = -31062, kMaxX = 30438, kMinY = -34598, kMaxY = 26902, kMinZ = -6569, kMaxZ = 177931;

bool pencil = true;
float widthSetting = 0.33f;             // 0..1, see TrackWidth()
double height = -1e9;                   // the line's height: the plane's (the rolling surface's) z; unset at first
bool heightSet = false;
bool unreachable = false;               // the cursor can't reach the line's height from here
array<OpenEnd@> openEnds;
double openEndsAt = -10;
OpenEnd@ startEnd;                      // the open end the line being drawn carries on from, or null
OpenEnd@ hoverEnd;                      // the open end under the cursor now
double startHeading = 0;
array<Placed@> track;                   // the fitted pieces of the line being drawn
string fitNote = "";
double fitAt = -10;
int fittedCount = -1;
int ghost = 0, ghostBad = 0;

// ---------------------------------------------------------------- UI

UI::Window@ menu;
UI::Button@ pencilButton;
UI::Dropdown@ kitBox;
UI::Slider@ widthSlider;
UI::Text@ widthText;
UI::Text@ heightText;
UI::Button@ downButton;
UI::Button@ upButton;
UI::Text@ noteText;
UI::Window@ tip;                        // the level (or the node) at the cursor
UI::Text@ tipText;

const string kFont = "/Game/UI/Fonts/CocogoosePro.CocogoosePro";
const float BOX_R = 0.08f, BOX_G = 0.08f, BOX_B = 0.09f;
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;
const float LIME_R = 0.80f, LIME_G = 1.0f, LIME_B = 0.0f;

OpenEnd@ offsetNode;                    // the node the level offset below is for
double nodeOffset = 0;                  // the level stepped up or down over the node under the cursor (cm)
double lineWidth = -1;                  // the line being drawn: its node's width when carried on from one, else -1
double TrackWidth() { return lineWidth > 0 ? lineWidth : kMinWidth + widthSetting * (kMaxWidth - kMinWidth); }
double WidthScale() { return TrackWidth() / kitWidth; }
string KitLabel(int k) { return k >= 0 && k < int(kits.length()) ? Lower(kits[k].name) : "no kit's"; }
string Lower(const string &in text)
{
    string r = text;
    for (uint i = 0; i < r.length(); i++)
        if (r[i] >= 65 && r[i] <= 90)
            r[i] = r[i] + 32;
    return r;
}
double Rad(double d) { return d * 3.14159265358979 / 180; }
double Deg(double r) { return r * 180 / 3.14159265358979; }

// ---------------------------------------------------------------- loading the tables

array<double>@ Numbers(const string &in text)
{
    array<string>@ parts = text.split(" ");
    array<double> values;
    for (uint i = 0; i < parts.length(); i++)
        if (parts[i] != "")
            values.insertLast(parseFloat(parts[i]));
    return values;
}

void LoadTables()
{
    ParseTables(Plugins::ReadFile("kit.txt"), Plugins::ReadFile("bounds.txt"), Plugins::ReadFile("ends.txt"));
    Log::Info("ends of " + endNames.length() + " track pieces; " + kits.length() + " kits, " + kit.length() + " pieces; " + boxNames.length() + " piece boxes");
}

// A kit by name, made when new.
int KitNamed(const string &in name)
{
    for (uint i = 0; i < kits.length(); i++)
        if (kits[i].name == name)
            return int(i);
    Kit k;
    k.name = name;
    kits.insertLast(k);
    return int(kits.length()) - 1;
}

// "Track@1": the kit's index (-1 for none or an unknown one) and the height scale.
void EndKit(const string &in text, int &out index, double &out scale)
{
    index = -1;
    scale = 1;
    int at = text.findFirst("@");
    if (at <= 0)
        return;
    string name = text.substr(0, at);
    for (uint i = 0; i < kits.length(); i++)
        if (kits[i].name == name)
            index = int(i);
    scale = parseFloat(text.substr(at + 1));
}

void ParseTables(const string &in kitText, const string &in boundsText, const string &in endsText)
{
    array<string>@ lines = kitText.split("\n");
    for (uint i = 0; i < lines.length(); i++)
    {
        if (lines[i] == "" || lines[i].substr(0, 1) == "#")
            continue;
        array<string>@ f = lines[i].split("|");
        if (f.length() < 8)
            continue;
        KitPiece k;
        k.kit = KitNamed(f[0]);
        k.name = f[1];
        k.classPath = f[2];
        k.turn = f[3] == "turn";
        k.sag = f[3] == "sag";
        k.crest = f[3] == "crest";
        k.roll = f.length() > 8 ? parseFloat(f[8]) : 0;
        array<double>@ a = Numbers(f[4]);
        array<double>@ b = Numbers(f[5]);
        if (a.length() < 6 || b.length() < 6)
            continue;
        k.a = a;
        k.b = b;
        k.width = parseFloat(f[6]);
        k.sz = parseFloat(f[7]);
        kit.insertLast(k);
        int index = int(kit.length()) - 1;
        if (k.turn)
            kits[k.kit].turns.insertLast(index);
        else if (k.sag)
            kits[k.kit].sags.insertLast(index);
        else if (k.crest)
            kits[k.kit].crests.insertLast(index);
        else
        {
            kits[k.kit].straights.insertLast(index);
            kits[k.kit].width = k.width;
        }
    }
    // straights shortest first, turns smallest first
    for (uint n = 0; n < kits.length(); n++)
    {
        array<int>@ st = kits[n].straights;
        for (uint i = 0; i < st.length(); i++)
            for (uint j = i + 1; j < st.length(); j++)
                if (StraightLength(st[j]) < StraightLength(st[i]))
                {
                    int t = st[i];
                    st[i] = st[j];
                    st[j] = t;
                }
        for (int list = 0; list < 2; list++)
        {
            array<int>@ sa = list == 0 ? kits[n].sags : kits[n].crests;
            for (uint i = 0; i < sa.length(); i++)
                for (uint j = i + 1; j < sa.length(); j++)
                    if (SagHalfSpan(sa[j]) > SagHalfSpan(sa[i]))
                    {
                        int t = sa[i];
                        sa[i] = sa[j];
                        sa[j] = t;
                    }
        }
        array<int>@ tu = kits[n].turns;
        for (uint i = 0; i < tu.length(); i++)
            for (uint j = i + 1; j < tu.length(); j++)
                if (TurnRadius(tu[j]) < TurnRadius(tu[i]))
                {
                    int t = tu[i];
                    tu[i] = tu[j];
                    tu[j] = t;
                }
    }

    lines = boundsText.split("\n");
    for (uint i = 0; i < lines.length(); i++)
    {
        if (lines[i] == "" || lines[i].substr(0, 1) == "#")
            continue;
        array<string>@ f = lines[i].split("|");
        if (f.length() < 3)
            continue;
        array<double>@ c = Numbers(f[1]);
        array<double>@ h = Numbers(f[2]);
        if (c.length() < 3 || h.length() < 3)
            continue;
        Box box;
        box.cx = c[0];
        box.cy = c[1];
        box.cz = c[2];
        box.hx = h[0];
        box.hy = h[1];
        box.hz = h[2];
        boxNames.insertLast(f[0]);
        boxList.insertLast(box);
    }
    // each kit's depth: its first straight's, from its rolling surface to the bottom of its box
    for (uint n = 0; n < kits.length(); n++)
        if (kits[n].straights.length() > 0)
        {
            KitPiece@ p = kit[kits[n].straights[0]];
            int at = boxNames.find(ClassName(p.classPath));
            if (at >= 0)
                kits[n].depth = p.a[2] - (boxList[at].cz - boxList[at].hz);
        }

    lines = endsText.split("\n");
    for (uint i = 0; i < lines.length(); i++)
    {
        if (lines[i] == "" || lines[i].substr(0, 1) == "#")
            continue;
        array<string>@ f = lines[i].split("|");
        if (f.length() < 5)
            continue;
        array<double>@ a = Numbers(f[1]);
        array<double>@ b = Numbers(f[2]);
        if (a.length() < 6 || b.length() < 6)
            continue;
        int ka, kb;
        double sa, sb;
        EndKit(f[3], ka, sa);
        EndKit(f[4], kb, sb);
        endNames.insertLast(f[0]);
        endA.insertLast(a);
        endB.insertLast(b);
        endKitA.insertLast(ka);
        endKitB.insertLast(kb);
        endScaleA.insertLast(sa);
        endScaleB.insertLast(sb);
    }
}

// The kit end `end` (0: A, 1: B) of ends.txt row `e` is when its piece is at height scale `sz`, or -1: an end is a
// kit's only at the height scale the kit uses it at (Round's curve at full height doesn't meet Round's straights).
int EndKitAt(int e, int end, double sz)
{
    int k = end == 0 ? endKitA[e] : endKitB[e];
    double scale = end == 0 ? endScaleA[e] : endScaleB[e];
    return k >= 0 && Math::abs(sz - scale) < 0.05 ? k : -1;
}

// The kit's crest made from the piece of this class, or -1.
int CrestOfClass(const string &in cls)
{
    for (uint i = 0; i < kit.length(); i++)
        if (kit[i].crest && ClassName(kit[i].classPath) == cls)
            return int(i);
    return -1;
}

string ClassName(const string &in classPath)
{
    int dot = classPath.findLast(".");
    return classPath.substr(dot + 1);
}

// A straight's length at scale 1.
double StraightLength(int k)
{
    KitPiece@ p = kit[k];
    return Math::sqrt((p.b[0] - p.a[0]) * (p.b[0] - p.a[0]) + (p.b[1] - p.a[1]) * (p.b[1] - p.a[1]));
}

// A sag's (or crest's) half span (its ends' distance apart along it, halved) and the angle its ends tilt (radians), at
// scale 1.
double SagHalfSpan(int k)
{
    KitPiece@ p = kit[k];
    return StraightLength(k) / 2;
}
double SagHalfAngle(int k)
{
    KitPiece@ p = kit[k];
    return Math::atan2(p.a[5], Math::sqrt(p.a[3] * p.a[3] + p.a[4] * p.a[4]));
}

// The line's kit's straight for a piece `length` long: the one stretched least.
int StraightFor(double length)
{
    int best = straights[0];
    double bestRatio = 1e30;
    for (uint i = 0; i < straights.length(); i++)
    {
        double r = length / StraightLength(straights[i]);
        if (r < 1)
            r = 1 / r;
        if (r < bestRatio)
        {
            bestRatio = r;
            best = straights[i];
        }
    }
    return best;
}

// A turn's radius at scale 1: how far its exit is ahead of (and beside) its entry.
double TurnRadius(int k)
{
    KitPiece@ p = kit[k];
    double fx = -p.a[3], fy = -p.a[4];          // forward, entering by A
    double ex = p.b[0] - p.a[0], ey = p.b[1] - p.a[1];
    return Math::abs(ex * fx + ey * fy);
}

// The way a turn turns when entered by end A: +1 toward +90 degrees (the right, in the game's frame), -1 the other.
int TurnSide(int k)
{
    KitPiece@ p = kit[k];
    double fx = -p.a[3], fy = -p.a[4];
    double ex = p.b[0] - p.a[0], ey = p.b[1] - p.a[1];
    double lat = -fy * ex + fx * ey;            // along +90 from forward
    return lat > 0 ? 1 : -1;
}

// ---------------------------------------------------------------- rotations (the game's: pitch, yaw, roll 0)

void Axes(double pitch, double yaw, array<double>@ m)
{
    double p = Rad(pitch), y = Rad(yaw);
    double cp = Math::cos(p), sp = Math::sin(p), cy = Math::cos(y), sy = Math::sin(y);
    // columns: X (forward), Y (right), Z (up)
    m[0] = cp * cy; m[1] = cp * sy; m[2] = sp;
    m[3] = -sy;     m[4] = cy;      m[5] = 0;
    m[6] = -sp * cy; m[7] = -sp * sy; m[8] = cp;
}

void Apply(array<double>@ m, double x, double y, double z, double &out wx, double &out wy, double &out wz)
{
    wx = x * m[0] + y * m[3] + z * m[6];
    wy = x * m[1] + y * m[4] + z * m[7];
    wz = x * m[2] + y * m[5] + z * m[8];
}

// Puts kit piece `k` with its entry end at the joint (jx, jy, jz), heading `heading` in plan and pitched `pitch`.
Placed@ Put(int k, bool viaB, double jx, double jy, double jz, double heading, double pitch, double sx, double sy)
{
    KitPiece@ p = kit[k];
    array<double>@ inEnd = viaB ? p.b : p.a;
    array<double>@ outEnd = viaB ? p.a : p.b;
    double localHeading = Deg(Math::atan2(-inEnd[4], -inEnd[3]));
    Placed q;
    q.piece = k;
    q.viaB = viaB;
    q.yaw = heading - localHeading;
    q.pitch = pitch;
    q.sx = sx;
    q.sy = sy;
    q.sz = p.sz;
    q.roll = p.roll;
    // a straight entered by B points backwards: its pitch is turned round with it
    if (!p.turn && Math::abs(localHeading) > 90)
        q.pitch = -pitch;
    array<double> m(9);
    AxesRoll(q.pitch, q.yaw, q.roll, m);
    double ix, iy, iz, ox, oy, oz;
    Apply(m, inEnd[0] * sx, inEnd[1] * sy, inEnd[2] * q.sz, ix, iy, iz);
    Apply(m, outEnd[0] * sx, outEnd[1] * sy, outEnd[2] * q.sz, ox, oy, oz);
    q.x = jx - ix;
    q.y = jy - iy;
    q.z = jz - iz;
    q.jx = jx;
    q.jy = jy;
    q.jz = jz;
    q.ex = q.x + ox;
    q.ey = q.y + oy;
    q.ez = q.z + oz;
    q.length = Math::sqrt((q.ex - jx) * (q.ex - jx) + (q.ey - jy) * (q.ey - jy));
    q.blocked = false;
    return q;
}

// ---------------------------------------------------------------- open ends already in the map

// The map's pieces: each one an obstacle (a turned box, or a ring sector for a turn), and the open ends of every
// track piece (ends.txt) that are level: the nodes a line can start from or join.
void FindPieces()
{
    openEnds.resize(0);
    obstacles.resize(0);
    array<int>@ pieces = Editor::Pieces();
    array<OpenEnd@> all;
    for (uint i = 0; i < pieces.length(); i++)
    {
        string cls = Editor::PieceClass(pieces[i]);
        double x, y, z, pitch, yaw, roll, sx, sy, sz;
        if (!Editor::GetLocation(pieces[i], x, y, z) || !Editor::GetRotation(pieces[i], pitch, yaw, roll) || !Editor::GetScale(pieces[i], sx, sy, sz))
            continue;
        Obstacle o;
        o.piece = pieces[i];
        o.x = x;
        o.y = y;
        o.z = z;
        AxesRoll(pitch, yaw, roll, o.m);
        o.sx = sx;
        o.sy = sy;
        o.sz = sz;
        bool hasBox = BoxFor(cls, o);
        if (hasBox)
            o.top = BoxTop(o);
        int e = endNames.find(cls);
        if (e >= 0)
        {
            double ax, ay, az, adx, ady, adz, bx, by, bz, bdx, bdy, bdz;
            array<double>@ a = endA[e];
            array<double>@ b = endB[e];
            // a ramp turned over (a crest) is ridden on its underside: its crest ends
            int over = Math::abs(Math::abs(roll) - 180) < 10 ? CrestOfClass(cls) : -1;
            if (over >= 0)
            {
                @a = kit[over].a;
                @b = kit[over].b;
            }
            Apply(o.m, a[0] * sx, a[1] * sy, a[2] * sz, ax, ay, az);
            Apply(o.m, a[3], a[4], a[5], adx, ady, adz);
            Apply(o.m, b[0] * sx, b[1] * sy, b[2] * sz, bx, by, bz);
            Apply(o.m, b[3], b[4], b[5], bdx, bdy, bdz);
            int ka = EndKitAt(e, 0, sz), kb = EndKitAt(e, 1, sz);
            double width = (ka >= 0 ? kits[ka].width : 500) * sy;
            double depth = (hasBox ? a[2] - (o.bcz - o.bhz) : 100) * sz;
            if (Math::abs(adz) < 0.05 && Math::abs(bdz) < 0.05 && Math::abs(az - bz) < 5)
                ArcFrom(o, x + ax, y + ay, z + az, adx, ady, x + bx, y + by, bdx, bdy, width, depth);
            for (int end = 0; end < 2; end++)
            {
                double ex = end == 0 ? ax : bx, ey = end == 0 ? ay : by, ez = end == 0 ? az : bz;
                double dx = end == 0 ? adx : bdx, dy = end == 0 ? ady : bdy, dz = end == 0 ? adz : bdz;
                OpenEnd n;
                n.level = Math::abs(dz) <= 0.05 && Math::abs(roll) <= 1;    // lines start and end level
                n.x = x + ex;
                n.y = y + ey;
                n.z = z + ez;
                n.heading = Deg(Math::atan2(dy, dx));
                n.kit = end == 0 ? ka : kb;
                n.width = (n.kit >= 0 ? kits[n.kit].width : 500) * sy;
                n.piece = pieces[i];
                all.insertLast(n);
            }
        }
        if (hasBox)
        {
            Bound(o);
            obstacles.insertLast(o);
        }
    }
    // an end with another end on it is joined, not open; a level join of one kit's two ends is a node of its own
    joinEnds.resize(0);
    for (uint i = 0; i < all.length(); i++)
    {
        int partner = -1;
        for (uint j = 0; j < all.length() && partner < 0; j++)
            if (i != j && all[i].piece != all[j].piece)
            {
                double dx = all[i].x - all[j].x, dy = all[i].y - all[j].y, dz = all[i].z - all[j].z;
                if (dx * dx + dy * dy + dz * dz < 40 * 40)
                    partner = int(j);
            }
        if (partner < 0 && all[i].level && all[i].kit >= 0)
            openEnds.insertLast(all[i]);
        if (partner >= 0 && all[i].level && all[i].kit >= 0 && all[uint(partner)].level && all[uint(partner)].kit == all[i].kit)
        {
            all[i].joined = true;
            @all[i].twin = all[uint(partner)];
            joinEnds.insertLast(all[i]);
        }
    }
    // the node balls are drawn again only when the open ends changed (every 2 s they were all made again: churn)
    double sign = openEnds.length();
    for (uint i = 0; i < openEnds.length(); i++)
        sign += openEnds[i].x * 1.3 + openEnds[i].y * 1.7 + openEnds[i].z * 2.1 + openEnds[i].kit * 7;
    if (sign != markedSign)
        markersDirty = true;
    markedSign = sign;
}
double markedSign = -1;

// Whether a point is on one of the map's pieces, not the arena or the scenery around it.
bool OnAPiece(double x, double y, double z)
{
    for (uint o = 0; o < obstacles.length(); o++)
        if (Inside(obstacles[o], x, y, z, 20))
            return true;
    return false;
}

void AxesRoll(double pitch, double yaw, double roll, array<double>@ m)
{
    double p = Rad(pitch), y = Rad(yaw), r = Rad(roll);
    double cp = Math::cos(p), sp = Math::sin(p), cy = Math::cos(y), sy = Math::sin(y), cr = Math::cos(r), sr = Math::sin(r);
    m[0] = cp * cy;                      m[1] = cp * sy;                      m[2] = sp;
    m[3] = sr * sp * cy - cr * sy;       m[4] = sr * sp * sy + cr * cy;       m[5] = -sr * cp;
    m[6] = -(cr * sp * cy + sr * sy);    m[7] = cy * sr - cr * sp * sy;       m[8] = cr * cp;
}

// The joins between pieces already in the map (each join's two ends), and the ones near the cursor now (one end of
// each): those show as nodes, and the cursor can take one.
array<OpenEnd@> joinEnds;
array<OpenEnd@> nearJoins;
const double kRevealPixels = 140;       // a join this close to the cursor on screen shows
const int kMaxNearJoins = 24;

void FindNearJoins(float mx, float my)
{
    nearJoins.resize(0);
    array<double> dist;
    for (uint i = 0; i < joinEnds.length(); i++)
    {
        OpenEnd@ e = joinEnds[i];
        if (e.twin !is null && e.twin.piece < e.piece)
            continue;                   // one end of each join
        float sx, sy;
        if (!Camera::Project(e.x, e.y, e.z, sx, sy))
            continue;
        double d = Math::sqrt((sx - mx) * (sx - mx) + (sy - my) * (sy - my));
        if (d > kRevealPixels)
            continue;
        uint at = 0;
        while (at < dist.length() && dist[at] <= d)
            at++;
        if (at >= uint(kMaxNearJoins))
            continue;
        dist.insertAt(at, d);
        nearJoins.insertAt(at, e);
        if (nearJoins.length() > uint(kMaxNearJoins))
        {
            nearJoins.removeLast();
            dist.removeLast();
        }
    }
}

// The node under the cursor (an open end, or a join near the cursor): within kSnapPixels of it on screen, or the
// cursor at its level within half its track's width (2 m at least) of it, so far nodes are as easy to hit as near
// ones. The nearest wins (an open end over a join as near); null if none.
OpenEnd@ EndUnderCursor(float mx, float my)
{
    OpenEnd@ best = null;
    double bestScore = 1e30;
    for (uint i = 0; i < openEnds.length() + nearJoins.length(); i++)
    {
        OpenEnd@ e = i < openEnds.length() ? openEnds[i] : nearJoins[i - openEnds.length()];
        double score = 1e30;
        float sx, sy;
        if (Camera::Project(e.x, e.y, e.z, sx, sy))
        {
            double d = Math::sqrt((sx - mx) * (sx - mx) + (sy - my) * (sy - my));
            if (d <= kSnapPixels)
                score = d;
        }
        double px, py, pz, along;
        if (DrawCore_OnPlane(mx, my, e.z, px, py, pz, along))
        {
            double reach = e.width / 2 > 200 ? e.width / 2 : 200;
            double d = Math::sqrt((px - e.x) * (px - e.x) + (py - e.y) * (py - e.y));
            if (d <= reach && d / reach * kSnapPixels < score)
                score = d / reach * kSnapPixels;
        }
        if (e.joined)
            score *= 1.15;
        if (score < bestScore)
        {
            bestScore = score;
            @best = e;
        }
    }
    return best;
}

// ---------------------------------------------------------------- nodes shown

bool markersDirty = true;
int markedKit = -1;                     // the kit the nodes were shown for
array<int> markers;
array<int> joinMarks;                   // the joins near the cursor
array<OpenEnd@> markedJoins;
int hoverMark = 0, guide = 0;
OpenEnd@ markedHover;

void ClearJoinMarks()
{
    for (uint i = 0; i < joinMarks.length(); i++)
        Draw::Remove(joinMarks[i]);
    joinMarks.resize(0);
    markedJoins.resize(0);
}

void ClearMarkers()
{
    ClearJoinMarks();
    for (uint i = 0; i < markers.length(); i++)
        Draw::Remove(markers[i]);
    markers.resize(0);
    if (hoverMark != 0)
        Draw::Remove(hoverMark);
    if (guide != 0)
        Draw::Remove(guide);
    hoverMark = 0;
    guide = 0;
    @markedHover = null;
}

// Every node as a small glowing ball while the pencil is on; the one under the cursor bigger and lime, with a guide
// line out of it the way a line from it goes.
void ShowMarkers(bool on)
{
    if (!on)
    {
        if (markers.length() > 0 || hoverMark != 0)
            ClearMarkers();
        markersDirty = true;
        return;
    }
    int shownKit = DrawCore_State() == kStateDrawing ? lineKit : kitChoice;
    if (markersDirty || shownKit != markedKit)
    {
        ClearMarkers();
        markersDirty = false;
        markedKit = shownKit;
        // the kit's own nodes (the ones a line can join) bright, other kits' smaller and grey
        for (uint i = 0; i < openEnds.length() && i < 200; i++)
        {
            bool own = openEnds[i].kit == shownKit;
            int b = own ? Draw::Ball(45, 0.1f, 0.75f, 1, true) : Draw::Ball(30, 0.55f, 0.58f, 0.62f, true);
            Draw::Move(b, openEnds[i].x, openEnds[i].y, openEnds[i].z + 20);
            markers.insertLast(b);
        }
    }
    // the joins near the cursor: small and white, only while it is near them
    bool same = markedJoins.length() == nearJoins.length();
    for (uint i = 0; i < nearJoins.length() && same; i++)
        same = markedJoins[i] is nearJoins[i];
    if (!same)
    {
        ClearJoinMarks();
        for (uint i = 0; i < nearJoins.length(); i++)
        {
            int b = Draw::Ball(32, 0.92f, 0.96f, 1, true);
            Draw::Move(b, nearJoins[i].x, nearJoins[i].y, nearJoins[i].z + 20);
            joinMarks.insertLast(b);
            markedJoins.insertLast(nearJoins[i]);
        }
    }
    if (hoverEnd is markedHover)
        return;
    @markedHover = hoverEnd;
    if (hoverMark != 0)
        Draw::Remove(hoverMark);
    if (guide != 0)
        Draw::Remove(guide);
    hoverMark = 0;
    guide = 0;
    if (hoverEnd is null)
        return;
    hoverMark = Draw::Ball(90, LIME_R, LIME_G, LIME_B, true);
    Draw::Move(hoverMark, hoverEnd.x, hoverEnd.y, hoverEnd.z + 20);
    // the way a line from it goes (a join: both ways along the track)
    double h = Rad(hoverEnd.heading);
    double back = hoverEnd.joined ? 2000 : 0;
    array<double> pair = {hoverEnd.x - Math::cos(h) * back, hoverEnd.y - Math::sin(h) * back, hoverEnd.z + 10,
                          hoverEnd.x + Math::cos(h) * 2000, hoverEnd.y + Math::sin(h) * 2000, hoverEnd.z + 10};
    guide = Draw::Segments(pair, 8, LIME_R, LIME_G, LIME_B, true, 0.5f);
}

// ---------------------------------------------------------------- fitting

class Leg
{
    int dir;                    // 0..3: the start heading turned by dir * 90 degrees
    double line;                // its line: the cross coordinate it runs along
    int first, last;            // the points it came from
    double turnRadius;          // the turn at its end (cm), 0 for the last leg
    int turnPiece;
}

// Points of the line in the start's frame: u along the start heading, v at +90 degrees to it.
array<double> pu, pv, pz;

double Along(int dir, double u, double v) { return dir == 0 ? u : (dir == 1 ? v : (dir == 2 ? -u : -v)); }
double Across(int dir, double u, double v) { return dir == 0 ? v : (dir == 1 ? -u : (dir == 2 ? -v : u)); }

// Ramer-Douglas-Peucker: the indexes of the points kept within `tol`.
void Simplify(int a, int b, double tol, array<int>@ keep)
{
    double ux = pu[b] - pu[a], vy = pv[b] - pv[a];
    double len = Math::sqrt(ux * ux + vy * vy);
    double worst = -1;
    int at = -1;
    for (int i = a + 1; i < b; i++)
    {
        double d;
        if (len < 1e-6)
            d = Math::sqrt((pu[i] - pu[a]) * (pu[i] - pu[a]) + (pv[i] - pv[a]) * (pv[i] - pv[a]));
        else
            d = Math::abs((pu[i] - pu[a]) * vy - (pv[i] - pv[a]) * ux) / len;
        if (d > worst)
        {
            worst = d;
            at = i;
        }
    }
    if (worst > tol && at > 0)
    {
        Simplify(a, at, tol, keep);
        keep.insertLast(at);
        Simplify(at, b, tol, keep);
    }
}

// The four directions as a cross coordinate's sign: a leg along dir d has its line in this coordinate.
double LineOf(int dir, double u, double v) { return (dir % 2 == 0) ? v : u; }

// The corner where leg `k` (along dir) meets the next one: the point on leg k's line at the next leg's line.
void Corner(Leg@ a, Leg@ b, double &out u, double &out v)
{
    if (a.dir % 2 == 0)
    {
        u = b.line;
        v = a.line;
    }
    else
    {
        u = a.line;
        v = b.line;
    }
}

bool joinsEnd = false;                  // the plan runs into the open end it is to join

// The line's plan: legs along the start heading's four directions, each a straight and the turn at its end.
array<Seg@>@ Fit(array<double>@ xs, array<double>@ ys, array<double>@ zs, double jx, double jy, double jz, double a0,
                 OpenEnd@ endAt)
{
    array<Seg@> segs;
    joinsEnd = false;
    int n = int(xs.length());
    double f = WidthScale();
    if (n < 2 || straights.length() == 0 || turns.length() == 0)
        return segs;
    double rs = TurnRadius(turns[0]) * f;

    // the points in the start's frame
    double ca = Math::cos(Rad(a0)), sa = Math::sin(Rad(a0));
    pu.resize(n);
    pv.resize(n);
    pz.resize(n);
    for (int i = 0; i < n; i++)
    {
        double dx = xs[i] - jx, dy = ys[i] - jy;
        pu[i] = dx * ca + dy * sa;
        pv[i] = -dx * sa + dy * ca;
        pz[i] = zs[i];
    }
    // an end the line is to join: its point is the line's last
    double endU = 0, endV = 0;
    int endDir = -1;
    if (endAt !is null)
    {
        double dx = endAt.x - jx, dy = endAt.y - jy;
        endU = dx * ca + dy * sa;
        endV = -dx * sa + dy * ca;
        // the way into it, as one of the four directions (or none: it can't be joined)
        double into = endAt.heading + 180 - a0;
        into = into - 360 * Math::floor(into / 360);
        double q = into / 90;
        int d = int(Math::floor(q + 0.5)) % 4;
        if (Math::abs(q - Math::floor(q + 0.5)) < 0.03)
            endDir = d;
    }

    // simplified, then each piece of it a leg along the nearest of the four directions
    array<int> keep = {0};
    Simplify(0, n - 1, rs * 0.5, keep);
    keep.insertLast(n - 1);
    array<Leg@> legs;
    for (uint s = 0; s + 1 < keep.length(); s++)
    {
        int a = keep[s], b = keep[s + 1];
        double du = pu[b] - pu[a], dv = pv[b] - pv[a];
        if (du * du + dv * dv < 1)
            continue;
        double ang = Deg(Math::atan2(dv, du));
        if (ang < 0)
            ang += 360;
        int dir = int(Math::floor(ang / 90 + 0.5)) % 4;
        if (legs.length() > 0 && legs[legs.length() - 1].dir == dir)
        {
            legs[legs.length() - 1].last = b;
            continue;
        }
        Leg leg;
        leg.dir = dir;
        leg.first = a;
        leg.last = b;
        legs.insertLast(leg);
    }
    if (legs.length() == 0)
    {
        Leg leg;
        leg.dir = 0;
        leg.first = 0;
        leg.last = n - 1;
        legs.insertLast(leg);
    }
    // wiggles out: an inner leg shorter than two of the smallest turn isn't a leg (points near the horizon jump a
    // long way for a pixel, and a road tool ignores a wobble too); its neighbours meet, or merge when they agree
    for (bool merged = true; merged;)
    {
        merged = false;
        for (uint k = 1; k + 1 < legs.length() && !merged; k++)
        {
            Leg@ leg = legs[k];
            double span = Math::abs(Along(leg.dir, pu[leg.last], pv[leg.last]) - Along(leg.dir, pu[leg.first], pv[leg.first]));
            if (span >= 2 * rs)
                continue;
            legs.removeAt(k);
            if (legs[k - 1].dir == legs[k].dir)
            {
                legs[k - 1].last = legs[k].last;
                legs.removeAt(k);
            }
            merged = true;
        }
    }

    // the track leaves the start straight ahead
    if (legs[0].dir != 0)
    {
        Leg lead;
        lead.dir = 0;
        lead.first = 0;
        lead.last = 0;
        legs.insertAt(0, lead);
    }
    // a U-turn needs a leg across between the two
    for (uint k = 0; k + 1 < legs.length(); k++)
        if ((legs[k].dir + 2) % 4 == legs[k + 1].dir)
        {
            Leg across;
            int p = legs[k].last;
            double side = Across(legs[k].dir, pu[legs[k + 1].first + (legs[k + 1].last - legs[k + 1].first) / 2], pv[legs[k + 1].first + (legs[k + 1].last - legs[k + 1].first) / 2])
                          - Across(legs[k].dir, pu[p], pv[p]);
            across.dir = (legs[k].dir + (side >= 0 ? 1 : 3)) % 4;
            across.first = p;
            across.last = p;
            legs.insertAt(k + 1, across);
        }
    // joining an open end: the last leg runs into it
    if (endDir >= 0 && legs[legs.length() - 1].dir != endDir)
    {
        if ((legs[legs.length() - 1].dir + 2) % 4 == endDir)
            endDir = -1;                // it faces the wrong way to be reached
        else
        {
            Leg into;
            into.dir = endDir;
            into.first = n - 1;
            into.last = n - 1;
            legs.insertLast(into);
        }
    }
    if (endAt !is null && endDir < 0)
        fitNote = "the end there can't be joined from this side";

    // each leg's line: where its points are across it (the first leg's goes through the start)
    for (uint k = 0; k < legs.length(); k++)
    {
        Leg@ leg = legs[k];
        if (k == 0)
        {
            leg.line = 0;
            continue;
        }
        double sum = 0;
        int count = 0;
        for (int i = leg.first; i <= leg.last; i++)
        {
            sum += LineOf(leg.dir, pu[i], pv[i]);
            count++;
        }
        leg.line = count > 0 ? sum / count : LineOf(leg.dir, pu[leg.first], pv[leg.first]);
    }
    if (endDir >= 0)
        legs[legs.length() - 1].line = LineOf(endDir, endU, endV);

    // where the last leg ends: the last point's place along it, or the open end
    Leg@ lastLeg = legs[legs.length() - 1];
    double endAlong = endDir >= 0 ? Along(lastLeg.dir, endU, endV) : Along(lastLeg.dir, pu[n - 1], pv[n - 1]);

    // the turns: each corner gets the turn whose size is nearest to how wide it was drawn, among those that fit;
    // a leg too short for its turns is made longer (the next leg's line moves out)
    double startAlong = 0;              // where the current leg begins, along it
    double prevRadius = 0;
    double su = 0, sv = 0;              // the current leg's start in (u, v)
    for (uint k = 0; k < legs.length(); k++)
    {
        Leg@ leg = legs[k];
        leg.turnRadius = 0;
        leg.turnPiece = -1;
        if (k + 1 == legs.length())
            break;
        Leg@ next = legs[k + 1];
        double cu, cv;
        Corner(leg, next, cu, cv);
        double len = Along(leg.dir, cu, cv) - Along(leg.dir, su, sv);
        // how wide the turn was drawn: the corner's distance to the nearest point near it
        double nearest = 1e18;
        int from = leg.first, to = next.last;
        for (int i = from; i <= to; i++)
        {
            double d = (pu[i] - cu) * (pu[i] - cu) + (pv[i] - cv) * (pv[i] - cv);
            if (d < nearest)
                nearest = d;
        }
        double drawnRadius = Math::sqrt(nearest) / 0.4142;
        // the room the next leg has for this turn (its own next turn needs at least the smallest)
        double nextRoom;
        if (k + 2 < legs.length())
        {
            double nu, nv;
            Corner(next, legs[k + 2], nu, nv);
            nextRoom = Along(next.dir, nu, nv) - Along(next.dir, cu, cv) - rs;
        }
        else
            nextRoom = (k + 2 == legs.length() ? endAlong : 0) - Along(next.dir, cu, cv);
        int pick = -1;
        double pickR = 0;
        for (uint t = 0; t < turns.length(); t++)
        {
            double r = TurnRadius(turns[t]) * f;
            if (r > len - prevRadius + 0.5 || r > nextRoom + 0.5)
                continue;
            if (pick < 0 || Math::abs(r - drawnRadius) < Math::abs(pickR - drawnRadius))
            {
                pick = turns[t];
                pickR = r;
            }
        }
        if (pick < 0)
        {
            // no turn fits: the smallest, with this leg made long enough for it (the next leg's line moves out)
            pick = turns[0];
            pickR = rs;
            double need = prevRadius + pickR - len;
            if (need > 0 && endDir >= 0 && k + 2 == legs.length())
                endDir = -1;            // the leg into the end it is to join can't move: no join
            else if (need > 0)
            {
                double sign = (leg.dir == 0 || leg.dir == 1) ? 1 : -1;
                next.line += sign * need;
                Corner(leg, next, cu, cv);
            }
        }
        leg.turnRadius = pickR;
        leg.turnPiece = pick;
        prevRadius = pickR;
        su = cu;
        sv = cv;
    }
    // the last leg must be long enough for the turn before it
    double lastLen = endAlong - Along(lastLeg.dir, su, sv);
    if (lastLen < prevRadius)
    {
        endAlong += prevRadius - lastLen;
        if (endDir >= 0)
            fitNote = "the end there is too close to join";
        endDir = -1;
    }

    // the plan: a straight (its length in plan) and the turn at its end, leg by leg
    su = 0;
    sv = 0;
    prevRadius = 0;
    for (uint k = 0; k < legs.length(); k++)
    {
        Leg@ leg = legs[k];
        double cu, cv, lenAlong;
        bool hasTurn = k + 1 < legs.length();
        if (hasTurn)
        {
            Corner(leg, legs[k + 1], cu, cv);
            lenAlong = Along(leg.dir, cu, cv) - Along(leg.dir, su, sv);
        }
        else
            lenAlong = endAlong - Along(leg.dir, su, sv);
        Seg straight;
        straight.turn = false;
        straight.length = lenAlong - prevRadius - leg.turnRadius;
        straight.first = leg.first;
        straight.last = hasTurn ? legs[k + 1].first : n - 1;
        if (straight.length > 1 || straight.length < -1)
            segs.insertLast(straight);
        if (hasTurn)
        {
            Seg t;
            t.turn = true;
            t.piece = leg.turnPiece;
            t.side = ((legs[k + 1].dir - leg.dir + 4) % 4) == 1 ? 1 : -1;
            t.viaB = TurnSide(leg.turnPiece) != t.side;
            t.first = leg.last;
            t.last = legs[k + 1].first;
            segs.insertLast(t);
            su = cu;
            sv = cv;
            prevRadius = leg.turnRadius;
        }
    }
    joinsEnd = endAt !is null && endDir >= 0;
    return segs;
}

int NearestPoint(double u, double v, int from, int to)
{
    int best = from;
    double bestD = 1e18;
    for (int i = from; i <= to && i < int(pu.length()); i++)
    {
        double d = (pu[i] - u) * (pu[i] - u) + (pv[i] - v) * (pv[i] - v);
        if (d < bestD)
        {
            bestD = d;
            best = i;
        }
    }
    return best;
}

// ---------------------------------------------------------------- what is in the way

// A piece in the map as a shape a track mustn't pass through: a turned box (its own box, scaled), or for a turn (two
// level ends a quarter turn apart) the ring sector it really covers, which its box is far bigger than.
class Obstacle
{
    int piece = -1;             // the map piece, or -1 (a piece of the line itself)
    int order = 0;              // for the line's own pieces: which one
    double pathEnd = 0;         // and how far along the track it ends
    double x, y, z;
    array<double> m(9);
    double sx = 1, sy = 1, sz = 1;
    double bcx, bcy, bcz, bhx, bhy, bhz;    // its box, in its own frame (scale 1)
    bool arc = false;
    double cx, cy, r, hw, a0, span;         // the arc: centre, radius, half width, from angle a0 over span (radians)
    double zlo, zhi;
    double top;                 // the highest point of it in the world
    double minX, minY, minZ, maxX, maxY, maxZ;  // around it in the world, for skipping it quickly
}

// The obstacle's world bounds (a ring sector's around its whole circle).
void Bound(Obstacle@ o)
{
    if (o.arc)
    {
        o.minX = o.cx - o.r - o.hw;
        o.maxX = o.cx + o.r + o.hw;
        o.minY = o.cy - o.r - o.hw;
        o.maxY = o.cy + o.r + o.hw;
        o.minZ = o.zlo;
        o.maxZ = o.zhi;
        return;
    }
    o.minX = o.minY = o.minZ = 1e18;
    o.maxX = o.maxY = o.maxZ = -1e18;
    for (int c = 0; c < 8; c++)
    {
        double wx, wy, wz;
        Apply(o.m, (o.bcx + ((c & 1) != 0 ? o.bhx : -o.bhx)) * o.sx, (o.bcy + ((c & 2) != 0 ? o.bhy : -o.bhy)) * o.sy,
              (o.bcz + ((c & 4) != 0 ? o.bhz : -o.bhz)) * o.sz, wx, wy, wz);
        wx += o.x;
        wy += o.y;
        wz += o.z;
        if (wx < o.minX) o.minX = wx;
        if (wy < o.minY) o.minY = wy;
        if (wz < o.minZ) o.minZ = wz;
        if (wx > o.maxX) o.maxX = wx;
        if (wy > o.maxY) o.maxY = wy;
        if (wz > o.maxZ) o.maxZ = wz;
    }
}

array<Obstacle@> obstacles;

// A box from bounds.txt, or false.
bool BoxFor(const string &in cls, Obstacle@ o)
{
    int at = boxNames.find(cls);
    if (at < 0)
        return false;
    Box@ b = boxList[at];
    o.bcx = b.cx;
    o.bcy = b.cy;
    o.bcz = b.cz;
    o.bhx = b.hx;
    o.bhy = b.hy;
    o.bhz = b.hz;
    return true;
}

// The world top of a turned box.
double BoxTop(Obstacle@ o)
{
    double top = -1e18;
    for (int c = 0; c < 8; c++)
    {
        double wx, wy, wz;
        Apply(o.m, (o.bcx + ((c & 1) != 0 ? o.bhx : -o.bhx)) * o.sx, (o.bcy + ((c & 2) != 0 ? o.bhy : -o.bhy)) * o.sy,
              (o.bcz + ((c & 4) != 0 ? o.bhz : -o.bhz)) * o.sz, wx, wy, wz);
        if (o.z + wz > top)
            top = o.z + wz;
    }
    return top;
}

// Makes the obstacle a ring sector if its two ends (world) are level and a quarter turn apart.
void ArcFrom(Obstacle@ o, double ax, double ay, double az, double adx, double ady, double bx, double by, double bdx, double bdy, double width,
             double depth)
{
    double dot = adx * bdx + ady * bdy;
    if (Math::abs(dot) > 0.1)
        return;
    double chord = Math::sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (chord < 10)
        return;
    double r = chord / 1.41421356;
    // the centre: from end A, across its direction, on end B's side
    double nx = -ady, ny = adx;
    if (nx * (bx - ax) + ny * (by - ay) < 0)
    {
        nx = -nx;
        ny = -ny;
    }
    o.cx = ax + nx * r;
    o.cy = ay + ny * r;
    o.r = r;
    o.hw = width / 2;
    double angA = Math::atan2(ay - o.cy, ax - o.cx), angB = Math::atan2(by - o.cy, bx - o.cx);
    double span = angB - angA;
    while (span > 3.14159265) span -= 6.2831853;
    while (span < -3.14159265) span += 6.2831853;
    o.a0 = angA;
    o.span = span;
    o.zhi = az;
    o.zlo = az - depth;
    o.top = o.zhi;
    o.arc = true;
}

bool Inside(Obstacle@ o, double px, double py, double pz, double margin, double band = -1)
{
    if (band < 0)
        band = margin;
    if (o.arc)
    {
        if (pz < o.zlo - band || pz > o.zhi + band)
            return false;
        double dx = px - o.cx, dy = py - o.cy;
        double d = Math::sqrt(dx * dx + dy * dy);
        if (d < o.r - o.hw - margin || d > o.r + o.hw + margin)
            return false;
        double a = Math::atan2(dy, dx) - o.a0;
        while (a > 3.14159265) a -= 6.2831853;
        while (a < -3.14159265) a += 6.2831853;
        return o.span > 0 ? (a >= -0.02 && a <= o.span + 0.02) : (a <= 0.02 && a >= o.span - 0.02);
    }
    // into the box's frame: transpose of the rotation, then the scale
    double dx = px - o.x, dy = py - o.y, dz = pz - o.z;
    double lx = (dx * o.m[0] + dy * o.m[1] + dz * o.m[2]) / o.sx;
    double ly = (dx * o.m[3] + dy * o.m[4] + dz * o.m[5]) / o.sy;
    double lz = (dx * o.m[6] + dy * o.m[7] + dz * o.m[8]) / o.sz;
    return Math::abs(lx - o.bcx) <= o.bhx + margin / o.sx && Math::abs(ly - o.bcy) <= o.bhy + margin / o.sy &&
           Math::abs(lz - o.bcz) <= o.bhz + band / o.sz;
}

// An obstacle for one of the line's own pieces.
Obstacle@ OwnObstacle(Placed@ p, int order)
{
    Obstacle o;
    o.order = order;
    KitPiece@ k = kit[p.piece];
    o.x = p.x;
    o.y = p.y;
    o.z = p.z;
    AxesRoll(p.pitch, p.yaw, p.roll, o.m);
    o.sx = p.sx;
    o.sy = p.sy;
    o.sz = p.sz;
    if (!BoxFor(ClassName(k.classPath), o))
        return null;
    o.top = BoxTop(o);
    if (k.turn)
    {
        array<double> m(9);
        AxesRoll(p.pitch, p.yaw, p.roll, m);
        double adx, ady, adz, bdx, bdy, bdz;
        Apply(m, k.a[3], k.a[4], k.a[5], adx, ady, adz);
        Apply(m, k.b[3], k.b[4], k.b[5], bdx, bdy, bdz);
        ArcFrom(o, p.viaB ? p.ex : p.jx, p.viaB ? p.ey : p.jy, p.jz, adx, ady, p.viaB ? p.jx : p.ex, p.viaB ? p.jy : p.ey, bdx, bdy,
                k.width * p.sy, (k.a[2] - (o.bcz - o.bhz)) * p.sz);
    }
    Bound(o);
    return o;
}

// ---------------------------------------------------------------- the line as pieces: plan, heights, pieces

// The joints between the short runs a line is cut into for its heights (runs of at most kRun in plan; a turn's two
// ends are one joint, as turns stay level).
class Joint
{
    double s;                   // plan distance along the straights to here
    double path;                // distance along the track to here, turns included
    double x, y;                // where it is in plan (a turn's: its entry)
    double ex, ey;              // a turn's exit (else the same)
    double heading;             // the heading leaving it
    double hin;                 // the heading arriving (a turn's entry)
    int seg;                    // the segment that leaves it, -1 at the end
    bool turn = false;          // a turn leaves it
    double target;              // the height drawn here
    double need = -1e18;        // the lowest it can be to clear what is in the way
    bool blocked = false;       // what is in the way here is too tall to bridge
    double z;
}

const double kRun = 250;                // cm: the longest run between height joints
const double kSlope = 45;               // degrees: the steepest a run climbs or falls (a sag's bend from level)
const double kBridgeSlope = 10;         // degrees: the ramps up to what has to be cleared (when nothing steeper is drawn)
const double kEdgeSlope = 3;            // degrees: the runs next to a turn or the line's ends (the bend there has room)
const double kGradeTolerance = 150;     // cm: the heights are simplified to grades this close to them (the 5 m joints
                                        // leave a short in-between slope at each end of a steep ramp: merged away)
const double kKink = 5;                 // degrees: the most one joint between two short pieces bends
const double kMinBend = 1.5;            // degrees: a bend smaller than this is just a joint
const double kKinkRadius = 2000;        // cm: the largest circle a bend made of short pieces follows
const double kMinStraight = 60;         // cm: a straight shorter than this between bends is taken up by one
const double kMaxStretch = 10;          // a straight piece is stretched up to this many times its length (Track M: 100 m)
const double kShortGrade = 600;         // cm in plan: a grade this short between two bends the same way is merged away
const double kTooTall = 1500;           // cm: higher than this above the line, an obstacle isn't bridged

array<Joint@> joints;

void MakeJoints(array<Seg@>@ segs, double jx, double jy, double a0)
{
    joints.resize(0);
    double x = jx, y = jy, heading = a0, s = 0, path = 0;
    double f = WidthScale();
    int mark = 0;
    for (uint k = 0; k < segs.length(); k++)
    {
        Seg@ g = segs[k];
        if (g.turn)
        {
            Placed@ t = Put(g.piece, g.viaB, x, y, 0, heading, 0, f, f);
            Joint j;
            j.s = s;
            j.path = path;
            j.x = x;
            j.y = y;
            j.ex = t.ex;
            j.ey = t.ey;
            j.heading = heading + g.side * 90;
            j.hin = heading;
            j.seg = int(k);
            j.turn = true;
            joints.insertLast(j);
            path += 1.5707963 * Math::sqrt((t.ex - x) * (t.ex - x) + (t.ey - y) * (t.ey - y)) / 1.41421356;
            x = t.ex;
            y = t.ey;
            heading = j.heading;
            continue;
        }
        int n = int(Math::ceil(g.length / kRun));
        if (n < 1)
            n = 1;
        for (int i = 0; i < n; i++)
        {
            Joint j;
            j.s = s;
            j.path = path;
            j.x = x;
            j.y = y;
            j.ex = x;
            j.ey = y;
            j.heading = heading;
            j.hin = heading;
            j.seg = int(k);
            joints.insertLast(j);
            double step = g.length / n;
            x += Math::cos(Rad(heading)) * step;
            y += Math::sin(Rad(heading)) * step;
            s += step;
            path += step;
        }
    }
    Joint last;
    last.s = s;
    last.path = path;
    last.x = x;
    last.y = y;
    last.ex = x;
    last.ey = y;
    last.heading = heading;
    last.hin = heading;
    last.seg = -1;
    joints.insertLast(last);
    // consecutive turns (no straight between) share a joint already; a turn right after the start keeps both
}

// The height drawn at each joint: the line's nearest point, searched forward from the last one found.
void Targets(array<double>@ xs, array<double>@ ys, array<double>@ zs)
{
    int from = 0;
    int n = int(xs.length());
    for (uint k = 0; k < joints.length(); k++)
    {
        int best = from;
        double bestD = 1e30;
        int upTo = from + 400 < n ? from + 400 : n;
        for (int i = from; i < upTo; i++)
        {
            double d = (xs[i] - joints[k].x) * (xs[i] - joints[k].x) + (ys[i] - joints[k].y) * (ys[i] - joints[k].y);
            if (d < bestD)
            {
                bestD = d;
                best = i;
            }
        }
        from = best;
        joints[k].target = zs[best];
    }
}

// Raises joint needs for what the run from joint k to k+1 (or the turn at k) passes through, sampled every metre
// across its width at the heights the track and the ball above it take up. `own` also counts the line's own pieces
// that end more than 4 m back along it (a loop crossing itself).
void Clearance(bool own, double jx, double jy, double ex, double ey)
{
    double w = TrackWidth() / 2 - 30;
    for (uint k = 0; k + 1 < joints.length(); k++)
    {
        Joint@ a = joints[k];
        Joint@ b = joints[k + 1];
        // a branch off a join runs along the track it leaves until it has turned away (and one merging in, along the
        // track it joins): the pieces there are its own road, not in its way
        if ((branchStart && a.path < branchClear) || (branchEnd && b.path > joints[joints.length() - 1].path - branchClear))
            continue;
        array<double> px, py;
        // the run's centre line in plan
        if (a.ex != a.x || a.ey != a.y)
        {
            // a turn at a: its arc, sampled along the chord's bulge (entry to exit, by the turn's centre)
            double hin = Rad(a.hin);
            double side = Math::sin(Rad(a.heading) - hin) > 0 ? 1 : -1;
            double r = Math::sqrt((a.ex - a.x) * (a.ex - a.x) + (a.ey - a.y) * (a.ey - a.y)) / 1.41421356;
            double cx = a.x - Math::sin(hin) * r * side, cy = a.y + Math::cos(hin) * r * side;
            for (int s = 0; s <= 6; s++)
            {
                double ang = hin - side * 1.5707963 + side * 1.5707963 * s / 6;
                px.insertLast(cx + Math::cos(ang) * r);
                py.insertLast(cy + Math::sin(ang) * r);
            }
        }
        double len = Math::sqrt((b.x - a.ex) * (b.x - a.ex) + (b.y - a.ey) * (b.y - a.ey));
        int steps = int(Math::ceil(len / 100));
        for (int s = 0; s <= steps; s++)
        {
            double t = steps > 0 ? double(s) / steps : 0;
            px.insertLast(a.ex + (b.x - a.ex) * t);
            py.insertLast(a.ey + (b.y - a.ey) * t);
        }
        double h = Rad(a.heading);
        double nx = -Math::sin(h), ny = Math::cos(h);
        // the obstacles near this run (plan bounds and heights), and only those tested point by point
        double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
        for (uint p = 0; p < px.length(); p++)
        {
            if (px[p] < x0) x0 = px[p];
            if (py[p] < y0) y0 = py[p];
            if (px[p] > x1) x1 = px[p];
            if (py[p] > y1) y1 = py[p];
        }
        x0 -= w + 60;
        y0 -= w + 60;
        x1 += w + 60;
        y1 += w + 60;
        double zl = (a.target < b.target ? a.target : b.target) - 120, zh = (a.target > b.target ? a.target : b.target) + 180;
        array<Obstacle@> near;
        for (uint o = 0; o < obstacles.length(); o++)
            if (obstacles[o].piece != skipFrom && obstacles[o].piece != skipTo && obstacles[o].piece != skipFrom2 &&
                obstacles[o].piece != skipTo2 && Near(obstacles[o], x0, y0, x1, y1, zl, zh))
                near.insertLast(obstacles[o]);
        if (own)
            for (uint o = 0; o < ownObstacles.length(); o++)
                if (ownObstacles[o].pathEnd < a.path - 400 && Near(ownObstacles[o], x0, y0, x1, y1, zl, zh) &&
                    !(loopClosed && ownObstacles[o].pathEnd < kLoopClear && a.path > joints[joints.length() - 1].path - kLoopClear))
                    near.insertLast(ownObstacles[o]);
        if (near.length() == 0)
            continue;
        for (uint p = 0; p < px.length(); p++)
        {
            // not next to where the line starts or joins: it touches those pieces there
            if ((px[p] - jx) * (px[p] - jx) + (py[p] - jy) * (py[p] - jy) < 150 * 150)
                continue;
            if (joinsEnd && (px[p] - ex) * (px[p] - ex) + (py[p] - ey) * (py[p] - ey) < 150 * 150)
                continue;
            double t = p < px.length() / 2 ? a.target : b.target;
            for (int across = -1; across <= 1; across++)
            {
                double qx = px[p] + nx * w * across, qy = py[p] + ny * w * across;
                for (uint o = 0; o < near.length(); o++)
                    Hit(near[o], qx, qy, t, k);
            }
        }
    }
}

// Whether the obstacle is where the track (100 thick) and the ball over it (to 160 above) would be at height t; if
// so, the joints either side of run k need to be above it.
bool Near(Obstacle@ o, double x0, double y0, double x1, double y1, double z0, double z1)
{
    return o.maxX >= x0 && o.minX <= x1 && o.maxY >= y0 && o.minY <= y1 && o.maxZ >= z0 && o.minZ <= z1;
}

void Hit(Obstacle@ o, double qx, double qy, double t, uint k)
{
    // the track (its kit's depth below the rolling surface, 1 m for Track) and the ball over it: two heights, each with
    // a band (Track's: 65 cm, the track's from 110 cm below to 20 above)
    if (!(Inside(o, qx, qy, t - (kitDepth - 10) / 2, 15, (kitDepth + 30) / 2) || Inside(o, qx, qy, t + 100, 15, 65)))
        return;
    double need = o.top + kitDepth + 160;   // its top, the track's depth and the ball's room
    for (uint e = k; e <= k + 1 && e < joints.length(); e++)
    {
        if (o.top - t > kTooTall)
            joints[e].blocked = true;
        if (need > joints[e].need)
            joints[e].need = need;
    }
}

int skipFrom = -1, skipTo = -1;         // the pieces the line starts from and joins: never in its way
int skipFrom2 = -1, skipTo2 = -1;       // at a join: the other piece there
bool branchStart = false, branchEnd = false;    // the line starts from (ends on) a join between two pieces
double branchClear = 0;                 // cm along the line from such a join where nothing counts as in its way
array<Obstacle@> ownObstacles;

// The heights: the drawn ones (as steep as drawn, up to kSlope), raised where something is in the way with ramps of
// kBridgeSlope towards those, level turns; the runs next to a turn or a node the line starts from or joins nearly
// level (kEdgeSlope), so the bend onto a slope has room there. The start fixed (and the end, when joining one). Joints that can't be raised
// enough in time are blocked. The start is fixed only when the line carries on a node; a line started in open space
// rises from its first piece when it has to. The bends between slopes are made by the pieces (Pieces).
void Profile(double startZ, bool fixedStart, double endZ, bool fixedEnd)
{
    uint n = joints.length();
    double g = Math::tan(Rad(kSlope)), gb = Math::tan(Rad(kBridgeSlope)), ge = Math::tan(Rad(kEdgeSlope));
    for (uint k = 0; k < n; k++)
        joints[k].z = joints[k].target > joints[k].need ? joints[k].target : joints[k].need;
    // ramps towards the heights needed (a requirement pulls its neighbours up)
    for (uint k = 0; k < n; k++)
        for (uint j = 0; j < n; j++)
        {
            if (joints[j].need < -1e17)
                continue;
            double reach = joints[j].need - gb * Math::abs(joints[k].s - joints[j].s);
            if (reach > joints[k].z)
                joints[k].z = reach;
        }
    // a line's open end is at the level it was drawn to (scrolled to at the cursor, say): the line leads up (or down)
    // to it as steep as kSlope allows, never below what it has to clear
    if (!fixedEnd)
        for (int k = int(n) - 2; k >= 0; k--)
        {
            double reach = g * (joints[n - 1].s - joints[k].s);
            double z = joints[k].z;
            if (z < joints[n - 1].z - reach)
                z = joints[n - 1].z - reach;
            if (z > joints[n - 1].z + reach)
                z = joints[n - 1].z + reach;
            joints[k].z = z > joints[k].need ? z : joints[k].need;
        }
    if (fixedStart || joints[0].z < startZ)
        joints[0].z = startZ;
    if (fixedEnd)
        joints[n - 1].z = endZ;
    // no steeper than the slope, from the start (and back from a fixed end)
    for (uint k = 1; k < n; k++)
        Clamp(joints[k], joints[k - 1], EdgeRun(k - 1, fixedStart, fixedEnd) ? ge : g);
    if (fixedEnd)
    {
        joints[n - 1].z = endZ;
        for (int k = int(n) - 2; k > 0; k--)
            Clamp(joints[k], joints[k + 1], EdgeRun(uint(k), fixedStart, fixedEnd) ? ge : g);
    }
    for (uint k = 0; k < n; k++)
        if (joints[k].z < joints[k].need - 5)
            joints[k].blocked = true;
}

// Whether the run from joint k to k + 1 is next to a turn, or next to a node the line starts from or joins (a line's
// open end is free: the level changed while drawing shows there at once, as far as kSlope reaches).
bool EdgeRun(uint k, bool fromNode, bool toNode)
{
    return (k == 0 && fromNode) || (k + 2 >= joints.length() && toNode) || (k > 0 && joints[k - 1].turn) ||
           joints[k + 1].turn;
}

void Clamp(Joint@ j, Joint@ prev, double g)
{
    double room = g * Math::abs(j.s - prev.s);
    if (j.z > prev.z + room)
        j.z = prev.z + room;
    if (j.z < prev.z - room)
        j.z = prev.z - room;
}

// The pieces, joint to joint: turns level, and each straight stretch between them (a leg) as grades with bends
// between them (BuildLeg). Stops before the first blocked joint. Sets `raised` when a bend over the top would pass below
// what a joint has to clear: that joint's need is raised by the shortfall, for fitting the heights again.
bool raised = false;

array<Placed@>@ Pieces(array<Seg@>@ segs, double jx, double jy, double a0, int &out stoppedAt)
{
    array<Placed@> chain;
    stoppedAt = -1;
    raised = false;
    double f = WidthScale();
    double x = jx, y = jy, z = joints[0].z, heading = a0;
    uint limit = joints.length() - 1;
    for (uint k = 0; k < joints.length(); k++)
        if (joints[k].blocked)
        {
            stoppedAt = k > 0 ? int(k) - 1 : 0;
            limit = uint(stoppedAt);
            break;
        }
    uint k = 0;
    while (k < limit)
    {
        Seg@ g = segs[joints[k].seg];
        if (g.turn)
        {
            Placed@ t = Put(g.piece, g.viaB, x, y, joints[k].z, heading, 0, f, f);
            t.pathEnd = joints[k + 1].path;
            chain.insertLast(t);
            x = t.ex;
            y = t.ey;
            z = t.ez;
            heading += g.side * 90;
            k++;
            continue;
        }
        uint end = k + 1;
        while (end < limit && !joints[end].turn)
            end++;
        BuildLeg(k, end, x, y, z, heading, f, chain);
        if (chain.length() > 0)
        {
            x = chain[chain.length() - 1].ex;
            y = chain[chain.length() - 1].ey;
            z = chain[chain.length() - 1].ez;
        }
        k = end;
    }
    return chain;
}

// Keeps the joints a simplified grade line must keep: the one furthest from the line between a and b (more than
// kGradeTolerance), or one the line would pass below what it has to clear.
void KeepGrades(array<double>@ s, array<double>@ z, array<double>@ need, array<bool>@ keep, int a, int b)
{
    if (b - a < 2)
        return;
    int worst = -1;
    double worstD = kGradeTolerance;
    for (int i = a + 1; i < b; i++)
    {
        double line = z[a] + (z[b] - z[a]) * (s[i] - s[a]) / (s[b] - s[a]);
        double d = Math::abs(z[i] - line);
        if (line < need[i] - 1)
            d = 1e9;
        if (d > worstD)
        {
            worstD = d;
            worst = i;
        }
    }
    if (worst < 0)
        return;
    keep[worst] = true;
    KeepGrades(s, z, need, keep, a, worst);
    KeepGrades(s, z, need, keep, worst, b);
}

// One leg (joints k0 to k1, no turn between): the heights simplified to grades, and each bend between two grades made
// from the kit's sag (a bend upward, stretched along to the bend: the largest that fits) or from short straights a
// few degrees apart around a circle (a bend over the top, or upward where no sag fits), then straights along the
// grades between the bends. Starts at (x, y, z), which is joint k0.
void BuildLeg(uint k0, uint k1, double x, double y, double z, double heading, double f, array<Placed@>@ chain)
{
    // the joints in the leg's own frame: plan distance from its start, height
    array<double> js, jz, jneed;
    for (uint k = k0; k <= k1; k++)
    {
        js.insertLast(joints[k].s - joints[k0].s);
        jz.insertLast(joints[k].z);
        jneed.insertLast(joints[k].need);
    }
    int n = int(js.length());
    array<bool> keep(n);
    keep[0] = true;
    keep[n - 1] = true;
    KeepGrades(js, jz, jneed, keep, 0, n - 1);
    array<double> vs, vz;
    for (int i = 0; i < n; i++)
        if (keep[i])
        {
            vs.insertLast(js[i]);
            vz.insertLast(jz[i]);
        }
    MergeShortGrades(vs, vz, js, jneed);
    int m = int(vs.length()) - 1;          // grades
    array<double> th(m), len(m);
    for (int i = 0; i < m; i++)
    {
        th[i] = Math::atan2(vz[i + 1] - vz[i], vs[i + 1] - vs[i]);
        len[i] = Math::sqrt((vs[i + 1] - vs[i]) * (vs[i + 1] - vs[i]) + (vz[i + 1] - vz[i]) * (vz[i + 1] - vz[i]));
    }
    // each bend: how far along the grades either side it reaches (t), and what makes it
    array<double> t(m + 1), stretch(m + 1), radius(m + 1);
    array<int> sagAt(m + 1), kinks(m + 1);
    for (int v = 0; v <= m; v++)
    {
        t[v] = 0;
        sagAt[v] = -1;
        kinks[v] = 0;
        if (v == 0 || v == m)
            continue;
        double bend = th[v] - th[v - 1];
        if (Math::abs(bend) < Rad(kMinBend))
            continue;
        double room = len[v - 1] * (v - 1 == 0 ? 1 : 0.5);
        double roomR = len[v] * (v == m - 1 ? 1 : 0.5);
        if (roomR < room)
            room = roomR;
        // upward: a sag; over the top: a crest (a ramp turned over), the largest that fits
        array<int>@ bends = bend > 0 ? sags : crests;
        for (uint q = 0; q < bends.length() && sagAt[v] < 0; q++)
        {
            double phi = Math::abs(SagHalfAngle(bends[q])), a = SagHalfSpan(bends[q]);
            double st = Math::tan(phi) / Math::tan(Math::abs(bend) / 2);
            double reach = Math::sqrt(st * st * a * a + a * a * Math::tan(phi) * Math::tan(phi));
            if (st >= 0.5 && st <= 6 && reach <= room)
            {
                sagAt[v] = bends[q];
                stretch[v] = st;
                t[v] = reach;
            }
        }
        if (sagAt[v] < 0)
        {
            double half = Math::tan(Math::abs(bend) / 2);
            double reach = kKinkRadius * half < room ? kKinkRadius * half : room;
            int pieces = int(Math::ceil(Math::abs(bend) / Rad(kKink)));
            double r = reach / half;
            if (pieces >= 2 && 2 * r * Math::sin(Math::abs(bend) / (2 * pieces)) >= 20)
            {
                kinks[v] = pieces;
                radius[v] = r;
                t[v] = reach;
            }
        }
    }
    // a straight left shorter than kMinStraight between bends (a sliver of a piece) is taken up by a bend of short
    // pieces beside it: its circle grows, when its other grade has the room
    for (int i = 0; i < m; i++)
    {
        double left = len[i] - t[i] - t[i + 1];
        if (left <= 0.5 || left >= kMinStraight)
            continue;
        for (int side = 0; side < 2; side++)
        {
            int v = side == 0 ? i + 1 : i;
            if (v < 1 || v > m - 1 || kinks[v] == 0)
                continue;
            int o = side == 0 ? i + 1 : i - 1;
            double after = len[o] - t[o] - t[o + 1] - left;
            if (after < -0.01 || (after > 0.5 && after < kMinStraight))
                continue;
            t[v] += left;
            radius[v] = t[v] / Math::tan(Math::abs(th[v] - th[v - 1]) / 2);
            break;
        }
    }
    // the pieces, in order; the rolling line they make in the leg's frame, to check the needs against
    double ux = Math::cos(Rad(heading)), uy = Math::sin(Rad(heading));
    double x0 = x, y0 = y, pathAt = joints[k0].path;
    array<double> rs, rz;
    rs.insertLast(0);
    rz.insertLast(z);
    for (int i = 0; i < m; i++)
    {
        double straight = len[i] - t[i] - t[i + 1];
        if (straight > 0.5)
        {
            // as few pieces as the straight can be: one, stretched, up to kMaxStretch times the kit's longest
            int pieces = int(Math::ceil(straight / (StraightLength(straights[straights.length() - 1]) * kMaxStretch)));
            double piece = straight / pieces;
            for (int q = 0; q < pieces; q++)
            {
                int kind = StraightFor(piece);
                Placed@ p = Put(kind, false, x, y, z, heading, Deg(th[i]), piece / StraightLength(kind), f);
                LegPiece(p, chain, x0, y0, ux, uy, pathAt, rs, rz);
                x = p.ex;
                y = p.ey;
                z = p.ez;
            }
        }
        int v = i + 1;
        if (v >= m)
            continue;
        if (sagAt[v] >= 0)
        {
            Placed@ p = Put(sagAt[v], false, x, y, z, heading, Deg((th[i] + th[v]) / 2), stretch[v], f);
            p.curved = true;
            p.cx = x + ux * Math::cos(th[i]) * t[v];
            p.cy = y + uy * Math::cos(th[i]) * t[v];
            p.cz = z + Math::sin(th[i]) * t[v];
            LegPiece(p, chain, x0, y0, ux, uy, pathAt, rs, rz);
            x = p.ex;
            y = p.ey;
            z = p.ez;
            if (th[v] > th[i])
                rz[rz.length() - 1] = 1e18; // a sag lies above the grades either side: never short of a need
            // (a crest lies between its corner and the straight line from its entry to its exit: checked on that line)
        }
        else if (kinks[v] > 0)
        {
            double bend = th[v] - th[i];
            double chord = 2 * radius[v] * Math::sin(Math::abs(bend) / (2 * kinks[v]));
            for (int q = 0; q < kinks[v]; q++)
            {
                int kind = StraightFor(chord);
                double pitch = th[i] + bend * (q + 0.5) / kinks[v];
                Placed@ p = Put(kind, false, x, y, z, heading, Deg(pitch), chord / StraightLength(kind), f);
                LegPiece(p, chain, x0, y0, ux, uy, pathAt, rs, rz);
                x = p.ex;
                y = p.ey;
                z = p.ez;
            }
        }
    }
    // a bend over the top passes below the corner of its grades: a need it now misses is raised by the shortfall
    for (int i = 1; i + 1 < n; i++)
    {
        if (jneed[i] < -1e17)
            continue;
        for (uint q = 0; q + 1 < rs.length(); q++)
            if (rs[q] <= js[i] && js[i] <= rs[q + 1] && rs[q + 1] > rs[q])
            {
                if (rz[q] > 1e17 || rz[q + 1] > 1e17)
                    break;
                double h = rz[q] + (rz[q + 1] - rz[q]) * (js[i] - rs[q]) / (rs[q + 1] - rs[q]);
                if (h < jneed[i] - 2)
                {
                    joints[k0 + uint(i)].need += jneed[i] - h + 5;
                    raised = true;
                }
                break;
            }
    }
}

// Two bends the same way with only a short grade between them (drawn heights in steps: the wheel turned while drawing)
// become one bend where the grades either side meet, so it is big enough for a sag or one smooth bend of short
// pieces, not two cramped ones. Only where the merged line still clears every joint's need.
void MergeShortGrades(array<double>@ vs, array<double>@ vz, array<double>@ js, array<double>@ jneed)
{
    bool changed = true;
    while (changed)
    {
        changed = false;
        for (int i = 1; i + 2 < int(vs.length()) && !changed; i++)
        {
            if (vs[i + 1] - vs[i] >= kShortGrade)
                continue;
            double g0 = (vz[i] - vz[i - 1]) / (vs[i] - vs[i - 1]);
            double g1 = (vz[i + 1] - vz[i]) / (vs[i + 1] - vs[i]);
            double g2 = (vz[i + 2] - vz[i + 1]) / (vs[i + 2] - vs[i + 1]);
            if ((g1 - g0) * (g2 - g1) <= 0 || Math::abs(g2 - g0) < 1e-6)
                continue;
            // where the grade before and the grade after meet
            double s = (vz[i + 1] - g2 * vs[i + 1] - vz[i] + g0 * vs[i]) / (g0 - g2);
            if (s <= vs[i - 1] + 1 || s >= vs[i + 2] - 1)
                continue;
            double z = vz[i] + g0 * (s - vs[i]);
            bool clear = true;
            for (uint k = 0; k < js.length() && clear; k++)
                if (js[k] > vs[i - 1] && js[k] < vs[i + 2] && jneed[k] > -1e17)
                {
                    double h = js[k] < s ? vz[i - 1] + g0 * (js[k] - vs[i - 1]) : z + g2 * (js[k] - s);
                    clear = h >= jneed[k] - 1;
                }
            if (!clear)
                continue;
            vs.removeAt(uint(i + 1));
            vz.removeAt(uint(i + 1));
            vs[i] = s;
            vz[i] = z;
            changed = true;
        }
    }
}

// A leg's piece placed: added to the chain, and its exit to the rolling line.
void LegPiece(Placed@ p, array<Placed@>@ chain, double x0, double y0, double ux, double uy, double pathAt,
              array<double>@ rs, array<double>@ rz)
{
    double along = (p.ex - x0) * ux + (p.ey - y0) * uy;
    p.pathEnd = pathAt + along;
    chain.insertLast(p);
    rs.insertLast(along);
    rz.insertLast(p.ez);
}

// The heights, then the pieces; again (twice at most) when a bend over the top missed a need.
array<Placed@>@ HeightsAndPieces(array<Seg@>@ segs, double jx, double jy, double jz, double a0, bool fixedStart,
                                 double endZ, bool fixedEnd, int &out stoppedAt)
{
    array<Placed@>@ chain;
    for (int pass = 0; pass < 3; pass++)
    {
        Profile(jz, fixedStart, endZ, fixedEnd);
        @chain = Pieces(segs, jx, jy, a0, stoppedAt);
        if (!raised)
            break;
    }
    return chain;
}

// ---------------------------------------------------------------- the line, fitted

array<double> lx, ly, lz;               // the line's points so far
// where the level changed while drawing: from that point on, the points move by this much in plan (Update)
array<int> shiftFrom;
array<double> shiftX, shiftY;

int stopped = -1;                       // the joint the track stops before (in the way), or -1
bool noJoin = false;                    // fitting again without the end it couldn't join
bool loopClosed = false;                // the line ends back at its own start: a loop
const double kLoopClear = 1500;         // cm along the track: a loop's first and last pieces never count as in each
                                        // other's way (they meet there)

// Whether the line has come back to its start (jx, jy): its last point within the track's width of it (3 m at least),
// after going further away than four of the kit's smallest turns.
bool BackAtStart(double jx, double jy)
{
    uint n = lx.length();
    if (n < 3 || turns.length() == 0)
        return false;
    double reach = TrackWidth() > 300 ? TrackWidth() : 300;
    double dx = lx[n - 1] - jx, dy = ly[n - 1] - jy;
    if (dx * dx + dy * dy > reach * reach)
        return false;
    double away = 4 * TurnRadius(turns[0]) * WidthScale(), far = 0;
    for (uint i = 0; i < n; i++)
    {
        double d = (lx[i] - jx) * (lx[i] - jx) + (ly[i] - jy) * (ly[i] - jy);
        if (d > far)
            far = d;
    }
    return far > away * away;
}

// Whether the plan's straights all run forwards and it ends on the end it is to join (in plan, within 20 cm).
bool PlanReaches(array<Seg@>@ segs, double jx, double jy, double a0, OpenEnd@ endAt)
{
    double x = jx, y = jy, heading = a0, f = WidthScale();
    for (uint k = 0; k < segs.length(); k++)
    {
        if (segs[k].turn)
        {
            Placed@ t = Put(segs[k].piece, segs[k].viaB, x, y, 0, heading, 0, f, f);
            x = t.ex;
            y = t.ey;
            heading += segs[k].side * 90;
        }
        else
        {
            if (segs[k].length < -1)
                return false;
            x += Math::cos(Rad(heading)) * segs[k].length;
            y += Math::sin(Rad(heading)) * segs[k].length;
        }
    }
    return joinsEnd && (x - endAt.x) * (x - endAt.x) + (y - endAt.y) * (y - endAt.y) < 20 * 20;
}

void Refit()
{
    fitNote = "";
    track.resize(0);
    stopped = -1;
    int n = int(lx.length());
    if (n < 2)
        return;
    UseKit(startEnd !is null ? startEnd.kit : kitChoice);
    // a line ending on an open end of its own kit joins it
    OpenEnd@ endAt = null;
    bool otherKit = false;
    if (hoverEnd !is null && hoverEnd !is startEnd && !noJoin)
    {
        if (hoverEnd.kit == lineKit)
            @endAt = hoverEnd;
        else
            otherKit = true;
    }
    // a line from a join goes the way it is drawn: whichever of the join's two ends faces that way
    OpenEnd@ from = startEnd;
    if (from !is null && from.joined && from.twin !is null)
    {
        double need = TurnRadius(turns[0]) * WidthScale();
        int far = -1;
        for (int i = 0; i < n && far < 0; i++)
            if ((lx[i] - from.x) * (lx[i] - from.x) + (ly[i] - from.y) * (ly[i] - from.y) >= need * need)
                far = i;
        if (far < 0)
            return;                     // not far enough yet to know which way it goes
        double way = Math::atan2(ly[far] - from.y, lx[far] - from.x);
        if (Math::cos(way - Rad(from.twin.heading)) > Math::cos(way - Rad(from.heading)))
            @from = from.twin;
    }
    // a line ending on a join merges in the way it arrives
    if (endAt !is null && endAt.joined && endAt.twin !is null && n >= 2)
    {
        int back = n - 1;
        double need = TurnRadius(turns[0]) * WidthScale();
        while (back > 0 && (lx[back] - endAt.x) * (lx[back] - endAt.x) + (ly[back] - endAt.y) * (ly[back] - endAt.y) < need * need)
            back--;
        double way = Math::atan2(endAt.y - ly[back], endAt.x - lx[back]);
        // arriving at an end means heading the opposite way to it
        if (Math::cos(way - Rad(endAt.twin.heading + 180)) > Math::cos(way - Rad(endAt.heading + 180)))
            @endAt = endAt.twin;
    }
    // the start: an open end carried on, or the line's first point heading the way it was first drawn (to 15
    // degrees; lined up with the end it is to join, when there is one)
    double jx = lx[0], jy = ly[0], jz = lz[0], a0 = 0;
    if (from !is null)
    {
        jx = from.x;
        jy = from.y;
        jz = from.z;
        a0 = from.heading;
    }
    else
    {
        int far = -1;
        double need = TurnRadius(turns[0]) * WidthScale();
        for (int i = 1; i < n && far < 0; i++)
            if ((lx[i] - lx[0]) * (lx[i] - lx[0]) + (ly[i] - ly[0]) * (ly[i] - ly[0]) >= need * need)
                far = i;
        if (far < 0)
            return;                     // not far enough yet to know which way it goes
        a0 = Deg(Math::atan2(ly[far] - ly[0], lx[far] - lx[0]));
        if (endAt !is null)
        {
            double base = endAt.heading;
            a0 = base + 90 * Math::floor((a0 - base) / 90 + 0.5);
        }
        else
            a0 = 15 * Math::floor(a0 / 15 + 0.5);
    }
    // a line drawn back to its own start closes into a loop: its start is the end it joins, facing back along it, so
    // the last piece runs into the first
    loopClosed = false;
    if (endAt is null && !noJoin && BackAtStart(jx, jy))
    {
        OpenEnd own;
        own.x = jx;
        own.y = jy;
        own.z = jz;
        own.heading = a0 + 180;
        own.width = TrackWidth();
        own.kit = lineKit;
        own.piece = -2;
        @endAt = own;
        loopClosed = true;
    }
    // ending on a node: the node is the line's end (the cursor is on it on screen, wherever the plane is under it)
    array<double> fx = lx, fy = ly, fz = lz;
    if (endAt !is null)
    {
        fx.insertLast(endAt.x);
        fy.insertLast(endAt.y);
        fz.insertLast(endAt.z);
    }
    array<Seg@>@ segs = Fit(fx, fy, fz, jx, jy, jz, a0, endAt);
    if (endAt !is null && !PlanReaches(segs, jx, jy, a0, endAt))
    {
        noJoin = true;
        Refit();
        noJoin = false;
        fitNote = "can't join that end from here: " + (fitNote != "" ? fitNote : "ends beside it");
        return;
    }
    for (int k = int(segs.length()) - 1; k >= 0; k--)
        if (!segs[k].turn && segs[k].length <= 1)
            segs.removeAt(k);           // a leg shorter than its turns need: the turns join directly
    if (segs.length() == 0)
        return;
    skipFrom = from !is null ? from.piece : -1;
    skipTo = endAt !is null ? endAt.piece : -1;
    skipFrom2 = from !is null && from.twin !is null ? from.twin.piece : -1;
    skipTo2 = endAt !is null && endAt.twin !is null ? endAt.twin.piece : -1;
    branchStart = from !is null && from.joined;
    branchEnd = endAt !is null && endAt.joined;
    branchClear = 2 * TurnRadius(turns[0]) * WidthScale() + TrackWidth();
    MakeJoints(segs, jx, jy, a0);
    Targets(fx, fy, fz);
    double ex = endAt !is null ? endAt.x : 0, ey = endAt !is null ? endAt.y : 0;
    // what is in the map, then (once) the line's own pieces as they came out: no feedback, so nothing runs away
    ownObstacles.resize(0);
    Clearance(false, jx, jy, ex, ey);
    int stop;
    array<Placed@>@ first = HeightsAndPieces(segs, jx, jy, jz, a0, startEnd !is null || loopClosed, endAt !is null ? endAt.z : 0, joinsEnd, stop);
    for (uint i = 0; i < first.length(); i++)
    {
        Obstacle@ o = OwnObstacle(first[i], int(i));
        if (o !is null)
            o.pathEnd = first[i].pathEnd;
        if (o !is null)
            ownObstacles.insertLast(o);
    }
    for (uint k = 0; k < joints.length(); k++)
    {
        joints[k].need = -1e18;
        joints[k].blocked = false;
    }
    Clearance(true, jx, jy, ex, ey);
    track = HeightsAndPieces(segs, jx, jy, jz, a0, startEnd !is null || loopClosed, endAt !is null ? endAt.z : 0, joinsEnd, stopped);
    if (stopped >= 0)
        fitNote = "in the way (red): raise the level (PgUp) or go round";
    else if (endAt !is null)
    {
        Placed@ last = track.length() > 0 ? track[track.length() - 1] : null;
        double miss = last is null ? 1e9 : Math::sqrt((last.ex - endAt.x) * (last.ex - endAt.x) + (last.ey - endAt.y) * (last.ey - endAt.y) + (last.ez - endAt.z) * (last.ez - endAt.z));
        if (loopClosed)
            fitNote = miss < 20 ? "closes the loop" : "can't close the loop from here";
        else
            fitNote = miss < 20 ? "joins the track there" : (joinsEnd ? "couldn't reach the end's height" : "can't join that end from here");
    }
    else
    {
        bool lifted = false;
        for (uint k = 0; k < joints.length() && !lifted; k++)
            lifted = joints[k].need > joints[k].target + 1;
        if (lifted)
            fitNote = "bridges over what it crosses";
        if (otherKit)
            fitNote = "that end is " + KitLabel(hoverEnd.kit) + ": a line joins only its own kind";
    }
    // the editor's placement limits
    for (uint i = 0; i < track.length(); i++)
    {
        Placed@ p = track[i];
        if (p.x < kMinX || p.x > kMaxX || p.y < kMinY || p.y > kMaxY || p.z < kMinZ || p.z > kMaxZ)
        {
            track.resize(i);
            fitNote = "stopped at the edge of the map";
            break;
        }
    }
}

// ---------------------------------------------------------------- ghosts

void ClearGhost()
{
    if (ghost != 0)
        Draw::Remove(ghost);
    if (ghostBad != 0)
        Draw::Remove(ghostBad);
    ghost = 0;
    ghostBad = 0;
}

// The outline of a piece's rolling surface: its two side edges and its ends.
void Outline(Placed@ p, array<double>@ pairs)
{
    double w = TrackWidth() / 2;
    double h0 = Rad(Math::atan2(p.ey - p.jy, p.ex - p.jx));
    // the heading at the entry: from the piece's own entry end
    array<double>@ inEnd = p.viaB ? kit[p.piece].b : kit[p.piece].a;
    array<double>@ outEnd = p.viaB ? kit[p.piece].a : kit[p.piece].b;
    array<double> m(9);
    AxesRoll(p.pitch, p.yaw, p.roll, m);
    double ix, iy, iz, ox, oy, oz;
    Apply(m, -inEnd[3], -inEnd[4], -inEnd[5], ix, iy, iz);
    Apply(m, outEnd[3], outEnd[4], outEnd[5], ox, oy, oz);
    double hin = Math::atan2(iy, ix), hout = Math::atan2(oy, ox);
    if (p.curved)
    {
        // a sag: its edges along the curve from the entry to the exit through the corner of the slopes either side
        double sx = -Math::sin(hin) * w, sy = Math::cos(hin) * w;
        for (int edge = -1; edge <= 1; edge += 2)
        {
            double px = 0, py = 0, pz = 0;
            for (int q = 0; q <= 8; q++)
            {
                double u = q / 8.0, a = (1 - u) * (1 - u), b = 2 * u * (1 - u), c = u * u;
                double qx = a * p.jx + b * p.cx + c * p.ex + edge * sx, qy = a * p.jy + b * p.cy + c * p.ey + edge * sy;
                double qz = a * p.jz + b * p.cz + c * p.ez;
                if (q > 0)
                    Pair(pairs, px, py, pz, qx, qy, qz);
                px = qx;
                py = qy;
                pz = qz;
            }
        }
        Pair(pairs, p.jx + sx, p.jy + sy, p.jz, p.jx - sx, p.jy - sy, p.jz);
        Pair(pairs, p.ex + sx, p.ey + sy, p.ez, p.ex - sx, p.ey - sy, p.ez);
        return;
    }
    if (!kit[p.piece].turn)
    {
        double sx = -Math::sin(hin) * w, sy = Math::cos(hin) * w;
        Pair(pairs, p.jx + sx, p.jy + sy, p.jz, p.ex + sx, p.ey + sy, p.ez);
        Pair(pairs, p.jx - sx, p.jy - sy, p.jz, p.ex - sx, p.ey - sy, p.ez);
        Pair(pairs, p.jx + sx, p.jy + sy, p.jz, p.jx - sx, p.jy - sy, p.jz);
        Pair(pairs, p.ex + sx, p.ey + sy, p.ez, p.ex - sx, p.ey - sy, p.ez);
        return;
    }
    // a turn: arcs from the entry to the exit around the turn's centre
    double turn = hout - hin;
    while (turn > 3.14159265) turn -= 6.2831853;
    while (turn < -3.14159265) turn += 6.2831853;
    double r = p.length / 1.41421356;           // a quarter circle's chord is r * sqrt(2)
    double side = turn > 0 ? 1 : -1;
    double cx = p.jx - Math::sin(hin) * r * side, cy = p.jy + Math::cos(hin) * r * side;
    for (int edge = -1; edge <= 1; edge += 2)
    {
        double rr = r + edge * w;
        double px = 0, py = 0;
        for (int s = 0; s <= 8; s++)
        {
            double a = hin - side * 1.5707963 + turn * s / 8;
            double qx = cx + Math::cos(a) * rr, qy = cy + Math::sin(a) * rr;
            if (s > 0)
                Pair(pairs, px, py, p.jz, qx, qy, p.jz);
            px = qx;
            py = qy;
        }
    }
}

void Pair(array<double>@ pairs, double ax, double ay, double az, double bx, double by, double bz)
{
    pairs.insertLast(ax);
    pairs.insertLast(ay);
    pairs.insertLast(az + 4);
    pairs.insertLast(bx);
    pairs.insertLast(by);
    pairs.insertLast(bz + 4);
}

void ShowGhost()
{
    ClearGhost();
    array<double> good, bad;
    for (uint i = 0; i < track.length(); i++)
        Outline(track[i], good);
    if (stopped >= 0)
        for (uint k = uint(stopped); k + 1 < joints.length(); k++)
            Pair(bad, joints[k].ex, joints[k].ey, joints[k].z, joints[k + 1].x, joints[k + 1].y, joints[k + 1].z);
    if (good.length() >= 6)
        ghost = Draw::Segments(good, 6, LIME_R, LIME_G, LIME_B, true);
    if (bad.length() >= 6)
        ghostBad = Draw::Segments(bad, 6, 1, 0.1f, 0.05f, true);
}

// ---------------------------------------------------------------- building

void Build()
{
    if (track.length() == 0)
        return;
    array<string> classes;
    array<double> transforms;
    for (uint i = 0; i < track.length(); i++)
    {
        Placed@ p = track[i];
        classes.insertLast(kit[p.piece].classPath);
        transforms.insertLast(p.x);
        transforms.insertLast(p.y);
        transforms.insertLast(p.z);
        transforms.insertLast(p.pitch);
        transforms.insertLast(p.yaw);
        transforms.insertLast(p.roll);
        transforms.insertLast(p.sx);
        transforms.insertLast(p.sy);
        transforms.insertLast(p.sz);
    }
    array<int>@ made = Editor::SpawnPieces(classes, transforms, true);
    if (made.length() > 0)
        built.insertLast(made[0]);
    Log::Info("built " + made.length() + " of " + track.length() + " pieces" + (fitNote != "" ? " (" + fitNote + ")" : ""));
    // the line's end is where the next line most likely starts
    height = track[track.length() - 1].ez;
    openEndsAt = -10;
}

// ---------------------------------------------------------------- menu

UI::Button@ PlainButton(const string &in label)
{
    UI::Button@ b = menu.AddButton(label);
    b.SetCornerRadius(6);
    b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1);
    return b;
}

void BuildMenu()
{
    @menu = UI::CreateWindow();
    menu.SetAnchor(0.5, 0);
    menu.SetPivot(0.5, 0);
    menu.SetOffset(0, 70);
    menu.SetBackground(BOX_R, BOX_G, BOX_B, 0.9f);
    menu.SetCornerRadius(10);
    menu.SetPadding(14, 10);
    menu.SetRowGap(6);
    menu.SetFont(kFont, "Regular");
    menu.SetBlocksClicks(true);
    menu.zOrder = 120;
    @pencilButton = menu.AddIconButton(Plugins::Folder() + "pencil.png");
    pencilButton.SetSize(36, 36);
    pencilButton.SetCornerRadius(8);
    menu.AddText("draw track", 19).SetGapBefore(10);
    menu.AddSpace(0);
    @kitBox = menu.AddDropdown(140);
    for (uint i = 0; i < kits.length(); i++)
        kitBox.AddOption(KitLabel(int(i)));
    kitBox.selected = kitChoice;
    menu.NewRow();
    menu.AddText("width", 15).SetColor(1, 1, 1, 0.65f);
    @widthText = menu.AddText("", 15);
    menu.AddSpace(0);
    @widthSlider = menu.AddSlider(140);
    menu.NewRow();
    menu.AddText("level", 15).SetColor(1, 1, 1, 0.65f);
    @heightText = menu.AddText("", 15);
    menu.AddSpace(0);
    @downButton = PlainButton(" - ");
    @upButton = PlainButton(" + ");
    menu.NewRow();
    @noteText = menu.AddText("", 14);
    @tip = UI::CreateWindow();
    tip.SetBackground(BOX_R, BOX_G, BOX_B, 0.85f);
    tip.SetCornerRadius(6);
    tip.SetPadding(8, 3);
    tip.SetFont(kFont, "Regular");
    tip.zOrder = 125;
    @tipText = tip.AddText("", 14);
    tip.visible = false;
    noteText.SetColor(1, 1, 1, 0.65f);
    menu.movable = true;
    menu.visible = false;
}

void RefreshMenu()
{
    pencilButton.SetBackground(pencil ? LIME_R : BUTTON_R, pencil ? LIME_G : BUTTON_G, pencil ? LIME_B : BUTTON_B, 1);
    pencilButton.SetTextColor(pencil ? 0.02f : 1, pencil ? 0.02f : 1, pencil ? 0.02f : 1, pencil ? 1 : 0.55f);
    widthSlider.value = widthSetting;
}

void ShowState()
{
    widthText.text = formatFloat(TrackWidth() / 100, "", 0, 1) + " m";
    heightText.text = heightSet ? formatFloat(height / 100, "", 0, 1) + " m" : "-";
    // at the cursor: the level, and while drawing how far above (or below) the start it is
    float mx, my;
    bool showTip = pencil && Input::MousePosition(mx, my) && !menu.hovered;
    if (showTip)
    {
        string t;
        if (DrawCore_State() == kStateDrawing && lx.length() > 0)
        {
            double rise = height - (startEnd !is null ? startEnd.z : lz[0]);
            t = (rise >= 0 ? "+" : "") + formatFloat(rise / 100, "", 0, 1) + " m";
        }
        else if (hoverEnd !is null)
            t = KitLabel(hoverEnd.kit) + (hoverEnd.joined ? " join: " : " node: ") + formatFloat(hoverEnd.width / 100, "", 0, 1) + " m wide" +
                (nodeOffset != 0 ? ", to " + (nodeOffset > 0 ? "+" : "") + formatFloat(nodeOffset / 100, "", 0, 1) + " m" : "");
        else
            t = "level " + formatFloat(height / 100, "", 0, 1) + " m";
        tipText.text = t;
        tip.SetRect(mx + 24, my + 18, 0, 0);
    }
    tip.visible = showTip;
    string note;
    if (DrawCore_State() == kStateDrawing)
        note = track.length() + (track.length() == 1 ? " piece" : " pieces") + (fitNote != "" ? ": " + fitNote : "");
    else if (hoverEnd !is null)
        note = hoverEnd.joined ? "a " + KitLabel(hoverEnd.kit) + " join: a line from here branches off the way you draw" :
                                 "carries on this " + KitLabel(hoverEnd.kit) + " end";
    else if (pencil && unreachable)
        note = "the height is out of view here: a click starts 10 m below the camera";
    else
        note = pencil ? "draw with the left button; wheel or PgUp/PgDn while drawing: level" : "pencil off: the editor as usual (B)";
    noteText.text = note;
}

// ---------------------------------------------------------------- frame

// The menu's kit (saved); the next line (and one being drawn from open space) is built with it.
void ChooseKit(int k)
{
    kitChoice = k;
    kitBox.selected = k;
    Storage::Set("kit", kits[k].name);
    fitAt = -10;
}

void Main()
{
    LoadTables();
    string saved = Storage::Get("kit", "Track");
    for (uint i = 0; i < kits.length(); i++)
        if (kits[i].name == saved)
            kitChoice = int(i);
    UseKit(kitChoice);
    widthSetting = float(parseFloat(Storage::Get("width", "0.33")));
    pencil = Storage::Get("pencil", "true") == "true";
    BuildMenu();
    RefreshMenu();
    Editor::AddHotkey(Plugins::Folder() + "pencil.png", "draw track (pencil on/off)");
}

int lastState = 0;
array<int> built;                       // a piece of each line built (newest last), for Ctrl+Z
double undoCheckAt = -1;
int movesAtPress = 0;                   // the editor's undo / redo steps when Ctrl+Z was pressed

// Ctrl+Z after a line: the editor's own undo takes it (one step). Where the editor doesn't get the key (a plugin
// window took the keyboard, say), Draw Track undoes it instead: once the editor has had 0.6 s and run no undo of its
// own (counted by the host, so the two never both undo: a slow editor on a big map took the line, and then the step
// before it went too, when this only waited 0.25 s and looked at the pieces).
void WatchUndo(bool pencilOn)
{
    if (Input::Down(Input::Ctrl) && (Input::Pressed(Input::Y) || (Input::Pressed(Input::Z) && Input::Down(Input::Shift))))
    {
        built.resize(0);                // redo makes new pieces: the list no longer says which are ours
        undoCheckAt = -1;
        return;
    }
    if (built.length() > 0 && Input::Down(Input::Ctrl) && Input::Pressed(Input::Z) && !Input::Down(Input::Shift) && !Editor::Typing())
    {
        undoCheckAt = Host::Time() + 0.6;
        movesAtPress = Editor::HistoryMoves();
    }
    if (undoCheckAt > 0 && (Host::Time() >= undoCheckAt || Editor::HistoryMoves() != movesAtPress))
    {
        bool editorDidIt = Editor::HistoryMoves() != movesAtPress;
        undoCheckAt = -1;
        int last = built[built.length() - 1];
        if (!editorDidIt && Editor::PieceClass(last) != "")
        {
            Editor::Undo();
            Log::Info("Ctrl+Z: undid the last line drawn (the editor didn't)");
        }
        built.removeLast();
        openEndsAt = -10;
    }
}

void Update(float dt)
{
    bool editing = Editor::IsOpen() && !Editor::IsTesting();
    menu.visible = editing;
    if (!editing)
    {
        // a line of ours being drawn when the editor closed is dropped (another client's strokes aren't ours)
        if (lastState == kStateDrawing && DrawCore_State() == kStateDrawing)
            DrawCore_Cancel();
        lastState = 0;
        ClearGhost();
        ShowMarkers(false);
        tip.visible = false;
        return;
    }
    // the pieces in the map: open ends and boxes, every two seconds (and after building)
    if (Host::Time() - openEndsAt > 2 || Host::Time() < openEndsAt)
    {
        openEndsAt = Host::Time();
        FindPieces();
    }

    WatchUndo(pencil);

    // the menu
    if (pencilButton.Clicked() || (Input::Pressed(Input::B) && !Editor::Typing() && !Input::Down(Input::Ctrl)))
    {
        pencil = !pencil;
        Storage::Set("pencil", pencil ? "true" : "false");
        RefreshMenu();
    }
    if (kitBox.Changed() && kitBox.selected >= 0 && kitBox.selected < int(kits.length()))
        ChooseKit(kitBox.selected);
    if (widthSlider.dragging || Math::abs(widthSlider.value - widthSetting) > 0.0001f)
    {
        widthSetting = widthSlider.value;
        Storage::Set("width", formatFloat(widthSetting, "", 0, 3));
        fitAt = -10;
    }
    bool drawingNow = DrawCore_State() == kStateDrawing;
    double step = 0;
    if (downButton.Clicked() || Input::Pressed(Input::PageDown))
        step -= kHeightStep * 2;
    if (upButton.Clicked() || Input::Pressed(Input::PageUp))
        step += kHeightStep * 2;
    if (drawingNow && Input::Wheel() != 0)
        step += Input::Wheel() * kHeightStep;

    // where a line would start: an open end under the cursor, on top of a piece, or at the height used last
    float mx, my;
    bool cursor = Input::MousePosition(mx, my);
    if (!drawingNow && cursor)
    {
        FindNearJoins(mx, my);
        @hoverEnd = EndUnderCursor(mx, my);
        if (hoverEnd !is offsetNode)
        {
            @offsetNode = hoverEnd;
            nodeOffset = 0;             // a new node under the cursor starts at its own height
        }
        if (hoverEnd !is null)
        {
            height = hoverEnd.z + nodeOffset;
            heightSet = true;
        }
        else if (Input::Pressed(Input::MouseLeft) && !menu.hovered)
        {
            double x, y, z, nx, ny, nz;
            int surface;
            if (Camera::Pick(mx, my, x, y, z, nx, ny, nz, surface) && nz > 0.7 && OnAPiece(x, y, z))
            {
                height = z + kits[kitChoice].depth;     // on top of the piece: the track's rolling surface on its base
                heightSet = true;
            }
        }
        // nothing yet, or a height the cursor can't reach from here (above the camera while looking down, say):
        // 10 m below the camera
        double px, py, pz, along;
        bool reachable = heightSet && DrawCore_OnPlane(mx, my, height, px, py, pz, along) && along <= kFarthest;
        unreachable = heightSet && !reachable;
        if (!heightSet || (!reachable && Input::Pressed(Input::MouseLeft) && !menu.hovered))
        {
            double ox, oy, oz, dx, dy, dz;
            if (Camera::Deproject(mx, my, ox, oy, oz, dx, dy, dz))
            {
                height = Math::floor((oz - 1000) / 100) * 100;
                heightSet = true;
                unreachable = false;
            }
        }
    }
    else if (drawingNow && cursor)
    {
        // the end it would join, while drawing
        FindNearJoins(mx, my);
        OpenEnd@ e = EndUnderCursor(mx, my);
        if (e !is hoverEnd)
        {
            @hoverEnd = e;
            fitAt = -10;
        }
    }
    if (step != 0 && !drawingNow && hoverEnd !is null)
        nodeOffset += step;             // over a node: the level the line from it goes to (kept while it's under the cursor)
    if (step != 0)
    {
        // while drawing, the line keeps its place in plan: the cursor's point on the raised (or lowered) plane is
        // nearer to (or further from) the camera, so the points from here on are moved back by that much
        double ox, oy, oz, nx, ny, nz, along;
        if (drawingNow && cursor && DrawCore_OnPlane(mx, my, height, ox, oy, oz, along) &&
            DrawCore_OnPlane(mx, my, height + step, nx, ny, nz, along))
        {
            double sx = (shiftX.length() > 0 ? shiftX[shiftX.length() - 1] : 0) + ox - nx;
            double sy = (shiftY.length() > 0 ? shiftY[shiftY.length() - 1] : 0) + oy - ny;
            shiftFrom.insertLast(DrawCore_Count());
            shiftX.insertLast(sx);
            shiftY.insertLast(sy);
        }
        height += step;
        fitAt = -10;
    }

    // a right click while drawing drops the line
    if (drawingNow && Input::Pressed(Input::MouseRight))
    {
        DrawCore_Cancel();
        drawingNow = false;
    }

    double r = TrackWidth() / 2;
    DrawCore_Frame(pencil, true, menu.hovered, kPlacePlane, height, r, 50, kFarthest, 0);
    int st = DrawCore_State();

    if (st == kStateDrawing && lastState != kStateDrawing)
    {
        // a new line: carrying on a node (its width too), or starting where it was pressed
        @startEnd = hoverEnd;
        lineWidth = startEnd !is null ? startEnd.width : -1;
        if (startEnd !is null && startEnd.kit != kitChoice)
            ChooseKit(startEnd.kit);    // the node's kit, carried on (as a road tool takes the road type it starts on)
        UseKit(kitChoice);
        lx.resize(0);
        ly.resize(0);
        lz.resize(0);
        shiftFrom.resize(0);
        shiftX.resize(0);
        shiftY.resize(0);
        fittedCount = -1;
    }
    if (st == kStateDrawing || st == kStateFinished)
    {
        int n = DrawCore_Count();
        if (DrawCore_ChangedFrom() < int(lx.length()))
        {
            lx.resize(0);
            ly.resize(0);
            lz.resize(0);
        }
        for (int i = int(lx.length()); i < n; i++)
        {
            double x, y, z;
            DrawCore_Point(i, x, y, z);
            for (int k = int(shiftFrom.length()) - 1; k >= 0; k--)
                if (i >= shiftFrom[k])
                {
                    x += shiftX[k];
                    y += shiftY[k];
                    break;
                }
            lx.insertLast(x);
            ly.insertLast(y);
            lz.insertLast(z);
        }
        // the plane's height changes as the line is drawn: the newest point takes the height now
        if (n > 0)
            lz[n - 1] = height;
        // fitted again at most ten times a second while drawing, and once at the end
        if (st == kStateFinished || Host::Time() - fitAt > 0.1 || Host::Time() < fitAt)
        {
            if (n != fittedCount || st == kStateFinished || fitAt < 0)
            {
                Refit();
                fittedCount = n;
                ShowGhost();
            }
            fitAt = Host::Time();
        }
        if (st == kStateFinished)
        {
            Build();
            track.resize(0);
            ClearGhost();
            lineWidth = -1;
            @startEnd = null;
        }
    }
    else
    {
        if (lastState == kStateDrawing)
        {
            // dropped
            track.resize(0);
            ClearGhost();
        }
    }
    lastState = st;
    ShowMarkers(pencil);
    ShowState();
}
