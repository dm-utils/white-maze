# White Maze - design section 21: skins for blocks and edges (card #032)

This file is section 21 of `docs/design.md`, kept as a separate file like sections 18 (`docs/design-look.md`), 19
(`docs/design-camera.md`) and 20 (`docs/design-feel.md`). Decision record: ADR 0013. Source of the direction: the
designer's note `docs/ideas/2026-11-22-skins.md` and its mockup (not in git), direction B with the outer edge of
direction C.

It changes how the tiles layer of the static chunks is drawn (18.8, 18.5 for `X` and `^`, 18.19 for the bake), the
outline of rings and beads (18.9), and where the world palettes live (18.4). `sim/`, `levels/`, `tests/solutions.json`,
the rules, the tuning, the camera and Lilith's figure are not touched. All new code lives in `ui/` (the UI layer of
this repository; there is no `apps/` folder).

## 21.1 Owner decisions (2026-11-22)

1. Base: direction B, "carved stone": every tile (sometimes a stone of 2 x 1 or 2 x 2) is a stone with a bevel (light
   top and left, dark bottom and right); variation per world; a trim in the lip colour on every ring face
   (`lip_face`); `X` as one smooth slab per row or column.
2. From direction C only the irregular outer edge: where stone meets air the edge is slightly crumbly and only goes
   inwards. The stones themselves stay carved as in B.
