# White Maze - design

Status: phase 1 (playable prototype) is built: the headless core (card #002, par counts rings used per ADR 0009) and
the screens, controls, profile store, screenshots and the Pages deploy (cards #004 and #006); deviations in sections 14
and 16. The owner's playtest and the tester's review of the screens are open. Later phases are outlined and marked
**[later]**; they are not built in phase 1.
This document describes the game as it must be built. Decisions with their trade-offs are in `docs/adr/`; terms are
defined in `docs/glossary.md`; code, test and level rules are in `docs/conventions.md`.

White Maze uses the shared base White Kit (`dm-utils/white-kit`, a git submodule at `res://addons/white_kit/`, pinned
to `v0.3.0`). Unlike the puzzle games it does not use the kit's day screen, attempt, rules or progress file; section 9
lists exactly what is reused (ADR 0008).

## 1. Purpose and phases

White Maze is a calm 2D platformer in the White series. The player walks and jumps through a fixed series of
handmade levels from start to finish. With the right stick (or a key, or the mouse) the player throws a white bead in
a straight line; where it hits a surface it becomes a bounce ring that launches the player away from that surface: up
from a floor, sideways from a wall, down from a ceiling. Each level has a supply of beads (usually three) that can be
taken back and thrown again, and a par: the fewest rings the level designer needs to bounce off (rings used, ADR
0009). There are no enemies and no lives, only obstacles. There is no time pressure, but every level is timed and the
times are kept as statistics in a local profile.

Owner decisions (2026-11-20), recorded in ADR 0001:

- Name White Maze, repository `white-maze`, game id `white-maze`, title `White Maze`, logo text `WHITE MAZE`.
- Walk, jump, finish levels; 2D; not too complex.
- Keyboard first, designed from the start for phones and tablets (touch, landscape).
- A fixed series of levels, no daily puzzle.
- No time pressure; time measured per level; statistics in a profile, local first, extendable to an online profile.
- White style: flat, dark, calm, the White Kit palette. No enemies, no lives, only obstacles.

### 1.1 Phase 1: playable prototype

Phase 1 answers:

1. Do walking and jumping feel good (tight, forgiving) with keyboard and with touch?
2. Is throwing a bead and bouncing off rings fun with grey blocks only?
3. Is aiming in slow motion pleasant on a phone (thumb conflict, section 4.4)?
4. Is the ring rule ("a ring pushes you away from its surface") clear after one level each?

In scope:

- Fixed-step simulation of player, beads, rings, hazards and finish (sections 2 and 3), fully testable headless.
- Controls: keyboard, optional mouse, touch overlay (section 4); slow motion while aiming.
- Handmade level format, loading and validation, a level check tool, and nine levels (the first three easy, medium, hard as test levels; l004 to l009 added by card #007) built
  from grey blocks (section 5).
- Run scripts: a text format for input sequences, used for solution tests and to store the best run (section 6).
- Time measurement per level and a local profile with statistics, versioned and merge-ready (section 7).
- Screens: level select, game with HUD, pause, result, rotate hint; Dutch and English (section 8).
- CI workflow (tests, level check, screenshots, web export) ready for when a remote exists; no deploy (section 10).

Out of scope for phase 1: moving obstacles, sound, gamepad, more than nine levels, a visual level editor, ghosts or
replays on screen, an online profile or leaderboard, Android/iOS builds, a settings screen, the play version on
GitHub Pages (needs a remote).

### 1.2 Later phases [later]

- Phase 2: 15 to 30 levels in a fixed series with a few new obstacle types (moving blocks, one-way platforms), sound,
  gamepad, polish after the phase 1 playtest. Play version at `play.white-maze.steefbeest.nl`.
- Phase 3: online profile through Pulse (`/v1/games/white-maze/profile`), using the merge function of section 7.6;
  optionally verified best times by replaying the stored run (section 6.4).

### 1.3 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| A1 | Godot 4.7.2, GDScript, GL Compatibility, web export single-threaded, as the other White games. | Change the pin in `project.godot`, CI and kit action inputs. |
| A2 | Levels are built from axis-aligned square tiles; no slopes, no rotating geometry in phase 1 or 2. | The own collision code (3.6) would need slopes; ADR 0002 revisited. |
| A3 | Level geometry is static in phase 1. Moving obstacles later become sim entities stepped in the same tick. | Nothing in phase 1 depends on it. |
| A4 | The phone test of phase 1 runs in a mobile browser (web export), landscape. | A native build is phase 2 or later. |
| A5 | Pulse's game profile is an opaque JSON object of at most 256 KB with an optional string `id` of at most 64 characters, and a 409 conflict is resolved by a deterministic client merge (`pulse/apps/accounts/src/profile.ts`). | The profile format of section 7 needs an adapter, not a rewrite. |
| A6 | GDScript integer arithmetic is 64-bit and identical on every platform; the simulation uses only integers (3.1). | None expected. |
| A7 | The number of beads is a level field (`beads`, 1 to 9, default 3); three is the usual value, not a series rule. A level may have fewer (l004 has one) and its par may exceed its beads (ADR 0009). | None. |

## 2. Game rules

### 2.1 World

- A level is a grid of square tiles, 40 px each. Columns `x` grow to the right, rows `y` grow downwards; row 0 is the
  top row of the level file (ADR 0004, conventions "Coordinates and units").
- Tile kinds: empty `.`, solid block `#`, no-ring block `X` (solid, beads do not stick), spike `^` (hazard, not
  solid), start `S` (empty, the spawn point), finish `F` (empty, the goal).
- Outside the grid to the left, to the right and above: solid, like `X`. Below the grid: empty; a player whose top
  edge passes below the grid dies (2.5).

### 2.2 Player

- A white square, 30 px wide and 32 px high (hitbox), drawn as a 32 x 32 rounded square with one dark eye stripe on the
  side it faces.
- Walks left and right, jumps; no double jump, no wall jump, no dash.
- Game feel (section 3.3): acceleration and deceleration, variable jump height (release early to jump lower), coyote
  time, jump buffer, short apex hang, corner correction, faster falling than rising, a maximum fall speed.

### 2.3 Beads and rings

- A level starts with `beads` beads (the level field, usually 3) and possibly some preset rings from the level file.
  The beads left are the supply: what the player can still throw.
- Throwing: the player aims in one of 144 directions (2.5 degree steps) and releases. The bead flies in a straight
  line from the player's centre at 1600 px/s, up to 800 px. Where it first hits a solid tile face, it becomes a ring on
  that face.
- A throw is valid only when the face hit belongs to a `#` block, the cell in front of that face is not a spike, no
  ring is on that face or on its way to it, the hit is within range, and a bead is left. An invalid throw costs
  nothing; the aim line shows the target as invalid before release (4.5).
- A ring sits on the centre of one tile face and lasts until the level is restarted or the ring is taken back.
- Launch rule: when the player touches a ring (zone in 3.7) it sets the player's velocity away from its surface:
  - floor ring (top face of a block): straight up at 1080 px/s; horizontal speed unchanged;
  - wall ring (side face): sideways at 640 px/s away from the wall plus at least 560 px/s upward; for 0.2 s the
    player's left/right input is ignored;
  - ceiling ring (bottom face): straight down at 900 px/s; horizontal speed unchanged.
  The launch sets the velocity, it does not add to it, so a ring always gives the same bounce (ADR 0005). The jump
  button does not change a launch.
- After launching, the same ring cannot launch again for 10 ticks.
- Take back ("bead back", key `Z`): removes the most recently thrown ring (or the bead still in flight) and returns
  the bead to the supply. Preset rings cannot be taken back. Taking back has no other effect: the player stays where
  they are, the clock keeps running and rings used does not go down.
- Rings used (ADR 0009): the number of thrown rings that have launched the player at least once in the attempt. A
  thrown ring counts at its first launch; further launches of the same ring do not count again. Preset rings never
  count. A ring taken back before it launched the player, or a bead taken back in flight, never counts. Rings used
  never goes down within an attempt (not by bead back, not by a death); a restart starts at 0. Par is compared with
  rings used.

### 2.4 Start and finish

- The player spawns standing on the floor below `S`, facing right.
- Touching the `F` tile finishes the level at once.

### 2.5 Hazards, death and respawn

- Touching a spike's hitbox (lower half of its tile, 3.6) or falling out of the grid is a death.
- After a death the player disappears for 0.5 s (30 ticks), then respawns at the start with zero velocity. Rings,
  beads and rings used stay as they are; beads in flight still land. The clock keeps running. There are no lives
  (ADR 0005).

### 2.6 Time

- Time is game time: the number of simulation ticks (60 per second) from the first active tick to the finish tick,
  inclusive (ADR 0003). The first active tick is the first tick with left/right input, a jump press or a valid throw;
  reading the level before moving is free.
- While the player aims, the game runs at a quarter of its speed (4.4); the clock runs at the same game speed, so
  aiming costs a quarter of real time.
- Shown as `m:ss.cc` (hundredths, rounded down): `cs = ticks * 100 / 60` (integer division).

### 2.7 Attempt, restart, pause

- An attempt starts when a level is opened or restarted: player at start, preset rings only, all beads, rings used 0,
  clock stopped at `0:00.00`.
- Restart (`R` or the HUD button) ends the attempt and starts a new one.
- Pause (`Esc`, `P`, the HUD button, losing window focus, turning a phone to portrait) stops the simulation.

### 2.8 Series and unlocking

- The levels form a fixed ordered series (`levels/index.json`). Level 1 is open; level `n + 1` opens when level `n`
  has been finished once (a best time exists in the profile).
- Debug argument `--all-levels` opens every level (section 10.4).

## 3. Simulation

### 3.1 Principles (ADR 0002)

- Own fixed-step simulation in `sim/`, no Godot physics. One tick = 1/60 s of game time.
- Integers only in `MazeSim.step` and `MazeSim.cast`: positions and velocities in units of 1/1000 px
  (`UNITS_PER_PX = 1000`), velocities per tick, accelerations per tick per tick. A tile is `TILE = 40000` units.
- No nodes, no scenes, no input, no rendering, no `Time`, no randomness, no `user://` in `sim/`.
- The same level and the same input sequence give the same state on every machine (determinism test, 11.2).

### 3.2 Integer conversion

`MazeTuning` (`sim/tuning.gd`) holds every tuning value twice: the readable value (px/s, px/s², px, s) as a float
constant with suffix `_PX` or `_S`, and the integer the simulation uses as a literal constant. Conversion:

- speed: `roundi(px_per_s * 1000 / 60)` units per tick;
- acceleration: `roundi(px_per_s2 * 1000 / 3600)` units per tick per tick;
- distance: `px * 1000` units; time: `roundi(seconds * 60)` ticks.

A test checks every literal against its readable value with these formulas (11.2), so tuning changes always edit
both lines.

### 3.3 Tuning values (start values)

| Name | Readable | Sim value | Purpose |
|---|---|---|---|
| `RUN_SPEED` | 300 px/s | 5000 | Top walking speed (7.5 tiles/s). |
| `GROUND_ACCEL` | 2400 px/s² | 667 | Speeding up on the ground (full speed in about 0.13 s). |
| `GROUND_DECEL` | 3000 px/s² | 833 | Stopping and turning on the ground; over-speed decay on the ground. |
| `AIR_ACCEL` | 1600 px/s² | 444 | Speeding up in the air in the input direction. |
| `AIR_TURN` | 2000 px/s² | 556 | Turning in the air (input opposite to motion). |
| `AIR_DRAG` | 300 px/s² | 83 | Slowing in the air without input, and over-speed decay with input in the same direction (keeps launch momentum). |
| `JUMP_SPEED` | 800 px/s | 13333 | Upward speed at jump start. |
| `GRAVITY_UP` | 2400 px/s² | 667 | Gravity while rising with jump held, and while rising after a launch. |
| `GRAVITY_DOWN` | 3600 px/s² | 1000 | Gravity otherwise (falling, or rising with jump released = variable jump). |
| `APEX_THRESHOLD` | 60 px/s | 1000 | Apex hang applies while `abs(vy)` is below this. |
| `APEX_GRAVITY` | 1200 px/s² (0.5 x up) | 333 | Gravity during apex hang (jump held). |
| `MAX_FALL` | 900 px/s | 15000 | Maximum downward speed. |
| `COYOTE_TICKS` | 0.10 s | 6 | A jump still works this many ticks after leaving a ledge. |
| `JUMP_BUFFER_TICKS` | 0.133 s | 8 | A jump press this many ticks before landing still jumps on landing. |
| `CORNER_CORRECTION` | 8 px | 8000 | A rising player whose head clips a ceiling corner by at most this is pushed sideways instead of stopped. |
| `FLOOR_LAUNCH` | 1080 px/s | 18000 | Floor ring: upward speed (about 5.8 tiles high). |
| `WALL_LAUNCH_X` | 640 px/s | 10667 | Wall ring: sideways speed. |
| `WALL_LAUNCH_LIFT` | 560 px/s | 9333 | Wall ring: minimum upward speed. |
| `CEILING_LAUNCH` | 900 px/s | 15000 | Ceiling ring: downward speed. |
| `WALL_LOCK_TICKS` | 0.2 s | 12 | Left/right input ignored after a wall launch. |
| `RING_COOLDOWN_TICKS` | 0.167 s | 10 | A ring does not launch again within this time. |
| `BEAD_SPEED` | 1600 px/s | 26667 | Bead flight speed (visual; arrival tick). |
| `CAST_RANGE` | 800 px | 800000 | Maximum throw distance (20 tiles). |
| `CAST_STEP` | 2 px | 2000 | Ray marching step. |
| `DEATH_TICKS` | 0.5 s | 30 | Time between death and respawn. |
| `PLAYER_W`, `PLAYER_H` | 30 px, 32 px | 30000, 32000 | Player hitbox. |
| `HAZARD_INSET` | 4 px | 4000 | The player's hazard box is the hitbox shrunk by this on every side. |
| `RING_DEPTH` | 8 px | 8000 | Depth of a ring's trigger zone in front of its face. |
| `RING_INSET` | 4 px | 4000 | A ring zone is shorter than the face by this at both ends. |
| `SPIKE_INSET` | 4 px | 4000 | A spike's hitbox is narrower than the tile by this on both sides. |

Not in `MazeTuning` because they are not simulation values: `AIM_TIME_SCALE = 0.25` and `AIM_RAMP_S = 0.08` (4.4) are
constants of `MazeGame`.

Resulting level design metrics (checked by tests, 3.12): a full jump lifts the player's feet 3.1 to 3.6 tiles, a tap
jump 1.8 to 2.6 tiles, a floor ring 5.5 to 6.3 tiles; a running full jump clears a gap of 4 tiles at the same height.
Rule for level makers: a wall of 3 tiles can be jumped, 4 cannot; 5 tiles need a floor ring.

### 3.4 State (`MazeSim`)

```gdscript
class_name MazeSim extends RefCounted

var level: MazeLevel
var tick := 0                     # ticks stepped so far
var px := 0                       # player bottom-centre x, units
var py := 0                       # player bottom-centre y (feet), units
var prev_px := 0                  # position before the last step (for render interpolation)
var prev_py := 0
var vx := 0                       # units per tick
var vy := 0                       # units per tick, positive = down
var facing := 1                   # 1 right, -1 left
var grounded := false
var coyote := 0                   # ticks of coyote time left
var buffer := 0                   # ticks of jump buffer left
var jumping := false              # rising from a jump (for variable height and apex hang)
var launched := false             # rising from a ring launch (gravity up regardless of the jump button)
var lock_ticks := 0               # wall-launch input lock left
var dead_ticks := 0               # > 0 while dead
var deaths := 0
var beads_left := 0               # the supply
var rings_used := 0               # thrown rings that launched the player at least once (ADR 0009); never decreases
var rings: Array[Dictionary] = []   # {"cell": Vector2i, "face": int, "preset": bool, "order": int, "cooldown": int, "used": bool}
var flights: Array[Dictionary] = [] # {"cell": Vector2i, "face": int, "from": Vector2i, "to": Vector2i, "throw_tick": int, "arrive_tick": int, "order": int}
var throw_count := 0              # increasing order number for thrown beads
var clock_start := -1             # tick of the first active tick; -1 = clock not started
var finish_tick := -1             # -1 = not finished
var events: Array[Dictionary] = []  # events of the last step (3.9)

func _init(lvl: MazeLevel) -> void
func step(input: MazeInput) -> void
func cast(dir_index: int) -> Dictionary
func finished() -> bool                      # finish_tick >= 0
func time_ticks() -> int                     # 0 before the clock starts; running: tick - clock_start + 1; finished: finish_tick - clock_start + 1
func alive() -> bool                         # dead_ticks == 0
func snapshot() -> String                    # canonical text of every field above except level and events; for determinism tests
```

`beads_used()` no longer exists (ADR 0009); the score is the field `rings_used`. `snapshot()` includes `rings_used`
and every ring's `used`.

Faces: `MazeLevel.Face { UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3 }`, named after the direction the face points to
(`UP` = top face of a block = floor ring). In JSON: `"up"`, `"down"`, `"left"`, `"right"`.

`_init`: spawn (3.6), `beads_left = level.beads`, `rings_used = 0`, `rings` = the level's preset rings in file order
with `preset = true`, `order = -1` and `used = false`, everything else zero, `facing = 1`, `grounded` computed from the
spawn position. The flight's `from` is the cast origin and `to` the cast `hit` point (both in units), for drawing.

### 3.5 Input (`MazeInput`)

```gdscript
class_name MazeInput extends RefCounted
var move := 0             # -1, 0, 1
var jump_held := false
var jump_pressed := false # a jump press happened since the previous tick (latched by the controls)
var throw_dir := -1       # aim index 0..143, or -1
var undo := false
static func idle() -> MazeInput
func equals(other: MazeInput) -> bool
```

### 3.6 Geometry and collision

- Player box: `left = px - 15000`, `right = px + 15000`, `top = py - 32000`, `bottom = py`; half-open
  `[left, right) x [top, bottom)`.
- Cell `(cx, cy)` covers `[cx * TILE, (cx + 1) * TILE) x [cy * TILE, (cy + 1) * TILE)`.
- `solid(cx, cy)`: `#` or `X`, or `cx < 0`, `cx >= width` or `cy < 0` (out of bounds left, right, top). `cy >= height`
  is not solid.
- Spawn: `px = sx * TILE + TILE / 2`, `py = (sy + 1) * TILE` for `S` at `(sx, sy)`.
- Grounded: a solid cell overlaps `[left, right) x [bottom, bottom + 1)`.
- Spike hitbox for `^` at `(cx, cy)`: `[cx * TILE + 4000, (cx + 1) * TILE - 4000) x [cy * TILE + 20000, (cy + 1) * TILE)`.
- Hazard box: the player box shrunk by `HAZARD_INSET` on all four sides.
- Finish: the `F` cell's full rectangle overlaps the player box.
- Moving: first X, then Y. Speeds stay below one tile per tick (largest 18000 units), so a move only has to check the
  cells between the old and the new edge; no tunnelling.
  - X: `new_px = px + vx`. Moving right: the first solid cell in the columns from the old right edge's column to the new
    right edge's column (rows overlapped by `[top, bottom)`) stops the player at `px = cell_left - 15000`, `vx = 0`.
    Moving left mirrors this.
  - Y down: the first solid row under the feet stops the player at `py = cell_top`, `vy = 0`; that is a landing.
  - Y up: when the new head position overlaps solid cells, try corner correction: if all blocking cells lie only in the
    leftmost `CORNER_CORRECTION` units of the box (or only in the rightmost), and shifting the player right (or left) by
    exactly the overlap gives a free box at the new height, shift and keep `vy`. Otherwise `top = cell_bottom`
    (`py = cell_bottom + 32000`), `vy = 0`.

### 3.7 Ring zones and launch

Trigger zone of a ring on solid cell `(cx, cy)`, `T = TILE`, `D = RING_DEPTH`, `I = RING_INSET`:

| Face | Zone (half-open) | Launch |
|---|---|---|
| `UP` | `[cx*T + I, (cx+1)*T - I) x [cy*T - D, cy*T + 1)` | `vy = -FLOOR_LAUNCH` |
| `DOWN` | `[cx*T + I, (cx+1)*T - I) x [(cy+1)*T - 1, (cy+1)*T + D)` | `vy = CEILING_LAUNCH` |
| `LEFT` | `[cx*T - D, cx*T + 1) x [cy*T + I, (cy+1)*T - I)` | `vx = -WALL_LAUNCH_X`, `vy = mini(vy, -WALL_LAUNCH_LIFT)`, `lock_ticks = WALL_LOCK_TICKS`, `facing = -1` |
| `RIGHT` | `[(cx+1)*T - 1, (cx+1)*T + D) x [cy*T + I, (cy+1)*T - I)` | `vx = WALL_LAUNCH_X`, `vy = mini(vy, -WALL_LAUNCH_LIFT)`, `lock_ticks = WALL_LOCK_TICKS`, `facing = 1` |

Every launch also sets `launched = (face != DOWN)`, `jumping = false`, `coyote = 0`, `buffer = 0`, `grounded = false`
and the ring's `cooldown = RING_COOLDOWN_TICKS`. The zones reach 1 unit into the block, so standing on a floor ring or
pressing against a wall ring triggers it.

Counting (ADR 0009): when the launching ring has `preset == false` and `used == false`, set `used = true` and
`rings_used += 1`; the `launch` event then has `counted = true`, otherwise `counted = false`.

### 3.8 Step order

`step(input)` does, in this order (`events` is cleared first):

1. `tick += 1`; `prev_px = px`; `prev_py = py`. When finished: stop here.
2. Clock: when `clock_start < 0` and (`input.move != 0` or `input.jump_pressed`): `clock_start = tick`.
3. Undo: when `input.undo` and a thrown ring or flight exists: remove the one with the highest `order`;
   `beads_left += 1`; `rings_used` is not changed; event `undo`.
4. Throw: when `input.throw_dir >= 0`, alive and `beads_left > 0`: `t = cast(input.throw_dir)`. When valid:
   `beads_left -= 1`, add a flight with `order = throw_count`, `throw_count += 1`,
   `arrive_tick = tick + maxi(1, ceil_div(t.dist, BEAD_SPEED))`; start the clock as in step 2 if not started; event
   `throw`. When invalid (or dead, or no beads): event `throw_invalid` with the reason; nothing changes. A throw does
   not change `rings_used`.
5. Flights: each flight with `arrive_tick <= tick` becomes a ring (`preset = false`, same `order`, cooldown 0,
   `used = false`); event `ring`.
6. Ring cooldowns: every ring with `cooldown > 0` loses 1.
7. Dead: when `dead_ticks > 0`: `dead_ticks -= 1`; when it reaches 0: respawn (spawn position, `vx = vy = 0`,
   `facing = 1`, `jumping = launched = false`, `lock_ticks = coyote = buffer = 0`, `grounded` recomputed); event
   `respawn`. Then stop here.
8. Horizontal speed (`approach(v, target, rate)` moves `v` towards `target` by at most `rate`), `target = move * RUN_SPEED`:
   - `lock_ticks > 0`: `lock_ticks -= 1`; `vx` unchanged.
   - grounded: input in the motion direction (or `vx == 0`) and `abs(vx) <= RUN_SPEED`: `approach(vx, target,
     GROUND_ACCEL)`; otherwise `approach(vx, target, GROUND_DECEL)`.
   - air: `move == 0`: `approach(vx, 0, AIR_DRAG)`; input in the motion direction (or `vx == 0`): `AIR_ACCEL` when
     `abs(vx) <= RUN_SPEED`, else `AIR_DRAG`; input opposite to the motion: `AIR_TURN`.
   - When not locked and `move != 0`: `facing = move`.
9. Jump (read, then update; see section 14): first read `can_jump = grounded or coyote > 0` and `wants_jump =
   input.jump_pressed or buffer > 0`, with `coyote` and `buffer` as the previous tick left them. Then
   `coyote = COYOTE_TICKS` when grounded, else `maxi(0, coyote - 1)`, and `buffer = JUMP_BUFFER_TICKS` when
   `input.jump_pressed`, else `maxi(0, buffer - 1)`. When `can_jump and wants_jump`: `vy = -JUMP_SPEED`,
   `jumping = true`, `launched = false`, `buffer = coyote = 0`, `grounded = false`; event `jump`.
10. Gravity: `g = APEX_GRAVITY` when `jumping and input.jump_held and abs(vy) < APEX_THRESHOLD`; else `GRAVITY_UP` when
    `vy < 0` and ((`jumping` and `input.jump_held`) or `launched`); else `GRAVITY_DOWN`. `vy = mini(vy + g, MAX_FALL)`.
11. Move X, then Y, with collision (3.6). On landing: `jumping = launched = false`; event `land` when the player was
    not grounded before. Then `grounded` is recomputed. `jumping = false` when `vy >= APEX_THRESHOLD`;
    `launched = false` when `vy >= 0`.
12. Rings: walk `rings` in list order (presets first, then by `order`); the first ring with `cooldown == 0` whose zone
    overlaps the player box launches (3.7) and is counted when it is a thrown ring not yet used (3.7); event `launch`.
    At most one launch per tick.
13. Hazards: when the hazard box overlaps a spike hitbox or `top >= height * TILE`: `dead_ticks = DEATH_TICKS`,
    `deaths += 1`, `vx = vy = 0`; event `death`. Stop here.
14. Finish: when the player box overlaps the finish cell: `finish_tick = tick`; when the clock had not started,
    `clock_start = tick`; event `finish`.

`ceil_div(a, b)` is `(a + b - 1) / b` for positive integers.

### 3.9 Events

Each event is a Dictionary with `"type"` and extra fields: `jump`, `land`, `launch` (`cell`, `face`, `counted`),
`death`, `respawn`, `throw` (`cell`, `face`, `order`), `throw_invalid` (`reason`), `ring` (`cell`, `face`), `undo`
(`order`), `finish` (`ticks`, `rings`). The view uses them for short effects; the game screen uses `finish`. Events
never feed back into the simulation.

### 3.10 Cast (`MazeSim.cast`)

`cast(dir_index) -> Dictionary` is a pure query on the current state; the aim preview calls it every frame and step 4
calls it at the throw. Result keys: `valid` (bool), `reason` (`"ok"`, `"none"`, `"no_ring"`, `"hazard"`, `"taken"`,
`"no_beads"`, `"dead"`), `cell` (Vector2i), `face` (int), `origin` (Vector2i, units), `hit` (Vector2i, units, last free
sample point, for drawing), `dist` (int, units).

1. `reason = "dead"` when not alive; `"no_beads"` when `beads_left == 0` (other keys still filled by the march, so the
   line can be drawn dimmed; `valid` is false).
2. Origin `o = (px, py - 16000)` (player centre). Direction `d = MazeAim.dir(dir_index)` (components scaled by 10000).
3. For `k = 1 .. CAST_RANGE / CAST_STEP`: `p = o + d * (k * CAST_STEP) / 10000` per component (integer division).
   Cell of `p`: `floori(p / TILE)` per component, computed with integers (for negative `p` the cell is negative, which
   is out of bounds and solid). The first sample whose cell is solid is the hit; `hit` = the previous sample (or `o`),
   `prev` = its cell.
4. No hit within range: `reason = "none"`, `valid = false`, `hit` = the last sample.
5. Face: when only `x` differs between `prev` and the hit cell: `LEFT` if the hit cell is to the right of `prev`, else
   `RIGHT`. When only `y` differs: `UP` if the hit cell is below `prev`, else `DOWN`. When both differ (a corner):
   vertical face (`UP`/`DOWN`) when `abs(d.y) >= abs(d.x)`, else horizontal.
6. Invalid (`valid = false`) when: the hit cell is `X` or out of bounds (`"no_ring"`); the cell in front of the face is
   solid (`"no_ring"`, face not exposed) or a spike (`"hazard"`); a ring or flight already has this cell and face
   (`"taken"`). Otherwise `valid = true`, `reason = "ok"` (unless step 1 set a reason).
7. `dist = k * CAST_STEP` of the hit sample.

### 3.11 Aim directions (`MazeAim`)

- `STEPS = 144`; index `i` is the angle `i * 2.5` degrees, counter-clockwise on screen from pointing right
  (index 36 points up, 72 left, 108 down).
- `DIRS`: a literal constant `Array[Vector2i]` of 144 entries,
  `Vector2i(roundi(cos(a) * 10000), -roundi(sin(a) * 10000))`. Generated once (for example by a throw-away script),
  pasted as a literal, and checked by a test against `cos`/`sin` within 1. The simulation never calls `cos` or `sin`.
- `static func dir(i: int) -> Vector2i` (`DIRS[posmod(i, 144)]`).
- `static func index_from_vector(v: Vector2) -> int`: `posmod(roundi(rad_to_deg(atan2(-v.y, v.x)) / 2.5), 144)`; a zero
  vector gives -1. Used by mouse and touch only (UI side; the index is what the simulation gets).
- `static func keyboard_index(facing: int, elevation: int) -> int`: `elevation` from -6 to 6 in 15 degree steps;
  facing right `posmod(elevation * 6, 144)`, facing left `posmod(72 - elevation * 6, 144)`.

### 3.12 Acceptance (simulation)

- S1 Every literal in `MazeTuning` equals the conversion of its readable value (3.2).
- S2 On a flat test map, holding right from standstill reaches `RUN_SPEED` within 8 ticks and never exceeds it;
  releasing stops the player within 7 ticks.
- S3 Full jump (jump held until landing) lifts the feet 3.1 to 3.6 tiles; tap jump (held 1 tick) 1.8 to 2.6 tiles.
- S4 Coyote: a jump pressed 6 ticks after walking off a ledge jumps; 7 ticks after does not.
- S5 Buffer: a jump pressed 8 ticks before the landing tick jumps on landing; 9 ticks before does not.
- S6 Corner correction: rising with the head overlapping a ceiling corner by 6 px moves the player sideways and keeps
  rising; by 10 px stops the rise.
- S7 Falling speed never exceeds `MAX_FALL`; walking into a wall at full speed stops at the wall without overlap; at
  every tick of every test the player box overlaps no solid cell.
- S8 Floor ring lifts the feet 5.5 to 6.3 tiles, the same with jump held or not, and with any incoming vertical speed.
- S9 Wall ring on a `RIGHT` face: after the launch `vx == WALL_LAUNCH_X`, `vy <= -WALL_LAUNCH_LIFT`, and holding left
  for the next 12 ticks does not change `vx`; at tick 13 it does. Mirror for `LEFT`.
- S10 Ceiling ring: `vy == CEILING_LAUNCH` after the launch.
- S11 A ring launches at most once per 10 ticks; two overlapping rings give one launch per tick (the first in order).
- S12 Throw: a valid throw lowers `beads_left` by 1, leaves `rings_used` unchanged, and creates the ring at
  `arrive_tick`; each invalid case of 3.10 (`X` face, out of bounds, unexposed face, spike in front, taken face, no
  beads, out of range, while dead) changes nothing and reports its reason.
- S13 Throwing straight down (index 108) while standing creates a floor ring under the player that launches it; after
  that launch `rings_used == 1`.
- S14 Undo removes the latest thrown ring or flight (not a preset), returns its bead, leaves `rings_used` unchanged,
  and with nothing thrown changes nothing.
- S15 Death by spike and by falling out: the player respawns after exactly 30 ticks at the spawn; rings, beads,
  `rings_used` and the clock are unchanged by the death; `deaths` counts.
- S16 Clock: before any input `time_ticks() == 0`; the first move starts it; after the finish `time_ticks()` stays
  fixed and further steps change nothing in `snapshot()` except `tick`.
- S17 Determinism: the same level and input sequence give equal `snapshot()` after every tick, in two separate runs;
  `snapshot()` contains `rings_used` and each ring's `used`.
- S18 `MazeAim`: 144 entries, index 0 is `(10000, 0)`, 36 is `(0, -10000)`, every entry within 1 of `cos`/`sin`;
  `keyboard_index` and `index_from_vector` give the values of 3.11 for at least eight hand-picked cases.
- S19 Rings used (ADR 0009), each on a small fixture map:
  - a) A thrown ring that lands and never touches the player: `rings_used == 0`; undo then returns the bead and
    `rings_used` stays 0.
  - b) A bead taken back while in flight: `rings_used == 0`.
  - c) Standing on an own floor ring and bouncing on it at least three times: `rings_used == 1`; only the first
    `launch` event has `counted == true`.
  - d) Undo after the launch: `beads_left == level.beads` again, `rings_used` stays 1; throwing again to the same face
    and launching from it gives `rings_used == 2`.
  - e) A preset ring launching the player: `rings_used == 0` and `counted == false`.
  - f) Misuse case: a level with `beads` 1; three cycles of throw, launch, undo end with `beads_left == 1` and
    `rings_used == 3` (with the old rule this was 0).
  - g) A death after a counted launch leaves `rings_used` unchanged; a new `MazeSim` on the same level starts at 0.
  - h) The `finish` event carries `rings` equal to `rings_used` at the finish tick.

