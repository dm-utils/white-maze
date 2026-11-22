# 0011 Zoomed follow camera in the view, with overview and intro pan

Status: accepted (2026-11-22). Design: `docs/design-camera.md` (section 19). Replaces the camera of design 8.3 and
16.1; changes assumption L2 of section 18.2.

## Context

At zoom 1 the camera shows 18 tiles of height, so every level fits or nearly fits and Lilith is 4.4 % of the screen
height: 32 px on a desktop window, about 19 physical px on a 960 x 432 phone. The details of section 18 (headband,
bandolier, lips) are lost. The owner decided on 2026-11-22: zoom in further; the whole path does not have to be in
view at once, the view may scroll as the player progresses.

Constraints: only the view changes (simulation, levels, solutions, determinism untouched); keyboard, mouse and touch
keep working; HUD, hint and touch controls stay screen-fixed; screenshots stay reproducible; the web export stays
within the frame budget of 18.10.

Questions to decide: how far to zoom and how the zoom scales with the screen; how the camera follows; how the player
still learns the level when it no longer fits; what the camera does while aiming; and how it is built.

## Options

Zoom:

1. **Fixed target zoom from the canvas height**: 10 tiles of visible height (Lilith 8 %), with at least 16 tiles of
   width on narrow screens.
2. **Fit the level** with a minimum size for Lilith (zoom out as far as possible while Lilith stays above N px).
3. **A zoom per level** (a level field).
4. **Dynamic zoom** (zoom out with speed, while aiming or near large drops).

Following:

1. **Own pure camera rig** (`MazeCameraRig`, RefCounted): look-ahead from the velocity with a turn delay, a ground
   anchor for calm vertical motion, hard guards that keep the player in the play rect, own level clamp, exponential
   smoothing in real time; the `Camera2D` only receives position and zoom.
2. **Godot `Camera2D` features**: drag margins, position smoothing, limits, zoom.

Learning the level:

1. **Overview on hold** (keys `Tab`/`M`, a map button on touch): zoom out to fit the level, game held.
2. **Intro pan** at level opening: door, hold, pan to the player; skipped by any input.
3. **Minimap** in a corner.
4. **Nothing**: the player explores.

Aiming:

1. **Frame the target** for keyboard and touch aims; mouse aims do not move the camera; an edge marker when the target
   is out of view.
2. **Follow the bead** in flight.
3. **Zoom out** while aiming.
4. **Camera still** while aiming.

## Decision

- **Zoom option 1.** `z = min(canvas.y / 400, canvas.x / 640)`: 1.8 on every landscape screen of 16:9 or wider
  (desktop and phones), 2.0 on 4:3 tablets. Lilith is 8 % of the height (6.7 % on 4:3). The zoom never goes above this
  for small levels; a level smaller than the play rect is centred. The value is one constant (`VIEW_H_TILES`) and can
  be tuned after the playtest.
- **Following option 1.** The rig is pure and tested headless with explicit time steps; Godot's smoothing, drag
  margins and limits are switched off. The camera is applied in the same frame as the interpolated player position
  (`force_update_scroll` right after the ticks and the interpolation), so camera and player can never be a frame apart,
  which is what makes a follow camera jitter over a fixed-step simulation. No pixel snapping: everything is drawn as
  vector shapes with antialiasing, so sub-pixel camera motion is smooth, and snapping a zoomed camera would make the
  whole world step.
- **Learning the level: options 1 and 2.** The overview is the tool to study the path at any time; the intro shows the
  goal once per opening without costing anything (the clock starts at the first input anyway, and any input skips it).
  During the overview the game is held (no ticks), like a pause without the overlay.
- **Aiming option 1.** Keyboard and stick aims are directions, so moving the camera cannot change them; a mouse aim is
  a screen position relative to the player, so a moving camera would move the aim. The framing stays until the thrown
  bead has become a ring, then returns.
- **Respawn and restart cut** (snap) to the start; during the 0.5 s of death the camera holds still.
- **Order:** the camera is built before look step 2 (#016), because step 2 is reviewed at the size on screen.

## Alternatives rejected

- **Fit the level with a minimum Lilith size (zoom option 2)**: keeps more of the level in view, but the zoom would
  differ per level and per screen, every level of 48 x 14 tiles would still give a small Lilith on a phone, and the
  owner asked to zoom in, not to fit. Rejected.
- **Zoom per level (option 3)**: a format change for a view concern, and the owner ruled out format changes in section
  18. Rejected.
- **Dynamic zoom (option 4)**: shows more when it matters, but the world pumps in and out, the aim line's length on
  screen changes while judging it, and it conflicts with the calm White style. Rejected.
- **Godot `Camera2D` features (following option 2)**: less code, but drag margins are symmetric and cannot express a
  ground anchor, a velocity look-ahead with a turn delay or aim framing; the built-in smoothing runs in the camera's own
  process step, so the result depends on node processing order and is hard to reproduce in headless tests. Rejected;
  the `Camera2D` stays only as the sink for position and zoom.
- **Pixel snapping** of the camera (`snap_2d_transforms_to_pixel` or rounding the position): crisp for pixel art, but
  the art is vector-drawn, and rounding a camera at zoom 1.8 makes the world move in visible steps while the player is
  interpolated smoothly. Rejected.
- **Minimap (learning option 3)**: always visible, but it covers play area, is tiny on a phone and is a second
  rendering of the level. Rejected.
- **Nothing (learning option 4)**: simplest, but the owner asked that the player can learn the finish and the path; a
  door the player has never seen makes the first run blind. Rejected.
- **Overview as a toggle** or **with the game running**: a toggle can be forgotten and leaves the game held; a running
  game at overview scale is dangerous and invites peeking mid-jump. Hold with the game held is safe and cannot get
  stuck.
- **Following the bead (aiming option 2)**: the bead flies up to 0.5 s; the view would swing away from Lilith while she
  is often in the air and swing back. Rejected.
- **Zoom out while aiming (option 3)**: the world pumps with every aim and the line's scale changes while judging it.
  Rejected.
- **Camera still while aiming (option 4)**: simplest and fine for the mouse, but keyboard and touch users could not see
  targets beyond the view. Rejected for those sources; kept for the mouse.
- **A smooth pan back to the start after a death**: shows the way back, but it starts while the player still looks at
  the place of death and makes the 0.5 s death pause busy. Rejected for a cut hidden by the respawn fade-in.

## Consequences

- New pure class `MazeCameraRig` (`ui/camera_rig.gd`) and a new suite `tests/camera_tests.gd`; changes in `MazeGame`,
  `MazeControls`, `MazeTouchOverlay` (map button), `MazeWorldView` (edge marker, player marker), `MazeStrings`
  (`ctl_map`, help texts), `MazeMain.parse_args` (`--camera`), the input map (`overview`: `Tab`, `M`) and
  `tools/shots.txt`.
- The HUD scrim of 18.11 is built with the camera, because the band becomes a fixed frame over a moving world.
- Every existing game screenshot changes (zoomed view around Lilith); the `door` scenario needs `--camera=door`.
- Sizes of sections 8.1 and 18 stay in world px and appear 1.8 times larger; assumption L2 of 18.2 no longer holds,
  and look step 2 is reviewed at the new zoom.
- The overview stops the clock like the pause does; no new way to gain time is added.
- The constants are start values; the owner's playtest may change the target zoom (for example 9 tiles, Lilith 8.9 %)
  and the follow rates without changing the structure.