3. Pins (spikes) and rings get an outline.
4. Lilith keeps her own, thinner outline, so she stands apart from the world.
5. A skin is a data pack per world (palette, bevel, joints, edge amplitude, motifs). The engine guards the reading
   rules: the lip, the pin colour, the door and the outlines never come from the pack. The world studio itself (card
   #033) is not built now.

## 21.2 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| K1 | Collision is the tile grid of the simulation; the drawing may be smaller than a tile, never larger (designer's note). | None; the rules below only ever move edges inwards. |
| K2 | The camera never shows anything outside the level in play (19.6 step 9); the overview may. | Level edges (21.9) would need their own outline if the follow view could look past them. |
| K3 | `Geometry2D.offset_polygon` and `Geometry2D.intersect_polygons` (Clipper, integer coordinates inside) give the same result for the same input on one machine; the screenshot comparison runs on one machine. | Two shot runs would differ by sub-pixel amounts; `shots.sh compare` would need a tolerance. |
| K4 | GDScript builds the primitives of the largest level (l006, 768 cells) in well under 150 ms native and under 400 ms in the browser (21.12). | Bake chunks over several frames (21.12.3, fallback). |
| K5 | The tiles layer has only these colours near the lip: block shades, mortar, contour, motif, specks, `X` colours, sheen. | A new colour must be added to the palette checks (21.13). |
| K6 | Level files never change for this card; every look decision is derived from the cells and `MazeArt.hash3`. | None. |

## 21.3 Overview

What changes, per layer:

| Layer | Today (18.8) | New |
|---|---|---|
| Back (in the chunk texture, first) | gradient, lines, back decor, door glow | unchanged; the line pattern is chosen by the pack (`back`) instead of by the world id |
| Tiles `#` | flat fill, joint lines, specks, 5 px lip strips | contour, mortar, carved stones with bevel and shade, motifs, specks and cracks, trims on lip faces, crumbly edge towards air |
| Tiles `X` | flat fill per cell, 2 px border, sheen lines | one rounded slab per row run or column run, contour, gradient, sheen bands, straight edges |
| Tiles `^` | fill, highlight, base | same shape, area and colours, plus a dark inner outline and a shaded right half |
| Tiles `F` | posts, lintel, light | same, frame colour derived by the engine, a contour around the opening |
| Dynamic: rings, beads | glow and white stroke | dark outline stroke under the white stroke |
| Dynamic: Lilith | 1.5 px outline | unchanged (21.10.4) |

New files (all pure `RefCounted` classes, no nodes):

| File | Class | Content |
|---|---|---|
| `ui/skin.gd` | `MazeSkin` | Engine rules: constants, lip tints, validation, resolving a pack, palette checks, side kinds, edge offsets, outlines, stone and slab grouping. |
| `ui/skins.gd` | `MazeSkins` | The three shipped packs as data (`TEMPLE`, `JUNGLE`, `CAVE`) and the cached resolved skins. |
| `ui/tile_shapes.gd` | `MazeTileShapes` | Primitives of the tiles layer (backing, stones, slabs, trims, spikes, door), per cell, per group and per chunk. |

Changed: `ui/worlds.gd` (palettes move out; `palette()` delegates), `ui/static_layer.gd` (the tiles layer replays
precomputed primitives), `ui/static_bake.gd` (timing and counters), `ui/world_view.gd` (ring and bead outlines),
`ui/hud.gd` (bake numbers in the `--fps` label), `ui/game.gd` (first frame time), tests, `tools/shots.txt`, a small
`tools/shot_variants.gd`.

## 21.4 Skin packs

### 21.4.1 Engine and pack

| Owned by the engine (never in a pack) | Chosen by the pack, within engine bounds |
|---|---|
| Where lips are (`lip_face`, `lip_drawn`); trim shape and widths; the three lip shades of every tint | Which lip tint (a name from `MazeSkin.LIP_TINTS`) |
| Contour colour (derived from `block`), contour, seam and slab-gap widths | Palette of back wall, stones, mortar, motif, specks, `X` and light |
| Pin colours (`HAZARD`, `HAZARD_HI`, `HAZARD_DARK`, `HAZARD_LINE`), pin area and hitbox | Pin outline shape from `SPIKE_SHAPES` (`spear`, `thorn`, `crystal`) |
| Door shape, door light, door frame colour (derived from `block`), door contour | |
| White (`RING`) and the ring and bead outline | |
| `X` form: straight edges, rounded slab, no trim, gradient direction, sheen alpha | `X` colours (`noring`, `noring_hi`, `noring_lo`, `noring_edge`, `sheen`) |
| Floors are straight; maximum edge offsets and chips; thin-mass limit | Edge offsets on walls and ceilings, corner chip (clamped) |
| Lilith (figure, colours, outline) | |
| The palette checks (21.13) that decide whether a pack is usable | Stone grouping, bond, chamfer, bevel, shade, mortar width, motifs, back line pattern, moss tufts |

### 21.4.2 Format

A pack is a Dictionary that is also valid JSON (colours as `"#RRGGBB"` strings, numbers, strings, booleans, arrays), so
a later studio can save it as a file without a conversion step. The shipped packs are constants in `ui/skins.gd`.

```gdscript
const TEMPLE := {
	"format": 1,
	"id": "temple",
	"names": {"nl": "Tempel", "en": "Temple"},
	"palette": {
		"void": "#140F18", "back_top": "#2A2030", "back_bottom": "#17121C", "back_line": "#33283B",
		"back_decor": "#3A2D45", "block": "#C29A62", "block_hi": "#D8AE70", "block_lo": "#93703F",
		"joint": "#9A7442", "mortar": "#4A3622", "speck": "#A7804C", "motif": "#9A7442",
		"noring": "#3F4260", "noring_hi": "#5B6190", "noring_lo": "#2A2C42", "noring_edge": "#2A2C42",
		"sheen": "#8A90B8", "detail": "#D9B77B", "light": "#FFB45A",
	},
	"lip": "sand",
	"spikes": "spear",
	"back": "masonry",
	"stones": {"pair": 70, "big": 0, "bond": "running", "chamfer": 5.0, "bevel": 3.0, "shade": 0.10, "mortar": 2.5},
	"rim": {"wall": 2, "ceiling": 2, "chip": 4},
	"motifs": [{"kind": "glyph", "chance": 18}],
	"tufts": false,
}
```

Jungle and cave differ in these values (all other palette keys keep their 18.4 values):

| Key | Jungle | Cave |
|---|---|---|
| `palette.block_hi`, `block_lo` | `#8A9B79`, `#4B5843` | `#7484A0`, `#414E64` |
| `palette.mortar`, `motif` | `#2C3526`, `#55703F` | `#27303F`, `#44526A` |
| `palette.noring_hi`, `noring_lo` | `#4F7770`, `#243833` | `#4A82A6`, `#1F3F56` |
| `lip`, `spikes`, `back` | `moss`, `thorn`, `courses` | `frost`, `crystal`, `strata` |
| `stones` | pair 40, big 0, bond `stack`, chamfer 6, bevel 3, shade 0.12, mortar 2.5 | pair 25, big 45, bond `stack`, chamfer 4, bevel 2.5, shade 0.08, mortar 2.0 |
| `rim` | wall 3, ceiling 3, chip 5 | wall 3, ceiling 3, chip 6 |
| `motifs` | `[{"kind": "moss", "chance": 40}]` | `[{"kind": "crack", "chance": 35}, {"kind": "crystal", "chance": 15}]` |
| `tufts` | `true` | `false` |

Field rules (checked by `MazeSkin.validate`):

| Field | Rule |
|---|---|
| `format` | `1` |
| `id` | `^[a-z0-9-]{1,32}$` |
| `names` | `nl` and `en`, non-empty strings |
| `palette` | exactly the keys of `MazeSkin.PALETTE_KEYS` (the 19 above), each `#RRGGBB` |
| `lip` | a key of `LIP_TINTS` |
| `spikes` | one of `SPIKE_SHAPES` |
| `back` | one of `BACK_PATTERNS` (`masonry`, `courses`, `strata`: the three line patterns of `_draw_back_cell` today) |
| `stones.pair`, `stones.big` | whole number 0 to 100 (percent) |
| `stones.bond` | `running` or `stack` |
| `stones.chamfer` | 2 to 6 (px) |
| `stones.bevel` | 2 to 4 (px) |
| `stones.shade` | 0 to 0.15 |
| `stones.mortar` | 1.5 to 4 (px) |
| `rim.wall`, `rim.ceiling` | whole number 0 to `RIM_MAX` (3) |
| `rim.chip` | whole number 0 to `CHIP_MAX` (6) |
| `motifs` | at most 2 entries; `kind` one of `MOTIFS` (`glyph`, `moss`, `crack`, `crystal`), `chance` whole number 0 to 50 |
| `tufts` | boolean |
| Engine-owned keys | `contour`, `outline`, `lip_hi`, `lip_lo`, `door_frame`, `door_light`, `ring`, `hazard`, `hazard_hi`, `hazard_dark`, `hazard_line`, `trim`, `floor_rim`, and `lip` inside `palette`: present anywhere gives an error "engine-owned" |
| Unknown keys | error |
| Palette checks | every rule of 21.13.1 on the resolved palette |

Whole numbers may arrive as floats from JSON (`70.0`); `validate` and `resolve` accept a float when it is whole.

### 21.4.3 Engine constants and API (`ui/skin.gd`)

```gdscript
class_name MazeSkin extends RefCounted
enum Side { SAME, AIR, SPIKE, SEAM, EDGE }
enum Corner { TL, TR, BR, BL }
const FORMAT := 1
const T := 40
const CONTOUR_W := 3.0        # dark band inside the edge towards air, spikes and X
const SEAM_W := 1.5           # per side of a # / X seam (3 px together)
const SLAB_GAP := 3.0         # between two X slabs
const SLAB_RADIUS := 6.0
const TRIM_UP := 8.0          # lip trim width on floors
const TRIM_SIDE := 6.0        # on walls and ceilings
const TRIM_HI_W := 2.0
const TRIM_LO_W := 1.5
const TRIM_SHADOW_W := 2.5
const TRIM_SHADOW_ALPHA := 0.55
const RIM_STEP := 8           # px between edge vertices; 6 vertices per side
const RIM_MAX := 3            # walls and ceilings
const THIN_RIM_MAX := 2       # a side whose opposite side is also air
const FLOOR_CHIP_MAX := 3     # corners next to a floor
const CHIP_MAX := 6
const CONTOUR_DARKEN := 0.82  # contour = block.darkened(CONTOUR_DARKEN)
const DOOR_FRAME_LIGHTEN := 0.15
const SHEEN_ALPHAS := [0.18, 0.45, 0.5] # wide band, thin line, top line
const MOTIF_MARGIN := 4.0
const LIP_TINTS := {
	"sand": ["#F3E0AE", "#F8E6B2", "#CFAE70"],   # lip, lip_hi, lip_lo
	"moss": ["#9BD36A", "#B8E68A", "#6A9E45"],
	"frost": ["#A9C6E4", "#B9D2EC", "#7B98BA"],
}
const SPIKE_SHAPES := ["spear", "thorn", "crystal"]
const BACK_PATTERNS := ["masonry", "courses", "strata"]
const MOTIFS := ["glyph", "moss", "crack", "crystal"]
const PALETTE_KEYS := [...]   # the 19 keys of 21.4.2
const ENGINE_KEYS := [...]    # 21.4.2
const SALT_RIM := 60          # + face (60..63)
const SALT_CHIP := 64
const SALT_BIG := 65
const SALT_PAIR := 66
const SALT_SHADE := 67
const SALT_MOTIF := 68        # + motif index (68, 69)
const SALT_MOTIF_POS := 70    # .. 75
const SALT_SLAB := 76

static func validate(pack: Dictionary) -> PackedStringArray     # empty when usable; one line per problem, "<path>: <problem>"
static func resolve(pack: Dictionary) -> Dictionary             # numbers clamped, colours parsed, engine keys added
static func from_pack(pack: Dictionary) -> Dictionary           # resolve(pack) when valid, else resolve(TEMPLE) + warning
static func check_palette(pal: Dictionary) -> PackedStringArray # the rules of 21.13.1, ids "C1".."C15"
static func side(level: MazeLevel, cell: Vector2i, face: int) -> int
static func rim_face(level: MazeLevel, cell: Vector2i, face: int) -> bool
static func rim_amp(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int) -> int
static func rim_d(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int, i: int) -> int
static func chip(level: MazeLevel, skin: Dictionary, cell: Vector2i, corner: int) -> int
static func outline(level: MazeLevel, skin: Dictionary, cell: Vector2i, inner: bool) -> PackedVector2Array
static func stone_of(level: MazeLevel, skin: Dictionary, cell: Vector2i) -> Rect2i
static func stone_outline(level: MazeLevel, skin: Dictionary, rect: Rect2i) -> PackedVector2Array
static func slab_of(level: MazeLevel, cell: Vector2i) -> Rect2i
static func slab_outline(level: MazeLevel, rect: Rect2i) -> PackedVector2Array
```

A resolved skin:

```
{
  "id": String, "lip": String, "spikes": String, "back": String, "tufts": bool,
  "stones": {...clamped}, "rim": {"wall": int, "ceiling": int, "chip": int}, "motifs": Array,
  "pal": {<the 19 palette colours as Color>, "lip", "lip_hi", "lip_lo": from the tint,
          "contour": block.darkened(CONTOUR_DARKEN), "door_frame": block.lightened(DOOR_FRAME_LIGHTEN)},
}
```

`ui/skins.gd`:

```gdscript
class_name MazeSkins extends RefCounted
const TEMPLE := {...}
const JUNGLE := {...}
const CAVE := {...}
const PACKS := [TEMPLE, JUNGLE, CAVE]          # index = MazeWorlds.World
static func pack(world: int) -> Dictionary      # unknown world: TEMPLE
static func skin(world: int) -> Dictionary      # MazeSkin.from_pack(pack(world)), cached in a static var per world
```

`MazeWorlds` keeps `World`, `COUNT`, `LEVELS_PER_WORLD`, `NAMES`, `for_number`, `from_name` and the shared constants
(`HAZARD`, `HAZARD_HI`, `HAZARD_DARK`, `RING`, `DOOR_LIGHT`) and gets `HAZARD_LINE := Color("#2A0F0C")`. Its `TEMPLE`,
`JUNGLE`, `CAVE` constants are removed; `palette(world)` returns `MazeSkins.skin(world)["pal"]`, which holds every key
`MazeDecor` and the layers read today. The derived `door_frame` is a little darker than the 18.4 values (temple about
`#CBA97A` instead of `#D9B77B`, jungle about `#84907A` instead of `#8C9A7A`, cave about `#738095` instead of
`#7D8CA4`).

## 21.5 Edge geometry

### 21.5.1 Sides

For a cell and a face, `side()` gives:

| Side | Cell in front of the face |
|---|---|
| `EDGE` | outside the grid (any of the four level edges, also below the last row) |
| `AIR` | `EMPTY` (also the `S` and `F` cells) |
| `SPIKE` | `SPIKE` |
| `SAME` | the same kind as the cell (`#` next to `#`, `X` next to `X`) |
| `SEAM` | the other solid kind (`#` next to `X`, `X` next to `#`) |

`rim_face(level, cell, face)` is true when the cell is `#` and `side()` is `AIR`. This equals
`MazeStaticLayer.lip_drawn` for every cell and face (tested, S2): a crumbly edge is always a ring face with a trim, and
a ring face always has its trim.

Insets per side (px, measured from the tile boundary inwards, before the edge offset):

| Side | Cell inner polygon (`outline(inner = true)`) | Stone | Slab |
|---|---|---|---|
| `AIR`, `SPIKE` | `CONTOUR_W` | `CONTOUR_W` | `CONTOUR_W` |
| `SEAM` | `SEAM_W` | `SEAM_W` | `SEAM_W` |
| `SAME` | 0 | `stones.mortar / 2` | `SLAB_GAP / 2` when the neighbour is in another slab, else no side |
| `EDGE` | 0 | 0 | 0 |

### 21.5.2 Vertices and offsets (the crumbly edge)

Each side of a cell has six vertices at 0, 8, 16, 24, 32 and 40 px along the side. Directions (screen coordinates, `y`
down; the outline runs clockwise):

| Side | Start corner | Along `a` | Inward normal `n` |
|---|---|---|---|
| `UP` | TL | `(1, 0)` | `(0, 1)` |
| `RIGHT` | TR | `(0, 1)` | `(-1, 0)` |
| `DOWN` | BR | `(-1, 0)` | `(0, -1)` |
| `LEFT` | BL | `(0, -1)` | `(1, 0)` |

Vertex `i` of side `s` is `V = start + a * 8 * i` in world px (always whole numbers). A point of the outline is
`V + n * (rim_d(s, i) + inset)`.

Amplitude of a side:

```
rim_amp(cell, s):
  if not rim_face(cell, s): return 0
  if s == UP: return 0                                   # floors are straight
  a = skin.rim.ceiling if s == DOWN else skin.rim.wall   # 0..RIM_MAX
  if side(cell, opposite(s)) == AIR: a = min(a, THIN_RIM_MAX)   # one tile thick: towers, thin platforms
  return a
```

Offset of a vertex (whole px, always `>= 0`, so the edge only ever moves inwards):

```
rim_d(cell, s, i):
  amp = rim_amp(cell, s)
  if amp == 0: return 0
  h = MazeArt.pick(V.x, V.y, SALT_RIM + s, RIM_MAX + 1)      # 0..3, from the vertex's world position
  if 1 <= i <= 4: return min(h, amp)
  m = cell + a if i == 5 else cell - a                       # the cell sharing this vertex on the same face line
  if rim_face(m, s): return min(h, amp, rim_amp(m, s))       # continuation: both cells compute the same value
  return 0                                                   # concave corner, material change, or a chipped corner
```

The hash uses the vertex's world position and the face, not the cell, so a wall that runs over many cells (and over
chunk borders) is one continuous edge; the shared vertex at a cell border gets the same offset from both cells (the
minimum of both amplitudes), so there is never a step at a cell border.

