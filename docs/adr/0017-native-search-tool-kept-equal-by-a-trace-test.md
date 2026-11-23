# 0017 A native search tool in `tools/`, kept equal to the simulation by a trace test

Status: accepted (2026-11-23). Design: `docs/design-roofs.md` (section 23.10.4). Card #011.

## Context

Par is the number of rings of the designer's route, and a level should have no cheaper route. The evidence comes from
searching the simulation: `tools/search_par.gd` pre-places rings and searches for a finish. In GDScript it manages about
2000 nodes per second; for #007 the tester wrote a throw-away C++ port of the movement part of the simulation in a
scratch folder, validated it tick for tick against Godot, and found it about 500 times faster (l005 in 0.7 s instead of
2.6 minutes). That port is not in the repository. Twelve new levels with slopes need the same evidence, and the
simulation now has more paths (slopes) where a port can drift.

## Options

1. **A C++17 single-file tool in `tools/solver/`**, built with plain `g++` in CI, reading a plain-text level export,
   with a per-tick trace comparison against the GDScript simulation on every level in CI.
2. **Only the GDScript search**, with longer runs.
3. **A GDExtension** with the simulation in C++ used by the game too.
4. **Another language** (Rust, Python with NumPy).

## Decision

Option 1. The tool ports the movement part of `MazeSim` (no throws, no undo, no cast: the search pre-places rings), uses
`int64_t` and truncating division like GDScript, and offers a `trace` mode and a `search` mode with the command line of
`search_par.gd`. `tools/check_solver.sh` builds it, exports the levels, runs seeded hold-only input sequences in both
simulations and diffs the per-tick traces (position, speed, ground, death, rings used), then runs calibration searches.
CI runs it on every push. The GDScript search stays as the reference. A change of movement in `sim/` changes the port in
the same commit.

## Alternatives rejected

- **Only GDScript**: no new code, but evidence for twelve levels at 2000 nodes per second is weak or takes hours, as the
  levels 4 to 9 report showed (l005 and l006 could not be confirmed). Rejected.
- **GDExtension**: one fast simulation for game and tools, but the game would ship native code for every platform
  (web export with extensions, iOS and Android later) and lose the pure-GDScript simulation that the tests and the
  determinism rules are built around. Far larger change. Rejected.
- **Rust**: as fast, but a second toolchain in CI for one tool. **Python**: easy, but not fast enough for a tree search.
  Rejected.

## Consequences

- Two implementations of the movement rules exist; the trace diff in CI is the guard and the rule above keeps them in
  step. A deliberate sim change without the port fails CI.
- `build/solver/` holds the binary and the exported files (ignored by git, excluded from the export).
- Par evidence for new levels is reproducible by anyone with `g++` and Godot; results go into the level tables.
