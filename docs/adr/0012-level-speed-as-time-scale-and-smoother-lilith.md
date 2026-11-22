# 0012 Level speed as a time scale; smoother Lilith; 9-tile camera

Status: accepted (2026-11-22). Design: `docs/design-feel.md` (section 20). Extends ADR 0003 (game rate), ADR 0010
(Lilith) and ADR 0011 (target zoom).

## Context

After playing the live version the owner asked for three changes: Lilith a bit smoother and with orange hair; the
camera from 10 to 9 tiles of visible height because Lilith looks small; and a game that is a bit slower, especially at
the start for beginners, getting a little faster further into the series without overdoing it. Hard requirement: every
level stays solvable within par. The simulation is a fixed-step integer simulation (ADR 0002) with stored solutions,
run scripts in the profile and a par per level (ADR 0009).

## Options

Speed:

1. **Time scale per level**: fewer simulation ticks per real second, by series position; the tick itself and all
   tuning stay. Same mechanism as the slow motion of ADR 0003.
2. **Tuning per level**: lower run speed, jump speed, gravity and launch speeds for early levels.
3. **Lower walking speed only**, global or per level.
4. **`Engine.time_scale`**.

Smoothness:

1. **Render time plus pose blending**: animation on a float clock that matches the interpolated position, crossfades
   between poses over 6 ticks, a slower run cycle, a smoothed look velocity for the tails.
2. **More hand-made poses** (in-between keyframes for each transition).
3. **Smooth every joint per tick** (exponential follow of all joints).

Camera: keep the structure of ADR 0011, change `VIEW_H_TILES` to 9 and retune the vertical framing, or change only
`VIEW_H_TILES`.

## Decision

- **Speed option 1.** `MazeGame.SPEED_PCT = [80, 82, 84, 86, 88, 90, 92, 94, 96]` by series position, later levels at
  96. The effective game rate is `aim rate * level speed`. The clock stays game time in ticks. A debug argument
  `--speed` and a web query key `speed` let the owner try values.
- **Smoothness option 1.** Render time `t = tick - 1 + alpha` for every animation value; a pure `MazePoseBlend` that
  blends a joint rig from the last drawn rig to the new pose over `BLEND_TICKS = 6`; `STRIDE_PX` 28 to 48; tails and
  launch tilt from a per-tick smoothed velocity; `alpha` kept while paused. Disabled while frozen, so shots stay exact.
- **Hair** `#C4701A`, with contrast and hue tests against the back walls of the three worlds, the spike red, the
  headband and the skin.
- **Camera**: `VIEW_H_TILES` 9 (zoom 2.0 on all landscape screens), with `FEET_Y` 0.70, `GUARD_TOP` 40, `GUARD_BOTTOM`
  96 and `AIM_MARGIN` 40.

## Alternatives rejected

- **Tuning per level (speed option 2)**: changes jump heights, gap widths and ring metrics per level, so the level rules
  of 3.3, the stored solutions and the par searches stop holding, and the simulation needs a level input. It would
  break exactly the requirement that every level stays solvable within par. Rejected.
- **Lower walking speed only (option 3)**: the running gap of 4 tiles depends on the run speed; levels with long jumps
  could become unsolvable and every stored solution changes. Rejected.
- **`Engine.time_scale` (option 4)**: also slows the camera, tweens, UI and input repeat, and does not help the integer
  simulation (ADR 0003). Rejected.
- **A clock in wall-clock seconds** for slower levels: a time would then depend on the speed table, so retuning the
  curve would change old best times, and the server could not verify a time from the run alone. Rejected; the clock
  runs at the level speed, as it already runs at a quarter while aiming.
- **More hand-made poses (smoothness option 2)**: more data to draw and to test for bounds, and still a hard cut at each
  transition unless the in-betweens are timed; blending gets smooth transitions for every pair of poses at once.
  Rejected for now; extra poses can be added on top of the blend.
- **Smoothing every joint per tick (option 3)**: also damps the run cycle and the throw swing (the legs would no longer
  reach their stride), and it depends on the tick rate. Rejected.
- **Only `VIEW_H_TILES` to 9**: at zoom 2.0 the old `FEET_Y` and `GUARD_TOP` leave 47 px above a jumping Lilith, less
  than the guard of 60, so every full jump would move the view; aim framing would reach 460 px instead of 530. Rejected.

## Consequences

- `sim/`, `levels/`, `tests/solutions.json`, the tuning and the profile format are unchanged; determinism and every
  stored run stay valid; par holds by construction and is checked by the level check.
- On early levels the clock runs slower than a wall clock (l001: 80 %). Best times stay comparable across any later
  change of the speed table.
- Tests that assume 60 ticks per real second of `MazeGame.advance` set the option `speed` to 100.
- New pure class `MazePoseBlend`; `MazeLilith` gets `rig` and `blend_rig`; `MazeWorldView` gets `after_tick`,
  `blend` and `last_rig`.
- Every game screenshot changes (zoom 2.0, hair colour, stride); the `aim-frame` scenario needs a new key/aim pair.
- Baked chunks are sampled at 1.0 texel per canvas unit instead of 1.1; slightly softer on large screens.
