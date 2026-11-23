# White Maze - design section 23: roofs (card #040)

This file is section 23 of `docs/design.md`, kept as a separate file like sections 18 to 21. Decision records: ADR 0015
(slope tiles in the simulation, level format 2), ADR 0016 (rooftop worlds and the journey) and ADR 0017 (native search
tool). Source of the direction: the designer's note `docs/ideas/2026-11-22-daken.md` and its mockup (not in git), the
large variant.

It changes the simulation (3.6 to 3.10: collision, ground, cast), the level format (5.1, 5.2), assumption A2 (1.3), the
tools (5.5, 16.2), the skins (21.4, 21.13), the worlds per position (18.3), the level select (8.2) and the speed table
(20.6.2). Section 22 (designed in parallel) is not touched; nothing here depends on it.

In this section R-numbers (R1, R2, ...) are the roof criteria of 23.15. The run-script criteria of design 6.4 are
written as 6.4 R1 to 6.4 R4.

## 23.1 Owner decisions (2026-11-23)

1. The large variant: real sloped tiles. Steep (45 degrees) means sliding, gentle (1 in 2) means walking. A sloped face
   is never a ring face.
2. The roofs come after the ruins, in one journey: levels 1 to 9 stay the ruins (temple, jungle, cave), levels 10 to 21
   go over the roofs of Amsterdam, Andalusia, Fes and London, three per city. The existing worlds stay.
3. Extra palette rule: the hazard red against the block colour at least "2.0 contrast" (see 23.11.4: the literal
   luminance reading cannot be met; a colour-difference rule, Delta E at least 35, was confirmed).
4. Every city has a fixed time of day with a dark sky; white and the lip stay readable; skyline silhouettes must not
   look walkable.
5. Decided at question time (2026-11-23, the answers to 23.19): the speed is 90 % at level 10, rising to 96 % (23.12);
   rule C16 is the colour difference Delta E at least 35 (23.11.4); Amsterdam steep, Andalusia gentle, Fes flat, London
   flat with a steep slate roof in the finale (23.13.2); Fes plays with the sabat (ceiling rings under it); a chapter card
   for every world, the ruins included (23.14); facade stones with the sun sign sparingly, about one per level (23.14).
   Open: whether "steer only the speed" while sliding feels right; the owner decides after playing the lab (`?lab`),
   the slide speeds stay three tuning values until then.

## 23.2 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| RA1 | Slopes only ever stand on a full block and have air above them (no sloped ceilings, no overhangs). The level validation enforces it (23.4.3). | Ceiling slopes would need head collision against slopes and a second cast rule; out of scope. |
| RA2 | The player's feet are one point (the bottom centre `px, py`) for slopes; full tiles keep colliding with the whole box. | This is the chosen model (ADR 0015). |
| RA3 | Every shipped level of format 1 must play bit for bit as before. All new code paths are inert on maps without slopes (23.5.9, R1). | A changed trace would change the stored solutions, the par evidence and the best runs in profiles. |
| RA4 | The C++ port the tester made for #007 is not in the repository and may be gone; #011 is rebuilt from `sim/sim.gd` and this section (23.10.4). | None; the port is small (about 600 lines). |
| RA5 | GitHub's `ubuntu-latest` runner has `g++` with C++17 (true today). | The solver step needs a toolchain setup action. |
| RA6 | A roof level has at most 900 cells, so its baked texture stays under the 24 MB of 18.19 (25.6 KB per cell). | Larger levels need the staggered bake of 21.12.3 and a new memory budget. |
| RA7 | The other architect's section 22 (the chain) changes the view and the result screen only. | Phase A starts after #038 is merged; the files `ui/world_view.gd` and `ui/game.gd` overlap. |

## 23.3 Overview

