# White Maze - design section 19: follow camera (card #017)

This file is section 19 of `docs/design.md`, kept as a separate file like section 18 (`docs/design-look.md`).
Decision record: ADR 0011. It changes only the view: `sim/`, `levels/`, `tests/solutions.json`, the tuning and the
rules are not touched, and determinism is unaffected (the camera reads the simulation, nothing flows back).

Sections replaced or extended here: design 8.3 (camera bullet), 16.1 (camera deviation), 4.1 and 4.2 (new action
`overview`), 4.6 (map button), 8.6 (texts), 10.4 (debug argument `--camera`), 10.5 and 18.14 (screenshot scenarios),
18.11 (the HUD scrim moves into this card) and assumption L2 of 18.2 (the world is no longer drawn at 1 world px = 1
viewport unit).

## 19.1 Owner decision (2026-11-22)

Literal: "Verder inzoomen op het level:, het hele af te leggen pad hoeft niet direct in beeld, het mag verschuiven
naarmate je verder komt" (zoom in further on the level; the whole path does not have to be in view at once, it may
scroll as you progress).

## 19.2 Current state and problem

- The game screen has a `Camera2D` at zoom 1 (design 8.3, 16.1): it follows the player with Godot's position
  smoothing (speed 8) and a 60 px look-ahead in the facing direction, with limits at the level bounds.
- The project stretches `canvas_items` with aspect `expand` from a base of 1280 x 720 (design 10.2). In landscape at
  16:9 or wider the canvas is therefore always 720 units high (a 960 x 432 phone gets a canvas of 1600 x 720 at scale
  0.6). At zoom 1 the world shows 18 tiles of height: every shipped level (14 to 24 rows) fits or nearly fits.
- Lilith (32 px high) is 32 / 720 = 4.4 % of the screen height: 32 px on a 720 px desktop window and 19 physical px on
  a 960 x 432 phone. Headband, bandolier and other details of section 18.6 disappear.

## 19.3 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| V1 | Stretch mode `canvas_items`, aspect `expand`, base 1280 x 720 stay (design 10.2). Landscape screens of 16:9 or wider give a canvas of height 720; narrower ones (4:3) a canvas of width 1280 and height above 720. | The zoom formula (19.4) still holds, the numbers in its table change. |
| V2 | `Camera2D.force_update_scroll()` applies the new canvas transform in the same frame (Godot 4.7). | Set `get_viewport().canvas_transform` directly instead; the rig is unchanged. |
| V3 | Camera feel can only be judged by playing. The constants of 19.5 are start values, like the tuning of 3.3. | Change the constants; the tests of 19.12 check structure and bounds, not taste. |
| V4 | Chunk `draw` signals of the static layers (18.7) fire once per chunk regardless of whether the chunk is on screen, so A6 keeps holding. | A6 counts `build()` calls instead of draws (as 18.2 L6 already allows). |
| V5 | Freezing the game during the overview (19.8) adds no advantage: the pause already stops the clock and the simulation. | Let the game run in slow motion during the overview instead; only `MazeGame` changes. |

## 19.4 Zoom

One fixed zoom per screen size, the **target zoom**. It does not change while playing, except for the overview (19.8).

```
z = min(canvas.y / (VIEW_H_TILES * 40), canvas.x / (MIN_VIEW_W_TILES * 40))
VIEW_H_TILES = 10, MIN_VIEW_W_TILES = 16
```

`canvas` is `get_viewport().get_visible_rect().size` (canvas units). Lilith's share of the screen height is
`32 * z / canvas.y` = 8.0 % whenever the height term decides, which is every landscape screen of 16:9 or wider.

| Screen | Canvas | z | Visible world (tiles) | Play rect below the HUD band (tiles) | Lilith on screen |
|---|---|---|---|---|---|
| Desktop 1280 x 720 (and 1920 x 1080) | 1280 x 720 | 1.8 | 17.8 x 10 | 17.8 x 8.5 | 58 canvas px, 8.0 % (now 4.4 %) |
| Phone 960 x 432 (and 2400 x 1080, 20:9) | 1600 x 720 | 1.8 | 22.2 x 10 | 22.2 x 8.5 | 35 physical px on 432, 8.0 % (now 19 px) |
| Tablet 1024 x 768 (4:3) | 1280 x 960 | 2.0 | 16 x 12 | 16 x 10.6 | 64 canvas px, 6.7 % |

- The width term only decides on screens narrower than 16:9 (tablets). It keeps at least 16 tiles of width so
  running and throwing still have room; Lilith is then 6.7 % instead of 8 %.
- Small levels: the zoom never goes above `z`. When a level is narrower than the play rect it is centred
  horizontally; when it is lower than the play rect it is centred vertically in the play rect. No shipped level is that
  small (the smallest is 32 x 14 tiles), so today every level scrolls in both directions.
- The HUD band (`HUD_BAND + safe area top`, 110 canvas units plus the inset) is not part of the play rect: the camera
  frames the player and the level in the **play rect**, the area of the screen below the band.
- Line widths and sizes of sections 8.1 and 18 stay in world px, so they grow by `z` on screen. The step 2 review of
  section 18 (lips, joints, ring strokes) is done at this zoom; that is one reason to build the camera first (19.14).

