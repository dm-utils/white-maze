# White Maze

A calm 2D platformer in the White series, an adventure with Lilith, an explorer with a red headband. Walk and jump from
start to finish through a fixed series of levels. Throw a white bead in a straight line: where it hits a surface it
becomes a bounce ring that launches you away from it, up from a floor, sideways from a wall, down from a ceiling. Three
beads per level, a par for the fewest rings you bounce off, and a clock that only measures, never hurries. Keyboard
first, touch in landscape.

Status: phase 1 (playable prototype): simulation, three levels, level select, game screen with keyboard, mouse and touch
controls, a local profile with times, and the web version. Waiting for the first playtest.

- Play version: https://play.white-maze.steefbeest.nl
- Design: `docs/design.md`, decisions in `docs/adr/`, terms in `docs/glossary.md`, rules for code, levels and tests in
  `docs/conventions.md`.

## Development

Godot 4.7.2. The shared base White Kit is a git submodule at `addons/white_kit`; clone with submodules:

```bash
git clone --recurse-submodules <repository url>
# or, after a plain clone:
git submodule update --init
```

Run the tests and the level check headless:

```bash
godot --headless --path . --import
godot --headless --path . res://tests/run_tests.tscn
godot --headless --path . -s res://tools/check_levels.gd
tools/check_search_par.sh
```

Play one level directly and print the run when you finish it:

```bash
godot --path . -- --level=l001 --print-run
```

In the web version the same debug arguments work as query parameters, for instance `?fps` for a frame rate label or
`?fps&world=cave&level=l001` (keys: `fps`, `world`, `level`, `camera`, `lang`, `touch`).

Debug screenshots (needs `xvfb`; scenarios in `tools/shots.txt`):

```bash
addons/white_kit/tools/shots.sh run . tools/shots.txt build/shots
```

## Controls

Keyboard: `A`/`D` or arrows walk, `Space` or `W` jump (hold for higher), hold `J` to aim (time slows down), `W`/`S`
turn the aim, release `J` to throw, `K` cancels, `Z` bead back, `R` restart, `Esc` pause. Mouse: hold and release the
left button to throw at the cursor. Touch: left thumb walks, right side has the throw stick and the jump button.

All rights reserved.
