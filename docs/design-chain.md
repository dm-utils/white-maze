# White Maze - design section 22: the chain (card #037)

This file is section 22 of `docs/design.md`, kept as a separate file like sections 18 to 21. Decision record: ADR 0014.
Source of the idea: the designer's note `docs/ideas/2026-11-22-daken.md`, part 2 ("eigen tintje"), idea 1 (not in git).

The chain is a view and profile feature. `MazeSim`, the tuning, the rules, the level files and the stored solutions are
not touched. New code: one pure class in `sim/` (`MazeChain`, it only reads simulation events and replays run scripts),
four classes in `ui/`. Changed: the profile (format 2, a `chain` field per level), the profile store and main (levels
are loaded before the profile), the game screen (records the chain), the result overlay, the level select, the texts,
the debug arguments and the screenshot scenarios.

Sections changed here: 7.2, 7.3, 7.4, 7.6 (profile format 2, chain record, merge, migration), 8.2 (level cards), 8.4
(result overlay), 8.5 (order in main), 8.6 (texts), 10.4 (debug arguments), 10.5 (scenarios), 11.2 (suites).

## 22.1 Owner decision (2026-11-23)

Steef chose "the chain" as the signature of the game: at the finish the rings the player used are strung, in order, on
a thread; the thread pulls taut and becomes a necklace in the shape of the player's own route. It can be shared; a
player who reaches par gets a clasp. Only the view changes; the simulation does not.

## 22.2 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| CH1 | Every `launch` event carries `cell`, `face` and `counted` (design 3.9, `sim/sim.gd`), and `counted` is true exactly once per thrown ring, at its first launch (ADR 0009). | The chain could not be derived from events; it would need a field in `MazeSim` (a sim change). |
| CH2 | Preset rings are known from `level.preset_rings`; a thrown ring can never sit on a preset's face (`cast` reports `taken`). | A knot (22.3) could be confused with a bead; the rule of 22.4 would need the ring list. |
| CH3 | The web build processes an input event in the frame after the DOM event, well inside the browser's transient user activation window (about 1 s in Safari and Firefox, 5 s in Chrome), so `navigator.share` called from `JavaScriptBridge.eval` while handling a button press counts as user initiated. | `share()` rejects with `NotAllowedError`; the JS falls back to a download (22.11.4), so sharing still produces the image. |
| CH4 | `SubViewport.get_texture().get_image()` returns the rendered card in the web export (WebGL 2) and in the screenshot runs (real renderer). In the headless test runner (dummy renderer) it returns an empty or null image. | Tests check the export view's content, not its pixels; the share button stays disabled when no image is ready. |
| CH5 | Card #040 (roof worlds, sloped tiles, levels 10 to 21) keeps the `launch` event and the four ring faces; sloped tiles are never ring faces. New worlds add skin packs with the palette keys of 21.4.2. | The chain needs a fifth face letter and a face point for slopes (22.20). |
| CH6 | A best run in the profile replays to the same finish tick and rings used (design 6.4 R4), as long as the simulation is unchanged. | The one-time backfill (22.9.5) finds fewer chains; nothing breaks. |

## 22.3 What the chain shows

The data already exists: the simulation emits a `launch` event for every launch with the ring's cell and face and
whether it was counted; the level knows its spawn, its door and its preset rings. The chain is built from these, in
the order of the events.

| Element | Source | Shown as |
|---|---|---|
| Start | `level.spawn` (the `S` cell) | the loose end of the thread with a small end knot |
| **Bead** | a `launch` event with `counted == true` (a thrown ring at its first launch) | a white bead on the thread |
| **Knot** | the first `launch` event of a preset ring | a small knot in the thread colour; never a bead |
| End | `level.finish` (the `F` cell) | the clasp when rings used `<=` par, else a plain end knot |

Consequences:

- The number of beads always equals `rings_used`, and so the score: a short chain is a good chain. Par is visible as
  the clasp.
- Ring positions are the ring centres of the world view: `MazeWorldView.face_point(cell, face, RING_LIFT)`.
- Order is the order of first launches, not of throws: the chain follows the route. A ring thrown early and used late
  sits where the route used it.
- A ring that never launched the player (taken back, or never touched) is not on the chain, as it does not count.
- A ring taken back after its launch and thrown again to the same face gives a second bead at the same place (it
  counts twice). Coinciding beads are stacked (22.5.3).
- Further launches of the same ring add nothing (they are not counted). Deaths do not remove beads (rings used never
  goes down).
- Presets are knots, not beads: the route passes them and the shape needs the point, but they are not the player's
  beads and never count.

Rejected: the rings standing at the finish (bead back removes used rings, so the chain would disagree with the score);
every valid throw (includes rings that gave nothing, which par does not count either); throw positions or the full
player trajectory (a scribble, not a necklace; the idea note named the risk "kluwen").

## 22.4 Links, the chain record and the share code (`MazeChain`, `sim/chain.gd`)

Pure `RefCounted`, integers and strings only, no nodes. Lives in `sim/` because the profile migration (22.9.5, in
`sim/profile.gd`) needs it and `sim/` never depends on `ui/`.

```gdscript
class_name MazeChain extends RefCounted
enum Kind { BEAD, KNOT }
const MAX_LINKS := 64            # longer chains are drawn up to here and never stored (22.9)
const MAX_LINKS_TEXT := 1024
const MAX_CODE := 1100
const CODE_TAG := "wm1"
const FACE_LETTERS := "udlr"     # index = MazeLevel.Face
const BACKFILL_MAX_TICKS := 7200 # 22.9.5

static func note(events: Array, level: MazeLevel, seen: Dictionary, links: Array) -> void
static func from_run(level: MazeLevel, script: String, max_ticks: int = 36000) -> Dictionary
	# {"ok": bool, "finished": bool, "ticks": int, "rings": int, "links": Array}; ok false when the script does not parse
static func encode(links: Array) -> String
static func parse(text: String) -> Dictionary          # {"ok": bool, "links": Array, "error": String}
static func bead_count(links: Array) -> int
static func fits(level: MazeLevel, links: Array) -> bool  # every cell inside the grid
static func record(rings: int, ticks: int, links: Array) -> Dictionary   # {"rings", "ticks", "links": encode(links)}
static func better(a: Dictionary, b: Dictionary) -> bool # record a beats b; an empty b is always beaten
static func code(level_id: String, rings: int, par: int, ticks: int, links_text: String) -> String
static func parse_code(text: String) -> Dictionary
	# {"ok", "level", "rings", "par", "ticks", "links": Array, "error"}
```

A link is `{"kind": Kind, "cell": Vector2i, "face": int}`.

### 22.4.1 `note`

Called once after every `sim.step` with `sim.events`. For each event in order:

- `type == "launch"` and `counted == true`: append a `BEAD` link with the event's cell and face.
- `type == "launch"`, `counted == false`, the event's `[cell, face]` is one of `level.preset_rings` and not yet in
  `seen`: set `seen[[cell, face]] = true` and append a `KNOT` link.
- Everything else: nothing.

`seen` and `links` belong to one attempt and are cleared at its start. `from_run` creates a `MazeSim`, parses the script,
steps every input with `note` after each step and stops at the finish (like `MazeRunScript.run`); `ticks` is
`time_ticks()`, `rings` is `rings_used`.

Invariant (tested, K2): after every tick `bead_count(links) == sim.rings_used`.

### 22.4.2 Link text

The chain in the profile and in the share code is a short text:

```
links = "" / link *("-" link)
link  = kind face x "." y
kind  = "b" / "k"                         ; bead, knot
face  = "u" / "d" / "l" / "r"             ; MazeLevel.Face UP, DOWN, LEFT, RIGHT
x     = 0 to 255, y = 0 to 63             ; decimal, no leading zeros (the level limits of 5.1)
```

Example (l004): `bu7.11-bu19.11-bu31.11`. No links (no ring, no preset touched): the empty string. `parse` rejects:
an empty token (`bu7.11--bu3.4`), an unknown kind or face, a missing dot, leading zeros (`bu07.11`), `x` above 255, `y`
above 63, more than `MAX_LINKS` links, a text longer than `MAX_LINKS_TEXT`, any other character. Errors are English,
one line, never engine output.