### 21.5.3 Corners

A corner `K` sits between the side `p` that ends there and the side `q` that starts there (TL: `p = LEFT`, `q = UP`).

- **Chipped corner**: the cell is `#` and both `p` and `q` are `AIR` (a convex outer corner). Chip size:
  `k = max(0, base - MazeArt.pick(K.x, K.y, SALT_CHIP, 2))` with `base = min(skin.rim.chip, FLOOR_CHIP_MAX)` when `p` or
  `q` is `UP`, else `min(skin.rim.chip, CHIP_MAX)`. The corner is replaced by two points:
  `K + n(p) * ip + n(q) * iq + n(q) * k` and `K + n(p) * ip + n(q) * iq + n(p) * k` (`ip`, `iq` the insets of the two
  sides; 0 for the outer silhouette). The chip is a 45 degree cut; with insets the inner cut stays parallel, so the
  contour band is about 4.2 px thick across the cut.
- **Other corners**: one point `K + n(p) * (rim_d(p, 5) + ip) + n(q) * (rim_d(q, 0) + iq)`.

`X` cells never get offsets or chips (`rim_face` is false), so `X` edges are always straight.

### 21.5.4 Outlines

`outline(level, skin, cell, inner)` returns the closed polygon of a `#` or `X` cell: for each corner TL, TR, BR, BL its
point or two chip points, then the interior vertices `i = 1..4` of the side that starts there, but only when that side
has `rim_amp > 0` (straight sides need no interior points). `inner = false` gives the silhouette (insets 0); `inner =
true` uses the cell insets of 21.5.1. Every point lies inside the cell rectangle (S4).

