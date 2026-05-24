# Track Navigator Project Knowledge

Current public version: 1.2.12

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
- The user's normal Track Navigator toolbar/action should run `/Applications/Reaper/Scripts/Tycho/reapack/Track Navigator/Track Navigator.lua`.
- Do not use `/Applications/Reaper/Scripts/Tycho ReaPack/Track Navigator`; that stray stale copy was archived on 2026-05-24 under `/Applications/Reaper/Scripts/Tycho cleanup archive 2026-05-24/Tycho ReaPack.stale-track-navigator-1.4`.
- `Reflex/Navigator.lua` belongs to the Reflex package as a NAV-only Reflex harness. It is not the public spin-off Track Navigator script.

## Versioning
- Public Track Navigator versions use patch numbers for tiny fixes, such as `1.2.1` or `1.2.2`. Reserve whole minor bumps such as `1.3` for more meaningful user-facing releases.
- Do not use Reflex `v20.xxx` version numbers for this package.
- On each release, update all three:
  - `Track Navigator/Track Navigator package.lua` `@version`
  - `Track Navigator/Track Navigator.lua` header `Version:`
  - `TRACK_NAVIGATOR_VERSION`
- After release changes, regenerate and verify `index.xml`.

## File Layout
- `Track Navigator.lua` bootstraps ReaImGui, loads the optional user theme, installs shared cores, owns standalone window lifetime, and passes standalone callbacks into `Reflex_NavViewCore`.
- `actions/` contains ReaPack-visible helper actions. These actions send one-shot commands through the `track_navigator_external_command` ExtState key; the running standalone Track Navigator consumes them on its defer loop. Most helper actions no-op if Track Navigator is not running rather than leaving stale commands; `Focus Search` is the exception and launches Navigator before focusing the search row.
- `core/Reflex_NavViewCore.lua` draws NAV UI: NAV buttons, global NAV.menu, TLT context menus, Help / Manual, docking menu, and the main NAV list.
- `core/Reflex_NavActionCore.lua` owns NAV visibility actions.
- `core/Reflex_ViewModes.lua` owns Routing, Selected, Armed, and Active view modes.
- `core/Reflex_ViewHistory.lua` owns view history state.
- `core/Reflex_NavTreeCore.lua` owns GUID-keyed Navigator tree disclosure persistence.
- `core/Reflex_PinCore.lua`, `Reflex_NavExclusionCore.lua`, and `Reflex_NavInclusionCore.lua` own pin/hidden/manual visibility and custom-set persistence.
- `core/Reflex_FontCore.lua`, `Reflex_StyleCore.lua`, and `Reflex_ColorCore.lua` own UI tokens, drawing helpers, fonts, and colors.
- `icons/` contains package assets and must stay listed in `@provides`.

The `Reflex_*.lua` core names are intentional historical/shared-core names. Do not rename them unless the package metadata, require paths, installed files, and Reflex-port plan are updated together.

## Reflex Relationship
- Reflex has its own embedded Navigator. Track Navigator is the standalone public package derived from the same NAV concepts.
- Use `/Applications/Reaper/Scripts/Tycho/reapack/Reflex` as the Reflex reference for shared behavior, helper patterns, and existing NAV expectations.
- Do not edit Reflex during Track Navigator work unless the user explicitly asks for a Reflex port.
- When a Track Navigator change affects shared NAV semantics, note whether Reflex should receive the same change in a separate Reflex task.
- When porting to Reflex, stay in this ReaPack repo, read `Reflex/PROJECT_KNOWLEDGE.md`, and follow Reflex rules such as its version bump and file-scope function constraints.
- Keep Track Navigator and Reflex as separate release surfaces even though they are developed from one repo and share NAV behavior.

## UI Shorthand
- `NAV.pill`: top-level track pill/button.
- `NAV.dot`: compact top-level track dot/button.
- `NAV.arr`: expand/collapse arrow region.
- `NAV.menu`: global right-click/options menu.
- `NAV.help`: Help / Manual popup from NAV.menu.
- `NAV.A`: Active Tracks View button.
- `NAV.S`: Selected Tracks View button.
- `NAV.R`: Routing View button.
- `TLT`: top-level track.

Use this shorthand in discussion and bug reports.