## 19.5 The camera rig (`MazeCameraRig`, `ui/camera_rig.gd`)

A pure `RefCounted` (no nodes, no `Input`, no `Time`), testable headless with explicit time steps. `MazeGame` feeds it
once per frame and copies its result into the `Camera2D`. Godot's camera smoothing, drag margins and limits are not
used (ADR 0011).

```gdscript
class_name MazeCameraRig extends RefCounted
const TILE := 40.0
const VIEW_H_TILES := 10.0
const MIN_VIEW_W_TILES := 16.0
const FEET_Y := 0.68             # height of the ground anchor in the play rect, as a fraction from its top
const LOOK_X := 120.0            # px look-ahead in the walking direction (3 tiles)
const LOOK_SPEED := 180.0        # px/s at which the look-ahead moves
const LOOK_MIN_VX := 60.0        # px/s: slower horizontal motion keeps the last look direction
const LOOK_TURN_S := 0.2         # a new walking direction must last this long before the look-ahead turns
const X_RATE := 7.0              # 1/s, exponential follow horizontally
const Y_RATE := 3.5              # 1/s, exponential follow vertically (calm)
const GUARD_X := 120.0           # px: player centre at least this far from the left and right edge of the play rect
const GUARD_TOP := 60.0          # px: player centre at least this far below the top of the play rect
const GUARD_BOTTOM := 100.0      # px: player centre at least this far above the bottom of the play rect
const GUARD_BOTTOM_FALL := 160.0 # px: the same while falling below the last ground
const GUARD_SPEED := 300.0       # px/s at which the bottom guard changes between the two values
const FALL_MIN := 40.0           # px: feet this far below the ground anchor count as falling below it
const AIM_MARGIN := 60.0         # px: aim framing keeps the hit point this far inside the play rect
const AIM_RATE := 6.0            # 1/s, exponential approach of the aim offset
const INTRO_HOLD_S := 0.8
const INTRO_PAN_SPEED := 900.0   # px/s; pan time clamped to INTRO_PAN_MIN_S..INTRO_PAN_MAX_S
const INTRO_PAN_MIN_S := 0.8
const INTRO_PAN_MAX_S := 2.0
const SKIP_BLEND_S := 0.3
const OVERVIEW_BLEND_S := 0.25
const OVERVIEW_PAD := 20.0       # canvas units of free space around the level in the overview
const MAX_DT := 0.1

static func target_zoom(canvas: Vector2) -> float                                   # 19.4
static func fit_zoom(level_px: Vector2, canvas: Vector2, band: float) -> float      # 19.8
func setup(level_px: Vector2, canvas: Vector2, band: float, door: Vector2) -> void  # every frame; cheap
func snap(f: Dictionary) -> void                    # follow state jumps to its target (no smoothing)
func update(dt: float, f: Dictionary) -> void       # one frame of real time
func start_intro() -> void
func skip_intro() -> void
func intro_active() -> bool
func set_overview(on: bool) -> void
var debug_view := ""                                 # "", "door" or "overview" (--camera, 19.11)
func view_centre() -> Vector2    # world px: the Camera2D position (centre of the whole viewport)
func view_zoom() -> float
func play_rect() -> Rect2        # world px: the part of the world visible below the HUD band
func overview_k() -> float       # 0..1, smoothstep weight of the overview
```

- `level_px` = level size in px; `canvas` = visible canvas size; `band` = `HUD_BAND + ins.top` in canvas units;
  `door` = centre of the `F` cell in world px.
- Frame dictionary `f` (all world px, px/s):

| Key | Type | Value from `MazeGame` |
|---|---|---|
| `player` | Vector2 | `world.player_centre()` (interpolated with `alpha`, 4.4) |
| `vel` | Vector2 | `Vector2(sim.vx, sim.vy) * 60 / 1000` |
| `grounded`, `alive` | bool | `sim.grounded`, `sim.alive()` |
| `facing` | int | `sim.facing` (only used by `snap`) |
| `aim_frame` | bool | aim framing wanted (19.7) |
| `aim_hit` | Vector2 | `Vector2(sim.cast(index)["hit"]) / 1000` when `aim_frame`, else unused |
| `flights` | bool | `not sim.flights.is_empty()` |

- Derived sizes, recomputed in `setup`: `z = target_zoom(canvas)`; play rect size at target zoom
  `Pw = canvas.x / z`, `Ph = (canvas.y - band) / z`. When `GUARD_TOP + GUARD_BOTTOM_FALL > 0.8 * Ph` (only in portrait,
  where the rotate hint pauses the game) all vertical guards are scaled by `0.8 * Ph / (GUARD_TOP + GUARD_BOTTOM_FALL)`,
  so the clamps never cross.
- Everything is in real time (`dt = minf(delta, MAX_DT)`): the camera is the player's eye, not part of the world, so
  it keeps its pace during slow motion. Smoothing is exponential and frame-rate independent:
  `k = 1 - exp(-RATE * dt)`.

## 19.6 Follow

State: `c` (centre of the play rect, world px), `anchor_y` (feet height of the last ground), `look_x`, `look_dir`
(-1 or 1), `turn_t`, `guard_b`, `aim_off` (Vector2), `aim_want` (Vector2), `aim_hold` (bool).

