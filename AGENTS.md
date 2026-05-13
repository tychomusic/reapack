# Tycho ReaPack

ReaPack repository for Tycho REAPER scripts. The active package is Track Navigator.

## First Read
- Read `Track Navigator/PROJECT_KNOWLEDGE.md` before making Track Navigator changes.
- Treat `/Applications/Reaper/Scripts/Tycho/reapack` as the working repo.
- Use `/Applications/Reaper/Scripts/Tycho/Reflex` only as read-only reference unless the user explicitly asks to work in Reflex.

## Track Navigator
- Main script: `Track Navigator/Track Navigator.lua`
- Package metadata: `Track Navigator/Track Navigator package.lua`
- Public ReaPack index: `index.xml`
- Current public version is documented in `Track Navigator/PROJECT_KNOWLEDGE.md`.
- Author metadata should remain `S.Hansen / Tycho`.
- Do not add comments or headers crediting agents, Claude, or other assistants.

## Reflex Relationship
- Track Navigator is the standalone public ReaPack package.
- Reflex contains its own embedded Navigator experience and remains an important reference for shared NAV behavior and helper patterns.
- The `Track Navigator/core/Reflex_*.lua` names are historical/shared-core names. Do not rename them casually; ReaPack packaging and `require` paths depend on them.
- When changing NAV behavior, consider whether the same behavior should be ported back to Reflex, but do not edit Reflex from this repo unless explicitly requested.
- If a task moves into Reflex, switch to the Reflex root, read Reflex `AGENTS.md` and `PROJECT_KNOWLEDGE.md`, and follow its separate versioning and architecture rules.

## Versioning And Releases
- Track Navigator public versions use simple package versions such as `1.1`, not Reflex `v20.xxx` versions.
- For every release change, keep these in sync:
  - `Track Navigator/Track Navigator package.lua` `@version`
  - `Track Navigator/Track Navigator.lua` header `Version:`
  - `TRACK_NAVIGATOR_VERSION`
- Rebuild/check the ReaPack index after release changes:
  - `~/.gem/ruby/2.6.0/bin/reapack-index --scan --no-commit`
  - `~/.gem/ruby/2.6.0/bin/reapack-index --check`
- Validate with `git diff --check`.
- Commit code changes and index changes as separate commits when practical.
- Push `main` after the index is updated.

## ReaPack
- Import URL:
  `https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml`
- If REAPER/ReaPack shows stale metadata, remove the Tycho repo, clear the local ReaPack cache file for Tycho, re-import the raw URL, and synchronize packages.

## Delivery
- Summarize what changed and what to test.
- After completing work and verification, play:
  `afplay /System/Library/Sounds/Hero.aiff`