## NAV Label Layout
- Expanded `NAV.pill` labels clip to a shared UTF-8 character count. If any visible TLT label loses characters at the current width, that fitted count becomes the frame's lowest common denominator and all longer TLT labels clip to the same count. Do not return to independent per-label pixel clipping; proportional glyph widths made adjacent pills show uneven one/two/three-letter remnants while resizing horizontally.

## TLT Tree Disclosure
- Tree disclosure is Navigator-only state. It must not change REAPER TCP visibility or folder compact state.
- `core/Reflex_NavTreeCore.lua` owns GUID-keyed disclosure persistence in project ExtState. It separates explicit per-track expansion (`nav_tree_expanded`) from temporary sibling-layer overrides (`nav_tree_layer_overrides`).
- Normal TLT body clicks keep the existing show/hide/select/solo behavior. Opt/Alt-click on the TLT body still pins/unpins. The pin indicator itself remains inert.
- Tree expansion is only through the right-side disclosure arrow. Normal arrow click toggles that TLT's Navigator children and updates explicit expansion state.
- Double-clicking an expandable TLT body is equivalent to clicking its disclosure arrow: it toggles Navigator child expansion/collapse without changing track visibility. If the TLT is inactive/hidden, double-clicking expands or collapses its Navigator children only; it does not show-only or add that TLT to the current REAPER view.
- Opt/Alt-click on the arrow applies the opposite of the clicked TLT's current disclosure state to the current sibling generation only: root TLT siblings at the top level, or expandable siblings at the same depth under the same visible parent. It must include the clicked TLT, must not recursively open every descendant in a large project, and manual deeper expansions should be remembered across these layer toggles.
- Pinned descendant visibility outranks collapse. If a pinned child is inside a collapsed branch, render the minimal ancestor path needed to explain it. These path ancestors are still normal clickable TLT rows. Partial path rows rest with the quiet inherited-pin circle and reveal the active right-arrow disclosure on hover.
- Plain-clicking a nested tree child must solo visibility within its visible root/parent context. Do not treat "only one top-level TLT is visible" as meaning a nested child is already alone; sibling visibility inside that root must also be checked.
- `Collapse all` in `NAV.menu` and TLT context menus clears explicit expansion and layer override state only. It must not clear pins or custom visibility rules.
- Custom visibility is structural, not disclosure state: `Hide in Track Navigator` removes the TLT/subtree; `Hide in Track Navigator - show children` grafts direct children upward; `Show selected tracks` creates promoted aliases that should resolve into their natural context as ancestors become visible.
- Promoted deep rows should appear under the nearest visible ancestor rather than at true full depth when intermediate ancestors are hidden. Avoid duplicates: a promoted alias should disappear once the same track is represented by the structural tree.
- `Indent TLTs` in `NAV.menu` controls child-row indentation and defaults on. When off, hierarchy and disclosure state remain structural but all TLT buttons draw flush with the top-level row x-position. Default unmirrored TLTs indent from the left and put colored circles on the left. `Flip indent` keeps the left edge fixed and indents from the right edge instead; it must shorten the pill without changing the internal mirror phase. Tree arrows live opposite the colored dot in both mirrored and non-mirrored layouts.
- `Enable TLT expand` in `NAV.menu` gates the disclosure prototype. When off, the Track Navigator list returns to legacy flat top-level/custom visibility behavior with no tree arrows or expandable child rows.

## TLT Search
- `Show search` in `NAV.menu` controls the search row. When off, when Navigator is collapsed, or when the expanded TLT lane is narrower than 125 Retina pixels, the search row must not draw and must not leave its 12 px search gaps behind.
- The search row is visually a TLT pill: same height, shape, and TLT title font, with `#2e3033` background. It has exactly 12 Retina pixels above and below it while visible.
- Search text uses the same color as expanded TLT name text; recognized operators tint amber. The input caret uses `#5e5f64` and selected text background is grey, not ImGui blue.
- Normal search is a case-insensitive literal substring filter: entering `text` behaves like `*text*`. Slash-prefixed search terms are reserved for operators and do not perform track-name matching. `/pin` shows only pinned tracks as a flat search-style TLT list with no tree context rows; plain `pin` remains a normal substring search for track names.
- `Show pinned only` in `NAV.menu` is a quick search macro. It enables the search row if needed, writes `/pin` into it, and clears that token when toggled off.
- Cmd+F while Track Navigator is focused opens/focuses the TLT search row. The `Track Navigator - Focus Search` helper action sends the same command; if Track Navigator is not running, it launches the standalone script and focuses search on startup.
- Search text filters into a flat result list of matching tracks. Matching result rows can still expose Navigator-only disclosure arrows when `Enable TLT expand` is on; search does not add pinned descendant paths for non-matching pinned tracks.
- Search results target the real REAPER tracks for normal click, Cmd/Ctrl-click, shift range, and Opt/Alt pin behavior. Descendant search rows must use actual visible-in-TCP-with-visible-parents state, not top-level-only visibility checks.
- Esc clears active search text/state before the standalone wrapper can use Esc to quit. The right-side `X` clear affordance lives in the search pill's right cap; X and Esc both clear search and release text focus without changing custom visibility, pins, or tree disclosure.

