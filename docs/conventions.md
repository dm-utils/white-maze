# Conventions

How code, tests, levels and branches are handled in this repository. The design is in `docs/design.md`. These
conventions follow White Sum's; differences are marked.

## Engine and layout

- Godot 4.7.2, GDScript only, pinned in `project.godot` and CI. Use the same version on every machine.
- Renderer: GL Compatibility. Web export single-threaded. Landscape (difference: the puzzle games are portrait).
- White Kit is a git submodule at `addons/white_kit`, pinned to a tagged release (CI checks the pin): `v0.3.0`. Clone
  with `--recurse-submodules`, or run `git submodule update --init` after a plain clone. Never edit files under
  `addons/white_kit` here; kit changes are requested in `dm-utils/white-kit` and arrive by updating the pin:

```bash
git -C addons/white_kit fetch --tags
git -C addons/white_kit checkout v<new>
git add addons/white_kit
# run the tests and the screenshot comparison, then commit: chore: update White Kit to v<new>
addons/white_kit/tools/shots.sh before-after . tools/shots.txt v<old> v<new>
```

| Folder | Content |
|---|---|
| `sim/` | Simulation, tuning, aim table, levels, run scripts, profile logic, time format. No scenes, nodes, input, rendering, time source, randomness or `user://`. |
| `ui/` | Main scene, level select, game screen, camera rig, world view, HUD, controls, touch overlay, overlays, profile file store, texts. Depends on `sim/` and the kit, never the other way round. |
| `levels/` | `index.json` and one `<id>.json` per level. |
| `tools/` | Headless scripts (`check_levels.gd`, `search_par.gd` with its calibration `check_search_par.sh`), the native solver in `tools/solver/` with `export_levels.gd`, `trace_sim.gd` and `check_solver.sh` (design 23.10.4), the screenshot scenario file `shots.txt` and `shot_variants.gd` (grey and half size copies of screenshots). |
| `tests/` | Headless test runner (extends `WhiteTestRunner`), suites, `solutions.json`. |
| `addons/white_kit/` | White Kit (submodule). |
| `build/` | Local output (exports, screenshots, the solver binary and its exported levels in `build/solver/`). Ignored by git. |

There is no `LICENSE` file: all rights reserved.

## GDScript style

- Godot style guide: tabs, `snake_case` functions and variables, `PascalCase` classes and enums, `UPPER_CASE`
  constants. Lines within 120 characters.
- Static typing everywhere.
- Internal members and functions start with `_`.
- Global classes have the prefix `Maze` (`MazeSim`, `MazeLevel`, `MazeLevels`, `MazeTuning`, `MazeAim`, `MazeInput`,
  `MazeRunScript`, `MazeProfile`, `MazeFormat`, `MazeMain`, `MazeLevelSelect`, `MazeGame`, `MazeWorldView`, `MazeHud`,
  `MazeCameraRig`, `MazeControls`, `MazeTouchOverlay`, `MazeOverlays`, `MazeProfileStore`, `MazeStrings`, `MazeLilith`,
  `MazePoseBlend`, `MazeArt`, `MazeWorlds`, `MazeDecor`, `MazeStaticLayer`, `MazeStaticBake`, `MazeSkin`,
  `MazeSkins`, `MazeTileShapes`, `MazeChain`, `MazeChainShapes`, `MazeChainView`, `MazeChainExport`,
  `MazeChainShare`, `MazeSlope`). Kit classes have the prefix `White`; do not declare `White*` names here. Test scripts
  declare no `class_name`.
- Documentation comments use `##`; ordinary comments `#`. Comments and identifiers in English.
- Player-facing texts live in `ui/strings.gd` (`MazeStrings.TEXT`, Dutch and English), registered through the kit;
  level names and hints live in the level files, also in both languages.
- Look values (colours, sizes, timings of effects) are constants at the top of the file that draws them; colours come
  from `WhiteTheme` where the theme has them. Exception: the palettes of the three worlds live together in
  `MazeSkins` (skin packs as data, validated by `MazeSkin`), not in the files that draw with them; the shared colours
  (hazard, ring, door light) stay in `MazeWorlds`.
- The look is derived, not stored: `MazeDecor` and the static layers use only `MazeArt.hash3` of the cell and a salt
  constant per rule, never a random generator, so a level looks the same on every run and machine. A new rule gets a
  new salt.
- No credentials, keys or personal data in the repository.

## Simulation rules

- `MazeSim.step` and `MazeSim.cast` use integers only: positions and velocities in units (1/1000 px), per tick. No
  `float`, no `cos`/`sin`/`atan2`, no `Time`, no `randi`/`randf`/`RandomNumberGenerator`.
