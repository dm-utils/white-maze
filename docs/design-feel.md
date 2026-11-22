# White Maze - design section 20: feel pass after the first live play (card #028)

This file is section 20 of `docs/design.md`, kept as a separate file like sections 18 (`docs/design-look.md`) and 19
(`docs/design-camera.md`). Decision record: ADR 0012. It changes the view, the frame loop of `MazeGame` and five
camera constants. `sim/`, `levels/`, `tests/solutions.json`, the tuning (3.3) and the rules are not touched, so every
level stays solvable within par with the same solution, and determinism is unaffected.

Sections changed here: 18.6.1 (hair colour) and 18.6.2 (animation timing, pose blending, stride), 19.4 and 19.5 (target
zoom and camera constants), 4.4 (the game rate gets a level factor), 2.6 (the clock also follows the level speed),
10.4 (debug argument `--speed`) and 18.19 (web query key `speed`).

## 20.1 Owner feedback (2026-11-22, after playing the live version)

Literal:

1. Lilith: "mooi, maak het iets vloeiender en geef haar oranje haar" (nice, make it a bit smoother and give her orange
   hair).
2. Camera: "ik vind Lilith wel wat klein": from 10 to 9 tiles of visible height. Intro and headband stay as they are.
3. Speed: "het is iets te snel nu. we moeten het niet overdrijven, maar de snelheid kan naarmate men verder in het spel
   komt iets sneller worden, vooral om het begin bereikbaarder te maken voor beginners" (it is a bit too fast now; do
   not overdo it, but the speed may increase a little as one gets further into the game, mainly to make the start more
   accessible to beginners). Hard requirement from the project lead: every level stays solvable within par.

## 20.2 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| F-A1 | `MazeGame.number` is the 1-based position of the level in `levels/index.json`, also when a level is opened with `--level` (18.2 L4). | The level speed (20.6) needs another source; the table is unchanged. |
| F-A2 | `MazeWorldView.notify_events` and the new `after_tick` are called exactly once after every `sim.step`, in `MazeGame._tick` and in `_debug_setup` (true today for `notify_events`). | The smoothed look velocity of 20.3.4 would depend on the frame rate. |
| F-A3 | A full jump lifts the feet at most 3.6 tiles (144 px), the upper bound of S3. | The camera numbers of 20.5 are checked by CAM4 anyway; a higher jump would need a smaller `GUARD_TOP`. |
| F-A4 | "Smoother" refers to the figure, not to the movement of the world: the position is already interpolated between ticks (4.4) and the camera is applied in the same frame (ADR 0011). | If the owner still sees stutter after this card on a real 60 Hz or 120 Hz screen, the next suspect is browser frame pacing (uneven `delta` in the web export), not the figure. |

## 20.3 Lilith: smoother animation

### 20.3.1 What makes her look jerky today

Read from `ui/lilith.gd` and `ui/world_view.gd`:

| # | Cause | Effect |
|---|---|---|
| J1 | Hard pose switches. `body_pose` and `arm_mode` pick one discrete pose per tick and `shapes` draws it directly. | Legs and arms jump between poses in one frame: idle to run (feet jump up to 6 px), jump to fall at the apex (near foot jumps 5.6 px from knee-up to legs apart), fall to idle on landing, rest to aim and aim to throw (hand jumps up to 11 px), hair tips flip at the start of a fall. |
| J2 | Very fast run cycle. `STRIDE_PX = 28`: at 300 px/s that is 10.7 cycles per second, about 5.6 frames per cycle at 60 fps. | The legs move up to 7 px per frame and read as flicker, like an animation with too few frames. |
| J3 | Animation time in whole ticks. Idle bob, tail flutter, landing squash, throw swing, death tilt and both fades use `sim.tick`. | They step at 60 Hz while the position is interpolated; on a 120 or 144 Hz screen and in slow motion (15 ticks per second) the steps are visible. |
| J4 | Look velocity per tick. Tails and launch tilt use `sim.vx`, `sim.vy` of the last tick. | At a launch or a landing the tails swing round in one frame. |
| J5 | Pause and overview set `world.alpha = 1`. | Lilith and the camera jump forward by up to one tick (5 px) when the game is paused or the overview is held. |

Position interpolation (4.4) is already in place and is not the cause; the camera already uses the interpolated
position.

### 20.3.2 Render time

All animation uses one float clock, the **render time** in ticks:

