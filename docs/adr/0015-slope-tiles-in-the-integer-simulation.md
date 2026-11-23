# 0015 Slope tiles in the integer simulation; level format 2

Status: accepted (2026-11-23). Design: `docs/design-roofs.md` (section 23.4 to 23.10). Amends ADR 0002 (slopes were
not available) and replaces assumption A2 of design 1.3.

## Context

The owner chose the large variant of the rooftop worlds: real sloped tiles. Steep roofs (45 degrees) make you slide,
gentle roofs (1 in 2) are walked like a floor, and a sloped face is never a ring face. The simulation is an own
fixed-step integer simulation with axis-aligned box collision against square tiles (ADR 0002); runs are replayed from
run scripts, nine levels have stored solutions and par evidence, and profiles store best runs. Known failure modes of
slopes in tile platformers: jitter on the slope, getting stuck where a slope meets a wall or a floor, hops at joints,
landing "dead" on a steep slope.

Questions: how the player collides with a slope; what sliding is and how much control it leaves; what happens at
landing and at the ends of a slope; how slopes are written in the level files; what the cast does with them; how the
nine shipped levels are kept bit for bit identical.

## Options

Collision model:

1. **Centre foot on slopes, box on full tiles.** The bottom centre of the player follows the slope surface; full tiles
   keep colliding with the whole box; a slope's vertical high side blocks like a wall from outside; while on a slope the
   bottom 16 px of the box may overlap a full block (the floor at the top of a slope, a ridge).
2. **Full polygon collision** (box against triangles, separating axes, sliding along the normal).
3. **Stairs only** (the small variant: slopes drawn in the background, the play field stays square).
4. **Godot physics** (`CharacterBody2D` with `floor_snap`).

Sliding:

1. **Speed steering**: on a steep slope the horizontal speed goes to 360 px/s, 480 with input downhill, 240 with input
   uphill; you never stop and never climb.
2. **No control**: one fixed slide speed.
3. **Brake to a stop** with input uphill.

Landing on a steep slope:

1. **Project the fall onto the slope**: `vx = (vx + downhill * vy) / 2`.
2. **Land dead** (`vy = 0`, `vx` unchanged) and let the slide accelerate.

Notation:

1. **`/ \` for steep, `rR` and `Ll` pairs for gentle**, level `format` 2.
2. **Letters only** (for example `a b c d e f`), no escaping in JSON.
3. **Keep format 1** and only add characters.

Cast:

1. **A slope stops the bead and the throw is invalid** (reason `slope`).
2. **A slope is transparent** for beads.
3. **A ring on a slope with a fifth, diagonal launch.**

## Decision

- **Collision option 1.** It keeps everything that exists (box against full tiles, X then Y, corner correction) and adds
  one point test against a surface per column, a lift after the X move, a snap within 16 px plus the horizontal speed
  when walking or sliding downhill, and a landing on the surface under the centre. Validation removes the hard cases:
  a slope always has a full block below and air above, gentle halves come in pairs, and the low side is open (no
  valleys, no pockets). Every new path needs a slope, so maps without slopes give the same trace (a golden-trace test
  pins this before the first change).
- **Sliding option 1.** Control over the speed keeps the calm character of the game (you choose when you reach the eave)
  without allowing standing or climbing, which would turn a steep roof into a floor. Three tuning values.
- **Landing option 1.** Falling onto a roof turns into a slide at once, which reads as physical; it happens only on a
  real landing (not on the per-tick contact while sliding).
- **Notation option 1** with format 2. `/` and `\` are the most readable; the backslash costs one escape in JSON, which
  the level check handles; lower and upper case tell the halves of a gentle pair apart. Format 2 also carries `sky`
  (a bead may fly out of the top). Format 1 files stay valid and the shipped levels stay format 1.
- **Cast option 1.** It is the owner's rule ("never a ring face") and needs no new launch. Faces covered by a slope are
  never ring faces either. A bead never lands on a roof; an invalid throw costs nothing, as before.

## Alternatives rejected

- **Full polygon collision**: general, but floats or rational arithmetic in the step, a new contact model for corners
  and a rewrite of the tested movement code; the "never larger than what collides" drawing rule would need polygon
  offsets everywhere. Far more risk than the feature needs. Rejected.
- **Stairs only**: no new physics, but the owner chose sliding as the new feel. Rejected by the owner.
- **Godot physics**: rejected for the reasons of ADR 0002 (floats, not replayable, not testable headless).
- **No slide control**: simplest, but losing all control on a roof is exactly the risk the designer named. Rejected.
- **Brake to a stop**: makes a steep roof a floor you can stand on and removes the mechanic. Rejected.
- **Land dead**: simpler, but a fall onto a steep roof would stop and then start sliding, a visible jolt. Rejected.
- **Letters only**: no escaping, but a grid of letters does not show the roof shape; the rows are the level designer's
  main tool. Rejected.
- **Keep format 1**: an older build would fail on the new characters with a less clear error, and `sky` changes how a
  throw behaves, which deserves a version. Rejected.
- **Transparent slopes for beads**: a bead flying through a roof reads as a bug. Rejected.
- **A fifth, diagonal launch**: rejected by the owner (sloped faces are never ring faces); it would also change par
  reasoning for every level.

## Consequences

- `MazeLevel` gets six cell kinds, `format`, `sky`, `covered()` and four validation rules; `MazeSlope` (`sim/slope.gd`)
  holds the geometry with integers only; `MazeSim` gets `ground`, sliding, the new move order and the slope-aware cast.
- `solid()` keeps meaning "full block"; every caller that asks "is this face exposed" uses `covered()`.
- The box may overlap a full block by at most 16 px at its bottom while standing on a slope; the "no overlap" invariant
  of S7 holds on maps without slopes and is replaced by the invariants of 23.5.8 on slope maps.
- Tools and the search must know slopes (ADR 0017); the view draws slopes inside their polygon and gives Lilith a slide
  pose; the camera treats a slide like a fall for its bottom guard.
- The nine shipped levels, their solutions and every stored best run stay valid.