- Every tuning value appears twice in `MazeTuning`: the readable value (`_PX` or `_S` suffix) and the integer. Change
  both; the tuning test checks them.
- Aim directions come only from the literal table `MazeAim.DIRS`. Converting a mouse or touch vector to an index is
  done in `ui/` (or in `MazeAim.index_from_vector`, which is never called by the simulation).
- The simulation never reads input devices; it gets one `MazeInput` per tick.
- A change of movement in `sim/sim.gd` or `sim/slope.gd` (or of the tuning values it uses) changes
  `tools/solver/maze_solver.cpp` in the same commit. `tools/check_solver.sh` compares both simulations tick for tick
  (levels of the index, the lab and the slope fixtures, seeded hold-only runs) and fails otherwise.
- A change of rules or tuning that changes how a level plays is checked with the solution tests and
  `tools/check_levels.gd`; if a stored solution no longer finishes, record a new one with `--print-run`.

## Coordinates and units

- `x` to the right, `y` downwards, `(0, 0)` top-left of the level; cell index `y * width + x`. Level rows are listed
  top first. (Difference: the grid puzzle games use `y` upwards.)
- A tile is 40 px = 40000 units. The player position is its bottom-centre (feet).
- Faces are named after the direction they point to: `UP` is the top face of a block (a floor).
- Time is counted in ticks (60 per second of game time); milliseconds or hundredths only for display.

## Levels

- One file per level, `levels/<id>.json`; ids `^[a-z0-9-]{1,32}$`, never reused or renamed once a level has shipped
  (statistics are keyed by id). The order lives only in `levels/index.json`.
- Rows in a monospace editor; the design (5.4) shows rows in blocks of 8 for review.
- A level with slope characters (`/ \ r R L l`) or the field `sky` is format 2 (design 23.4.3); format-1 levels never
  change meaning. The test series `levels/lab/` (opened with `--lab` or `?lab`, never written to the profile) is checked
  like the real series: `godot --headless --path . -s res://tools/check_levels.gd -- --dir=res://levels/lab`.
- `tests/inert_tests.gd` pins the per-tick state of every stored solution of l001 to l009 (design 23.15, R1). A change of
  the simulation that changes that hash changes how the ruins play; do it on purpose or not at all.
- After every level change:

```bash
godot --headless --path . -s res://tools/check_levels.gd
```

- Every level in the index has a solution in `tests/solutions.json` that finishes within par. Record one by playing:

```bash
godot --path . -- --level=<id> --print-run
```

## Profile

- `user://profile.json`, format in design 7.2. A change of a field's meaning raises `format` and adds a step to
  `MazeProfile.migrate`; adding a field does not (unknown keys are kept by older versions).
- Format 2 holds the chain record per level (design 22.9); a backfill from `best_run` runs once, in the migration from
  format 1 (`MazeProfile.backfill_chains`). The chain is a view and profile feature: `MazeSim` never changes for it.
- Every new field gets a merge rule in `MazeProfile.merge` and a test.
- Tests use files under `user://` with the prefix `white_maze_test_` and delete them afterwards.

## Tests

- Run headless; import first after a fresh clone or a new `class_name`:

```bash
godot --headless --path . --import
timeout 300 godot --headless --path . res://addons/white_kit/tests/run_kit_tests.tscn -- --min-checks=764
timeout 300 godot --headless --path . res://tests/run_tests.tscn -- --min-checks=<N>
godot --headless --path . -s res://tools/check_levels.gd
```

- `tests/run_tests.gd` extends `WhiteTestRunner`; CI's `MIN_CHECKS` equals the current check count; raise it when tests
  are added.
- `what` in `check(ok, what)` describes the expected behaviour in plain words.
- Simulation tests build small maps with `MazeLevel.from_dict` from row arrays in the test file, and drive the
  simulation with run scripts or `MazeInput` arrays; no scenes.
- UI is checked with headless scene tests and the screenshot scenarios in `tools/shots.txt`; screenshots are not
  committed.

## Git and CI

- `develop` is the working branch; `main` is protected and updated through pull requests only (once a remote exists).
- `.github/workflows/ci.yml` comes from the kit template (`addons/white_kit/templates/ci.yml`) plus the level check and
  the par search calibration and the native solver check (`tools/check_solver.sh`, needs `g++`); `develop` is deployed to GitHub Pages (`play.white-maze.steefbeest.nl`).
- Branch names: `feature/<description>`, `fix/<description>`, `chore/<description>`.
- Commit messages in English, imperative, short subject line.
- CI (or, without a remote, the same steps locally) must be green before merging. Do not commit build output.
