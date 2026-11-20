# 0007 A versioned local profile that can be merged with an online profile

Status: accepted (2026-11-20); bead fields renamed to ring fields by ADR 0009 (format stays 1).

## Context

Level times and other statistics are kept in a profile on the device. Later the profile may become an online profile.
The series' platform Pulse stores a game profile as an opaque JSON object per account and game (at most 256 KB, an
optional `id` string that pins it to an account) with a write counter; a stale write gets a conflict with the server
copy, and the client is expected to merge deterministically and retry (`pulse/apps/accounts/src/profile.ts`). The
puzzle games' progress file (`WhiteProgress`) is keyed by puzzle day and stores move records; it does not fit.

## Decision

- One JSON object in `user://profile.json` with `format` (1), `game`, `tick_hz`, a random per-installation `device`
  id, `updated`, `lang` and `levels` keyed by level id.
- Per level: the fastest finish (`best_ticks` with its rings used and run script), the finish with the fewest rings
  used (`fewest_rings`, `fewest_ticks`), `first_finish`, `last_played`, and counters per device (`starts`,
  `finishes`, `deaths`, `play_ticks`). (ADR 0009 renamed `best_beads` and `fewest_beads` to `best_rings` and
  `fewest_rings`.)
- Every field has a merge rule: bests by minimum (fields of one best travel together), first by minimum, last by
  maximum, counters per device by maximum, then summed for display. `merge(local, remote)` is implemented and tested in
  phase 1, but not called.
- Reading is robust: a damaged file is renamed and a fresh profile started; a file with a newer `format` is left
  untouched and the session does not save. Unknown keys are kept. Writes go through a temporary file and a rename.
- `migrate` converts older formats step by step; format 1 has nothing to migrate.

## Alternatives considered

- **Use `WhiteProgress` from the kit**: its format is a map of days to move records; stretching it to level times
  would change the kit format for one game. Rejected.
- **Plain totals without device keys**: smaller, but two devices merging totals would double-count or lose plays.
  Rejected.
- **An append-only log of every finish**: merges trivially by union and keeps full history, but grows without limit
  and approaches the 256 KB cap. Rejected for phase 1; a short history per level is a later option.
- **Godot `ConfigFile` or binary `store_var`**: not the JSON shape the online profile expects, and harder to inspect.
  Rejected.
- **Build the online profile now**: out of scope by the owner's decision.

## Consequences

- Phase 3 can upload the local profile as is and resolve conflicts with `merge`.
- The best run (a run script) lets a later server re-run the simulation and check a best time.
- A device id appears in the file; it is random and contains no personal data.