```
t = float(sim.tick) - 1.0 + alpha        # alpha as in 4.4; t = sim.tick when alpha is 1 (frozen, finished)
```

The drawn position `lerp(prev, current, alpha)` is the state at exactly this time, so pose and position agree. Every
place that uses `sim.tick` or `sim.dead_ticks` for Lilith uses `t` instead:

| Value | Today | New |
|---|---|---|
| Idle bob, tail flutter | `tick` (int) | `t` (float); `shapes` takes `tick` as a float |
| Landing squash | `1 - (tick - land_tick) / LAND_TICKS` | `age = t - land_tick`; `squash_k = 0` when `age < 0`, `age` while `age < 1`, else `maxf(0, 1 - (age - 1) / LAND_TICKS)` (rises over one tick, so there is no jump at the landing frame) |
| Throw swing | `since_throw / THROW_TICKS` | `clampf((t - throw_tick) / THROW_TICKS, 0, 1)` |
| Death tilt, death fade | from `sim.dead_ticks` | `dead_age = clampf(t - death_tick, 0, DEATH_TICKS)`; `dead_k = dead_age / DEATH_TICKS`; fade `1 - dead_k` |
| Respawn fade-in | `(tick - respawn_tick) / FADE_IN_TICKS` | `clampf((t - respawn_tick) / FADE_IN_TICKS, 0, 1)` |

Pose choice (`body_pose`, `arm_mode`) and `since_throw < THROW_TICKS` stay integer tick logic. The ring flash and the
bead flight already use `alpha` and stay as they are.

`MazeGame.advance` keeps `world.alpha = _acc / TICK_S` while paused or in the overview (only `frozen` and a finished
sim set 1), which removes J5. `_acc` already survives a pause.

### 20.3.3 Pose blending (`MazeLilith` rig, `MazePoseBlend`)

The figure is described by a small **rig** of joints; shapes are built from the rig. A change of pose blends from the
rig as last drawn to the new pose over `BLEND_TICKS` of render time.

```gdscript
# ui/lilith.gd, additions
static func rig(p: Dictionary) -> Dictionary
	# {"near_foot", "far_foot", "hand_near", "hand_far": Vector2, "drop": float, "tilt": float (radians),
	#  "hair_up": float 0..1}; the values shapes() uses today, for body, arm, phase, aim_angle, throw_k, vel, tick
static func blend_rig(a: Dictionary, b: Dictionary, k: float) -> Dictionary   # per key lerp, k in 0..1
# shapes(p): uses p["rig"] when present, else rig(p). Hips, boots, arms and hair are built from the rig.
# The hair polygon's back point is lerp((-6.8, -27.0), (-8.0, -30.5), hair_up).
```

```gdscript
class_name MazePoseBlend extends RefCounted   # ui/pose_blend.gd, pure
const BLEND_TICKS := 6.0
var enabled := true
func reset() -> void                                                # next apply() starts without a blend
func apply(key: Vector2i, target: Dictionary, t: float) -> Dictionary
	# key = Vector2i(body, arm). When key differs from the previous key: start a blend from the rig returned by the
	# previous apply() at time t, unless the old or new body is DEAD, the blend is disabled, or there was no previous
	# apply (then switch at once). Returns blend_rig(from, target, smoothstep(0, 1, (t - start) / BLEND_TICKS)).
	# A new switch during a blend starts from the rig as last returned, so nothing ever jumps.
```

- `MazeWorldView` owns one `MazePoseBlend` (`var blend`); `_draw_player` computes `target = MazeLilith.rig(p)`, then
  `p["rig"] = blend.apply(Vector2i(body, arm), target, t)`. The squash, the death tilt and the fade stay global
  transforms after the rig, as today.
- `reset()` at `MazeWorldView.reset()` (attempt start) and at the `respawn` event.
- `MazeGame` sets `world.blend.enabled = not frozen` every frame, so `--shot`, `--keys`, `--aim` and `--camera` shots
  show the target pose at once (they draw a frozen state; a blend would never finish).
- The blend runs in render time, so it slows down with slow motion and the level speed (20.6), and it holds while
  paused.
- The target keeps animating during a blend (the run cycle runs on while blending from idle).

### 20.3.4 Smoothed look velocity

`MazeWorldView.after_tick()` (new, called by `MazeGame` right after every `notify_events`, F-A2):

