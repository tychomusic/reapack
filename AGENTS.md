# Tycho ReaPack

ReaPack repository for Tycho REAPER scripts. This is a multi-package repo: each package owns its own `PROJECT_KNOWLEDGE.md`.

## First Read
- Read repo-level `PROJECT_KNOWLEDGE.md` before work in this repo.
- Then read the package-specific `PROJECT_KNOWLEDGE.md` for the package being changed.
- Treat `/Applications/Reaper/Scripts/Tycho/reapack` as the working repo.
- If the user has not named a package, assume the active package is Track Navigator for now.

## Current Packages
- Track Navigator:
  - Package path: `Track Navigator/`
  - Knowledge: `Track Navigator/PROJECT_KNOWLEDGE.md`
  - Main script: `Track Navigator/Track Navigator.lua`
  - Package metadata: `Track Navigator/Track Navigator package.lua`
- Reflex:
  - Package path: `Reflex/`
  - Knowledge: `Reflex/PROJECT_KNOWLEDGE.md`
  - Main script: `Reflex/Reflex.lua`
  - Package metadata: `Reflex/Reflex package.lua`
  - Live/local test path: `/Applications/Reaper/Scripts/Tycho/reapack/Reflex`

## Cross-Package Rules
- Keep package-specific behavior, versioning, and architecture rules in that package's `PROJECT_KNOWLEDGE.md`.
- Shared NAV behavior may need coordinated changes in Track Navigator and Reflex, but do not edit both implicitly. Do one package at a time unless the user explicitly asks for a port.
- Reflex and standalone Track Navigator are developed and locally tested from this ReaPack repo before release; avoid using `/Applications/Reaper/Scripts/Tycho/Reflex` as a source of truth unless the user explicitly asks to recover/migrate files from it.
- Do not add comments or headers crediting agents, Claude, or other assistants.
- Preserve author metadata as `S.Hansen / Tycho` unless the user requests otherwise.

## Pixel And Retina UI Work
- For disputed 1-2px UI spacing/alignment, stop before tuning constants and use screenshot-based measurement. Do not iterate from verbal estimates or inferred geometry alone.
- Treat odd Retina-pixel targets as half-logical coordinates. Do not run them through `S()` or floor/round the Y coordinate afterward.
- For draw-list geometry from user-provided pixel specs, write the pixel contract before editing: which visible edge is being measured, whether the number is an outer-edge inset or a center coordinate, the target OD/ID in Retina pixels, and the exact existing color token being used.
- If the user says an object is `N px from` or `N px in from` an edge, treat `N` as the visible outer-edge gap unless they explicitly say the center is `N px` from that edge. Compute center as `edge + gap + radius` or `edge - gap - radius`.
- For fixed screenshot/Retina draw-list targets, convert to raw logical coordinates with `retina_px / 2` at the rendered surface. Do not pass odd diameters, radii, or final center coordinates through `S()`, because `S()` rounds away half-logical pixels. Use `S()` for scalable layout primitives only, not for final measured pixel targets.
- When a requested color is described by another control/state, trace that control's actual code path and reuse its token. Do not substitute a visually similar token.
- If a parent/child ImGui boundary snaps away the odd pixel, put the final 1px half-logical offset at the rendered surface immediately before drawing the card/row, not in `WindowPadding`.
- After one failed pixel attempt, switch to measuring the rendered screenshot and identify both edges being measured before another edit.

## ReaPack Releases
- Public ReaPack index: `index.xml`
- Import URL:
  `https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml`
- Rebuild/check the ReaPack index after release changes:
  - `~/.gem/ruby/2.6.0/bin/reapack-index --scan --no-commit`
  - `~/.gem/ruby/2.6.0/bin/reapack-index --check`
- Validate with `git diff --check`.
- Commit code changes and index changes as separate commits when practical.
- Push `main` after the index is updated.

## Stale ReaPack Metadata
- If REAPER/ReaPack shows stale metadata, remove the Tycho repo, clear the local ReaPack cache file for Tycho, re-import the raw URL, and synchronize packages.

## Delivery
- Summarize what changed and what to test.
- After completing work and verification, play:
  `afplay /System/Library/Sounds/Hero.aiff`