`update(dt, f)`, follow part, in this order:

1. When `not f.alive`: `aim_want = 0`, `aim_hold = false`, and the rest of the follow state does not change (the
   camera holds where the player died); go to the presentation part (19.9).
2. `feet_y = f.player.y + 16`. When `f.grounded`: `anchor_y = feet_y`.
3. `falling = not f.grounded and f.vel.y > 0 and feet_y > anchor_y + FALL_MIN`. `ref_y = maxf(anchor_y, feet_y)`:
   the reference follows the player down, never up (jumps and launches above the last ground do not move it).
4. Look-ahead: `vdir = signf(f.vel.x)` when `absf(f.vel.x) >= LOOK_MIN_VX`, else 0. When `vdir != 0` and
   `vdir != look_dir`: `turn_t += dt`, and when `turn_t >= LOOK_TURN_S`: `look_dir = vdir`, `turn_t = 0`. Otherwise
   `turn_t = 0`. Then `look_x = move_toward(look_x, look_dir * LOOK_X, LOOK_SPEED * dt)`. The direction comes from the
   velocity, not from `facing`, so a wall launch looks where the player flies and a short tap the other way does not
   swing the view.
5. Base target: `t = Vector2(f.player.x + look_x, ref_y - (FEET_Y - 0.5) * Ph)`. With the feet on the ground the play
   rect shows 0.68 of its height above the feet (5.8 tiles on desktop) and 0.32 below (2.7 tiles).
6. Aim offset (19.7): update `aim_want`; `aim_off += (aim_want - aim_off) * (1 - exp(-AIM_RATE * dt))`;
   `t += aim_off`.
7. Smoothing: `c.x += (t.x - c.x) * (1 - exp(-X_RATE * dt))`; `c.y += (t.y - c.y) * (1 - exp(-Y_RATE * dt))`.
8. Guards (hard clamps on the state, so the player never leaves the play rect and there is no catch-up afterwards):
   `guard_b = move_toward(guard_b, GUARD_BOTTOM_FALL if falling else GUARD_BOTTOM, GUARD_SPEED * dt)`;
   `c.x = clampf(c.x, p.x - (Pw / 2 - GUARD_X), p.x + (Pw / 2 - GUARD_X))`;
   `c.y = clampf(c.y, p.y - (Ph / 2 - guard_b), p.y + (Ph / 2 - GUARD_TOP))` with `p = f.player`.
9. Level clamp (last, wins over the guards; the player is inside the level, so it stays visible):
   `c.x = clampf(c.x, Pw / 2, level_px.x - Pw / 2)` when `level_px.x >= Pw`, else `level_px.x / 2`; the same for `y`
   with `Ph`. The play rect never shows anything outside the level; above the level only the HUD band can show the
   `void` colour (18.7).

Resulting behaviour (desktop numbers):

- Walking right at 300 px/s: the view leads the player by about 77 px (120 look-ahead minus about 43 px lag); about
  12 tiles are visible ahead and 6 behind.
- A full jump (feet up to 3.6 tiles) does not move the view: the player centre stays at least 60 px below the top of the
  play rect (it starts 214 px below it and rises at most 144 px).
- A floor ring (6.1 tiles) moves the view up only by what the top guard needs; after the landing on a higher ledge the
  anchor moves and the view settles at `Y_RATE`.
- Falling below the last ground: the reference follows the feet, and the bottom guard grows to 160 px within 0.2 s, so
  at least 3.6 tiles below the feet are visible while falling at any speed (19.12 CAM7), unless the level ends there.

`snap(f)`: `anchor_y = f.player.y + 16`, `look_dir = f.facing`, `look_x = look_dir * LOOK_X`, `turn_t = 0`,
`guard_b = GUARD_BOTTOM`, `aim_hold = false`, `aim_want` computed as in 19.7 (so a frozen `--aim` shot is framed),
`aim_off = aim_want`, `c` = the base target plus `aim_off`, then steps 8 and 9. Snap does not touch the intro or the
overview.

When `MazeGame` snaps:

- at the start of every attempt (opening and restart, `_start_attempt`) and after `_debug_setup`;
- at a `respawn` event: the camera holds still during the 0.5 s of death (the player sees where it went wrong), then
  cuts to the spawn; the respawn fade-in of 10 ticks softens the cut;
- not at a resize: the next `update` applies the new sizes, guards and clamps.

## 19.7 Aiming: frame the target, do not follow the bead

Decision (ADR 0011): while aiming with the keyboard or the touch stick, the camera shifts towards the target so that
the hit point and the player are both in view; with the mouse it does not shift; the bead in flight is never followed.

- `aim_frame` is true when `world.aim_index >= 0` and the aim comes from the keyboard or the throw stick
  (`controls.aim_source()` is `KEYS` or `TOUCH`, 19.10), or from the debug argument `--aim`. Keyboard and stick aims are
  directions, so moving the camera does not change them. A mouse aim is a screen position relative to the player's
  screen position: moving the camera would move the aim and the camera would chase its own tail. A mouse user points
  inside the visible area anyway.