```
_look_prev = _look_cur
_look_cur  = _look_cur.lerp(Vector2(sim.vx, sim.vy) * 60.0 / 1000.0, LOOK_FOLLOW)   # LOOK_FOLLOW = 0.35 per tick
```

Both are set to zero at `reset()` and at `respawn`. `_draw_player` passes `vel = _look_prev.lerp(_look_cur, alpha)`
(mirrored by `_face` as today) to the tails and the launch tilt. A launch turns the tails round over about six ticks
instead of one frame. The camera keeps using the raw velocity (19.5).

### 20.3.5 Run cycle

`STRIDE_PX` goes from 28 to **48**: 6.25 cycles per second at 300 px/s (9.6 frames per cycle at 60 fps), 5 cycles per
second at the level speed of l001 (20.6). Leg swing (`+-6` px) and lift (3 px) stay, so the bounds of 18.6.1 (A2) are
unchanged. The phase still comes from the interpolated `x`, so the legs never run faster than the ground moves.

### 20.3.6 Not changed

No new poses, no take-off stretch, no secondary motion beyond the existing tails. These can follow after the owner has
seen this pass.

## 20.4 Lilith: orange hair

| Constant | Old | New |
|---|---|---|
| `MazeLilith.HAIR` | `#3A2418` (dark brown) | `#C4701A` (copper orange; hue 30.4 degrees, HSV saturation 0.87, value 0.77) |

Everything else of Lilith keeps its colour; the headband stays `#E0306E`. The hair keeps its dark outline (18.6.1), which
separates it from blocks next to her (she is never drawn over a solid cell, only next to one).

Checked values (WCAG contrast with `MazeArt.contrast`, hue in degrees):

| Pair | Value | Rule (test F7) |
|---|---|---|
| Hair against `back_top`: temple, jungle, cave | 4.2, 4.1, 4.3 | `>= 3.0` |
| Hair against `back_bottom`, every world | higher than against `back_top` (darker backs) | `>= 3.0` |
| Hair hue against `HAZARD` (6.3) | 24.1 | `>= 20` (orange, not the spike red) |
| Hair hue against the headband (339) | 51.4 | `>= 30` (the band stays a separate mark on the hair) |
| Hair against skin `#D9A07A` | 1.63 | `>= 1.5` (hair and face do not merge) |

Why this tint: a lighter orange (hue 28 to 35, value above 0.85) is close to the skin in luminance and to the temple
torch `light` `#FFB45A`; a redder copper (hue below 22) comes within 16 degrees of the spike red. `#C4701A` sits between
both. Against the temple block `#C29A62` the luminance contrast is low (1.4), which is acceptable because of the outline
and because the back wall, not a block, is behind her.

## 20.5 Camera: 9 tiles of height

### 20.5.1 Constants (`MazeCameraRig`)

| Constant | Old | New | Why |
|---|---|---|---|
| `VIEW_H_TILES` | 10 | **9** | Owner. |
| `FEET_Y` | 0.68 | **0.70** | Keeps a full jump inside the play rect without moving the view (20.5.3). |
| `GUARD_TOP` | 60 | **40** | Same. |
| `GUARD_BOTTOM` | 100 | **96** | Same. |
| `AIM_MARGIN` | 60 | **40** | Keeps the reach of aim framing close to what it was (20.5.3). |

All other constants of 19.5 stay, including the intro (`INTRO_*`, `SKIP_BLEND_S`), the overview and `MIN_VIEW_W_TILES`
(16). Nothing changes in the headband or the intro behaviour.

### 20.5.2 Resulting numbers

`z = min(canvas.y / 360, canvas.x / 640)`:

| Screen | Canvas | z (old) | z (new) | Visible world (tiles) | Play rect (tiles) | Lilith |
|---|---|---|---|---|---|---|
| Desktop 1280 x 720 | 1280 x 720 | 1.8 | 2.0 | 16 x 9 | 16 x 7.6 | 64 canvas px, 8.9 % (was 8.0 %) |
| Phone 960 x 432, 20:9 | 1600 x 720 | 1.8 | 2.0 | 20 x 9 | 20 x 7.6 | 38 physical px on 432 (was 35), 8.9 % |
| Tablet 4:3 | 1280 x 960 | 2.0 | 2.0 | 16 x 12 | 16 x 10.6 | 6.7 %, unchanged (the width term decides) |

On 16:9 the height and width terms are now equal; 16:9 is the narrowest screen where the height decides.