## TLT Custom Set
- The custom set is a per-project GUID-keyed membership list (`nav_custom_set`) separate from pins, hidden/promoted state, and manually shown tracks.
- TLT context menus expose `Add to custom set` / `Remove from custom set`. `NAV.menu` exposes `Add selected to custom set`, `Clear custom set`, a removable `Custom set` section, and `Show custom set`.
- Opt+Shift-click on macOS / Alt+Shift-click on Windows on a `NAV.pill` / `NAV.dot` toggles that track's custom-set membership without changing TCP/Mixer visibility. The same chord on `NAV.arr` toggles `Show custom set`.
- `Show custom set` is a Navigator render mode: it shows only custom-set members as a flat search-style TLT list. It must not pin tracks and must not directly change REAPER TCP/Mixer visibility.
- Clearing the custom set must also turn off `Show custom set` so the Navigator never remains filtered to an empty set. Removing the final custom-set member should also exit the mode, and a saved empty custom set should normalize the mode off on startup.
- Custom-set rows target their real tracks and should keep normal TLT interaction semantics: click solo/show, Cmd/Ctrl add/remove, Shift range, Opt/Alt pin.
- Normal search text filters the custom set while `Show custom set` is active. `/pin` remains an explicit operator for pinned tracks and is not the custom-set mechanism.
- `Reset custom visibility` should not clear the custom set; use the `Custom set` section clear button for that.

## TLT Tree Arrow Layout
- TLT disclosure arrows use the same `▶` / `▼` NAV arrow glyphs as `NAV.arr`; do not replace them with a custom triangle.
- Tree arrows and pin indicators target `14x14` Retina pixels. Treat these as literal screen-pixel measurements converted with `NavRetinaPx`, not as `S()` design-unit values.
- The pin indicator is always centered inside the colored track circle, including expanded, mirrored, indented, and minimized TLT states. It uses the resolved TLT body color so it reads as a cut-out: opaque `C.bg` when active/hovered and `#2e3033` when faded/inactive. It never reserves side-lane text space or draws as a separate amber side dot.
- Custom-set membership draws `icons/Nav.CustomSet.Asterisk.png` tinted `#1485e0` in the tree-arrow control lane at 16 Retina pixels. If no tree arrow is present, it uses the would-be arrow slot. If a tree arrow is present, the asterisk moves inward with a fixed 15 Retina-pixel gap from the arrow slot and must not move when the arrow glyph changes direction or becomes the partial-path circle.
- Partial pinned-descendant paths rest as a quiet `15x15` Retina-pixel circle in `#3e3e3e`. Hovering the TLT reveals the normal right-arrow partial indicator using the active arrow styling.
- The arrow right edge sits 25 Retina pixels from the TLT pill's right edge.
- The arrow glyph has built-in text/advance padding, so `CalcTextSize` does not equal visible triangle pixels. Size against rendered screenshots when tuning; the current code compensates the glyph font size while keeping layout and hit geometry on the 14px indicator slot.
- The TLT title clips before the tree arrow with the same style as the old title clipping; pin state must not change the text limit.
- The arrow hit target is the pill's full arrow-side cap plus a small inward allowance. It should be easy to click without stealing normal body clicks left of that region.
- In expanded TLT rows, the colored endcap is its own locate/track-selection target from the colored circle's inner edge through the pill edge. Hover shows the hand cursor. Plain click selects the real REAPER track and scrolls TCP to it; Cmd-click on macOS / Ctrl-click on Windows toggles the track in the REAPER track selection; Shift-click selects the TCP-visible range from the last endcap selection anchor; primary+Shift adds that range. Opt/Alt-click in the colored endcap must not select the REAPER track; it follows normal TLT modifier behavior and pins/unpins the TLT. If the clicked track is hidden or inside a hidden/collapsed parent chain, reveal the target and required parents first, push view history, and do not solo/show-only the TLT. This must work symmetrically in mirrored mode.
- TLT context menus include `Show children` for folder tracks. It adds the TLT's direct children as manual Track Navigator buttons, like selecting those child tracks and using `Show selected tracks`, while leaving the parent TLT visible. It does not change REAPER TCP/Mixer visibility or Navigator tree disclosure state. This is useful when `Enable TLT expand` is off and should remain non-conflicting when it is on.
- Collapsed arrow: points right, rest color `#23262a`, hover color `#393a3d`; inactive TLT arrows use `#3d3d3d`. Expanded arrow: points down and uses `#515151`. Partial/pinned-path hover arrow: points right, active color `#393a3d`.
- After changing TLT arrow layout, reload Track Navigator in REAPER and, if spacing is disputed, use screenshot-based pixel measurement before further tuning.

