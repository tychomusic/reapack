# Track Navigator Project Knowledge

Current public version: 1.5

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

## Standalone Window And Docking Lessons
- Docking is requested with `ImGui_SetNextWindowDockID` before `ImGui_Begin`.
- Docking availability is enabled through ReaImGui config flags when supported.
- Docked state is detected with `ImGui_IsWindowDocked` / `ImGui_GetWindowDockID`.
- Track Navigator is currently designed as a vertical navigator. Standalone docking controls should remain side-only until a horizontal layout exists. The current `NAV.menu` dock pad uses left/right arrow buttons plus a center `Dock` / `Undock` button.
- The center `Dock` action should dock to the last known side dock when available, otherwise left. Do not restore top/bottom dock IDs from history while horizontal mode is unsupported.
- Resolve side dock targets from `DockGetPosition`; do not blindly send `ImGui_SetNextWindowDockID` to hardcoded fallback docker indices. On installs with no left/right docker, only provision the expected side docker when SWS config helpers are available; otherwise keep the dock control disabled instead of docking somewhere arbitrary.
- `Quit` belongs at the bottom of the standalone global menu. The old `Current:` dock status is not useful user-facing information and should stay out of the UI.
- `Esc key to close` is a standalone global option. When disabled, the main script ignores Esc for quitting. Earlier attempts to make Esc close nested globals/help before quitting were unreliable and were removed.

## Floating Window Presentation
- Floating windows use rounded corners; docked windows use square corners. The floating title bar is intentionally hidden, leaving only the Navigator content and uniform padding.
- Floating internal right gap should match the left edge gap. Docked mode also keeps uniform edge gaps except for two macOS chrome compensation cases: left-side REAPER docker uses the smaller right gap, and right-side REAPER docker uses the smaller left gap, because REAPER leaves blank chrome strips against the arrange view there.
- The floating window outline is a custom 1 px line in `#525254`, not ImGui's normal border. Draw straight edges with filled rects and only use arc strokes for rounded corners. This avoids the fuzzy gradient / over-antialiased look ImGui can produce on straight lines.
- Draw the floating outline on the foreground draw list when available so it traces the whole window edge. Keep `WindowBorderSize` at zero and let the custom outline define the visible edge.
- Match resize grip colors to the outline color so the lower-right handle does not fall back to ImGui blue.
- Collapsed width can become very narrow when TLTs are circles. The minimum width should be based on the minimum NAV content width plus edge padding, not a large arbitrary ImGui window minimum.
- Collapsed minimum height should follow the number of wrapped dot rows. Expanded minimum height should fit the visible NAV rows when reasonable, capped to the usable viewport so a very large project does not force an oversized window.
- Height limits should be one-way: enforce a viable minimum, but allow the user to resize the floating window taller for future tracks.
- When undocking, ReaImGui can preserve the docker height, which is usually wrong for Track Navigator. On dock-to-float transitions, snap to a meaningful floating size: use the user's last explicitly resized floating size when known, otherwise use the current content-fit/minimum viable height. Never record docked dimensions as a floating user size.
- Save floating user size only from actual floating resize gestures, not from automatic snap/auto-fit frames.

## Context Menu Access
- `NAV.menu` is normally opened by right-clicking blank Navigator space or `NAV.arr`, but at some scale and width combinations there may be no blank area left because `NAV.arr`, `NAV.R`, and `NAV.A` occupy the available surface.
- Local right-click menus such as TLT menus include a bottom separator plus `Options`. `Options` opens the global `NAV.menu`, giving users a reliable path to settings even when no blank right-click target is available.
- Keep this as a deliberate fallback action, not a replacement for item-specific context menus. The item menu should retain its local actions first, then expose `Options` at the bottom.

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
  - Dock left/right and Undock
  - Esc key to close option
  - Quit while docked
  - TLT context menu bottom `Options` opens global `NAV.menu`
- Test floating window behavior:
  - right gap matches left gap when undocked
  - outline traces rounded corners without fuzzy straight edges
  - resize grip matches outline color
  - undock snaps to content-fit height or remembered floating user size
- Confirm installed script shows the expected public version.

## Known Notes
- ReaPack or REAPER may show stale package metadata after repository changes. On the affected machine, remove the Tycho repo, delete the Tycho cache XML under the local ReaPack cache folder, re-import the raw URL, and synchronize.
- No standalone Lua interpreter is guaranteed on the Mac workspace; use REAPER runtime testing plus `git diff --check` and `reapack-index --check`.