Play rect on desktop: `Pw = 640`, `Ph = (720 - 110) / 2 = 305` world px.

### 20.5.3 Checks

- **Calm jumps (CAM4).** At rest the player centre is `0.70 * 305 - 16 = 197.5` px below the top of the play rect; a
  full jump raises it at most 144 px (F-A3), leaving 53.5 px, above `GUARD_TOP` 40. With the old values at the new zoom
  it would be `0.68 * 305 - 16 - 144 = 47.4` px, below the old guard of 60: every full jump would have pushed the view up.
  With a safe area top inset of 24 (band 134, `Ph = 293`) the margin is 45.1 px, still above 40.
- **Bottom guard at rest.** The centre is `0.30 * 305 + 16 = 107.5` px above the bottom (`Ph = 293`: 103.9), above
  `GUARD_BOTTOM` 96, so standing never pushes the view. Visible below the feet at rest: 91.5 px (2.3 tiles, was 2.7).
- **Falling (CAM7).** `GUARD_BOTTOM_FALL` stays 160: at least 144 px (3.6 tiles) below the feet while falling, as
  before. `GUARD_TOP + GUARD_BOTTOM_FALL = 200 < 0.8 * Ph = 244`, so the portrait scaling of 19.5 does not kick in on
  landscape screens.
- **Look-ahead.** `LOOK_X` stays 120 px (3 tiles). It is below `Pw / 2 - GUARD_X = 200`, so look-ahead and side guard do
  not fight. Walking right at 300 px/s the view leads by about 77 px: about 9.9 tiles visible ahead and 6.1 behind on
  desktop (was 12 and 6), 11.9 and 8.1 on the phone canvas. A running full jump clears 4 tiles, so the landing is always
  in view. At a lower level speed (20.6) the camera lag is smaller (the camera runs in real time), so the lead is a few
  px larger.
- **Aim framing (CAM8).** Horizontal reach of framing is `(Pw / 2 - AIM_MARGIN) + (Pw / 2 - GUARD_X)`: with the old
  margin 260 + 200 = 460 px, with the new margin 280 + 200 = 480 px (was 530 at zoom 1.8). The CAM8 fixture (wall 12
  tiles right, hit about 458 px away) fits with 22 px to spare. Vertical reach upwards: `(Ph / 2 - AIM_MARGIN) +
  (Ph / 2 - GUARD_BOTTOM) = 112.5 + 56.5 = 169` px (was 179).
- **Edge marker.** Unchanged: drawn where the line leaves `play_rect().grow(-24)` (world px), now 48 canvas px from the
  edge (was 43), clear of the 24 px scrim fade under the HUD band; chevron 20 canvas px long (was 18).
- **`aim-frame` shot (19.15).** `--level=l001 --keys=R40 --aim=0` hits at 800 px, beyond the reach of 480 px, so it
  would show the edge marker instead of a framed target. The developer picks a new `--keys`/`--aim` pair on l001 whose
  hit is outside the follow view but within 480 px, and writes it into `tools/shots.txt`.
- **Intro.** Same constants; the door view uses the new zoom. More levels now start with the door out of view, so the
  intro plays on more levels (it is skipped when the door is already visible, 19.9).
- **Overview.** `fit_zoom` is capped by `target_zoom`; every shipped level is far larger than the view, so the overview
  zoom values of 19.8 are unchanged.
- **Baked chunks (18.19).** `SCALE` 2 texels per world px gives 1.0 texel per canvas unit at zoom 2.0 (was 1.1). On a
  1920 x 1080 window that is 0.67 texel per screen px, slightly softer edges. Left as is (raising `SCALE` to 3 multiplies
  the texture memory by 2.25, above the 24 MB per level of 18.19); the tester judges the shots.

## 20.6 Game speed per level

### 20.6.1 Options

1. **Time scale per level** (chosen): the level runs at fewer ticks per real second, the same mechanism as the slow
   motion of ADR 0003. Every trajectory in ticks and tiles stays identical; only real time stretches.
2. **Slower tuning per level** (lower `RUN_SPEED`, `JUMP_SPEED`, gravity, launches): rejected. Jump heights and widths,
   the ring metrics of 3.3 and the level rules ("3 tiles can be jumped, 4 cannot") would change per level; the
   solutions in `tests/solutions.json` and the par searches would no longer hold; the simulation would need a level
   input. This is exactly what the hard requirement forbids.