## 21.6 Stones

### 21.6.1 Grouping

`stone_of(cell)` returns the stone a `#` cell belongs to, decided only from the cell, its lattice neighbours and the
hash, so every chunk finds the same stones:

```
stone_of(cell):
  a = Vector2i(cell.x - cell.x % 2, cell.y - cell.y % 2)                   # 2 x 2 lattice anchor
  if big(a): return Rect2i(a, Vector2i(2, 2))
  off = cell.y % 2 if stones.bond == "running" else 0
  px = cell.x - posmod(cell.x - off, 2)                                     # 2 x 1 lattice anchor in this row
  if pair(Vector2i(px, cell.y)): return Rect2i(px, cell.y, 2, 1)
  return Rect2i(cell, Vector2i.ONE)

big(a):  chance(a.x, a.y, SALT_BIG, stones.big) and the four cells of Rect2i(a, (2, 2)) are all SOLID
pair(p): chance(p.x, p.y, SALT_PAIR, stones.pair) and p and p + (1, 0) are SOLID
         and neither lies in a big stone (big() of their own lattice anchors is false)
```

`level.cell` returns `NO_RING` outside the grid and `EMPTY` below it, so a stone never leaves the grid. Every cell of a
returned rectangle returns the same rectangle (S10).

### 21.6.2 Stone outline and bevel

`stone_outline(rect)` walks the perimeter of the rectangle clockwise. Each perimeter cell contributes its side points
(21.5.2) with the stone insets of 21.5.1; where the inset changes between two cells of one side (for example `AIR`
above one cell, `SAME` above the next) both end points are kept, so the outline has a small step inside the mass. At
the four corners of the rectangle the corner point `P` (21.5.3, with stone insets) is chamfered: it is replaced by
`P - a(p) * c` and `P + a(q) * c`, with `c = stones.chamfer`, or `max(stones.chamfer, k + 1)` at a chipped corner so the
stone stays inside the chip.

Drawing a stone (`MazeTileShapes.stone`), with `O = stone_outline(rect)`, `b = stones.bevel`:

1. `O` in `block_lo` (the dark bottom and right bevel).
2. Every polygon of `Geometry2D.intersect_polygons(O, O translated by (-b, -b))` in `block_hi` (the light top and left
   bevel).
3. Every polygon of `Geometry2D.offset_polygon(O, -b)` in the stone colour:
   `v = MazeArt.pick(anchor, SALT_SHADE, 5) - 2`; `block.lerp(block_hi if v > 0 else block_lo, abs(v) * stones.shade)`.
4. The motif (21.6.3).

The bevel follows the crumbly edge on air sides, because it is computed from the outline itself.

### 21.6.3 Motifs

For each stone, the motifs of the pack are tried in order; the first with `chance(anchor, SALT_MOTIF + index,
motif.chance)` is drawn, so a stone has at most one motif. A motif lives in the stone's motif area: the stone rectangle
shrunk by `CONTOUR_W + trim + TRIM_SHADOW_W + MOTIF_MARGIN` on sides that are lip faces (17.5 px on a floor, 15.5 px on
a wall or ceiling) and by `max(stones.chamfer, stones.bevel) + MOTIF_MARGIN` on the other sides. When the area is
smaller than 12 x 12 px the stone gets no motif. Positions inside the area come from `pick(anchor, SALT_MOTIF_POS + j,
...)`.

| Kind | Shape (all inside the motif area) | Colour |
|---|---|---|
| `glyph` | an incised sun: circle polyline r 4.5 and two 3 px dashes left and right of it, width 2 | `joint` |
| `moss` | two ellipses (9 x 4.5 and 4 x 6 half axes) | `motif` at alpha 0.85 |
| `crack` | a 4-point polyline, mostly vertical, width 2 | `joint` |
| `crystal` | a flat hexagon 6 px wide and 8 px high (no corner sharper than 120 degrees) | `block_hi` |

Existing details stay: `MazeDecor.speck_shapes` per `#` cell and the `crack` decor items (18.20) are drawn after the
stones and before the trims.

## 21.7 `X` slabs

`slab_of(cell)` for an `X` cell:

```
h = the maximal run of X cells in the cell's row that contains the cell
if h.size.x >= 2: return h
v = the maximal run of X cells in the cell's column that contains the cell and whose cells all have a row run of 1
return v                                                   # a single X cell is a 1 x 1 slab
```

Drawing (`MazeTileShapes.slab`): the slab rectangle shrunk by the slab insets of 21.5.1, with corners rounded by
`SLAB_RADIUS` (5 points per quarter circle) except corners where one of the two sides is `EDGE` (those stay square, so
the slab runs flush into the level edge).

1. Fill: one `vpoly`. The light axis is the short axis (top to bottom for a row slab and a 1 x 1 slab, left to right for
   a column slab). Colour at position `t` (0 on the lit side, 1 on the far side): `noring_hi.lerp(noring, t / 0.18)` for
   `t < 0.18`, else `noring.lerp(noring_lo, (t - 0.18) / 0.82)`.
2. Sheen: along the long axis at `p = 19 + 38 * j + MazeArt.pick(anchor, SALT_SLAB, 19)` for every `p` below the length
   plus 20: a band 8 px wide in `sheen` at alpha 0.18 and a line 2 px wide 11 px further at alpha 0.45, both slanted by
   0.7 short-axis length per unit, clipped to the fill polygon with `Geometry2D.intersect_polygons`.
3. Edge: closed polyline 1.5 px inside the outline, width 2, `noring_edge`.
4. Top line: on the lit side, 3 px inside, from `SLAB_RADIUS + 1` to the length minus `SLAB_RADIUS + 1`, width 2,
   `sheen` at alpha 0.5.

`X` has no trim, no edge offsets and no chips. The contrast between straight, smooth slabs and carved, slightly crumbly
stone is the second carrier of "nothing sticks here", next to the colour.

## 21.8 Trims (the lip) and inner corners

For every face with `rim_face` (equal to `lip_drawn`), `MazeTileShapes.trims` draws four bands. A band between depths
`d0` and `d1` is the polygon between the side's points at inset `d0` and at inset `d1` (same vertices and edge offsets as
the outline, so it follows the crumbly edge), extended 1 px past both ends, and intersected with the cell's inner
polygon (`outline(inner = true)`); the intersection cuts it cleanly at contours, seams and chips of the neighbouring
sides. `w = TRIM_UP` on `UP`, `TRIM_SIDE` elsewhere; `d0` of the first band is `CONTOUR_W - 0.5` so no sliver of
background stays between contour and trim.