- `aim_want` while `aim_frame` (per axis, shown for `x`; for `y` the player interval uses `guard_b` below and
  `GUARD_TOP` above, the hit interval `AIM_MARGIN` on both sides):

  ```
  hit_lo = h.x - (Pw / 2 - AIM_MARGIN);  hit_hi = h.x + (Pw / 2 - AIM_MARGIN)
  pl_lo  = p.x - (Pw / 2 - GUARD_X);     pl_hi  = p.x + (Pw / 2 - GUARD_X)
  lo = max(hit_lo, pl_lo);  hi = min(hit_hi, pl_hi)
  want_c = clamp(base_t.x, lo, hi)                    when lo <= hi
         = (pl_hi if h.x > p.x else pl_lo)            otherwise: as far towards the hit as the player allows
  want_c = level clamp of 19.6 step 9 applied to want_c
  aim_want.x = want_c - base_t.x
  ```

  `base_t` is the base target of 19.6 step 5, `h = f.aim_hit`, `p = f.player`.
- When `aim_frame` turns false while `f.flights` is true (a throw was just made), `aim_hold = true` and `aim_want` keeps
  its last value until `f.flights` is false; then `aim_hold = false` and `aim_want = 0`. So the view stays on the target
  until the bead has become a ring (at most 0.5 s of game time), then returns at `AIM_RATE`. A cancelled aim (no
  flight) returns at once. A death sets `aim_want = 0`.
- Edge marker: when the hit point is outside the play rect (a throw of up to 20 tiles does not always fit, and a mouse
  aim never frames), the world view draws, where the dotted line leaves `play_rect().grow(-24)`, a chevron of two 3 px
  lines, 10 px long, opening 7 px to each side, pointing along the line, in the line colour of 4.5 (valid `TEXT` at
  0.7 alpha, invalid `DIM`). The dots continue to the hit as before (off screen).
- Slow motion is unchanged (4.4). The world dimming (`modulate`) is unchanged.

Rejected alternatives (ADR 0011): following the bead in flight (the view would swing away for up to 0.5 s and back while
the player, often in the air, needs to see Lilith; disorienting); zooming out while aiming (the world would pump in and
out with every aim, and the slow motion already changes the feel; a size change makes the line harder to judge);
keeping the camera still for all aims (keyboard and touch users could not see far targets).

## 19.8 Overview

The player can hold a key or a button to see the whole level, with the game held still. Together with the intro of
19.9 this replaces "the whole level is always in view".

- Input: new action `overview`, keys `Tab` and `M` (physical), held; on touch a **map button** on the touch overlay,
  held (19.10). Releasing returns to the follow view.
- Allowed when the game is not paused, not finished, not frozen by a debug argument and no overlay is open. When it
  starts, `MazeGame` calls `controls.cancel_aim()`.
- While the overview is on, the game is held: no ticks (the clock stops, as in a pause), `controls.clear_latches()`
  every frame (the existing "not active" path), the rate is 0, no world dimming. After release the rate ramps back from 0
  with `next_rate`, as after a resume. Held keys keep their state (holding `D` through the overview walks on at once).
- View: `fit_zoom = minf(target_zoom, minf((canvas.x - 2 * OVERVIEW_PAD) / level_px.x,
  (canvas.y - band - 2 * OVERVIEW_PAD) / level_px.y))`, centred on the level centre in the play rect. Blended in and out
  over `OVERVIEW_BLEND_S` (19.9). Examples at 1280 x 720: l001 (48 x 14) 0.646; l006 (32 x 24) 0.594; on the phone
  canvas 1600 x 720: l001 0.813.
- When the level already fits at the target zoom, the overview equals the follow view (nothing moves; the game is still
  held while the key is down).
- Player marker: while `overview_k() > 0` the world view draws a circle outline around `player_centre()` of radius
  `22 / view_zoom` and width `2 / view_zoom` (22 and 2 canvas units), colour `TEXT` at alpha `0.6 * overview_k()`, so
  Lilith (19 canvas units high at zoom 0.6) is easy to find.

Rejected alternatives: a minimap in a corner (covers play area, small on a phone, a second rendering of the level);
toggle instead of hold (a forgotten toggle leaves the game held; hold is a peek and cannot get stuck); keeping the
game running during the overview (dangerous at a small scale and invites peeking mid-jump, while the pause already
allows stopping).

## 19.9 Intro pan and presentation

Intro: when a level is opened (not on a restart, not after a respawn), the camera shows the door, holds, and pans to
the player, so the player sees the goal and the way. It never blocks play.

- `MazeGame` calls `rig.start_intro()` once in `_ready`, after `_debug_setup` and the first snap, only when none of
  `--shot`, `--keys`, `--solve`, `--aim`, `--pause`, `--camera` is given and the door cell is not inside the snapped
  follow play rect (when it is, there is nothing to show).
- Door view: zoom `z`, play rect centred on `door`, clamped to the level (19.6 step 9).
- Timeline (real time, not advanced while `MazeGame.paused`): hold the door view for `INTRO_HOLD_S`; then pan for
  `pan_s = clampf(distance / INTRO_PAN_SPEED, INTRO_PAN_MIN_S, INTRO_PAN_MAX_S)` (distance between the door view centre
  and the follow centre at the start of the intro) from the door view to the **live** follow view with
  `smoothstep(0, 1, u)`; at `u = 1` the intro ends exactly on the follow view (l001 on desktop: 0.8 s + 1.6 s).
