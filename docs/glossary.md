# Glossary

Terms used in the code, the design (`docs/design.md`) and the ADRs. Code names in brackets. Terms shared by the series
(safe area, test runner, game id, ...) are defined in White Kit's glossary (`addons/white_kit/docs/glossary.md`) and
repeated here only where White Maze adds something. Terms marked [later] belong to phases after phase 1.

| Term | Meaning |
|---|---|
| Active tick | A tick with left/right input, a jump press or a valid throw. The first one starts the clock. |
| Aim | Choosing a throw direction: hold `J`, hold the left mouse button, or drag the throw stick out of its dead zone. The game runs in slow motion while aiming. |
| Aim index (`MazeAim`) | One of 144 throw directions, `i * 2.5` degrees counter-clockwise from pointing right (36 up, 72 left, 108 down). |
| Aim line | The dotted line from the player to where the bead would hit, drawn while aiming; dimmed with a cross when the throw would be invalid. |
| Apex hang | Half gravity near the top of a jump while the jump button is held (`APEX_GRAVITY`, `APEX_THRESHOLD`). |
| Attempt | One go at a level, from opening or restarting it until the finish, a restart or leaving. Not the kit's `WhiteAttempt`. |
| Bead | The white ball the player throws. A level has `beads` of them (a level field, usually three). It becomes a ring where it hits. Beads are the supply, not the score; the score is rings used. |
| Bead back (`undo`) | Taking back the most recently thrown ring (or the bead still in flight) and getting the bead back into the supply. Does not lower rings used. `Z` or the HUD button. |
| Beads left (`beads_left`) | The beads the player can still throw in the current attempt; a valid throw takes one, bead back returns one. Shown as the bead dots in the HUD. |
| Beads used | Former score (beads at the start minus beads left at the finish); replaced by rings used (ADR 0009). |
| Best rings (`best_rings`) | Rings used in the fastest finish of a level; travels with `best_ticks` and `best_run`. Formerly `best_beads`. |
| Best run (`best_run`) | The run script of the fastest finish of a level, stored in the profile. |
| Best time (`best_ticks`) | The fastest finish of a level, in ticks. |
| Cast (`MazeSim.cast`) | The pure query that marches the throw ray through the grid and reports the target face and whether the throw is valid. |
| Clock | Game time of the current attempt, shown as `m:ss.cc`; starts at the first active tick. |
| Coyote time (`COYOTE_TICKS`) | A jump still works for a few ticks after walking off a ledge. |
| Corner correction (`CORNER_CORRECTION`) | A rising player whose head clips a ceiling corner by a few pixels is shifted sideways instead of stopped. |
| Counters (`counts`) | Per-device statistics of a level in the profile: `starts`, `finishes`, `deaths`, `play_ticks`. |
| Dead zone | The part of a stick around its centre where input counts as none (move stick 20 px horizontally, throw stick 26 px). |
| Death | Touching a spike's hitbox or falling below the level. The player returns to the start after 30 ticks; nothing else is lost. |
| Device id (`device`) | 16 random hex characters created with the profile; the key of this installation's counters. |
| Face | One side of a tile: `UP` (top, floor), `DOWN` (bottom, ceiling), `LEFT`, `RIGHT` (walls), named after the direction it points to. |
| Fewest rings (`fewest_rings`) | The finish with the fewest rings used; the faster one (`fewest_ticks`) wins a tie. Formerly `fewest_beads`. |
| Finish (`F`) | The goal tile; touching it ends the level. |
| Flight | A thrown bead on its way; it becomes a ring at its arrival tick. |
| Format (`format`) | Version number of the profile or of a level file; raised when a field changes meaning. |
| Game time | Time counted in simulation ticks (60 per second of normal speed). Slow motion slows game time down. |
| Hazard box | The player's hitbox shrunk by 4 px on every side; used against spikes. |
| Hint | An optional line of a level shown at the bottom of the game screen, with control names filled in for the current input mode. |
| Index (`levels/index.json`) | The ordered list of level ids that forms the series. |
| Input mode | Keyboard or touch, whichever was used last; decides the touch overlay's visibility and the control names in hints. |
| Jump buffer (`JUMP_BUFFER_TICKS`) | A jump pressed shortly before landing still happens on landing. |
| Launch | A ring setting the player's velocity away from its face. The first launch of a thrown ring makes it a used ring. |
| Level (`MazeLevel`) | One handmade map with metadata, loaded from `levels/<id>.json`. |
| Level check (`tools/check_levels.gd`) | Headless tool that validates all levels and replays their solutions. |
| Level id | Stable name of a level (`l001`), the key of its statistics. |
| Merge (`MazeProfile.merge`) | Deterministic combination of a local and a remote profile, for the online profile [later]. |
| Move stick | The floating touch control on the left for walking; horizontal only. |
| No-ring block (`X`) | A solid block on which beads do not stick. |
| Par | The fewest rings used the level designer needs for a level (0 to 20). May be larger than the level's beads, because bead back lets a bead be reused. |
| Preset ring | A ring placed by the level file; it cannot be taken back and never counts as used. |
| Profile (`MazeProfile`, `user://profile.json`) | The local file with the language and per-level statistics. |
| Respawn | Returning the player to the start after a death. |
| Ring | A bounce ring on a block face, made by a bead or preset; it launches the player away from its face. |
| Rings used (`rings_used`) | The score of an attempt: the number of thrown rings that launched the player at least once. Never goes down within an attempt (not by bead back, not by a death); compared with par (ADR 0009). |
| Ring zone | The thin area in front of a ring's face that triggers a launch. |
| Run script (`MazeRunScript`) | Text form of a per-tick input sequence, for example `R40 RJ12 T30 -5`. |
| Series | The fixed, ordered levels of the game; level `n + 1` opens after level `n` is finished. |
| Slow motion | A quarter game speed while aiming (`AIM_TIME_SCALE`), ramped over 0.08 s. |
| Solid | A tile the player cannot pass: `#`, `X`, and everything outside the grid to the left, right and top. |
| Solution | A run script in `tests/solutions.json` that finishes a level within par (rings used <= par). |
| Spawn (`S`) | The start tile; the player stands on the floor below it. |
| Spike (`^`) | A hazard tile; its hitbox is the lower half of the tile, slightly narrower. |
| Supply | The beads left; see beads left. |
| Throw | Releasing an aim; a valid throw spends a bead from the supply and starts a flight. A throw alone does not count towards par. |
| Throw stick | The touch control on the right for aiming and throwing: drag to aim, release to throw, back to the centre to cancel. |
| Tick | One simulation step, 1/60 s of game time. |
| Tile | A 40 x 40 px square of the level grid. |
| Touch overlay (`MazeTouchOverlay`) | The on-screen move stick, throw stick and jump button. |
| Tuning (`MazeTuning`) | The movement and ring values, each as a readable value and as the integer the simulation uses. |
| Unit | 1/1000 px; the simulation's distance unit. A tile is 40000 units. |
| Used ring (`used`) | A thrown ring that has launched the player at least once; counted once in rings used. |
| Wall lock (`WALL_LOCK_TICKS`) | After a wall launch, left/right input is ignored for 12 ticks. |
| White Kit | The shared base of the White games, a submodule at `addons/white_kit`, pinned to `v0.3.0`. |