## 4. Controls

### 4.1 Intent

`MazeControls` (`ui/controls.gd`, `RefCounted`) merges keyboard, mouse and touch into one intent that the game screen
samples once per simulation tick:

```gdscript
func move() -> int                     # keyboard right - left when non-zero, else the touch move
func jump_held() -> bool               # keyboard or touch
func take_jump_pressed() -> bool       # latched press since the last call
func aiming() -> bool
func aim_index() -> int                # valid while aiming
func take_throw() -> int               # latched throw index, or -1
func take_undo() -> bool
func take_restart() -> bool
func take_pause() -> bool
func cancel_aim() -> void              # used on death, finish, pause
func handle_event(event: InputEvent) -> bool   # keyboard and mouse; true when used
func set_facing(f: int) -> void        # the player's facing, for keyboard aiming
func set_player_screen_pos(p: Vector2) -> void # for mouse aiming
func set_can_aim(ok: bool) -> void     # false while dead, finished, paused or without beads
# touch overlay calls:
func touch_move(m: int) -> void
func touch_jump(down: bool) -> void
func touch_aim(active: bool, index: int) -> void
func touch_throw(index: int) -> void
```

Latched events (jump press, throw, undo) survive frames without a tick (slow motion) and are consumed by the next tick
(ADR 0003). `MazeGame` builds a `MazeInput` per tick from these calls.