## A/S/R View Buttons
- `NAV.A`, `NAV.S`, and `NAV.R` are special view modes. On entry, each captures the current TCP/Mixer visibility snapshot, folder compact state, selected-track set, inspector/flow state, and TCP vertical scroll; on exit, that state is restored. Horizontal arrange scroll/zoom is captured but restored only when `Recall arrange view` is enabled in `NAV.menu`.
- When applying any A/S/R view, expand every shown folder and every parent folder of every shown track, even when that parent folder is not itself shown. REAPER will not render a visible child track inside a collapsed parent.
- While an A/S/R mode is active, plain-click its button restores the previous view. Opt/Alt-click recalculates the active mode in place: `NAV.A` rescans active tracks, `NAV.S` rebuilds from the current REAPER track selection, and `NAV.R` rebuilds routing from the current REAPER track selection.
- `NAV.S` shows only the currently selected REAPER tracks. It deliberately does not add parent folders, children, routing context, or active-signal context.
- `NAV.R` walks routing directionally: downstream follows sends and main-send folder parents from the selected track(s), upstream follows receives and main-send-enabled folder children into the selected track(s). Receive-side source tracks must not expand into their unrelated downstream sends or parent folders. When the selected source is a folder, receives into routed child tracks count as upstream contributors to that selected folder, including sidechain-channel receives.
- Track Navigator fixes `NAV.R` routing depth at one hop. Do not load or expose the old Reflex `routing_depth` preference in the standalone package.
- `NAV.A` peak polling is intentionally throttled for large templates. Revisit this after real 1000+ track session testing; if it is still measurable, prefer adaptive scan intervals before adding a UI option that removes the Active Tracks View button.
- Keep the three controls grouped in A/S/R order. Wide expanded mode pins all three to the top row. When width gets tight, all three drop together to row 2; then A stays on row 2 while S/R drop together to row 3; then A, S, and R stack individually. Collapsed mode follows the same A/S/R grouping before TLT dots.
- A/S/R labels are image assets in `icons/`, not live text. Do not tune normal A/S/R centering with fallback text nudges; create or edit the PNG asset so it uses the same `NavDrawArLabelImage` path as the other buttons. `Nav.Select.S.png` uses alpha bounds `24,23,39,41` in a 64x64 source, matching A/R's vertical placement.

## View History
- Standalone Track Navigator shows Previous/Next view buttons in the bottom-left corner when `Show history buttons` is enabled in `NAV.menu`. They mirror the A/S/R button geometry: same diameter, horizontal gap, row cadence, and stack behavior. When the width cannot fit both buttons side by side, Back is the first row and Forward is the row below.
- History buttons reserve bottom space from the standalone NAV list. As the window gets shorter, the gap between the final visible TLT row and the history buttons shrinks until the list scrolls.
- A direction with no available history uses Reflex's disabled history look. An available history direction rests as a dimmed A-colored button and hovers into the normal available view-mode treatment.
- View history snapshots include REAPER TCP/Mixer visibility, folder compact state, selected tracks, TCP/arrange work state, Navigator tree disclosure/layer overrides, pins, hidden/promoted/manual visibility, custom set membership/mode, and TLT search text.
- Tree disclosure changes push history before they mutate state, including `Collapse all`, so Back can recover an accidentally collapsed Navigator tree.
- Track Navigator exposes `History Back` and `History Forward` helper actions. They send commands through the running standalone action bridge so user-bound REAPER shortcuts work even when the Navigator window is not focused. The standalone window must keep keyboard passthrough active so these shortcuts reach REAPER unless an ImGui item is actively editing/dragging.