### 22.4.3 Chain record

`{"rings": int, "ticks": int, "links": String}`: rings used and time of the finish, and its link text. Self-contained:
it is ranked on its own fields, so it never has to agree with `best_*` or `fewest_*`.

`better(a, b)`: `b` empty, or `a.rings < b.rings`, or equal rings and `a.ticks < b.ticks`. The best chain of a level is
the fewest-rings finish, the faster on a tie: the same order as `fewest_rings` (design 7.3), because the chain is about
the route and par.

### 22.4.4 Share code

```
code = "wm1/" level_id "/" rings "/" par "/" ticks "/" links
```

Example: `wm1/l004/3/3/371/bu7.11-bu19.11-bu31.11`. The level id may contain `-`, so the fields are split on `/`
first (exactly six fields, the last may be empty). Numbers are whole, without leading zeros. `parse_code` checks the
tag, the id pattern of 5.1, the numbers, the link text and that the bead count equals `rings`. Longer than `MAX_CODE`:
no code (the share card then shows none).

The code identifies a route in text form, for the share text and the card. It is not a proof (it can be typed by
hand) and nothing reads it back in this card; importing a code to view someone else's chain is **[later]**.

## 22.5 Shape and layout (`MazeChainShapes`, `ui/chain_shapes.gd`)

Pure `RefCounted`. Produces draw primitives in the format of `MazeDecor.shapes` (`poly`, `vpoly`, `line`, `polyline`,
`circle`, each with a colour), so tests read the same data that is drawn.

```gdscript
class_name MazeChainShapes extends RefCounted
enum Style { CARD, EXPORT, MINI }
const START := 2                 # extra point kinds next to MazeChain.Kind
const END := 3
static func layout(level: MazeLevel, links: Array, box: Rect2, style: int) -> Dictionary
	# {"scale": float, "map": Rect2, "inner": Rect2, "points": PackedVector2Array, "kinds": PackedInt32Array,
	#  "bead_r": float, "thread_w": float, "knot_r": float, "ghost": Array[Rect2], "door": Rect2, "more": int}
static func colours(world: int, under: Color) -> Dictionary     # 22.6.1; under = the colour the chain is drawn on
static func duration(n: int) -> float                            # 22.7
static func anim_state(t: float, n: int) -> Dictionary           # 22.7
static func shapes(lay: Dictionary, state: Dictionary, cols: Dictionary, clasp: bool, style: int) -> Array[Dictionary]
```

### 22.5.1 Route silhouette in the level frame

The chain keeps the shape of the route: every point is the real position in the level, scaled uniformly. Not
normalised (evenly spaced beads on a line or an arc), because then every chain of a level with the same ring count would
look the same, and the signature is that your route is recognisable.

The frame is **the whole level**, not the route's bounding box: chains of one level are drawn in the same frame, so
two players' chains of l006 can be compared at a glance, and the ghost map (22.5.4) fits.

- Level rectangle in world px with half a tile of margin: `L = Rect2(-20, -20, width * 40 + 40, height * 40 + 40)`.
- Inner box: `inner = box.grow(-pad)` with `pad` 18 (CARD), 0 (EXPORT; the export box already has its margins,
  22.11.1), 4 (MINI).
- `scale = minf(inner.size.x / L.size.x, inner.size.y / L.size.y)`; the map rectangle `map` is `L` scaled and centred
  in the inner box. A world point `p` maps to `map.position + (p - L.position) * scale`.
- Points (world px, then mapped): start = centre of the `S` cell; each link (up to `MAX_LINKS`) =
  `MazeWorldView.face_point(cell, face, RING_LIFT)`; end = centre of the `F` cell. `kinds` has one entry per point:
  `START`, `BEAD` or `KNOT`, `END`. `more` = links beyond `MAX_LINKS` (0 normally).

### 22.5.2 Thread

Straight segments between consecutive points: a taut thread is straight. Rejected: a spline through the points
(Catmull-Rom overshoots, so the thread would pass through walls and the shape stops being the route); a polyline of the
player's full trajectory (a tangle).

### 22.5.3 Sizes and coinciding beads

| Value | CARD, EXPORT | MINI |
|---|---|---|
| `bead_r` | `clampf(0.30 * 40 * scale, 8, 14)` | `clampf(0.30 * 40 * scale, 2.5, 4)` |
| `thread_w` | `clampf(0.35 * bead_r, 2.5, 4)` | 1.25 |
| `knot_r` | `0.45 * bead_r` | `0.6 * bead_r` |

Beads are allowed to be larger than a tile on the card (l001 on the in-game card: a tile is 13.8 px, a bead 16 px wide);
the chain is a necklace over a map, not a map.

Coinciding links: the `k`-th link (`k >= 1`) whose cell and face equal an earlier link's is moved `k * 1.7 * bead_r` card
px along the face normal (`MazeLevel.FACE_STEP[face]`), away from the block, into the air where the route was. So a
reused face shows a short stack of beads. Links that are only close keep their place (beads may touch).

### 22.5.4 Ghost map and door

- `ghost`: one rectangle per horizontal run of solid cells (`#` and `X`) of a row, mapped. Drawn in the world's
  `back_decor`, which rule C10 keeps within contrast 1.6 of the back colours: the level reads as a faint relief behind
  the chain, never competing with it. Spikes are not drawn (no red on the card). MINI: no ghost map.
- `door`: the `F` cell mapped, drawn as a rectangle in `MazeWorlds.DOOR_LIGHT` at alpha 0.25 behind the end of the
  thread (CARD and EXPORT only).

## 22.6 Look per world

### 22.6.1 Colours

`colours(world, under)` with `pal = MazeWorlds.palette(world)`:

| Key | Value |
|---|---|
| `bg_top`, `bg_bottom` | `pal.back_top`, `pal.back_bottom` (card background gradient) |
| `border` | `pal.back_line` |
| `ghost` | `pal.back_decor` |
| `thread` | the first of `pal.door_frame`, `pal.lip_lo`, `WhiteTheme.DIM` whose contrast is `>= 3.0` against `under` (CARD, EXPORT: against both `back_top` and `back_bottom`) |
| `thread_under` | `#120E10` at alpha 0.6 (the ring outline colour, `RING_OUTLINE`) |
| `bead` | `MazeWorlds.RING` (white) |
| `bead_shade` | `MazeWorlds.RING.darkened(0.10)` |
| `outline` | `MazeWorldView.RING_OUTLINE` |
| `clasp`, `clasp_hi`, `clasp_lo` | `pal.lip`, `pal.lip_hi`, `pal.lip_lo` (the world's lip tint: sand, moss, frost) |

The fallback chain for `thread` keeps the rule without a new pack key: card #040 adds packs at the same time, and a pack
with a dim door frame still gets a readable thread. With the three shipped packs `door_frame` passes (temple about 6.9,
jungle 4.6, cave 3.9 against `back_top`).

### 22.6.2 Beads are the same in every world

A bead on the chain is the bead the player threw: white with the dark ring outline, the same in every world (white is
reserved for the player's things, 18.5). World identity comes from the card background, the thread, the ghost map and
the clasp in the world's lip tint. Rejected: a bead shape per world (round, barrel, facet) as a pack field; it would
make the bead look like decor and add a pack key while card #040 writes new packs.

### 22.6.3 Elements (CARD and EXPORT)

Draw order: background, ghost map, door, thread (under-stroke, then thread), knots, beads, start knot, end (clasp or
knot), and in EXPORT the texts (22.11.1).

| Element | Shape |
|---|---|
| Background | CARD: rounded rectangle (radius 14, 6 points per corner) as a `vpoly` from `bg_top` to `bg_bottom`, then a 2 px closed polyline in `border`. EXPORT: the full rectangle, same gradient, no border. MINI: none (drawn on the level card button). |
| Thread | per segment a polyline (straight when taut, 22.7.2 when slack) in `thread_under` with width `thread_w + 2`, then in `thread` with `thread_w`. |
| Bead | circle `bead_r + 1.5` in `outline`; circle `bead_r` in `bead_shade`; circle `0.82 * bead_r` at `(-0.15, -0.15) * bead_r` in `bead` (a lit upper left, a slightly darker lower right, so it reads as a ball, not a dot). |
| Knot | circle `knot_r + 1.2` in `thread_under`, circle `knot_r` in `thread`. |
| Start | a knot at the start point plus a loose tail: a line of `1.2 * bead_r` from the start point at 120 degrees (down and left), `thread_w`, in `thread` over `thread_under`. |
| Clasp (rings used `<=` par) | at the end point, rotated to the direction of the last segment: a rounded rectangle frame of `2.6 * bead_r` by `2.0 * bead_r` (radius `0.5 * bead_r`) as a closed polyline: width 6.5 in `outline`, width 3.5 in `clasp`, then the upper long side again with width 1.5 in `clasp_hi` (offset 1 px outwards), and a pin: a line across the middle, parallel to the short sides, width 2 in `clasp_lo`. The thread ends at the frame's near side. |
| End knot (rings used `>` par) | a knot of `1.3 * knot_r` at the end point. |
| More than `MAX_LINKS` | after the last drawn bead the thread runs straight to the end; a `+N` label (`FONT_MESSAGE`, `thread` colour) sits next to the last bead. |

MINI draws only the thread (no under-stroke), beads (circle `bead_r + 1` in `outline`, `bead_r` in `bead`), knots
(`knot_r` in `thread`) and the end: a filled circle of `1.4 * bead_r` in `clasp` with a 1 px `outline` ring when par is
reached, else nothing. `under` for MINI is the level card's button colour (`WhiteTheme.BUTTON["normal"]`).

### 22.6.4 Variants

| Case | Chain |
|---|---|
| At par | beads, clasp; result text `perfect` as today. |
| Under par | beads, clasp; result text `under_par` as today. |
| 0 rings (always `<=` par) | a bare thread from start to door, with knots where presets were used, and the clasp. The result column adds `no_rings` under the rings line (22.14). |
| Over par | beads, end knot, no clasp. |
| Same face reused | stacked beads (22.5.3). |
| More than 64 rings | first 64 beads and `+N` (22.6.3); not stored in the profile (22.9.2). |

## 22.7 The finish moment

### 22.7.1 Timeline

The animation runs in **real time** from the moment the result overlay opens (`delta` of `_process`, capped at 0.1 s),
not in game time: the level speed and the slow motion must not stretch it. `n` = number of drawn links (beads and knots).

| Phase | Start | Length | What happens |
|---|---|---|---|
| In | 0 | `T_IN` 0.25 s | card fades in (background, ghost map, door, start knot: alpha 0 to 1) |
| Stringing | `T_IN` | `n * BEAD_S`, `BEAD_S = minf(0.18, 1.2 / maxi(n, 1))` | link `i` appears at `T_IN + i * BEAD_S` and drops into place over `BEAD_S`; the slack thread runs from the previous point to it |
| Taut | `T_TAUT = T_IN + n * BEAD_S` | `TAUT_S` 0.35 s | the last segment to the door appears; all sag goes to 0 with `smoothstep` |
| End | `T_END = T_TAUT + TAUT_S` | `END_S` 0.25 s | clasp: scale `0.6 + 0.4 * ease_out_back(k)`, alpha `minf(1, 3k)`; end knot: alpha `k` |

`duration(n) = T_IN + n * BEAD_S + TAUT_S + END_S`: 0.85 s for no links, 1.39 s for l004 (3 beads), 1.57 s for l009
(4 beads), 2.05 s from 7 links on (the stringing phase is at most 1.2 s), never more. `ease_out_back(x) = 1 +
2.70158 (x - 1)^3 + 1.70158 (x - 1)^2`.

### 22.7.2 State and drawing

`anim_state(t, n)` returns `{"card_a": float, "link_k": PackedFloat32Array (per link, -1 before it appears, else 0..1),
"last_seg": bool, "slack": float, "end_k": float, "done": bool}` with `slack = 1 - smoothstep(T_TAUT, T_TAUT + TAUT_S,
t)`. With `t >= duration(n)` the state equals the final state exactly (`card_a` 1, every `link_k` 1, `last_seg` true,
`slack` 0, `end_k` 1, `done` true).

- A link with `0 <= k < 1` is drawn `(1 - ease_out_cubic(k)) * 2.5 * bead_r` px above its place, alpha `minf(1, 2k)`.
- Segment `j` (from point `j` to point `j + 1`) is drawn when point `j + 1` is a link with `k >= 0`, or for the last
  segment when `last_seg`; it ends at the link's current (dropping) position.
- Sag of a segment of length `len`: `sag = slack * minf(SAG_K * len, SAG_MAX)`, `SAG_K` 0.18, `SAG_MAX`
  `0.12 * inner.size.y`. A sagging segment is a quadratic Bezier from `a` to `b` with control point
  `(a + b) / 2 + (0, 2 * sag)` (downwards: gravity), sampled at 12 points. With `slack == 0` it is a single line.
- MINI is never animated.

### 22.7.3 Skip

- During the animation a key press (`InputEventKey`, pressed, not echo), a mouse button press or a touch-down calls
  `chain_view.finish_now()` (`t = duration(n)`) and marks the event handled, so it does not also press a button, go to
  the next level (Enter), restart (R) or leave (Esc). The next press acts as today.
- Grace: during the first `SKIP_GRACE_S` (0.3 s) such presses are consumed and ignored (a jump pressed at the door does
  not skip the moment). Keys still held from playing do not produce new presses.
- `MazeOverlays._input` does this (it runs before the GUI). `MazeGame._input` handles Enter only when
  `not overlays.chain_animating()`, so the order of `_input` calls does not matter.
- Reduced motion: when the player's system asks for reduced motion, the chain starts in its final state (no animation,
  no skip needed). Web: `JavaScriptBridge.eval("!!(window.matchMedia && window.matchMedia('(prefers-reduced-motion:
  reduce)').matches)", true)`, read once in `MazeMain._ready` into `opts["reduced_motion"]`. Debug flag
  `--reduced-motion` sets it on any platform.
- Shots and frozen runs: in `--shot` mode the chain is in its final state unless `--chain-t=<s>` fixes `t` (22.15).

No sound (there is no sound in the game yet; when sound comes, a soft click per bead and one at the clasp fit here).
No vibration (calm, and the web API needs its own activation).

## 22.8 Result screen

`MazeOverlays.show_result(data)` gets new keys: `links` (Array), `links_text`, `code`, `level` (MazeLevel), `world`
(int), `number`, `name`, `reduced_motion`, `chain_t` (float, -1 when not fixed). Layout of the result panel (the `BG`
panel at alpha 0.85 stays):

```
CenterContainer
  HBoxContainer (separation RESULT_GAP 40)
    MazeChainView (style CARD, W x H)
    VBoxContainer (width RESULT_COL_W 480): finished, time, rings line [+ no_rings], record or best time,
                                            share button, share feedback (DIM, hidden when empty),
                                            restart, next, levels
```

- `W = clampf(avail.x - RESULT_COL_W - RESULT_GAP, CARD_MIN_W, CARD_MAX_W)` with `CARD_MIN_W` 480 and `CARD_MAX_W`
  800; `H = W * 9 / 16`; when `H > avail.y`: `H = avail.y`, `W = H * 16 / 9`. `avail` = viewport minus `2 * MARGIN` and
  the safe area insets (`WhiteSafeArea.insets` with the game's `safe` override). Recomputed on viewport resize.
- Results: 1280 x 720: card 712 x 400; 1600 x 720 with safe 60,0,60,24: 800 x 450; 1280 x 960: 712 x 400. Every
  landscape canvas is at least 1280 wide (design 10.2), so the side-by-side layout always fits; portrait shows the
  rotate hint.
- The column is the existing content with width 480 instead of 560, plus the share button and its feedback line. Focus
  stays on Next (or Restart on the last level).
- The world behind the panel stays frozen as today.

`MazeChainView` (`ui/chain_view.gd`, `Control`, `mouse_filter = IGNORE`):

```gdscript
class_name MazeChainView extends Control
var style := MazeChainShapes.Style.CARD
func setup(level: MazeLevel, links: Array, world: int, clasp: bool, t0: float = 0.0, frozen: bool = false) -> void
func finish_now() -> void
func animating() -> bool         # t < duration and not frozen
func primitives() -> Array       # the last computed list, for tests
func texts() -> Array            # EXPORT only: [{"text", "pos", "size", "align"}], for tests (22.11.1)
# _process(delta): t += minf(delta, 0.1) unless frozen or done; recompute layout on resize; queue_redraw while animating
# _draw(): replays MazeChainShapes.shapes(layout(...), anim_state(t, n), colours(...), clasp, style)
```

`clasp = rings_used <= par`. `MazeOverlays` gets `chain_view` (the CARD view or null) and `chain_animating()`.

## 22.9 Profile: format 2

### 22.9.1 The field

A level entry gets `chain`, a chain record (22.4.3), absent until a finish with at most `MAX_LINKS` links:

```json
"l004": {
  "best_ticks": 371, "best_rings": 3, "best_run": "R2 T142 R70 U ...",
  "fewest_rings": 3, "fewest_ticks": 371,
  "chain": {"rings": 3, "ticks": 371, "links": "bu7.11-bu19.11-bu31.11"},
  "first_finish": 1763900000, "last_played": 1763900000, "counts": {"...": {}}
}
```

Size: at most 1024 characters of links per level; P6 (30 levels) stays under 100 KB; a new check P7 adds a 64-link chain
to every level of the P6 profile and stays under 140 KB.

### 22.9.2 Operations (`MazeProfile`, changes to 7.3)

```gdscript
const FORMAT := 2
static func sanitize(data: Variant, levels: Dictionary = {}) -> Dictionary
	# {"profile", "status": "ok" | "damaged" | "newer", "migrated": bool}; levels: id -> MazeLevel, for 22.9.5
static func migrate(data: Dictionary) -> Dictionary     # format 1 -> 2: copy with format 2 (no structural change)
static func record_finish(p: Dictionary, level_id: String, ticks: int, rings: int, run: String, now: int,
		links: Variant = null) -> Dictionary
	# adds "new_chain": bool to the result
static func backfill_chains(p: Dictionary, levels: Dictionary) -> int   # 22.9.5; number of chains added
```

- `record_finish` with `links` a String that `MazeChain.parse` accepts: `cand = {"rings": rings, "ticks": ticks,
  "links": links}`; when `MazeChain.better(cand, entry.get("chain", {}))`, store it and `new_chain = true`. `links`
  null or unparsable: no change, `new_chain = false`. Callers without a chain (existing tests) pass nothing.
- The game passes the text only when the attempt has at most `MAX_LINKS` links (else null).

### 22.9.3 `sanitize` (changes to 7.3)

1. Not a Dictionary, `format` missing, not whole, below 1: `damaged` (unchanged).
2. `format > 2`: `newer` (unchanged rule, new number).
3. Otherwise remember `from = format`; `migrate` when `from == 1`; the field checks of 7.3, plus `chain` in every level
   entry: a Dictionary with exactly `rings`, `ticks` (whole, `>= 0`) and `links` (a String of at most
   `MAX_LINKS_TEXT` that `MazeChain.parse` accepts, with `bead_count == rings`); otherwise the key is removed. Unknown
   keys inside `chain` make it invalid (it is a closed record). `format` becomes 2.
4. When `from == 1`: `backfill_chains(out, levels)`; `migrated = true`.

### 22.9.4 Merge (changes to 7.6)

`chain`: the record for which `better` holds (absent loses); tie: `local`. The record travels whole. `merge(a, a) == a`
holds. `chain` is added to the list of keys that `_merge_level` erases before picking, so it is never taken from the
unknown-key pass-through.

### 22.9.5 Migration 1 to 2 and backfill

Players of the live build have format-1 profiles with finished levels and their fastest run (`best_run`). The
migration gives them chains at once, so the level select is not empty after the update:

`backfill_chains(p, levels)`, for every level entry without `chain` whose id is in `levels` with a valid level, with
`best_run` non-empty, `best_ticks` and `best_rings` present, and a script of at most `BACKFILL_MAX_TICKS` ticks (2 min of
game time; longer runs are skipped so opening never stalls): `r = MazeChain.from_run(level, best_run)`. When `r.ok`,
`r.finished`, `r.ticks == best_ticks`, `r.rings == best_rings` and `r.links.size() <= MAX_LINKS`: `chain =
MazeChain.record(r.rings, r.ticks, r.links)`. Otherwise the entry stays without a chain.

The backfilled chain is the chain of the fastest run, not necessarily of the fewest-rings run; it is a valid chain
record ranked by its own fields, and the next better finish replaces it (22.4.3). It runs once per profile, during the
migration; afterwards every finish writes its chain directly.

Why the format goes to 2 although only a field is added (conventions: "adding a field does not raise the format"):

- An older build that loads a profile with chains keeps `chain` only as an unknown key: it never updates it, and its
  merge (7.6, unknown keys from `local`) would keep a worse local chain over a better remote one. With format 2 an older
  build treats the file as newer and leaves it alone (`notice = "newer"`, not writable), so a chain is never degraded.
- The backfill must run exactly once; the format number records that it happened.
- Cost: a browser that still runs a cached older build after the update shows the "newer" notice and saves nothing
  until it loads the new build. There is no online profile yet (phase 3), so no other device can be affected.

### 22.9.6 Store and main (changes to 7.4 and 8.5)

- `MazeProfileStore.open(p: String, now: int, levels: Dictionary = {})` passes `levels` to `sanitize`; when
  `migrated` is true it saves at once (the file on disk becomes format 2). A format-1 file is never set aside.
- `MazeMain._ready` loads the level ids and levels **before** opening the profile and passes `{id: level}` for the
  valid levels. The rest of the order is unchanged.
- `--shot` keeps `open_memory`; with `--demo-profile` (22.15) the memory profile is filled from the stored solutions.

## 22.10 Level select: all chains at a glance

Every finished level card shows its best chain as a mini chain; together the cards are the overview of all chains.

- `MazeLevelSelect._card`: when the level is open, finished, the entry has a `chain` that parses, and `MazeChain.fits`
  holds: add a `MazeChainView` with style `MINI` as a child of the button, `mouse_filter = IGNORE`, size `MINI_W x
  MINI_H` = 104 x 58, anchored to the top-right corner with an inset of `MINI_INSET` 10 px. World:
  `MazeWorlds.for_number(i + 1)`; clasp: `chain.rings <= par`.
- No mini chain for locked levels, unfinished levels, or a finished level without a chain (a level finished before the
  update whose run could not be replayed); a bare thread would read as "0 rings", so nothing is better than a
  placeholder.
- The text lines stay as they are (they carry the numbers; the mini chain is a picture of the route). The card height
  stays 170, so nine cards still fit at 1280 x 720 without scrolling.
- No-overlap rule (K12): the first two lines (number and name, difficulty) must fit left of the mini chain:
  `font.get_string_size(line, FONT_BUTTON).x + 2 * BUTTON_PAD <= card_w - MINI_W - 2 * MINI_INSET` for every shipped
  level in both languages at 1280 x 720 (card width about 353, so about 219 px for the line; the longest shipped name,
  `3  Smalle pilaar` / `3  Narrow pillar`, is about 180 px). `BUTTON_PAD` is the button's horizontal content margin
  (read from its style box in the test). Lines 3 and 4 run under the mini chain's bottom (58 + 10 = 68 px from the top;
  lines 3 and 4 start below about 85 px) and may use the full width; the test checks this vertical rule as well.
- A gallery screen with all chains at full size and sharing of a stored best chain is **[later]**; the idea note's
  city postcard (idea 7) can reuse `MazeChainShapes` then.

## 22.11 Sharing

### 22.11.1 Share card (`EXPORT`)

A fixed image of 1200 x 675 px (16:9, readable as a link preview and in a chat):

| Area | Content |
|---|---|
| Background | the world gradient over the full image (22.6.3) |
| Header, `y` 0 to 112 | left: `WHITE MAZE` (size 22, `WhiteTheme.DIM`) at `(40, 46)`; `"%d  %s" % [number, name]` (size 36, `WhiteTheme.TEXT`) at `(40, 92)`. Right-aligned at `x = 1160`: the time `MazeFormat.time(ticks)` (size 36, `TEXT`) at baseline 52; the rings line `result_rings % [rings, par]` plus `perfect`, `under_par` or `no_rings` as on the result screen (size 22, `TEXT`) at baseline 92 |
| Chain box | `Rect2(40, 124, 1120, 488)`, style `EXPORT`, final state |
| Footer, `y` 612 to 675 | left: the share code (size 18, `DIM`) at `(40, 652)`, omitted when there is no code; right-aligned at `x = 1160`: `play.white-maze.steefbeest.nl` (size 18, `DIM`) |

Text is drawn with `ThemeDB.fallback_font` (the font the game already uses) with `draw_string`; sizes are fixed
because the image has a fixed size. The language is the current `WhiteText.lang`. A name too long for the header is
cut with `TextServer` overrun (`OVERRUN_TRIM_ELLIPSIS`) at 640 px.

### 22.11.2 Rendering (`MazeChainExport`, `ui/chain_export.gd`)

```gdscript
class_name MazeChainExport extends Node
signal ready_png
const SIZE := Vector2i(1200, 675)
var png := PackedByteArray()
func render(info: Dictionary) -> void
	# info: level, links, world, clasp, number, name, ticks, rings, par, code, under (bool), zero (bool)
func view() -> MazeChainView    # the EXPORT view inside the viewport, for tests
```

- A `SubViewport` of `SIZE`, `transparent_bg = false`, `render_target_update_mode = UPDATE_ONCE`, holding one
  `MazeChainView` (style `EXPORT`, frozen, final state) that also draws the texts. A `SubViewport` is not drawn on
  screen by itself; the export node lives under the result overlay.
- After `await RenderingServer.frame_post_draw`: `img = get_texture().get_image()`; when `img` is non-null and not
  empty: `png = img.save_png_to_buffer()` and `ready_png` is emitted. Otherwise `png` stays empty.
- `render` is started when the result opens (not when the button is pressed), so the image is ready when the player
  presses Share and the browser's activation window is used only for the share call itself. Expected size 60 to 160 KB.

### 22.11.3 Share button

- In the result column: `WhiteUi.button(t("share"))` on the web, `t("share_save")` elsewhere; disabled until
  `ready_png`; `focus_mode = FOCUS_ALL`, reachable with the arrow keys, not focused by default.
- Web: `MazeChainShare.share(png, file_name, title, text) -> String` returns `"share"` or `"download"`; on `"download"`
  the feedback line shows `t("chain_downloaded")`. On `"share"` nothing is shown (the system share sheet is the
  feedback; a cancel is silent).
- Not web (desktop debug runs): the PNG is written to `user://chains/<file_name>` and the feedback line shows
  `t("chain_saved") % path` (`ProjectSettings.globalize_path`).
- `file_name` = `"white-maze-%s-%d-%d.png" % [level_id, rings, ticks]`.
- `title` = `"White Maze"`. `text` = `t("share_text") % [number, name, rings, par, MazeFormat.time(ticks)]`, then a new
  line and the share code (when present), then a new line and `https://play.white-maze.steefbeest.nl`.

### 22.11.4 Web Share with download fallback (`MazeChainShare`, `ui/chain_share.gd`)

```gdscript
class_name MazeChainShare extends RefCounted
const SHARE_JS := "..."     # defines window.whiteMazeShare once
static func share(png: PackedByteArray, file_name: String, title: String, text: String) -> String
static func save_local(png: PackedByteArray, file_name: String) -> String   # non-web; returns the path or ""
```

`share` evaluates `SHARE_JS` (it defines the function only when missing), then
`JavaScriptBridge.eval("window.whiteMazeShare(%s, %s, %s, %s)" % [JSON.stringify(Marshalls.raw_to_base64(png)),
JSON.stringify(file_name), JSON.stringify(title), JSON.stringify(text)], true)`. `SHARE_JS`:

```js
window.whiteMazeShare = window.whiteMazeShare || function (b64, name, title, text) {
  var bin = atob(b64);
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  var blob = new Blob([bytes], {type: 'image/png'});
  var download = function () {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  };
  try {
    var file = new File([blob], name, {type: 'image/png'});
    if (navigator.canShare && navigator.canShare({files: [file]})) {
      navigator.share({files: [file], title: title, text: text}).catch(function (e) {
        if (!e || e.name !== 'AbortError') download();
      });
      return 'share';
    }
  } catch (e) {}
  download();
  return 'download';
};
```

- Web Share with files where `canShare` says so (Android Chrome, iOS and macOS Safari, Windows Edge and Chrome); a
  download elsewhere (desktop Firefox, Linux browsers). A user cancel (`AbortError`) does nothing; any other rejection
  (for example `NotAllowedError` when the activation expired, CH3) downloads instead.
- Privacy: no network request, no external script, no analytics, no tracker, no URL parameters; the image is built in
  the page and handed to the system share sheet or saved. The only address in the text is the game's own play address.
  The code contains no personal data (level id, numbers, cells).
- The function stays on `window` under one name; no other global is added.

Rejected: sharing a URL that encodes the route (needs a page that draws it, and that page would be a service); an
image host or a short-link service (external, tracking); `canvas.toBlob` of the game canvas (captures HUD and overlay,
depends on the screen size); `JavaScriptBridge.download_buffer` alone (no share sheet on phones, where sharing matters).

## 22.12 Determinism

- Links come from simulation events, which are deterministic (S17). `from_run` on a solution and the in-game recording
  of the same inputs give the same links (K5). The link text, the record and the code are integer strings.
- Layout and shapes are pure functions of the level, the links, the box, the style and `t`; no randomness, no `Time`.
  Two calls give equal primitive lists; values are pinned in a test with a tolerance of 0.01 px (K6).
- The export image and the shots are compared between two runs with `shots.sh compare` (K16), as for every shot
  (assumption K3 of 21.2: one machine).
- So the planned snapshot test exists at three levels: link text per solution (exact), primitives (pinned numbers),
  images (two runs equal).

## 22.13 Accessibility and phone readability

- Every fact on the chain is also text in the result column (rings, par, perfect or under par, no rings, time); the
  chain never carries information alone.
- Par is shown by shape (a buckle versus a plain knot), not by colour alone; the clasp tint has contrast `>= 3.0`
  against both background colours (K8), and the grey copy of the shots keeps it visible.
- Beads are white with a dark outline on a dark card (contrast above 10); the thread has contrast `>= 3.0` (22.6.1).
- Sizes on the smallest target (960 x 432 phone, canvas 1600 x 720 at 0.6): card 800 x 450 canvas = 480 x 270
  physical px; bead at least 8 canvas px radius = about 10 physical px wide; thread at least 2.5 canvas = 1.5 physical
  px plus its under-stroke; clasp about 25 x 19 physical px.
- The animation is short (at most 2.05 s), skippable with any key, click or tap, and off with reduced motion.
- The mini chains on the level select are pictures only; their content is in the card text lines.
- Share button: a normal focusable button with a text label; feedback as text.

## 22.14 Texts (`MazeStrings`, additions to 8.6)

| Key | Dutch | English |
|---|---|---|
| `share` | `Delen` | `Share` |
| `share_save` | `Afbeelding bewaren` | `Save image` |
| `chain_downloaded` | `Afbeelding gedownload` | `Image downloaded` |
| `chain_saved` | `Bewaard: %s` | `Saved: %s` |
| `share_text` | `White Maze %d · %s · %d ringen · par %d · %s` | `White Maze %d · %s · %d rings · par %d · %s` |
| `no_rings` | `Zonder ringen!` | `No rings!` |

## 22.15 Debug arguments and screenshot scenarios

New debug arguments (`MazeMain.parse_args`, passed to the game in `_debug_game_options`):

| Argument | Effect |
|---|---|
| `--chain-t=<s>` | Decimal seconds `>= 0`: the result chain is frozen at this time of its animation. Other values: warning, ignored. |
| `--chain-export` | With `--level` and `--solve` (or `--keys` that finish): the screen shows only the share card, 1200 x 675, at the top-left (for the screenshot of the export; the scenario's window has that size). |
| `--demo-profile` | Only with `--shot`: the memory profile is filled by replaying every solution of `tests/solutions.json` (`record_start`, then `record_finish` with its links, `now` = 0), so the level select shows mini chains. Without `--shot`: warning, ignored. |
| `--reduced-motion` | The chain starts in its final state (22.7.3). |

No web query keys are added (browsers can emulate reduced motion in their developer tools).

Scenarios added to `tools/shots.txt` (the existing `result` scenario now shows the chain of l001):

```
chain-mid 1280x720 --level=l004 --solve --chain-t=0.55
chain-taut 1280x720 --level=l004 --solve --chain-t=0.95
chain-jungle 1280x720 --level=l005 --solve
chain-towers 1280x720 --level=l006 --solve
chain-cave 1280x720 --level=l009 --solve
chain-zero 1280x720 --level=l001 --keys=<zero>
chain-overpar 1280x720 --level=l004 --keys=<over>
chain-phone 960x432 --level=l006 --solve --touch --safe=40,0,40,16
chain-export 1200x675 --level=l004 --solve --chain-export
chain-export-cave 1200x675 --level=l009 --solve --chain-export --lang=en
chain-export-zero 1200x675 --level=l001 --keys=<zero> --chain-export
select-chains 1280x720 --all-levels --demo-profile
select-chains-en 1280x720 --all-levels --demo-profile --lang=en
select-chains-phone 960x432 --all-levels --demo-profile --safe=40,0,40,16
```

- `chain-mid`: l004 at 0.55 s: the second bead is dropping (it appears at 0.43 s), the thread is slack.
  `chain-taut`: at 0.95 s the thread is pulling taut (0.79 to 1.14 s), no clasp yet.
- `<zero>`: a run of l001 that finishes with 0 rings (board item #010: the opening is jumpable). The developer records it
  with `--print-run` and writes it into the file (commas for spaces, 21.19).
- `<over>`: a run of l004 that finishes with 4 rings (one extra floor ring that launches, for example taken back and
  thrown again on the same face, which also shows the stacked beads). The developer records it and writes it in.
- The `--keys` runs must finish; `--keys` and `--solve` both open the result when the run finishes (design 10.4).

## 22.16 Acceptance

Headless tests in a new suite `tests/chain_tests.gd` (added to `SUITES`) unless stated.

- **K1 Simulation untouched.** `git diff <base> -- sim/sim.gd sim/tuning.gd sim/level.gd sim/aim.gd sim/input.gd
  sim/run_script.gd levels/ tests/solutions.json` is empty; all existing checks green (`MIN_CHECKS` only goes up, apart
  from the profile checks that change with format 2, K10); `tools/check_levels.gd` exits 0; A1 green.
- **K2 Links from events.** On fixture maps: a) a thrown ring that launches once gives one bead; b) bouncing three times
  on it still one bead; c) a ring taken back before any launch gives none; d) take back after the launch, throw again
  to the same face and launch: two beads with equal cell and face; e) a preset launched twice gives one knot and no
  bead; f) a death after a counted launch keeps the bead; g) for every shipped solution, after every tick,
  `bead_count(links) == sim.rings_used`.
