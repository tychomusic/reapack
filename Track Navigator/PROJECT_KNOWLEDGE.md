# Track Navigator Project Knowledge

Current public version: 1.1

Track Navigator is the standalone public ReaPack package for the NAV track visibility manager. It is related to Reflex's embedded Navigator, but this ReaPack package is its own working surface and release target.

Read repo-level `../PROJECT_KNOWLEDGE.md` first for ReaPack-wide workflow and cross-package rules.

## Repo And Package
- Working repo: `/Applications/Reaper/Scripts/Tycho/reapack`
- Main script: `Track Navigator/Track Navigator.lua`
- Package metadata: `Track Navigator/Track Navigator package.lua`
- ReaPack index: `index.xml`
- Theme template: `Track Navigator/Track Navigator_Theme_Default.lua`
- Public import URL: `https://raw.githubusercontent.com/tychomusic/reapack/main/index.xml`
- Author metadata: `S.Hansen / Tycho`

## Versioning
- Public Track Navigator versions are simple release versions such as `1.0`, `1.1`, `1.2`.
- Do not use Reflex `v20.xxx` version numbers for this package.
- On each release, update all three:
  - `Track Navigator/Track Navigator package.lua` `@version`
  - `Track Navigator/Track Navigator.lua` header `Version:`
  - `TRACK_NAVIGATOR_VERSION`
- After release changes, regenerate and verify `index.xml`.

## File Layout
- `Track Navigator.lua` bootstraps ReaImGui, loads the optional user theme, installs shared cores, owns standalone window lifetime, and passes standalone callbacks into `Reflex_NavViewCore`.
- `core/Reflex_NavViewCore.lua` draws NAV UI: NAV buttons, global NAV.menu, TLT context menus, Help / Manual, docking menu, and the main NAV list.
- `core/Reflex_NavActionCore.lua` owns NAV visibility actions.
- `core/Reflex_ViewModes.lua` owns Routing and Active view modes.
- `core/Reflex_ViewHistory.lua` owns view history state.
- `core/Reflex_PinCore.lua`, `Reflex_NavExclusionCore.lua`, and `Reflex_NavInclusionCore.lua` own pin/hidden/manual visibility persistence.
- `core/Reflex_FontCore.lua`, `Reflex_StyleCore.lua`, and `Reflex_ColorCore.lua` own UI tokens, drawing helpers, fonts, and colors.
- `icons/` contains package assets and must stay listed in `@provides`.

The `Reflex_*.lua` core names are intentional historical/shared-core names. Do not rename them unless the package metadata, require paths, installed files, and Reflex-port plan are updated together.

## Reflex Relationship
- Reflex has its own embedded Navigator. Track Navigator is the standalone public package derived from the same NAV concepts.
- Use `/Applications/Reaper/Scripts/Tycho/Reflex` as read-only reference for shared behavior, helper patterns, and existing NAV expectations.
- Do not edit Reflex during Track Navigator work unless the user explicitly asks for a Reflex port.
- When a Track Navigator change affects shared NAV semantics, note whether Reflex should receive the same change in a separate Reflex task.
- When porting to Reflex before Reflex is moved into this repo, switch roots, read Reflex `AGENTS.md` and `PROJECT_KNOWLEDGE.md`, and follow Reflex rules such as its version bump and file-scope function constraints.
- When Reflex eventually lives inside this ReaPack repo, keep Reflex package knowledge in `Reflex/PROJECT_KNOWLEDGE.md` and continue treating Track Navigator and Reflex as separate release surfaces.

## UI Shorthand
- `NAV.pill`: top-level track pill/button.
- `NAV.dot`: compact top-level track dot/button.
- `NAV.arr`: expand/collapse arrow region.
- `NAV.menu`: global right-click/options menu.
- `NAV.help`: Help / Manual popup from NAV.menu.
- `NAV.R`: Routing View button.
- `NAV.A`: Active Tracks View button.
- `TLT`: top-level track.

Use this shorthand in discussion and bug reports.

## Modifier Behavior
- Click `NAV.pill` / `NAV.dot`: show only this TLT; subsequent clicks expand/collapse if the track is a folder.
- Cmd-click on macOS / Ctrl-click on Windows: add/remove this TLT from the visible set.
- Cmd+Shift-click on macOS / Ctrl+Shift-click on Windows: show all tracks.
- Opt-click on macOS / Alt-click on Windows: pin/unpin this TLT.
- Opt+Cmd-click on macOS / Alt+Ctrl-click on Windows: expand/collapse this TLT and children, if folder, without affecting visibility of other TLTs.
- Shift-click: range behavior.

Important macOS detail: standalone Track Navigator can report Cmd-click as raw Ctrl (`mods=0x1000`, `Key_LeftCtrl=1`). `TrackNavigatorModState()` treats that Ctrl path as primary/Cmd on macOS. Do not remove this behavior without retesting Cmd-click and Cmd+Shift-click in standalone Track Navigator.

## Docking
- Track Navigator v1.1 added standalone docking controls in `NAV.menu`:
  - `Float window`
  - `Dock left`
  - `Dock right`
  - `Dock top`
  - `Dock bottom`
  - `Quit Track Navigator`
- Docking is requested with `ImGui_SetNextWindowDockID` before `ImGui_Begin`.
- Docking availability is enabled through ReaImGui config flags when supported.
- Docked state is detected with `ImGui_IsWindowDocked` / `ImGui_GetWindowDockID`.
- Floating windows use more rounded corners; docked windows use square corners.

## ReaPack Release Workflow
1. Make code changes.
2. Update version metadata if releasing.
3. Run `git diff --check`.
4. Run `~/.gem/ruby/2.6.0/bin/reapack-index --check`.
5. Commit code changes.
6. Run `~/.gem/ruby/2.6.0/bin/reapack-index --scan --no-commit`.
7. Inspect `index.xml` for the expected version and commit-pinned source URLs.
8. Run `~/.gem/ruby/2.6.0/bin/reapack-index --check` again.
9. Commit `index.xml`.
10. Push `main`.
11. Verify the live raw index URL shows the expected version.

## Validation Checklist
- ReaPack synchronize on macOS and Windows.
- Install/update Track Navigator from the Tycho ReaPack repo.
- Launch standalone Track Navigator.
- Test `NAV.pill` and `NAV.dot`:
  - click show-only and folder expand/collapse
  - primary-click add/remove
  - primary+Shift show all tracks
  - Opt/Alt pin behavior
  - Opt+Cmd / Alt+Ctrl child expand/collapse
  - Shift range behavior
- Test `NAV.menu`:
  - Help / Manual opens/closes
  - Show all tracks
  - Dock left/right/top/bottom
  - Float window
  - Quit Track Navigator while docked
- Confirm installed script shows the expected public version.

## Known Notes
- ReaPack or REAPER may show stale package metadata after repository changes. On the affected machine, remove the Tycho repo, delete the Tycho cache XML under the local ReaPack cache folder, re-import the raw URL, and synchronize.
- No standalone Lua interpreter is guaranteed on the Mac workspace; use REAPER runtime testing plus `git diff --check` and `reapack-index --check`.
