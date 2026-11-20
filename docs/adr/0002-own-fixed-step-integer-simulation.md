# 0002 Own fixed-step integer simulation instead of Godot physics

Status: accepted (2026-11-20)

## Context

The player walks, jumps, bounces off rings and dies on spikes in a world of axis-aligned square tiles. The movement
needs custom rules anyway: coyote time, jump buffer, variable jump height, apex hang, corner correction, ring launches
that set velocity, an input lock after a wall launch. Aiming runs in slow motion. The owner wants the rules testable
headless, and times kept as statistics that may later be compared online, which needs runs that can be replayed and
checked.

## Decision

- The game world is simulated by `MazeSim` in `sim/`: a fixed step of 1/60 s, integer positions and velocities in
  units of 1/1000 px, axis-separated AABB collision against the tile grid (X first, then Y).
- The simulation is a pure function of the level and the per-tick input sequence. It uses no nodes, physics server,
  time source, randomness or floating-point arithmetic in its step and cast functions. Aim directions come from a
  literal table of 144 integer vectors.
- Tuning values are written as readable px/s values next to the integer the simulation uses; a test keeps the two in
  agreement.
- Rendering interpolates between the previous and the current position, so the fixed step looks smooth at any frame
  rate and in slow motion.

## Alternatives considered

- **`CharacterBody2D` with `move_and_slide` on a `TileMapLayer`**: the usual Godot route and less collision code, but
  floating-point physics tied to the physics frame, harder to test without a running scene tree, not reproducible
  from an input record, and the custom rules (launches, coyote, buffer, corner correction) still have to be written
  around it. Slow motion through `Engine.time_scale` would change the physics step or its count in ways that are hard
  to reason about. Rejected.
- **Floating-point fixed step**: deterministic on one machine and probably across machines (IEEE add and multiply),
  but contact tests on exact float edges are fragile (standing exactly on a floor, touching a ring zone). Integers make
  every edge exact. Rejected.
- **A 2D physics engine with rigid bodies**: wrong model for a platformer character. Rejected.

## Consequences

- About 300 lines of own movement and collision code, fully covered by headless tests (design 3.12).
- Slopes, rotating platforms and physics props are not available; the levels do not need them (assumption A2).
  Moving obstacles can be added later as entities stepped in the same tick.
- Every run can be replayed from its run script (ADR 0003), which makes solution tests, deterministic screenshots and a
  later server check of best times possible.
