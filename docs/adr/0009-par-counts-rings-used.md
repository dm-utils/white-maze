# 0009 Par counts rings used, not beads left over

Status: accepted (2026-11-20). Amends ADR 0005 (bead back, par) and ADR 0007 (bead fields of the profile).

## Context

ADR 0005 defined beads used as "beads at the start minus beads left at the finish" and compared par with that. Bead
back (`Z`) may be used at any moment, also after a ring has launched the player and also in the air. A player who
takes back every ring right after bouncing off it finishes with all beads left: beads used 0, below every par. Par
then measures nothing, and a level with fewer beads than rings needed (the designer's l004 with one bead, l006 with
three beads and four rings) cannot express its intended cost at all.

Three further questions came with the sketch of levels 4 to 9:

- Should a ceiling ring also stop horizontal speed, so that it gets a role of its own?
- May a level have fewer than three beads (l004 with one bead)?
- What happens to the profile fields `best_beads` and `fewest_beads`, whose meaning changes with par?

## Options for par

1. **Beads left over (current).** Simple, but par can always be beaten with 0 by taking every ring back after use.
   Rejected: it is the problem.
2. **Valid throws.** Every valid throw counts; take-back does not lower the count. Closes the misuse, but also charges
   a misplaced ring that the player takes back at once without bouncing on it. That makes "restart to stay within par"
   the answer to every fat-finger throw, which ADR 0005 rejected as homework.
3. **Rings placed.** Like 2, but a bead taken back while still in flight does not count. Slightly kinder, same
   objection for a ring that landed in the wrong place.
4. **Rings used: thrown rings that launched the player at least once.** A thrown ring counts the first time it
   launches the player; further launches of the same ring do not count again; taking it back afterwards returns the
   bead but not the count. A ring taken back before it ever launched (or a bead taken back in flight) costs nothing.

## Decision

- **Par and the result count rings used (option 4).** `rings_used` is the number of thrown rings that have launched
  the player at least once during the attempt. Preset rings never count. The count never goes down within an attempt:
  not by bead back, not by a death; a restart starts a new attempt at 0.
- **Beads are the supply, not the score.** `beads_left` is what the player can still throw; bead back returns a bead to
  the supply (unchanged from ADR 0005). Reusing a bead is allowed and is exactly what costs par: take back, throw
  again, launch again = one more ring used.
- **Why this closes the misuse.** A thrown ring has no effect on the player other than launching it: rings do not
  block movement, do not change a bead's flight and do not interact with hazards; they only mark their face as taken
  for further throws. Every benefit a ring gives therefore passes through a launch, and the first launch of every
  thrown ring is counted. A take-back and re-throw creates a new ring, which is counted again on its first launch.
  There is no way to get a launch from a thrown ring without paying for it.
- **Par may exceed the number of beads.** Par is the designer's fewest rings used; with take-back a level can need
  more rings than it has beads. Level validation accepts `par` from 0 to 20, independent of `beads`.
- **Beads per level is a level field.** `beads` (1 to 9, default 3) already exists in the level format (design 5.1).
  Three is the usual value, not a series rule; l004 with one bead is allowed. Assumption A7 is reworded accordingly.
- **Ceiling ring unchanged in phase 1.** It keeps "straight down, horizontal speed unchanged". The designer's
  proposal (a ceiling ring also sets horizontal speed to 0) is recorded as an open point for after the owner's
  playtest (design 13). No level uses a ceiling ring, so nothing waits for it.
- **Profile names follow the meaning; format stays 1.** `best_beads` becomes `best_rings`, `fewest_beads` becomes
  `fewest_rings`; `fewest_ticks` keeps its name. `record_finish` takes `rings`. The profile format stays 1, because no
  profile file has ever been written by the game: the file store and the screens (card #004) are not built, so there
  is nothing to migrate. From the first build that writes a profile on, the convention "a change of meaning raises
  `format`" applies as before.
- **Texts say rings.** The HUD, the result and the level card show rings used against par ("Ringen 1 · par 2"); the
  bead dots in the HUD keep showing the supply.

## Alternatives considered

- **Options 2 and 3 (count throws or placed rings)**: also close the misuse and are slightly simpler (one counter at
  the throw or at the landing), and the HUD count would rise at the moment of the throw. Rejected because they charge
  par for corrections that gave the player nothing, which goes against the calm, forgiving tone of ADR 0005; the
  extra cost of option 4 is one boolean per ring.
- **Forbid bead back after a launch**: closes the misuse too, but removes reuse of beads, which is the idea of l004,
  l006 and l009. Rejected.
- **Show par as "rings standing at the finish" (the designer's option B)**: keeps the rules, but par still measures
  nothing. Rejected.
- **Ceiling ring stops horizontal speed now**: gives every face its own role and makes a "land on the island" level
  robust. Rejected for phase 1: phase 1 asks whether "a ring pushes you away from its surface" is clear (design 1.1,
  question 4); adding a second effect to one face before the playtest muddies that answer, and no level needs it yet.
  To be decided after the playtest.
- **Raise the profile format to 2 with a migration**: the textbook route for a change of meaning, but a migration for
  files that do not exist is code without a purpose, and old bead counts cannot be converted to rings used anyway.
  Rejected.
- **Keep the field names `best_beads` and `fewest_beads` with the new meaning**: no code churn in the profile, but the
  online profile (phase 3) would carry misleading names forever. Rejected.

## Consequences

- ADR 0005's consequence "par means rings standing when you finish, so take-back makes par forgiving" is replaced:
  take-back is forgiving for mistakes (a ring that never launched you is free) but not for reuse.
- The simulation gets `rings_used` and a `used` flag per ring; both are part of `snapshot()`. `beads_used()` is
  removed; every caller (level check, run printing, result, profile) uses `rings_used`.
- The counter rises at the first launch of a ring, not at the throw; the HUD count therefore changes at the bounce,
  together with the ring's existing launch flash.
- Par values in the level sketch for l004 to l009 are its "A" column (l004 par 3 with one bead, l006 and l009 par 4).
  The shipped levels l001 to l003 keep par 1, 2, 3: their solutions throw only rings they launch from and take nothing
  back.
- Level validation, the level check, solution tests, profile tests and the screen texts change (design 15).
