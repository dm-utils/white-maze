# White Maze - design section 18: look and feel of the adventure world (card #012)

This file is section 18 of `docs/design.md`; it is kept as a separate file because of its size and is referenced from
`docs/design.md` sections 8.1 and 18. Decision record: ADR 0010. Source of the direction: the designer's note
`docs/ideas/2026-11-21-look-and-feel.md` and its mockup A (not in git).

## 18.1 Owner decisions (2026-11-22)

1. Direction A, "Lost temple": a fully coloured adventure world. Worlds per three levels: levels 1-3 temple, 4-6
   jungle ruin, 7-9 cave.
2. Reading rules (18.5) hold in every world: a light lip on every face of a `#` block where a ring can go; `X` smooth
   and glossy without a lip; `^` always the same warm red hazard colour; `F` drawn as a doorway; beads and rings have a
   colour of their own (white) that decor never uses; decor only on the back wall or in empty cells, with low
   contrast; details derived from neighbouring cells with a deterministic hash of `(x, y)`.
3. No change to the level format, the simulation, the tuning or the rules. The HUD, the menus and the shared White Kit
   theme keep their look (18.11 lists the three small readability backings that are added).
4. The player character is **Lilith**: an original explorer in colour (skin, dark hair, jacket, trousers, boots), a
   red headband with two fluttering tails as her mark, a bandolier across the chest that shows the beads left, no
   weapons, drawn inside the 30 x 32 hitbox (the head never outside it). Nothing taken from existing characters: no
   braid, no pistols or holsters, no tank top with shorts, no hat, no whip.

## 18.2 Assumptions

| # | Assumption | Consequence if wrong |
|---|---|---|
| L1 | All art is drawn in code with `CanvasItem` draw calls (polygons, lines, circles, per-vertex colours). No image, font or shader assets are added (ADR 0010). | A later asset pipeline is an addition; nothing here depends on its absence. |
| L2 | The world is drawn at 1 world px = 1 viewport unit (viewport 1280 x 720, stretch `canvas_items`, design 10.2). On a phone in landscape Lilith is 20 to 40 screen px high. | Sizes in 18.6 and 18.8 are tuned for this; a camera zoom would need a review. |
| L3 | GL Compatibility (WebGL 2 on the web) draws a few thousand cached canvas commands per frame at 60 fps on a mid-range phone. | Fallback in 18.10 (bake static chunks with a one-shot `SubViewport`). |
| L4 | The game screen knows the level's position in the series (`MazeGame.number`, 1-based, from `levels/index.json`). | World selection (18.3) needs another source. |
| L5 | Animations may read the simulation's tick, state and events, but never feed anything back (events stay one-way, design 3.9). | None. |
| L6 | Chunk `draw` signals fire in the headless test runner (the scene tree dispatches `NOTIFICATION_DRAW` with the dummy renderer). | A6 counts `build()` calls instead of draws. |

## 18.3 World per level: derived from the series position

```gdscript
class_name MazeWorlds extends RefCounted   # ui/worlds.gd, pure, no nodes
enum World { TEMPLE, JUNGLE, CAVE }
const COUNT := 3
const LEVELS_PER_WORLD := 3
static func for_number(number: int) -> int     # clampi((number - 1) / LEVELS_PER_WORLD, 0, COUNT - 1)
static func from_name(name: String) -> int     # "temple" | "jungle" | "cave", else -1 (debug argument)
static func palette(world: int) -> Dictionary  # 18.4; an unknown world gives the temple palette
```

- `MazeGame` sets `world.world_id = MazeWorlds.for_number(number)`, or the value of the debug argument `--world=<name>`
  when it names a world (addition to 10.4, view only; `MazeMain.parse_args` gets the key `world`, default `""`).
- Levels after the ninth stay in the last world (`clampi`) until more worlds exist; phase 2 extends the table.
- No level field. ADR 0010 gives the reasons (owner: no level format change; groups of three are a series property,
  not a level property; reordering the index moves a level into the world of its new group, which is what a designer
  wants).

## 18.4 Palettes

All colours are constants in `MazeWorlds` (shared constants plus one Dictionary per world with the keys below).
Lilith's colours are in `MazeLilith` and the same in every world. Values are start values; changing them is allowed
when the palette tests (18.12, A3) stay green.

Shared:

| Constant | Value | Use |
|---|---|---|
| `HAZARD` | `#D24A3A` | Spike fill (hue about 6 degrees), every world. |
| `HAZARD_HI` | `#F39A7E` | Spike highlight edge. |
| `HAZARD_DARK` | `#8E2A22` | Spike base shadow. |
| `RING` | `#FFFFFF` | Rings, beads, the bead in Lilith's hand, filled bandolier slots. Reserved: no other colour may be near white (A3). |
| `DOOR_LIGHT` | `#FFE7B0` | Light in the doorway (18.8). |