- **K3 Pinned chains.** `encode(from_run(level, solution).links)` per shipped level equals:

  | Level | Links |
  |---|---|
  | l004 | `bu7.11-bu19.11-bu31.11` |
  | l005 | `ku22.16-br21.9-bl26.9` |
  | l006 | `bu5.21-bu9.17-bu13.13-bu17.9` |
  | l007 | `br10.9-bu27.12` |
  | l008 | `ku1.13-br0.6-bu10.13` |
  | l009 | `bu8.13-bu11.13-br10.6-bu20.13` |
  | l001 | expected `ku26.11-bu38.11` |
  | l002 | expected `ku1.11-br0.<4 or 5>-bu22.11` |
  | l003 | expected `bu1.11-br0.4-bu24.11` |

  l004 to l009 follow the ring lists of design 17 in the order of first launch. For l001 to l003 the developer pins the
  recorded value; when it differs from the expected text beyond the open row of l002, the developer records why in
  22.21 (the ring list of 5.4 would be wrong, not the chain).
- **K4 Codecs.** `parse(encode(x)).links == x` for 50 random link arrays of 0 to 64 links (`WhiteRng`, seeded); each
  error of 22.4.2 gives `ok == false` with a message and no engine output; `parse_code(code(...))` round-trips for
  every pinned chain of K3; `parse_code` rejects a wrong tag, five or seven fields, a bad id, leading zeros, a bead count
  that differs from `rings`, a code longer than `MAX_CODE`.