- Skip: any key press, mouse button press or touch-down (`controls.take_any_input()`, 19.10) during the intro calls
  `rig.skip_intro()`: the intro view freezes where it is and the presentation blends from it to the follow view over
  `SKIP_BLEND_S`. The input itself is handled as always (a move key walks at once; the clock starts as usual on the
  first active tick). Reading the level before moving stays free (2.6).

Presentation (the last part of `update`, every frame, also while dead):

```
follow   = (c, z)
base     = follow                                             when no intro
         = intro view                                         during hold and pan
         = lerp_view(follow, frozen intro view, 1 - smoothstep(0, 1, s / SKIP_BLEND_S))   after a skip, s = time since
ov       = move_toward(ov, 1 if overview on else 0, dt / OVERVIEW_BLEND_S)
final    = lerp_view(base, overview view, smoothstep(0, 1, ov))
lerp_view(a, b, k): zoom = exp(lerp(log(a.zoom), log(b.zoom), k)); centre = lerp(a.centre, b.centre, k)
```

- Views are pairs of (play rect centre, zoom). `view_zoom()` = `final.zoom`; `view_centre()` = `final.centre -
  Vector2(0, band / (2 * final.zoom))` (the viewport centre lies above the play rect centre by half the band);
  `play_rect()` = the rectangle of size `Vector2(canvas.x, canvas.y - band) / final.zoom` around `final.centre`.
- `debug_view == "door"`: `final` is the door view; `"overview"`: `ov = 1` at once (19.11).

## 19.10 Changes outside the rig

`MazeGame` (`ui/game.gd`):

- Remove `LOOK_AHEAD`, `LOOK_RATE`, `CAMERA_SPEED`, `_look` and the limit code of `_update_camera`. The `Camera2D` stays
  (child of the world, `make_current()`), with `position_smoothing_enabled = false`, default limits, no drag.
- `_update_camera(delta, snap)`: `rig.setup(...)`, build `f`, `rig.snap(f)` or `rig.update(delta if not paused else
  0.0, f)`, then `camera.zoom = Vector2(z, z)` with `z = rig.view_zoom()`, `camera.position = rig.view_centre()`,
  `camera.force_update_scroll()`, and `world.view_rect = rig.play_rect()`, `world.view_zoom = z`,
  `world.overview_k = rig.overview_k()`.
- Order in `advance`: latches and rate, ticks, `world.alpha`, overview state, `_update_camera`, then
  `controls.set_player_screen_pos(world.get_canvas_transform() * world.player_centre())`, then `world.aim_index` from
  the controls, then HUD and redraw. So the camera is applied in the same frame as the interpolated player, and the
  mouse aim uses this frame's player position (today `set_player_screen_pos` runs before `_update_camera` and uses the
  previous frame's transform). The aim index for framing in `_update_camera` comes from `controls.aim_index()`, which
  for keys and touch does not depend on the screen position.
- `active` becomes `not paused and not frozen and not sim.finished() and not _overview`; while `_overview` the rate is
  0 like while paused.
- A `respawn` event in `_tick` sets `_snap_next = true`; the next `_update_camera` snaps.
- Intro start and skip as in 19.9.

`MazeControls` (`ui/controls.gd`):

```gdscript
enum AimSource { NONE, KEYS, MOUSE, TOUCH }
func aim_source() -> int            # the source of the current aim; NONE when not aiming
func overview_held() -> bool        # an overview key or the map button is held
func touch_map(down: bool) -> void  # map button of the touch overlay
func take_any_input() -> bool       # latched: any key press (not echo), mouse button press or touch-down since the last call
func note_touch() -> void           # called by the touch overlay at every touch-down
```

`release_all` also releases the overview keys and the map button.

Input map (`project.godot`): action `overview` with physical keys `Tab` and `M`. Design 4.2 gets the row
`overview | Tab, M | Hold: overview of the whole level, the game is held.`

`MazeTouchOverlay` (`ui/touch_overlay.gd`): role `MAP`. Map button centre
`(W - 80 - ins.right, 110 + ins.top + 80)`, radius 34, hit radius 48, drawn like the jump button (faint circle, 50 %
when not pressed), label `ctl_map` under it in `DIM`, font 20. Role order at touch-down: jump, throw, map, move zone.
Held while the finger is down (`controls.touch_map(true/false)`). It sits below the HUD band and clear of the hint line
in touch mode (`y` 116 to 146). Every touch-down also calls `controls.note_touch()`.

`MazeWorldView` (`ui/world_view.gd`): new fields `view_rect: Rect2`, `view_zoom := 1.0`, `overview_k := 0.0`; the edge
marker (19.7) in `_draw_aim`; the player marker (19.8) after `_draw_player`. `_visible_tiles` keeps using the canvas
transform (it now includes the zoom). No other drawing changes.

`MazeHud`: unchanged in layout. The HUD scrim of 18.11 (`BG` at alpha 0.55 over the band plus a 24 px fade) is built
in this card instead of in look step 2, because the band is now a fixed frame over a moving world. Hint and touch
controls stay screen-fixed on their canvas layers (1 and 2); the camera only changes the world's canvas transform.

