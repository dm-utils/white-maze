# 0008 White Kit v0.3.0 for look, texts, tests and CI; own screens

Status: accepted (2026-11-20)

## Context

White Kit (`dm-utils/white-kit`) is the shared base of the White puzzle games: daily puzzle day and seeds, puzzle
store, rules interface, attempt with move record, progress file, texts, theme and buttons, the shared day screen,
safe area, tile view, test runner, screenshot tools and the CI action and template. Its newest release is `v0.3.0`.
White Maze is a platformer with a fixed level series, no daily puzzle, no move records and a landscape layout.

## Decision

- White Maze includes the kit as a git submodule at `addons/white_kit`, pinned to `v0.3.0`; CI checks the pin.
- Used: `WhiteTheme`, `WhiteUi`, `WhiteText` (with the game's table), `WhiteFormat.clock`, `WhiteSafeArea`,
  `WhitePuzzleStore.load_json`, `WhiteTestRunner`, `WhiteRng` (tests only), `ci/setup-godot`, `templates/ci.yml`,
  `tools/shots.sh` and `tools/compare_shots.gd`.
- Not used: `WhiteDayScreen`, `WhiteAttempt`, `WhiteRules`, `WhiteProgress`, `WhiteDaily`, `WhiteSeed`,
  `WhitePrecompute`, `WhiteTileView`.
- The game builds its own level select, game screen, overlays, debug arguments and `--shot` mode.
- CI follows the kit template (pin check, Godot setup, kit tests at 764 checks, game tests, screenshots, web export)
  plus a level check step, without the Pages job until a GitHub repository exists.
- Kit changes are never made in `addons/white_kit`; they are requested in the kit repository and arrive by moving the
  pin.

## Alternatives considered

- **Extend `WhiteDayScreen` with hooks for a platformer**: the screen is built around tabs per level, undo and restart
  of moves, a share line and a portrait column; bending it would add hooks to the kit for one game. Rejected.
- **No kit at all**: the look, texts, safe area, test runner and CI would be copied and drift from the series.
  Rejected.
- **Pin `v0.2.0`**: lacks the safe area and screenshot tools. Rejected.
- **Ask the kit for a generic debug-argument and screenshot helper first**: useful, but not needed to start; listed as
  a later kit candidate. Rejected for now.

## Consequences

- White Maze depends only on stable, generic parts of the kit; a kit update mostly touches look and tests.
- About 100 lines of own debug-argument and screenshot code that a later kit helper could replace.
- The kit's design documents list only puzzle games as users; a note about White Maze is a small kit documentation
  task.