### 4.2 Keyboard (primary)

Input actions (defined in `project.godot`):

| Action | Keys | Effect |
|---|---|---|
| `move_left`, `move_right` | `A`, `Left` / `D`, `Right` | Walk. |
| `jump` | `Space`, `W`, `Up` | Jump; hold for a higher jump. While aiming only `Space` jumps. |
| `aim` | `J` | Hold: aim (line, slow motion). Release: throw. |
| `aim_up`, `aim_down` | `W`, `Up` / `S`, `Down` | While aiming: 15 degrees up / down; held keys repeat after 0.25 s every 0.1 s (real time). |
| `aim_cancel` | `K` | Cancel the aim; releasing `J` then throws nothing. `Esc` also cancels while aiming. |
| `undo` | `Z`, `Backspace` | Bead back. |
| `restart` | `R` | Restart the level. |
| `pause` | `Esc`, `P` | Pause / resume (`Esc` cancels an aim first). |

Keyboard aim: the elevation starts at +3 (45 degrees up) for each attempt and keeps its last value within the attempt;
the direction is `MazeAim.keyboard_index(facing, elevation)` with the player's current facing, so walking the other way
mirrors the line. Elevation is clamped to -6..6. Aiming cannot start while `set_can_aim(false)`.

### 4.3 Mouse (optional)

- Left button down (not an emulated event, `event.device != InputEvent.DEVICE_ID_EMULATION`): start aiming; the index
  follows `index_from_vector(mouse - player_screen_pos)`. Release: throw. Right button while aiming: cancel.
- Mouse events emulated from touch are ignored, so touch never aims through the mouse path. Project setting
  `input_devices/pointing/emulate_mouse_from_touch` stays `true` (UI buttons need it);
  `emulate_touch_from_mouse` stays `false`.

### 4.4 Slow motion while aiming (ADR 0003)

- While `aiming()` is true, the target rate is `AIM_TIME_SCALE = 0.25`, else 1. The current rate moves towards the
  target linearly over `AIM_RAMP_S = 0.08` s real time:
  `rate = move_toward(rate, target, delta * (1.0 - AIM_TIME_SCALE) / AIM_RAMP_S)` (`static func next_rate(rate: float,
  aiming: bool, delta: float) -> float` on `MazeGame`, testable). Paused: 0.
- The simulation itself is unchanged: `MazeGame` accumulates `acc += minf(delta, 0.1) * rate` and steps while
  `acc >= 1/60`, at most 6 steps per frame. So slow motion means fewer ticks per real second, never a different tick.
- Rendering interpolates between `prev` and current positions with `alpha = acc * 60`, so slow motion looks smooth.
- While the rate is below 1 the world (not the HUD) is drawn at 85 % brightness (`modulate`).
- The game clock counts ticks, so it also runs at a quarter of its speed while aiming.

### 4.5 Aim preview

While aiming, the world view draws every frame, from `sim.cast(aim_index())`:

- a dotted line (`TEXT` colour, 70 % alpha, dots 3 px every 14 px) from the player centre to `hit`;
- valid: a dashed ring outline on the target face plus a faint arrow in the launch direction;
- invalid: the line in `DIM` colour and a small cross at `hit`; with reason `"none"` the line runs the full range.

### 4.6 Touch (ADR 0006)

`MazeTouchOverlay` (`ui/touch_overlay.gd`, a full-rect `Control` on its own `CanvasLayer`, `mouse_filter = IGNORE`)
reads `InputEventScreenTouch` and `InputEventScreenDrag` in `_input` (through `handle_event(event) -> bool`, testable)
and tracks fingers by index. Each finger gets a role at touch-down that lasts until it is lifted. Positions are in
viewport units; `ins` = safe area insets (`WhiteSafeArea.insets`), `W x H` = viewport size; the top band is
`y < 110 + ins.top` (HUD; touches there are ignored by the overlay).

| Control | Place | Behaviour |
|---|---|---|
| Jump button | centre `(W - 130 - ins.right, H - 130 - ins.bottom)`, radius 80, hit radius 100 | Held while the finger is down; touch-down is a press. |
| Throw stick | centre `(W - 340 - ins.right, H - 120 - ins.bottom)`, radius 72, hit radius 95 | Drag beyond the dead zone (26 px from the centre) = aiming, index = `index_from_vector(finger - centre)`, knob follows up to 72 px. Back inside the dead zone = not aiming (line hidden, normal speed). Lift while aiming = throw; lift inside the dead zone = nothing. A short tap does nothing. |
| Move stick | anywhere with `x < 0.45 * W` outside the top band; floating | The base appears at the touch-down point (radius 96); the knob follows within 70 px. Horizontal only: `dx > 20` is right, `dx < -20` left, else none. When the finger moves more than 110 px from the base, the base follows it (stays 110 px behind). |

- Role assignment order at touch-down: jump button, throw stick, move zone, else ignored.
- Drawn as in the mockup (`docs/ideas/2026-11-20-platformer-r2-white-cast.html`): faint white circles, knob 36 px,
  labels under each control in `DIM`, font 20 (`ctl_move`, `ctl_throw`, `ctl_jump` texts). The move stick is drawn at
  its default place `(200 + ins.left, H - 170 - ins.bottom)` with 50 % alpha when no finger is on it. Without beads
  the throw stick is drawn at 40 % alpha and does not aim.
- Visible when touch mode is on: at start when `DisplayServer.is_touchscreen_available()` or `--touch`; any screen
  touch turns it on; any key press turns it off (not with `--touch`).
- Jumping and aiming use the same thumb on purpose: jump first, then aim in slow motion in the air.

### 4.7 Acceptance (controls)

- C1 Keyboard: the actions of 4.2 give the intents; `W`/`Up` jump when not aiming and turn the aim while aiming;
  `Space` always jumps.
- C2 A jump press and release between two ticks still gives `jump_pressed` on the next tick; a throw and an undo are
  latched the same way and consumed once.
- C3 Keyboard aim: start index for facing right is 18 (45 degrees), for facing left 54; up/down change the index by 6
  per step and stop at elevation +-6; `K` and `Esc` cancel so releasing `J` throws nothing.
- C4 Mouse: left press/release throws towards the cursor; right button cancels; emulated mouse events are ignored.
- C5 Touch (synthetic events into `MazeTouchOverlay.handle_event`): a touch in the left zone and a drag of +30 px gives
  move 1, of +10 px move 0; a touch on the jump button gives a press and held until lifted; a drag on the throw stick
  of 50 px to the upper right gives aiming with index 18 (within 1); lifting there throws; dragging back into the dead
  zone and lifting throws nothing; a touch in the top band is ignored; two fingers (move and jump) work at the same
  time.
- C6 Slow motion: `next_rate` reaches 0.25 within 0.08 s of aiming and 1.0 within 0.08 s after; the number of ticks
  over one real second of aiming is 15 (within 1).

## 5. Levels

### 5.1 Format (ADR 0004)

One JSON file per level, `levels/<id>.json`, made by hand in a text editor:

```json
{
  "format": 1,
  "id": "l001",
  "name": {"nl": "Eerste ring", "en": "First ring"},
  "difficulty": "easy",
  "beads": 3,
  "par": 1,
  "hint": {"nl": "...", "en": "..."},
  "rings": [{"x": 26, "y": 11, "face": "up"}],
  "rows": [
    "################################################",
    "..."
  ]
}
```

| Field | Rule |
|---|---|
| `format` | 1. |
| `id` | `^[a-z0-9-]{1,32}$`, equal to the file name without `.json`. Stable: statistics are keyed by it. |
| `name` | Object with non-empty `nl` and `en`. |
| `difficulty` | `easy`, `medium` or `hard` (label from the kit text `levels`). |
| `beads` | Integer 1 to 9; default 3 when absent. The bead supply of the level, a design choice per level (ADR 0009). |
| `par` | Integer 0 to 20: the fewest rings used the designer needs (ADR 0009). Independent of `beads`; may be larger, because a bead can be taken back and thrown again. |
| `hint` | Optional object with `nl` and `en`; may contain `{move}`, `{jump}`, `{throw}`, `{undo}` (8.6). |
| `rings` | Optional list of preset rings: `x`, `y` of a `#` cell and `face`; the face must be exposed (cell in front not solid, not a spike); no duplicates. |
| `rows` | Strings, top row first, all the same length; width 8 to 256, height 8 to 64; characters `. # X ^ S F`; exactly one `S` with a solid cell below it; exactly one `F`. |