`MazeStrings` (`ui/strings.gd`), new and changed keys:

| Key | Dutch | English |
|---|---|---|
| `ctl_map` | `kaart` | `map` |
| `help_keys` | `A/D of pijltjes: lopen\nSpatie of W: springen (vasthouden = hoger)\nJ vasthouden: richten, W/S draaien, loslaten: werpen, K: annuleren\nTab of M vasthouden: overzicht\nZ: kraal terug  ·  R: opnieuw  ·  Esc: pauze` | `A/D or arrows: walk\nSpace or W: jump (hold = higher)\nHold J: aim, W/S turn, release: throw, K: cancel\nHold Tab or M: overview\nZ: bead back  ·  R: restart  ·  Esc: pause` |
| `help_touch` | `Linkerduim: lopen\nSpringknop: springen (vasthouden = hoger)\nWerpstick: slepen = richten, loslaten = werpen, terug naar het midden = annuleren\nKaartknop vasthouden: overzicht` | `Left thumb: walk\nJump button: jump (hold = higher)\nThrow stick: drag = aim, release = throw, back to the centre = cancel\nHold the map button: overview` |

`MazeMain.parse_args`: key `camera`, default `""`; `--camera=door|overview` (other values: `push_warning`, ignored);
passed to `MazeGame` in `options`.

## 19.11 Screenshots, tools and existing tests

- `--shot` mode: no intro; the camera is snapped after `--keys`/`--solve`/`--aim` (19.6), so shots stay reproducible.
  Every existing game shot changes: it now shows the zoomed area around Lilith instead of (almost) the whole level.
- Debug argument `--camera=door|overview` (design 10.4): shows the door view of the intro or the full overview, frozen.
- `tools/shots.txt` changes (the line `door` replaces the one of 18.14; the others are added):

```
door 1280x720 --level=l005 --camera=door
overview 1280x720 --level=l006 --camera=overview
overview-phone 960x432 --level=l001 --touch --safe=40,0,40,16 --camera=overview
aim-frame 1280x720 --level=l002 --keys=-1 --aim=<i>
aim-edge 1280x720 --level=l001 --keys=-1 --aim=0
phone-follow 960x432 --level=l003 --touch --safe=40,0,40,16 --keys=R60
```

  `aim-frame`: the developer picks an index `<i>` whose hit lies outside the follow view at the spawn of l002 but inside
  the framed view, and writes it into the file. `aim-edge`: on l001 the throw to the right hits the step at column 20,
  about 700 px away, which does not fit with the player guard, so the shot shows the edge marker.
- Existing tests: no test reads camera limits or world positions on screen. `controls_tests.gd` sets the player screen
  position by hand and is unaffected; mouse aiming uses a direction, which a uniform zoom does not change. `ui_tests.gd`
  drives `MazeGame.advance` and must stay green unchanged (the intro only starts without debug arguments; if a UI test
  opens a level without them, the intro runs but never blocks input). The A1 snapshot test of 18.12 must stay green.
- Performance: at zoom 1.8 the view covers about 2 x 1 to 3 x 2 chunks of 16 x 16 tiles instead of the whole level,
  so Godot culls more; the overview shows the whole level, which is today's case. The rig costs one extra `sim.cast`
  per frame while aiming (at most 400 ray steps). The frame budget of 18.10 is unchanged.

## 19.12 Acceptance (camera)

Pure rig tests in a new suite `tests/camera_tests.gd` (added to `SUITES`) drive `MazeSim` with run scripts or
`MazeInput` arrays and feed the rig with `dt = 1/60` and the player centre of the simulation (alpha 1), unless stated.
Canvas 1280 x 720 and band 110 unless stated. Fixture maps are row arrays in the test file and leave at least 5 rows
of room below every floor the test looks at, so the level clamp does not interfere.

- CAM1 Zoom: `target_zoom` gives 1.8 for 1280 x 720 and 1600 x 720, 2.0 for 1280 x 960; `32 * z / canvas.y` is at
  least 0.075 for 1280 x 720 and 1600 x 720 and at least 0.065 for 1280 x 960. `fit_zoom` gives the values of 19.8
  (within 0.001) and is never above `target_zoom`.
- CAM2 Level clamp: for every shipped level, over every frame of its stored solution, `play_rect()` lies inside the
  level rectangle (within 0.01 px) in each axis where the level is larger than the play rect.
- CAM3 Player in view: for every shipped level, over every frame of its stored solution at canvases 1280 x 720,
  1600 x 720 and 1280 x 960, while alive, the player centre lies inside `play_rect()` shrunk by 40 px on every side
  that is not a level edge (on a side where the play rect touches the level edge, inside the play rect).
- CAM4 Calm jumps: on a flat fixture map, a full jump from standing (jump held until landing) and five jumps in a row
  change `view_centre().y` by at most 1 px.
- CAM5 Launch: after a floor ring launch on a fixture with a high ledge, the player centre is always at least
  `GUARD_TOP - 0.5` px below the top of the play rect, and after landing on the ledge `view_centre().y` settles within
  2 px of its target within 2 s.