Per world:

| Key | Temple | Jungle ruin | Cave | Use |
|---|---|---|---|---|
| `void` | `#140F18` | `#0C1410` | `#0A0F17` | Everything outside the level rectangle. |
| `back_top` | `#2A2030` | `#1A2A22` | `#172234` | Back wall gradient, top of the level. |
| `back_bottom` | `#17121C` | `#0F1A15` | `#0D1420` | Back wall gradient, bottom of the level. |
| `back_line` | `#33283B` | `#20332A` | `#1C2A3D` | Masonry or strata lines of the back wall. |
| `back_decor` | `#3A2D45` | `#284A2E` | `#22344A` | Large decor silhouettes (pillars, arches, vines, crystals). |
| `block` | `#C29A62` | `#6E7D62` | `#5A6A82` | `#` fill (sandstone, mossy stone, blue-grey rock). |
| `joint` | `#9A7442` | `#556349` | `#44526A` | Joints and cracks inside `#` (always darker than `block`). |
| `speck` | `#A7804C` | `#617055` | `#4E5D74` | Small dots inside `#`. |
| `lip` | `#F3E0AE` | `#9BD36A` | `#B9CCE0` | Lip on ring faces (light sand, moss, frost). |
| `noring` | `#3F4260` | `#34504C` | `#2E5B7A` | `X` fill (polished basalt, wet stone, deep ice). |
| `noring_edge` | `#2A2C42` | `#243833` | `#1F3F56` | 2 px inner border of `X` (darker than the fill, never light). |
| `sheen` | `#8A90B8` | `#7FB8B0` | `#CFEFFF` | Gloss streaks on `X`. |
| `detail` | `#D9B77B` | `#86C25E` | `#3A6EA5` | Sand drifts, moss tufts, faint cave glow spots. |
| `light` | `#FFB45A` | `#FFB45A` | `#7FC8E8` | Torch flame (temple, jungle), glow crystal (cave). |
| `door_frame` | `#D9B77B` | `#8C9A7A` | `#7D8CA4` | Door posts and lintel. |

## 18.5 Reading rules as code

`MazeArt` (`ui/art.gd`, pure static functions, no nodes):

```gdscript
class_name MazeArt extends RefCounted
static func hash3(x: int, y: int, salt: int) -> int
static func pick(x: int, y: int, salt: int, n: int) -> int         # hash3(...) % n
static func chance(x: int, y: int, salt: int, percent: int) -> bool # hash3(...) % 100 < percent
static func lip_face(level: MazeLevel, cell: Vector2i, face: int) -> bool
static func luminance(c: Color) -> float                           # WCAG relative luminance, linearised sRGB
static func contrast(a: Color, b: Color) -> float                  # (L1 + 0.05) / (L2 + 0.05), L1 >= L2
```

- `hash3`, integers only, so the result is the same on every platform:

  ```gdscript
  var h := (x * 374761393 + y * 668265263 + salt * 2147483647) & 0xFFFFFFFF
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
  return h ^ (h >> 16)
  ```

  Salts are named constants in the file that uses them (`SALT_CRACK := 1`, `SALT_VINE := 2`, ...); every rule has its
  own salt so rules do not correlate.
- `lip_face` is true exactly when a ring may be placed on that face, apart from "taken" and range (design 3.10 step 6):
  the cell is `#` (`Cell.SOLID`, inside the grid), the cell in front of the face is not solid and is not a spike.
  Faces towards a spike, towards another block or towards the out-of-bounds sides get no lip. (Change from 8.1: the old
  edge highlight was drawn on every exposed face, also in front of spikes.)
- `X` gets no lip on any face, a 2 px `noring_edge` inner border and two to three diagonal `sheen` streaks (3 px,
  alpha 0.5, positions from `pick`), so "smooth, so nothing sticks" reads without the hatching of 8.1.
- `^` is drawn the same in every world: two triangles per tile as in 8.1 in `HAZARD`, a 2 px `HAZARD_HI` line on the
  lit side, a 3 px `HAZARD_DARK` base. Only the outline varies a little per world (temple: spear points; jungle:
  slightly curved thorns; cave: crystal points), never the colour and never the area it covers.
- White (`RING`) is used only for rings, beads, the bead in Lilith's hand and the filled bandolier slots. The aim line
  keeps `WhiteTheme.TEXT`.

