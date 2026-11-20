# 0005 Ring, bead and death rules

Status: accepted (2026-11-20); par and beads used amended by ADR 0009 (par counts rings used).

## Context

The concept has one rule: a ring pushes the player away from its surface. Several details decide whether that rule
is predictable and calm: where exactly a ring sits, how strong a launch is, what a missed throw costs, whether a bead
can be taken back, and what happens on a spike.

## Decision

- **Straight throws, snapped rings.** A bead flies in a straight line (no arc) up to 20 tiles and becomes a ring on the
  centre of the tile face it hits. Rings sit only on `#` blocks; `X` blocks reject beads (a level design tool).
- **A launch sets the velocity.** Floor ring: up at a fixed speed; wall ring: sideways at a fixed speed plus a minimum
  lift, with 0.2 s of ignored left/right input; ceiling ring: down. The jump button and the incoming speed do not
  change a launch, so every bounce off the same ring is the same.
- **Invalid throws cost nothing.** A throw at an `X` block, an unexposed face, a face with a spike in front, an
  occupied face or beyond range is refused, and the aim line shows this before release. On touch a short tap or a
  release in the dead zone throws nothing.
- **Bead back.** `Z` (or the HUD button) removes the latest thrown ring and returns its bead, without moving the player
  or stopping the clock. Beads used = beads at the start minus beads left at the finish; par is compared with that.
  (Superseded by ADR 0009: par is compared with rings used, the number of thrown rings that launched the player at
  least once; bead back returns the bead but does not lower that count.)
- **Death without loss.** A spike or a fall out of the level returns the player to the start after 0.5 s. Rings and
  beads stay; the clock keeps running. No lives.

## Alternatives considered

- **Arcing throws (gravity on the bead)**: prettier, but much harder to aim, especially on touch and with keyboard
  steps. Rejected (the designer's advice).
- **Rings at the exact hit point**: more freedom, but bounces would depend on sub-tile aim and levels would be hard to
  design and test. Rejected.
- **Launch adds to the current velocity**: physically plausible, but the bounce height would depend on how the player
  arrived. Rejected for predictability.
- **A missed throw spends the bead**: harsher; with slow-motion aiming and a visible target it only punishes
  fat-finger releases on a phone. Rejected.
- **No take-back (restart only)**: simpler, but a whole restart for one misplaced ring feels like homework. Rejected.
- **Death resets the level (rings and time)**: makes a spike much more expensive than in a calm game; the clock
  already charges the lost time. Rejected.

## Consequences

- Par means "rings standing when you finish", so take-back makes par forgiving; the clock rewards clean play.
  (Superseded by ADR 0009: take-back stays free for a ring that never launched the player, but reusing a bead costs
  par.)
- The rules are few enough to be fully unit tested (design 3.12).
- Level designers work with fixed metrics (jump 3 tiles, floor ring about 5.8 tiles).
