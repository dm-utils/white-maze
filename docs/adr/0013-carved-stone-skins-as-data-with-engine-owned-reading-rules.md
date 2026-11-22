# 0013 Carved stone skins with a crumbly outer edge, as data packs with engine-owned reading rules

Status: accepted (2026-11-22). Design: `docs/design-skins.md` (section 21). Extends ADR 0010 (procedural art, cached
static layers); the tiles layer of 18.8 and the world palettes of 18.4 are replaced.

## Context

After the look steps the owner found the world "still far too blocky" and asked for skins for blocks and special
treatment of edges, at a finished level comparable to well-produced mobile games, with a world studio for players as a
later possibility. The designer offered three directions (A toy block, B carved stone, C living terrain). The owner
chose B as the base with the irregular outer edge of C, only where stone meets air, slightly crumbly and only inwards;
stones stay carved. Pins and rings get an outline; Lilith keeps a thinner outline of her own. A skin must be a data
pack per world, and the lip, the pin colour, the door and the outlines must never come from the pack.

Constraints: collision is the tile grid, so the drawing may never be larger than what collides; the simulation and the
levels do not change; all art stays procedural (ADR 0010); the static layer is baked into one texture per chunk with a
limit of 24 MB per level (18.19); readability rules (18.5) must hold in greyscale and on a phone.

Six questions needed a decision: how the crumbly edge is made and how far it may go; how stones and `X` slabs are
grouped without breaking chunk independence; how the bevel is drawn on an irregular outline; where the line between
pack and engine lies; how the lip is kept readable; and how the extra work is baked and measured.

## Options

Crumbly edge:

1. **Per-vertex inward offsets from the cell hash on world coordinates**, vertices every 8 px, amplitude per face
   orientation (floors 0, walls and ceilings up to 3 px), chips at convex corners.
2. **The mockup's continuous noise** (sine sums per face, 1 to 5 px everywhere).
3. **Uniform offsets on every air face**, floors included (direction C as drawn).
4. **No crumbly edge**, only carved stones (pure B).

Grouping of stones and slabs:

1. **Local lattice rules**: a stone is decided from a 2 x 2 or 2 x 1 lattice anchor and the hash; a slab is the maximal
   row run, else the column run; every chunk computes the same groups and draws a group whole when it touches it.
2. **A greedy scan from the top-left** (the mockup).
3. **Groups clipped to chunk borders.**

Bevel on an irregular outline:

1. **Clipping**: outline in the dark shade, the outline intersected with itself shifted up-left in the light shade, the
   outline shrunk by the bevel in the stone colour (`Geometry2D`).
2. **Per-face quads of an octagon** (the mockup).
3. **A shader.**

Pack and engine:

1. **Packs as JSON-compatible Dictionaries in code; the engine owns lip placement, trim shape, lip shades (the pack
   names a tint), contour, pin colours, door, `X` form, white, floor straightness and maximum offsets; one rule set
   (`check_palette`) gates every pack.**
2. **Skins as code** (a subclass or a draw function per world).
3. **JSON files under `res://skins/` now**, with a loader.
4. **Free colours for the lip and door in the pack, guarded only by validation.**

Baking:

1. **Compute all primitives in `build()`, replay them in the chunk draw, free them after the first frame**; measure
   build time, command count and the first frame.
2. **Keep computing inside the draw callbacks** (as today).

## Decision

- **Crumbly edge, option 1.** Offsets are whole pixels from `MazeArt.pick` of the vertex's world position and the face,
  so a wall across many cells and chunk borders is one continuous edge, and the shared vertex of two cells gets the same
  value from both (minimum of both amplitudes). Floors are straight: the line under the feet is the collision line.
  Walls and ceilings get at most 3 px (2 px on one-tile-thick walls, towers and platforms), convex ledge corners a chip
  of at most 3 px, other convex corners at most 6 px. Faces towards spikes, `X` and the level edge stay straight. `X`
  never gets offsets: straight and smooth against carved and crumbly is a second carrier of "nothing sticks". Checked on
  l003 (narrow pillar: full-width straight top, square corners next to the spikes) and the one-tile towers of l006.
- **Grouping, option 1.** Stones of 1 x 1, 2 x 1 (running or stacked bond) and 2 x 2 from lattice anchors; slabs per row
  run of at least two, else per column run. Groups that cross a chunk border are drawn by every chunk they touch; the
  baked texture clips at its edge, as the door glow already does. Every cell draws everything else only inside itself.
