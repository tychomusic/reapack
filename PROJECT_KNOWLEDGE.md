# Tycho ReaPack Project Knowledge

This is the repo-level knowledge file for the Tycho ReaPack repository. It describes repo structure, release workflow, and cross-package coordination. Package-specific details live inside each package directory.

## Current State
- Repo root: `/Applications/Reaper/Scripts/Tycho/reapack`
- GitHub remote: `https://github.com/tychomusic/reapack.git`
- ReaPack import URL: `https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml`
- Current packages in this repo: Track Navigator, Reflex
- Current Track Navigator public version: 1.2.13
- Current Reflex public version: 20.673

## Package Knowledge Convention
- Each package should have its own `PROJECT_KNOWLEDGE.md`.
- Before editing a package, read repo `PROJECT_KNOWLEDGE.md`, then that package's `PROJECT_KNOWLEDGE.md`.
- Package-specific files own package versioning, UI shorthand, behavior rules, architecture notes, and test checklists.
- Repo-level docs should stay package-neutral where possible.

## Current Layout
- `AGENTS.md`: repo-level Codex instructions.
- `PROJECT_KNOWLEDGE.md`: this repo-level knowledge file.
- `README.md`: public repo overview and ReaPack import URL.
- `index.xml`: generated ReaPack index.
- `.reapack-index.conf`: ReaPack indexer config.
- `Track Navigator/`: current public package.
- `Track Navigator/PROJECT_KNOWLEDGE.md`: Track Navigator package knowledge.
- `Reflex/`: current public package.
- `Reflex/PROJECT_KNOWLEDGE.md`: Reflex package knowledge.

## Layout
```text
reapack/
  AGENTS.md
  PROJECT_KNOWLEDGE.md
  README.md
  index.xml
  Track Navigator/
    PROJECT_KNOWLEDGE.md
  Reflex/
    PROJECT_KNOWLEDGE.md
```

## Live Dev And Testing Convention

`/Applications/Reaper/Scripts/Tycho/reapack` is the single live development, local testing, packaging, and release repo for both packages.

The user's active REAPER install at `/Applications/Reaper` should run only these two user-facing live scripts:
- Track Navigator: `/Applications/Reaper/Scripts/Tycho/reapack/Track Navigator/Track Navigator.lua`
- Reflex: `/Applications/Reaper/Scripts/Tycho/reapack/Reflex/Reflex.lua`

`Reflex/Navigator.lua` exists inside the Reflex package as a NAV-only Reflex harness. It is useful for isolating Reflex's embedded Navigator behavior, but it is not the spin-off public Track Navigator script and should not be described to the user as the normal Navigator button/action. When the user says they want to run "Track Navigator", they mean `Track Navigator/Track Navigator.lua`.

Stale duplicate folders were archived on 2026-05-24 under `/Applications/Reaper/Scripts/Tycho cleanup archive 2026-05-24`:
- old `/Applications/Reaper/Scripts/Tycho/Reflex` (`20.669`)
- old `/Applications/Reaper/Scripts/Tycho/Reflex.bak`
- stray `/Applications/Reaper/Scripts/Tycho ReaPack`

Do not use or recreate `/Applications/Reaper/Scripts/Tycho/Reflex`, `/Applications/Reaper/Scripts/Tycho/Reflex.bak`, or `/Applications/Reaper/Scripts/Tycho ReaPack` as live sources. If recovery is needed, copy specific files out of the archive deliberately.

Reflex user-local state files (`remote_buttons.txt`, `remote_pages.txt`, and `fx_browser_action.txt`) were migrated into `/Applications/Reaper/Scripts/Tycho/reapack/Reflex` and are locally ignored via `.git/info/exclude`; they are not packaged. `Tycho_Track Name Rewriter.lua` was preserved at `/Applications/Reaper/Scripts/Tycho/Tycho_Track Name Rewriter.lua`.

## Track Navigator And Reflex
- Track Navigator is the standalone public ReaPack package for NAV.
- Reflex is the public ReaPack package for the full inspector/visibility/routing/Remote workflow and has its own embedded Navigator.
- Track Navigator contains `core/Reflex_*.lua` files because the NAV code descends from shared Reflex-era helpers. The names are currently part of package layout and `require` paths; do not rename casually.
- When changing shared NAV behavior, note whether Reflex should receive the same change in a separate task.
- Do not mix Track Navigator release work with Reflex edits unless the user explicitly asks for a cross-package port.

## Versioning
- Packages use their own version schemes.
- Track Navigator uses public versions such as `1.0`, `1.1`, and `1.2`; use patch versions such as `1.2.1` for small fixes and reserve whole minor bumps for more meaningful user-facing releases.
- Reflex historically uses `v20.xxx`; do not apply Reflex version numbers to Track Navigator.
- For every release, update the package's declared version sources, then regenerate `index.xml`.

## ReaPack Release Workflow
1. Make package code changes.
2. Update package version metadata if releasing.
3. Run `git diff --check`.
4. Run `~/.gem/ruby/2.6.0/bin/reapack-index --check`.
5. Commit code changes.
6. Run `~/.gem/ruby/2.6.0/bin/reapack-index --scan --no-commit`.
7. Inspect `index.xml` for the expected version and commit-pinned source URLs.
8. Run `~/.gem/ruby/2.6.0/bin/reapack-index --check` again.
9. Commit `index.xml`.
10. Push `main`.
11. Verify the live raw index URL shows the expected version.

Docs-only changes usually do not require regenerating `index.xml` unless package metadata or provided files changed.

## New Codex Project Setup
For a Codex project dedicated to ReaPack packages, point it at:

```text
/Applications/Reaper/Scripts/Tycho/reapack
```

Onboarding prompt:

```text
Working repo:
/Applications/Reaper/Scripts/Tycho/reapack

Read first:
AGENTS.md
PROJECT_KNOWLEDGE.md
Then read the package-specific PROJECT_KNOWLEDGE.md for the package being edited.

Current package:
Track Navigator or Reflex

Current Track Navigator version:
1.2.13

ReaPack import URL:
https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml

Reflex:
Use /Applications/Reaper/Scripts/Tycho/reapack/Reflex as the live local test location and release source. The only normal user-facing Reflex action is Reflex/Reflex.lua. Reflex/Navigator.lua is an internal NAV-only Reflex harness, not the public spin-off Track Navigator. Do not use /Applications/Reaper/Scripts/Tycho/Reflex, /Applications/Reaper/Scripts/Tycho/Reflex.bak, or /Applications/Reaper/Scripts/Tycho ReaPack as source folders; stale copies were archived under /Applications/Reaper/Scripts/Tycho cleanup archive 2026-05-24.
```

## Validation Baseline
- `git diff --check`
- `~/.gem/ruby/2.6.0/bin/reapack-index --check`
- Package-specific runtime tests from that package's `PROJECT_KNOWLEDGE.md`