## ReaPack Actions
- Track Navigator exposes ReaPack-visible actions for `NAV.A`, `NAV.S`, and `NAV.R`: `Enable`, `Rebuild`, and `Exit`. Enable enters only when inactive; Rebuild matches the Opt/Alt-click behavior; Exit restores the saved pre-entry view when that mode is active.
- Track Navigator also exposes action-only Armed View actions: `Enable`, `Rebuild`, `Exit`, and `Toggle`. Armed View has no UI affordance for now, captures/restores state like A/S/R, and shows only currently record-armed tracks.
- Track Navigator exposes action-only History Back and History Forward commands that target the running standalone history stack.
- `Track Navigator - Scroll to Record Armed Tracks` selects and scrolls TCP to the first record-armed track by track number without entering Armed View.
- Track Navigator also exposes `Show Only TLT 01..10` actions. These target the first ten non-auto-ignored natural top-level folders in the current NAV list and call the same plain-click path as a normal TLT button, preserving Navigator's solo-visibility behavior.
- The standalone script self-registers helper actions on startup with `AddRemoveReaScript` so local working copies under `Tycho/reapack` expose the same helper actions as ReaPack-installed copies.
- `Track Navigator - Focus Search` opens/focuses the TLT search row and is allowed to launch the standalone Navigator when it is not already running. Other helper actions remain running-instance-only.
- The helper action files are intentionally thin command senders. Keep Navigator behavior in the running standalone script and shared cores so toolbar/MIDI actions and mouse UI stay consistent.

## Tooltips
- `NAV.menu` has a `Modifier key tooltips` option (`helper_tooltips`) for verbose shortcut/helper tooltips. It defaults off and sits directly above `All tooltips`, with no separator between those options and `Help / Manual`.
- `All tooltips` (`track_navigator_tooltips`) disables every Track Navigator tooltip when off.
- In `NAV.menu` global options, `Ignore ARCHIVE` sits below `Esc key to close`; `Indent TLTs`, `Flip indent`, and `Mirror TLT buttons` are a separated group; `Show search` and standalone `Show history buttons` are the final rows of that options section.
- With modifier-key tooltips off, expanded `NAV.pill` simple track-name tooltips should appear only when the drawn label is clipped down to two UTF-8 characters or fewer. Collapsed `NAV.dot` tooltips still show the track name because dots have no visible label.
- TLT tooltip titles show the REAPER track number prefix plus the full track name, e.g. `45: Synths`; the number prefix uses the normal TLT name color and the track name is white.

## Custom Visibility
- `NAV.menu` exposes three selected-track actions: `Show selected tracks`, `Hide selected tracks`, and `Hide selected & show descendants`.
- `Show selected tracks` can add any allowed selected REAPER track as a manual NAV button. `Hide selected tracks` and `Hide selected & show descendants` apply only to selected eligible natural TLTs, matching the per-TLT right-click rules.
- The custom visibility recovery sections are `Manually shown tracks`, `Hidden tracks`, and `Showing descendants instead`. Each section has an `X` clear-all button. All close/clear `X` buttons use the shared drawn cross with rest color `#4c4e53` and a one-screen-pixel optical nudge up/left; the Options close button uses the same cross at a bolder stroke. Row labels include the REAPER track number prefix (`T26`) and clip track names to 16 UTF-8 characters plus `...`.
- The show-descendants rule uses the existing `nav_excluded` behavior: hide the parent TLT button and promote direct children as NAV buttons.

