# 0001 White Maze: a calm platformer with thrown bounce rings

Status: accepted (2026-11-20)

## Context

The owner asked for a game "in the trend of Mario": a 2D platformer with running, jumping and levels, original, built
in Godot by one developer, also playable on a phone. The game designer proposed three directions in round 1 and two in
round 2 (`docs/ideas/2026-11-20-platformer.md`). The owner answered:

- "Mario" means running, jumping and finishing levels; 2D; not too complex.
- Keyboard first; later playable on phone and tablet with touch (virtual sticks and buttons; two sticks are an
  example, not a requirement); landscape.
- A White game: flat, dark, calm, the White Kit palette; no enemies, no lives, only obstacles.
- A fixed series of levels, no daily puzzle.
- No time pressure, but time measured per level and kept as statistics in a profile: local first, extendable to an
  online profile later.
- Name White Maze (repository `white-maze`), concept: the round 2 direction with thrown beads.

## Decision

- White Maze is a 2D platformer: walk and jump from start to finish through a fixed, ordered series of handmade
  levels. The player throws a white bead in a straight line; where it hits a surface it becomes a bounce ring that
  launches the player away from that surface. Three beads per level; par is the fewest beads the designer needs.
- Aiming runs in slow motion, which solves the thumb conflict on touch (jump and aim are under the same thumb).
- Obstacles only (spikes, gaps, no-ring blocks); a death sends the player back to the start of the level without any
  other penalty.
- Time is measured per level, shown with hundredths, never a limit. Statistics live in a local profile designed to be
  merged with an online profile later (ADR 0007).
- Names: repository, folder and game id `white-maze`; title `White Maze`; logo text `WHITE MAZE`; app id (later)
  `com.st33f.whitemaze`; play address (later) `play.white-maze.steefbeest.nl` (White Kit ADR 0008).
- Phase 1 is a playable prototype with three grey-block test levels (easy, medium, hard).

## Alternatives considered

- **White Step** (one stick, place a tile under your feet): smaller and easier to learn, but the owner chose the
  throwing concept. It stays the fallback if aiming on a phone proves frustrating; movement, levels and profile carry
  over.
- **Lampion** (auto-runner, one-touch): solves touch controls best, but the owner wants to walk himself. Rejected.
- **Kiem** (colourful garden, enemies, lives): the most Mario-like, but much art and not a White game. Rejected.
- **A daily level set like the puzzle games**: needs more than 1000 handmade levels a year. Rejected by the owner in
  favour of a fixed series.
- **Par on time (time pressure)**: rejected by the owner; time is only measured.

## Consequences

- The complexity sits in the levels, not in the rules: one rule ("a ring pushes you away from its surface").
- Movement feel is the main risk; phase 1 is built to test it, and tuning is expected after the owner's playtest.
- The game shares look and some code with the puzzle games but not their screen flow (ADR 0008).