3. **Only a lower walking speed** (global or per level): rejected. The running gap of 4 tiles depends on `RUN_SPEED`, so
   levels with long jumps (l003, l007, l009) could become unsolvable; it also breaks the solutions.
4. **`Engine.time_scale`**: rejected as in ADR 0003 (also slows tweens, the camera, UI animations and input repeat).

Effect of a time scale `s` on the feel, so it is not overdone: horizontal speeds look `s` times as fast, gravity looks
`s^2` as strong, every duration (a jump, the death pause, a bead flight) takes `1 / s` as long in real time. At
`s = 0.80` a jump hangs 25 % longer, which gives a beginner more time to react and to aim; at 0.96 the difference with
today is barely noticeable.

### 20.6.2 The curve

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 and later |
|---|---|---|---|---|---|---|---|---|---|---|
| Speed (% of today) | 80 | 82 | 84 | 86 | 88 | 90 | 92 | 94 | 96 | 96 |
| Walking, as seen (px/s) | 240 | 246 | 252 | 258 | 264 | 270 | 276 | 282 | 288 | 288 |

- Linear, 2 points per level; the last level stays just below today's speed, which the owner found a bit too fast.
- Keyed by the series position (`MazeGame.number`, F-A1), like the worlds (18.3): reordering the index moves a level to
  the speed of its new position. No level field (no format change).
- The table is one constant and can be tuned after the playtest without touching anything else.

### 20.6.3 Implementation (`MazeGame`)

```gdscript
const SPEED_PCT := [80, 82, 84, 86, 88, 90, 92, 94, 96]   # per series position; later levels use the last value
const SPEED_MIN_PCT := 50
const SPEED_MAX_PCT := 150
var speed := 1.0                                            # level speed, set in _ready

static func level_speed(number: int) -> float              # SPEED_PCT[clampi(number, 1, SPEED_PCT.size()) - 1] / 100.0
```

- `_ready`: `speed = options["speed"] / 100.0` when `int(options.get("speed", 0)) > 0`, else `level_speed(number)`.
- `advance`: `_acc += minf(delta, MAX_FRAME_S) * rate * speed`. `rate` keeps its meaning (aim slow motion, pause,
  overview); `next_rate` is unchanged. **The world dimming test stays `rate < 1.0`**, so a level at 80 % is not drawn
  dimmed.
- `MAX_STEPS` (6) and `MAX_FRAME_S` (0.1) stay.
- Nothing else changes: the camera, the intro, the overview blend, input repeat and the HUD run in real time; Lilith's
  animation runs in render time (20.3.2) and therefore at the level speed, like everything in the world.

### 20.6.4 Slow motion, clock, runs, replays, determinism, profile

- **Slow motion.** Effective game rate = `rate * speed`. Aiming on l001 runs at `0.25 * 0.80 = 0.20` of today's speed
  (12 ticks per real second), on l009 at 0.24. The ramp of 4.4 is unchanged (it ramps `rate`).
- **Clock.** The clock stays game time in ticks (ADR 0003): on l001 it runs at 80 % of a wall clock, as it already runs
  at 25 % while aiming. A time in ticks does not depend on the speed table, so changing the table later never makes old
  best times better or worse.
- **Run scripts and solutions.** A run script is one input per tick; the speed only decides how many ticks pass per real
  second. Recorded runs, `best_run`, `--keys`, `--solve`, `tests/solutions.json`, `tools/check_levels.gd` and
  `tools/search_par.gd` are unaffected. Par and rings used are unaffected: the solution of every level reaches the finish
  with the same `rings_used` at the same tick.
- **Replays (phase 3, and ghosts later).** A replay is fed tick by tick and shown at the level speed of the playing
  build; server verification counts ticks and never needs the speed.
- **Determinism.** `sim/` gets the same `MazeInput` per tick and is not changed; S17 holds. The only difference for the
  player is finer input timing (more frames per tick); presses between ticks are latched (ADR 0003).
- **Profile.** No new field; `tick_hz` stays 60; `play_ticks` stays game time.

### 20.6.5 Debug argument and web query

- `--speed=<pct>`: integer 50 to 150, overrides the table for every level of the session (`MazeMain.parse_args` key
  `speed`, default `0` = table). Other values: `push_warning`, ignored.
- Web query key `speed` (added to `QUERY_KEYS`, 18.19), for example `?speed=90`, so the owner can try values in the
  browser. Not a setting in the game.