| Band | Depth (px from the edge, plus the edge offset) | Colour |
|---|---|---|
| Lip | `CONTOUR_W` to `CONTOUR_W + w` | `lip` |
| Light stripe | `CONTOUR_W` to `CONTOUR_W + TRIM_HI_W` (the air side) | `lip_hi` |
| Dark stripe | `CONTOUR_W + w - TRIM_LO_W` to `CONTOUR_W + w` | `lip_lo` |
| Shadow | `CONTOUR_W + w` to `CONTOUR_W + w + TRIM_SHADOW_W` | `contour` at `TRIM_SHADOW_ALPHA` |

Across a cell border with `SAME` on the side the trim runs to the border, so a floor of many cells has one unbroken
trim, also over stone joints and chunk borders.

**Inner corner joint.** A `#` cell `D` whose two sides at a corner are `SAME`, whose diagonal cell at that corner is
`EMPTY`, and whose two neighbours at that corner have their faces towards the diagonal cell as lip faces (for example a
floor running into a wall) continues both trims into its corner until they meet. Example: floor `A` left of `D`, wall
`W` above `D`, corner point `K` = top-left of `D`: the contour square `[K, K + (3, 3)]` stays contour; the floor trim
band continues `CONTOUR_W + TRIM_SIDE` (9 px) into `D` (`x` from `K.x` to `K.x + 9`, `y` from `K.y + 3` to `K.y + 11`);
the wall trim band continues `CONTOUR_W + TRIM_UP` (11 px) into `D` (`x` from `K.x + 3` to `K.x + 9`, `y` from `K.y` to
`K.y + 11`); the union in `lip`, with the shadow band along its inner edges. Other corners are the same, mirrored. All
of it lies inside `D`; `D` has no face towards air, so no new ring face is suggested; the lip turns the corner like a
moulding.

## 21.9 Transitions

| Where | Treatment |
|---|---|
| `#` next to `#` (same mass) | No contour. Mortar gap of `stones.mortar` between stones; none inside a 2 x 1 or 2 x 2 stone. |
| `#` next to air | Contour 3 px, crumbly edge (walls and ceilings), trim, chips at convex corners. Floors straight. |
| `#` next to `X` | Seam: 1.5 px on both sides, a 3 px contour line exactly on the tile border. No trim, no offsets on that side. A floor trim that runs into an `X` cell ends 1.5 px before the border (its end vertex offset is 0). The `X` slab corner on that side is rounded. |
| `#` or `X` next to `^` | Straight contour of 3 px, no trim, no offset, no chip (the spike base sits flat on it). A pillar between spikes keeps a straight top of its full width (21.11). |
| `X` next to air | Straight contour of 3 px, no trim. |
| `X` next to `X` in another slab | 3 px gap in contour colour between the two slabs. |
| Level edge (`EDGE`) | No contour, no offset, inset 0: stones and slabs run flush to the level border; the bottom row gets no trim (as `lip_drawn` today). |
| Concave corner (floor into wall) | End vertices next to the corner have offset 0; the inner corner joint (21.8) continues the lip. |
| Convex corner (ledge) | Chip of at most 3 px next to a floor, at most `rim.chip` (max 6) elsewhere. |
| Door `F` | The door stays inside its cell (18.8); the floor under it has its trim like every floor. |
| Chunk border | Every cell draws only inside its own cell (backing, trims, inner corner joints). Stones and slabs that cross a chunk border are drawn whole by every chunk that holds one of their cells; the chunk texture clips at its edge (as the door glow, 18.19). Edge offsets come from world positions, so both sides of a border agree. |

## 21.10 Spikes, door, rings, beads and Lilith

### 21.10.1 Spikes

The outline points per shape are those of `_draw_spikes` today (`spear` = temple, `thorn` = jungle, `crystal` = cave).
Per spike: the polygon `pts` in `HAZARD_LINE`; every polygon of `Geometry2D.offset_polygon(pts, -1.5)` in `HAZARD`; that
fill intersected with the half of the spike right of its apex in `HAZARD_DARK` at alpha 0.45; the highlight polyline on
the lit half of the fill polygon in `HAZARD_HI`, width 2; the base rectangle in `HAZARD_DARK` as today. The drawn area is
exactly the area of today (the outline is inside it), the colours are the shared constants, and the pack can only pick
the outline shape.

### 21.10.2 Door

Geometry and light as in 18.8. `door_frame` is derived (21.4.3). New: a contour polyline of width 2 in `contour` along
the inner edges of posts and lintel (from `(5, 40)` up to `(5, 6)`, across to `(35, 6)`, down to `(35, 40)`, relative to
the cell), inside the cell.

### 21.10.3 Rings and beads

```gdscript
const RING_OUTLINE := Color("#120E10", 0.6)
const RING_OUTLINE_W := 8.0          # RING_STROKE + 3
const BEAD_OUTLINE_R := 8.5          # BEAD_R + 1.5
static func ring_strokes(flash: bool) -> Array   # [[width, Color], ...] in draw order: two glows, outline, white
```

`_draw_ring` draws the strokes of `ring_strokes` in order; the arrow is unchanged (it is faint, an outline would be
stronger than the arrow). A bead in flight: halo, then a circle of `BEAD_OUTLINE_R` in `RING_OUTLINE`, then the bead.
The bead in Lilith's hand and the bandolier slots are part of her figure and keep their look.

### 21.10.4 Lilith's outline

Unchanged: `#120E10` at alpha 0.85, 1.5 px per side (`OUTLINE_LINE` 3.0 added to line widths, `OUTLINE_CIRCLE` 1.5).
The block contour is 3 px, twice as thick. That ratio is the point: the world is drawn with a heavy line, the player
with a light one, so she reads as the foreground figure. Her outline colour is neutral, the block contours are dark
tints of each world's block colour, so the two never merge into one line where she touches a wall. A test pins the
ratio (S9). No refinement is needed.

## 21.11 Precision on floors, walls and ring faces

| Face | Edge | Max distance between drawn edge and collision edge |
|---|---|---|
| Floor (`UP` lip face) | straight | 0 px along the floor; at a ledge corner a chip of at most 3 px |
| Wall | crumbly | `rim.wall` (max 3 px; 2 px on a one-tile-thick wall or tower) |
| Ceiling | crumbly | `rim.ceiling` (max 3 px; 2 px on a one-tile-thick platform) |
| Towards spikes, `X`, level edge | straight | 0 px |
| `X` | straight | 0 px |

Why floors are straight: a player who aims at a ledge looks at the line under the feet; any offset there shows as
floating or sinking feet. At zoom 2.0 one world px is 2 canvas px on desktop and about 1.2 physical px on a 960 x 432
phone, so an offset of 1 px would not read as crumbly anyway, only as wrong. Walls and ceilings are touched by the side
and the head, where 3 px (6 canvas px, 0.8 % of the screen height) reads as texture, not as a different position. A ring
on a wall sits `RING_LIFT` (5 px) in front of the tile border as before, so at most 8 px in front of the drawn edge.

Check on l003 ("Narrow pillar", temple: wall 2, ceiling 2, chip 4):

