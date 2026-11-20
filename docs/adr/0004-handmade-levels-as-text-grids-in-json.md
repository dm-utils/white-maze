# 0004 Handmade levels as text grids in JSON files

Status: accepted (2026-11-20)

## Context

The levels of a platformer are made by hand, unlike the generated puzzles of the other White games. Phase 1 needs three
grey-block levels; later 15 to 30. The simulation works on a tile grid (ADR 0002) and must load levels headless in
tests and in a check tool. Statistics are stored per level and must survive a change of the level order.

## Decision

- One JSON file per level in `levels/<id>.json` with metadata (`id`, names in Dutch and English, difficulty, beads,
  par, optional hint, preset rings) and the map as `rows`: strings of tile characters, top row first
  (`.` empty, `#` block, `X` no-ring block, `^` spike, `S` start, `F` finish).
- `levels/index.json` lists the ids in series order. Statistics are keyed by the stable `id`, never by position.
- Rows grow downwards (`y` down), matching Godot's screen coordinates; this differs from the grid puzzle games (`y` up)
  and is stated in the conventions.
- Levels are validated on load (one English error text per problem) and by `tools/check_levels.gd`, which also
  replays the stored solution of each level. A solution test in CI keeps every level finishable within par.

## Alternatives considered

- **Godot scenes with a `TileMapLayer`**: a visual editor for free, but levels become binary-ish `.tscn` files that
  diff poorly, loading needs scene instancing, and the simulation would need a converter anyway. Considered for a
  later editor that exports to this format. Rejected for phase 1.
- **External editors (Tiled, LDtk)**: good tools, but an extra dependency and import code for a handful of grey-block
  levels. Rejected.
- **Plain `.txt` files**: slightly nicer to edit, but not exported by Godot without extra filters and no place for
  structured metadata. Rejected.
- **One file with all levels**: fewer files, but every edit touches the same file and diffs get noisy. Rejected.

## Consequences

- Levels are reviewable in a diff and can be written in any editor; a monospace font is enough to see the shape.
- Precision placement (rings on faces) is written as coordinates, which is less visual; the check tool and the
  `--level` debug start make the loop short.
- A visual editor remains possible later as an exporter to this format.
