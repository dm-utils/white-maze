# 0010 Procedural adventure art, drawn outside the simulation

Status: accepted (2026-11-22). Replaces the look of design 8.1 for the game world; HUD, menus and the White Kit theme
are unchanged. Design: `docs/design-look.md` (section 18).

## Context

The owner wants the game to look better: a coloured adventure world instead of grey blocks, and an explorer instead
of a white square. On 2026-11-22 he chose the designer's direction A ("Lost temple"): three worlds of three levels
each (temple, jungle ruin, cave), fixed reading rules (lip on ring faces, glossy `X` without lip, one hazard red,
doorway as finish, white reserved for beads and rings, quiet decor derived from neighbouring cells), and a coloured
character named Lilith with a red headband and a bandolier that shows the beads left. Constraints: no change to the
level format or the simulation, determinism and all existing tests stay, the web export must stay fast on phones, and
no third-party art with an unclear licence.

Four questions needed a decision: how the art is made, how it is kept apart from the simulation, where the world of a
level comes from, and how it stays fast.

## Options

How the art is made:

1. **Procedural drawing in GDScript** (`CanvasItem` draw calls: polygons, lines, circles, vertex colours), with all
   colours as constants and all variation from a deterministic hash of the cell coordinates.
2. **Own SVG or PNG sprites and tiles** drawn in an editor, imported as textures; a `TileMapLayer` with an atlas for the
   level.
3. **Third-party asset packs** (free or paid).
4. **Shaders** for materials and glow.

Where the world comes from:

1. **Derived from the series position**: world = `(number - 1) / 3`, clamped.
2. **A level field** (`"world": "jungle"`), optional, defaulting to the derived value.
3. **A separate mapping file** (`levels/worlds.json`, id to world).

## Decision

- **Art is procedural (option 1).** Every shape is drawn in code; there are no image, font or shader assets. The
  figure is described as data (`MazeLilith.shapes` returns shapes in local coordinates), so its bounds, poses and
  colours are tested headless without rendering. Tile variation comes from `MazeArt.hash3(x, y, salt)`, an
  integer-only hash, so every level looks the same every time and on every machine, and level makers do nothing.
- **Rendering stays outside the simulation.** Only `ui/` changes. The view reads `MazeSim` fields and events and the
  interpolation `alpha`; animation timing comes from `sim.tick` and stored event ticks; nothing flows back. `sim/`,
  `levels/` and `tests/solutions.json` are not touched in any step (acceptance A1), and a test compares the snapshot of
  a run through the new game screen with a pure simulation run.
- **The world is derived from the series position (option 1).** `MazeWorlds.for_number(number)`; levels beyond the
  last group stay in the last world. A debug argument `--world` overrides it for screenshots.
- **Static layers are cached.** Back wall, decor and tiles are drawn once per level into 16 x 16 tile chunks
  (`MazeStaticLayer`); only rings, beads, Lilith and the aim preview are redrawn per frame. Glow is a few translucent
  shapes; no shaders, textures, particles or post-processing.
- **Readability is carried by shape and luminance**, checked by palette tests with WCAG contrast (lip lighter than its
  block, `X` distinct from the back wall, hazard bright against the back wall, nothing near white except rings and
  beads, nothing near the hazard hue). Three small backings (HUD scrim, hint backing, touch control discs) keep the
  unchanged HUD readable over light materials.

## Alternatives rejected

- **Own sprites and a `TileMapLayer` (option 2)**: richer detail per hour of drawing for a skilled pixel artist, and
  the editor shows the result directly. Rejected: the project has no artist workflow, every world would need a
  hand-drawn atlas plus autotile rules that duplicate the neighbour logic (lips depend on spikes and solids, which
  autotiling expresses poorly), bounds and colour rules could not be tested headless, and three worlds times every
  pose of Lilith is a large drawing job before anyone has seen it on a phone. Sprites remain possible later for
  single items without changing this structure.
- **Third-party asset packs (option 3)**: fast, but the licence and origin must be tracked for a public showcase and a
  possible store release, the style would not match the White series, and a recognisable pack makes the game look
  generic. Rejected by the owner's constraint.
- **Shaders (option 4)**: cheap glow and material effects on desktop, but GL Compatibility on WebGL 2 differs per
  phone, shader compilation stutters on first use in browsers, and shaders are hard to test headless. Rejected; the few
  glows are translucent shapes.
- **A level field for the world**: lets a designer put one level in another world. Rejected: the owner ruled out a
  format change, groups of three are a series property (levels 1-3 teach the basics, 4-6 reuse and bouncing, 7-9
  catching and momentum), and a field could contradict its group after a reorder. If a single exception is ever
  needed, an optional field is an addition that keeps format 1.
- **A separate mapping file**: no format change, but a second place to keep in step with the index for no gain over
  the derived rule. Rejected.
- **Redrawing everything every frame** (the phase 1 world view): simplest, but the decor of three worlds multiplies
  the commands per frame on phones. Rejected in favour of cached chunks.
- **Baking static layers into textures now** (`SubViewport` with `UPDATE_ONCE`): fewest commands per frame, but more
  code, texture memory per chunk and blurry edges when scaled. Kept as the fallback if the phone test misses the
  budget of 50 fps.
- **Stateful animation** (springs for the headband tails, an animation player): smoother motion, but screenshots and
  tests would depend on frame history. Rejected; every pose is a pure function of the simulation state, the tick and
  stored event ticks.

## Consequences

- New pure classes in `ui/`: `MazeArt`, `MazeWorlds`, `MazeDecor`, `MazeLilith`, plus the node `MazeStaticLayer`.
  The conventions get their names, and palettes live in `MazeWorlds` (an exception to "look values at the top of the
  file that draws them", because three drawing files share them).
- Design 8.1 is replaced for the world: grid lines are gone, edges become lips only on ring faces (no longer in front
  of spikes), `X` loses the hatching, the finish post becomes a door, the white square becomes Lilith.
- The look is checked in three ways: headless tests (bounds, poses, palettes, lip rule, decor rules, cached layers),
  screenshot scenarios per world and per pose reviewed by the tester, and a frame-rate check on the web export.
- The work is split into three steps (Lilith and door; worlds and tiles; details and back decor), so a loss of
  readability can be traced to one step.
- The White series rules stay: dark ground, white belongs to the player, calm (no particles, no screen shake, decor at
  low contrast).