## Modifier Behavior
- Click `NAV.pill` / `NAV.dot`: show only this TLT; subsequent clicks expand/collapse if the track is a folder.
- Cmd-click on macOS / Ctrl-click on Windows: add/remove this TLT from the visible set. This additive visibility toggle preserves the current REAPER track selection and TCP vertical scroll; it must not select or scroll to the newly shown TLT.
- Opt+Shift-click on macOS / Alt+Shift-click on Windows: add/remove this TLT from the custom set without changing track visibility. The same chord on `NAV.arr` toggles `Show custom set`.
- Cmd+Shift-click on macOS / Ctrl+Shift-click on Windows: show all tracks.
- Opt-click on macOS / Alt-click on Windows: pin/unpin this TLT.
- Pins are absolute visibility rules for the pinned button only, not its descendants. After project-state changes such as REAPER undo/redo, Track Navigator should reconcile pinned GUIDs back to visible without creating a separate Navigator history action.
- Opt+Cmd-click on macOS / Alt+Ctrl-click on Windows: expand/collapse this TLT and children, if folder, without affecting visibility of other TLTs.
- Shift-click: range behavior. TLT body range selection uses a GUID-backed anchor from the last plain or primary body click; repeated Shift-clicks keep that anchor so extending a range behaves like TCP selection. Range selection shows only the rows inside the range plus required parent folders; a folder row inside the range must not automatically show all of its descendants.

Important macOS detail: standalone Track Navigator can report Cmd-click as raw Ctrl (`mods=0x1000`, `Key_LeftCtrl=1`). `TrackNavigatorModState()` treats that Ctrl path as primary/Cmd on macOS. Do not remove this behavior without retesting Cmd-click and Cmd+Shift-click in standalone Track Navigator.

## Standalone Window And Docking Lessons
- Docking is requested with `ImGui_SetNextWindowDockID` before `ImGui_Begin`.
- Docking availability is enabled through ReaImGui config flags when supported.
- Docked state is detected with `ImGui_IsWindowDocked` / `ImGui_GetWindowDockID`.
- Track Navigator is currently designed as a vertical navigator. Standalone docking controls should remain side-only until a horizontal layout exists. The current `NAV.menu` dock pad uses left/right arrow buttons plus a center `Dock` / `Undock` button.
- The center `Dock` action should dock to the last known side dock when available, otherwise left. Do not restore top/bottom dock IDs from history while horizontal mode is unsupported.
- Resolve side dock targets from `DockGetPosition`; do not blindly send `ImGui_SetNextWindowDockID` to hardcoded fallback docker indices. On installs with no left/right docker, only provision the expected side docker when SWS config helpers are available; otherwise keep the dock control disabled instead of docking somewhere arbitrary.
- `Quit` belongs at the bottom of the standalone global menu. The old `Current:` dock status is not useful user-facing information and should stay out of the UI.
- In standalone `NAV.menu`, the bottom action cluster is `Show all tracks`, dock controls, then `Quit`. `Show all tracks` keeps the separated section above the cluster; the dock controls have no visible separators above or below, just dock-only separator-height gaps reduced by 5 px.
- `Esc key to close` is a standalone global option. When disabled, the main script ignores Esc for quitting. When enabled, Esc closes active NAV/help/TLT popups first and only quits the standalone script when no NAV popup was active in the current or previous frame. Popup activity is reported from `Reflex_NavViewCore` to the standalone wrapper instead of relying only on generic `IsPopupOpen(...AnyPopup...)` timing.
- Standalone Track Navigator needs a single-instance guard. Re-running the action without one can leave older deferred ImGui contexts alive, making layout tests appear unchanged or inconsistent.
- Mac side-dock gap compensation is Reapertips-theme-only. `TrackNavigatorIsReapertipsTheme()` reads REAPER's active color theme filename via `GetLastColorThemeFile()` and enables the measured spacer compensation only when the name contains `reapertips`. Other themes use the normal edge gap with no side-dock body/header offsets.
- Reapertips mac side-dock gap compensation has separate layout layers:
  - `NAV.pill` / TLT rows are anchored inside the `##nav_scroll` child in `core/Reflex_NavViewCore.lua`. Parent cursor nudges before `NavDrawSection` do not move these rows.
  - `NAV.arr`, wrapped collapsed dots, and A/S/R controls are drawn in the parent/header layer before `##nav_scroll`.
  - Do not treat docked Navigator gaps as one margin or assume right-dock can be fixed by blindly mirroring left-dock numbers. Left dock is the measured tuned baseline; right dock needs the same layer-by-layer treatment with the inside compensation gap on the opposite side.
  - To reduce the mac-left TLT left gap while preserving the correct right gap, offset the `##nav_scroll` child left and widen it by the same amount. In the current standalone wrapper this is passed as `nav_body_x_offset = -1`.
  - Header elements need their own offsets: `nav_header_x_offset = -0.5` for `NAV.arr`/collapsed header flow, and `nav_ar_x_offset = -0.5` for fixed A/S/R alignment. On Retina this half logical px corresponds to the 1 screen px correction needed for the collapsed circle lane and fixed `NAV.R` to align with the TLT lane.
  - Mac right dock uses `WindowPadding.x = 3`, then applies the docker chrome width compensation plus one logical px, plus a 7 logical px horizontal gap correction (14 screen px on Retina). It offsets body/header by `-7` and widens by the same amount so both left and right gaps shrink while the top gap stays unchanged. It keeps `nav_ar_x_offset = -0.5` so fixed A/S/R retains the measured 1 screen px right-edge correction.
  - Do not try to fix this by changing only `WindowPadding`, `GetContentRegionAvail`, or a parent `SetCursorPosX`; those affect different layers and caused no visible TLT movement.