`levels/index.json` lists the series in order: `{"format": 1, "levels": ["l001", ..., "l009"]}`.

The level `format` stays 1: `par` keeps its type and only its upper bound and meaning change, and every shipped level
(l001 to l003) has the same par under both readings (5.4); l004 to l009 are made for the new reading (section 17).

### 5.2 Loading and validation

```gdscript
class_name MazeLevel extends RefCounted
enum Cell { EMPTY, SOLID, NO_RING, SPIKE }
enum Face { UP, DOWN, LEFT, RIGHT }
const MAX_PAR := 20
var id := ""
var names := {}                 # {"nl": ..., "en": ...}
var difficulty := 0             # 0 easy, 1 medium, 2 hard
var beads := 3
var par := 0
var hints := {}                 # {} or {"nl": ..., "en": ...}
var width := 0
var height := 0
var cells := PackedByteArray()  # Cell per (x, y), index y * width + x; S and F are EMPTY
var spawn := Vector2i()         # the S cell
var finish := Vector2i()        # the F cell
var preset_rings: Array[Dictionary] = []   # {"cell": Vector2i, "face": int}
var errors := PackedStringArray()
static func from_dict(d: Variant) -> MazeLevel   # never null; errors filled when invalid
func valid() -> bool                             # errors.is_empty()
func cell(x: int, y: int) -> int                 # out of bounds left/right/top: NO_RING; below: EMPTY
func solid(x: int, y: int) -> bool
func render() -> PackedStringArray               # rows back as text (S and F at their cells)
```

```gdscript
class_name MazeLevels extends RefCounted
const DIR := "res://levels/"
static func ids() -> PackedStringArray           # from index.json; [] when missing or bad
static func load_level(id: String) -> MazeLevel  # from DIR + id + ".json"; a missing file gives a level with an error
```

- JSON is read with `WhitePuzzleStore.load_json(path)` (cached, no error output on bad files).
- Error texts are English, one per problem, with coordinates where useful, for example
  `row 3 has length 47, expected 48`, `unknown character 'Q' at (5, 2)`, `need exactly one S, found 2`,
  `nothing solid below S at (2, 10)`, `par 21 is outside 0..20`, `ring at (4, 11) up is not on a # block`,
  `id 'l1' does not match file name 'l001'` (the file name check is done by `load_level`).
- The game shows only valid levels; an invalid level in the index is shown as locked with no name and logged with
  `push_error` (the tests and the check tool make sure this never ships).

### 5.3 How levels are made

1. Copy an existing level file, give it a new id, add the id to `levels/index.json`.
2. Edit `rows` in a text editor (monospace); use the metrics of 3.3. Choose `beads` (the supply) and `par` (the fewest
   rings used your own route needs) separately.
3. Check: `godot --headless --path . -s res://tools/check_levels.gd` (5.5).
4. Play it directly: `godot --path . -- --level=<id> --print-run`; at the finish the run script is printed (6.3).
5. Paste that script into `tests/solutions.json` under the id; the solution test (11.2) then keeps it solvable.

A visual editor (for example importing a `TileMapLayer` scene) is **[later]**.

### 5.4 The levels

Rows are given in blocks of 8 columns for readability; the JSON row is the concatenation without spaces. The level
check verifies lengths. Intended solutions are the designer's; the solution tests (11.2) prove that each level can be
finished within par (rings used <= par). If the tuning makes a level impossible or clearly cheaper than par, the
developer adjusts the geometry (not the tuning), and records the change in the log and in this section.

Par of l001 to l003 is unchanged by ADR 0009: their intended routes throw only rings they bounce off and take none
back, so rings used equals the old beads used.

**l001, "Eerste ring" / "First ring", easy, beads 3, par 1** (48 x 14), preset ring `{"x": 26, "y": 11, "face": "up"}`

```
            0-7      8-15     16-23    24-31    32-39    40-47
row  0      ######## ######## ######## ######## ######## ########
row  1      #....... ........ ........ ........ ........ .......#
row  2      #....... ........ ........ ........ ........ .......#
row  3      #....... ........ ........ ........ ........ .......#
row  4      #....... ........ ........ ........ ........ .......#
row  5      #....... ........ ........ ........ ........ ....F..#
row  6      #....... ........ ........ ....#### ##...... ########
row  7      #....... ........ ........ ....#### ##...... ########
row  8      #....... ........ ........ ....#### ##...... ########
row  9      #....... ........ ........ ....#### ##...... ########
row 10      #.S..... ........ ....###. ....#### ##...... ########
row 11      ######## #####... ######## ######## ######## ########
row 12      ######## #####^^^ ######## ######## ######## ########
row 13      ######## ######## ######## ######## ######## ########
```

Teaches: walking, a 3-wide spike pit, a step, the preset floor ring over a 5-high wall, then one own floor ring in front
of the second 5-high wall (for example on cell (38, 11)). Hint: nl "Loop met {move}, spring met {jump}. Stap op de
ring. Bij de tweede muur werp je zelf een kraal: {throw}." en "Walk with {move}, jump with {jump}. Step on the ring. At
the second wall, throw a bead yourself: {throw}."

**l002, "Opzij" / "Sideways", medium, beads 3, par 2** (40 x 14), preset ring `{"x": 1, "y": 11, "face": "up"}`

```
            0-7      8-15     16-23    24-31    32-39
row  0      ######## ######## ######## ######## ########
row  1      #....... ........ ........ ........ .......#
row  2      #....... ........ ........ ........ .......#
row  3      #....... ........ ........ ........ .......#
row  4      #....... ........ ........ ........ .......#
row  5      #....... ........ ........ ........ ..F....#
row  6      #....... ........ ........ ######## ########
row  7      #....... ........ ........ ######## ########
row  8      #....... ........ ........ ######## ########
row  9      #....... ........ ........ ######## ########
row 10      #.S..... ........ ........ ######## ########
row 11      ###..... ..###### ######## ######## ########
row 12      ###^^^^^ ^^###### ######## ######## ########
row 13      ######## ######## ######## ######## ########
```

Teaches the wall ring: throw a bead high on the left wall (cell (0, 4) or (0, 5), face right), step left onto the
preset floor ring, rise along the wall, touch the wall ring and fly right over the 7-wide pit; then a floor ring in
front of the big wall (for example (22, 11)). Hint: nl "Een ring op een muur duwt je opzij. Schiet omhoog langs de
muur en raak je ring." en "A ring on a wall pushes you sideways. Shoot up along the wall and hit your ring."

**l003, "Smalle pilaar" / "Narrow pillar", hard, beads 3, par 3** (48 x 14), no preset rings

```
            0-7      8-15     16-23    24-31    32-39    40-47
row  0      ######## ######## ######## ######## ######## ########
row  1      #....... ........ ........ ........ ........ .......#
row  2      #....... ........ ........ ........ ........ .......#
row  3      #....... ........ ........ ........ ........ .......#
row  4      #....... ........ ........ ........ ........ .......#
row  5      X....... ........ ........ ........ ........ F......#
row  6      X....... ........ ........ ....#### ######## ########
row  7      X....... ........ ........ ....#### ######## ########
row  8      X....... ........ ........ ....#### ######## ########
row  9      X....... ........ ........ ....#### ######## ########
row 10      X.S..... ........ ........ ....#### ######## ########
row 11      ###..... ..###### ####^^^^ #^^^#### ######## ########
row 12      ###^^^^^ ^^###### ######## ######## ######## ########
row 13      ######## ######## ######## ######## ######## ########
```

Combines both: the lower left wall is `X`, so the wall ring must go high (cells (0, 1) to (0, 4)); an own floor ring
at (1, 11) replaces l002's preset; then a precise jump onto the one-tile pillar at (24, 11) between spikes and a floor
ring on the pillar to get over the last 5-high wall. Hint: nl "Op donkere blokken blijft geen kraal hangen." en "Beads
do not stick to dark blocks."

**l004, "Eén kraal" / "One bead", easy, beads 1, par 3** (48 x 14), no preset rings

```
            0-7      8-15     16-23    24-31    32-39    40-47
row  0      ######## ######## ######## ######## ######## ########
row  1      #....... ........ ........ ........ ........ .......#
row  2      #....... ........ ........ ........ ........ .......#
row  3      #....... ........ ........ ........ ........ .......#
row  4      #....... ........ ........ ........ ........ .......#
row  5      #....... ........ ........ ........ ........ ...F...#
row  6      #....... .###.... .....### ........ ######## ########
row  7      #....... .###.... .....### ........ ######## ########
row  8      #....... .###.... .....### ........ ######## ########
row  9      #....... .###.... .....### ........ ######## ########
row 10      #.S..... .###.... .....### ........ ######## ########
row 11      ######## ######## ..###### ######## ######## ########
row 12      ######## ######## ^^###### ######## ######## ########
row 13      ######## ######## ######## ######## ######## ########
```

Teaches bead back (`Z`): three walls of 5 tiles, one bead. Throw a floor ring in front of a wall, bounce over it, take
the ring back, throw the next one. Hint: nl "Je hebt één kraal. Gebruikt? Haal hem terug met {undo}." en "One bead.
Used it? Take it back with {undo}."

**l005, "Schoorsteen" / "Chimney", medium, beads 3, par 2** (32 x 18), preset ring `{"x": 22, "y": 16, "face": "up"}`

```
            0-7      8-15     16-23    24-31
row  0      ######## ######## ######## ########
row  1      #....... ........ ........ ..######
row  2      #....... ........ ........ ..######
row  3      #....... ........ ........ ..######
row  4      #....... ........ ........ ..######
row  5      #....... ........ ........ ..######
row  6      #....... ........ ........ ..######
row  7      #....F.. ........ ........ ..######
row  8      ######## ######## ######.. ..######
row  9      ######## ######## ######.. ..######
row 10      ######## ######## ######.. ..######
row 11      ######## ######## ######.. ..######
row 12      ######## ######## ######.. ..######
row 13      ######## ######## ######.. ..######
row 14      ######## ######## ######.. .......#
row 15      ######## ######## ######.. .....S.#
row 16      ######## ######## ######## ########
row 17      ######## ######## ######## ########
```

Teaches bouncing between two walls of a 4-wide shaft: the preset floor ring lifts the player along the left wall, a
wall ring on (21, 9) throws it right, a wall ring on (26, 9) back left over the edge of the plateau (rows 8 and 9 both
work for the second ring). Hint: nl "Ringen op allebei de muren: kaats omhoog." en "Rings on both walls: bounce your way
up."

**l006, "Torens" / "Towers", medium, beads 3, par 4** (32 x 24), no preset rings

```
            0-7      8-15     16-23    24-31
row  0      ######## ######## ######## ########
row  1      #....... ........ ........ .......#
row  2      #....... ........ ........ .......#
row  3      #....... ........ ........ .......#
row  4      #....... ........ ........ ...F...#
row  5      #....... ........ .....### ########
row  6      #....... ........ .....### ########
row  7      #....... ........ .....### ########
row  8      #....... ........ .....### ########
row  9      #....... ........ .#...### ########
row 10      #....... ........ .#...### ########
row 11      #....... ........ .#...### ########
row 12      #....... ........ .#...### ########
row 13      #....... .....#.. .#...### ########
row 14      #....... .....#.. .#...### ########
row 15      #....... .....#.. .#...### ########
row 16      #....... .....#.. .#...### ########
row 17      #....... .#...#.. .#...### ########
row 18      #....... .#...#.. .#...### ########
row 19      #....... .#...#.. .#...### ########
row 20      #.S..... .#...#.. .#...### ########
row 21      ######.. .#...#.. .#...### ########
row 22      ######^^ ^#^^^#^^ ^#^^^### ########
row 23      ######## ######## ######## ########
```

Teaches precision and reuse: three towers of one tile, each 4 higher than the last, over spikes. Four floor rings are
needed with three beads, so the ring on the middle tower is taken back once it has launched. Throw the ring on a tower
while still falling onto it (it launches on touch). Hint: nl "Sta op een toren en werp recht omlaag. Op? {undo}." en
"Stand on a tower and throw straight down. Out of beads? {undo}."

**l007, "Opvangen" / "Catch", medium, beads 3, par 2** (36 x 18), no preset rings

```
            0-7      8-15     16-23    24-31    32-35
row  0      ######## ######## ######## ######## ####
row  1      ######## ###..... ........ ........ ...#
row  2      ######## ###..... ........ ........ ...#
row  3      ######## ###..... ........ ........ ...#
row  4      ######## ###..... ........ ........ ...#
row  5      ######## ###..... ........ ........ ...#
row  6      #....... ........ ........ ........ F..#
row  7      #.S..... ........ ........ ....#### ####
row  8      ######## ###..... ........ ....#### ####
row  9      ######## ###..... ........ ....#### ####
row 10      ######## ###..... ........ ....#### ####
row 11      ######## ###..... ........ ....#### ####
row 12      ######## ###..... ...##### ######## ####
row 13      ######## ###..... ...##### ######## ####
row 14      ######## ###..... ...##### ######## ####
row 15      ######## ###..... ...##### ######## ####
row 16      ######## ###^^^^^ ^^^##### ######## ####
row 17      ######## ######## ######## ######## ####
```

Teaches catching a fall: walk off the end of the low tunnel, throw a bead at the wall ring cell (10, 9) while sliding
down along that wall (row 9: the player is level with it a moment after stepping off, one row lower is too late); the wall
ring throws the player over the 8-wide pit. Then a floor ring on (27, 12) for the 5-high wall. Hint: nl "Val langs de muur en werp
terug. Een muurring vangt je op." en "Fall along the wall and throw back. A wall ring catches you."

**l008, "Vaart" / "Momentum", hard, beads 3, par 2** (40 x 16), preset ring `{"x": 1, "y": 13, "face": "up"}`