| Area | Change | Phase |
|---|---|---|
| Level format | Format 2: six slope characters, field `sky`; format 1 unchanged | A |
| Simulation | Slope geometry (`MazeSlope`), ground kinds, sliding, landing on slopes, snapping, slope-aware cast | A |
| Lab levels | `levels/lab/` with three playable test levels, debug argument `--lab` and web key `lab` | A |
| View | Minimal slope drawing in every skin, Lilith's slide pose and feet on slopes, camera guard while sliding | A |
| Tools | Level check (format 2, cell budget, headroom), `search_par.gd`, solution tests, C++ solver `tools/solver/` (#011) | B |
| Skins | Pack format 2, roof styles, door shapes, `X` patterns, two spike shapes, four lip tints, motifs, skylines, rules C16 to C22, four city packs | C |
| Journey | Seven worlds by position, level select grouped per world, speed table for 10 to 21, levels l010 to l021 | D |
| Story | Chapter cards, ending card, optional stone marks | E |

New files:

| File | Class | Content |
|---|---|---|
| `sim/slope.gd` | `MazeSlope` | Slope geometry, integers only (23.4.2) |
| `levels/lab/index.json`, `lab01.json` to `lab03.json` | | Lab series (23.9.3) |
| `tests/slope_tests.gd` | | Phase A simulation tests |
| `tools/export_levels.gd`, `tools/trace_sim.gd` | | Plain-text level export and reference traces for the solver |
| `tools/solver/maze_solver.cpp`, `tools/solver/build.sh` | | Native solver (23.10.4) |
| `tools/check_solver.sh` | | Solver build, equivalence and calibration |

## 23.4 Slope tiles and level format 2

### 23.4.1 Kinds and notation

| Char | `MazeLevel.Cell` | Shape (local px, `y` down, cell 40 x 40) | Kind | Downhill | High side |
|---|---|---|---|---|---|
| `/` | `STEEP_R` (4) | triangle `(0,40) (40,0) (40,40)` | steep, rises to the right | left (-1) | right |
| `\` | `STEEP_L` (5) | triangle `(0,0) (40,40) (0,40)` | steep, rises to the left | right (+1) | left |
| `r` | `GENTLE_R_LO` (6) | `(0,40) (40,20) (40,40)` | gentle, lower half, rises to the right | left | none (its partner `R` covers it) |
| `R` | `GENTLE_R_HI` (7) | `(0,20) (40,0) (40,40) (0,40)` | gentle, upper half, rises to the right | left | right |
| `L` | `GENTLE_L_HI` (8) | `(0,0) (40,20) (40,40) (0,40)` | gentle, upper half, rises to the left | right | left |
| `l` | `GENTLE_L_LO` (9) | `(0,20) (40,40) (0,40)` | gentle, lower half, rises to the left | right | none |

- Reading aid: `r`/`R` is a roof that rises to the right, `L`/`l` one that rises to the left; lower case is the lower
  half. A gentle slope is always a pair: `rR` rises one tile over two, `Ll` falls one tile over two. A gentle ridge is
  `rRLl`, a steep ridge `/\`.
- In the JSON file a backslash is written `\\` (JSON escaping), so a row with `\` looks one column longer in the editor.
  The level check counts lengths after parsing. The design shows rows unescaped.
- Enum values are appended after `SPIKE` (3), so the bytes of format-1 levels do not change. `MazeLevel.CHARS :=
  ".#X^/\\rRLl"` (index = `Cell`; `S` and `F` are `EMPTY` with their own fields, as today).

### 23.4.2 Geometry (`MazeSlope`, `sim/slope.gd`)

```gdscript
class_name MazeSlope extends RefCounted
## Geometry of slope tiles in units; integers only. Used by the simulation, the cast, the tools and the view.
static func is_slope(kind: int) -> bool        # kinds 4..9
static func steep(kind: int) -> bool           # STEEP_R, STEEP_L
static func downhill(kind: int) -> int         # -1 for / r R (the surface falls to the left), 1 for \ L l
static func high_side(kind: int) -> int        # Face.RIGHT for / and R, Face.LEFT for \ and L, -1 for r and l
static func surface(kind: int, cy: int, lx: int) -> int   # y of the surface at local x lx (0..TILE) in row cy
static func inside(kind: int, cx: int, cy: int, p: Vector2i) -> bool  # p.y >= surface(kind, cy, p.x - cx * TILE)
static func polygon(kind: int) -> Array[Vector2i]          # the shape of 23.4.1 in local px, clockwise (view only)
```

`surface`, with `b = cy * TILE`, `T = TILE` (40000), `lx` in `0..T`, `/` is integer division (always on a value
`>= 0`, so it floors):

| Kind | Surface |
|---|---|
| `/` | `b + T - lx` |
| `\` | `b + lx` |
| `r` | `b + T - lx / 2` |
| `R` | `b + T / 2 - lx / 2` |
| `L` | `b + lx / 2` |
| `l` | `b + T / 2 + lx / 2` |

The surface of a tile lies inside `[b, b + T]`. At every allowed joint (23.4.3) the two surfaces meet at the same `y`
(for example `r` at `lx = T` and `R` at `lx = 0` both give `b + 20000`).

### 23.4.3 Format 2

A level file with `"format": 2` may contain the six slope characters and the optional field `sky`. Everything else is as
in 5.1. Format 1 files load exactly as before; the nine shipped levels stay format 1. `levels/index.json` keeps its
`format` 1.

| Field | Rule |
|---|---|
| `format` | 1 or 2. Any other value: `format must be 1 or 2`. |
| `rows` | Format 2 adds the characters `/ \ r R L l`. In a format-1 file: `slope '<c>' at (x, y) needs format 2`. |
| `sky` | Optional boolean, format 2 only (`sky needs format 2`, `sky must be true or false`). Default false. Effect in 23.5.6: a bead that leaves the grid at the top is not stopped. The player is still stopped by the top edge (as today). |

Validation rules for slope cells (one error per problem, coordinates of the slope cell):

| # | Rule | Error text |
|---|---|---|
| V1 | The cell directly below is `#` or `X` (inside the grid). | `slope at (x, y) needs # or X below` |
| V2 | The cell directly above is `.` or `F` (empty, not `S`, not a spike, not solid, not a slope; above the grid counts as allowed). | `slope at (x, y) needs empty space above` |
| V3 | Gentle halves pair up: `r` has `R` to its right, `R` has `r` to its left, `L` has `l` to its right, `l` has `L` to its left. | `gentle slope 'r' at (x, y) needs 'R' to its right` (and the three mirrored texts) |
| V4 | The low side is open: the cell on the downhill side in the same row (left of `/` and `r`, right of `\` and `l`) is not solid, not a slope and not outside the grid. This forbids valleys (`\/`), cliffs inside a slope run (`//`) and pockets against a wall. | `slope at (x, y) has a blocked low side` |

The high side may be air (a gable end), a full block (the floor continues at the top) or the high side of another slope
(a ridge: `/\`, `RL`, `/L`, `R\`). `S` keeps its rule "a solid cell below" (`solid()` is false for slopes), so `S` can
never stand on a slope. Preset rings: 5.1 plus "the face is exposed" now also fails when the cell in front is a slope.

```gdscript
# MazeLevel additions
enum Cell { EMPTY, SOLID, NO_RING, SPIKE, STEEP_R, STEEP_L, GENTLE_R_LO, GENTLE_R_HI, GENTLE_L_HI, GENTLE_L_LO }
const CHARS := ".#X^/\\rRLl"
var format := 1
var sky := false
var slope_count := 0
func slope(x: int, y: int) -> bool      # MazeSlope.is_slope(cell(x, y))
func covered(x: int, y: int) -> bool    # solid(x, y) or slope(x, y): a face with this cell in front is not exposed
# solid() is unchanged: only # and X (and outside left, right, top)
# render() writes CHARS[cell], S and F as today
```

### 23.4.4 Faces next to slopes

A face whose front cell is a slope is covered: never a ring face, never a lip. That is the top face of the block under
every slope, and the side face of a block next to a slope's high side. `MazeArt.lip_face` and the cast (23.5.6) use
`covered()` instead of `solid()` for the front cell. On format-1 levels this is the same function (no slopes).

## 23.5 Simulation with slopes

### 23.5.1 State and tuning

```gdscript
# MazeSim additions
enum Ground { NONE, FLAT, GENTLE, STEEP }
var ground := Ground.NONE       # what the player stands on after the last step; grounded == (ground != NONE)
func sliding() -> bool          # ground == Ground.STEEP
func ground_kind() -> int       # the slope Cell under the centre when ground is GENTLE or STEEP, else -1 (view)
```

New tuning (3.2 formulas; readable and sim value as for every constant, checked by `tuning_tests.gd`):

| Name | Readable | Sim value | Purpose |
|---|---|---|---|
| `SLIDE_SPEED` | 360 px/s | 6000 | Sliding speed on a steep slope without input. |
| `SLIDE_FAST` | 480 px/s | 8000 | Sliding speed with input downhill. |
| `SLIDE_SLOW` | 240 px/s | 4000 | Sliding speed with input uphill (braking; you never stop or climb). |
| `SLIDE_ACCEL` | 1800 px/s² | 500 | Rate at which the horizontal speed moves towards the sliding target. |
| `SLOPE_STEP` | 16 px | 16000 | On slope ground, the bottom band of the box that may overlap a full block (23.5.4). |
| `SLOPE_SNAP` | 16 px | 16000 | Snapping range below the feet, plus `abs(vx)` (23.5.4 step 5). |

### 23.5.2 Ground

The slope under the centre: column `cx = fdiv(px, T)`; the slope cell in that column in row `fdiv(py - 1, T)` or
`fdiv(py, T)` (two rows, because `\` and `L` have their surface at the very top of their cell at `lx = 0`). There is at
most one: slopes are never vertically adjacent (V1). `s = MazeSlope.surface(kind, cy, px - cx * T)`.

`_compute_ground()` after every move and at spawn and respawn:

1. When a slope cell is under the centre and `py == s`: `ground = STEEP` or `GENTLE` by its kind.
2. Else when `py` is a multiple of `T` and a full solid cell (`solid()`) lies in row `py / T` in the box columns
   (`fdiv(px - HW, T)` to `fdiv(px + HW - 1, T)`): `ground = FLAT`. (Today's `_is_grounded`, plus the alignment test; on
   format-1 levels a grounded player is always aligned, so the result is the same.)
3. Else `NONE`. `grounded = ground != NONE`.

A player standing on the corner of the floor at the top of a slope, with the centre over the slope and above its
surface, stands on the floor (`FLAT`) and does not slide.

### 23.5.3 Horizontal speed (step 8)

After the lock branch (unchanged) and before the ground branch:

```
if grounded and ground == STEEP:
    d = MazeSlope.downhill(kind under the centre)
    target = d * SLIDE_SPEED
    if move == d:  target = d * SLIDE_FAST
    if move == -d: target = d * SLIDE_SLOW
    vx = approach(vx, target, SLIDE_ACCEL)
    if move != 0: facing = move
    return
```

`GENTLE` uses the ground branch of 3.8 step 8 unchanged: walking on a gentle slope is walking on a floor (the speed is
horizontal; along the surface it is 12 % more, not noticeable). A player landing on a steep slope with uphill speed
skids up, stops and slides down within about a quarter of a second.

### 23.5.4 Moving (step 11)

`_move()` becomes, in this order (`start` = `ground` and `was_grounded` = `grounded` as left by steps 1 to 10; a jump
in step 9 has already set `grounded = false`):

1. `allow = SLOPE_STEP` when `start` is `GENTLE` or `STEEP`, else 0.
2. **X.** As 3.6 X, but the cells checked in each newly entered column are the rows overlapped by
   `[py - PLAYER_H, py - allow)`, and a column also blocks when one of those rows holds a slope whose high side faces
   the player: moving right is blocked by `\` and `L`, moving left by `/` and `R` (their full-height vertical side).
   Slopes never block otherwise; the box may overlap a slope's triangle.
3. **Lift.** Let `c` be the cell of the point `(px, py - 1)`.
   - When `c` is a slope and `py > s` (the centre is below its surface): `py = s`.
   - Else when `allow > 0`, `c` is solid and `py - c.y * T <= allow` (stepping from a slope onto the floor at its top):
     `py = c.y * T`.
   - When `py` changed here and the box rows `[py - PLAYER_H, py - allow)` overlap a full solid cell: undo the X move
     and the lift (`px`, `py` back to their values before step 2) and `vx = 0`.
4. **Y.** As 3.6 Y, with one addition for falling (`vy > 0`): besides the first solid row under the box, also the slope
   under the centre counts when its surface `s` satisfies `py <= s <= py + vy`; the player lands on the nearer of the
   two (`py = min`), `vy = 0`. Rising is unchanged (slopes have no exposed underside).
5. **Snap.** `_compute_ground()`. When `was_grounded`, `vy >= 0`, `ground == NONE`, and below the feet within
   `SLOPE_SNAP + abs(vx)` there is a support (the first solid row top under the box columns, or the surface of the slope
   under the centre, whichever is nearer), and (`start` is `GENTLE` or `STEEP`, or that support is a slope surface):
   `py` = that support, `vy = 0`, `_compute_ground()` again. No `land` event. This keeps the player on the roof when
   walking or sliding downhill and when stepping from the top floor onto a slope.
6. **Landing.** As today: `landed` from step 4 (or `grounded and vy > 0`); `jumping = launched = false`; event `land`
   when not `was_grounded`. New: when `landed`, not `was_grounded` and `ground == STEEP`, the fall turns into a slide:
   `vx = (vx + d * vy_before) / 2` with `d` the downhill sign and `vy_before` the vertical speed before step 4. `/` is
   GDScript integer division on a possibly negative value (truncation towards zero; the C++ port uses the same). Falling
   straight onto `/` at 900 px/s gives `vx = -7500` (450 px/s down the roof).
7. **Slide event.** When `ground == STEEP` and `start != STEEP`: event `slide` (`dir` = `d`), and `facing = d` unless
   `move != 0` this tick.
8. The rest of 3.8 step 11 as today (`jumping` and `launched` flags by `vy`).

Leaving a slope over air (the eave) is like walking off a ledge: no snap support within range, `ground = NONE`, `vy` is
what gravity gave in this tick, coyote time applies. The player leaves horizontally, which gives a little more time to
jump than following the roof line would.

Why the bottom band (`SLOPE_STEP`): walking up a slope towards the floor at its top (or over a ridge), the box's front
corner reaches the next column while the feet are still up to 15 px (steep) or 7.5 px (gentle) below the top. Without
the band that corner would hit the floor as a wall. With it, the corner may sink into the floor or the other slope until
the centre crosses, and then the lift of step 3 puts the feet on the floor; at the border the surfaces meet, so that
lift is at most `abs(vx)`.

A known small effect: a player who lands on the corner of the floor at the top of a steep roof (centre over the roof)
stands there; walking towards the roof, the box leaves the floor when the centre is about 15 px from the edge, and the
snap moves the feet down to the roof surface by up to 16 px in one tick. Render interpolation shows it as a quick step
down. It happens only after a landing on that exact corner.

### 23.5.5 Jumping, coyote, buffer, rings, hazards

- Jump (step 9): unchanged. A jump from any ground is straight up (`vy = -JUMP_SPEED`), `vx` unchanged, so a jump from a
  slide carries the slide speed.
- Coyote and buffer: unchanged; `grounded` includes slope ground.
- Ring zones and launches (3.7, step 12): unchanged. A sliding player who reaches a floor ring on a gutter is launched
  straight up with the slide speed kept, a long diagonal leap.
- Hazards: unchanged. A spike next to the low end of a slope (allowed by V4) kills a sliding player.
- Corner correction: unchanged.

### 23.5.6 Cast (`MazeSim.cast`)

3.10 step 3 tests every sample point `p`: the hit is the first sample whose cell is solid, **or** is a slope with
`MazeSlope.inside(kind, cx, cy, p)`. A slope hit: `cell` = the slope cell, `face` = `UP`, `dist` as usual, `valid =
false`, reason **`"slope"`** (after `dead` and `no_beads`, as for the other reasons). Step 6 uses `covered()` for the
cell in front of the face (reason `no_ring`).

When the level has `sky == true`, a sample above the grid (`cy < 0`, `0 <= cx < width`) is not a hit; the march goes on,
and a ray that leaves through the top ends with reason `"none"` (no cross in the sky). The player's collision still
treats the top edge as solid.

### 23.5.7 Events and snapshot

- New event `slide` (`dir`: -1 or 1) when the player starts sliding (step 7). The view and a later sound may use it.
- `throw_invalid` may carry `reason: "slope"`.
- `snapshot()` adds `ground` after `grounded`. No stored snapshot exists; determinism tests compare two runs.

### 23.5.8 Invariants (tested, R15)

- The centre point is never strictly below the surface of a slope cell it lies in.
- The box overlaps a full solid cell only in its bottom `SLOPE_STEP` band, and only while the centre is over a slope
  cell or the player is rising after leaving slope ground.
- `grounded == (ground != NONE)`; `ground == FLAT` implies `py % T == 0`.
- On `GENTLE` ground with no input and `vx == 0`, the position does not change from tick to tick.
- On format-1 levels the trace of every stored solution is identical to the trace before this change (R1).

### 23.5.9 Inertness on format 1

On a map without slopes: `allow` is always 0 (`start` is never a slope kind), the high-side test never finds a slope,
step 3 never lifts, step 4 never finds a slope, step 5 never snaps (its condition needs a slope), step 6 never projects,
`ground` is `FLAT` exactly when the old `grounded` was true, and the cast never meets a slope (and `sky` is false). The
only visible difference is the extra `ground` field in `snapshot()`.

### 23.5.10 Metrics on slopes (design aids, measured by R12 and recorded in 23.21 as built)

| Situation | Expected |
|---|---|
| Jump height from a slope | As from a floor (3.1 to 3.6 tiles), measured from the take-off feet. |
| Running jump from a gentle slope | As from a floor: a 4-tile gap at equal height. |
| Jump from a slide without input (360 px/s) | About 5 tiles at equal height. |
| Jump from a slide holding downhill (480 px/s) | About 6 to 7 tiles at equal height. |
| Time from landing on a steep roof (from rest) to 360 px/s | At most 14 ticks. |
| Walking off an eave at 480 px/s, falling one tile | About 1.8 tiles forward. |

Rule for level makers: a steep roof is a slide you cannot climb; to get up one you need a ring (a floor ring on the
gutter or on the floor before it, a wall ring on a gable) or a higher start. A gentle roof is a floor.

## 23.6 Beads and rings near slopes

- A sloped face is never a ring face: a throw whose ray first meets a slope is invalid with reason `slope`; the aim line
  is drawn dimmed with a cross, as for every invalid throw (4.5). It costs nothing.
- A bead never lands on a slope: beads fly in a straight line and only ever become a ring on a valid face, so "a bead
  that falls on a roof" does not exist. (A view-only "glance" effect for invalid throws at a roof is an open idea, not
  in scope.)
- The faces a slope covers (the top of the block under it, the side of a block next to its high side) are not ring
  faces (`no_ring`), have no lip, and a preset ring on them is a level error.
- Faces next to a slope that are still exposed keep their rules: the gutter at the bottom of a roof (a `#` whose top is
  at the low end's height), the floor at the top of a roof, a wall above the high end of a slope.
- Bead back, rings used and par are unchanged.

## 23.7 Camera and slow motion

- Camera (19.6): the frame dictionary gets `slide` (`sim.sliding()`). Step 3 becomes `falling = (not f.grounded and
  f.vel.y > 0 and feet_y > anchor_y + FALL_MIN) or f.slide`, so the bottom guard grows to `GUARD_BOTTOM_FALL` while
  sliding and at least 3.6 tiles below the feet are visible when racing towards an eave. The ground anchor follows the
  feet on every kind of ground, so walking a gentle roof moves the view smoothly at `Y_RATE`. Nothing else changes; on
  format-1 levels `slide` is never true.
- Slow motion (4.4) and the level speed (20.6) are time scales; sliding is simulated per tick like everything else.
  Aiming while sliding is allowed and the slide goes on at a quarter of the speed. Keyboard aim follows `facing`, which
  points downhill when the slide starts and follows the input after that (23.5.4 step 7).

## 23.8 Lilith: slide pose and feet on slopes

```gdscript
# MazeLilith additions
enum Body { IDLE, RUN, JUMP, LAUNCH, FALL, DEAD, SLIDE }   # SLIDE appended, other values unchanged
static func body_pose(alive: bool, grounded: bool, vx: int, vy: int, launched: bool, sliding: bool = false) -> int
	# not alive -> DEAD; sliding -> SLIDE; otherwise as 18.6.2
# shapes()/rig(): p gets "grade": float = slope dy/dx in Lilith's local frame (after the facing mirror), 0 off slopes
```

- `grade` = `MazeSlope.downhill(kind) * (1.0 if steep else 0.5) * facing` for the slope under the centre when `ground`
  is `GENTLE` or `STEEP`, else 0. The world view computes it from `sim.ground_kind()`.
- Feet on slopes (every grounded pose): after the rig is built, each foot gets `y += clampf(grade * foot.x, -8, 8)`, so
  both boots stand on the roof line. The rest of the figure stays upright.
- `SLIDE` rig (start values, local frame, facing downhill): `drop` 4 (crouched), `near_foot (7, -0.5)` (leading leg
  stretched downhill), `far_foot (-6, -3)` (trailing leg bent), `hand_near (10, -15)`, `hand_far (-11, -19)` (arms out for
  balance), `tilt` -0.25 rad (leaning back, uphill), `hair_up` 0.5; arm mode `REST` unless aiming or throwing. Facing
  uphill (braking) mirrors the same pose, which reads as sliding backwards.
- Bounds (A2, F8): every pose keeps `x in [-15, 15]`; `y` may go down to +9 for the downhill foot of `SLIDE` and to +4 for
  the feet of grounded poses on `GENTLE`; all other bounds as 18.6.1.
- The pose blend (20.3.3) covers every switch into and out of `SLIDE` (6 ticks); the tails follow the look velocity.

## 23.9 Minimal slope look and the lab (phase A)

### 23.9.1 Slope drawing in every skin

`MazeTileShapes.slope(level, skin, cell)` (new) gives the primitives of a slope cell, drawn in step 2 of 21.12.1 after the
stones of the chunk:

1. The polygon of `MazeSlope.polygon(kind)` in the roof contour colour (`roof.darkened(CONTOUR_DARKEN)`).
2. The polygon inset by `CONTOUR_W` on the sides towards air (the surface and an exposed high side) and by `SEAM_W` on
   the sides against a block (the bottom, a high side against a block), in `roof`.
3. The roof style's courses and details (phase A: style `plain`, courses only: lines parallel to the surface every 7 px in
   `roof_lo`, 1.6 px wide, clipped to the inner polygon).

Rules (engine-owned, every style): never outside the collision polygon; the surface edge is straight (no crumbly
offset: it is a floor); no trim, no lip colour; the block below and beside it treats the slope side as a seam
(`MazeSkin.Side.SLOPE`, insets and contour as `SEAM`, `rim_face` false). Format-1 packs resolve
`roof = block.darkened(0.25)`, `roof_hi = block`, `roof_lo = block.darkened(0.45)` and style `plain` (23.11.1).

### 23.9.2 Decor

`MazeDecor.plan` treats slope cells as solid in every neighbour rule (`covered()`), so nothing floats over a roof, and
never places an item in a slope cell (D1 already requires `EMPTY`).

### 23.9.3 Lab series

- `levels/lab/index.json` (`{"format": 1, "levels": ["lab01", "lab02", "lab03"]}`) and three format-2 levels:
  `lab01` steep roofs (slide, eave jump, gutter ring, a steep ridge), `lab02` gentle roofs (walk up and down, a gentle
  ridge, a slope into a wall, tiers), `lab03` mixed (a steep roof running into a gentle one, spikes at a low end, a
  catch ring thrown while sliding). Built from the fixtures of 23.9.4, enlarged; each with a solution in
  `tests/solutions.json` and a par.
- Debug argument `--lab` and web key `lab` (added to `QUERY_KEYS`; `lab=0` switches it off): the level select and
  `--level` use `res://levels/lab/` instead of `res://levels/`; the profile is opened in memory only
  (`MazeProfileStore.open_memory`, as `--shot`), so lab play never writes statistics. Worlds follow the lab position
  (temple until phase C; `--world=` overrides).
- `tools/check_levels.gd --dir=res://levels/lab` and CI check the lab too.

### 23.9.4 Test fixtures (rows for `tests/slope_tests.gd`)

Fixture S (steep ridge, 16 x 10):

```
            0-7      8-15
row  0      ######## ########
row  1      #....... .......#
row  2      #....... .......#
row  3      #....... .......#
row  4      #....... /\.....#
row  5      #....../ ##\....#
row  6      #...../# ###\...#
row  7      #.S../## ####\..#
row  8      ######## ########
row  9      ######## ########
```

Fixture G (gentle tiers, a slope into a wall, a gentle ridge, 24 x 8):

```
            0-7      8-15     16-23
row  0      ######## ######## ########
row  1      #....... ........ .......#
row  2      #....... ........ .......#
row  3      #....... ..#..... .......#
row  4      #....... rR#..... rRLl...#
row  5      #.S...rR ###...rR ####Ll.#
row  6      ######## ######## ########
row  7      ######## ######## ########
```

Fixture E (gutter, steep roof, eave over the street, 20 x 10; the bottom row is open, so the street is a fall):

```
            0-7      8-15     16-19
row  0      ######## ######## ####
row  1      #....... ........ ...#
row  2      #....... ........ ...#
row  3      #....... ..../\.. ...#
row  4      #....... .../##\. ...#
row  5      #.S..... ../####\ ...#
row  6      ######.. .####### ...#
row  7      ######.. .####### ...#
row  8      ######.. .####### ...#
row  9      ........ ........ ....
```

Fixture T (top joints: a floor running into a steep slope on the left and into a gentle pair on the right, 16 x 8):

```
            0-7      8-15
row  0      ######## ########
row  1      #....... .......#
row  2      #....... .......#
row  3      #....... .......#
row  4      #....... S......#
row  5      #..../## ####Ll.#
row  6      ######## ########
row  7      ######## ########
```

All four pass V1 to V4. In E the gutter is `(9, 6)`, the eave is the low end of `\` at `(15, 5)` over the street
columns 16 to 18. Tests may put the player anywhere by setting `px`, `py` (and `ground` with `_compute_ground`) before
the first step, for example to drop it onto a roof.

## 23.10 Tools

### 23.10.1 Level check (`tools/check_levels.gd`)

- Format-2 levels print `ok <id> <w>x<h> beads <b> par <p> slopes <n>`; format-1 lines are unchanged.
- New error: `error <id>: <w>x<h> is <n> cells, more than 900` (bake budget, RA6; every shipped level is at most 768).
- New warning (does not fail): for a level with `sky`, every lip `UP` face whose column has open air up to the top edge
  with fewer than 8 free rows prints `warn <id>: floor face (x, y) has <n> rows of sky` (a floor ring lifts the head
  about 7.1 tiles; less headroom means the invisible top edge can be hit).
- CI and the conventions run it for `levels/` and `levels/lab/`.

### 23.10.2 `tools/search_par.gd`

- `_clone` copies `ground`; `_key` adds `ground`; `_faces` skips faces whose front cell is `covered()`; `_try` builds its
  temporary level with the level's `format` and `sky` (rows from `render()`, which now writes slope characters).
- `tools/check_search_par.sh` keeps l001 in CI and adds one lab case (the lab01 ring set) to `--full`.
- It stays the reference implementation in GDScript; the fast search is the solver of 23.10.4.

### 23.10.3 Solution tests and robustness

- `tests/solution_tests.gd` covers the index and the lab index.
- The robustness test of section 17 (take back every thrown ring right after its first launch) runs for every new level.
- `tests/level_tests.gd`: the L2 cases get the format-2 errors (23.4.3), at least ten new minimal bad levels.

### 23.10.4 Native solver (card #011, ADR 0017)

A C++17 port of the movement part of `MazeSim` for fast par evidence, kept equal to the GDScript simulation by a trace
test in CI.

| File | Content |
|---|---|
| `tools/export_levels.gd` | `godot --headless -s res://tools/export_levels.gd -- --out=build/solver/levels.txt [--dir=...]`: writes every level of the index (and of `--dir`) in a plain text form. |
| `tools/trace_sim.gd` | `-- --levels=... --seeds=12 --ticks=900 --out=build/solver/`: writes `cases.txt` (per case: level id and a hold-only run script from `WhiteRng`, half of them with three random extra presets on exposed faces) and `trace_gd.txt` (per tick: `case tick px py vx vy ground grounded dead_ticks rings_used`). |
| `tools/solver/maze_solver.cpp` | One file, no dependencies, `int64_t` everywhere. Parts: level (grid, presets, sky), sim (3.8 steps 1, 2 and 6 to 14 including slopes; no throws, no undo, no cast), run-script parser for hold tokens (`T` and `U` give an error), `trace` mode, `search` mode. |
| `tools/solver/build.sh` | `g++ -std=c++17 -O2 -Wall -Wextra -o build/solver/maze_solver tools/solver/maze_solver.cpp`. |
| `tools/check_solver.sh` | Build; export; trace both and `diff`; calibration searches; exit 1 on any difference or failed calibration. CI runs it after the level check. |

Plain level text (one block per level):

```
level <id> <width> <height> <beads> <par> <sky 0|1>
row <cells as CHARS, S and F included>      (height lines)
ring <x> <y> <face 0..3>                     (one line per preset ring)
end
```

Solver command line, the same as `search_par.gd` so `check_search_par.sh` can call either:

```
maze_solver trace <levels.txt> <cases.txt>                       # prints the trace lines of trace_gd.txt
maze_solver search <levels.txt> --level=<id> [--rings="x,y,face;..."] [--k=4] [--nodes=N] [--weight=W]
maze_solver search <levels.txt> --level=<id> --subset=N [--faces=x0,y0,x1,y1] [--anchor=...] [--part=i/n]
```

- `search` is the relaxation of 16.2 and 17.2: extra rings are presets from tick 0, macro steps of `k` ticks over move x
  jump, A* with the heuristic and the quantised key of `search_par.gd` (with `ground`), weight 0 is breadth first. Output
  lines as `search_par.gd` (`extra rings ...: FINISH script <script>`, `sets with a finish: <n>`), and at the end
  `nodes <n> ms <t>`.
- Faces: exposed faces of `#` cells whose front cell is not `covered()` and not a spike; `DOWN` faces are included.
- Rule (conventions): every change of `sim/sim.gd` or `sim/slope.gd` that changes movement also changes
  `maze_solver.cpp` in the same commit; `check_solver.sh` fails otherwise.

## 23.11 Rooftop skins

### 23.11.1 Pack format 2

A format-2 pack is a format-1 pack (21.4.2) plus these keys; format-1 packs stay valid and resolve the new keys from
their own values, so the ruins look exactly as before.

| Key | Format 2 rule | Format 1 resolves to |
|---|---|---|
| `palette.roof`, `roof_hi`, `roof_lo` | `#RRGGBB` | `block.darkened(0.25)`, `block`, `block.darkened(0.45)` |
| `palette.cap`, `cap_hi`, `cap_lo` | `#RRGGBB` (used only with `cap: true`) | `block`, `block_hi`, `block_lo` |
| `palette.pattern_a`, `pattern_b` | `#RRGGBB` (used by the `X` pattern) | `noring_hi`, `noring_lo` |
| `palette.back_far` | `#RRGGBB` (far skyline layer) | `back_decor` |
| `roof` | one of `ROOF_STYLES`: `plain`, `glazed`, `pantile`, `plaster`, `slate` | `plain` |
| `door` | one of `DOOR_SHAPES`: `post`, `fanlight`, `arch`, `horseshoe`, `hatch` | `post` (today's door) |
| `xpattern` | one of `X_PATTERNS`: `plain`, `window`, `azulejo`, `zellige`, `lead` | `plain` |
| `cap` | boolean: the top stone row of a mass (cells whose `UP` side is `AIR`) uses the cap colours | `false` |
| `skyline` | one of `SKYLINES`: `none`, `gables`, `village`, `medina`, `towers` | `none` |
| `back` | adds `sky` to `BACK_PATTERNS` (gradient only, no lines) | unchanged |
| `spikes` | adds `needle` and `shard` to `SPIKE_SHAPES` | unchanged |
| `lip` | adds the tints of 23.11.2 | unchanged |
| `motifs[].kind` | adds `putlog` and `soot` to `MOTIFS` | unchanged |

`PALETTE_KEYS` for format 2 are the 19 keys of 21.4.2 plus the 9 above (28). Engine-owned keys (21.4.2) stay forbidden.

### 23.11.2 Engine additions

| Set | New entries | Rule kept by the engine |
|---|---|---|
| `LIP_TINTS` | `stone` `#EAD6A2 #F2E0B0 #BFA672`, `lime` `#F4DEB0 #F8E6BE #D0B27C`, `plaster` `#F0D9A6 #F5E2B6 #C7AC76`, `cornice` `#E6D5A4 #EEDFB2 #BDAB7A` (lip, lip_hi, lip_lo) | C15 for every tint (not near white, not the hazard hue) |
| `SPIKE_SHAPES` | `needle` (three thin needles per tile, pigeon spikes), `shard` (four irregular glass shards) | Same colours, same hitbox; the outline stays inside the envelope of today's three shapes (lower half of the cell, 4 px inset), every shape points up |
| `DOOR_SHAPES` | `fanlight` (posts, lintel and a half-round light above the opening), `arch` (round top), `horseshoe` (horseshoe arch), `hatch` (posts with a triangular pediment) | Inside the `F` cell; the lit opening touches the cell bottom and has at least 85 % of today's area (30 x 34 px); frame colour derived, contour along the inner edge, `DOOR_LIGHT` |
| `X_PATTERNS` | `window` (a 2 px muntin cross per cell in `noring_edge`), `azulejo` (a ring r 9, 2 px, in `pattern_a` and four dots in `pattern_b` per cell), `zellige` (an eight-point star r 8 in `pattern_a`, centre dot `pattern_b`), `lead` (diagonal lattice, 1.5 px, `pattern_b`, every 10 px) | Drawn per `X` cell, at least 6 px inside the slab outline, after the fill and before the sheen; the slab outline, edge and top line unchanged |
| `ROOF_STYLES` | `glazed` (courses plus a `roof_hi` sheen line 7 px inside the surface, 2.2 px, alpha 0.95, and two short sheen strokes), `pantile` (courses plus rows of half-round tiles, `roof_hi` alpha 0.55), `plaster` (no courses, a few `roof_lo` specks), `slate` (courses plus short vertical joints every 9 px in `roof_lo`) | 23.9.1 for every style |
| `MOTIFS` | `putlog` (a row of three dark dots r 1.5 in `motif`, scaffold holes), `soot` (a band 6 px high along the stone's top edge in `motif` at alpha 0.5, never on a lip-face stone) | The motif area of 21.6.3 |
| `BACK_PATTERNS` | `sky` (gradient only) | |
| `SKYLINES` | see 23.11.5 | |

### 23.11.3 Cap row

With `cap: true`, a `#` cell whose `UP` side is `AIR` draws its stone fill with `cap`, `cap_hi`, `cap_lo` instead of
`block`, `block_hi`, `block_lo` (a stone of two cells takes the cap when its top row qualifies). A cell with a spike
above has `UP` side `SPIKE`, so the red never stands on the cap. The lip trim is drawn over the cap as on any stone.

### 23.11.4 Palette rules C16 to C22

C1 to C15 apply to every pack, format 1 and 2. New (ids continue in `MazeSkin.check_palette`):

| Id | Rule |
|---|---|
| C16 | The hazard red differs clearly from what pins stand on: CIELAB colour difference (Delta E 1976, D65) between `HAZARD` and each of `block`, `cap`, `roof` is at least 35. |
| C17 | The sky is dark: `luminance(back_top) <= 0.05` and `luminance(back_bottom) <= 0.05`. |
| C18 | `contrast(lip, cap) >= 1.8` and `luminance(cap_lo) < luminance(cap) < luminance(cap_hi)`. |
| C19 | Roofs: `luminance(roof_lo) < luminance(roof) < luminance(roof_hi)`; `contrast(roof, back_top) >= 1.5` and the same against `back_bottom`; `contrast(lip, roof_hi) >= 1.8` (a glazed sheen never reads as a lip). |
| C20 | `X` patterns stay quiet and are never lip-like: `contrast(lip, c) >= 1.8` and `luminance(lip) > luminance(c)` for `c` in `pattern_a`, `pattern_b`; `contrast(pattern_a, noring) <= 2.5`. |
| C21 | Skyline: `back_far` has `contrast <= 1.6` against both back colours (as C10). |
| C22 | C3, C11 and C12 also cover `roof`, `roof_hi`, `roof_lo`, `cap`, `cap_hi`, `cap_lo`, `pattern_a`, `pattern_b`, `back_far`. |

**Why C16 is not a luminance contrast of 2.0.** Pins stand on blocks; a block must keep C1 (lip against block at least
1.8, with a lip that may not be near white, so the block's luminance is at most about 0.40) and C5 (the derived contour
against the block at least 3.0, so the block's luminance is at least about 0.11). The hazard red has luminance 0.19; a
WCAG contrast of 2.0 needs a block below 0.07 or above 0.43. No block satisfies all three, and the three ruin packs
measure 1.25 to 1.7 today. What the designer warned about is hue: terracotta, red brick and Marrakech pink look like the
pins. A colour difference catches that, and keeps the luminance freedom the lip needs. Values: temple about 48,
Amsterdam brick about 48, Fes about 46, the Andalusian terracotta `#B9824E` about 38, a red brick `#A0402F` about 14
(rejected), a Marrakech pink `#C87A6E` about 32 (rejected). The dark spike outline (`HAZARD_LINE`, 21.10.1) separates a
pin from a light block in greyscale. The owner confirmed this reading (23.1, item 5).

`MazeArt` gets `static func lab(c: Color) -> Vector3` (sRGB to CIELAB, D65) and `static func delta_e(a: Color, b: Color)
-> float` (Euclidean distance in Lab). Tested against three reference pairs within 0.5.

### 23.11.5 Skylines (back layer)

`MazeDecor.skyline(level, world) -> Array[Dictionary]` (items like the plan, layer `back`), drawn in the back layer after
the gradient and before the other back items:

- Positions: along the level width, an item every `3 + pick(x, 0, SALT_SKY, 4)` tiles; base at the level's bottom edge;
  height `3 + pick(..., 5)` tiles; drawn at half scale (features of 10 to 20 px, never 40), so nothing lines up with the
  tile grid.
- Two depths: far items in `back_far`, near items in `back_decor`. No contour, no lip colour, no outline, no light except
  the kinds that carry it (Fes lanterns use `light` at alpha at most 0.08, like the torch glow of 18.8).
- Kinds per skyline: `gables` (neck gables, bell gables, a church tower; no step gables), `village` (lavender houses,
  bell tower with a stork nest, cypresses), `medina` (minaret, grey dishes, flat blocks), `towers` (towers, a clock
  tower, chimney rows, and a fog band: `detail` at alpha 0.12 over the lower third of the sky, behind everything).
- Never in front: skylines live only in the back layer; tiles cover them where blocks are.
- D9 skyline colours are only `back_far`, `back_decor`, `detail` (fog, at most 0.12 alpha) and `light` (at most 0.08).
- D10 no horizontal segment of a skyline polygon is 20 px or longer (a flat top would read as a floor).
- D11 no skyline vertex lies within 6 px of a multiple of 40 in `y`, measured from the level top (nothing lines up with
  a floor line).
- D12 the plan depends only on the level and the world (as D6).

### 23.11.6 The four packs (start values)

Values are start values from the mockup, corrected where a rule failed (noted). The developer may change any value to
make `check_palette` pass, keeping the hue character, and records the change in 23.21.

| Key | Amsterdam | Andalusia | Fes | London |
|---|---|---|---|---|
| Time of day | morning after rain, grey-blue | dusk, purple | night with lanterns, indigo | night with low fog |
| `void` | `#10151B` | `#120D18` | `#0B0A14` | `#0E1118` |
| `back_top`, `back_bottom` | `#1F2833`, `#11161D` | `#2D2138`, `#171120` | `#1D1A2E`, `#0F0D19` | `#1A1F2D`, `#262C3A` |
| `back_line`, `back_decor`, `back_far` | `#252F3B`, `#283240`, `#222B37` | `#33263F`, `#3A2C47`, `#33263F` | `#24203A`, `#2A2640`, `#24203A` | `#252B3B`, `#2B3243`, `#252B3B` |
| `block`, `block_hi`, `block_lo` | `#7E5748`, `#956A5A`, `#5E4136` (mockup `#6C4A3E` fails C5) | `#A797AC`, `#BAACBF`, `#84778E` | `#AE8870`, `#C29E85`, `#876752` | `#8A7D60`, `#A19473`, `#695F49` |
| `joint`, `mortar`, `speck`, `motif` | `#5E4136`, `#2A1C17`, `#8A6253`, `#5E4136` | `#8E8098`, `#463C50`, `#9A8BA0`, `#8E8098` | `#8F705C`, `#45342A`, `#9E7B65`, `#6E5444` | `#6C624B`, `#2C2820`, `#7A6F56`, `#4A4436` |
| `cap`, `cap_hi`, `cap_lo` | = block | `#B9824E`, `#CE9A63`, `#8A5D36` | = block | = block |
| `noring`, `noring_hi`, `noring_lo`, `noring_edge` | `#3E5470`, `#5A7598`, `#2A3A50`, `#2A3A50` | `#2F4F8E`, `#4A6DB0`, `#203868`, `#203868` | `#1F6A5D`, `#2F8A79`, `#134840`, `#134840` | `#46506A`, `#636F8D`, `#2E3548`, `#2E3548` |
| `sheen`, `pattern_a`, `pattern_b` | `#9DB3CF`, `#5A7598`, `#2A3A50` | `#A9C1EA`, `#7C9FD6`, `#B8923E` | `#8FD3C4`, `#45A893`, `#0E3A33` | `#AFC0DA`, `#636F8D`, `#2E3548` |
| `roof`, `roof_hi`, `roof_lo` | `#4A5060`, `#6A7182`, `#30343E` (mockup `#3A3E4A` fails C19) | `#B9824E`, `#CE9A63`, `#8A5D36` | `#9C7A64`, `#AE8870`, `#7A5E4C` | `#46506A`, `#636F8D`, `#2E3548` |
| `detail`, `light` | `#7F93A8`, `#FFC873` | `#E8B07A` (mockup glow `#E8A27A` is within 15 degrees of the hazard hue, C12), `#FFB45A` | `#6A5F8A`, `#FFB45A` | `#6A7488` (fog), `#FFD08A` |
| `lip` | `stone` | `lime` | `plaster` | `cornice` |
| `spikes`, `door`, `xpattern` | `needle`, `fanlight`, `window` | `shard`, `arch`, `azulejo` | `thorn`, `horseshoe`, `zellige` | `spear`, `hatch`, `lead` |
| `roof`, `cap`, `back`, `skyline` | `glazed`, false, `sky`, `gables` | `pantile`, true, `sky`, `village` | `plaster`, false, `sky`, `medina` | `slate`, false, `sky`, `towers` |
| `stones` | pair 55, big 0, running, chamfer 3, bevel 2.5, shade 0.08, mortar 2.5 | pair 40, big 0, stack, chamfer 6, bevel 2, shade 0.05, mortar 2 | pair 30, big 40, stack, chamfer 6, bevel 3, shade 0.10, mortar 2 | pair 55, big 0, running, chamfer 3, bevel 2.5, shade 0.10, mortar 2.5 |
| `rim` | wall 2, ceiling 2, chip 3 | wall 1, ceiling 1, chip 3 | wall 3, ceiling 3, chip 5 | wall 2, ceiling 2, chip 4 |
| `motifs` | `glyph` 4 (a rare facade stone with the sun sign) | `crack` 10 | `putlog` 35 | `soot` 30 |
| `tufts` | false | false | false | false |

Estimated by hand (the test recomputes): C1 lip against block about 4.4, 2.1, 2.3, 2.8; C16 about 48, 66 (block) and 38
(cap, roof), 46, 57; C19 lip against `roof_hi` about 4.4 and 1.9 for Amsterdam and Andalusia (Andalusia is tight); C17
all back colours below 0.03. `MazeWorlds.World` gets `AMSTERDAM, ANDALUSIA, FES, LONDON` (3 to 6), `COUNT` 7, `NAMES`
adds `amsterdam`, `andalusia`, `fes`, `london`; `MazeSkins.PACKS` gets the four packs in that order.

### 23.11.7 Slide trace (view only)

While `sim.sliding()`, the world view draws up to three short streaks behind Lilith's feet along the roof line, in
`roof_hi` at alpha 0.35, 6 to 14 px long by speed, in render time. Never white, never lip-coloured, never in front of
Lilith. Off in frozen shots.

## 23.12 Journey and progress

| Topic | Change |
|---|---|
| Series | `levels/index.json` lists `l001` to `l021`. One series, one unlock chain (2.8): `l010` opens when `l009` is finished. A profile that has finished 1 to 9 shows `l010` open at once. |
| Worlds | `MazeWorlds.for_number` unchanged (`(number - 1) / 3`, clamped): 10 to 12 Amsterdam, 13 to 15 Andalusia, 16 to 18 Fes, 19 to 21 London. Reordering the index moves a level to the world of its position, as before. |
| Level select (8.2) | One row per world: a header label (`FONT_SUBTITLE`, `DIM`) with the world's name from its pack (`names[lang]`), then its three cards in one row (3 columns, as today). The rows sit in the existing `ScrollContainer` with `follow_focus = true`, so focusing the first open unfinished card scrolls it into view. Numbers stay global (1 to 21). Arrow keys move between rows. |
| Subtitle | `Gehaald n/21` follows from the count. |
| Profile | No change: statistics are keyed by level id; 21 levels are far under the P6 size test (30 levels). |
| Debug | `--world=amsterdam|andalusia|fes|london` and the web key `world` take the new names. |
| Speed (20.6.2) | Decided (23.1, item 5): the roofs start a new chapter with a new mechanic, so the speed dips and rises again, never above 96 %. |

Speed table (decided; `SPEED_PCT` gets 21 entries):

| Level | 1 to 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 to 21 |
|---|---|---|---|---|---|---|---|---|
| Speed (%) | 80 to 96 (unchanged) | 90 | 91 | 92 | 93 | 94 | 95 | 96 |

## 23.13 Levels 10 to 21

### 23.13.1 Rules for roof levels

- Format 2, `sky: true`, at most 900 cells (for example 56 x 16 or 45 x 20).
- The street is the abyss: falling between houses leaves the grid at the bottom.
- Headroom: at least 8 free rows above every floor face where a floor ring is meant (the check warns, 23.10.1).
- Fewer ceilings on roofs: ceiling-ring places come from objects that are real tiles (a hoist beam in Amsterdam, a sabat
  in Fes, a bridge between towers in London), never from decor.
- Every level: a hint in `nl` and `en`, a stored solution within par, the take-back robustness, and par evidence with the
  solver: `--subset=par-1` over all exposed faces at weight 1 (and weight 0 where the space allows) finds no finish;
  the result goes into a table like 17.2.

### 23.13.2 Briefs (the designer sketches per city before building; titles are working titles)

| No. | Id | City | Difficulty | Focus | Beads | Par (target) | Slopes |
|---|---|---|---|---|---|---|---|
| 10 | l010 | Amsterdam | easy | First steep roof: land, slide, jump off at the eave onto the next roof; a gutter floor ring to get onto a gable | 3 | 1 | steep |
| 11 | l011 | Amsterdam | medium | Slide into a gutter ring for a long diagonal leap; a step gable climbed with a wall ring | 3 | 2 | steep |
| 12 | l012 | Amsterdam | hard | A catch ring thrown while sliding towards an eave (slow motion); bead back between two roofs | 3 | 3 | steep |
| 13 | l013 | Andalusia | easy | Gentle roofs: long low runs up and down, ridges; a bell tower as a wall (floor ring) | 3 | 1 | gentle |
| 14 | l014 | Andalusia | medium | Bell towers climbed with wall rings; azulejo walls (no ring) force the order | 3 | 2 | gentle |
| 15 | l015 | Andalusia | hard | A floor ring on a terrace keeps the speed of a run down a gentle roof (the l008 idea on roofs) | 3 | 3 | gentle |
| 16 | l016 | Fes | easy | Flat terraces at different heights, wide jumps, a first sabat | 3 | 1 or 2 | none |
| 17 | l017 | Fes | medium | Ceiling rings under sabats; zellige walls | 3 | 2 or 3 | none |
| 18 | l018 | Fes | hard | A riad shaft (the l005 chimney at scale), bead back | 3 | 3 or 4 | none |
| 19 | l019 | London | easy (for London) | Chimneys with pots (`X` on top), towers; wall rings | 3 | 2 | none |
| 20 | l020 | London | medium | Vertical: wall rings up a tower, a bridge with a ceiling ring | 3 | 3 | none |
| 21 | l021 | London | hard | Finale: a steep slate roof slide, towers, everything; ends at the highest tower | 3 | 4 | steep |

Fes plays with the sabat (decided, 23.1 item 5). The old question of design 13 ("drop": a ceiling ring also sets `vx =
0`) stays as it is in the simulation today (`CEILING_LAUNCH` changes `vy` only); a change would be a new decision before
the Fes levels are sketched.

## 23.14 Story and transitions (phase E)

- **Chapter card.** When a level that is the first of its world (number 1, 4, 7, 10, 13, 16, 19) is opened and the
  profile has no entry for it yet (checked before `record_start`), the game shows a card over the frozen world: the
  world name (pack `names`), one line of text (`chapter_<world>` in `MazeStrings`, `nl` and `en`, written by the
  designer from the note's story line) and `t("press_any_key")`. Any key, click or touch closes it; the intro pan (19.9)
  starts after it. Not shown with `--shot`, `--keys`, `--solve`, `--lab`. No profile field: an existing entry means the
  card was seen.
- **Ending.** After the result overlay of level 21, `Enter` (or the next button, which reads `t("ending_btn")` there)
  shows an ending card (`ending_title`, `ending_text`) instead of the level select; any input then opens the level
  select.
- **Chapter cards also for the ruins** (decided): numbers 1, 4 and 7 get one as well.
- **Stone marks (decided: wanted, sparingly, about one per level).** Format-2 field `marks`: `[{"x": 12, "y": 7, "kind": "sun"}]`, each on a `#` cell (error
  otherwise); the view draws the `glyph` motif on that stone regardless of the hash (the facade stone with the sun sign).
  View only, no effect on the simulation.
- The interplay with the chain of section 22 (the result screen) is checked when phase E starts; the ending card comes
  after whatever the result screen shows then.

## 23.15 Acceptance

### Phase A: slopes in the simulation

- R1 Inertness: a test hashes the per-tick tuple `(px, py, vx, vy, grounded, coyote, buffer, jumping, launched,
  lock_ticks, dead_ticks, rings_used)` of every stored solution of l001 to l009; the expected hash is computed on develop
  before the first simulation change and written into the test. After phase A the hash is unchanged; every existing check
  is green; the `tools/check_levels.gd` output for l001 to l009 is unchanged.
- R2 Tuning: the six new constants pass S1.
- R3 Format: format-1 levels load as before; a format-2 level with all six slope characters loads and `render()` gives
  its rows back; `format` 3, a slope in a format-1 file, `sky` in format 1, `sky` not a boolean, and each of V1 to V4
  (with every mirrored text of V3) have a minimal bad level that produces exactly its error (at least ten new cases); a
  preset ring on a covered face gives `is not exposed`.
- R4 Geometry: `MazeSlope.surface` at `lx` 0, 20000 and 40000 for each kind equals the table of 23.4.2; the joints `rR`,
  `Ll`, `/\`, `RL`, a tier `R` to `r`, and a top joint (slope to floor) meet at equal `y`; `inside` is true on and below
  the surface and false 1 unit above it.
- R5 Walking up gentle (fixture G, from the spawn holding right): `grounded` on every tick until the wall at column 10;
  `px` never decreases; `py` never increases; no `land` event; `ground` goes from `FLAT` to `GENTLE` once and stays
  `GENTLE` over the tier joint at column 8; the player stops with the box's right edge at `10 * T` and `px`, `py` stay
  constant for 60 more ticks.
- R6 Standing on a gentle slope for 120 idle ticks: `px`, `py`, `vx`, `vy` constant, `ground == GENTLE`.
- R7 The gentle ridge of fixture G (columns 16 to 19) walked in both directions: grounded every tick, no `land` event,
  no step in `py` larger than `abs(vx) / 2 + 1` per tick.
- R8 Sliding (fixture S, dropped onto the ridge's left side): `ground == STEEP`; one `slide` event; `facing` points
  downhill; with no input `vx` reaches `-SLIDE_SPEED` within 14 ticks of the landing and stays there; holding downhill
  gives `-SLIDE_FAST`, holding uphill `-SLIDE_SLOW`; `py` strictly increases while on the slope; grounded every tick.
- R9 Bottom joint (fixture S, left side): from the slope onto the floor there is no tick with `ground == NONE` and no
  `land` event; afterwards `vx` changes by `GROUND_DECEL` per tick towards the input target.
- R10 Eave (fixture E, right side): sliding off the low end of `\` at `(15, 5)`: on the first tick without support
  `ground == NONE`, `vy == GRAVITY_DOWN`; a jump pressed within 6 ticks of that tick still jumps (coyote); the player
  falls out of the grid if nothing is done.
- R11 Landing: dropping from rest onto the left side of fixture S gives, on the landing tick, `vx == (0 - v) / 2`
  (truncated) with `v` the vertical speed before the landing, and one `land` event; dropping onto a gentle slope leaves
  `vx` unchanged.
- R12 Metrics: a full jump from a gentle and from a steep slope lifts the feet 3.1 to 3.6 tiles above the take-off
  point; the slide-jump distances of 23.5.10 are measured and printed; 23.21 records them.
- R13 Top joints (fixture T): from the spawn walking left onto the steep slope, and walking right down the gentle pair
  onto the floor: grounded on every tick, no `land` event, no tick with `ground == NONE`; on the left the slide starts
  at the joint (one `slide` event).
- R14 Slope into wall: on fixture G the player pressing into the wall at the high end of the upper tier stays still (no
  change of `px`, `py` over 60 ticks); a player dropped onto a steep slope next to a wall at its high end slides away
  from it.
- R15 Invariants of 23.5.8 on fixtures S, G, E, T and the three lab levels for 50 seeded random input runs of 1200 ticks
  each (seeded with `WhiteRng`; hold tokens and jumps only).
- R16 Determinism: S17 on fixtures S, G, E, T; `snapshot()` contains `ground`.
- R17 Cast: a throw that first meets a slope is invalid with reason `slope` and changes nothing; throws at the top face
  of a block under a slope and at the side of a block next to a high side are `no_ring`; on a level with `sky` a throw
  straight up (index 36) from under open sky gives reason `none`, without `sky` it gives `no_ring` at the top edge.
- R18 Rings: on fixture E with a preset floor ring on the gutter `(9, 6)`, a player sliding down the left side is
  launched with `vy == -FLOOR_LAUNCH` and `vx` equal to its slide speed at that tick; `rings_used` counts as in ADR 0009.
- R19 Camera: on a slide fixture with `slide` true, `guard_b` reaches `GUARD_BOTTOM_FALL` within 0.3 s of real time and
  the play rect shows at least 3.6 tiles below the feet from then on; all CAM tests unchanged with `slide` false.
- R20 Lilith: `body_pose` gives `SLIDE` for sliding and the 18.6.2 poses otherwise; the bounds of 23.8 hold for `SLIDE`
  and for grounded poses with `grade` -1, -0.5, 0.5 and 1; F5 measured on a lab01 slide sequence: no rig joint moves
  more than 3.5 px between frames of 1/120 s.
- R21 Look: every slope primitive lies inside its collision polygon (tolerance 0.01 px); the surface edge of every slope
  is straight; no slope and no covered face has a trim; `lip_face` equals cast validity (apart from range and taken) on
  every face of the lab levels; all existing shots compare equal to develop.
- R22 Lab: `--lab` and `?lab` show the three lab levels and never write the profile; `tools/check_levels.gd
  --dir=res://levels/lab` exits 0 with every solution within par.

### Phase B: tools and solver

- R23 `search_par.gd` runs on format-2 levels and finds the lab01 calibration set; `check_search_par.sh` green.
- R24 Level check: the format-2 output line, the 900-cell error (test with a 31 x 30 level), the headroom warning (test
  with a sky level and a floor 5 rows under the top); exit 0 on the shipped levels and the lab.
- R25 `tools/solver/build.sh` builds without warnings (`-Wall -Wextra`); CI runs `tools/check_solver.sh`.
- R26 Equivalence: for every level of the index and the lab, 12 seeds of 900 ticks (half with three random extra
  presets), `trace_gd.txt` and the solver's trace are identical (`diff` empty).
- R27 Calibration: the solver finds the stored solution ring sets of l001 to l009 and the lab levels; it reproduces the
  "no finish" results of 17.2 and the 2026-11-21 test report for l004 to l009 at the documented settings.
- R28 Speed: on the l005 calibration the solver is at least 100 times faster than `search_par.gd` (both times printed).

### Phase C: skins

- R29 Ruins unchanged: every existing shot compares equal to the end of phase B; the S-criteria of 21.14 green.
- R30 The four packs pass `validate` and `check_palette`; each survives the JSON round trip of S2.
- R31 Each of C16 to C22 has a mutation of a pack that produces exactly its id; C16 to C22 hold for the three ruin packs
  too; `MazeArt.delta_e` matches three reference pairs within 0.5.
- R32 Unknown roof style, door shape, `X` pattern, skyline, spike shape, tint or motif each give a validation error; the
  engine-owned keys are still refused.
- R33 Never larger: slope, spike, door and `X` pattern primitives inside their cell (or slab, or collision polygon); the
  door opening area of every shape at least 85 % of 1020 px²; every spike outline inside today's envelope.
- R34 Reading: the lip sampling of 21.13.2 on the lab levels and on l001 in every city; along every slope surface no
  sample within 16 px is lip-like (`contrast(lip, c) < 1.3`); with `cap`, the sampled lip rule holds on cap stones too.
- R35 Skyline: D9 to D12 on every lab level and new level in its city; tester review that nothing in the skyline looks
  walkable (23.17 C).
- R36 Bake: the budgets of 21.12.3 hold for the lab levels in all seven worlds; texture memory under 24 MB.
- R37 Shots of 23.16 C are produced without errors and are identical in two runs.

### Phase D: journey and levels

- R38 The index lists l001 to l021; `for_number` gives the four cities for 10 to 21; the level select shows seven world
  rows with their names and 21 cards; the first open unfinished card is focused and visible.
- R39 Unlock: with l001 to l009 finished, card 10 is enabled and 11 is not; finishing l010 enables 11.
- R40 Speed: `level_speed` follows the decided table (F1 updated).
- R41 Every new level: valid, at most 900 cells, `sky`, hint in both languages, a solution within par, the robustness
  test, no headroom warning that is not explained in its brief.
- R42 Par evidence: the solver table of every new level (no finish with par - 1 rings at the documented settings) in
  23.21.
- R43 Shots: one play shot and one overview shot per new level.

### Phase E: story

- R44 The chapter card shows exactly when a first-of-world level is opened without a profile entry, never in the debug
  modes of 23.14, and closes on any input; afterwards the intro runs.
- R45 Texts: every new key exists in `nl` and `en` (U7).
- R46 The ending card follows the result of level 21 and leads to the level select.
- R47 `marks`: valid on `#` cells only; the marked stone shows the sun glyph in every world.

## 23.16 Developer steps per phase

Branches `feature/roofs-a-slopes`, `feature/roofs-b-tools`, `feature/roofs-c-skins`, `feature/roofs-d-<city>`,
`feature/roofs-e-story`; one commit per step; every step green before the next.

### Phase A (after #038 is merged)

1. **Golden trace.** On develop, before anything else: the R1 test with its hash. Commit.
2. **Level format.** `MazeLevel` (enum, `CHARS`, `format`, `sky`, `slope_count`, `slope`, `covered`, `render`, V1 to
   V4, the format errors), `MazeSlope`; `level_tests.gd` (R3, R4). Format-1 levels untouched.
3. **Ground and moving.** `MazeSim`: `ground`, `_compute_ground`, the new `_move` (23.5.4), the slide branch, the
   `slide` event, `snapshot`. Tuning constants. `slope_tests.gd` with fixtures S, G, E, T: R2, R5 to R16, R18. R1 green.
4. **Cast and faces.** Slope hits, reason `slope`, `covered()` for the front cell, `sky`; `MazeArt.lip_face` with
   `covered()`; preset validation. R17.
5. **Minimal look.** `MazeSkin.Side.SLOPE`, derived roof colours for format-1 packs, `MazeTileShapes.slope` (style
   `plain`), decor treats slopes as solid. R21. Shots compare equal.
6. **Lilith and camera.** `Body.SLIDE`, `grade`, foot adaptation, the `SLIDE` rig; camera `slide` key. R19, R20.
7. **Lab.** `levels/lab/`, `--lab`, web key `lab`, solutions, check in CI. Shots `lab-steep`, `lab-gentle`, `lab-mixed`
   (`--lab --level=lab0n`) and `lab-slide` (a `--keys` prefix of the lab01 solution with Lilith sliding). R22.
8. **Documentation.** Deviations as built in 23.21; `MIN_CHECKS`; after section 22 is merged: in `docs/design.md` a
   pointer `## 23. Roofs`, A2 in 1.3 replaced by "Slopes: see section 23 (ADR 0015)", one line at 3.6, 3.10, 5.1 and
   5.5: "Changed by section 23 (`docs/design-roofs.md`)"; `docs/conventions.md`: class `MazeSlope`, the lab folder, the
   rule that slope levels are format 2; the glossary terms of 23.20 into `docs/glossary.md`.

### Phase B

1. `tools/check_levels.gd` (23.10.1) and its tests (R24); CI for the lab.
2. `tools/search_par.gd` (23.10.2), `check_search_par.sh` lab case (R23).
3. `tools/export_levels.gd`, `tools/trace_sim.gd`.
4. `tools/solver/maze_solver.cpp` and `build.sh`: level reader, sim, trace mode; `check_solver.sh` with the diff (R25,
   R26). Write the sim part from `sim/sim.gd` function by function, keeping the names (`move_x`, `lift`, `move_y`,
   `snap`).
5. Search mode and calibration (R27, R28). Results in 23.21.
6. CI step, conventions (the rule of 23.10.4), README line. Card #011 is done with this phase.

### Phase C

1. **Format-2 packs, no visible change.** Keys, sets, resolve with derived values for format 1, `validate`, C16 to C22,
   `MazeArt.lab`, `delta_e`. R29 (compare), R31, R32.
2. **Engine shapes.** Roof styles, door shapes, `X` patterns, spike shapes `needle` and `shard`, motifs `putlog` and
   `soot`, cap row. R33.
3. **Skylines.** `MazeDecor.skyline`, back pattern `sky`. R35.
4. **Packs.** The four packs, `MazeWorlds` (seven worlds, names), `--world` names. R30, R34, R36.
5. **Slide trace** (23.11.7).
6. **Shots** added to `tools/shots.txt`: per city `<city>-lab` (`--lab --level=lab01|lab02|lab03 --world=<city>`, the
   steep lab for Amsterdam and London, the gentle one for Andalusia, the mixed one for Fes), `<city>-on-l001`
   (`--level=l001 --world=<city>`), `<city>-overview` (`--camera=overview`), `<city>-phone` (960 x 432, `--touch`), and
   `slide-glazed` (Amsterdam, Lilith sliding). Grey and half copies with `tools/shot_variants.gd`. R37.
7. Documentation: 23.21, conventions (classes, the palette exception now names the four packs), `MIN_CHECKS`.

### Phase D (per city: designer sketch, owner nod, then build)

0. **Journey plumbing** (once, before Amsterdam): `SPEED_PCT` (decided table), level select rows per world with headers,
   `follow_focus`, tests U1 (the test reads the index size), R38 to R40 with the levels that exist.
1. Per city: three levels from the designer's sketch, the index, hints, solutions, robustness, solver evidence, shots.
   R41 to R43. The difficulty labels follow the brief.

### Phase E

1. Chapter card and texts (R44, R45). 2. Ending (R46). 3. `marks` (R47), only if the owner wants the facade stones.

## 23.17 Tester checklists

### A

- Headless: all checks, R1 hash unchanged, `check_levels` for `levels/` and `levels/lab/`.
- Play the lab in a desktop browser (`?lab`) and on a phone: walking up and down gentle roofs without jitter or stalls,
  also at ridges and tiers; sliding on steep roofs feels controlled (faster, slower, never stopped), the jump at the
  eave is reachable, coyote at the eave works; landing on a steep roof turns into a slide without a jolt; no getting
  stuck where a slope meets a wall or a floor; a throw at a roof shows the invalid line; a gutter ring launches a sliding
  player far.
- Lilith: slide pose readable, feet on the roof line, no jump in the legs when a slide starts or ends; the view shows
  enough below while sliding.
- Ruins: l001 to l009 play as before (spot check l003, l006, l009 with their solutions on screen via `--solve`).
- Try to break it: jump into a ridge from below at speed, walk off a slope top onto a lower floor, hold against a wall
  at a high end while jumping, slide into spikes, aim in slow motion while sliding, land exactly on the floor corner at
  the top of a steep roof and walk onto the roof.

### B

- `tools/check_solver.sh` locally and in CI; change one constant in a scratch copy of `sim.gd` only and confirm the
  check fails.
- Repeat two cheaper-route searches of 17.2 with the solver; compare with the 2026-11-21 report.
- Run the solver on each lab level with `--subset=par-1`.

### C

- Shots at 100 %, 50 % and grey (`tools/shot_variants.gd`): in every city, every ring face has a lip you find without
  searching; roofs never look like a lip; `X` patterns are quiet and read as "smooth"; pins are clearly red on the
  blocks of each city, also in grey; white rings and beads stand out on every palette; the sky is dark.
- Skylines: nothing in the back looks like a ledge, a stair or a platform (look especially at Amsterdam gables and London
  chimney rows); fog stays behind the play field.
- Doors read as the finish in every city; nothing else looks like a lit door (windows in the back stay small and faint).
- Ruins: compare shots equal.
- Phone: `<city>-phone` shots and one played lab level per city.

### D

- Per city: play the three levels on desktop and phone; difficulty rises within the city and from city to city; each
  level teaches its focus of 23.13.2; par feels fair; try to beat par (report routes); headroom never bites.
- Level select: seven rows, names, unlock from 9 to 10, scrolling with keys and touch.
- The speed dip at level 10 is noticeable as calmer, not as a bug.

### E

- First opening of levels 1, 4, 7, 10, 13, 16, 19 shows the card once; a second opening does not; debug modes do not.
- Texts in both languages; the ending after 21.

## 23.18 Phases: risks and estimates

Estimates in developer days (D) and tester days (T), including tests and documentation.

| Phase | Content | Estimate | Main risks | Mitigation |
|---|---|---|---|---|
| A | Slopes in the sim, format 2, cast, minimal look, slide pose, camera key, lab | 4 D, 1.5 T | Edge cases at joints (jitter, stalls, one-tick hops); a changed trace on the ruins; sliding feels like losing control | Golden trace first (R1); fixtures for every joint; invariant fuzzing (R15); the owner plays the lab before phase C; slide speeds are three tuning values |
| B | Level check, search_par, C++ solver with equivalence | 2.5 D, 0.5 T | Two simulations drift apart; integer division semantics differ; CI toolchain | Per-tick trace diff in CI on every level; one rule: sim changes touch both in one commit; `int64_t` and truncating division as in GDScript |
| C | Pack format 2, engine shapes, skylines, four packs | 3.5 D, 1.5 T | Palette rules conflict (C16 reading); skylines read as walkable; roofs read as lips; bake time grows | C16 as colour difference (confirmed); D10 and D11 geometric rules plus review; C19 and sampled checks; bake budget test |
| D | Journey plumbing; 12 levels with designer sketches | 0.5 D plumbing, then per city 0.5 designer + 1.5 D + 0.5 T (about 8.5 days in total) | Weak levels; par not minimal; levels over 900 cells; headroom; Fes waits for the ceiling-ring decision | Sketch first and owner nod; solver evidence per level; check errors and warnings |
| E | Chapter cards, ending, marks | 1 D, 0.5 T | Text volume and tone; interplay with the chain's result screen | Designer writes the texts; checked against section 22 when E starts |

Total about 19 developer days and 5.5 tester days, plus the designer's sketches and texts. Phase B starts after A step 3
(the solver ports the finished movement). C needs A (slope drawing); D needs A, B (evidence) and C (look); E needs D for
the cities' texts.

## 23.19 Questions for the owner (answered 2026-11-23)

1. **Red against the block.** Colour difference Delta E at least 35 (C16). Agreed.
2. **Speed after level 9.** 90 % at level 10, rising by 1 per level to 96 %, then 96 %. Agreed (23.12).
3. **Control while sliding.** On a steep roof you steer only the speed. Open: the owner decides after playing `?lab`;
   built as designed in phase A.
4. **Slopes per city.** Amsterdam steep, Andalusia gentle, Fes flat, London steep in the finale. Agreed.
5. **Ceiling ring in Fes.** Fes plays with the sabat. Agreed; the ceiling-ring behaviour stays as it is (23.13.2).
6. **Chapter cards.** One per world, the ruins included. Agreed.
7. **Facade stones with the sun sign** (`marks`): wanted, sparingly, about one per level. Agreed (phase E, R47).

## 23.20 Glossary additions (to be merged into `docs/glossary.md` by the developer)

| Term | Meaning |
|---|---|
| Slope (`MazeSlope`) | A sloped tile: `/` and `\` (steep, 45 degrees) or a gentle pair `rR` / `Ll` (1 in 2). Always on a full block with air above; never a ring face. |
| Steep slope | A 45 degree slope tile; standing on it means sliding. |
| Gentle slope | Half of a 1 in 2 slope pair; walked on like a floor. |
| Slide | Moving down a steep slope: the speed goes to 360 px/s, 480 with input downhill, 240 with input uphill; never stops while on the slope. |
| High side, low side | The vertical end of a slope tile (it blocks like a wall from outside) and the open lower end. |
| Slope surface | The line a slope tile's walking surface follows; the player's centre stands on it. |
| Ground (`MazeSim.Ground`) | What the player stands on: none, flat, gentle or steep. |
| Snap | Keeping the feet on the roof when walking or sliding downhill, within 16 px plus the horizontal speed. |
| Step band (`SLOPE_STEP`) | The bottom 16 px of the box that may overlap a full block while standing on a slope, so a slope runs into the floor at its top without a wall. |
| Covered face | A face whose front cell is solid or a slope; never a ring face, never a lip. |
| Gutter | A block at the low end of a roof whose top is a floor (and a ring face). |
| Eave | The low end of a roof over open air. |
| Ridge | Two slopes meeting at their high sides (`/\`, `rRLl`). |
| Sky (`sky`) | Level field (format 2): a bead that leaves the grid at the top flies on; the player is still stopped at the top edge. |
| Level format 2 | The level format with slope tiles and `sky` (and the optional `marks`); format 1 stays valid. |
| Lab | The test series `levels/lab/`, opened with `--lab` or `?lab`, never written to the profile. |
| Native solver | `tools/solver/maze_solver`: a C++ port of the movement part of the simulation for par searches, kept equal by a trace diff. |
| Roof style | The engine-drawn look of slope tiles, chosen by a pack: plain, glazed, pantile, plaster, slate. |
| Door shape | The engine-drawn outline of the door, chosen by a pack: post, fanlight, arch, horseshoe, hatch. |
| `X` pattern | An engine-drawn quiet pattern inside `X` slabs, chosen by a pack: window, azulejo, zellige, lead. |
| Cap row | The top stone row of a mass drawn in the cap colours (Andalusian roof tiles), never under a pin. |
| Skyline | Low-contrast, half-scale silhouettes of a city in the back layer; never lined up with the tile grid. |
| Journey | The single series from the ruins (1 to 9) over the roofs (10 to 21). |
| Chapter card | A short card with the world's name and a line of story, shown once at the first opening of a world. |
| Delta E | The CIELAB colour difference used by rule C16 (hazard red against blocks, caps and roofs). |

## 23.21 Deviations as built

Filled in per phase by the developer: measurements (slide-jump distances of R12, solver timings of R28, bake numbers of
R36), changed palette values, level tables with par evidence.

### Phase A (card #041, branch `feature/roofs-a`)

Built as designed unless listed. Check counts: `MIN_CHECKS` 1711 -> 1885; kit tests, `check_levels` (`levels/` and
`levels/lab/`), `check_search_par.sh` and the web export green; `check_levels` output for l001 to l009 identical.

**R1 golden trace.** `tests/inert_tests.gd` hashes (SHA-256) the tuple `(px, py, vx, vy, grounded, coyote, buffer,
jumping, launched, lock_ticks, dead_ticks, rings_used)` of every tick of the stored solutions of l001 to l009: 2570 ticks,
`ed5d3873a5d602b74d300a169a765cd70e4e092e280ac6f84bef3cdfa5db17ad`. Computed on develop before the first simulation
change (commit `11c6f8b`); unchanged after phase A. The 59 existing shots of `tools/shots.txt` compare equal to develop
(only the live `fps` label differs).

Deviations from the text above (all in `sim/sim.gd` unless noted):

1. **Lift on a block under a roof (23.5.4 step 3, second bullet).** When the cell of `(px, py - 1)` is a full block with a
   slope standing on it, the feet go to that slope's surface (never above the block top), not to the block top. As
   written, a player walking over a tier joint (`R` into the `r` above the next block) was put on the block top, 2 px
   below the roof, for one tick and then lifted: ground flickered `GENTLE`, `FLAT`, `GENTLE` and R5 ("stays `GENTLE`
   over the tier joint") failed.
2. **Snap prefers the roof over a block corner (23.5.4 step 5).** When the player was on a slope (`start` is `GENTLE` or
   `STEEP`), the slope under the centre wins over a nearer block top under the box, and a `FLAT` result after a
   slope tick is snapped to the slope under the centre too. As written ("whichever is nearer"), a slide down a stair
   of `/` tiles (fixture S) stood on every block corner for two to four ticks and braked with `GROUND_DECEL`:
   6000 -> 3500 and up again at every tile. A player that starts on a floor or lands on a corner is unchanged (the
   documented corner case of 23.5.4 stays).
3. **R17.** No ray can reach a face that is covered by a slope without crossing the slope's own polygon first (the slope
   is always in front of the face), so the cases "top face of a block under a slope" and "side of a block next to a high
   side" cannot be produced by `cast`. They are covered by validation (`is not exposed`), by `lip_face` and by the
   comparison of R21: for every open face of the fixtures and the lab levels `MazeArt.lip_face` equals the validity of a
   cast from the cell in front of the face (more than 300 faces).
4. **`MazeSlope.FIRST` and `LAST`** are the literals 4 and 9 (the `Cell` values) to keep `MazeSlope` and `MazeLevel` free of
   a constant cycle.
5. **Lilith (23.8).** `SLIDE` `hand_near` is `(8.5, -15)` instead of `(10, -15)`: with an aim arm the bead halo at
   `(10, -15)` and the tilt left the 30 px box by 0.4 px. Bounds in the tests: the boot of `SLIDE` and every pose on a
   steep grade down to `y = +9`, grounded poses on a gentle grade down to `y = +5` (the design said +4; a running boot
   at `x = 9.5` and grade 0.5 reaches 4.75). Blends from or to `SLIDE` use the same extension.
6. **Camera (R19).** `MazeGame` passes `slide`; `MazeCameraRig` reads it with `f.get("slide", false)`, so frames of the
   old tests need no key. Measured: the bottom guard reaches `GUARD_BOTTOM_FALL` after 0.20 s; the play rect shows at
   least 144 px (3.6 tiles) below the feet on every frame from 0.3 s.
7. **Decor and the chain map (23.9.2).** `MazeDecor` uses `covered()` in `_solid_next_to` and the interior-crack rule
   only; supports (a torch's floor, sand) still need a full block, so nothing is placed on a roof. The ghost map of the
   chain draws slope cells as solid runs.
8. **Level check.** The `ok` line of format-2 levels and the 900-cell error are phase B (23.10.1); the lab levels print
   the format-1 line. CI checks `levels/lab/` in its own step.
9. **Glossary.** Only the terms of phase A (23.20) are merged into `docs/glossary.md`; native solver, roof style, door
    shape, `X` pattern, cap row, skyline, journey, chapter card and Delta E come with their phases.
10. **Fixtures** (`tests/slope_fixtures.gd`) got an `F` cell (S: (13, 2), G: (19, 2), E: (18, 2), T: (14, 2)) so they
    validate as levels. R15 runs on them and on the three lab levels (50 seeds of 1200 ticks each).

Measurements (R12, from `tests/slope_tests.gd`; the same run prints them):

| Situation | Measured | Design 23.5.10 |
|---|---|---|
| Full jump from a gentle slope, lift of the feet | 3.17 tiles | 3.1 to 3.6 |
| Full jump from a steep slope, lift of the feet | 3.17 tiles | 3.1 to 3.6 |
| Running jump from a gentle slope, distance at equal height | 4.88 tiles | a 4-tile gap |
| Jump from a slide without input (360 px/s) | 4.31 tiles | about 5 |
| Jump from a slide holding downhill (480 px/s) | 5.85 tiles | 6 to 7 |
| Walking off an eave at 480 px/s, one tile of fall | 1.71 tiles forward | about 1.8 |
| From rest on a steep roof to 360 px/s | 12 ticks (500 units per tick) | at most 14 |

The two slide jumps are about 0.7 and 0.15 tile shorter than estimated; the owner decides after playing `?lab` whether the
slide speeds (three tuning values) stay.

Lab series (`levels/lab/`, format 2, `sky`, solutions in `tests/solutions.json`):

| Id | Size | Par | Solution | Content |
|---|---|---|---|---|
| lab01 | 48 x 18 | 2 | 314 ticks, 2 rings | floor ring over a steep ridge, slide down the far side, jump at the eave, slide to a gutter with a ring thrown while sliding, leap to the door |
| lab02 | 40 x 14 | 0 | 290 ticks, 0 rings | gentle tiers up and down, a gentle ridge, a gentle slope into a wall (jump), a gentle descent |
| lab03 | 36 x 17 | 1 | 173 ticks, 1 ring | steep roof into a gentle one, a spike at the low end, a floor ring thrown while sliding, leap to a ledge |

How to open the lab in the web build: `https://play.white-maze.steefbeest.nl/?lab` (level select with the three cards,
every card open) or `?lab&level=lab01` (and `lab02`, `lab03`) for one level. Locally: `godot --path . -- --lab`
(`--level=lab01`). Nothing is written to the profile.
