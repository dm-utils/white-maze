# 0006 Controls: keyboard first, touch layout from the start

Status: accepted (2026-11-20)

## Context

The owner plays with a keyboard but wants the game playable on phones and tablets in landscape later, with virtual
sticks and buttons where the game needs them. The game needs three things: walk left/right, jump (held for height),
and aim plus throw.

## Decision

- **One intent layer** (`MazeControls`) merges keyboard, mouse and touch; the game screen samples it once per
  simulation tick. Presses (jump, throw, bead back) are latched until the next tick.
- **Keyboard:** `A/D` or arrows walk; `Space`, `W` or `Up` jump; hold `J` to aim (slow motion), `W/S` or `Up/Down`
  turn the aim in 15 degree steps relative to the facing side, release `J` to throw, `K` or `Esc` cancels; `Z` bead
  back, `R` restart, `Esc`/`P` pause.
- **Mouse (optional):** hold the left button to aim at the cursor, release to throw, right button cancels. Mouse events
  emulated from touch are ignored.
- **Touch:** a floating, horizontal-only move stick on the left; on the right a fixed throw stick (drag = aim, release =
  throw, back to the centre = cancel, a tap does nothing) and a large jump button. Both are under the right thumb on
  purpose; slow motion while aiming resolves the conflict (ADR 0003). HUD buttons for bead back, restart and pause sit
  in the top band, where the overlay ignores touches.
- Walking is digital (full speed beyond a 20 px dead zone), not analog.
- Aim directions are 144 steps of 2.5 degrees for mouse and touch, 24 for the keyboard.

## Alternatives considered

- **Jump by pushing the move stick up**: imprecise and causes accidental jumps; the designer advised against it.
  Rejected.
- **One stick and buttons only, aiming with fixed directions**: fewer controls, but throwing at a chosen spot is the
  core of the game and needs free aim. Rejected.
- **Analog walking speed**: helps fine positioning, but the levels are designed on full-speed metrics and a half
  pressed stick makes jumps inconsistent. Rejected for phase 1; can be revisited after the phone test.
- **Mouse as the primary aim on desktop**: the owner plays keyboard first; the mouse remains optional.
- **Tap anywhere on the screen to throw at that spot**: intuitive on a phone, but the finger covers the target and the
  right side of the screen is already taken. Rejected.

## Consequences

- The touch layout exists in phase 1 and can be tested in a mobile browser; positions and sizes are tuning values.
- Keyboard aiming is slower than mouse or stick; slow motion compensates.
- Gamepad support (left stick, right stick, a button) fits the same intent layer later.