- **Bevel, option 1.** Works on any outline, so the bevel follows the crumbly edge; two Clipper calls per stone.
- **Pack and engine, option 1.** `MazeSkin` (`ui/skin.gd`) holds the engine rules, `validate`, `resolve`, `from_pack`
  and `check_palette` (C1 to C15, the A3 rules plus new ones for bevel, mortar, contour, trim and `X`). `MazeSkins`
  (`ui/skins.gd`) holds the three packs. The contour colour is derived from `block` (`darkened(0.82)`), the door frame
  from `block` (`lightened(0.15)`), the lip shades from a named engine tint. A pack that fails is replaced by the temple
  pack. `MazeWorlds.palette` delegates, so existing callers keep working.
- **Baking, option 1.** Texture memory does not change (same chunks, same `SCALE`). The primitive lists are transient.
  Budgets: tiles primitives at most 150 ms native per level, the longest frame at level start at most 400 ms in
  headless Chrome; fallback is building one chunk per frame. Bake time, first frame and fps are shown in the `--fps`
  label for measurement on phones.
- **Outlines.** Block contour 3 px, seam 1.5 px per side, spikes with a dark inner outline inside today's area, rings
  and beads with a dark stroke under the white. Lilith's outline stays 1.5 px per side: half the block contour, so she
  reads as the foreground; a test pins the ratio.
- **Lip.** A trim of 8 px on floors and 6 px on walls and ceilings, with a light outer stripe, a dark inner stripe and a
  shadow, exactly on `lip_drawn` faces, continuous across cells; at inner corners the two trims meet like a moulding.
  Sampled tests check that every lip face shows contour, then lip, then a dark band, and that no other face shows
  anything lip-like.

## Alternatives rejected

- **Continuous noise (edge option 2)**: smooth curves, but floats and trigonometry per point make the result harder to
  pin in tests, and the mockup's amplitude (up to 5 px on every face) is exactly what the designer flagged as the risk
  for precise jumps. Rejected.
- **Uniform offsets including floors (edge option 3)**: the richest silhouette, but feet would float or sink by up to
  5 px, the first thing a player aiming at a ledge notices. Rejected; floors carry precision.
- **No crumbly edge (edge option 4)**: simplest and fully honest, but the owner asked for the irregular edge; without it
  the result stays "nicer blocky". Rejected.
- **Greedy scan (grouping option 2)**: the result of a cell depends on every cell before it in scan order, so a chunk
  cannot compute its stones alone and a level edit far away changes stones elsewhere. Rejected.
- **Groups clipped to chunks (grouping option 3)**: no cross-chunk drawing, but a visible straight line every 16 tiles
  where no stone ever crosses. Rejected; drawing a group twice costs a few commands.
- **Octagon quads (bevel option 2)**: no Clipper calls, but needs one vertex per face, which a crumbly outline does not
  have; the bevel would not follow the edge. Rejected.
- **Shader (bevel option 3)**: rejected for the reasons of ADR 0010 (WebGL differences, compile stutter, not testable
  headless).
- **Skins as code (pack option 2)**: no validation needed, but a studio could never produce a world, and nothing would
  stop a skin from drawing its own lip. Rejected.
- **JSON files now (pack option 3)**: closest to the studio, but adds a loader, file handling and an export filter
  before anyone needs them. Rejected for now; the packs are JSON-compatible and a round-trip test keeps them so.
- **Free lip and door colours with validation (pack option 4)**: more freedom, but the owner ruled that the lip and the
  door never come from the pack; a named tint keeps world identity (sand, moss, frost) with engine-owned colours.
  Rejected.
- **Computing inside draw callbacks (baking option 2)**: no transient memory, but the cost cannot be measured apart
  from rendering and would be paid again if a chunk ever redraws. Rejected.
- **A drop shadow of blocks on the back wall** (mockups A to C): more depth, but it falls in front of walls and under
  ceilings, exactly in front of ring faces, and makes a mass look larger than it collides. Rejected; depth comes from
  the bevel and the trim's shadow, inside the block.
- **A thicker outline for Lilith matching the blocks**: one style for everything, but she would merge into the world's
  line work. Rejected by the owner; kept thinner on purpose.

## Consequences

- New pure classes `MazeSkin`, `MazeSkins`, `MazeTileShapes` in `ui/`; `MazeWorlds` loses its palette constants;
  conventions get the class names and the palette exception moves from `MazeWorlds` to `MazeSkins`.
- The A3 palette tests become code (`check_palette`) shared by tests and a later studio; new rules C2 to C6, C8, C14,
  C15.
- The door frame colour shifts slightly (derived). The old joint patterns, 5 px lip strips and per-cell `X` drawing are
  removed.
- Simulation, levels, solutions, camera and Lilith's figure are unchanged; A1 stays the guard.
- Level start does more CPU work once; texture memory per level is unchanged; per-frame cost is unchanged apart from one
  extra stroke per ring and bead.
- The world studio (card #033) can build on `validate`, `resolve` and `check_palette`; decor kinds per world still need
  to move into the pack then.