- When reuniting standalone Navigator with Reflex, keep these offsets as caller-provided standalone dock chrome compensation, not shared NAV behavior. Reflex's embedded Navigator should continue to pass defaults (`0`) unless its own docked gaps are independently measured as wrong.

## Floating Window Presentation
- Floating windows use rounded corners; docked windows use square corners. The floating title bar is intentionally hidden, leaving only the Navigator content and uniform padding.
- Floating internal right gap should match the left edge gap. Docked mode also keeps uniform edge gaps except for two macOS chrome compensation cases: left-side REAPER docker uses the smaller right gap, and right-side REAPER docker uses the smaller left gap, because REAPER leaves blank chrome strips against the arrange view there.
- The floating window outline is a custom 1 px line in `#525254`, not ImGui's normal border. Draw straight edges with filled rects and only use arc strokes for rounded corners. This avoids the fuzzy gradient / over-antialiased look ImGui can produce on straight lines.
- Draw the floating outline on the foreground draw list when available so it traces the whole window edge. Keep `WindowBorderSize` at zero and let the custom outline define the visible edge.
- `NAV.menu` and `NAV.help` use the same custom solid-outline path with native popup/window borders disabled, and use doubled popup outer padding so the menu content does not feel cramped. Section separators use `#262930` and draw full-width from inside outline edge to inside outline edge.
- `NAV.menu` position is seeded inside the visible work area before it opens, then corrected once after its first measured size is known. Its height is capped to the visible work area so long option stacks scroll instead of spilling off-screen. Do not clamp it continuously while visible: users must be able to drag the Options window freely past screen edges without shape jitter or resize artifacts.
- Match resize grip colors to the outline color so the lower-right handle does not fall back to ImGui blue.
- Collapsed width can become very narrow when TLTs are circles. The minimum width should be based on the minimum NAV content width plus edge padding, not a large arbitrary ImGui window minimum.
- Collapsed minimum height should follow the number of wrapped dot rows. Expanded minimum height should fit the visible NAV rows when reasonable, capped to the usable viewport so a very large project does not force an oversized window.
- Height limits should be one-way: enforce a viable minimum, but allow the user to resize the floating window taller for future tracks.
- When undocking, ReaImGui can preserve the docker height, which is usually wrong for Track Navigator. On dock-to-float transitions, snap to a meaningful floating size: use the user's last explicitly resized floating size when known, otherwise use the current content-fit/minimum viable height. Never record docked dimensions as a floating user size.
- Save floating user size only from actual floating resize gestures, not from automatic snap/auto-fit frames.

## Context Menu Access
- `NAV.menu` is normally opened by right-clicking blank Navigator space or `NAV.arr`, but at some scale and width combinations there may be no blank area left because `NAV.arr`, `NAV.A`, `NAV.S`, and `NAV.R` occupy the available surface.
- Local right-click menus such as TLT menus include a separated `Collapse all` row above a bottom separator plus `Options`. `Options` opens the global `NAV.menu`, giving users a reliable path to settings even when no blank right-click target is available.
- Opening a TLT right-click menu should close `NAV.menu` first so the local menu is never hidden under the options window.
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
  - descendant solo visibility inside a pinned TLT
  - Opt+Cmd / Alt+Ctrl child expand/collapse
  - Shift range behavior