- **K5 Game equals replay.** For every shipped level, `MazeGame` with `--solve` ends with `last_result["links_text"]`
  equal to K3, and playing the l001 solution through `MazeControls` (the U3 path) gives the same links as
  `from_run`.
- **K6 Layout.** For every shipped level in CARD 712 x 400, EXPORT and MINI 104 x 58: every point, ghost rectangle and
  the door lie inside the inner box; `scale` equals the formula of 22.5.1; `bead_r`, `thread_w` within their clamps;
  two calls give equal results; for l004 CARD the start, the three bead points and the end equal pinned values within
  0.01 px; the stacked-bead rule moves the second of two equal links by `1.7 * bead_r` along the face normal.
- **K7 Animation.** `duration(0) == 0.85`, `duration(3) == 1.39`, `duration(4) == 1.57` and `duration(7) == 2.05`
  (within 0.001), `duration(n) <= 2.05` for `n` up to 64; `anim_state` at `t = 0`: `card_a == 0`, no link shown; at
  `T_IN + 0.5 * BEAD_S`: first link with `k == 0.5`; `slack == 1` before `T_TAUT` and `0` after `T_TAUT + TAUT_S`; at
  `duration(n)` the state equals the final state; `shapes` at `t = duration(n)` equals `shapes` at `t = 99`.
