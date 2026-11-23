# 0014 The chain: the used rings as a route necklace in the view, stored in profile format 2, shared as a local PNG

Status: accepted (2026-11-23). Design: `docs/design-chain.md` (section 22). Builds on ADR 0009 (rings used), ADR 0007
(versioned profile) and ADR 0013 (skin packs, engine-owned colours).

## Context

The owner chose "the chain" as the signature of White Maze: at the finish the rings the player used are strung, in
order, on a thread that pulls taut into a necklace in the shape of the route; it can be shared, and reaching par earns
a clasp. The simulation must not change.

Facts in the code: every `launch` event has the ring's cell, face and `counted` (true exactly at a thrown ring's first
launch, ADR 0009); the level knows its spawn, door and preset rings; the profile stores the fastest run (`best_run`)
but no route of the fewest-rings finish; the result overlay is a centred column; level cards are 170 px buttons with
four text lines; the web build already calls `JavaScriptBridge`; screenshots are compared between runs. Card #040
(roof worlds, sloped tiles, new skin packs) is designed at the same time.

Decisions were needed on: what the chain shows, its shape, the look per world, the finish animation, storage and
migration, the overview, sharing, determinism and where the code lives.

## Options

What the chain shows:

1. **Counted launches in order (beads) plus first launches of presets (knots), from the start to the door.**
2. Rings standing at the finish.
3. Every valid throw.
4. The full trajectory of the player.

Shape:

1. **Route silhouette in the frame of the whole level, straight segments, a faint map of the level behind it.**
2. Normalised: beads evenly spaced on a line or arc.
3. Route silhouette fitted to the route's bounding box.
4. A smooth spline through the points.

Look per world:

1. **The same white bead everywhere; world identity from the card background, the thread (door frame colour with a
   contrast fallback), the ghost map and a clasp in the world's lip tint. No new pack key.**
2. A bead shape per world as a skin pack field.

Storage:

1. **A self-contained chain record per level (`rings`, `ticks`, link text), ranked fewest rings then time; profile
   format 2; a one-time backfill from `best_run` in the migration from format 1.**
2. Store the run script of the fewest-rings finish and replay it when drawing.
3. Add the field within format 1 (the convention for added fields).
4. Derive chains only from `best_run`, store nothing new.

Sharing:

1. **A fixed 1200 x 675 PNG rendered in a `SubViewport`, handed to the Web Share API with files where available, else a
   download; inline JS only; the route also as a short text code.**
2. A share URL that encodes the route and a page that draws it.
3. Upload to an image host or a short-link service.
4. `canvas.toBlob` of the game canvas.

Finish moment:

1. **A short real-time stringing animation on a result card (at most 2.05 s), skippable by any press after a 0.3 s
   grace, off with reduced motion.**
2. Beads flying from their places in the world to the card.
3. No animation.

Overview of all chains:

1. **A mini chain on every finished level card.**
2. A separate gallery screen.

## Decision

Option 1 in every group:

- **Content.** A bead per counted launch, so the bead count is `rings_used` and the clasp is "rings used `<=` par".
  Preset rings appear as knots because the route passed them, but they are never beads. Rings taken back before a
  launch are absent; a reused face gives stacked beads.
- **Shape.** Real positions (ring centres, start cell, door cell) scaled uniformly into the whole level's frame, so
  every chain of a level shares a frame and can be compared; straight segments because a taut thread is straight and a
  spline would cut through walls; the solid cells as a ghost map in `back_decor`, which rule C10 keeps quiet.
- **Look.** The bead is the player's white bead in every world (white stays reserved, 18.5). The thread colour is the
  first of `door_frame`, `lip_lo`, `DIM` with contrast at least 3.0, so packs from #040 need nothing new. The clasp
  is a buckle shape, so par does not depend on colour.
- **Storage.** `chain: {"rings", "ticks", "links"}` per level entry, link text like `bu7.11-bu19.11-bu31.11`. Profile
  format 2, because an older build would keep the field only as an unknown key and its merge could keep a worse local
  chain over a better remote one; with format 2 it treats the file as newer and leaves it alone. The migration replays
  each `best_run` once (at most 7200 ticks) to give existing players chains; the backfilled record may later be
  replaced by a better finish.