## 20.7 Acceptance

- F1 `level_speed` gives 0.80, 0.82, ..., 0.96 for numbers 1 to 9 and 0.96 for 10 and 12; `--speed=110` gives 1.1 for
  every level; `--speed=20` and `--speed=abc` are ignored with a warning.
- F2 In `MazeGame` on l001 at the table speed, holding right for 300 frames of 1/60 s gives `sim.tick` 240 (within 1),
  and `sim.snapshot()` equals a fresh `MazeSim` stepped with the same number of `move = 1` inputs. With `speed` 100 the
  same walk gives 300 ticks. Aiming on l001 for one real second after the ramp gives 12 ticks (within 1). Not aiming,
  `world.modulate` is white.
- F3 Simulation untouched: `git diff <base> -- sim/ levels/ tests/solutions.json` is empty; all existing checks green
  (`MIN_CHECKS` only goes up); `tools/check_levels.gd` exits 0, so every level is solved within par.
- F4 Render time: with `world.alpha` 0.25 and 0.75 between the same two ticks, the landing squash, throw swing, fades
  and idle bob differ (not stepped per tick); with `alpha` 1 they equal the values of the integer tick (frozen shots
  unchanged apart from colour and stride).
- F5 Smoothness: in `MazeGame` with `speed` 100 and frames of 1/120 s, a scripted sequence (stand, walk right, stop,
  full jump, fall, land, walk, keyboard aim start, throw, launch on a floor ring) gives, between any two consecutive
  frames, a movement of at most 3.5 px for every rig joint (`near_foot`, `far_foot`, `hand_near`, `hand_far`) in
  Lilith's local frame, and at most 2 degrees of `tilt`. Frames at a death, a respawn or a change of `_face` are
  excluded. The world view exposes the last drawn rig (`last_rig`) for this test. (Today's code fails this at the apex,
  at the start of a run and at the start of an aim.)
- F6 `MazePoseBlend`: a key change starts at the last returned rig (no jump at the switch frame); after `BLEND_TICKS` of
  `t` the result equals the target; a switch during a blend starts from the current blended rig; with `enabled` false
  or with `DEAD` on either side it switches at once; `reset` makes the next call switch at once.
- F7 Hair: the contrast and hue rules of 20.4 in `art_tests.gd`, for all three worlds; the headband rule of 18.18 (25
  degrees from `HAZARD`) still holds.
- F8 Bounds (A2) also hold for blended rigs: the A2 sweep is repeated with `blend_rig(rig(a), rig(b), k)` for every
  pair of non-`DEAD` body poses, every arm mode and `k` in {0.25, 0.5, 0.75}.
- F9 Camera: CAM1 gives 2.0 for 1280 x 720, 1600 x 720 and 1280 x 960, Lilith's share at least 0.085 on 1280 x 720 and
  1600 x 720 and at least 0.065 on 1280 x 960; CAM2 to CAM16 green with the new constants (tests read the constants or
  the computed zoom, no hard-coded 1.8); CAM4 also with band 134.
- F10 Shots: all scenarios produced without errors; `aim-frame` shows the framed target with Lilith in view.

## 20.8 Developer steps (card #029)

Branch `feature/feel-pass`, one commit per step, merged after the tests are green and the tester has reviewed it.

1. **Camera.** Constants of 20.5.1 in `ui/camera_rig.gd`; replace the hard-coded 1.8 in `tests/camera_tests.gd` by
   `target_zoom` of the test canvas; CAM1 values of F9; new `aim-frame` pair in `tools/shots.txt`.
2. **Level speed.** `SPEED_PCT`, `level_speed`, `speed`, the `advance` change (20.6.3); `--speed` in `parse_args` and
   `speed` in `QUERY_KEYS`; F1 and F2 in a new suite `tests/feel_tests.gd` (added to `SUITES`). Existing tests that
   assume 60 ticks per real second of `advance` (the A1 snapshot test, CAM10 to CAM13, `ui_tests.gd`,
   `screens_tester_tests.gd`) set the option `speed` to 100; tests that compare two runs at the same speed need nothing.