## 18.6 Lilith

### 18.6.1 Figure

Local coordinates: origin at the feet centre (the simulation's `px, py`), `y` up is negative, facing right; the view
mirrors with `draw_set_transform(pos, 0, Vector2(facing, 1))`. Sizes in px at a hitbox of 30 x 32.

| Part | Shape (idle pose) | Colour |
|---|---|---|
| Head | circle centre `(1, -25.5)`, r 6 | skin `#D9A07A` |
| Hair | short bob polygon over the back and top of the head, top at `y = -32.0`, down to the jaw (`y = -22`) | `#3A2418` |
| Eye | circle `(4.2, -25.5)`, r 0.9 | `#1E1A18` |
| Headband | 2 px band across the head at `y = -28.5` | `#DC3150` (crimson, hue about 349 degrees; deliberately not the hazard hue) |
| Headband tails | two chains of 3 points from the knot at `(-5, -28.5)`, lengths 7 and 6 px, 2.2 px wide | `#DC3150` |
| Jacket (torso) | rounded rectangle `(-8, -21)` to `(8, -11.5)`, radius 3 | `#2F7F86`, shadow `#24646A` |
| Bandolier | 2.4 px strap from `(-6, -21)` to `(6, -12.5)` | `#3A2A1E` |
| Bead slots | up to 4 slots evenly on the strap, r 1.8 | filled `RING`, empty `#1E1612` |
| Belt and satchel | 1.8 px belt at `y = -12.5`; satchel `(-12, -16)` 6 x 7, radius 1.5 | `#3A2A1E`, `#6B4A2B` |
| Trousers | two legs, 4 px wide lines from the hips `(+-3, -11.5)` to the knees and boot tops | `#5A5F40` |
| Boots | rounded rectangles 7 x 5 at the feet | `#2B2420` |
| Arms | 3 px lines from the shoulder `(2, -19)`, hand a circle r 1.4 | jacket colour, hand skin |
| Outline | every shape first drawn in `#120E10` (alpha 0.85) 1.5 px larger (lines +3 px width, circles +1.5 r, polygons as closed 3 px polylines) | a clean silhouette on light sand and on dark walls |

- The bandolier shows `mini(level.beads, 4)` slots; the first `mini(beads_left, 4)` are filled. The HUD stays the
  authoritative count (levels with more than four beads show only four slots).
- Bounds (tested, A2): for every pose except `DEAD`, every point of every shape except the headband tails lies inside
  `x in [-15, 15]`, `y in [-32, 0]` (circles: centre +- radius; lines: endpoints +- half the width). The tails may reach
  `x in [-19, 15]`, `y in [-34, 0]` (behind and slightly above, never in front of the face).

### 18.6.2 Poses and animation

`MazeLilith` (`ui/lilith.gd`, pure, no nodes) separates the choice of pose from the drawing so both are testable:

```gdscript
class_name MazeLilith extends RefCounted
enum Body { IDLE, RUN, JUMP, LAUNCH, FALL, DEAD }
enum Arm { REST, AIM, THROW, UP }
const RUN_MIN_VX := 500      # units per tick (30 px/s): below this a grounded player stands
const STRIDE_PX := 28.0      # one run cycle per 28 px travelled
const LAND_TICKS := 6
const THROW_TICKS := 10
const DEAD_TILT_TICKS := 12
static func body_pose(alive: bool, grounded: bool, vx: int, vy: int, launched: bool) -> int
static func arm_mode(aiming: bool, ticks_since_throw: int, body: int) -> int
static func shapes(p: Dictionary) -> Array[Dictionary]
	# p: body, arm, phase (0..1), tick, aim_angle (radians, local frame), throw_k (0..1), squash_k (0..1),
	#    dead_k (0..1), vel (Vector2, px/s, local frame), slots (0..4), filled (0..4)
	# returns [{"type": "circle"|"poly"|"line", "part": "head"|"hair"|"band"|"tail"|"body"|"arm"|"leg"|"bead",
	#           "c": Vector2, "r": float, "pts": PackedVector2Array, "w": float, "color": Color}], in draw order
```

`body_pose`: not alive -> `DEAD`; not grounded and `vy < 0` -> `LAUNCH` when `launched`, else `JUMP`; not grounded and
`vy >= 0` -> `FALL`; grounded and `abs(vx) >= RUN_MIN_VX` -> `RUN`; else `IDLE`.

`arm_mode`: `DEAD` -> `REST`; aiming -> `AIM`; `ticks_since_throw < THROW_TICKS` -> `THROW`; `LAUNCH` -> `UP`; else
`REST`.

| Animation | Source | Look |
|---|---|---|
| idle | `IDLE`, `tick` | Torso and head bob 0.6 px on a 120-tick sine; tails hang down and back. |
| run | `RUN`, `phase = fposmod(x_px / STRIDE_PX, 1)` from the interpolated `x` | Legs swing `+-6` px, the lifted foot up to 3 px; body dips 1 px twice per cycle; arms swing opposite. Stateless, so a screenshot of a frozen position always looks the same. |
| jump | `JUMP` | One knee up, arms slightly back. |
| launched | `LAUNCH`, arm `UP` | Both arms up, body tilted up to 8 degrees towards the velocity around `(0, -16)`. |
| fall | `FALL` | Legs apart and straight, arms out, hair tips up. |
| throw | arm `THROW`, `throw_k = ticks_since_throw / THROW_TICKS` | The arm swings from behind the shoulder to the throw direction (from the newest flight's `from` to `to`); the hand is empty, the slot on the band is already empty because `beads_left` dropped at the throw tick. |
| aim | arm `AIM`, `aim_angle` from `MazeAim.dir(aim_index)` | The arm points along the aim, a `RING` bead (r 1.9 with a 3.5 r halo at alpha 0.25) in the hand. Lilith faces the aim side (view only; `sim.facing` is not touched). |
| land | `squash_k = 1 - ticks_since_land / LAND_TICKS` while above 0 and grounded | Scale around the feet: `y` by `1 - 0.12 * squash_k`, `x` by `1 + 0.06 * squash_k`. |
| dead | `DEAD`, `dead_k = 1 - dead_ticks / DEATH_TICKS` | Tilts backwards up to 70 degrees around the feet over the first 12 ticks, tails droop, alpha `1 - dead_k` (the fade of 8.1). Respawn fades in over 10 ticks as before. |

- Headband tails are stateless: their direction is the opposite of `vel` when `vel.length() > 50` px/s, else down and
  back `(-0.6, 0.8)`; length grows with speed up to the values of 18.6.1; each point flutters by `1.2 * min(1, speed /
  300) * sin(tick * 0.35 + i)` px. They are clamped to the tail bounds of 18.6.1.
- Velocities for the look come from `sim.vx`, `sim.vy` (units per tick) times `60 / 1000`.
- All timing comes from `sim.tick` and the event ticks the view stores (`land`, `throw`, `death`, `respawn`), so slow
  motion slows the animation down with the game, and a frozen `--shot` is reproducible.

## 18.7 World view structure and draw order

`MazeWorldView` stays the coordinator with its public API (`sim`, `alpha`, `aim_index`, `notify_events`, `reset`,
`player_centre`, `face_point`, `ring_points`); new: `world_id: int` and `build()` (called by `MazeGame` after `sim` and
`world_id` are set; a restart of the same level with the same world does not call it again).

```
World (Node2D, MazeWorldView)        dynamic layer: own _draw, every frame (queue_redraw)
  Back (Node2D, MazeStaticLayer)     z_index -2: void, back wall gradient, masonry/strata lines, back decor, door glow
  Tiles (Node2D, MazeStaticLayer)    z_index -1: blocks, joints, specks, cracks, lips, X with sheen, spikes, door
  Camera2D
```

- `MazeStaticLayer` (`ui/static_layer.gd`) splits the level into chunks of 16 x 16 tiles. Each chunk is a child
  `Node2D` whose `draw` signal draws only its cells (plus decor items anchored in them). Chunks are drawn once after
  `build()` and never redrawn while the level is open, so per frame only cached commands are submitted, and Godot culls
  whole chunks outside the camera. `build()` frees and recreates the chunks.
- The dynamic layer (`MazeWorldView._draw`) draws, in this order: rings (with glow, 18.9), beads in flight, Lilith, the
  aim preview. The grid lines of 8.1 are dropped; the masonry of the back wall follows the 40 px tile rhythm instead.
- The `void` colour covers the level rectangle plus 2000 px on every side, so centred small levels have no `BG` border.
- `world.modulate` dimming while aiming (4.4) applies to all children as before.
- A counter `static_draws` (incremented by every chunk draw) exists for the tests (A6).

## 18.8 Tiles, door and details

Tiles layer per cell (`T = 40`):

- `#`: fill `block`; joints per world, always `joint` 2 px lines that stay out of the outer 5 px band where a lip can
  be: temple running bond (two courses of 20 px per tile, vertical joints at 0 and 20 alternating per course); jungle
  one stone per tile with a vertical joint at `pick(x, y, SALT_JOINT, 3) * 8 + 8`; cave no bricks, one crack polyline
  of 3 points when `chance(x, y, SALT_CRACK, 30)`. One or two `speck` dots (r 1.5) per tile at hashed positions.
- Lips: for every face with `lip_face`: a 5 px strip in `lip` along that face inside the cell, with the corner filled
  where two lip strips meet. Jungle: on `UP` lip faces, moss tufts (3 to 5 blades, up to 4 px high, colour `lip`) in
  the cell above when `chance(x, y, SALT_TUFT, 50)`.
- `X` and `^`: 18.5.
- `F` (door): posts 5 px wide at both sides of the cell and a 6 px lintel at the top, in `door_frame`; the opening
  (30 x 34 px) is a vertical gradient polygon from `DOOR_LIGHT` alpha 0.9 at the bottom to alpha 0.15 at the top; on
  the back layer two glow circles (r 34 and 22, `DOOR_LIGHT` alpha 0.06 and 0.08) centred in the cell. The door stays
  inside the `F` cell, so it never covers a lip.

Back layer: `void` rectangle, vertical gradient over the level rectangle (`back_top` to `back_bottom`, one polygon with
vertex colours), masonry or strata lines in `back_line`, then the back items of the decor plan.

Decor plan (`MazeDecor`, `ui/decor.gd`, pure):

```gdscript
class_name MazeDecor extends RefCounted
static func plan(level: MazeLevel, world: int) -> Array[Dictionary]
	# [{"kind": String, "cell": Vector2i, "size": int, "variant": int, "layer": "back" | "tiles"}], sorted by (y, x, kind)
```

| Kind | Worlds | Layer | Rule (chances via `MazeArt.chance` with the kind's own salt) |
|---|---|---|---|
| `pillar` | temple | back | Column `x` with `pick(x, 0, SALT_PILLAR, 7) == 0`: every vertical run of at least 4 non-solid cells with a solid cell above and below gets a pillar silhouette (`back_decor`, 24 px wide) over the run; `size` = run length. |
| `relief` | temple | back | A sun disc (two circles and 8 rays, 3 px lines, `back_decor`) centred in an empty 3 x 3 area without spikes, chance 9, at most one per 12 columns. |
| `torch` | temple, jungle | back | Empty cell with no solid 4-neighbour, the cell below empty and the cell two below solid; chance 12; at least 6 columns from the previous torch. Holder in `back_decor`, flame 8 x 14 in `light`, glow circles r 60/40/24 at alpha 0.05/0.06/0.08 in `light`. |
| `sand` | temple | back | Empty cell with a solid cell below and a solid cell left or right (inner corner): a wedge of at most 16 x 8 px against that wall, `detail`, chance 60. |
| `arch` | jungle | back | Broken arch outline (4 px, `back_decor`) over an empty 4 x 3 area, chance 8, at most one per 12 columns. |
| `vine` | jungle | back | Empty cell with a solid cell above, chance 25: a vine of `1 + pick(x, y, SALT_VINE_LEN, 3)` cells down, stopping before the first non-empty cell, 3 px `back_decor` with leaf ellipses. |
| `glow` | cave | back | Empty cell with at least 2 empty cells below it before a floor and an empty cell above it, chance 6: a blunt crystal cluster (hexagonal prisms with flat tops, `back_decor`) with a faint `light` glow (alpha 0.08). |
| `spot` | cave | back | Empty cell, chance 5: soft `detail` circle r 16 at alpha 0.15. |
| `crack` | all | tiles | `#` cell whose four neighbours are solid, chance 25: a 2 px `joint` polyline. |

Constraints on every plan (tested, A5):

- D1 `back` items lie only in `EMPTY` cells, never in the `S` or `F` cell or in the 8 cells around `F`.
- D2 No `back` item in a spike cell or in the cell directly above a spike.
- D3 `torch` and `glow` items have no solid 4-neighbour (no light next to a ring face).
- D4 `sand` only in empty cells with a solid cell below; `vine` starts in an empty cell with a solid cell above and
  covers only empty cells.
- D5 `tiles` items lie only in `#` cells.
- D6 The plan depends only on the level's cells and the world: two calls give equal arrays, and the level's `render()`
  is unchanged afterwards.
- D7 Calm: at most 8 `back` items per 100 empty cells of a level.
- D8 No stalactites or other pointed shapes hanging down or standing up in back decor (review item for the tester:
  nothing may look like a spike or a ledge).

## 18.9 Rings and beads

- Ring: the ellipse of 8.1, drawn three times on the same points: width 17 at alpha 0.08, width 11 at alpha 0.18, then
  width 5 opaque in `RING` (or `WhiteTheme.ACCENT` during the launch flash). Arrow unchanged.
- Bead in flight: halo circle r 11 at alpha 0.2, then r 7 opaque `RING`.
- The aim preview keeps 4.5 (dots in `TEXT`, `DIM` with a cross when invalid).

## 18.10 Performance on the web export

- No shaders, no `WorldEnvironment` glow, no textures, no particles, no full-screen alpha layers other than the HUD
  scrim of 18.11. Glow is a few translucent shapes.
- Static layers are cached (18.7); per frame the dynamic layer submits about 60 commands for Lilith (shapes plus
  outlines), 3 per ring, 2 per bead and the aim dots.
- Budget: 60 fps in a desktop browser on every level; at least 50 fps on a mid-range phone in landscape (tester, web
  export). A debug argument `--fps` shows `Engine.get_frames_per_second()` in a small `DIM` label under the HUD band
  (view only; `parse_args` key `fps`, default `false`).
- Fallback if the phone stays below 50 fps: render each static chunk once into a `SubViewport` with
  `render_target_update_mode = UPDATE_ONCE` and draw its texture (ADR 0010). Not built unless needed.

## 18.11 Readability on a phone

- Every rule of 18.5 is carried by shape and luminance, not by hue alone: lips are lighter than their block, `X` has no
  lip and a different texture, spikes are triangles with a dark base, the door is a lit opening.
- HUD scrim: `WhiteTheme.BG` at alpha 0.55 over the HUD band (110 px plus the safe area top) with a 24 px fade at its
  lower edge, drawn as the first child of the HUD canvas layer. HUD content, layout, fonts and colours are unchanged.
- Hint backing: the hint label gets a `StyleBoxFlat` of `BG` at alpha 0.7, radius 8, 12 px horizontal padding.
- Touch controls: each control gets a disc of `BG` at alpha 0.35 under its existing faint circle, so the sticks stay
  visible over light blocks.
- These three backings are the only changes to HUD and overlay files; the level select, pause and result overlays are
  unchanged apart from the name in the subtitle (18.13).

## 18.12 Acceptance (look and feel)

- A1 Simulation untouched: `git diff <base> -- sim/ levels/ tests/solutions.json` is empty for every step; all existing
  checks stay green (`MIN_CHECKS` only goes up); `tools/check_levels.gd` exits 0. A test plays the l001 solution
  through `MazeGame.advance` with the new view and compares `sim.snapshot()` with `MazeRunScript.run` on the same
  script: equal.
- A2 Lilith bounds (18.6.1) for every `Body` except `DEAD`, every `Arm`, `phase` 0 to 1 in steps of 0.05, `tick` 0 to
  119, `aim_angle` for all 144 directions, `squash_k` 0 and 1, `vel` with each axis in `{0, +-300, +-1080}`, `slots`
  0 to 4.
- A3 Palettes, for each world: `contrast(lip, block) >= 1.8`; `contrast(noring, back_top) >= 1.5` and the same against
  `back_bottom`; `contrast(HAZARD, back_top) >= 3` and the same against `back_bottom`; `luminance(joint) <
  luminance(block) < luminance(lip)`; `luminance(noring_edge) < luminance(noring)`; `back_decor` and `back_line` have
  `contrast <= 1.6` against both back colours; no palette colour other than `RING` and `DOOR_LIGHT` is near white (HSV
  saturation `>= 0.2` or value `<= 0.8`); no palette colour other than the three hazard colours has a hue within 15
  degrees of `HAZARD` with saturation `> 0.4` and value `> 0.45`; Lilith's headband hue is at least 15 degrees from
  `HAZARD`.
- A4 `lip_face` on a fixture map: lips exactly on the faces that 3.10 step 6 accepts (a `#` next to empty: lip; next to
  a spike, a block or the out-of-bounds side: none; `X`: never); on every shipped level the lip faces equal the faces
  for which that rule holds.
- A5 `MazeDecor.plan` meets D1 to D7 for every shipped level in every world (27 combinations) and for a 64 x 64 fixture
  of random cells seeded with `WhiteRng`; `hash3` returns four pinned values in the test (computed once and pasted,
  like `MazeAim.DIRS`), and `pick(x, y, s, 4)` over the 672 cells of l001 gives each value between 15 % and 35 %.
- A6 Static layers: after `build()` and 120 frames of `MazeGame.advance(1/60)` with input, `static_draws` equals the
  number of chunks (each drawn once); a restart of the same level does not rebuild.
- A7 Pose table: `body_pose` and `arm_mode` give the values of 18.6.2 for at least 12 hand-picked cases, among them
  spawn (IDLE), running right (RUN), after a jump press (JUMP), after a floor ring launch (LAUNCH, arm UP), falling
  (FALL), dead (DEAD, REST), aiming while running (RUN, AIM), 5 ticks after a throw (THROW).
- A8 Worlds: `for_number` gives TEMPLE for 1-3, JUNGLE for 4-6, CAVE for 7-10; `--world=jungle` on l001 gives the
  jungle palette; an unknown name is ignored.
- A9 Screenshots (`tools/shots.txt`, 18.14) are produced without errors and reviewed by the tester (18.15).
- A10 Web export within the budget of 18.10.

## 18.13 Where the name Lilith appears

- In the game: the level select subtitle starts with a tagline in the same `DIM` line, so no extra row is needed and
  the nine cards still fit at 1280 x 720: `"%s  ·  %s  ·  %s" % [t("tagline"), levels_done, play_time]`. New text key
  `tagline`: nl `Een avontuur met Lilith`, en `An adventure with Lilith`. The title stays `WHITE MAZE`.
- In the README (short description of the game) and in the promo site text (outside this repository; the project lead
  proposes it to the owner).
- Not in the HUD, the hints or the result overlay.
- `icon.svg` stays as it is in these steps; a Lilith icon is an open point (18.16).

## 18.14 Screenshot scenarios added to `tools/shots.txt`

`shots.sh` splits the arguments on spaces, so every `--keys` script in this file is a single token.

```
lilith-idle 1280x720 --level=l001
lilith-run 1280x720 --level=l001 --keys=R30
lilith-jump 1280x720 --level=l001 --keys=RJ20
lilith-fall 1280x720 --level=l001 --keys=RJ45
lilith-aim 1280x720 --level=l002 --keys=-1 --aim=30
lilith-dead 1280x720 --level=l001 --keys=R<n>
door 1280x720 --level=l005
temple 1280x720 --level=l003
jungle 1280x720 --level=l005 --solve
cave 1280x720 --level=l009
jungle-on-l001 1280x720 --level=l001 --world=jungle
cave-on-l001 1280x720 --level=l001 --world=cave
phone-small 960x432 --level=l007 --touch --safe=40,0,40,16
```

- `lilith-dead`: the developer picks `<n>` so that Lilith walks into the spike pit of l001 and the shot is taken about
  8 ticks after the death, and writes the number into the file. `lilith-fall` likewise may change its count so that
  the shot shows a fall.
- `door` and `jungle`: l005 is 32 x 18 tiles and fits the screen, so its door is in view; `jungle` with `--solve` shows
  the result overlay over the jungle world (the overlay must stay readable).
- The existing scenarios stay.

## 18.15 Developer steps (card #013 and following)

Each step is one branch (`feature/look-<step>`), merged after its tests are green and the tester has reviewed it.
Every step keeps A1.

**Step 1: Lilith and the door (in the current grey world).**

- Build `ui/lilith.gd` (`MazeLilith`: poses, shapes, outlines, bandolier, tails) and use it in `MazeWorldView` instead
  of the white square; the view stores the ticks of `land`, `throw`, `death`, `respawn` from `notify_events`.
- The finish becomes the door of 18.8 with `door_frame = WhiteTheme.BUTTON["pressed"]` and `DOOR_LIGHT`.
- Name: `tagline` text and the level select subtitle (18.13); README line.
- Tests: new suite `tests/art_tests.gd` (added to `SUITES`) with A2, A7 and the snapshot check of A1; `ui_tests.gd`
  adjusted only where it reads the subtitle text.
- Shots: the `lilith-*` and `door` scenarios.
- Acceptance: A1, A2, A7; all shots produced; nine cards fit without scrolling at 1280 x 720.
- Tester: A1 (diff and the full suite), A2 and A7 in the run; review the `lilith-*` shots at 100 % and scaled to 50 %:
  pose recognisable, headband tails visible, bandolier slots match the HUD dots, head never above the hitbox (jump
  under a ceiling in l003 by eye), nothing weapon-like or copied; play l001 to l003 in a desktop browser and on a
  phone if possible.

**Step 2: worlds, tiles, lips, gloss and hazard colour.**

- Build `ui/art.gd` (`MazeArt`), `ui/worlds.gd` (`MazeWorlds`) and `ui/static_layer.gd` (`MazeStaticLayer`, chunks);
  `MazeWorldView` gets `world_id` and `build()`; `MazeGame` sets the world from `number` or `--world`.
- Tiles: block fill and joints per world, lips by `lip_face`, `X` with border and sheen, spikes in the hazard colours,
  the door in the world's `door_frame`, back wall gradient and lines, `void`; ring and bead glow (18.9); the three
  readability backings (18.11); `--fps`.
- Tests: A3, A4, A6, A8 in `art_tests.gd`.
- Shots: `temple`, `jungle`, `cave`, `jungle-on-l001`, `cave-on-l001`, `phone-small`; the existing ones now show the
  new look.
- Acceptance: A1, A3, A4, A6, A8; shots produced; desktop browser 60 fps on l001 and l009.
- Tester: A1; review every world shot against the reading rules: every ring face has a lip and no other face has one
  (compare with the level rows for at least l003, l005 and l009), `X` reads as smooth, spikes have the same colour in
  all three worlds, white only on rings, beads and bandolier; a greyscale copy of each world shot still shows lips,
  `X`, spikes and the door; the 50 % copy and `phone-small` still show every ring face; HUD text, hint and result
  overlay readable over the temple ceiling and in `jungle`; frame rate with `--fps` in the web export (desktop, phone
  if possible).

**Step 3: details and back decor.**

- Build `ui/decor.gd` (`MazeDecor.plan`) and draw its items in the static layers: tufts, cracks, specks and the back
  decor of 18.8.
- Tests: A5 in `art_tests.gd`.
- Acceptance: A1, A5, A6 still green; shots produced; 60 fps desktop and the phone budget of 18.10.
- Tester: A1; review the world shots against D8 (nothing looks like a spike or a ledge, decor stays quiet behind the
  level); compare each world shot with the one of step 2 (lips and spikes are still the first thing you see); two runs
  of the shots give identical images (`shots.sh compare`); phone check on the web export.

**Step 4: documentation and close.** Record deviations as built (as sections 14 and 16 do), raise `MIN_CHECKS`,
update `docs/conventions.md` (class list `MazeLilith`, `MazeArt`, `MazeWorlds`, `MazeDecor`, `MazeStaticLayer`;
palettes live in `MazeWorlds`, an exception to "look values at the top of the file that draws them") and design 10.1,
10.4, 10.5 and 11.2.

## 18.16 Open points for the owner

- Tagline wording (18.13), and whether the name should also appear on the icon (`icon.svg`, a Lilith head with the
  red headband).
- Headband colour: crimson `#DC3150`, kept apart from the warm hazard red on purpose; a plain warm red would read as
  danger on the figure.
- The three readability backings (18.11) are small additions to HUD, hint and touch controls; without them white text
  is hard to read over the light temple ceiling.
- Levels 10 and later stay in the cave until a fourth world is designed (phase 2).
- Torches and the door glow are the only light sources, without flicker (calm rule). Flicker or parallax can be tried
  after the phone check.

## 18.17 Deviations as built, step 1 (card #013)

- `MazeLilith.shapes` returns the outlines first (`part` `"outline"`, polygons as `"loop"` polylines) and then the
  fills; `bead` halos and bandolier `slot` circles get no outline. The bounds test (A2) checks the fills only, because
  the outline is 1.5 px larger on purpose.
- `shapes` takes one extra key `fade` (alpha factor, respawn fade-in and death fade); `dead_k` only drives the tilt.
- Upper body offsets (idle bob, run dip) only move downwards, hair top at `y = -31.8`, so the head stays below `-32`
  with the tilt. In `LAUNCH` only the upper body tilts around `(0, -16)`; tilting the legs would put the boots below
  the floor line (`y > 0`).
- The aim and throw arm is 7 px long with the bead 1.5 px beyond the hand, so the 3.5 px halo stays inside the hitbox
  at full squash. The far arm and far leg are drawn in darker colours.
- Tail points are clamped to the tail bounds shrunk by half the line width, so the bounds hold for the drawn width.
- `_throw_dir` and the view-only facing (`_face`) live in `MazeWorldView`; the facing follows the aim, then the throw,
  then `sim.facing`.
- The door constants (`DOOR_FRAME`, `DOOR_LIGHT`, sizes) sit at the top of `ui/world_view.gd` until `MazeWorlds`
  exists (step 2); the door glow is drawn in the dynamic layer, since there is no back layer yet. The grid lines and
  the old block edges stay as they are in step 1.
- `lilith-fall` uses `RJ28` and `lilith-dead` uses `R109` (death at tick 101, the shot 8 ticks later).
- The A1 test (`tests/art_tests.gd`) awaits no frame during the run: frames awaited mid-run made the game screen
  diverge from the plain run in the headless runner; the frame is awaited once after the run.
