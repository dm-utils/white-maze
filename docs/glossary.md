# Glossary

Terms used in the code, the design (`docs/design.md`) and the ADRs. Code names in brackets. Terms shared by the series
(safe area, test runner, game id, ...) are defined in White Kit's glossary (`addons/white_kit/docs/glossary.md`) and
repeated here only where White Maze adds something. Terms marked [later] belong to phases after phase 1.

| Term | Meaning |
|---|---|
| Active tick | A tick with left/right input, a jump press or a valid throw. The first one starts the clock. |
| Aim | Choosing a throw direction: hold `J`, hold the left mouse button, or drag the throw stick out of its dead zone. The game runs in slow motion while aiming. |
| Aim framing | The camera shifting towards the aim's hit point while aiming with the keyboard or the throw stick, so target and player are both in view; kept until the thrown bead has become a ring. Not done for mouse aims (design 19.7). |
| Aim index (`MazeAim`) | One of 144 throw directions, `i * 2.5` degrees counter-clockwise from pointing right (36 up, 72 left, 108 down). |
| Aim line | The dotted line from the player to where the bead would hit, drawn while aiming; dimmed with a cross when the throw would be invalid. |
| Aim source (`MazeControls.AimSource`) | Where the current aim comes from: keys, mouse or touch; decides whether the camera frames the aim. |
| Apex hang | Half gravity near the top of a jump while the jump button is held (`APEX_GRAVITY`, `APEX_THRESHOLD`). |
| Arm mode (`MazeLilith.Arm`) | What Lilith's throwing arm does: rest, aim, throw or up; chosen independently of the body pose. |
| Attempt | One go at a level, from opening or restarting it until the finish, a restart or leaving. Not the kit's `WhiteAttempt`. |
| Back decor | Quiet decoration on the back wall or in empty cells (pillars, reliefs, torches, arches, vines, crystals), drawn behind the level at low contrast. Never in front of or next to a ring face, never pointed. |
| Bandolier | The strap across Lilith's chest with up to four bead slots; filled slots show the beads left. |
| Bead | The white ball the player throws. A level has `beads` of them (a level field, usually three). It becomes a ring where it hits. Beads are the supply, not the score; the score is rings used. |
| Bead back (`undo`) | Taking back the most recently thrown ring (or the bead still in flight) and getting the bead back into the supply. Does not lower rings used. `Z` or the HUD button. |
| Beads left (`beads_left`) | The beads the player can still throw in the current attempt; a valid throw takes one, bead back returns one. Shown as the bead dots in the HUD. |
| Beads used | Former score (beads at the start minus beads left at the finish); replaced by rings used (ADR 0009). |
| Best rings (`best_rings`) | Rings used in the fastest finish of a level; travels with `best_ticks` and `best_run`. Formerly `best_beads`. |
| Best run (`best_run`) | The run script of the fastest finish of a level, stored in the profile. |
| Best time (`best_ticks`) | The fastest finish of a level, in ticks. |
| Body pose (`MazeLilith.Body`) | Lilith's whole-body animation state: idle, run, jump, launch, fall or dead, a pure function of the simulation state. |
| Camera guard | A hard limit of the follow camera: the player centre stays at least a set distance inside the play rect (sideways 3 tiles, top 1 tile, bottom 2.4 tiles or 4 while falling). The camera's counterpart of a dead zone (design 19.6, values in 20.5). |
| Camera rig (`MazeCameraRig`) | The pure class that computes the camera's position and zoom each frame from the player, the aim, the intro and the overview; the `Camera2D` only receives its result (ADR 0011). |
| Cast (`MazeSim.cast`) | The pure query that marches the throw ray through the grid and reports the target face and whether the throw is valid. |
| Chunk | A 16 x 16 tile part of a static layer, drawn once per level. |
| Clock | Game time of the current attempt, shown as `m:ss.cc`; starts at the first active tick. Runs at the level speed and slower while aiming. |
| Coyote time (`COYOTE_TICKS`) | A jump still works for a few ticks after walking off a ledge. |
| Corner correction (`CORNER_CORRECTION`) | A rising player whose head clips a ceiling corner by a few pixels is shifted sideways instead of stopped. |
| Counters (`counts`) | Per-device statistics of a level in the profile: `starts`, `finishes`, `deaths`, `play_ticks`. |
| Dead zone | The part of a stick around its centre where input counts as none (move stick 20 px horizontally, throw stick 26 px). For the camera see camera guard. |
| Death | Touching a spike's hitbox or falling below the level. The player returns to the start after 30 ticks; nothing else is lost. |
| Decor plan (`MazeDecor.plan`) | The deterministic list of details and back decor of a level in a world, derived from the cells and the cell hash. |
| Device id (`device`) | 16 random hex characters created with the profile; the key of this installation's counters. |
| Door | How the finish tile is drawn: a doorway with posts, a lintel and warm light. |
| Door view | The camera view centred on the door, shown at the start of the intro pan. |
| Edge marker | A small chevron at the edge of the play rect where the aim line leaves the view, when the hit point is off screen. |
| Face | One side of a tile: `UP` (top, floor), `DOWN` (bottom, ceiling), `LEFT`, `RIGHT` (walls), named after the direction it points to. |
| Fewest rings (`fewest_rings`) | The finish with the fewest rings used; the faster one (`fewest_ticks`) wins a tie. Formerly `fewest_beads`. |
| Finish (`F`) | The goal tile; touching it ends the level. Drawn as the door. |
| Fit zoom | The zoom at which the whole level fits in the play rect with a small margin; used by the overview, never above the target zoom. |
| Flight | A thrown bead on its way; it becomes a ring at its arrival tick. |
| Follow camera | The zoomed camera that follows Lilith with a look-ahead, a ground anchor and camera guards, clamped to the level (design 19.6). |
| Format (`format`) | Version number of the profile or of a level file; raised when a field changes meaning. |
| Game rate | Simulation ticks per real second divided by 60: the level speed times the aim rate (a quarter while aiming), 0 while paused or in the overview. |
| Game time | Time counted in simulation ticks (60 per second at a game rate of 1). Slow motion and the level speed slow game time down. |
| Ground anchor | The feet height of the last ground Lilith stood on; the follow camera keeps it at a fixed height in the play rect, so jumps do not move the view. Falling below it moves the view down. |
| Hazard box | The player's hitbox shrunk by 4 px on every side; used against spikes. |
| Hazard colour (`MazeWorlds.HAZARD`) | The one warm red of spikes in every world; no other world colour comes near its hue. |
| Hint | An optional line of a level shown at the bottom of the game screen, with control names filled in for the current input mode. |
| HUD band | The top 110 px of the screen (plus the safe area) with the HUD, darkened by a scrim; not part of the play rect. |
| Index (`levels/index.json`) | The ordered list of level ids that forms the series. |
| Input mode | Keyboard or touch, whichever was used last; decides the touch overlay's visibility and the control names in hints. |
| Intro pan | At the opening of a level the camera shows the door, holds briefly and pans to Lilith; any input skips it, and it never blocks play. |
| Jump buffer (`JUMP_BUFFER_TICKS`) | A jump pressed shortly before landing still happens on landing. |
| Launch | A ring setting the player's velocity away from its face. The first launch of a thrown ring makes it a used ring. |
| Level (`MazeLevel`) | One handmade map with metadata, loaded from `levels/<id>.json`. |
| Level check (`tools/check_levels.gd`) | Headless tool that validates all levels and replays their solutions. |
| Level id | Stable name of a level (`l001`), the key of its statistics. |
| Level speed (`MazeGame.speed`) | The time scale of a level, from its position in the series (`SPEED_PCT`, 80 % for level 1 up to 96 % from level 9); fewer ticks per real second, the same trajectories (ADR 0012). |
| Lilith (`MazeLilith`) | The player character: an original explorer with orange hair, a rose-red headband with two fluttering tails and a bandolier, drawn in code inside the 30 x 32 hitbox. |
| Lip | The light strip on a `#` face where a ring can be placed (`MazeArt.lip_face`). No lip on `X`, on faces towards a spike or a block. |
| Look-ahead | The follow camera's horizontal offset of 3 tiles in the walking direction, taken from the velocity with a short turn delay. |
| Look velocity | The per-tick smoothed velocity that Lilith's tails and launch tilt follow, so they swing round instead of snapping (design 20.3.4). Not used by the camera. |
| Map button | The touch button under the HUD band on the right that shows the overview while held. |
| Merge (`MazeProfile.merge`) | Deterministic combination of a local and a remote profile, for the online profile [later]. |
| Move stick | The floating touch control on the left for walking; horizontal only. |
| No-ring block (`X`) | A solid block on which beads do not stick; drawn smooth and glossy, without a lip. |
| Overview | Holding `Tab`, `M` or the map button zooms out to show the whole level; the game is held (no ticks, the clock stops) until released. |
| Palette | The colours of one world (`MazeWorlds.palette`), checked by contrast tests. |
| Par | The fewest rings used the level designer needs for a level (0 to 20). May be larger than the level's beads, because bead back lets a bead be reused. |
| Play rect | The part of the world visible below the HUD band; the follow camera frames the player and the level in it. |
| Pose blend (`MazePoseBlend`) | The short crossfade (6 ticks of render time) of Lilith's rig from the pose last drawn to a new body pose or arm mode, so legs and arms never jump. Off while the game is frozen for screenshots. |
| Preset ring | A ring placed by the level file; it cannot be taken back and never counts as used. |
| Profile (`MazeProfile`, `user://profile.json`) | The local file with the language and per-level statistics. |
| Render time | The moment the view draws, in ticks as a float: `tick - 1 + alpha`. The interpolated position is the state at this moment; Lilith's animation runs on it. |
| Respawn | Returning the player to the start after a death. The camera cuts to the start at that moment. |
| Rig (`MazeLilith.rig`) | Lilith's joints for one pose: feet, hands, upper-body drop, tilt and how far the hair tips are up. The shapes are built from it; blends mix two rigs. |
| Ring | A bounce ring on a block face, made by a bead or preset; it launches the player away from its face. |
| Rings used (`rings_used`) | The score of an attempt: the number of thrown rings that launched the player at least once. Never goes down within an attempt (not by bead back, not by a death); compared with par (ADR 0009). |
| Ring zone | The thin area in front of a ring's face that triggers a launch. |
| Run script (`MazeRunScript`) | Text form of a per-tick input sequence, for example `R40 RJ12 T30 -5`. |
| Series | The fixed, ordered levels of the game; level `n + 1` opens after level `n` is finished. |
| Slow motion | A quarter of the level speed while aiming (`AIM_TIME_SCALE`), ramped over 0.08 s. |
| Snap | Moving the camera to its follow target at once, without smoothing: at the start of an attempt, at a respawn and for screenshots. |
| Solid | A tile the player cannot pass: `#`, `X`, and everything outside the grid to the left, right and top. |
| Solution | A run script in `tests/solutions.json` that finishes a level within par (rings used <= par). |
| Spawn (`S`) | The start tile; the player stands on the floor below it. |
| Speed curve (`MazeGame.SPEED_PCT`) | The table of level speeds by series position (design 20.6.2). |
| Spike (`^`) | A hazard tile; its hitbox is the lower half of the tile, slightly narrower. |
| Static layer (`MazeStaticLayer`) | The back wall or tile layer of the world view, split into chunks and drawn once per level. |
| Supply | The beads left; see beads left. |
| Target zoom | The camera's fixed zoom for a screen size: 9 tiles of visible height (at least 16 tiles of width), so Lilith is about 8.9 % of the screen height on 16:9 and wider (design 19.4, 20.5). |
| Throw | Releasing an aim; a valid throw spends a bead from the supply and starts a flight. A throw alone does not count towards par. |
| Throw stick | The touch control on the right for aiming and throwing: drag to aim, release to throw, back to the centre to cancel. |
| Tick | One simulation step, 1/60 s of game time. |
| Tile | A 40 x 40 px square of the level grid. |
| Touch overlay (`MazeTouchOverlay`) | The on-screen move stick, throw stick, jump button and map button. |
| Tuning (`MazeTuning`) | The movement and ring values, each as a readable value and as the integer the simulation uses. |
| Unit | 1/1000 px; the simulation's distance unit. A tile is 40000 units. |
| Used ring (`used`) | A thrown ring that has launched the player at least once; counted once in rings used. |
| Wall lock (`WALL_LOCK_TICKS`) | After a wall launch, left/right input is ignored for 12 ticks. |
| White Kit | The shared base of the White games, a submodule at `addons/white_kit`, pinned to `v0.3.0`. |
| World (`MazeWorlds.World`) | The look of a group of three levels: temple (1-3), jungle ruin (4-6), cave (7-9 and later). Derived from the level's position in the series, never stored in a level file. |