| Place | Cells | Result |
|---|---|---|
| The pillar between spikes | `(24, 11)` | `UP` air, `LEFT` and `RIGHT` spike: top edge exactly `y = 440` from `x = 960` to `1000`, no chips, contour straight on both sides; trim from `x = 963` to `997`. |
| Ledge left of the pit | `(10, 11)` | `UP` and `LEFT` air: chip of 2 or 3 px at the top-left corner, floor straight; wall below the corner crumbly up to 2 px. |
| Ledge right edge | `(19, 11)` | `RIGHT` spike: square corner, straight. |
| Spawn floor | `(1, 11)`, `(2, 11)` | Straight floor; chip at the top-right of `(2, 11)`; `(0, 11)` has a seam on top towards the `X` column. |
| `X` column | `(0, 5)` to `(0, 10)` | One column slab, flush with the left level edge, rounded corners on the right, seams top and bottom, straight contour towards the room. |
| Wall before the door | `(28, 6)` to `(28, 10)` | Crumbly left wall up to 2 px; chip at the top-left of `(28, 6)`; offset 0 at the bottom (the cell below faces a spike). |
| Ceiling | row 0 | Crumbly ceiling up to 2 px, flush with the top level edge. |

The same applies to the towers of l006 (jungle: wall 3, so 2 on the one-tile towers at columns 9, 13 and 17): straight
tops of full width with chips of at most 3 px, walls at most 2 px, offset 0 where a tower meets the spikes at its foot.

## 21.12 Baking

### 21.12.1 Order and caching

The tiles layer no longer computes while drawing. `MazeStaticLayer.build` (kind `TILES`) computes the primitives of
every chunk with `MazeTileShapes.chunk(level, skin, cx, cy)` and stores them; the chunk's `draw` callback replays them
(`_draw_shapes`, with the new type `"vpoly"` drawn with `draw_polygon(pts, cols)`) and then frees that chunk's list.
`draws` still counts one draw per chunk (A6 unchanged). The back layer stays as it is (its pattern now comes from
`skin.back`).

Order inside `MazeTileShapes.chunk`, over the cells of the chunk:

1. Backing of every `#` and `X` cell: the silhouette in `contour`; for `#` the inner polygon in `mortar`.
2. Every stone with at least one cell in the chunk (each once).
3. Every slab with at least one cell in the chunk (each once).
4. Specks and `crack` decor items of the `#` cells.
5. Trims and inner corner joints of the cells.
6. Moss tufts in empty cells (when `skin.tufts`), spikes, the door.

### 21.12.2 Memory

Texture memory is unchanged: the same chunks at the same `SCALE` (2 texels per world px), so the same sizes as 18.19
(l001 17.2 MB, l002 14.3, l003 17.2, l004 17.2, l005 14.7, l006 19.7, l007 16.6, l008 16.4, l009 16.4), under the 24 MB
per level. The primitive lists are host memory, live only between `build()` and the first frame: about 8 to 12
primitives per solid cell, at most about 10 000 per level (l006), a few MB of Dictionaries, freed after each chunk's
draw.

### 21.12.3 Time

Estimate for l006 (768 cells, about 300 `#` cells, 150 lip faces, 190 stones): about 1 000 Clipper calls (2 per stone,
4 per lip face, a few per slab) at 10 to 30 µs and about 30 µs of GDScript per cell, so 40 to 80 ms native on a desktop
and 100 to 300 ms in the browser (WebAssembly, GDScript 2 to 4 times slower). The GPU work of the first frame grows
with the command count, about 1.0 to 1.4 times today's (polygons have more vertices, but cells have fewer separate
joint rectangles). Budget:

- `build_usec` of the tiles primitives at most 150 ms native for every shipped level in every world (logged by the
  test; the test fails only above 1 000 ms, so a slow CI machine does not flake);
- in headless Chrome (method of 18.19), the longest frame in the first second after opening l003, l006 and l009 at most
  400 ms, and the frame rate after that equal to develop within noise.

Fallback when the browser budget is missed: build the primitives of one chunk per frame, the chunk under the camera
first, and bake each chunk when its list is ready (the intro pan of 19.9 covers the first second). Not built unless
needed; record it as a deviation.

### 21.12.4 Measurement

- `MazeStaticBake.build_usec` (`Time.get_ticks_usec()` around the primitive build in `build()`),
  `MazeStaticBake.command_count` (primitives of all chunks), `MazeStaticBake.first_frame_usec` (set by `MazeGame` in
  the first `_process` after `build()`: the time since `build()` returned).
- `--fps` (and `?fps` in the web build) shows them in the existing label: `"bake %d ms  first %d ms  %d fps"`. The label
  still ends with `fps`.
- A test (S13) builds every shipped level in every world, prints `bake <id> <world>: <ms> ms, <n> primitives, <bytes>
  bytes`, checks the bounds above and that every chunk's list is empty after the first frame.
- The tester measures in headless Chrome and on a phone (web export, `?fps`): bake, first frame and frame rate on l003,
  l006 and l009, develop against the branch.

## 21.13 Readability rules

### 21.13.1 Palette checks (`MazeSkin.check_palette`)

The A3 tests of 18.12 move into code, so the game tests and a later studio use one set of rules. Luminance and contrast
are WCAG (`MazeArt.luminance`, `MazeArt.contrast`); a greyscale copy shows exactly this luminance. `sheen` is checked as
composited at its strongest alpha (0.5) over `noring`.

| Id | Rule |
|---|---|
| C1 | `contrast(lip, block) >= 1.8` (A3) |
| C2 | `contrast(lip, block_hi) >= 1.5` (the bevel highlight never reads as a lip) |
| C3 | the lip is the lightest colour of the tiles layer: for `c` in `block_hi`, `joint`, `mortar`, `speck`, `motif`, `noring_hi`, sheen over `noring`, `door_frame`: `luminance(lip) > luminance(c)` and `contrast(lip, c) >= 1.3` |
| C4 | `luminance`: `block_lo < block < block_hi`; `joint < block`; `mortar < block_lo`; `noring_lo < noring < noring_hi`; `noring_edge < noring`; `lip_lo < lip < lip_hi` (extends A3) |
| C5 | `contrast(contour, block) >= 3.0` |
| C6 | `contrast(mortar, block) >= 2.0` |
| C7 | `contrast(noring, back_top) >= 1.5` and the same against `back_bottom` (A3) |
| C8 | `contrast(lip, noring_hi) >= 2.0` (the lit edge of `X` never reads as a lip) |
| C9 | `contrast(HAZARD, back_top) >= 3` and the same against `back_bottom` (A3) |
| C10 | `back_decor` and `back_line`: `contrast <= 1.6` against both back colours (A3) |
| C11 | no colour of the resolved palette is near white (HSV saturation `< 0.2` and value `> 0.8`) (A3) |
| C12 | no colour of the resolved palette has a hue within 15 degrees of `HAZARD` with saturation `> 0.4` and value `> 0.45` (A3) |
| C13 | `contrast(MazeLilith.HAIR, back_top) >= 3.0` and the same against `back_bottom` (F7) |
| C14 | `contrast(door_frame, back_top) >= 2.0` |
| C15 | engine colours: every lip tint passes C11 and C12; `luminance(HAZARD_LINE) < luminance(HAZARD_DARK)` |