- CAM6 Look-ahead: walking right from rest on a flat fixture of 64 tiles, after 2 s `view_centre().x - player.x` is
  between 60 and 120; after reversing, the look direction has not changed at 0.15 s and has changed at 0.25 s; after
  2 s of walking left the view centre is left of the player.
- CAM7 Falling: walking off a 6-tile ledge, from 0.25 s after the feet are more than `FALL_MIN` below the ledge until
  the landing, the bottom of the play rect is at least 140 px below the feet.
- CAM8 Aim framing: on a fixture with a wall 12 tiles to the right of the player, with `aim_frame` true and index 0, the
  hit point is inside `play_rect()` shrunk by `AIM_MARGIN - 1` within 1 s and the player centre stays inside the play
  rect shrunk by 40 px; with `aim_frame` false (mouse) and a standing player the view does not move (less than 0.5 px
  over 1 s); after a throw the offset stays while `flights` is true and is below 2 px within 1.5 s after the bead has
  become a ring.
- CAM9 Snap: after `snap`, `view_centre()` equals the clamped base target (within 0.01 px) with no smoothing; in
  `MazeGame`, a restart and a respawn snap (the first frame after the `respawn` event shows the spawn framing).
- CAM10 Intro: on l001 at 1280 x 720, at `t = 0` and `t = INTRO_HOLD_S - 0.05` the play rect contains the door cell; at
  the end of the pan the view equals the follow view (within 0.5 px) and `intro_active()` is false; a skip at 0.5 s
  reaches the follow view within `SKIP_BLEND_S + 1/60`. In `MazeGame`, a move key pressed during the intro moves the
  player in the same frames as without intro (equal `sim.snapshot()` after 60 frames).
- CAM11 Overview: for every shipped level at 1280 x 720 and 1600 x 720, `OVERVIEW_BLEND_S + 1/60` after
  `set_overview(true)` the zoom equals `fit_zoom` and the play rect contains the whole level; after release the zoom is
  back at `target_zoom` within `OVERVIEW_BLEND_S + 1/60`. In `MazeGame`, with `Tab` held for 30 frames, `sim.tick` and
  `sim.time_ticks()` do not change and an aim in progress is cancelled; after release ticks continue.
- CAM12 Same-frame camera: in `MazeGame`, after every `advance` of a walk of 120 frames with deltas alternating
  1/60, 1/144 and 1/30, `world.get_canvas_transform()` maps `rig.play_rect().position` to `(0, band)` within 0.01
  canvas units (the camera is applied in the frame it was computed for).
- CAM13 Mouse: the position given to `controls.set_player_screen_pos` equals `world.get_canvas_transform() *
  world.player_centre()` of the same frame; a mouse press and release 100 canvas units straight right of that point
  throws index 0 at the target zoom.
- CAM14 Screen-fixed layers: HUD, touch overlay and overlays keep an identity canvas transform while the camera moves
  and zooms; the HUD scrim covers the band (110 plus the safe area top).
- CAM15 Controls: `overview_held` is true while `Tab` or `M` is held and while the map button is held (synthetic
  `InputEventScreenTouch` on its centre); a touch-down on the map button does not move or jump; `aim_source` reports
  `KEYS`, `MOUSE`, `TOUCH` for the three aim paths and `NONE` otherwise; `take_any_input` latches once per press.
- CAM16 Simulation untouched: `git diff <base> -- sim/ levels/ tests/solutions.json` is empty; all existing checks
  green; `MIN_CHECKS` raised; `tools/check_levels.gd` exits 0.
- CAM17 Screenshots of 19.11 are produced without errors and reviewed by the tester (19.13).

## 19.13 Tester checklist

Headless: CAM1 to CAM16 in the run; the diff of CAM16.

Screenshots (`tools/shots.sh`), at 100 % and on the phone sizes:

- `easy`, `hard`, `lilith-*`: Lilith clearly larger (about 8 % of the height); headband tails and bandolier slots
  visible; the player below the HUD band, never under it.
- `door`, `overview`, `overview-phone`: door view shows the doorway; the overview shows the whole level inside the area
  below the band with the player marker; the touch controls and the map button readable over it.
- `aim-frame`: target face and Lilith both in view; `aim-edge`: chevron at the edge in the line colour.
- `phone-follow`, `phone-small` (l007, added in look step 2): on 960 x 432, Lilith about 35 px high; nothing important
  under the stick discs.
- `pause`: the controls legend with the extra overview line still fits.

Play in a desktop browser (web export) and on a phone in landscape if possible:

- Walking: the view leads in the walking direction; a short tap the other way does not swing the view; no jitter while
  walking at 60 Hz and, if available, on a 120 or 144 Hz screen; no jitter during slow motion.
- Jumping on flat ground does not bob the view; a floor ring follows smoothly up; falling into a pit or off a ledge
  shows the ground below in time.
- Aiming with `J` and with the throw stick at a far wall: the view moves towards the target and returns after the bead
  has become a ring; aiming with the mouse does not move the view; the edge chevron appears when the target is out of
  view.
- Death: the view holds while Lilith fades, then cuts to the start; `R` cuts to the start at once.
- Intro: opening a level shows the door, then pans to Lilith; any key, click or touch skips it smoothly and the input
  works immediately; restarting does not replay it.