- **Sharing.** The PNG is rendered when the result opens, so the share call itself uses the browser's activation
  window. `navigator.share({files})` when `canShare` allows it; otherwise, or on any rejection other than a user cancel,
  a download through a blob URL. No network request, no external script, no tracker. A share code
  `wm1/<level>/<rings>/<par>/<ticks>/<links>` goes into the share text and onto the card; reading codes back is later.
- **Finish.** Stringing in real time (card fade, beads dropping one by one on a slack thread, the thread pulling taut,
  the clasp closing), 0.85 s without links and at most 2.05 s; a press during the grace is consumed, a later press
  finishes the animation without also acting on the result buttons; reduced motion (web `matchMedia`, or a debug flag)
  shows the final state at once.
- **Overview.** A mini chain (104 x 58) at the top right of each finished level card; the text lines keep the numbers.
- **Code location.** `MazeChain` (links, codecs, record, replay) is pure and lives in `sim/` because the profile
  migration in `sim/profile.gd` needs it; it reads events and replays scripts and does not change `MazeSim`. Layout,
  colours, animation and drawing are in `ui/` (`MazeChainShapes`, `MazeChainView`, `MazeChainExport`,
  `MazeChainShare`).
- **Determinism.** Links come from deterministic events; layout and shapes are pure functions; tests pin the link text
  of every shipped solution, pin layout points, and compare two screenshot runs.

## Alternatives rejected

- **Rings standing at the finish**: simplest to read from the state, but bead back removes used rings, so the chain
  would disagree with the score that par measures. Rejected.
- **Every valid throw**: includes rings that gave nothing and that par does not count. Rejected.
- **The full trajectory**: exact, but a tangle on most levels, not a necklace. Rejected.
- **Normalised shape**: always tidy, but every chain with the same count looks alike; the route is the signature.
  Rejected.
- **Bounding box of the route**: a larger chain, but the frame changes per run and the level context is lost.
  Rejected.
- **Spline**: softer, but overshoots through walls and stops being the route. Rejected.
- **Bead shape per world**: more variety, but the bead would read as decor instead of the player's bead, and it adds a
  pack key while #040 writes packs. Rejected.
- **Storing the fewest-rings run script**: allows replay and verification, but every draw (nine cards) would replay
  the simulation, a run can be up to 20000 characters, and a later simulation change would silently break stored
  chains. Rejected; the link text is small and stable.
- **Format 1 with the added field**: follows the convention and avoids the "newer" notice for a cached old build, but
  allows an old build to degrade the chain in a merge and gives the backfill no "done" marker. Rejected.
- **Only from `best_run`**: no new field, but the fastest run is not the fewest-rings route, so the chain would not
  match par. Rejected (used only once, as the backfill).
- **Route URL with a drawing page**: links instead of images, but needs a hosted page, which is a service and invites
  tracking. Rejected.
- **Image host or short links**: external services, against the privacy rule. Rejected.
- **`canvas.toBlob` of the game**: no extra viewport, but the picture would include the HUD and overlay and depend on
  the screen size. Rejected.
- **Beads flying from the world**: spectacular, but the camera shows only part of the level, so most beads would start
  off screen, and the world-to-card mapping changes with every camera position. Rejected.
- **No animation**: cheapest, but the stringing is the signature moment the owner chose. Rejected.
- **Gallery screen**: chains at full size, but a new screen and navigation for something the level cards can show.
  Left for later, together with sharing an old best chain.

## Consequences

- New classes `MazeChain` (`sim/chain.gd`), `MazeChainShapes`, `MazeChainView`, `MazeChainExport`, `MazeChainShare`
  (`ui/`); conventions list them. `MazeSim`, tuning, levels and solutions do not change; the guard diff lists the
  simulation files by name because `sim/profile.gd` does change.
- Profile format 2 with a `chain` record per level, its sanitize, record and merge rules, and a one-time backfill; the
  store gets the levels when it opens, so main loads levels before the profile. Profile tests that assert format 1 are
  updated.
- The result overlay becomes card plus column, with a share button; the level cards get a mini chain; six texts,
  four debug arguments and fourteen screenshot scenarios are added.
- Web sharing depends on the browser: share sheet where files can be shared, a download elsewhere; the tester checks
  it by hand on Android, iOS and desktop.
- A ring face on slopes (#040) would need a new face letter in the link text; a format change for #040 should share
  the number with this one.