- **K8 Look rules.** For every world in `MazeSkins.PACKS` (so new packs of #040 are covered automatically): `thread`
  has contrast `>= 3.0` against both background colours, and the MINI `thread` against the button colour; `clasp` has
  contrast `>= 3.0` against both background colours; beads use only `RING`, its shade and `RING_OUTLINE`. With rings
  `<=` par the primitives contain the clasp and no end knot, with rings `>` par the end knot and no clasp; with no
  links the thread is one segment from start to end.
- **K9 Skip.** In `MazeGame` after the l004 finish: a key press at 0.1 s is consumed and changes nothing (grace); a key
  press, a mouse press and a touch-down (each in its own run) at 0.5 s end the animation in that frame, and the scene
  stays on the result (no next level, no restart, no level select); after the animation, Enter opens the next level as
  before. With `reduced_motion` the view is not animating from the first frame.
- **K10 Profile.** `create` gives format 2; `sanitize` of format 3 is `newer`, of format 1 is `ok` with `migrated` true;
  chain cases each with its expected result: valid kept; `links` unparsable, too long, bead count not equal to `rings`,
  negative or fractional `rings` or `ticks`, an extra key, not a Dictionary: removed; `record_finish`: first finish
  stores the chain, fewer rings replaces, equal rings and faster replaces, equal rings and slower keeps, more rings
  keeps, `links` null changes nothing, `new_chain` reports it; `merge`: better chain from either side, tie to local,
  absent loses, `merge(a, a) == a`; P6 still under 100 KB; P7 under 140 KB. Existing profile tests that assert format 1
  are updated to 2 (their other assertions unchanged).
- **K11 Migration.** A format-1 file (written by the test under `user://white_maze_test_*`) with the l004 solution as
  `best_run` and its true `best_ticks` and `best_rings`: after `open` with the levels the file on disk has format 2 and
  `chain` equal to `from_run`; with `best_run` `""`, with a wrong `best_ticks`, with a script longer than
  `BACKFILL_MAX_TICKS`, or without the level in `levels`: no chain, format 2; a second `open` changes nothing; a
  format-1 file is never renamed to `profile.damaged-*`.
- **K12 Level select.** With `--demo-profile` (or the same profile built in the test): every finished card has exactly
  one MINI view and unfinished or locked cards none; the no-overlap rules of 22.10 hold for all nine levels in `nl` and
  `en` at 1280 x 720 and 1600 x 720; nine cards fit at 1280 x 720 without scrolling (as 17.3).
- **K13 Result layout.** At 1280 x 720, 1600 x 720 (safe 60,0,60,24) and 1280 x 960 the card and the column lie inside
  the safe rect without overlap; the card is between 480 and 800 wide and 16:9; on l001 `bead_r >= 8`.
- **K14 Export and share.** The EXPORT view of l004 holds the header texts, the rings line, the code and the play
  address (from `texts()`); `file_name` and the share text follow 22.11.3; `SHARE_JS` contains none of `fetch`,
  `XMLHttpRequest`, `sendBeacon`, `http`, `import(`; the share text contains no address other than the play address;
  in a run with a real renderer (the screenshot run) `save_local` writes a non-empty PNG under `user://chains/`, which
  the check removes afterwards.
- **K15 Print.** `--print-run` prints, after the `run` line, `chain <code>` (the share code).
- **K16 Shots.** All scenarios of 22.15 and the existing ones are produced without errors; two runs are identical
  (`shots.sh compare`).
- **K17 Web (manual, tester).** Android Chrome: Share opens the system sheet with the PNG and the text; iOS Safari the
  same; desktop Chrome on Linux and Firefox download `white-maze-<id>-<rings>-<ticks>.png`; cancelling the sheet does
  nothing; the developer tools' network tab shows no request when sharing.
- **K18 Readability (manual, tester).** On the shots and on a phone: beads, thread and clasp readable at 960 x 432 and in
  the grey copies (`tools/shot_variants.gd`); the clasp reads as a buckle, the over-par end as a plain knot; the mini
  chains are recognisable as routes and do not touch the card text.

## 22.17 Developer steps (card #038)

Branch `feature/chain`, one commit per step, each green before the next. Every step keeps K1.

1. **`MazeChain`.** `sim/chain.gd` with `note`, `from_run`, the link text, the record, `better`, the code. Tests K2, K3,
   K4 in `tests/chain_tests.gd`. Record the l001 to l003 values for K3.
2. **Recording in the game.** `MazeGame`: `_links` and `_preset_seen` reset in `_start_attempt`; one helper
   `_step_sim(inp)` (step, `MazeChain.note`, world and HUD notifications) used by `_tick` and `_debug_setup`; at the
   finish `result` gets `links`, `links_text` (when at most `MAX_LINKS` links, else `""` and no chain passed to the
   profile), `code`, `level`, `world`, `number`, `name`; `--print-run` prints the `chain` line. Tests K5, K15.
3. **Profile format 2.** `FORMAT` 2, `migrate`, `sanitize` with `levels` and `migrated`, the `chain` rules,
   `record_finish` with `links`, `merge`, `backfill_chains`; `MazeProfileStore.open` with `levels` and the save after a
   migration; `MazeMain` loads levels first. Tests K10, K11; update the format numbers in the existing profile and
   store tests (P1, P2, P4) and note which.
4. **Shapes and the view.** `ui/chain_shapes.gd` (layout, colours, timeline, shapes) and `ui/chain_view.gd`. Tests K6,
   K7, K8.
5. **Result screen.** `MazeOverlays.show_result` layout of 22.8, the CARD view, skip with grace, `chain_animating`,
   `MazeGame._input` guard, reduced motion, `--chain-t`, `--reduced-motion`, `no_rings`. Existing UI tests that press
   Enter or a button right after a finish first call `overlays.chain_view.finish_now()` (or advance 2.1 s); list them.
   Tests K9, K13. Shots: `result`, `chain-mid`, `chain-taut`, `chain-jungle`, `chain-towers`, `chain-cave`,
   `chain-phone`, `chain-zero`, `chain-overpar` (record the two `--keys` runs).
6. **Export and share.** `ui/chain_export.gd`, `ui/chain_share.gd`, the share button and feedback, texts of 22.14,
   `--chain-export`. Test K14. Shots `chain-export*`. Try the web export locally (`build/web` served on the local
   network) on a phone if one is at hand; otherwise leave K17 to the tester.
7. **Level select.** Mini chains, `--demo-profile`. Test K12. Shots `select-chains*`; `select` and `select-en` stay
   unchanged (their memory profile is empty, so no mini chains).
8. **Documentation and close.** Deviations as built in 22.21; raise `MIN_CHECKS`; in `docs/design.md` add `## 22. The
   chain` with a pointer to this file and mention it in the status line, and one line each under 7.2, 8.2, 8.4 and 10.4:
   "Changed by section 22 (`docs/design-chain.md`)"; merge the terms of 22.19 into `docs/glossary.md` (and change the
   glossary's `Format` entry: profile format 2); `docs/conventions.md`: classes `MazeChain`, `MazeChainShapes`,
   `MazeChainView`, `MazeChainExport`, `MazeChainShare`, and in "Profile" a sentence that format 2 holds the chain
   record and that a backfill runs once in the migration from 1.

## 22.18 Tester checklist (card #039)

Headless: K1 to K15 in the run; the diff of K1; `tools/check_levels.gd`; `--print-run` on l004 prints the chain line.

Shots (`tools/shots.sh`, with `tools/shot_variants.gd` for the grey and half copies):

- `result`, `chain-jungle`, `chain-towers`, `chain-cave`: the chain has the shape of the route (compare the bead
  places with the ring lists of 5.4 and 17 on the ghost map); beads white with an outline; thread readable; clasp in
  sand, moss or frost; knots for the presets of l001, l005 and l008 are clearly not beads.
- `chain-mid`, `chain-taut`: beads dropping in order, a slack thread hanging down, then pulling straight; nothing
  outside the card.
- `chain-zero`: bare thread with clasp and the `no_rings` line. `chain-overpar`: no clasp, an end knot, two stacked
  beads at the reused face.
- `chain-phone`: card and column side by side on 960 x 432, nothing under the safe area, beads countable.
- `chain-export*`: header, chain, code and address readable at 100 % and as the 50 % copy; in English for the cave;
  nothing cut off; the zero variant correct.
- `select-chains*`: mini chains on the finished cards only, not touching the text, recognisable per level; nine cards
  fit without scrolling at 1280 x 720.
- Two runs of the shots identical (`shots.sh compare`).

Play in a desktop browser (web export) and on a phone (landscape):

- Finish l001 to l004: the animation is calm and short; any key, click or tap skips it without also pressing Next or
  restarting; a jump held into the door does not skip it; after it, Enter goes on as before.
- Reduced motion on (system setting, or the browser's emulation): no animation.
- Share on Android Chrome and iOS Safari (sheet with image and text; cancel does nothing); on desktop a download with
  the right file name; the network tab shows no request when sharing.
- After the update with a profile from the live build: finished levels show a mini chain (backfill) where the fastest
  run replays; a new finish with fewer rings replaces it.
- Readability on the phone: count the beads on the result card of l006 and l009 without zooming.

## 22.19 Glossary terms (to be merged into `docs/glossary.md` by the developer, step 8)

| Term | Meaning |
|---|---|
| Chain (`MazeChain`) | The necklace shown at the finish: the rings the player used, as beads on a thread in the order of their first launch, in the shape of the route, from the start to the door. One bead per ring used, so its length is the score (design 22). |
| Chain bead | A bead on the chain: one thrown ring at its first launch (a counted launch). Always white, the same in every world. |
| Chain record (`chain`) | The best chain of a level in the profile: rings used, time in ticks and the link text of a finish; the fewest rings wins, the faster on a tie. Ranked on its own, independent of the best time. |
| Clasp | The buckle at the door end of the chain, in the world's lip tint, shown when rings used is at most par. Over par the thread ends in a plain knot. |
| Ghost map | The faint picture of a level's solid cells behind the chain on the result card and the share card. |
| Knot | A small knot on the chain where the route used a preset ring for the first time; not a bead and never counted. |
| Link | One element of the chain between start and door: a bead or a knot, with its cell and face (`b` or `k`, face letter, `x.y`). |
| Link text | The chain as text, for example `bu7.11-bu19.11-bu31.11`; stored in the chain record and in the share code. |
| Mini chain | The small picture of a level's best chain on its card in the level select. |
| Share card | The 1200 x 675 PNG of a finish: level, time, rings and par, the chain and the share code; shared with the system share sheet or downloaded. |
| Share code | Text form of a finish's chain: `wm1/<level>/<rings>/<par>/<ticks>/<links>`. Identifies a route; not a proof. |
| Stringing | The finish animation: the beads drop onto the thread one by one, the thread pulls taut, the clasp closes; at most 2.05 s, skippable, off with reduced motion. |
| Thread | The line of the chain, straight between links when taut; in the world's door frame colour (or a fallback with enough contrast). |

Changed entry: **Format** (profile format is now 2; design 22.9).

## 22.20 Coordination and open points

- **Card #040 (roof worlds, section 23).** The chain reads only `launch` events, ring faces, the spawn, the door and
  palette keys that every pack has; it adds no pack key (22.6.1, 22.6.2). New worlds get a chain look automatically, and
  K8 runs over every pack in `MazeSkins.PACKS`. If #040 adds a ring face on slopes, `FACE_LETTERS` and
  `face_point` need one more case and the link text one more letter (a link text with that letter would then need
  profile format 3). If #040 needs a profile format change of its own, the two changes should share one format number;
  the project lead orders the merges.
- **Glossary and design.md.** Not edited here (another architect works on section 23 at the same time); 22.17 step 8
  and 22.19.
- **For the owner:**
  - The clasp shows "at or under par"; under par has no extra mark on the chain (the text says it). A second mark
    (for example a double clasp) is possible.
  - Presets are knots; leaving them out would make some chains (l001, l005, l008) look shorter but less like the route.
  - The mini chains sit at the top right of the level cards; a separate gallery screen and sharing an old best chain
    are left for later.
  - Profile format 2: a browser still running a cached older build after the update shows the "newer profile" line and
    saves nothing until reloaded.
  - The share text includes the play address; it can be left out.

## 22.21 Deviations as built (card #038)

Result: 1630 game checks (`MIN_CHECKS` 1630, was 1193), kit tests 764, `tools/check_levels.gd`, `tools/check_search_par.sh`
and the web export green. K1 holds: `git diff 8e4574b -- sim/sim.gd sim/tuning.gd sim/level.gd sim/aim.gd sim/input.gd
sim/run_script.gd levels tests/solutions.json` is empty; `sim/` only gained `chain.gd` and the profile changes.

**K3 pinned chains.** All nine values equal the expected ones; no ring list of 5.4 or 17 was wrong. The open values
of the estimate: l001 `ku26.11-bu38.11` (as expected), l002 `ku1.11-br0.5-bu22.11` (the open row is 5), l003
`bu1.11-br0.4-bu24.11` (as expected). They are pinned in `tests/chain_tests.gd`.

**Tests.** Two suites instead of one: `tests/chain_tests.gd` (K2 to K5, K10, K11, K15) and `tests/chain_view_tests.gd`
(K6 to K9, K12 to K14); both in `SUITES`. Existing tests changed: P1, P2, P4 and the store and robustness checks that
asserted format 1 now assert 2 (`profile_tests`: create, "format 3 is newer", migrate; `profile_store_tests`: a format 3
file is the newer one; `robust_tests`: merge result; `screens_tester_tests`: repaired store files). Two tests that press
Enter right after a finish call `overlays.chain_view.finish_now()` first: `ui_tests` (Enter on the result opens the next
level) and `screens_tester_tests` (Enter on the last level's result).

**K14 with a real renderer.** The headless runner has the dummy renderer, where the share image stays empty (CH4), so the
render and the save are checked by `tools/check_chain_export.gd` (xvfb, opengl3: a 1200 x 675 PNG with the card on it,
saved with `save_local`, removed again) and a CI step after the shots. The headless suite checks the texts, the file
name, the share text, the script, the button states and `save_local` with fake bytes. The web path was smoke-tested
in headless Chrome (22.21.1).

**Shapes and view.** `layout` also returns `box`, `style` and `n` (drawn links); for EXPORT the view adds `canvas`, the
whole image, because the background covers the image while the chain sits in the chain box. `shapes` knows one
primitive kind beyond the decor format: `text` (the `+N` label). Names that differ from the sketch: `drawn_count`,
`bead_step`, `level_rect`, `FINAL_T` (99 s, the end state), `MazeChain.key` (public; `seen` holds integers, not
`[cell, face]` arrays). `colours(world, under)` takes a transparent `under` for the card and the export (contrast against
both background colours) and the button colour for MINI. Clasp: centred on the door point, rotated to the last segment;
the last segment ends at the frame's near side. The start tail points down and left; the `+N` label sits right of and
below the last bead. The `MINI` clasp is the filled circle with a 1 px outline, drawn at the door point.

**Skip.** The 0.3 s grace is measured in the view's own animation time (capped at 0.1 s per frame, like the animation),
not wall clock, so it stretches when the frame rate is very low and stays testable with fixed deltas. The first 0.3 s
eat key, mouse and touch presses; releases and key echoes never count. Shots (`--shot`) start in the final state unless
`--chain-t` is given.

**Result layout.** `MazeOverlays` gets `safe_override` (set by the game from `--safe`); the card height is floored
(712 x 400, not 400.5) and the view is centred vertically beside the column. The share feedback label is always in the
layout (empty text) instead of hidden: when it filled, the column grew and the buttons jumped under the pointer.
`MazeOverlays.card_size(avail)` is static and tested.

**`--chain-export`.** The window of the scenario is 1200 x 675 but the canvas is 1280 x 720 (stretch `canvas_items`), so
the export view is scaled by `canvas width / 1200` to fill the window; the screenshot is the share card. The share
image itself is rendered in its own `SubViewport` of exactly 1200 x 675. The rings line of the export says `no_rings`
for a zero-ring finish where the result screen shows `under_par` and `no_rings` on two lines.

**Level select.** The card's top and bottom padding of the scroll area went from 6 to 5 px: nine cards were 1 px too
tall for 1280 x 720 (a scrollbar showed on the select shots before this card), K12 needs them to fit. `--demo-profile`
is `MazeMain.fill_demo_profile` and only works with `--shot` (else a warning).

**Profile.** `MazeProfileStore.open` saves after a migration; `MazeMain` loads the levels before the profile and
passes the valid ones. `sanitize` returns `migrated`; `migrate` raises the format number of a format 1 copy.

**Fixtures of the shots.** `chain-zero` and `chain-export-zero` use the 0-ring route of l001 from the report of
`docs/test-reports/2026-11-21-levels-4-9.md` (B1, card #010): `R96 RJ4 R32 RJ4 R16 RJ4 R12 RJ8 R24 L4 R28 RJ4 R16 -4 L4
R8 RJ24 R48` (337 ticks, chain `ku26.11`). It only exists while that opening can be jumped: `tests/chain_view_tests.gd`
checks the fixture and says so in its message, so closing the opening fails that one check and the two scenarios
must then get another route (no other shipped level can be finished without a thrown ring). `chain-overpar` uses
`R2 T142 R70 U L64 -8 T142 R70 U R20 -24 T142 R6 RJ14 R80 R12 U -3 T142 R300` on l004: 4 rings, par 3, chain
`bu7.11-bu7.11-bu19.11-bu31.11` (the first face used twice: stacked beads), 513 ticks.

### 22.21.1 Web smoke test (K17, partly)

The release build cannot finish a level from the URL (no `solve` key, `tests/` is left out of the export), so the smoke
test ran on a scratch copy of the project with `?solve` and `tests/` enabled, exported for the web and served on
localhost, driven in headless Chrome over the DevTools protocol (software GL). Results: the card renders, the animation
ends, Share enables once the image is ready; with `navigator.canShare` and `navigator.share` present the page called
`share` once with `white-maze-l004-3-371.png` (image/png, 36 517 bytes), the title `White Maze` and the text of 22.11.3;
with both removed a download of the same file name started and the file is a 1200 x 675 PNG; no network request left
the page after the click in either case; the feedback line `Afbeelding gedownload` showed after the download. Not
covered: a real phone share sheet, iOS Safari, Android Chrome (left to the tester, K17).
