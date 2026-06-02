# Presentation Contract

Two layers of parity now exist between Android and iOS:

| Layer | File | Fixes |
|---|---|---|
| Decision | `parity/corridor-core.json` | grid → `command` / `reason` |
| Presentation | `parity/presentation-core.json` | the decision → how it is drawn |

`presentation-core.json` is the single source of truth for both overlays. If you
change a colour, glyph, caption, or the gesture, change it there first, then
mirror it in `PresentationContract.kt` (Android) and `PresentationContract.swift`
(iOS). The snapshot tests below exist to catch drift.

## Two surfaces

Roana now renders one of two surfaces, never a raw full-screen camera feed by
default:

1. **Ambient (default, real users).** Near-black, low-power. One large
   command glyph + colour + a one-line speech caption + an "alive" pulse.
   Blind and low-vision users rely on speech and haptics; the screen is a
   low-cost ambient cue and a glanceable signal for a sighted helper. On OLED a
   near-black screen costs almost no power and does not glare.
2. **Debug HUD (developers / testing / sighted helpers).** Shows what the
   system sees: a 15×15 depth heatmap aligned to the planner grid, the YOLO
   detection box, the corridor path, the command chip, and a telemetry strip.
   The live camera frame is **off by default** (it is the bright, power-hungry
   layer) and can be toggled back on for debugging.

## Switching between them

A 2-second long-press in the **bottom-right corner** toggles ambient ⇄ debug.

- Kept in release builds, but deliberately hard to hit by accident.
- **Not** a single double-tap: that is the VoiceOver / TalkBack "activate"
  gesture and would collide.
- State is **not persisted**; every launch starts in ambient.

## Depth colour ramp

Normalized depth value (higher = nearer) maps far→near as cool→warm, with the
two ramp stops placed exactly on the corridor thresholds so the colour change is
meaningful:

- `0.72` = `SAFE_CELL_DEPTH`
- `0.86` = `NEAR_OBSTACLE_DEPTH`

UI code must read these from the shared corridor constants, not re-declare them.

## Command map

| command | glyph | colour | caption |
|---|---|---|---|
| STRAIGHT | ↑ | `#62E08A` | Go straight |
| LEFT | ← | `#5CC8FF` | Turn left |
| RIGHT | → | `#C89BFF` | Turn right |
| STOP | ■ | `#FF5563` | Stop |

## Telemetry

Same fields, same order, same format on both platforms:
`FRM`, `YOLO ms`, `DEPTH ms`, `GAPS` (milliseconds rounded to integer).

## Parity test

Each platform renders a fixed set of `PresentationFrame`s (one per command, plus
a near-obstacle STOP and an all-safe STRAIGHT) and asserts the **structured
descriptor** — command → colour / glyph / caption / path target column /
telemetry text — matches `presentation-core.json`. We compare descriptors, not
pixels; cross-platform pixel equality is not a realistic goal.
