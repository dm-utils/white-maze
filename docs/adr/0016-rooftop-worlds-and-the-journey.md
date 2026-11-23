# 0016 Rooftop worlds as skin packs, and one journey from the ruins over the roofs

Status: accepted (2026-11-23). Design: `docs/design-roofs.md` (sections 23.11 to 23.14). Extends ADR 0013 (skins as
data with engine-owned reading rules) and ADR 0010 (procedural art); changes the speed table of ADR 0012.

## Context

The owner wants the game to feel less generic: four rooftop cities (Amsterdam, Andalusia, Fes, London), each with its
own roof type, materials and time of day, after the three ruin worlds, in one journey of 21 levels. The existing worlds
stay. Reading rules must hold in every city: the lip only on ring faces, `X` smooth, pins always the same red, the door
lit, white only for the player's things. The owner added a rule: the hazard red against the block colour at least "2.0
contrast". Every city has a dark sky; skyline silhouettes must not look walkable.

Questions: how much of a city's look comes from the pack and how much from the engine; what to do with the 2.0 rule;
how the journey is ordered and unlocked; what the level select and the speed curve do with 21 levels.

## Options

Pack and engine:

1. **Pack format 2 with named engine shapes**: the pack picks a roof style, a door shape, an `X` pattern, a spike shape,
   a lip tint, motifs and a skyline from engine-owned sets, plus colours; the engine draws them and checks them.
2. **Free shapes in the pack** (polygons for doors, patterns as data).
3. **Code per city** (a draw function per world).

The red rule:

1. **WCAG luminance contrast 2.0** between `HAZARD` and `block`.
2. **CIELAB colour difference (Delta E 1976) at least 35** between `HAZARD` and `block`, `cap` and `roof`.
3. **Hue distance only** (an extension of C12 to darker colours).

Journey:

1. **One series** (levels 10 to 21 after the ruins, world by position).
2. **Two series** (two books in the menu, own progress).
3. **Mixed** (ruins and roofs alternating).

Speed after level 9:

1. **Dip to 90 % at level 10 and rise to 96 %.**
2. **Keep 96 %.**
3. **Rise on to 100 %.**

## Decision

- **Pack option 1.** The engine keeps every reading rule: door shapes all keep the lit opening at the bottom with at
  least 85 % of today's area; spike shapes stay inside today's envelope and colours; `X` patterns stay quiet and inside
  the slab; slopes are drawn inside their collision polygon with a straight surface and never a trim; lip tints are
  engine colours chosen by name. Packs of format 1 (the ruins) resolve the new keys from their own colours, so the ruins
  look exactly as before.
- **Red rule option 2**, to be confirmed by the owner. A luminance contrast of 2.0 cannot hold together with C1 (lip
  against block at least 1.8, with a lip that is not near white) and C5 (contour against block at least 3.0): it needs
  a block darker than luminance 0.07 or lighter than 0.43, while C1 and C5 allow 0.11 to 0.40. What the rule is meant
  to prevent (terracotta, red brick or pink blocks that look like pins) is a hue and chroma question, which Delta E
  measures. All seven packs pass at 35; a red brick (about 14) and a Marrakech pink (about 32) fail.
- New palette rules C16 to C22: the red rule, a dark sky (`luminance <= 0.05` for both back colours), cap and roof
  ordering and contrast against the lip and the sky, quiet `X` patterns, a quiet far skyline, and the existing
  near-white and hazard-hue rules over every new colour.
- Skylines are half-scale, low-contrast silhouettes in the back layer with geometric rules: no horizontal segment of 20 px
  or more and no vertex near a tile row, so nothing lines up with a floor; no step gables.
- **Journey option 1.** It tells one story (from under the ground to above the city), needs no new screens, and the
  world already follows from the series position (ADR 0010). The level select shows one row per world with its name,
  which fits the three columns exactly. Unlocking stays sequential.
- **Speed option 1**, to be confirmed by the owner: a new chapter with a new mechanic starts calmer, and the owner found
  100 % a little too fast.

## Alternatives rejected

- **Free shapes in the pack**: more freedom for a later studio, but a pack could draw a door without light or a pattern
  that looks like a lip; the reading rules would depend on validation of arbitrary geometry. Rejected for now; the
  named sets can grow.
- **Code per city**: no validation possible and a studio could never make a city. Rejected (as in ADR 0013).
- **WCAG contrast 2.0**: infeasible with the lip rules (see above). Rejected unless the owner prefers to relax C1 or C5.
- **Hue distance only**: misses dull reds that differ in hue by more than 15 degrees but still read as "red brick next
  to a red pin". Rejected.
- **Two series**: a menu change and two progressions for the same game. Rejected; can be added later for side trips.
- **Mixed order**: variety, but the story falls apart. Rejected.
- **Keep 96 % / rise to 100 %**: possible; the owner decides (23.19).

## Consequences

- `MazeSkin` gets format 2, the new sets and rules, `MazeArt` gets `lab` and `delta_e`, `MazeDecor` gets skylines,
  `MazeTileShapes` gets slopes, door shapes, patterns, the cap row and two spike shapes; `MazeWorlds` gets seven worlds.
- The Amsterdam brick of the mockup is lighter in the pack (C5) and its roof lighter (C19); the Andalusian horizon glow
  moves away from the hazard hue (C12).
- Levels 10 to 21 are format 2 with `sky`, at most 900 cells, designed by the designer per city before they are built.
- Chapter cards and an ending give the journey its story without a profile change.