Approximate values of the shipped packs (temple, jungle, cave; the test recomputes them): C1 2.0, 2.5, 3.1; C2 1.58,
1.69, 2.14; C5 6.5, 4.1, 3.4; C6 4.4, 2.9, 2.4; C8 4.5, 2.8, 2.4; the tightest C3 pair is the cave lip against sheen over
`noring`, about 1.6.

### 21.13.2 The lip at a glance (sampled)

`tests/skin_tests.gd` has a small sampler: `_colour_at(shapes, point, base)` composites, in draw order, every primitive
that contains the point (`poly`: point in polygon; `vpoly`: the vertex colour with the highest luminance, a conservative
choice; `line`, `polyline`: distance to a segment at most half the width; `circle`) over `base` with its alpha. With it:

- For every lip face (`lip_drawn`) of l001, l003, l005 and l009 in their own world, and of l001 in all three worlds:
  along the inward normal at 25 %, 50 % and 75 % of the face, starting at the tile border: the first opaque colour is
  `contour` for at least 2 px; then within the next 2 px a run of at least 5 px of `lip`, `lip_hi` or `lip_lo`; then a
  colour with `contrast(lip, c) >= 1.8` within 4 px after the run.
- For every face towards air or a spike of an `X` cell and every `#` face towards a spike, a seam or the level edge: no
  sample within 16 px of the border has `contrast(lip, c) < 1.3` (nothing lip-like where no ring can go).
- For every `#` cell that is not next to air: no sample on a 4 x 4 grid inside the cell has `contrast(lip, c) < 1.3`,
  except inside an inner corner joint.

## 21.14 Acceptance

- S1 Simulation untouched: `git diff <base> -- sim/ levels/ tests/solutions.json` is empty; all existing checks stay
  green (`MIN_CHECKS` only goes up); `tools/check_levels.gd` exits 0; A1 (snapshot through the game screen) green.
- S2 Data: the three shipped packs give no errors from `validate`; `MazeWorlds.palette(w)` equals
  `MazeSkins.skin(w)["pal"]` and holds every key that `MazeDecor`, `MazeStaticLayer` and the world view read;
  `palette(99)` equals `palette(TEMPLE)`; a pack survives `JSON.parse_string(JSON.stringify(pack))` with an equal
  resolved skin; `rim_face` equals `MazeStaticLayer.lip_drawn` for every cell and face of every shipped level.
- S3 Engine guard: a pack with each engine-owned key (`contour`, `lip_hi`, `door_frame`, `hazard`, `ring`, `lip` in
  `palette`) gives an "engine-owned" error per key; out-of-range values (`rim.wall` 9, `stones.chamfer` 20, `motifs`
  with 3 entries, unknown `lip` tint, unknown motif) each give an error; `from_pack` of such a pack returns the temple
  skin; `resolve` clamps (`rim.wall` 9 becomes 3) and never takes `contour`, lip shades, door frame or hazard colours
  from the pack.
- S4 Never larger: for every `#` and `X` cell of every shipped level in every world and of the 64 x 64 random map of A5:
  every point of `outline` (both kinds), of the backing, of the trims and inner corner joints lies inside the cell
  rectangle (tolerance 0.01 px, lines including half their width); every primitive of a stone lies inside the stone
  rectangle, of a slab inside the slab rectangle, of a spike inside today's spike polygon plus its base rectangle, of
  the door inside the `F` cell; every `rim_d` is `>= 0`.
- S5 Continuity: for every pair of neighbouring cells on one face line with `rim_face` on both, the shared vertex has
  the same offset from both cells; `MazeTileShapes.chunk` gives equal primitives for a stone or slab whether it is
  computed for one chunk or for a neighbouring chunk it also touches; two builds give equal primitive lists.
- S6 Precision: on every shipped level, every silhouette point on an `UP` side has `y` equal to the cell top, except
  chip points within `FLOOR_CHIP_MAX` of a convex corner; every `rim_d` is at most `RIM_MAX`, at most `THIN_RIM_MAX` on
  sides whose opposite side is air; no chip next to a floor is larger than 3; the cases of the l003 table (21.11) hold
  exactly, including the pillar top from `(960, 440)` to `(1000, 440)` without chips; on l006 the tower tops are
  straight and the tower walls are at most 2 px.
- S7 Lip at a glance: the sampled checks of 21.13.2.
- S8 Palettes: `check_palette` is empty for the three packs; for every rule C1 to C15 a mutation of the temple pack (or
  of an engine colour in a test copy) that breaks it gives an error with that id; the A3 and F7 tests of
  `art_tests.gd` run on the resolved palettes.
- S9 Outline hierarchy: `CONTOUR_W >= 2 * (MazeLilith.OUTLINE_LINE / 2)` (the block contour is at least twice
  Lilith's outline per side); `MazeLilith.OUTLINE`, `OUTLINE_LINE` and `OUTLINE_CIRCLE` unchanged;
  `RING_OUTLINE_W > RING_STROKE`.
- S10 Groups: `stone_of` and `slab_of` are consistent (every cell of a returned rectangle returns the same rectangle),
  every `#` cell is in exactly one stone and every `X` cell in exactly one slab, stones contain only `SOLID` cells and
  are 1 x 1, 2 x 1 or 2 x 2; on the 64 x 64 random map with the cave pack 2 x 2 stones occur, with the temple pack no
  2 x 2 stones occur and 2 x 1 stones follow the running bond; slabs are maximal runs by the rule of 21.7.
- S11 Spikes: the colours of a spike's primitives are only `HAZARD`, `HAZARD_HI`, `HAZARD_DARK`, `HAZARD_LINE` (with
  alpha); the outline polygon equals today's polygon; same for all three shapes.
- S12 Rings and beads: `ring_strokes(false)` and `ring_strokes(true)` give the glows, then `[RING_OUTLINE_W,
  RING_OUTLINE]`, then the white stroke last.
- S13 Bake: `baked_bytes` at most 24 MB per level (unchanged test) and equal to before this card; `build_usec` printed
  per level and world, at most 1 000 ms each; `command_count` at most 8 000 per chunk; after the first frame every
  chunk's primitive list is empty; A6 (`static_draws == chunk_count`, no rebuild on restart) green.
- S14 Determinism: two runs of all shots give identical images (`shots.sh compare`).
- S15 Shots: all scenarios of 21.15 and the existing ones are produced without errors and reviewed (21.17).
- S16 Performance: the budgets of 21.12.3 in headless Chrome; frame rate on l001, l006 and l009 equal to develop within
  noise.

## 21.15 Screenshot scenarios (added to `tools/shots.txt`)

```
skin-pillar 1280x720 --level=l003 --keys=<n>
skin-towers 1280x720 --level=l006 --keys=<n>
skin-x 1280x720 --level=l003 --world=cave
skin-rings 1280x720 --level=l002 --keys=<n>
skin-temple-all 1280x720 --level=l003 --camera=overview
skin-jungle-all 1280x720 --level=l006 --camera=overview
skin-cave-all 1280x720 --level=l009 --camera=overview
skin-phone 960x432 --level=l006 --touch --safe=40,0,40,16
```