- Overview: holding `Tab`, `M` or the map button shows the whole level; the clock stops; releasing continues; holding
  `D` through it walks on at once.
- HUD band, hint and touch controls stay fixed; the HUD text is readable over the moving world (scrim).
- Frame rate with `--fps` (when look step 2 is in) or the browser's tools: within the budget of 18.10.

## 19.14 Developer steps and order with look step 2

Branch `feature/follow-camera`, one card, merged after the tests are green and the tester has reviewed it.

1. `ui/camera_rig.gd` (`MazeCameraRig`) with `tests/camera_tests.gd` (CAM1 to CAM11 rig parts).
2. `MazeGame` integration (19.10), `Camera2D` settings, frame order, respawn snap, intro, overview hold; the HUD scrim;
   `MazeControls` additions and the input action; the map button on the touch overlay; texts; `--camera`.
3. World view: `view_rect`, `view_zoom`, `overview_k`, edge marker, player marker.
4. Integration tests CAM9 to CAM15 in `camera_tests.gd`, `controls_tests.gd` and `ui_tests.gd`; raise `MIN_CHECKS`.
5. `tools/shots.txt` (19.11), shots produced and looked at; record deviations as built in section 19.15 of this file;
   add `MazeCameraRig` to the class list in `docs/conventions.md`; design 4.2, 10.4 and 10.5 point to this section.

Order with look step 2 (#016): **build the camera first**, then step 2 on top of it, sequentially (not in parallel).
Reasons: step 2's review (lip widths, joints, ring glow, readability on the phone, the 50 % copy) depends on the size
on screen, which the zoom changes from 4.4 % to 8 % of the height; reviewing at zoom 1 first would be done twice. Both
change `ui/game.gd`, `ui/world_view.gd` and `tools/shots.txt`, so parallel branches would conflict. The camera is
small and independent of the art. If #016 is already in progress, finish it first and build the camera on top; the
step 2 review is then repeated briefly on the camera shots.

## 19.15 Deviations as built

Built as designed except for the points below. None touches `sim/`, `levels/` or `tests/solutions.json`.

- **`aim-frame` shot.** `--level=l001 --keys=R40 --aim=0` instead of l002 at the spawn. At the l002 spawn the player is
  100 px from the left level edge, the level clamp (19.6 step 9) wins over the player guard, and no index exists whose
  hit is outside the follow view but inside the framed view. On l001 after 40 ticks of running the throw to the right
  hits the step at column 20 (800 px): outside the follow view, inside the framed one. Framing only reaches hits within
  about 530 px of the player horizontally (295 hit margin + 235 player guard).
- **Aim grace.** `AIM_GRACE_S = 0.15` (real time): when the aim ends, the offset is kept for at least this long before
  it is released without a flight. A throw reaches the sim up to a few frames after the key release (slow motion: one
  tick per 4 frames), so without it the view started to return one frame before `flights` became true. A cancelled
  aim therefore returns after 0.15 s instead of at once (CAM8 only requires that it returns).
- **`look_dir()`** is a public getter of the rig, used by CAM6.
- **CAM6 reversal** is tested with a synthetic velocity (-300 px/s) so the 0.15 s and 0.25 s marks do not depend on the
  deceleration of the player; the tap and the 3 s walk to the left use the simulation.
- **CAM7** uses a 12-tile drop, not 6: with a 6-tile ledge the landing comes 0.37 s after the start of the fall, before
  the 0.25 s window after `FALL_MIN` opens (0.15 s + 0.25 s), so the check would be empty. The window has 5 or more frames.
- **CAM2/CAM3** run for every canvas (1280 x 720, 1600 x 720, 1280 x 960); CAM2 is not limited to two of them.
- **Test viewport.** The headless test runner has a viewport of 1280 x 1280, so game tests compute the expected zoom with
  `MazeCameraRig.target_zoom(visible rect)` instead of assuming 1.8 (CAM12).
- **Intro start.** `MazeGame._ready` calls `_update_camera(0.0, false)` after `rig.start_intro()` so the first drawn
  frame already shows the door.
- **HUD scrim** is drawn by `MazeHud._draw` itself (before its children) instead of a separate first child; `MazeHud`
  has a getter `scrim_band()` for CAM14.
- **Player marker** is only drawn while the player is alive; the edge marker is skipped when the player is not inside
  the play rect shrunk by 24 px (no exit point), and when no camera has set `view_rect`.
- **Dead camera.** While the player is dead the follow state is frozen including the level clamp, so a window resize in
  those 0.5 s is applied at the respawn snap.
- **Left-edge spawns and touch.** Every level spawns near the left edge, so Lilith stands under the move stick disc at the
  start on a phone (`phone-follow`, `phone-wide`). The level clamp and guards keep the camera inside the level, so the
  camera cannot shift her; this is a layout point for the touch controls (look step 2 or the tester), not a camera one.
- **Test counts.** `MIN_CHECKS` is 950 (was 777): the new suite `tests/camera_tests.gd`, the CAM15 checks in
  `controls_tests.gd` and one `--camera` check in `ui_tests.gd`. No existing test was changed.
