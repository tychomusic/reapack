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
  - Source/reference workspace: `/Applications/Reaper/Scripts/Tycho/Reflex`

## Cross-Package Rules
- Keep package-specific behavior, versioning, and architecture rules in that package's `PROJECT_KNOWLEDGE.md`.
- Shared NAV behavior may need coordinated changes in Track Navigator and Reflex, but do not edit both implicitly. Do one package at a time unless the user explicitly asks for a port.
- Do not add comments or headers crediting agents, Claude, or other assistants.
- Preserve author metadata as `S.Hansen / Tycho` unless the user requests otherwise.

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