- `skin-pillar`: the developer picks a `--keys` script (a prefix of the stored l003 solution) so that Lilith stands on
  or next to the pillar at `(24, 11)`; `skin-towers`: Lilith on the first tower of l006; `skin-rings`: at least one
  thrown ring on a wall and one on a floor in view. The chosen scripts go into the file.
- `tools/shot_variants.gd` (headless, `godot --headless -s res://tools/shot_variants.gd -- <png> ...`) writes for each
  shot a greyscale copy (WCAG luminance, `-grey.png`) and a 50 % copy (`-half.png`) next to it, so the tester's grey
  and size checks are reproducible.

## 21.16 Developer steps (card after #032)

Branch `feature/skins`, one commit per step, each step green before the next. Every step keeps S1 and runs all shots;
"compare" means `shots.sh compare` against the previous step.

1. **Packs and rules, no visible change.** `ui/skin.gd` (constants, `validate`, `resolve`, `from_pack`,
   `check_palette`), `ui/skins.gd` with the three packs; `MazeWorlds.palette` delegates; `HAZARD_LINE`. The back layer
   reads `skin.back` instead of the world id. Tests S2, S3, S8 in a new suite `tests/skin_tests.gd` (added to
   `SUITES`); `art_tests.gd` A8 compares `palette(99)` with `palette(TEMPLE)`. Shots: compare; only the door frames
   differ (derived colour).
2. **Primitive cache, no visible change.** `ui/tile_shapes.gd` produces today's tiles look as primitives (blocks,
   joints, specks, cracks, lips, `X`, spikes, door, tufts); `MazeStaticLayer` replays them; `"vpoly"` in
   `_draw_shapes`; `build_usec`, `command_count`, `first_frame_usec`; the `--fps` label. Shots: compare, identical.
   Write down `build_usec` per level: this is the baseline.
3. **Contour, mortar and stones, straight edges.** `side`, `outline` (offsets forced to 0 in this step), `stone_of`,
   `stone_outline`, stone drawing with bevel and shade; the old joints go; the old 5 px lip strips stay on top for now.
   Shots: `temple`, `jungle-play`, `cave`, `phone-small`, with grey and half copies: every block has a dark contour
   towards air, stones read as carved, 2 x 1 and 2 x 2 stones per world, lips still visible.
4. **Trims.** The four bands and the inner corner joint replace the lip strips. Tests S7. Shots: the same plus
   `skin-temple-all`, `skin-jungle-all`, `skin-cave-all` and their grey copies: every ring face has a trim, no other
   face has one, inner corners turn.
5. **`X` slabs.** `slab_of`, `slab_outline`, slab drawing; the old `X` drawing goes. Shots: `skin-x`, `temple`,
   `cave`: one slab per run, seams to `#`, flush at the level edge, no trim.
6. **Crumbly edge.** `rim_amp`, `rim_d`, `chip` live; trims and stones follow. Tests S4, S5, S6, S10. Shots:
   `skin-pillar`, `skin-towers`, `skin-phone`, the three overviews: floors straight, pillar top full width, walls and
   ceilings slightly crumbly, no step at cell or chunk borders (look at the chunk borders at tile 16 and 32).
7. **Motifs, tufts flag, door.** Motifs per pack, `tufts` from the pack, derived door frame and door contour. Shots:
   world shots and `decor-*`: motifs quiet, never in the trim, door unchanged apart from the contour.
8. **Spikes, rings and beads.** Spike outline and shade, `ring_strokes`, bead outline. Tests S11, S12, S9. Shots:
   `lilith-dead` (spike pit), `skin-rings`, `medium-aim`: spikes same size and colour, rings stand out on light sand and
   on frost.
9. **Measure and document.** Tests S13; `tools/shot_variants.gd`; bake numbers in 21.19 against the baseline of step
   2; deviations as built in 21.19; raise `MIN_CHECKS`; in `docs/design.md` add `## 21. Skins` with a pointer to this
   file and mention it in the status line; in `docs/design-look.md` 18.4, 18.5, 18.8 and 18.9 one line each: "Changed
   by section 21 (`docs/design-skins.md`)"; `docs/conventions.md`: classes `MazeSkin`, `MazeSkins`, `MazeTileShapes`,
   and the palette exception now names `MazeSkins` (packs as data) instead of `MazeWorlds`.

## 21.17 Tester checklist

Headless: S1 to S13 in the run, the diff of S1, `tools/check_levels.gd`; read the printed bake lines.

Shots, each at 100 %, as the 50 % copy and as the grey copy (`tools/shot_variants.gd`):

- Lip at a glance: in `temple`, `jungle-play`, `cave`, the three `skin-*-all` overviews and `skin-phone`, every ring
  face has a light trim with a dark line on both sides, and you find them without searching, also in grey and at 50 %;
  compare the trims with the level rows for l003, l006 and l009 (no trim towards spikes, `X`, the level edge or the
  bottom row).
- `X` reads as one smooth slab per run without a trim, also in grey; the seam to `#` is a thin dark line.
- Edges: floors straight; `skin-pillar` shows the pillar top at full width with square corners; `skin-towers` shows
  straight tower tops and only slightly crumbly walls; nothing of a block is drawn outside its tile (look at Lilith
  against walls and ceilings: never overlapping a block); no step or gap at cell or chunk borders.
- Stones: carved, light top and left, dark bottom and right; per world a recognisably different grouping and motif;
  quiet at 50 % and on the phone (B's risk: noise on 40 px tiles).
- Spikes: same size, shape and red in all worlds, now with a dark outline; nothing else in the world looks like a pin
  (motifs, chips, crystals).
- Rings and beads: white with a dark outline, clear on sand, moss and frost; Lilith's outline is visibly thinner than
  the block contour and she stands apart from the wall behind and next to her.
- Door: as before, with a contour; frame colour close to the old one.

Play in a desktop browser and on a phone (web export, `?fps`): l003 (land on the pillar, jump along the ledge edges),
l006 (stand on the tower tops, throw against tower walls), l009. Does any edge feel as if you stand on nothing or hit
something before you see it? Note bake ms, first frame ms and fps on l003, l006, l009, develop against the branch.

## 21.18 Open points for the owner

- Edge amplitudes per world: temple 2 px, jungle and cave 3 px on walls and ceilings, floors always straight. Higher is
  possible up to 3 px; above that the engine refuses.
- The inner corner joint lets the lip turn into a wall like a moulding; it can be dropped if it reads as a ring face.
- The door frame colour is now derived from the block colour (a little darker than today in all three worlds), so a
  world pack cannot choose it.
- Moss tufts on jungle floors stand up to 4 px above the floor line (18.20); they stay as they are.
- Studio (card #033): `validate`, `resolve` and `check_palette` are the gate; decor kinds per world (`MazeDecor`) are
  still keyed by world id and would move into the pack then.

## 21.19 Deviations as built

(Filled in by the developer in step 9.)