3. **Lilith.** `HAIR` (20.4); `STRIDE_PX` 48; `rig`, `blend_rig` and `shapes` from the rig in `ui/lilith.gd`;
   `ui/pose_blend.gd`; render time, `after_tick`, look velocity, `last_rig` and the blend in `ui/world_view.gd`; in
   `MazeGame`: `after_tick` after every `notify_events`, `world.blend.enabled = not frozen`, `alpha` kept while paused
   or in the overview (20.3.2). Tests F4 to F8 in `tests/feel_tests.gd` and `tests/art_tests.gd`.
4. **Documentation.** Deviations as built in section 20.10 of this file; raise `MIN_CHECKS`; in `docs/design.md` add
   `## 20. Feel` with a pointer to this file (like 18 and 19) and mention it in the status line; in
   `docs/design-camera.md` 19.4 and `docs/design-look.md` 18.6.1 and 18.6.2 add one line each: "Changed by section 20
   (`docs/design-feel.md`)"; add `MazePoseBlend` to the class list in `docs/conventions.md`; `--speed` in design 10.4.

## 20.9 Tester checklist (card #030)

Headless: F1 to F10 and the diff of F3; `tools/check_levels.gd` output shows every solution within par.

Shots (`tools/shots.sh`), at 100 % and on the phone sizes: Lilith larger than before (about 8.9 % of the height), orange
hair readable in `temple`, `jungle`, `cave`, `jungle-on-l001`, `cave-on-l001` and `phone-small`; hair clearly different
from the spikes in the spike pit shots (`lilith-dead`, l001 and l003) and from the headband; nothing cut off under the
HUD band; `aim-frame` and `aim-edge` as in 19.13.

Play in a desktop browser (web export), and on a phone if possible, on a 60 Hz screen and, if available, 120 or 144 Hz:

- Lilith: starting to run, stopping, the top of a jump, landing, starting an aim and throwing have no visible jump in
  the legs or arms; the run cycle reads as running, not as flicker; the tails swing round at a launch instead of
  snapping; in slow motion she moves smoothly, not in steps.
- Speed: l001 feels calmer than the live version; the step from level to level is not noticeable on its own, l009 is
  close to the live version. Compare with `?speed=100`.
- Camera: a full jump on flat ground does not move the view; falling into a pit shows the ground below in time; the
  landing of a running jump is in view; the intro and the overview behave as before.

## 20.10 Deviations as built

Built as designed (card #029, branch `feature/feel-pass`, game tests 1099 checks, `MIN_CHECKS` 1099). No rule, tuning
value, level or solution changed; `git diff b0c5c23 -- sim/ levels/ tests/solutions.json` is empty and
`tools/check_levels.gd` exits 0 with every solution within par. Points the design left open:

- `aim-frame` is `--level=l001 --keys=R60 --aim=0`: the ring on the far wall is 416 px from Lilith and outside the
  follow view, inside the reach of 480 px (20.5.3). The shot shows the framed ring with Lilith in view.
- `MazeWorldView.player_params()` is public: `_draw_player` was split so that the pose, the blend and `last_rig` are
  computed without drawing. F4 and F5 call it after every `MazeGame.advance`; the draw calls the same function.
- `MazeGame` has `SPEED_MIN_PCT` (50) and `SPEED_MAX_PCT` (150) next to `SPEED_PCT`; `MazeMain.parse_args` reads them.
- Death age uses `_death_tick` when set, else `sim.tick - (DEATH_TICKS - dead_ticks)`, so a view without the death
  event still fades correctly.
- F7 and F8 are in `tests/art_tests.gd` (next to A2 and A3), F1 and F2 and F4 to F6 in `tests/feel_tests.gd`. F8 samples
  6 of the 144 aim directions, three phases and three throw progressions per pose pair.
- F5 result on l001 (a scripted walk, jump, aim and throw, then the solution with its ring launches, 1831 measured
  frames of 1/120 s): largest joint step 1.95 px (`far_foot`), largest tilt step 1.40 degrees.
- Existing tests that assume 60 ticks per second pass `--speed=100` (A1, CAM10 to CAM13, `ui_tests.gd`,
  `screens_tester_tests.gd`).

## 20.11 Open points for the owner

- The speed table (80 to 96 %) is a start value; try `?speed=` in the browser and give a number for level 1 and level 9.
- The clock shows game time, so on level 1 it runs at 80 % of a wall clock (as it does at 25 % while aiming). If the
  owner prefers a clock in real seconds, that is a display change only (times in the profile stay in ticks).
- Hair tint `#C4701A`; a lighter ginger is possible but comes close to the skin and the torch light (20.4).
