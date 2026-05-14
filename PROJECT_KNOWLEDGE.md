# Tycho ReaPack Project Knowledge

This is the repo-level knowledge file for the Tycho ReaPack repository. It describes repo structure, release workflow, and cross-package coordination. Package-specific details live inside each package directory.

## Current State
- Repo root: `/Applications/Reaper/Scripts/Tycho/reapack`
- GitHub remote: `https://github.com/tychomusic/reapack.git`
- ReaPack import URL: `https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml`
- Current package in this repo: Track Navigator
- Current Track Navigator public version: 1.2
- Future package expected here: Reflex

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

## Intended Future Layout
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

Reflex is not currently managed from this repo. Until it is moved here, use `/Applications/Reaper/Scripts/Tycho/Reflex` only as read-only reference unless the user explicitly asks to switch to Reflex work.

## Track Navigator And Reflex
- Track Navigator is the standalone public ReaPack package for NAV.
- Reflex has its own embedded Navigator and remains the upstream/sibling reference for shared NAV behavior.
- Track Navigator contains `core/Reflex_*.lua` files because the NAV code descends from shared Reflex-era helpers. The names are currently part of package layout and `require` paths; do not rename casually.
- When changing shared NAV behavior, note whether Reflex should receive the same change in a separate task.
- Do not mix Track Navigator release work with Reflex source edits unless the user explicitly asks for a cross-package port.

## Versioning
- Packages use their own version schemes.
- Track Navigator uses simple public versions such as `1.0`, `1.1`, `1.2`.
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
Track Navigator

Current Track Navigator version:
1.2

ReaPack import URL:
https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml

Reflex:
Use /Applications/Reaper/Scripts/Tycho/Reflex only as read-only reference unless I explicitly ask for Reflex work or a Reflex port.
```

## Validation Baseline
- `git diff --check`
- `~/.gem/ruby/2.6.0/bin/reapack-index --check`
- Package-specific runtime tests from that package's `PROJECT_KNOWLEDGE.md`