```
            0-7      8-15     16-23    24-31    32-39
row  0      ######## ######## ######## ######## ########
row  1      #....... ........ ........ ........ .......#
row  2      #....... ........ ........ ........ .......#
row  3      #....... ........ ........ ........ .......#
row  4      #....... ........ ........ ........ .......#
row  5      #....... ........ ........ ........ .......#
row  6      #....... ........ ........ ........ .......#
row  7      #....... ........ ........ ........ ....F..#
row  8      #....... ........ .####### ######## ########
row  9      #....... ........ .####### ######## ########
row 10      #....... ........ .####### ######## ########
row 11      #....... ........ .####### ######## ########
row 12      #...S... ........ .####### ######## ########
row 13      ######## ###..... .####### ######## ########
row 14      ######## ###^^^^^ ^####### ######## ########
row 15      ######## ######## ######## ######## ########
```

Teaches that a floor ring keeps the horizontal speed: the preset ring and a wall ring on (0, 6) (near the apex of the climb;
the ring on row 7 fires too early and lands short) throw the player over the
ground at about 500 px/s; a floor ring on (10, 13), thrown during the flight, carries that speed over the 6-wide pit
onto the ledge. Hint: nl "Een vloerring houdt je vaart vast. Land er vliegend op." en "A floor ring keeps your speed.
Land on it while flying."

**l009, "Opruimen" / "Tidy up", hard, beads 3, par 4** (40 x 16), no preset rings

```
            0-7      8-15     16-23    24-31    32-39
row  0      ######## ######## ######## ######## ########
row  1      X....... ........ ........ ........ .......#
row  2      X....... ........ ........ ........ .......#
row  3      X....... ........ ........ ........ .......#
row  4      X....... ........ ........ ........ .......#
row  5      X....... ........ ........ ........ .......#
row  6      X....... ..#..... ........ ........ .......#
row  7      X....... ..X..... ........ ........ ....F..#
row  8      X....... .#X..... ........ ...##### ########
row  9      X....... .#X..... ........ ...##### ########
row 10      X....... .#X..... ........ ...##### ########
row 11      X....... .#X..... ........ ...##### ########
row 12      X..S.... .#X..... ........ ...##### ########
row 13      ######## ######## #####... ...##### ########
row 14      ######## ######## #####^^^ ^^^##### ########
row 15      ######## ######## ######## ######## ########
```

The finale. Ring T on (8, 13) lifts the player over the stepped wall (columns 9 and 10; below its top cell column 10
is `X`); then l008 without a preset:
floor ring F1 (11, 13), wall ring W1 (10, 6) and floor ring K (20, 13). Four rings, three beads, so T must be taken
back before F1 and W1 are thrown; the left wall is `X` (no flight from the start). Hint: nl "Ruim op wat je niet meer
nodig hebt. {undo} pakt altijd de laatste." en "Clear away what you no longer need. {undo} always takes the last
one."

Par of l004 to l009 is the number of rings used by the stored solution, counted as in ADR 0009 (section 17).

### 5.5 Level check tool (`tools/check_levels.gd`, `extends SceneTree`)

For every id in the index: load, validate, print `ok <id> <w>x<h> beads <b> par <p>` or each error as
`error <id>: <text>`. When `tests/solutions.json` has the id: run the script with `MazeRunScript.run` (at most 36000
ticks) and print `solution <id> finished ticks <t> rings <r>` or `solution <id> FAILED <reason>`; a solution whose
`rings_used` is above par fails with the reason `used <r> rings, par is <p>`. Also reports ids in the index without a
file and level files not in the index. Exit code 1 on any error or failed solution, else 0. Optional `--dir=<path>`
checks another level folder (for tests).

### 5.6 Acceptance (levels)

- L1 The nine shipped levels and the index are valid; `render()` gives the file rows back.
- L2 Each validation rule of 5.1 has a test with a minimal bad level that produces exactly its error (at least 14
  cases), and no case produces engine error output. The par cases are: `par` -1 and 21 give `par <v> is outside
  0..20`; `par` 3 with `beads` 1 is valid (par may exceed beads).
- L3 `cell()` outside the grid: left, right, top `NO_RING`; below `EMPTY`.
- L4 `tools/check_levels.gd` exits 0 on the shipped data, and 1 on a temporary folder with one broken level
  (`--dir`); the test runs it as a child process like the kit's precompute test. Its output uses
  `solution <id> finished ticks <t> rings <r>`.
- L5 Every shipped level has a solution in `tests/solutions.json` that finishes with `rings_used <= par` (11.2).

## 6. Run scripts

### 6.1 Purpose

A run script is a compact text form of a per-tick input sequence. It is used for solution tests, for debug screenshots
(`--keys`), to print a played run (`--print-run`) and to store the best run of a level in the profile (7.2), which
makes later replay or server verification possible (ADR 0003).

### 6.2 Grammar (`MazeRunScript`, `sim/run_script.gd`)

```
script = token *(" " token)
token  = hold / event
hold   = flags count
flags  = "-" / [ "L" / "R" ] [ "J" ] [ "P" ]      ; at least one letter, or "-"; letters in this order
count  = "1".."9" *DIGIT                          ; 1 to 99999
event  = "T" index / "U"                          ; index 0 to 143 without leading zeros
```

Meaning: a hold token gives `count` ticks with `move` -1 (`L`), 1 (`R`) or 0, `jump_held` when `J`. `jump_pressed` is
true on a tick when `J` is held there and not on the previous tick (the tick before the script counts as not held),
and on the first tick of a token with `P`. Events attach to the first tick of the next hold token: `T<i>` sets
`throw_dir = i`, `U` sets `undo`. At most one `T` and one `U` per tick; an event at the end without a following hold is
an error.

```gdscript
class_name MazeRunScript extends RefCounted
static func parse(text: String) -> Dictionary     # {"ok": bool, "inputs": Array[MazeInput], "error": String}
static func encode(inputs: Array) -> String       # canonical script
static func run(level: MazeLevel, text: String, max_ticks: int = 36000) -> MazeSim
	# parse, step every input, then idle ticks until finished or max_ticks; null when the script does not parse
```

Canonical encoding: consecutive ticks with equal move and jump_held, no events and no non-derivable press are merged
into one token; `P` is written only when `jump_pressed` is true and not derivable from the hold transition; a tick with
events starts a new token, preceded by its events (`T` before `U`).

Example: `R40 RJ12 R20 T30 -5 L18 U -1`.

### 6.3 Recording

`MazeGame` appends every `MazeInput` it feeds the simulation to a list for the current attempt (reset on restart). At
the finish it encodes the list. With `--print-run` the script is printed to stdout as
`run <level id> <ticks> <rings> <script>`, with `<rings>` the attempt's `rings_used`.

### 6.4 Acceptance (run scripts)

- R1 `parse` accepts the example above and gives the expected ticks (count, moves, held, pressed, throw, undo).
- R2 Errors (each `ok == false` with a message, no engine output): empty token, `0` count, `RL5`, `JR5`, `T144`,
  `T05`, two `T` before one hold, trailing event, unknown letter, count 100000.
- R3 Round trip: `parse(encode(x)).inputs` equals `x` for random input arrays of 500 ticks (50 arrays, seeded with
  `WhiteRng`), and `encode(parse(s).inputs) == s` for canonical scripts.
- R4 A recorded run (from a solution) replayed in a fresh simulation finishes at the same tick with the same
  `rings_used`.

## 7. Profile and statistics

### 7.1 Principles (ADR 0007)

- One JSON file, `user://profile.json`, one object, versioned with `format`.
- Shaped like a Pulse game profile (A5): a single JSON object well under 256 KB, so phase 3 can upload it unchanged.
- Every field merges deterministically (7.6): bests by minimum, timestamps by min/max, counters per device.
- Robust reading as in White Kit's progress file: a damaged file never stops the game.
- ADR 0009 renamed the bead fields to ring fields within format 1 (no profile had been written yet). From the first
  build that writes profiles on, a change of meaning raises `format` (conventions, "Profile").

### 7.2 Format 1

```json
{
  "format": 1,
  "game": "white-maze",
  "tick_hz": 60,
  "device": "9f2c4a1b7e3d5a60",
  "updated": 1763640500,
  "lang": "nl",
  "levels": {
    "l001": {
      "best_ticks": 2412,
      "best_rings": 1,
      "best_run": "R40 RJ12 R20 T102 -5 R18",
      "fewest_rings": 1,
      "fewest_ticks": 2412,
      "first_finish": 1763640400,
      "last_played": 1763640500,
      "counts": {
        "9f2c4a1b7e3d5a60": {"starts": 5, "finishes": 2, "deaths": 3, "play_ticks": 9000}
      }
    }
  }
}
```

| Field | Meaning |
|---|---|
| `format` | Profile format version, 1. Raised when a field changes meaning; `migrate` converts older versions. |
| `game` | Always `white-maze`. |
| `tick_hz` | 60. Tick counts are only comparable with the same rate. |
| `device` | 16 lower-case hex characters, random per installation (`Crypto.new().generate_random_bytes(8).hex_encode()`), created with the profile. Key of this device's counters. |
| `id` | Absent in phase 1. Reserved for the online profile id (string, 1 to 64 characters); kept when present. |
| `updated` | Unix seconds of the last write. |
| `lang` | `nl` or `en`. |
| `levels.<id>` | Statistics per level id (5.1); an entry exists once the level was started. |
| `best_ticks`, `best_rings`, `best_run` | Fastest finish: time in ticks, rings used in that run, its run script (`""` when longer than 20000 characters). Absent until finished. |
| `fewest_rings`, `fewest_ticks` | Finish with the fewest rings used; the fastest such finish breaks ties. Absent until finished. |
| `first_finish` | Unix seconds of the first finish. Absent until finished. |
| `last_played` | Unix seconds of the last start, finish or flush. |
| `counts.<device>` | Counters of one device: `starts` (attempts begun), `finishes`, `deaths`, `play_ticks` (game time played, also of unfinished attempts). Totals are sums over devices. |

Unknown keys at the top level and inside level entries are kept unchanged on write (forward compatibility within a
format). `best_beads` and `fewest_beads` are no longer known keys; if a development profile still has them, they pass
through as unknown keys and are never read.

### 7.3 Operations (`MazeProfile`, `sim/profile.gd`, pure, no file access)

```gdscript
class_name MazeProfile extends RefCounted
const FORMAT := 1
const GAME := "white-maze"
const MAX_RUN := 20000
static func create(device: String, lang: String, now: int) -> Dictionary
static func sanitize(data: Variant) -> Dictionary      # {"profile": Dictionary or {}, "status": "ok" | "damaged" | "newer"}
static func migrate(data: Dictionary) -> Dictionary    # format 1: unchanged copy
static func record_start(p: Dictionary, level_id: String, now: int) -> void
static func add_play(p: Dictionary, level_id: String, ticks: int, deaths: int, now: int) -> void
static func record_finish(p: Dictionary, level_id: String, ticks: int, rings: int, run: String, now: int) -> Dictionary
	# {"new_best": bool, "new_fewest": bool, "best_ticks": int, "fewest_rings": int}
static func level_totals(p: Dictionary, level_id: String) -> Dictionary  # {"starts", "finishes", "deaths", "play_ticks"} summed over devices
static func is_finished(p: Dictionary, level_id: String) -> bool         # best_ticks present
static func total_play_ticks(p: Dictionary) -> int
static func merge(local: Dictionary, remote: Dictionary) -> Dictionary   # 7.6
```

The device whose counters are changed is `p.device`.

- `record_start`: creates the level entry when missing; `counts[device].starts += 1`; `last_played = now`;
  `updated = now`.