- Test TLT tree disclosure while `NAV.pill` is expanded:
  - normal arrow click expands/collapses only that TLT's Navigator children
  - double-clicking an expandable TLT body toggles disclosure without changing visibility
  - body click outside the arrow cap keeps existing TLT visibility behavior
  - expanded colored-endcap hover shows the hand cursor in normal and mirrored mode; endcap click selects/scrolls the real REAPER track, primary-click toggles track selection, Shift selects a track-number range, and hidden targets are revealed first without soloing/show-onlying the TLT
  - TLT context menu `Show children` adds direct child tracks as manual Navigator buttons without changing REAPER visibility or Navigator tree disclosure, with `Enable TLT expand` on and off
  - Opt/Alt-click arrow applies the opposite of the clicked TLT's current disclosure state to expandable siblings at the same visible parent/depth, including the clicked TLT
  - manual deeper expansions survive sibling-layer toggles
  - pinned descendants force only the minimal ancestor path, show the quiet circle at rest, reveal the active right-arrow on hover, and do not become explicit expansion state
  - `Collapse all` clears disclosure state without unpinning or clearing custom visibility
- Test TLT search:
  - normal text matches as a case-insensitive literal substring
  - plain `pin` matches track names containing `pin`
  - `/pin` shows only pinned tracks as a flat search-style list and tints the search text amber
  - `Show pinned only` writes/clears `/pin` and enables the search row if needed
- Test custom set:
  - TLT context menu adds/removes a track from the custom set
  - Opt+Shift-click on macOS / Alt+Shift-click on Windows on a TLT adds/removes it from the custom set without changing track visibility
  - Opt+Shift-click on macOS / Alt+Shift-click on Windows on `NAV.arr` enters/exits `Show custom set`
  - custom-set member TLTs draw the `#1485e0` asterisk in the stable arrow/control lane
  - `Add selected to custom set` adds selected allowed tracks without changing visibility
  - `Clear custom set` empties the set, exits `Show custom set`, and does not touch pins or custom visibility
  - `Show custom set` displays only custom-set members as a flat TLT list
  - custom-set rows can still be clicked/soloed normally and are not pinned by membership
  - normal search text filters the custom set, and clearing the custom set leaves pins/hidden/promoted state unchanged
- Test `NAV.menu`:
  - Help / Manual opens/closes
  - Show all tracks
  - Recall arrange view option
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

## Screenshot-Based UI Diagnosis
- When UI alignment, spacing, clipping, or rendering is in question, prefer screenshot analysis over repeated verbal/pixel-measurement loops.
- The user may place screenshots on the Desktop and ask to diagnose. Use the newest Desktop image unless they name a specific file:
  `find /Users/scotthansen/Desktop -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \) -print0 | xargs -0 ls -t | head`
- Open the screenshot with `view_image` first to identify the relevant Track Navigator state: dock side, expanded/collapsed, pill/circle mode, and whether the issue is visible.
- For pixel measurements, crop the relevant area with `sips`, convert the crop to BMP if needed, then parse pixels programmatically. PNG screenshots are preferred because they preserve exact rendered pixels.
- Treat the screenshot as rendered ground truth. If code geometry and screenshot pixels disagree, assume the code path or visual layer being measured is wrong until proven otherwise.
- For Track Navigator circle/dock checks, measure the visible dark outer circle/body edge, not text labels, antialiased guide overlays, or coarse visual markers. Report concrete pixel extents such as `x=13..66` and the resulting left/right gaps.
- Avoid temporary visual guide overlays for 1 px decisions unless they are solid, 1-retina-pixel, non-antialiased, and explicitly requested. Prefer image analysis and code-coordinate dumps.

## Known Notes
- ReaPack or REAPER may show stale package metadata after repository changes. On the affected machine, remove the Tycho repo, delete the Tycho cache XML under the local ReaPack cache folder, re-import the raw URL, and synchronize.
- No standalone Lua interpreter is guaranteed on the Mac workspace; use REAPER runtime testing plus `git diff --check` and `reapack-index --check`.
