# 0003 Game time in ticks; slow motion by fewer ticks per second

Status: accepted (2026-11-20)

## Context

On a phone the jump button and the throw stick are both under the right thumb, so a player cannot jump and aim at the
same moment. The designer proposed that time slows down while aiming. Levels are timed (no time pressure), and the
times are kept as statistics that may later go online. The simulation is a fixed-step integer simulation (ADR 0002).

## Decision

- Slow motion changes how many simulation ticks run per real second, never the tick itself: while aiming the game
  runs at a quarter of its speed (15 ticks per real second), ramping over 0.08 s. Rendering interpolates.
- A level time is game time: the number of ticks from the first active tick (first move, jump press or valid throw) to
  the finish tick, inclusive, shown as `m:ss.cc`. Aiming therefore costs a quarter of real time. Reading the level
  before moving is free; pauses are free.
- Every attempt's inputs are recorded per tick and can be written as a run script; the best run of each level is kept
  in the profile.

## Alternatives considered

- **Real (wall-clock) time**: what a stopwatch would show, but aiming in slow motion would then cost four times as
  much as the game time that passes, a time cannot be reproduced from the inputs, and a server could never check it.
  Rejected.
- **No slow motion; aim and jump on separate thumbs** (for example the jump on the left side): breaks the familiar
  layout of a move stick left and actions right, and still asks for a simultaneous jump and aim. Rejected.
- **Freeze time completely while aiming**: removes all timing from throws in the air and makes aiming feel like a menu.
  Rejected in favour of a quarter speed; the factor is a tuning value.
- **`Engine.time_scale`**: also scales tweens, UI animations and the HUD clock rendering, and does not help the
  integer simulation. Rejected.

## Consequences

- A time depends only on the level and the input sequence, so the same run gives the same time everywhere; the stored
  best run can verify the best time later.
- Players can spend a long time aiming at a quarter of the cost. In a calm series without time pressure this is
  accepted; the owner decides after the playtest (design 13).
- Input events that happen in frames without a tick (common in slow motion) must be latched until the next tick.