- `add_play`: adds to `play_ticks` and `deaths` of this device; `last_played`, `updated`.
- `record_finish` (`rings` = the attempt's `rings_used`): `finishes += 1`; best when `best_ticks` absent or
  `ticks < best_ticks` (sets `best_ticks`, `best_rings`, `best_run` or `""` when too long); fewest when absent,
  `rings < fewest_rings`, or equal rings and `ticks < fewest_ticks`; `first_finish` when absent; `last_played`,
  `updated`. Play ticks and deaths are added by the caller through `add_play`.
- Numbers from JSON arrive as floats; `sanitize` accepts a number that is finite, whole and `>= 0` and stores
  `int(value)`; other values are dropped (the field becomes absent, a counter 0).

`sanitize(data)`:

1. Not a Dictionary, or `format` missing, not a whole number, or below 1: status `"damaged"`, profile `{}`.
2. `format > FORMAT`: status `"newer"`, profile `{}` (the file is left untouched).
3. Otherwise `migrate`, then field by field: `game` forced to `white-maze`; `tick_hz` forced to 60; `device` kept when
   16 lower-case hex characters, else set to `""` (the caller generates one; status stays `"ok"`); `id` kept when a
   string of 1 to 64 characters; `lang` kept when `nl` or `en`, else `nl`; `levels` must be a Dictionary (else empty);
   level keys must match the id pattern; inside an entry every known field is checked as above (`best_run` a string of
   at most `MAX_RUN`, `counts` keys 16 hex characters, counter values whole numbers >= 0); unknown keys pass through.

### 7.4 File handling (`MazeProfileStore`, `ui/profile_store.gd`)

```gdscript
class_name MazeProfileStore extends RefCounted
const DEFAULT_PATH := "user://profile.json"
var path := DEFAULT_PATH
var data := {}
var writable := true
var notice := ""            # "" | "damaged" | "newer"; shown on the level select (8.2)
func open(p: String, now: int) -> void
func save(now: int) -> bool
```

- `open`: missing file: `create` (new device id, `lang` `nl`), `save`. File present: parse with `JSON.new().parse()`.
  Unparsable or `sanitize` status `"damaged"`: rename the file to `profile.damaged-<now>.json` in the same folder,
  `create`, `save`, `notice = "damaged"`. Status `"newer"`: `data = create(...)` in memory, `writable = false`,
  `notice = "newer"`. Empty `device` after sanitize: generate one and save.
- `save`: nothing (returns false) when not writable; sets `updated = now`; writes `JSON.stringify(data)` to
  `path + ".tmp"`, then renames it over `path` (`DirAccess.rename_absolute`); returns false on any failure (no crash,
  `push_warning`).
- `--shot` mode never opens or saves a profile; `--profile=<path>` uses another path (tests, manual checks).

### 7.5 When statistics are written

| Moment | Calls | Save |
|---|---|---|
| Level opened, or restarted | `add_play` for the previous attempt's unflushed ticks and deaths (restart only), then `record_start` | yes |
| Finish | `add_play` (unflushed), `record_finish` with `sim.rings_used` | yes |
| Leaving to the level select, pause by focus loss, `NOTIFICATION_WM_CLOSE_REQUEST`, `NOTIFICATION_APPLICATION_PAUSED` | `add_play` (unflushed) | yes |

"Unflushed" = the attempt's `time_ticks()` and `deaths` minus what was already added in this attempt; `MazeGame`
keeps `flushed_ticks` and `flushed_deaths` per attempt. After the finish nothing more is added for that attempt.

### 7.6 Merge (for the online profile, phase 3; implemented and tested in phase 1)

`merge(local, remote)` returns a new profile; both inputs are sanitized format-1 profiles:

- `format` 1, `game`, `tick_hz` 60; `device` from `local`; `id` from `remote` when present, else from `local`.
- `updated`: maximum. `lang`: from the profile with the larger `updated`; equal: `local`.
- `levels`: union of ids. Per level: best = the one with the smaller `best_ticks` (absent counts as infinite); tie:
  smaller `best_rings`; tie: `local`; its `best_ticks`, `best_rings`, `best_run` go together. Fewest = smaller
  `fewest_rings`, tie smaller `fewest_ticks`, tie `local`, both fields together. `first_finish`: minimum of the present
  values. `last_played`: maximum. `counts`: union of device keys; per device and counter the maximum.
- Unknown keys: from `local` when present there, else from `remote`.
- Properties: `merge(a, a) == a`; `merge(a, b)` and `merge(b, a)` have equal levels when no ties occur; totals after a
  merge never double-count a device.

### 7.7 Acceptance (profile)

- P1 `create` gives format 1 with all top-level fields and a 16-hex device id.
- P2 `sanitize` cases (each with expected result): not a Dictionary, `format` missing / `"1"` / `0.5` / `-1`
  (damaged), `format` 2 (newer), bad `lang`, bad level key, negative and fractional counters, a `best_run` that is not
  a string, unknown keys kept, `id` of 65 characters dropped, bad `device` replaced by `""`, a negative `best_rings`
  dropped, an old `best_beads` key kept unchanged as an unknown key.
- P3 `record_start`, `add_play`, `record_finish` update exactly the fields of 7.3; a slower finish keeps the best; a
  finish with fewer rings but slower updates only fewest; `best_run` over 20000 characters is stored as `""`; after
  `record_finish` the entry has `best_rings` and `fewest_rings` and no `best_beads` or `fewest_beads`.
- P4 Store: a missing file creates one; a write and a fresh `open` round-trip the data; a file with `"not json"` is
  renamed to `profile.damaged-<now>.json` and a fresh profile is written; a format-2 file is left byte-identical and
  `save` returns false. Test files live under `user://` with prefix `white_maze_test_` and are deleted afterwards.
- P5 `merge` properties of 7.6 and at least six hand-made cases (best from remote, tie on `best_ticks` decided by
  `best_rings`, tie to local, counts from two devices, id from remote, lang by `updated`, unknown keys).
- P6 A profile with 30 levels, each with a 2000-character best run and counters of two devices, serializes to less
  than 100 KB (size printed in the test output).

## 8. Screens and texts

### 8.1 Look

- Colours from `WhiteTheme`: background `BG` `#1B1F26`; grid lines in the world `#20252D`, 1 px, every tile; solid
  blocks `BUTTON.normal` `#2A303B` with a 4 px edge in `BUTTON.pressed` `#4A5363` on every exposed face; no-ring blocks
  `#20252D` with diagonal hatching in `#343B48` every 10 px, no edge highlight; spikes as triangles in `#4A5363` (two
  per tile); finish an 8 x 40 px white (`ACCENT`) post centred in the tile with a 2 px frame at 25 % alpha; player
  `TEXT` `#E6E9EF` rounded square (radius 6) with a 14 x 6 px `BG` eye stripe towards `facing`; rings an ellipse
  (along the face 38 x 10 px) with a 5 px `TEXT` stroke and a faint arrow in the launch direction; a ring that just
  launched flashes `ACCENT` for 10 ticks; bead a white circle, radius 7.
- White is only for what belongs to the player or what the player needs: player, beads, rings, finish, aim line.
- Death: the player fades out over the 30 death ticks; respawn fades in over 10 ticks (view only).
- Fonts and sizes from `WhiteTheme`; buttons from `WhiteUi.button`.
- No image assets except `icon.svg` (a white rounded square with an eye stripe on `BG`).

### 8.2 Level select (`MazeLevelSelect`, `ui/level_select.gd`)

- Margins `WhiteTheme.MARGIN` plus the safe area; the column is at most 1100 px wide, centred.
- Top row: title `t("title")` (`FONT_TITLE`, `ACCENT`, expanding) and the language button (`t("lang")`).
- Subtitle (`DIM`): `t("levels_done") % [finished, total]` and `t("play_time") % WhiteFormat.clock(ms)` joined by
  `"  ·  "`, with `ms = total_play_ticks * 1000 / 60`.
- Notice line (`DIM`) when the store has a notice (`t("profile_damaged")` or `t("profile_newer")`); shown until a
  level is opened.
- Level cards in a `GridContainer` with 3 columns inside a `ScrollContainer`; each card is a `WhiteUi.button` of height
  170 with four lines: `"%d  %s" % [number, name]`, difficulty (`t("levels")[difficulty]`), best time line
  (`t("card_time") % time` or `t("not_done")`), rings line (`t("card_rings") % [fewest_rings, par]` or
  `t("par") % par`). Locked levels are disabled and show `t("locked")` as the last line.
- Focus starts on the first open level that is not finished (else the first). Arrow keys move focus (Godot focus
  neighbours), `Enter`/`Space` opens.

### 8.3 Game screen (`MazeGame`, `ui/game.gd`)

Node layout (created in code):

```
MazeGame (Node)
  World (Node2D, MazeWorldView)   tiles, rings, beads, player, aim preview
    Camera2D
  Hud (CanvasLayer 1)             MazeHud
  Touch (CanvasLayer 2)           MazeTouchOverlay
  Overlay (CanvasLayer 3)         MazeOverlays: pause, result, rotate hint
```

- Camera: follows the interpolated player centre with `position_smoothing_enabled` (speed 8), a look-ahead of 60 px in
  the facing direction (lerped), limits at the level bounds; a level smaller than the viewport is centred.
- HUD (`MazeHud`, top band, 110 px plus safe area): left `"%d · %s" % [number, name]` (`FONT_SUBTITLE`, `TEXT`) and
  under it the score line `t("hud_rings") % [sim.rings_used, par]` (`DIM`; `TEXT` for 10 ticks after a `launch` event
  with `counted == true`); centre the clock `MazeFormat.time(sim.time_ticks())` (`FONT_INFO`); right the bead dots
  (the supply: `level.beads` circles of radius 12, filled `TEXT` for each bead left, 3 px `DIM` outline for each bead
  not in the supply) and three buttons `t("undo_bead")`, `t("restart")`, `t("pause")` (`WhiteUi.button`, height 52,
  `focus_mode = FOCUS_NONE` so keys never press them).
- Hint: when the level has a hint, a `DIM` label (`FONT_MESSAGE`) centred at the bottom, above the safe area, with the
  placeholders of 8.6 filled for the current input mode; hidden on the result overlay.
- Each frame: handle pause/restart/undo latches, update the rate (4.4), step the simulation, feed
  `controls.set_facing`, `set_player_screen_pos` and `set_can_aim`, record inputs (6.3), process events (finish ->
  result), update view and HUD.
- Pause triggers (2.7) open the pause overlay and call `cancel_aim()`.

### 8.4 Overlays (`MazeOverlays`, `ui/overlays.gd`)

- Pause: full-screen `BG` at 85 % alpha; centred column: `t("pause")` (`FONT_TITLE`), buttons `t("resume")`,
  `t("restart")`, `t("levels_btn")`, and the controls legend (`t("help_keys")` or `t("help_touch")` by input mode,
  `DIM`). `Esc`/`P` resumes.
- Result (after the finish, the world stays visible and frozen): `t("finished")` (`FONT_TITLE`), the time
  (`FONT_TITLE`), `t("result_rings") % [rings_used, par]` plus `"  " + t("perfect")` when rings used == par or
  `"  " + t("under_par")` when rings used < par, `t("new_record")` when `new_best` (`ACCENT`), else
  `t("best_time") % best`; buttons `t("restart")` (`R`), `t("next")` (`Enter`, hidden on the last level; on the last
  level `Enter` opens the level select), `t("levels_btn")` (`Esc`). Focus on Next (or Restart on the last level).
- Rotate hint: when the viewport is taller than wide, a full-screen `BG` panel with `t("rotate")`; the game pauses;
  turning back closes the hint but keeps the pause overlay.

### 8.5 Main (`MazeMain`, `ui/main.tscn`, `ui/main.gd`)

Root `Control` (full rect) with a `BG` `ColorRect`. `_ready`: parse user arguments (10.4), register texts
(`WhiteText.register(MazeStrings.TEXT)`), open the profile (unless `--shot`), set `WhiteText.lang` (debug argument or
profile), load the level ids and levels, then show the level select or, with `--level=<id>`, start that level. Switches
between `MazeLevelSelect` and `MazeGame` by freeing one and adding the other. The language toggle stores `lang` and
saves.

### 8.6 Texts (`ui/strings.gd`, `class_name MazeStrings`)

Registered through `WhiteText.register`; kit base keys used as they are: `levels`, `par`, `restart`, `next`, `perfect`,
`lang`. Game keys (Dutch / English):

| Key | Dutch | English |
|---|---|---|
| `title` | `WHITE MAZE` | `WHITE MAZE` |
| `levels_done` | `Gehaald %d/%d` | `Finished %d/%d` |
| `play_time` | `Speeltijd %s` | `Play time %s` |
| `locked` | `Op slot` | `Locked` |
| `not_done` | `Nog niet gehaald` | `Not finished yet` |
| `card_time` | `Beste tijd %s` | `Best time %s` |
| `card_rings` | `Minste ringen %d · par %d` | `Fewest rings %d · par %d` |
| `hud_rings` | `Ringen %d · par %d` | `Rings %d · par %d` |
| `undo_bead` | `Kraal terug` | `Bead back` |
| `pause` | `Pauze` | `Pause` |
| `resume` | `Doorgaan` | `Resume` |
| `levels_btn` | `Levels` | `Levels` |
| `finished` | `Gehaald!` | `Finished!` |
| `result_rings` | `Ringen: %d · par %d` | `Rings: %d · par %d` |
| `under_par` | `Onder par!` | `Under par!` |
| `new_record` | `Nieuw record` | `New record` |
| `best_time` | `Beste tijd %s` | `Best time %s` |
| `rotate` | `Draai je toestel` | `Rotate your device` |
| `profile_damaged` | `Het profiel was beschadigd en is opnieuw begonnen.` | `The profile was damaged and has been started again.` |
| `profile_newer` | `Dit profiel komt van een nieuwere versie; je tijden worden nu niet bewaard.` | `This profile comes from a newer version; your times are not saved now.` |
| `ctl_move` | `lopen` | `move` |
| `ctl_throw` | `werpen` | `throw` |
| `ctl_jump` | `springen` | `jump` |
| `keys` | `{"move": "A/D", "jump": "Spatie", "throw": "J vasthouden en loslaten", "undo": "Z"}` | `{"move": "A/D", "jump": "Space", "throw": "hold and release J", "undo": "Z"}` |
| `touch` | `{"move": "je linkerduim", "jump": "de springknop", "throw": "de werpstick", "undo": "Kraal terug"}` | `{"move": "your left thumb", "jump": "the jump button", "throw": "the throw stick", "undo": "Bead back"}` |
| `help_keys` | `A/D of pijltjes: lopen\nSpatie of W: springen (vasthouden = hoger)\nJ vasthouden: richten, W/S draaien, loslaten: werpen, K: annuleren\nZ: kraal terug  ·  R: opnieuw  ·  Esc: pauze` | `A/D or arrows: walk\nSpace or W: jump (hold = higher)\nHold J: aim, W/S turn, release: throw, K: cancel\nZ: bead back  ·  R: restart  ·  Esc: pause` |
| `help_touch` | `Linkerduim: lopen\nSpringknop: springen (vasthouden = hoger)\nWerpstick: slepen = richten, loslaten = werpen, terug naar het midden = annuleren` | `Left thumb: walk\nJump button: jump (hold = higher)\nThrow stick: drag = aim, release = throw, back to the centre = cancel` |
| `help_par` | `Par telt de ringen waar je vanaf bent gestuiterd. Kraal terug geeft je de kraal terug, maar een gebruikte ring blijft meetellen.` | `Par counts the rings you bounced off. Bead back returns the bead, but a used ring still counts.` |

The keys `card_beads` and `result_beads` of the first design are replaced by `card_rings` and `result_rings`.
`help_par` is shown in the pause overlay as a last `DIM` line under the controls legend, in both input modes.

`keys` and `touch` are Dictionaries (`WhiteText.t` returns a Variant). Hint placeholders `{move}`, `{jump}`, `{throw}`,
`{undo}` are replaced with the values of `keys` or `touch` (current input mode) via `String.format`.

`MazeFormat` (`sim/format.gd`): `static func time(ticks: int) -> String` gives `m:ss.cc` with `cs = ticks * 100 / 60`
(`0` -> `0:00.00`, `59` -> `0:00.98`, `60` -> `0:01.00`, `216000` -> `60:00.00`; negative -> `0:00.00`).

### 8.7 Acceptance (screens)

- U1 Headless: the main scene opens the level select with nine cards; with an empty profile only card 1 is enabled;
  after a recorded finish of l001 card 2 is enabled and card 1 shows the best time and the fewest rings line
  (`t("card_rings")`).
- U2 The language toggle switches every visible text and is saved in the profile; `--lang=en` overrides for the
  session.
- U3 Starting l001 and feeding its solution through `MazeControls` (not directly into the simulation) ends in the
  result overlay with the time, `t("result_rings") % [1, 1]`, the `perfect` text and `new_record`; the profile has the
  finish with `best_rings == 1` and `fewest_rings == 1`.
- U4 HUD buttons have `focus_mode == FOCUS_NONE`; `Space` on the game screen never presses a button.
- U5 Pause stops ticks (no change of `sim.tick` over 30 frames); resume continues; restart creates a fresh simulation
  and a `starts` increment.
- U6 A viewport taller than wide shows the rotate hint and pauses.
- U7 `MazeFormat.time` cases of 8.6; every text key exists in both languages (`MazeStrings.TEXT["nl"].keys() ==
  MazeStrings.TEXT["en"].keys()`); the keys `card_beads` and `result_beads` no longer exist.
- U8 The screenshots of `tools/shots.txt` (10.5) are produced without errors; the tester reviews them by eye against
  8.1-8.4 and the mockup.
- U9 HUD score line on l001: at the start it reads `Ringen 0 · par 1`; after the solution's own ring first launches
  the player it reads `Ringen 1 · par 1`; a bead back after that refills a bead dot and the line still reads
  `Ringen 1 · par 1`; a restart shows `Ringen 0 · par 1` again.

## 9. White Kit usage (ADR 0008)

Pinned tag `v0.3.0` (the newest release; 764 kit checks).

| Kit part | Used | How |
|---|---|---|
| `WhiteTheme`, `WhiteUi` | Yes | Colours, sizes, fonts, buttons and labels on every screen. |
| `WhiteText` | Yes | Language state and lookup; game table `MazeStrings.TEXT` registered; base keys `levels`, `par`, `restart`, `next`, `perfect`, `lang` reused. |
| `WhiteFormat.clock` | Yes | Total play time on the level select (`m:ss`). Level times use the game's `MazeFormat.time` (hundredths). |
| `WhiteSafeArea` | Yes | Insets for HUD, touch overlay and level select (`--safe=l,t,r,b` debug override). |
| `WhitePuzzleStore.load_json` | Yes | Reading level and index JSON without error output. |
| `WhiteTestRunner` | Yes | Base of `tests/run_tests.gd`; script errors fail the run; `--min-checks`. |
| `WhiteRng` | Tests only | Seeded random input arrays in the run script round-trip test. |
| `ci/setup-godot`, `templates/ci.yml` | Yes | Godot 4.7.2 download and cache; the game workflow starts from the template. |
| `tools/shots.sh`, `tools/compare_shots.gd` | Yes | Screenshot scenarios (`tools/shots.txt`); the game implements `--shot` itself (10.4). |
| `WhiteDayScreen`, `WhiteAttempt`, `WhiteRules`, `WhiteProgress` | No | Built for daily puzzles with move records, undo history and a day-keyed progress file; a platformer has none of these. |
| `WhiteDaily`, `WhiteSeed`, `WhitePrecompute`, `WhiteTileView` | No | No daily puzzle, no generator, no cell board. |

Game-own: simulation, levels, run scripts, profile, controls, touch overlay, world view, HUD, overlays, level select,
time format, debug arguments and the `--shot` mode.

Kit work: none needed for phase 1. Candidates for later, to be requested in `dm-utils/white-kit` and never edited in
`addons/white_kit` (13): a shared debug-argument and screenshot helper for games without the day screen; a clock
format with hundredths; a note in the kit design that White Maze uses the kit without the day screen.

## 10. Project, build and CI

### 10.1 Layout

```
white-maze/
  project.godot  export_presets.cfg  icon.svg  README.md  .gitignore  .gitmodules
  addons/white_kit/              White Kit submodule at v0.3.0
  sim/        tuning.gd  level.gd  levels.gd  aim.gd  input.gd  sim.gd  run_script.gd  profile.gd  format.gd
  ui/         main.tscn  main.gd  level_select.gd  game.gd  world_view.gd  hud.gd  controls.gd  touch_overlay.gd
              overlays.gd  profile_store.gd  strings.gd
  levels/     index.json  l001.json ... l009.json
  tests/      run_tests.tscn  run_tests.gd  *_tests.gd  solutions.json
  tools/      check_levels.gd  shots.txt
  .github/workflows/ci.yml
  docs/       design.md  conventions.md  glossary.md  adr/
```

Class names and the prefix `Maze`: `docs/conventions.md`. Every `.gd` file has its committed `.gd.uid` next to it.

### 10.2 Project settings (`project.godot`)

- `config/name="White Maze"`, `config/version="0.1.0"`, features `4.7` and `GL Compatibility`, main scene
  `res://ui/main.tscn`, icon `res://icon.svg`, boot splash without image on `BG`.
- Display: viewport 1280 x 720, window override 1280 x 720, stretch mode `canvas_items`, aspect `expand`,
  `window/handheld/orientation=4` (sensor landscape).
- Renderer `gl_compatibility` (also for mobile), default clear colour `BG`.
- Input map: the actions of 4.2.
- `input_devices/pointing/emulate_touch_from_mouse=false`, `emulate_mouse_from_touch=true` (defaults, stated
  explicitly).
- `debug/gdscript/warnings/integer_division=0` (as White Sum).
- `.gitignore`: `.godot/`, `build/`, `*.tmp`.

### 10.3 Export (`export_presets.cfg`)

One preset `Web`, copied from White Sum's: `export_filter="all_resources"`, `include_filter="*.json"`,
`exclude_filter="tests/*,tools/*,addons/white_kit/tests/*,addons/white_kit/tools/*"`,
`export_path="build/web/index.html"`, no threads, no extensions, `html/canvas_resize_policy=2`,
`html/focus_canvas_on_start=true`, the same `head_include`.

### 10.4 Debug arguments (after `--`)

| Argument | Effect |
|---|---|
| `--level=<id>` | Start this level directly (also when locked). |
| `--all-levels` | Every level open on the level select. |
| `--lang=nl\|en` | Language for this session (not saved). |
| `--touch` | Touch overlay always on. |
| `--safe=l,t,r,b` | Safe area override (kit). |
| `--profile=<path>` | Profile file path. |
| `--print-run` | Print the run script at each finish (6.3). |
| `--keys=<script>` | With `--level`: feed this run script into the simulation at once (no real time), then freeze. |
| `--solve` | With `--level`: like `--keys` with the level's script from `tests/solutions.json` (ignored when the file is missing); a finish shows the result overlay. |
| `--aim=<index>` | With `--level`: show the aim preview for this index (frozen). |
| `--pause` | With `--level`: open the pause overlay. |
| `--shot=<png>` | Screenshot mode: no profile read or write, simulation frozen after `--keys`/`--solve`, no camera smoothing; wait 0.5 s and one drawn frame, save the viewport to the PNG, quit. |

### 10.5 Screenshot scenarios (`tools/shots.txt`)

```
select 1280x720
select-en 1280x720 --lang=en --all-levels
easy 1280x720 --level=l001
easy-touch 1280x720 --level=l001 --touch
medium-aim 1280x720 --level=l002 --keys=-1 --aim=30
hard 1280x720 --level=l003
result 1280x720 --level=l001 --solve
pause 1280x720 --level=l001 --pause
phone-wide 1600x720 --level=l002 --touch --safe=60,0,60,24
portrait 720x1280 --level=l001
```

### 10.6 CI (`.github/workflows/ci.yml`, ADR 0008)

From the kit template, without the Pages job:

1. Checkout with submodules; kit pin check (tag `v0.3.0` equals the submodule HEAD).
2. `uses: ./addons/white_kit/ci/setup-godot`.
3. Import; kit tests `--min-checks=764`; game tests `--min-checks=${MIN_CHECKS}` (the count after #002).
4. Level check: `godot --headless --path . -s res://tools/check_levels.gd`.
5. Debug screenshots from `tools/shots.txt`, artifact `shots`.
6. Export Web (release), artifact `web`.

Triggers, concurrency and permissions as in White Sum. Since card #006 the workflow also has the Pages job of White
Sum: on `develop` (not on pull requests) the release web build is uploaded with `upload-pages-artifact` and published by
a `pages` job with `deploy-pages`; the play address is `https://play.white-maze.steefbeest.nl`. The custom domain is a
repository setting (Pages source "GitHub Actions" plus the domain), not a `CNAME` file. A step runs
`tools/check_search_par.sh` (16.2).

## 11. Tests

### 11.1 Runner

`tests/run_tests.tscn` with `tests/run_tests.gd extends WhiteTestRunner`; suites loaded by path, each with
`func run(check: Callable, node: Node) -> void`. Run:

```bash
godot --headless --path . --import
timeout 300 godot --headless --path . res://addons/white_kit/tests/run_kit_tests.tscn -- --min-checks=764
timeout 300 godot --headless --path . res://tests/run_tests.tscn -- --min-checks=<N>
```

### 11.2 Suites (all headless)

| Suite | Covers |
|---|---|
| `tuning_tests.gd` | S1. |
| `aim_tests.gd` | S18. |
| `level_tests.gd` | L1-L4. |
| `move_tests.gd` | S2-S7 on small hand-made maps built with `MazeLevel.from_dict`. |
| `ring_tests.gd` | S8-S14 and S19. |
| `rules_tests.gd` | S15-S17. |
| `run_script_tests.gd` | R1-R4. |
| `solution_tests.gd` | L5: every level in the index has a solution in `tests/solutions.json` that finishes with `rings_used <= par`; replaying it twice gives equal snapshots; the encoded recording of the replay replays to the same finish. |
| `profile_tests.gd` | P1-P6. |
| `controls_tests.gd` | C1-C6 with synthetic `InputEventKey`, `InputEventMouseButton`, `InputEventScreenTouch` and `InputEventScreenDrag` passed to `handle_event` of the controls and the overlay. |
| `ui_tests.gd` | U1-U7 and U9 with the main scene in the test tree (`--profile` under `user://white_maze_test_*`). |

Fixture maps in tests are written as row arrays in the test files (no extra level files).

### 11.3 What cannot be tested headless

Game feel itself (does it feel good), readability on a real phone, multi-touch on real hardware, and browser
behaviour. These are checked by the tester on the web export (desktop browser and, when possible, a phone in landscape
over the local network) and by the owner's playtest (13).

## 12. Developer work (card #002)

Build order, each step with its tests green before the next:

1. Project skeleton: `project.godot`, submodule at `v0.3.0`, `.gitignore`, export preset, `icon.svg`, empty test runner,
   CI file. Kit tests green in the game.
2. `sim/`: tuning, aim table, level parsing and validation, simulation, run scripts, format; suites `tuning`, `aim`,
   `level`, `move`, `ring`, `rules`, `run_script`.
3. Levels l001-l003 and `tools/check_levels.gd`.
4. UI: main, level select, game screen with world view, HUD, keyboard and mouse controls, slow motion, overlays.
5. Solutions recorded with `--print-run`, `solution_tests.gd`; adjust maps if needed (5.4).
6. Profile and store, statistics on screens; `profile_tests.gd`.
7. Touch overlay; `controls_tests.gd`; `ui_tests.gd`.
8. `tools/shots.txt`, web export, README; `MIN_CHECKS` set to the final count.

Suggested split for the board (project lead decides): steps 1-3 and the pure part of 6 (`MazeProfile`) form a headless
core; steps 4, 5, 7, 8 and the store of 6 form the screens and controls. The tester can start on the core while the
screens are built.

## 13. Open points

- Owner playtest after #003: tuning values of 3.3 (jump height, ring strength, coyote and buffer), slow-motion factor,
  touch layout. Tuning changes are expected; they only touch `MazeTuning` (and its test values) and possibly the maps.
- Unlocking: sequential (2.8). Alternative for the prototype: everything open. Owner question.
- Time is game time, so aiming costs a quarter of real time (2.6, ADR 0003). Owner question.
- A phone test needs the web build on a reachable address: a GitHub repository with Pages, or serving `build/web` on
  the local network. Owner question.
- Kit candidates (9) are not needed now; the project lead may create kit cards when a second game needs them.
- Ceiling ring role (ADR 0009): in the current rules a ceiling ring rarely does something air control cannot, so no
  level uses it. The level designer proposes that a ceiling ring also sets horizontal speed to 0 ("drop": floor = up,
  wall = sideways, ceiling = stop and fall). Decide after the owner's playtest, together with the tuning. If accepted:
  3.7 `DOWN` row gets `vx = 0`, S10 checks `vx == 0`, and no existing solution changes (none uses a ceiling ring).
- Par rule (ADR 0009) to be confirmed in the owner's playtest: does "rings used" read naturally in the HUD, and is a
  free take-back of a ring that never launched the player understood?
- [later] Moving obstacles as sim entities, gamepad, sound, a per-level finish history (last N times), a visual level
  editor, showing the best run as a ghost.

## 14. Deviations and results of the headless core (card #002)

Built as designed, except for the points below. None changes a rule or a tuning value.

- **Coyote and buffer counting (3.8 step 9, S4, S5).** The counters are read as the previous tick left them and then
  updated. With the literal order of step 9 (update, then read) a jump pressed 6 ticks after the walk-off tick, or 8
  ticks before the landing tick, would already be too late; with read-then-update S4 and S5 hold exactly. "Walk-off
  tick" is the tick in which `grounded` becomes false; "landing tick" is the first tick that starts grounded.
- **`prev_px`, `prev_py` after the finish (3.8 step 1).** They are no longer updated once the level is finished, so
  that only `tick` changes in `snapshot()` (S16).
- **`MazeLevels.ids` and `load_level`** take an optional folder argument (default `res://levels/`), used by
  `tools/check_levels.gd --dir` and the tests.
- **`MazeTuning`** also holds `UNITS_PER_PX`, `TILE` and `TICK_HZ`.
- **`MazeSim.cast`:** the reasons `dead` and `no_beads` take precedence over the face rules; `valid` is then false.
- **Run scripts:** an empty script is an error (the grammar needs at least one token). `MazeRunScript.run` stops at
  the finish.
- **Level check:** also reports a level file that is not in the index (`error <id>: level file is not in the index`).
- **Project:** `rendering/textures/vram_compression/import_etc2_astc=true` is set (as in White Sum); without it the web
  preset refuses to export.
- **CI:** the screenshot step runs only when `tools/shots.txt` exists (it comes with card #004); `MIN_CHECKS` is 333.

Level geometry (5.4) is unchanged; all three levels are solvable within par with the designed rows and the start
tuning. Stored solutions (`tests/solutions.json`), found with a throw-away search over the simulation, not by playing:

| Level | Par | Beads | Ticks | Time | Deaths |
|---|---|---|---|---|---|
| l001 | 1 | 1 | 391 | 0:06.51 | 0 |
| l002 | 2 | 2 | 256 | 0:04.26 | 0 |
| l003 | 3 | 3 | 295 | 0:04.91 | 0 |

"Beads" in this table is the old beads used; the solutions contain no `U`, so rings used is expected to be the same
(each thrown ring is thrown to be bounced off). The solution tests confirm this after the change of section 15.

Facts found while solving, for the playtest: a floor-ring jump from standing lifts the feet 5.85 tiles; the wall ring
of l003 can only be reached at cell (0, 4) (from a floor-ring jump, throwing from about x = 2.4 tiles, index 41); a
throw to (0, 4) from the spawn point itself hits the corner and is invalid. The solutions are replayed by
`tests/solution_tests.gd` and `tools/check_levels.gd`; after a tuning change record them again (a played run with
`--print-run` once the screens exist).

## 15. Par counts rings used (ADR 0009): developer work

A rule change on the built core. No tuning, geometry or level file changes. Order:

1. `sim/sim.gd`: add `rings_used`; add `"used": false` to every ring (presets in `_init`, thrown rings in step 5);
   count in the launch (3.7, 3.8 step 12) and add `counted` to the `launch` event; add `rings` to the `finish` event;
   include `rings_used` and each ring's `used` in `snapshot()`; remove `beads_used()`. Undo (step 3) stays as it is.
2. `sim/level.gd`: `par` accepted from 0 to `MAX_PAR` (20), independent of `beads`; error text
   `par <v> is outside 0..20`.
3. `sim/profile.gd`: `best_beads` -> `best_rings`, `fewest_beads` -> `fewest_rings` in `record_finish` (parameter
   `rings`, result key `fewest_rings`), `sanitize`, `merge` and the known-field lists. `FORMAT` stays 1; `migrate`
   unchanged.
4. `tools/check_levels.gd`: compare `rings_used` with par; output `solution <id> finished ticks <t> rings <r>` and
   `solution <id> FAILED used <r> rings, par is <p>`. `tools/search_par.gd` (throw-away search tool): add `rings_used`
   to its state key and score by it, or delete the tool if it is no longer needed.
5. Tests: every use of `beads_used()`, `best_beads` and `fewest_beads` in `tests/` moves to the new names
   (`ring_tests`, `rules_tests`, `solution_tests`, `profile_tests`, `run_script_tests`, `robust_tests`,
   `fuzz_tests`); new cases S19 a-h in `ring_tests`; L2 par cases in `level_tests`; P2, P3, P5 additions in
   `profile_tests`. Raise `MIN_CHECKS` to the new count.
6. Run the full suite and the level check; l001 to l003 must still pass with their stored solutions and report
   rings 1, 2, 3.

The screens (card #004) are built directly against sections 8.2 to 8.7 as they stand now (`hud_rings`,
`card_rings`, `result_rings`, `help_par`, U9).

## 16. Deviations and results of the screens (card #004, #006)

Built as designed (sections 4, 7.4, 8, 10.4, 10.5), except for the points below. None changes a rule or a tuning value.

### 16.1 Deviations

- **Hint place in touch mode (8.3).** With touch controls on, the level hint sits under the HUD band instead of at the
  bottom, where the stick labels and the jump button are.
- **Mouse and keys reach `MazeControls` from `_unhandled_input`.** A press on a HUD or overlay button never starts an
  aim; the touch overlay reads touches in `_input` and is disabled while an overlay is open.
- **Enter on the result overlay** is handled by `MazeGame._input` (next level, or the level select on the last level),
  not by the focused button, so the last level behaves as 8.4 says.
- **`MazeControls`** has extra methods: `queue_undo` (HUD button), `release_all`, `reset_attempt` (elevation back to
  +3, latches dropped), `clear_latches`, `update(delta)` (real-time repeat of the aim keys), `can_aim`, `elevation`.
- **`MazeGame.advance(delta)`** is the per-frame step that `_process` calls; the tests call it with fixed deltas.
  While paused the rate is 0 and ramps back to 1 over 0.107 s after resuming.
- **`MazeMain`**: `parse_args` is a static function; `args` and `use_cmdline` let the tests inject arguments. `--keys`,
  `--solve` and `--aim` freeze the simulation in every mode, `--shot` always (not only after `--keys`/`--solve`).
- **`MazeProfileStore.open_memory`** gives `--shot` a profile that is never read or written, so the result screenshot
  can show a new record.
- **Input map** uses physical keys (layout independent): `A`/`Left`, `D`/`Right`, `Space`/`W`/`Up`, `J`, `S`/`Down`,
  `K`, `Z`/`Backspace`, `R`, `Esc`/`P`.
- **Camera.** `Camera2D` with smoothing speed 8; its limits are recomputed every frame and a level smaller than the
  viewport is centred in the area under the HUD band.

- **Profile entry without a fewest pair (B8).** `MazeProfile.sanitize` keeps accepting an entry with only a best pair
  (existing tests require that the fewest pair is not invented). The level select therefore falls back to `best_rings`
  for the card text instead of deriving a pair in `sanitize`; the UI never reads a field that `sanitize` does not
  guarantee. The next finish writes the full pair.
- **Rotate hint keeps the game paused (B9).** While the rotate hint shows, pause, resume and restart keys are dropped;
  the game stays paused until the window is landscape again.
- **Cosmetics (B10).** Hint sits 16 px higher at the bottom; the move-stick label `lopen` moved inside the stick ring and
  is fainter; the level grid has 6 px padding so the focus border is not clipped by the scroll area.

### 16.2 Par search tool (B7)

`tools/search_par.gd` is back to its old meaning: extra rings are pre-placed as presets and the number of extras is the
score; `rings_used` stays in the state key. The change of 451b7f7 (extras as thrown rings, a ring weight in the cost)
made the search lose its known results. Calibration: `tools/check_search_par.sh` runs l001 (extra ring `38,11,up`,
weight 3, under a second) in CI; `tools/check_search_par.sh --full` also finds l002 (about 2 minutes at 300000 nodes)
and l003 and is run by hand after a change of the simulation or the tool.

### 16.3 Results

- Game tests: 662 checks (controls C1-C6 in `controls_tests.gd`, store P4 in `profile_store_tests.gd`, screens U1-U7
  and U9 in `ui_tests.gd`); kit tests 764; level check and web export green.
- `--print-run` on l001 prints the run of the stored solution unchanged, so the recording matches the run script.
- Screenshots of `tools/shots.txt` (10 scenarios, among them `easy-touch` and `phone-wide` with touch controls) are
  produced by `shots.sh` without errors; reviewed by the developer, the tester reviews them against the mockup (U8).
- Not checked here: feel on a real phone, multi-touch on hardware, browser behaviour (11.3).

## 17. Levels 4 to 9 (card #007)

The six sketched levels (designer's note of 2026-11-20) are in `levels/` and `levels/index.json` lists l001 to l009.
Par is counted as rings used (ADR 0009); the sketch's "A" column was the starting point. Solutions are in
`tests/solutions.json`, found with scratch scripts over the simulation (hand-guided runs and a throw-away search that
also plans throws), not by playing. Every solution is replayed by `tests/solution_tests.gd` and
`tools/check_levels.gd`, and survives the robustness test that takes back every thrown ring right after its first
launch (so each ring is thrown just before it is needed).

| Level | Difficulty | Beads | Par | Rings used | Ticks | Rings of the solution |
|---|---|---|---|---|---|---|
| l004 | easy | 1 | 3 | 3 | 371 | floor rings (7, 11), (19, 11), (31, 11); each taken back after use |
| l005 | medium | 3 | 2 | 2 | 215 | wall rings (21, 9) right, (26, 9) left; preset floor ring |
| l006 | medium | 3 | 4 | 4 | 214 | floor rings (5, 21), (9, 17), (13, 13) (taken back), (17, 9) |
| l007 | medium | 3 | 2 | 2 | 227 | wall ring (10, 9) right, floor ring (27, 12) |
| l008 | hard | 3 | 2 | 2 | 264 | wall ring (0, 6) right, floor ring (10, 13); preset floor ring |
| l009 | hard | 3 | 4 | 4 | 337 | floor ring T (8, 13) (taken back), F1 (11, 13), W1 (10, 6) right, K (20, 13) |

### 17.1 Changes to the sketch

- **l007: the pit is 8 wide, not 9** (the far side starts at column 19 instead of 20; rows 12 to 16 of column 19 are
  solid). With the sketched geometry the flight over the pit reached the far side with about 3 px to spare (the
  sketch estimated 21 px); with the shorter pit it is about 60 px. A coyote jump from the tunnel is still hopeless: the
  tunnel is two tiles high, so a jump is cut short by the ceiling.
- **l008 and l009: the ground ends one tile earlier** (l008: pit of 6 instead of 5, columns 11 to 16, the ring on the
  ground goes on (10, 13); l009 the same ten columns further, ring K on (20, 13)). With the sketched geometry
  `tools/search_par.gd` found a route with one ring: run, jump, and touch the floor ring on the last ground tile in
  the air at its far edge; that launches about 50 px further than the sketch assumed (it estimated 50 px short) and
  reaches the ledge. With the ring on the new last tile the search finds no one-ring route, and the stored two-ring
  route is unchanged (the flight meets the ring at the same x).
- **l009: column 10 is `X` below its top cell** (rows 7 to 12). The sketch's second route (walk off the top of column
  10, fall along the wall and use W1 as a catching ring, as in l007) was found with three rings: T, a wall ring on row
  7 and K (a brute-force scan over the throw time and a few ticks of air control finds it for several starting
  variants). With only the top cell `#` the wall ring has to go on (10, 6), which the intended route needs anyway;
  the same scan found no three-ring route then.
- All other grids are as sketched, tile for tile.
- l004 to l006, l008 and l009: the sketched routes work with small differences in where the rings go. l004's first
  ring can go on (7, 11) as well as (8, 11): a ring in the player's path launches at running speed, the player hits
  the wall, climbs along it and lands on top. The solutions of l008 and l009 use the wall ring on row 6; rows 7 and 8
  (the sketch allowed rows 6 to 8) land about 9 ticks earlier, so the ring on the ground would have to move.
- Measured margins of the stored solutions: l005 feet 16 px above the plateau edge on the way back; l007 about 60 px
  above the far edge of the pit; l008 and l009 about 25 px above the edge of the ledge.
- The wall flights are as sketched: 640 px/s, landing about 390 px from the wall at about 500 px/s. The air drag
  takes 5 px/s per tick, so the floor ring of l008 and l009 is thrown in the air during the flight and takes the
  player on landing.

### 17.2 Cheaper routes

Par is the number of rings of the designer's route; the level should not have a cheaper one. Checked with
`tools/search_par.gd` (extra rings pre-placed, `--subset=1`, weight 1, 150000 nodes per set, so every extra ring is
free and the search is generous) and with reasoning:

| Level | Result | Strength of the evidence |
|---|---|---|
| l004 | no route with 2 rings | The three walls are 5 tiles high and a jump reaches 3.6; each needs its own launch and a ring cannot launch the player over two walls 12 tiles apart. A planner with throws and bead back (`--par=2`, 18 candidate faces, 250000 nodes) found nothing; the same planner finds the 3-ring route in under 13000 nodes. |
| l005 | no route with 1 wall ring | The sketch's calculation: one wall ring falls about 44 px short of the plateau edge. `search_par.gd --subset=1` over the 21 faces of the shaft and a planner run found nothing, but both failed to find the known 2-ring route as well, so they prove nothing here. |
| l006 | no route with 3 rings | Each of the four steps (shore to tower 1, 1 to 2, 2 to 3, tower 3 to the plateau) is 4 tiles up, a jump reaches 3.6, a floor ring 6.1 and a tower is too far from the next to share a launch; wall rings on a tower add only about 65 px (sketch: tower 2 is out of reach with floor ring and wall ring together). The planner could not find even the known 4-ring route, so this is reasoning only. |
| l007 | no route with 1 ring | `search_par.gd --subset=1` over the 46 faces right of the tunnel, weight 1, 150000 nodes per set: no finish. The same settings find the known 2-ring route when both rings are pre-placed (calibration). |
| l008 | no route with 1 ring | Same search over the 74 faces of columns 0 to 20: no finish. Before the change of 17.1 it found one: floor ring on the last ground tile reached from a jump. |
| l009 | no route with 3 rings found | The wall and the pit each need a ring besides T (stepped wall, wall flight, ring on the ground), and the one-ring jump of l008 is closed in the same way. The sketch's catch route with three rings was found on the first geometry (17.1) and is no longer found: a scan over 30 launch variants of W1 on (10, 6), the time of the throw of K at four ground cells and two segments of air control (about 100000 runs per variant) gives no finish. The same scan finds the intended route on the main variant, so it is a fair, not an exhaustive, test. |

Par stays the designer's: l004 3, l005 2, l006 4, l007 2, l008 2, l009 4. Where the evidence is thin (l005, l006) the
playtest or the tester can still find a cheaper route; then par drops and the card is edited here.

### 17.3 Tests and tools

- `tests/level_tests.gd`: the series is nine levels, with their beads, par and difficulty; `tests/ui_tests.gd`: nine
  cards, `Gehaald 1/9`, `--all-levels` opens card 9.
- Game tests 636 checks (`MIN_CHECKS` 636); kit tests untouched; level check, web export and the `tools/shots.sh`
  scenarios (checked: `select-en` with nine cards, `l006` with `--solve`) are green.
- The level select (3 columns) fits nine cards on 1280 x 720 without scrolling.
