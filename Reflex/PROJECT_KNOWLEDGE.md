# Reflex — Project Knowledge

## What is Reflex

Reflex is a standalone ReaImGui script for REAPER providing track visibility/collapse management, a track inspector with FX chain display, A/B compare system, volume/pan controls, envelope management, inline routing panel, FX plugin browser, routing view, sends view, flow view, send topology view, view history, noise floor detection, and a configurable macro pad (Remote) with pages. It is a companion to the Realist live performance system for Tycho.

**Current version: v20.672** (~10,700-line main script; I/O Manager split into shared core modules)

**Dependencies:** REAPER's built-in Lua 5.4, ReaImGui 0.10+. SWS still exists in some Reflex-only legacy paths (`BR_GetMediaTrackSendInfo_Track` in routing panels/send topology and `BR_GetMediaTrackSendInfo_Envelope` for send envelope matching), but standalone Navigator's `NAV.R` no longer requires SWS as of v20.662 / Navigator v20.662; it uses native `GetTrackSendInfo_Value(..., "P_DESTTRACK"/"P_SRCTRACK")` only. Prefer native REAPER/Lua APIs over SWS wherever they can provide the same behavior.

**File-scope functions:** use global assignment pattern (`myFunc = function() end`). Do not use `local function` at file scope.

---

## ReaPack Package Notes

Read repo-level `../PROJECT_KNOWLEDGE.md` first for ReaPack-wide workflow and cross-package rules.

- Working repo: `/Applications/Reaper/Scripts/Tycho/reapack`
- Live/local test path: `/Applications/Reaper/Scripts/Tycho/reapack/Reflex`
- Package path: `Reflex/`
- Package metadata: `Reflex/Reflex package.lua`
- Main script: `Reflex/Reflex.lua`
- Public version: `20.672`
- Author metadata: `S.Hansen / Tycho`
- Release package excludes generated/user-local state files such as `remote_buttons.txt`, `remote_pages.txt`, and `fx_browser_action.txt`.
- The user's normal Reflex toolbar/action should run `/Applications/Reaper/Scripts/Tycho/reapack/Reflex/Reflex.lua`.
- `Reflex/Navigator.lua` is a NAV-only Reflex harness for isolating embedded Navigator behavior during development. It is not the public spin-off Track Navigator script; when the user says "Track Navigator", use `/Applications/Reaper/Scripts/Tycho/reapack/Track Navigator/Track Navigator.lua`.
- Reflex no longer loads external theme files. The former tested `Reflex_Theme.lua` values are embedded in `Reflex.lua`, `Navigator.lua`, and `Reflex_IOManager.lua`; future user-facing UI customization belongs in an Options GUI.
- Reflex user-local state files (`remote_buttons.txt`, `remote_pages.txt`, `fx_browser_action.txt`) now live in `/Applications/Reaper/Scripts/Tycho/reapack/Reflex` for local testing and are locally ignored via `.git/info/exclude`.
- The older `/Applications/Reaper/Scripts/Tycho/Reflex` folder is no longer the source of truth for development. It was archived on 2026-05-24 under `/Applications/Reaper/Scripts/Tycho cleanup archive 2026-05-24/Reflex.stale-20.669` along with `Reflex.bak`; use that archive only when intentionally recovering a specific old/local file.

---

## Element Naming (UI Shorthand)

Use these names when describing UI elements. Format: `SECTION.element`

```
NAV             Navigator section (TLT buttons / mini circles)
NAV.arr         Expand/collapse arrow
NAV.pill        TLT pill button (expanded view)
NAV.dot         TLT mini circle (collapsed view)
NAV.A/S/R       Active / Selected / Routing view mode buttons
NAV.R/F/S       Circle buttons (routing/flow/sends)

HDR             Track header box (rounded bg) — loose density
HDR.row1        Title row (num + name)
HDR.num         Track number (colored)
HDR.name        Track name
HDR.row2        Button row: [record] [mon] [M] [S] [pan] ... [V] [P] [ENV] [▶/▼]
HDR.record      Record-arm ring
HDR.mon         Record-monitor input icon, shown only when HDR.record is armed
HDR.input       Record-input selector row, shown only when HDR.record is armed
HDR.M / .S      Mute / Solo
HDR.pan         Pan value (draggable) — on row2 after record/mon/M/S

ENV.track       Track-level envelope list (between HDR and VOL when expanded)
ENV.row         Single envelope row (transparent bg, C.env_row_bg on hover)

VOL             Volume slider: combined meter+slider, solid white handle, peak display
VOL.val         dB value readout (hover bg on mouseover)
VOL.±           Increment/decrement buttons

CTRL            Controls row (below VOL)
CTRL.fxbtn      Combined ▼FX button (moves to FX area when routing open)
CTRL.add        Add FX button (+)
CTRL.route      Routing pill (add-send + circle in left endcap, 3 dots, expand arrow, right-aligned)
CTRL.add_send   Add-send (+) circle integrated into routing pill left endcap

FX              FX list area — dense density
FX.row          Single plugin row (3-state expansion: collapsed / extras / full)
FX.row2         Extras row (wet + A/B + latency, when expanded)

ROUTE           Inline routing panel (between CTRL and FX when CTRL.route expanded)
ROUTE.sends/recvs/hw  Section dropdowns (amber/red/grey)
ROUTE.row       Send/receive/hw item row (sorted by track number, displayed as "5: Returns")

FLOW.btn        ▶ FLOW toggle button (FX-style, right-aligned on bottom row, outside card)
CMP             Compare controls (A/B pill + mode + float, right-aligned, outside card)

SEND            Send topology section (folder cards + return modules + distant sends)
SEND.folder     Folder card (DrawSendFolderCard — spanning, click title or body to expand; title is also a locate link)
SEND.folder.title  Folder name row (locate link; body click also toggles expand/collapse)
SEND.folder.M/S    Folder mute/solo (left-aligned, top-aligned with knob tops when wide)
SEND.col        Return module column (DrawCompactTrackColumn)
SEND.col.snd    SND header (▶/▼ SND — full-width hit area, chevron at right endcap, tooltip "Open sending track controls")
SEND.col.title  Return module title (locate link; click also caller-handled if applicable)
SEND.col.M/S    Return mute/solo (centered pair)
SEND.distant    Distant sends (two-state only: fully open or fully closed)
SEND.distant.title Distant card title row (locate link; body click also toggles expand/collapse)
SEND.distant.sc SC badge (blue bg, right-aligned, faded when collapsed+not hovered)

CARD            Card container box (wraps track modules when opt_card_boxes)
DIV             Resize divider handle
RMT             Remote macro pad
RMT.tab         Page tab
RMT.btn         Macro button
```

**Terminology:** `TLT` means top-level track. A TLT may be a folder or a plain top-level leaf track; do not assume folder shape from the acronym. Older internal identifiers such as `top_folders`, `ShowAllTLFs`, and `ViewHistoryPushTlf` remain for compatibility and should not be renamed casually.

**Layout order (top to bottom):** NAV → [CARD: HDR → [HDR.input] → ENV.track → VOL → CTRL → [ROUTE] → FX] → FLOW → CMP → [SEND.folder → SEND.col grid] → DIV → RMT

**Density zones:** HDR = loose (`UI.pad`), FX/ENV = dense (`UI.pad_sm`), SENDS = dense

---

## File Layout

```
Scripts/Tycho/Reflex/
  Reflex.lua               Main script
  Navigator.lua            Standalone Navigator action/window (NAV section only)
  Reflex_IOManager.lua      Standalone I/O Manager action/window
  Reflex_WindowToggle.lua   FX window toggle (v1.3) — bind as REAPER action
  Reflex_HistoryBack.lua    View history back (sets ExtState, bind as REAPER action)
  Reflex_HistoryForward.lua View history forward (sets ExtState, bind as REAPER action)
  Reflex_Navigator_ArmedViewToggle.lua       Navigator Armed View toggle action
  Reflex_Navigator_ScrollToRecordArmed.lua   Select/scroll to first record-armed track action
  Reflex_NavigatorActionBridge.lua            Shared ExtState bridge for Navigator actions
  core/
    Reflex_StyleCore.lua      Shared popup/menu/tooltip style helpers used by Reflex + Navigator
    Reflex_ViewHistory.lua   View history snapshot/restore/back/forward module
    Reflex_NavActionCore.lua Shared NAV click handlers, visibility utilities, and ScrollTrackToCenter
    Reflex_NavViewCore.lua   Shared NAV.arr/NAV.dot/NAV.pill/A-S-R renderer used by Reflex + Navigator
    Reflex_NavTreeCore.lua   GUID-keyed Navigator tree disclosure persistence
    Reflex_RemoteCore.lua    Remote button/page persistence and mutation helpers
    Reflex_ViewModes.lua     Routing / Selected / Armed / Active View relationship, scan, apply, and toggle helpers
    Reflex_FlowCore.lua      Flow View chain, toggle, focus, and refresh helpers
    Reflex_FontCore.lua      Scaled font lookup and push/pop helpers
    Reflex_FXBrowserCore.lua FX browser action persistence and backend/cache helpers
    Reflex_RoutingClipboard.lua Routing clipboard backend helpers
    Reflex_RouteControlsCore.lua ROUTE.row renderer and SEND.col send-control widgets
    Reflex_RouteMenuCore.lua ROUTE.sends/recvs/hw add-menu helpers
    Reflex_RoutePanelCore.lua Expanded inline ROUTE panel renderer
    Reflex_RouteTooltipCore.lua CTRL.route persistent tooltip formatting/display helpers
    Reflex_SendTopologyCore.lua SEND topology analysis/list/group/refresh backend helpers
    Reflex_SendCreateCore.lua SEND/CTRL.route send creation and conforming Returns* helpers
    Reflex_SendFxCacheCore.lua SEND FX-name cache refresh helpers
    Reflex_SendGridCore.lua SEND section/side-column wrappers, blank cells, measurements, grouped row-grid renderer
    Reflex_SendFolderCore.lua SEND.folder card + folder-chain renderer
    Reflex_SendDistantCore.lua SEND.distant section + collapsed card renderer
    Reflex_FXChunkCore.lua   FX clipboard chunk parser/splice helpers
    Reflex_FXDragCore.lua    FX drag/drop backend, drop-target registry, and automation-strip helpers
    Reflex_FXClipboardCore.lua FX copy/cut/paste backend, carry visuals, and paste-target helpers
    Reflex_FXRowCore.lua     Shared FX.row context menu, outline, and interaction helpers
    Reflex_PinCore.lua       GUID-keyed TLT pin persistence helpers
    Reflex_NavExclusionCore.lua Excluded-TLT persistence + ghost-parent visibility sync
    Reflex_NavInclusionCore.lua Custom NAV item persistence + selected-track include helpers
    Reflex_TrackUtilCore.lua Folder child/collapse/visibility helpers
    Reflex_TrackScanCore.lua Top-folder, subgroup, song-section, render-list, and song-list scanners
    Reflex_SongCore.lua      Current-song visibility and song-section selection helpers
    Reflex_SubGroupCore.lua  Subgroup save/apply/show helpers
    Reflex_ColorCore.lua     Shared track-color conversion and FX state color helpers
    Reflex_MeterCore.lua     Shared meter color, peak smoothing, and volume knob mapping helpers
    Reflex_NoiseCore.lua     Noise-floor scan helper for settings panel
    Reflex_IOCore.lua        Shared HDR.input / I/O Manager device model, aliases, favorites, meters, and INI persistence
    Reflex_IOManagerCore.lua I/O Manager floating panel UI, table sorting/filtering/editing, and page controls
    Reflex_CompareCore.lua   A/B compare backend helpers
    Reflex_EnvelopeCore.lua  Inspector envelope cache/alias/visibility/formatting helpers
    Reflex_FXSelectionCore.lua FX multi-select state and backend helpers
    Reflex_RealistCore.lua   Realist current-song lookup and song-region view clamp helpers
  remote_buttons.txt           Remote macro pad persistence (auto-generated, not packaged)
  remote_pages.txt             Remote page definitions (auto-generated, not packaged)
  fx_browser_action.txt        Custom FX browser action ID (auto-generated, not packaged)
  icons/                       Remote button icon PNGs (3-state horizontal strips)
  icons/Nav.Active.A.png       NAV.A label image
  icons/Nav.Select.S.png       NAV.S label image
  icons/Nav.Route.R.png        NAV.R label image
  icons/Nav.CustomSet.Asterisk.png Custom-set membership marker
  icons/Tycho-Logo-dots.png    Standalone Navigator title/menu mark
  icons/rounded-arrow-down.png Flow view separator arrow (white on transparent, tinted at render)
  icons/inspect-send-arrow.png Inspect arrow (white on transparent, 28px → 14px at 2:1)
```

---

## Window Structure

```
Main Window (NoScrollbar, NoScrollWithMouse, NoCollapse, SizeConstraints)
├── Reflex section (collapsible, toggleable via Show Nav)
├── Content Child ("##content", NoScrollbar, mousewheel via ImGui)
│   ├── Inspector (toggleable via Show Inspector)
│   │   ├── CARD → HDR → [HDR.input] → ENV.track → VOL → CTRL → [ROUTE] → FX
│   │   ├── FLOW.btn, CMP (outside card)
│   │   └── Flow view chain / SENDS section
│   └── Right-click context menu
├── Bottom bar: Gear (⚙) left, Back/Forward (◀/▶) right
├── Settings panel (inline, NO BeginChild — crashes style stack)
├── DIV (draggable resize handle)
└── Remote Child ("##remote", fixed height, scrollbar stabilized)
```

---

## Inspector Architecture

| Function | Content |
|---|---|
| `InspDrawHeader` | HDR: title, record/mon/M/S, pan, record input, ENV buttons, env detail rows |
| `InspDrawVolumeSlider` | VOL: combined meter+slider, vol value, -/+ circles |
| `InspDrawControlsRow` | CTRL: routing pill (always), FX controls or empty |
| `InspDrawFXArea` | FX controls (when routing open) + FX rows, drag-reorder, overlays |
| `InspDrawTrackBlock` | Orchestrator: calls above 4 + ROUTE panel insertion |

Communication via `hdr` table returned from `InspDrawHeader` with layout, track state, sizing, rendering, and mute overlay fields.

**Inspector persists on deselection.** Clicking blank TCP keeps the last inspected track visible.

---

## Extracted Helper Functions

| Function | Purpose | Sites |
|---|---|---|
| `MuteOpts(bool)` / `SoloOpts(bool)` | NavRect opts for mute/solo buttons | 11+ |
| `PushPopupStyle()` / `PopPopupStyle()` / `PushTooltipStyle()` / `PopTooltipStyle()` / `ReflexPushPopupLayout()` / `ReflexPopPopupLayout()` / `ReflexMenuItem(label, opts)` / `ReflexPopupLabel(label, opts)` / `ReflexPopupSeparator(w, opts)` / `ReflexPopupRule(w, opts)` / `ReflexPopupStackGap(h)` / `ReflexApplyKeyboardPassthrough(opts)` | v20.584 moved shared popup/menu/tooltip styling to `core/Reflex_StyleCore.lua`; v20.586 added shared popup row geometry/label/separator primitives; v20.587 added shared keyboard passthrough helpers; v20.588 briefly added optional `hard_focus_reaper`, superseded/removed in v20.598; v20.589 made NAV popup layout explicit; v20.590 made `ReflexMenuItem` suppress ImGui's square header fill and draw a nested rounded hover/active rect itself; v20.591 centered text by measured text bounds and put NAV popup controls into the same padded row rhythm as labels/menu rows; v20.592 split static popup labels from clickable hover rows so non-button text/controls align to the separator/content edge while menu-item text keeps hover-box padding; v20.594 reverted the v20.593 symmetric popup-padding experiment because it removed too much horizontal gutter and caused content clipping; v20.595 keeps the good horizontal popup gutter and makes vertical popup gutter match it with `WindowPadding(S(10), S(10))`; v20.596 removes default vertical padding from static popup labels so the visible top label edge matches the outer popup gutter; v20.597 adds explicit no-gap rule and stack-gap primitives, and applies them to the Navigator global popup so vertical rhythm is owned by one stack model instead of hidden inside each element helper; v20.598 adds Reflex-vs-standalone NAV global menu context and removes the hard-focus keyboard passthrough path. Popup menus use `C.bg`, dim resting text, `C.fx_ctrl_hover` row hover, and `C.fx_ctrl_active` active row. Tooltips keep compact padding/rounding. | NAV global + TLT context rows; popup/tooltip helpers; Reflex/Navigator keyboard policy |
| `FxStateColors(...)` | 35-line FX color cascade → 1 call | 3 |
| `MeterColor(db)` | Meter threshold color | 5 |
| `NoiseScanAllTracks()` | v20.520. Settings-panel noise-floor scan; returns `{ track, name, peak_db }` entries sorted by peak level, using live peaks and the existing `insp_meter_noise` variance cache. | Settings "Noisy Tracks" panel |
| `SetTrackVis(track, bool)` | Paired TCP+Mixer visibility | 19 |
| `GetFontStep(offset)` / `GetSteppedFont(offset, style)` | Font step computation | 12 |
| `InspFormatSendEnvName(track, env, name)` | Send envelope display: `SND VOL - 27: Reverb` | ENV list |
| `DrawInspectArrow` / `InspectArrowButton` / `GetInspectArrowImg` | PNG inspect arrow | Send arrow sites |
| `DrawFXChainCompound` | Unified [▶ FX +] compound: collapse, chain, add, right-click menus | 3 (controls row stacked/wide, FX area) |
| `SweepDeadTrackCaches()` | Periodic cleanup of dead `MediaTrack*` pointers across 6 meter/FX caches | Loop (~every 300 frames) |
| `ViewHistoryPushTlf()` | 500ms-debounced wrapper around `ViewHistoryPush` for TLT click handlers | 2 (HandleTracksClick, HandleSongsClick) |
| `NavParamKnob(...)` | Unified vol/pan knob + Option C drag/undo. Handles track or send param via `si` arg, meter dot on vol, domain-specific drag math (dB for vol, linear+snap for pan). | 12 (folder narrow/wide × {vol,pan} + send wrap/side × {vol,pan} + return wrap/side × {vol,pan}) |
| `RouteFilterMatch` / `RouteAddMenuList` / `RouteSectionHeader(...)` | v20.528 moved to `core/Reflex_RouteMenuCore.lua`. Shared filterable add-menu shell for ROUTE.sends/recvs/hw: multi-word filtering, keyboard nav, popup stroke/background, per-popup scroll indicator state, and section header "+" button. Receives a window-height bridge for popup list sizing. | 3 (sends, recvs, hw) |
| `RouteBuildSortedTrackList(track, category)` | v20.528 moved to `core/Reflex_RouteMenuCore.lua`. Returns `{idx, name, num, nchan}` list sorted by track number for sends (category=0) or receives (category=-1). Uses `BR_GetMediaTrackSendInfo_Track` to resolve other-side tracks. | 2 (sends, recvs) |
| `DrawRouteRow` / `RouteVolValue` / `RoutePanValue` / `RouteMidiDropdown` / `DrawRouteModeDD` / `RouteChannelDropdown` | v20.527 moved shared ROUTE.row/SEND.col send-control widgets to `core/Reflex_RouteControlsCore.lua`; v20.529 moved the full `DrawRouteRow` renderer there too. Vol/pan use Option C drag commits with module-local `{before,moved}` state; `route_slider_drag_id` remains global so `DrawRouteRow` can suppress hover on other rows while dragging. | ROUTE rows; `DrawRouteModeDD` also in SEND.col SND controls |
| `DrawRoutePanel(track, bw, hdr)` | v20.531 moved to `core/Reflex_RoutePanelCore.lua`. Expanded inline `ROUTE` panel renderer: owns sends/receives/hardware section layout, add-popup contents, sorted row loops, and hardware output labels. `InspDrawTrackBlock` now just calls it when `insp_routing_expanded[track]` is true. | `InspDrawTrackBlock` |
| `FormatChanPacked` / `FormatChanHW` / `ShowRoutingTooltip` | v20.530 moved to `core/Reflex_RouteTooltipCore.lua`. Persistent `CTRL.route` hover tooltip: lists sends/receives/hardware outputs while collapsed, with muted route coloring and non-default channel arrows. | 2 (`CTRL.route` hover sites) |
| `AnalyzeSendTopology` / `DebugSendTopology` / `NavRoutingTargetTrack` / `SendsViewToggle` / `SendsViewBuildList` / `SendsViewBuildGroups` / `SendsViewRefresh` / `SendsViewCheckRefresh` | v20.532 moved to `core/Reflex_SendTopologyCore.lua`. SEND topology/list/group/refresh backend: builds `SEND.folder`, `SEND.col`, and `SEND.distant` data, preserves remote-only and SC-badge refresh behavior, and keeps the routing target policy used by SEND add panels. | SEND view button/draw loop/add panels |
| `RoutingViewGetParentChain` / `RoutingViewGetChildren` / `RoutingViewGetSendDests` / `RoutingViewGetRecvSources` | v20.518. Routing/Active View relationship helpers; build parent/child/send/receive track sets used by `RoutingViewScan` and `ActiveViewScan`. v20.661 changed send/receive track resolution to native-only `GetTrackSendInfo_Value(..., "P_DESTTRACK"/"P_SRCTRACK")`, so standalone Navigator `NAV.R` no longer needs SWS and SWS cannot mask native lookup failures during QA. | `Reflex_ViewModes.lua` |
| `ViewModeFirstTrackInSet(track_set)` / `ViewModeScrollTrackToCenter(track)` / `ViewModeDeferScroll(track)` | v20.519. View-mode post-apply scroll helpers. Routing View scrolls to `routing_view_source`; Active View scrolls to the first visible result by track number. Uses direct JS TCP scrolling without changing selection on the next defer cycle after visibility changes settle; falls back to `ScrollTrackToCenter` if JS scroll is unavailable. | `Reflex_ViewModes.lua` |
| `ArmedViewCollectTracks` / `ArmedViewToggle` / `ArmedViewRefreshFromRecordArm` / `ArmedViewExit` / `TrackNavigatorScrollToRecordArmed` | v20.668. Record-armed track view helpers shared by embedded Reflex and standalone Navigator. Armed View is command-driven; `TrackNavigatorScrollToRecordArmed` selects and scrolls to the first record-armed track without entering the view. | `Reflex_ViewModes.lua` |
| `GetInheritedSendColor` / `GetSourceSendDests` / `TrackNameStartsReturns` / `IsConformingReturnsFolderForSource` / `DetermineConformTarget` / `RoutingAddSendTrack` / `AddSendModePopup` | v20.533 moved to `core/Reflex_SendCreateCore.lua`. SEND/CTRL.route send-creation backend: conforming `Returns*` predicate, target selection, new return insertion, inside-folder closure transfer, inherited color, MIDI-off send setup, send envelope visibility, and send-mode popup. | CTRL.route add-send; SEND inside-folder add panels |
| `SendsEnsureFxNameCache(track)` / `SendsFxCachedCount(track)` | v20.538 moved to `core/Reflex_SendFxCacheCore.lua`. Shared SEND-surface FX-name cache refresh/count helpers for expanded `SEND.folder`, normal `SEND.col`, and expanded `SEND.distant` render paths. Rebuilds cleaned FX-name arrays only when count changes. | `SendsDrawFolderChain`, `SendsDrawGroupColumns`, `SendsDrawDistantSection`; `DrawCompactTrackColumn` consumes `sends_fx_cache` |
| `DrawSendAddCard(...)` / `DrawSendDimPlaceholder(...)` / `SendsDrawSpanningAddRow(...)` / `DrawSendsColumn(...)` / `SendsDrawSection(...)` / `SendsMeasureGrid(...)` / `SendsDrawGroups(...)` / `SendsDrawGroupColumns(...)` | v20.543 moved normal grouped `SEND.col` rows to `core/Reflex_SendGridCore.lua`; v20.544 moved the outer grouped SEND wrapper there too; v20.545 moved shared SEND measurements there; v20.547 moved the full SEND section wrapper there; v20.548 moved the side-by-side SEND column wrapper there; v20.549 folded the former add-card core into the grid core. Owns SEND activation refresh, side-column responsive column count, empty SEND add placeholder, scroll-to, top margin, fallback flat-group creation, column width/padding/title-height/control-height measurements, ungrouped label drawing, folder-chain delegation, inter-group spacing, row max-FX/SND-expanded height math, per-column SEND FX-name cache refresh, `DrawCompactTrackColumn` calls, conforming add-card blanks, dim placeholders, row cursor advancement, spanning add-row rendering/gating, and distant-section delegation. | Main SEND surfaces + side-by-side SEND column |
| `DrawSendFolderCard(track, dl, cx, cy, w, id_suffix)` / `SendsDrawFolderChain(...)` | v20.534 moved the collapsed `SEND.folder` card to `core/Reflex_SendFolderCore.lua`; v20.535 fixed its font bridge to use `GetSteppedFont(UI.font_send_title)` because `scaled_fonts` remains local to `Reflex.lua`; v20.541 moved the folder-chain loop there too. Owns collapsed folder card rendering, expanded folder-card height calculation, title/blank expand-collapse handling, and folder-chain cursor advancement. | `SendsDrawSection` folder branch |
| `DrawDistantSendCollapsedCard(...)` / `SendsDrawDistantSection(...)` | v20.536 moved the collapsed `SEND.distant` spanning-card renderer to `core/Reflex_SendDistantCore.lua`; v20.540 moved the full distant section wrapper there too. Owns Distant Sends label/gap, collapsed/expanded card loop, expanded distant height calculation, SND-forced-open/collapse-request handling, SC badge/title link via the collapsed-card helper, and exclusive expand state. Uses `GetSteppedFont(UI.font_send_title)` rather than the local `scaled_fonts` table. | `SendsDrawSection` distant branch |
| `DrawDashedRoundedRect(dl, x1, y1, x2, y2, col, rounding, thickness, dash_len, gap_len)` | v20.405. Traces full rounded-rect perimeter (arcs sampled by radius) as dense polyline + walks with dash-phase cursor. Use when dashes must follow a card's rounded corners. | 1 (dest card outline during FX drag) |
| `FxRowContextMenu(track, fi, fx_guid, fx_en, fx_off, popup_id, surface)` | v20.419 (Phase 1 of FX-row unification); v20.526 moved to `core/Reflex_FXRowCore.lua`. Shared FX.row right-click menu body. REAPER-native order: Copy all FX → Copy/Cut variants → Paste → Remove → Bypass/Offline → Duplicate → Rename. Selection-aware: when clicked row is part of a live multi-selection bound to `track`, action items operate on the whole selection (pluralized labels). Wraps `PushPopupStyle`/`BeginPopup` internally. Rename uses a Reflex.lua bridge into the track-bound inline rename state. Caller still owns the `IsItemClicked(ctx, 1) → OpenPopup` line through `FxRowInteract`. | 2 (`InspDrawFXRow`, `DrawCompactTrackColumn` real-FX branch) |
| `FxRowOutlineColor(track, fi, guid, surface)` | v20.422 (Phase 2 of FX-row unification); v20.526 moved to `core/Reflex_FXRowCore.lua`. Returns uint32 outline color or nil for the row's outline rect. Caller draws its own `AddRect` — only the priority logic is shared. 4-state cascade in priority order: drag-source (operation color, gated on `fx_drag.src_surface == surface`) / paste-landed pulse (animated green) / clipboard carry (`C.fx_clip_carry`) / multi-select (`C.fx_sel_outline`). Empty-guid guard on all guid-based branches. | 2 (same call sites as `FxRowContextMenu`) |
| `FxRowInteract(p)` | v20.427 (Phase 3 of FX-row unification, plan complete); v20.526 moved to `core/Reflex_FXRowCore.lua`. Shared FX.row interaction kernel. Caller still owns row sizing, Selectable allocation, tooltip, text/widgets, fade, outline. Helper handles: drag begin (`FxDragBegin`) + activate (`FxDragTryActivate` w/ `src_track` + `src_surface` gate), hover/active fill + `FxDragLegendTip`, full click dispatch (Opt remove / Cmd+Shift offline / Cmd toggle / Ctrl range / Shift bypass / plain show), focus-grab suppression, `FxDragClear` on release-without-drag, right-click open + `FxRowContextMenu`. Post-action FX cache invalidation routes through `InspMarkTrackFxDirty(track)`. Two surface-gated side effects remain (different reasons): `cmp_key` ProjExtState clear (compare state is inspector-context only) and `InspPositionFXWindow` on `opt_fx_float` plain-click (geometry math against inspector card). Single table arg (~14 fields). | 2 (`InspDrawFXRow`, `DrawCompactTrackColumn` real-FX branch) |
| `InspGetFxList(track)` | v20.432. Returns `track_fx_cache[track].list`, lazily scanning via `InspScanTrack` on cache miss or count mismatch. Returns empty table for invalid tracks. The takes-a-track-arg rule (v20.406) — caller specifies track explicitly, no implicit "current inspected track." | All FX-record reader sites (post-Stage C migration) |
| `InspGetFxCount(track)` | v20.432. Lightweight: returns live `r.TrackFX_GetCount(track)` without touching the cache. Use for "do I have any FX here" gates where records aren't needed (e.g. `DrawFXChainCompound`'s `has_fx` check). | 1+ |
| `InspInvalidateTrackFx(track)` | v20.432. Drops `track_fx_cache[track]`; next `InspGetFxList` triggers full rescan. Used inside `InspMarkTrackFxDirty`'s non-inspector branch and at flow-state-transition cleanup. | via `InspMarkTrackFxDirty` |
| `InspMarkTrackFxDirty(track)` | v20.433 (Stage B). Post-action FX cache freshness helper. Two-branch: rescans eagerly via `InspScanTrack(track)` when `track == insp_track` (atomicity for same-frame rendering), or invalidates via `InspInvalidateTrackFx(track)` otherwise. Replaces the pre-Stage-B inline pattern `if insp_fx and track == insp_track then InspScanTrack(track) end` and the bug-incorrect `if surface == "inspector" then InspScanTrack(track) end` row-action gates. | 11 (clipboard sites + drop commit + row-action handlers) |
| `InspGetFxLatencyText(track, fx_idx)` | v20.657. Expanded `FX.row2` latency formatter. Reads REAPER's reported plugin PDC (`pdc`) and reported chain PDC (`chain_pdc_reporting`) and returns the REAPER-style `plugin/chain spls` label. Called only from visible expanded inspector/flow/secondary FX rows, never `SEND.col`. | 1 (`InspDrawFXRow`) |
| `LocateInREAPER(track, peek)` | v20.440. Universal locate gesture. Plain (`peek=false`): `InspRevealTrack` (visibility on, parent folders expanded, scroll TCP to center via direct `JS_Window_SetScrollPos` math, select). Sets `flow_view_browsing = true` if target is in active flow chain (so loop's silent-track-switch path pushes history). Pinned + non-flow-chain target: pre/post `ViewHistoryPush` to record secondary card transition (loop won't push under pinned TCP sync). Peek (`peek=true`): same visibility/expand mutation, scroll directly without touching selection — pure REAPER-side light-touch. Earlier peek implementations saved+restored selection via `Main_OnCommand(40297) + SetTrackSelected`, but REAPER's auto-scroll-on-selection on the re-selection step overrode peek's scroll; v20.441 inlined visibility walk and bypassed selection entirely. | 1 (called from `TitleLink`) |
| `TitleLink(id, x, y, w, h, track, opts)` | v20.440. Track-name-as-link affordance. Manual hit-test (no `InvisibleButton`) — avoids overlap conflicts with sibling buttons that may be registered earlier on the same screen region without `AllowOverlap`. Detects hover via `IsMouseHoveringRect`-style coordinate check + `IsWindowHovered(AllowWhenBlockedByActiveItem | AllowWhenBlockedByPopup)`. On hover: pushes `MouseCursor_Hand`, draws "Click to locate · ⌥-click to peek" tooltip via direct `SetTooltip` (gated on `opt_tooltips`). On click: dispatches `LocateInREAPER(track, opt_held)`. On Opt+click sets frame flag `nav_title_peek_consumed = true` so co-located bg/title fall-through handlers (folder expand, distant expand, minimal-flow browse) suppress themselves — peek is strict light-touch. Plain click is additive: locate + fall-through both fire. `opts.dbl_handler` lets caller preserve double-click semantics on a per-surface basis (HDR.name uses it for flow focus / secondary unpin). Suppressed during `fx_drag.active` and `nav_focus_grab_eat_click`. Returns `(hovered, clicked)`; caller draws its own underline using `hovered`. | 5 sites (HDR.name in `InspDrawHeader`, `DrawCompactTrackColumn` `##ctitle_link`, `DrawSendFolderCard` `##fctitlelink`, `FlowDrawMinimalCard` `##mctitlelink`, distant collapsed `##dtitlelink`) |

**Defined but not yet wired:** (none remaining as of v20.401). `SmoothPeak` wired in v20.393 at 5 peak-smoothing sites. `DrawClippedText` deleted v20.393 (PushClipRect mid-glyph clipping violated `Utf8DropLast` convention). `KnobUndoOn/Off` removed v20.380, replaced by Option C pattern. `ApplyVolDrag`/`ApplyPanDrag` superseded by `NavParamKnob` in v20.385.

---

## Per-Track FX Cache (v20.432–v20.437)

**Single source of truth for FX records, keyed by `MediaTrack*`.** Replaces the legacy file-scope `insp_fx` slot (removed in v20.436, Stage D) and the parallel `flow_fx_cache` (merged in v20.437, Stage G).

### Structure

```lua
track_fx_cache = {}   -- track_ptr → { list = [{...fx_record...}, ...], count = N }
```

Each `list` entry is the full FX record shape: `{track, fx_idx, name, enabled, offline, env_count, guid, cmp_key, has_bypass_env, wet_param_idx, wet_value, is_instrument, is_container}`. Records are mutated in place by `InspRefreshFXState` for per-frame field freshness; full rebuild via `InspScanTrack` when count or GUID order changes.

### API

`InspGetFxList(track)` is the canonical reader — lazy-rescans on cache miss or count mismatch. `InspGetFxCount(track)` is a lightweight count-only check that bypasses the cache. `InspInvalidateTrackFx(track)` drops a cache entry. `InspMarkTrackFxDirty(track)` is the post-action freshness helper that decides between eager rescan and lazy invalidate based on whether the action targeted `insp_track`. See "Extracted Helper Functions" table for full signatures and call counts.

### Freshness Model

Two complementary mechanisms:

1. **Count-based lazy rescan** inside `InspGetFxList`: compares cached `count` against `r.TrackFX_GetCount(track)`; if mismatch, calls `InspScanTrack(track)` to rebuild. Catches FX add/remove that bypassed Reflex.

2. **GUID-reorder detection + in-place field freshness** via `InspRefreshFXState(track)` (called per-frame from `Loop` for `insp_track` and from `flow_prepare_track` for chain tracks): walks the cached list, returns `true` if any GUID position changed (caller must rescan), otherwise mutates `enabled`/`offline`/`env_count`/`has_bypass_env`/`wet_value` fields in place.

### Loop Track-Resync Pattern (post-v20.434)

The `Loop` pre-render check uses cached count directly to compare against live REAPER count without triggering lazy rescan (which would defeat the mismatch detection):

```lua
local fx_count = r.TrackFX_GetCount(insp_track)
local cached = track_fx_cache[insp_track]
local cached_count = cached and cached.count or 0
if fx_count ~= cached_count then
    -- handle add/remove (move new instruments, fire insert-target moves, rescan)
elseif InspRefreshFXState(insp_track) then
    -- handle GUID reorder
end
```

### Migration History

- **Stage A (v20.432):** Introduced `track_fx_cache` + `InspGetFxList`/`InspGetFxCount`/`InspInvalidateTrackFx` API. `InspScanTrack` dual-wrote to both `insp_fx` and `track_fx_cache`. No reader migrated yet — parallel, dormant.
- **Stage B (v20.433):** Added `InspMarkTrackFxDirty(track)` helper. Migrated 11 post-action freshness sites from inline patterns (`if insp_fx and track == insp_track then InspScanTrack(track) end`) and from buggy `surface == "inspector"` row-action gates to the helper.
- **Stage C (v20.434):** Migrated all reader sites — `InspDrawFXArea`, `DrawFXChainCompound`, `InspRefreshFXState`, `InspFormatEnvForTrackList`, `InspCmpAnyFloating`, both env-expand-all loops, Loop track-resync paths. Each function's reads now go through `InspGetFxList(track)` or directly to `track_fx_cache[track].list` with explicit track arg per the takes-a-track-arg rule.
- **Stage D (v20.436):** Dropped the legacy `local insp_fx = {}` declaration. Rewrote `InspScanTrack` to build into a local list and single-write to `track_fx_cache[track]`. Deleted the swap dance in `flow_prepare_track` (replaced 11-line scan-or-cached logic with 3 lines: `InspGetFxList` + `InspRefreshFXState` + `flow_fx_cache` alias). Deleted the secondary card swap save/restore in `InspDrawSelectedTrackCard`, including the redundant `InspScanTrack(insp_track)` rebuild at the end (existed solely to repair swap damage). Removed the trailing flow-render restore (`if afc then insp_fx = afc.list else insp_fx = saved_fx end`).
- **Stage G (v20.437):** Merged `flow_fx_cache` into `track_fx_cache`. Audit revealed `flow_fx_cache` was write-only post-Stage-D (zero member-access reads in the entire script) — the alias write in `flow_prepare_track` plus 17 invalidation sites were maintaining a cache nobody read. Pure deletion: dropped declaration, removed entry from `SweepDeadTrackCaches`, deleted 7 single-line invalidations + 1 multi-line drag-commit block + 5 wholesale `flow_fx_cache = {}` mid-segments + 3 prune loops + the alias write. ~37 lines removed.

### Honest Framing of the "Self-Send" Bug

The v20.426 PROJECT_KNOWLEDGE entry describing the architectural rationale for this refactor framed the motivation as the "self-send staleness bug" — a one-frame stale render when a sends-surface action targeted `insp_track`. **Tracing the code in v20.434 revealed this scenario isn't reachable through normal REAPER usage:** REAPER's send-routing UI doesn't allow a track to send to itself; folder cards in sends view always represent ancestors of destinations (never `insp_track` directly); distant sends and return modules are always destination tracks. The `surface == "inspector"` gates in `FxRowContextMenu` / `FxRowInteract` were architecturally wrong (should have been track-identity checks) but never actually fired the bug they appeared to prevent.

The refactor's real value was always architectural: eliminating the swap dance in `flow_prepare_track` and `InspDrawSelectedTrackCard`, removing the forced `InspScanTrack(insp_track)` rebuild after every secondary card render, replacing implicit "current renderer's track" coupling with explicit per-track lookups, and (Stage G) collapsing two parallel cache identities into one. Those payoffs are all visible in the diff.

### Stage F (Deferred)

**F:** localize `insp_fx_rects` to `InspDrawFXArea` (currently still a file-scope global, hot-swapped in flow render). Migrate `fx_browser_drag` handler at lines ~14533/14558 to read from `fx_drop_targets` registry instead.

Optional. Skip unless it unblocks other work.

---

## Scale System

`ui_scale` defaults to 1.0 (displayed as 100%). The 0.8 base factor is baked into `S()`:

```lua
S = function(v) return math.floor(v * ui_scale * 0.8 + 0.5) end
```

Pref key: `"ui_scale_v2"` (auto-migrates from legacy `"ui_scale"` key on first load). Steps: 0.10 (10% increments), range 50%–250%.

Font step base: `ui_scale * 0.8 * 10`.

**Pixel communication convention:** S.Hansen provides retina physical pixels. Convert: **retina px ÷ 1.6 = S-units** at 100% scale. Example: "20px" = S(12.5), "13px" = S(8).

**Settings panel scale lock (100% fixed):** save `real_ui_scale = ui_scale; ui_scale = 1.0` at top of `if settings_open then`, restore at end. This makes `S()` and `GetFontStep` resolve to 100% values. Reflex Size +/- buttons read/write `real_ui_scale` directly. Additionally: push a 100%-scale font *inside* the window's `Begin`/`End` — the main loop's outer scaled font push stays active otherwise, and ImGui built-in widget heights will scale even with `ui_scale` overridden.

**Separate NAV scale (v20.552):** `navigator_scale_v1` is the shared scale for `NAV.arr`, `NAV.dot`, `NAV.pill`, A/S/R, and standalone `Navigator.lua`. Reflex keeps `ui_scale_v2` for the inspector/work surfaces; the main loop temporarily sets `ui_scale = nav_ui_scale` only around `NavDrawSection`, pushes a NAV-scaled font, then restores the Reflex scale before drawing `HDR`/`VOL`/`CTRL`/`FX`/`SEND`/`RMT`. Standalone Navigator loads `navigator_scale_v1` directly, falling back to `ui_scale_v2` on first run.

---

## UI Token System

```lua
UI = { pad=10, pad_sm=6, row_gap=10, section_gap=10, btn_h=26,
       group_gap=10, ctrl_sz=22, corner_r=4, fx_gap=6, meter_h=6,
       slider_h=22, circ_btn_r=13, hdr_row_gap=14,
       gap_hdr_vol=0, gap_vol_ctrl=10, gap_ctrl_route=0,
       gap_ctrl_fx=0, gap_route_fx=14, gap_bottom=0, gap_sends=4,
       card_r=12, card_pad=14, card_pad_top=15, card_pad_bot=22,
       card_gap=12, flow_gap=3, edge_pad=12,
       send_pad_top=10, send_pad_bot=17, send_folder_pad_bot=12,
       font_insp_name=4, font_title=3, font_section=2,
       font_fx=0, font_send_title=0 }
```

`gap_bottom` and `gap_sends` are dead tokens. `pad_sm` (=6) is the standard element gap; half-gap reserved for joined compound buttons only. Section gap convention: top-margin-only, no trailing margin.

### Button Primitives: `NavSquare` / `NavCircle` / `NavPill` / `NavRect`

Every button must use one. **Forbidden:** raw `InvisibleButton + AddRectFilled + AddText`.

---

## Card Box System

**Stroke colors:** `C.source_stroke` (amber) on source track cards. `C.send_stroke` (white) on whichever flow view card is currently inspected (`is_selected` / `chain_track == insp_track`). Send modules, folder spanners, and distant sends have **no stroke**.

**FX row strokes (v20.403+):** three additional tokens for multi-select + drag state:
- `C.fx_drag_move` (washed red `0xE57373`) — move-operation source rows and destination dashed outline
- `C.fx_drag_copy` (blue `0x58A6FF`) — copy-operation source rows and destination dashed outline
- `C.fx_sel_outline` (white `0xFFFFFF`) — multi-selected FX rows when no drag is active

These colors are currently script-owned constants. Future user-facing overrides should be exposed through the Options GUI rather than an external theme file.

`CardBegin`/`CardEnd` handle rounded-rect containers with optional stroke, height estimation from previous frame, and cursor inset/restore.

### Card Top Padding

`trk_pad_top = 0` when `opt_card_boxes` is on — `CardBegin` already provides `card_pad_top`. Without card boxes, falls back to `S(UI.pad)`. All card types (expanded, source, compressed) share the same `card_pad_top` gap above the title row.

---

## Send Topology View

**`DrawSendFolderCard` / `SendsDrawFolderChain`** — in `Reflex_SendFolderCore.lua` as of v20.534/v20.541. `DrawSendFolderCard` returns `(card_h, fc_title_clicked)` for collapsed `SEND.folder`; title is also a locate link, and M/S is top-aligned with knobs. `SendsDrawFolderChain` owns the outermost-first folder-card loop for conforming groups, including expanded folder-card height calculation, title/blank expand-collapse handling, auto-scroll position capture, and cursor advancement. Expanded folders still render through `DrawCompactTrackColumn`.

**`DrawCompactTrackColumn`** returns `ct_clicked`. SND header: arrow and "SND" text rendered independently (arrow unaffected by mute, text faded red `0x99` alpha when muted). Full-width SND hit area. Inspect arrow hover-gated on M/S row. Mute overlay: `(C.bg & 0xFFFFFF00) | 0x70` with mute button redrawn on top.

**`RoutingAddSendTrack(track, send_mode, target_folder)`** — in `Reflex_SendCreateCore.lua` as of v20.533. Inserts inside folder by walking subtree and stealing target/outer fold-depth closures from the previous last child. `target_folder` is accepted only when it passes `IsConformingReturnsFolderForSource`; stale/nonconforming folder targets fall back to normal/conform placement.

**`DrawSendAddCard` / `DrawSendDimPlaceholder` / `SendsDrawSpanningAddRow` / `DrawSendsColumn` / `SendsDrawSection` / `SendsMeasureGrid` / `SendsDrawGroups` / `SendsDrawGroupColumns`** — in `Reflex_SendGridCore.lua` as of v20.543/v20.544/v20.545/v20.547/v20.548/v20.549. Own the side-by-side SEND column wrapper, full SEND section wrapper, SEND blank-cell renderers, shared measurement pass, and grouped `SEND.col` block: activation refresh, side-column responsive column count, empty SEND add placeholder, activation scroll-to, top margin, fallback flat group creation, column width/padding/title-height/control-height measurements, ungrouped label drawing, folder-chain delegation through `SendsDrawFolderChain`, inter-group spacing, row max-FX/SND-expanded height calculation, `DrawCompactTrackColumn` calls, per-column SEND FX-name cache refresh, conforming add-card blanks, non-final dim placeholders, row cursor advancement, spanning add-row rendering/gating, and distant-section delegation through `SendsDrawDistantSection`. `SendsMeasureGrid` uses `GetSteppedFont(UI.font_send_title)` rather than the local `scaled_fonts` table.

**`SendsEnsureFxNameCache` / `SendsFxCachedCount`** — in `Reflex_SendFxCacheCore.lua` as of v20.538. Centralizes the SEND-surface `sends_fx_cache` freshness pattern used before rendering expanded `SEND.folder`, normal `SEND.col`, and expanded `SEND.distant`. `DrawCompactTrackColumn` still consumes `sends_fx_cache` directly for row names.

### Sends FX Area (v20.420 parity with inspector)

Sends columns render their FX area identically to the inspector card. Each compound is `[arrow|FX|+]` when the column has FX (3 segments), `[FX|+]` when empty (2 segments). The `+` button mirrors `DrawFXChainCompound` exactly: `btn_h` square, hover `0x08A5F7FF`, drag-to-insert state via `insp_fx_insert_sy`/`insp_fx_insert_dragging`, right-click opens `##snd_addfx_ctx` (Open REAPER FX Browser / Define Action / Clear).

**Empty slots render nothing.** v20.420 deleted the placeholder `+` cells in shorter-than-max columns and the always-present trailing add-FX row. Variant B equalization: `slots = max(fx_count, max_fx)` keeps column heights aligned across the row of sibling columns (so M/S knobs stay at column bottoms), but the empty space is invisible. `fx_area_h = slots > 0 and (slots * fx_h + (slots - 1) * fx_gap_v) or 0` — no trailing slot.

**Wrap-prediction parity (v20.425).** Parent height computation predicts whether the controls row will wrap (route pill drops below) so card height accounts for it. The estimate must match the child's actual rendered width. Three sites in `RenderSendsView` use `est_arrow_w + est_fx_btn_w + est_addfx_w + row_gap + est_route_w > inner_w` (regular columns, folder cards expanded, distant sends). The `est_addfx_w = btn_h` term was missing in v20.420–v20.424 — parent under-predicted compound width at intermediate card widths, allocated single-row `ctrl_h` while child rendered two-row, M/S rode off the bottom by `row_gap + btn_h`. Whenever the compound's width formula changes, all three parent predictors must update in lockstep.

### Send Topology Classifications

Conforming `SEND.folder` groups are intentionally narrow. A destination renders under `SEND.folder` only when the return track is a direct child of a valid local return folder: folder track, name starts with `Returns`, same immediate parent as the source, and same track depth as the source. Arbitrary parent folders, nested folders, and same-branch non-`Returns*` folders must not render as return folders.

`is_ungrouped` only labels local sends when conforming groups exist (`#group_order > 0`). When there are no conforming groups, local sends render as normal `SEND.col` columns with no `Ungrouped` label and no inside-folder add blanks. When conforming group(s) and loose/nonconforming local sends both exist, those locals render under `Ungrouped`. `SEND.distant` does **not** require conforming `SEND.folder` groups: remote-only topologies leave `sends_view_groups` empty and render only the Distant Sends section. Remote/distant classification includes normal depth > 1 sends and no-local-merge cases such as a top-level source sending into an unrelated folder. Same-branch nonconforming folders stay normal `SEND.col`; they simply do not render a folder card.

**Top-level source fix (v20.443, refined v20.514/v20.516).** `SendsViewBuildGroups` originally required `entry.depth == 1 and #entry.path >= 3` to enter the grouping branch — assumed source had at least one parent in the path so `path[#path]` was the merge point in the source chain. When source is top-level (no parents), `AnalyzeSendTopology`'s "no intersection found" branch produces paths that do not include the source-side merge. v20.443 added a `path == 2` branch for direct top-level Returns folders. v20.514 made remote-only distant rendering possible. v20.516 replaced topology-shaped folder grouping with `IsConformingReturnsFolderForSource`, so top-level and nested cases follow the same `Returns*` sibling rule.

### Distant Sends

Two-state: fully open or fully closed. Expanded: SND forced open every frame, any click collapses (title click sets `d_ct_clicked`, SND header click sets `sends_distant_collapse_request`, blank-area click satisfies `d_blank_click`). Exclusive expand. Can render alone when every send is remote; `SendsDrawSection` skips its flat fallback in that case so remote-only sends are not duplicated as normal columns. Locate via title click (no longer via dedicated inspect arrow — see "Locate & Peek" section).

**`DrawDistantSendCollapsedCard` / `SendsDrawDistantSection`** — in `Reflex_SendDistantCore.lua` as of v20.536/v20.540. Owns the `SEND.distant` section renderer: heading/gap, collapsed-card title locate/peek + `SEND.distant.sc` badge, expanded distant height calculation, forced-open SND state, SND-click collapse request handling, blank-area collapse, and exclusive expand state. Expanded distant cards still render through `DrawCompactTrackColumn`, but the distant module now owns the wrapper and state transitions.

### Routing Panel Integration
`route_hovered_send_idx` draws white `AddRect` outline on matching send module. Sends/receives sorted by track number, displayed as `"5: Returns"`.

### Auto-Scroll on Expand
`sends_expand_scroll_cy` positions card top at 30% of viewport next frame. Scroll bottom padding: `Dummy(1, S(UI.edge_pad))` in all 3 child paths.

### Sends View Refresh Detection
`SendsViewCheckRefresh` (in `Reflex_SendTopologyCore.lua` as of v20.532) detects four change types:
1. Source track changed → refresh
2. Send count changed → refresh
3. Destination pointer mismatch (same count but send rerouted) → refresh
4. Distant-send destination channel changed → refresh, so `SEND.distant.sc` badge/sort updates immediately

Per-frame loop compares current send dest pointers to cached `sends_view_tracks`, and compares cached `SEND.distant` sidechain flags against live `I_DSTCHAN`. Catches API-initiated routing changes that preserve count and channel-only edits that would otherwise leave the SC badge stale.

---

## Locate & Peek (v20.440–v20.443)

Universal "track name = locate-link to that track in REAPER" gesture across every surface that displays a track name. The mental model: clicking a name brings REAPER and Reflex into sync on that track. The card surface still owns its own actions (expand, browse, focus, etc.) — title is just one carved-out region within it.

### The Gesture

| Modifier | Action |
|---|---|
| Plain click on title | Locate: visibility on, parent folders expanded, scroll TCP to center, select. **Additive** — bg/title fall-through handlers also fire (e.g. folder card click also expands, minimal flow card click also browses). |
| ⌥+click on title | Peek: REAPER-side mutation only (visibility, expand, scroll). No selection change, no Reflex state change. **Strict light-touch** — bg/title fall-through handlers gated off via `nav_title_peek_consumed` frame flag. |

### Affordance

Cursor changes to `MouseCursor_Hand` on hover. Underline drawn at text baseline by the caller using the `hovered` return value from `TitleLink`. Tooltip "Click to locate · ⌥-click to peek" via direct `SetTooltip` (gated on `opt_tooltips`). Suppressed during `fx_drag.active` and `nav_focus_grab_eat_click`.

### Why Manual Hit-Test, Not InvisibleButton

`TitleLink` does not register an `InvisibleButton` because every surface it's applied to already has an underlying broader InvisibleButton (e.g. `##hdrtitle`, `##fctitle`, `##ctitle`) registered earlier in the frame on overlapping space. Without `AllowOverlap` opt-in on those underlying buttons, a later-registered InvisibleButton on top is blocked from receiving hits — symptom: title clicks don't fire. ReaImGui's `IsItemHovered` and `IsItemClicked` respect this priority.

`TitleLink` instead does coordinate hit-testing (`mouse_x/y` against `x/y/w/h` rect) + `IsWindowHovered` with `AllowWhenBlockedByActiveItem | AllowWhenBlockedByPopup` flags, then dispatches `IsMouseClicked(0)` directly. This sidesteps the priority system entirely. The "additive" semantics fall out for free: both TitleLink AND the underlying InvisibleButton fire on a click, and the underlying handler is the one carrying the surface-specific action (folder expand, etc.).

### Peek Suppression Pattern

`nav_title_peek_consumed` is a frame-scoped global, reset to `false` at the top of `Loop`. `TitleLink` sets it to `true` when an Opt+click dispatches. Every bg/title fall-through site that needs to suppress on peek gates its own click handler with `... and not nav_title_peek_consumed`:

- `##ctitle` (DrawCompactTrackColumn) — gates `ct_clicked` so caller's folder-collapse-on-title-click doesn't fire on peek
- `##fctitle` (DrawSendFolderCard) — gates `fc_title_clicked` so caller's folder-expand doesn't fire on peek
- `##dist_card` (distant collapsed) — gates the `dclk` expand toggle on peek
- `FlowDrawMinimalCard` bg single-click + double-click — gates expand+browse and focus on peek

`HDR.name` doesn't need the peek flag because it gates fall-through on `not title_clicked` directly (and TitleLink returns `clicked=true` for both plain and Opt). On HDR.name peek, `title_clicked` is true → fall-through gated off naturally.

### Scroll-to-Center Math

`ScrollTrackToCenter` uses direct `JS_Window_SetScrollPos`. Critical detail: `JS_Window_GetClientSize` returns `(retval, w, h)` — three values, not two. Earlier code (`local _, th = ...`) was capturing the WIDTH into `th` and computing centering against width-as-height. This produced track-positions in the bottom third (close enough to look like REAPER's own `40913` "scroll selected into view" action, which masked the bug). Fixed v20.440 with `local _, _, th = ...`.

The math: `target_scroll = sp + ty + tkh/2 - th/2` where `sp` is current scroll position, `ty` is `I_TCPY` (track Y relative to current viewport), `tkh` is `I_TCPH`, `th` is viewport height. `40913` is no longer called — the JS_Window math is authoritative. Fallback path (no JS_ReaScriptAPI) still uses `40913` but lands tracks in the bottom third.

### Peek Scroll Implementation

Peek path inlines the visibility-walk (parent folder enumeration + `I_FOLDERCOMPACT=0`) from `InspRevealTrack`, then calls `JS_Window_SetScrollPos` directly without ever touching selection. Earlier implementations saved+restored selection via `Main_OnCommand(40297) + SetTrackSelected`, but REAPER's auto-scroll-on-selection on the re-selection step would scroll back to the previously selected track, defeating peek's scroll. v20.441 fix: don't mutate selection at all in peek mode.

### View History Behavior

- **Unpinned plain locate**: main loop's selection-tracking branch pushes when `sel_track ~= insp_track` (existing path)
- **Unpinned plain locate where target == current insp_track**: no-op for history (dedup), but TCP still scrolls — useful "drag REAPER back to where Reflex is" gesture
- **Pinned + flow-chain target plain locate**: `flow_view_browsing = true` triggers v20.429 silent-track-switch push
- **Pinned + non-flow-chain target plain locate**: `LocateInREAPER` pre/post-pushes around the mutation (loop's pinned TCP sync convention doesn't push, so locate captures it explicitly)
- **Peek (any context)**: never pushes — by definition no Reflex state changed

### Inspect Arrows Removed

v20.441 removed all per-surface "inspect arrow" affordances now that title-click locates. Removed sites: SEND.col M/S row arrow, SEND.folder arrow (below M/S), distant collapsed card arrow (left of title). The `InspectArrowButton` and `DrawInspectArrow` helpers are still defined and could be reused, but no callers remain.

### SND Header Chevron Move

v20.441 moved the SND expand chevron from left of "SND" text to the right endcap. Whole row remains a single hit zone. Tooltip "Open sending track controls" added (descriptive category, gated on `opt_tooltips`).

### Distant Card Collapse Race

When `sends_distant_rendering` is true, the outer renderer force-writes `sends_snd_expanded[send_idx] = true` every frame (distant cards are two-state: fully open or closed). SND's own click handler self-toggling that flag would be reverted next frame, producing a flicker but no actual collapse. Worse: SND's InvisibleButton makes `IsAnyItemActive` true on the click frame, blocking the outer `d_blank_click` collapse path.

Fix (v20.441): SND header click in distant mode sets `sends_distant_collapse_request = true` instead of self-toggling. Outer distant handler reads it after `DrawCompactTrackColumn` returns and treats it like `d_ct_clicked` — collapses the entire distant card. The flag is set and consumed in the same frame; reset to false before each distant card render and after consumption.

---

## TLT Click Modifiers

| Modifier | Action |
|---|---|
| Click | Solo (if others visible) or toggle collapse (if alone) |
| Cmd+click | Add/remove from visible set |
| Opt+click | Toggle pin |
| Ctrl+click | Expand/collapse folder and all children |
| Shift+click | Range select |

`IsCtrl` helper: bit `0x1`. Range selection stores both the legacy `tracks_last_click` label and `tracks_range_anchor_guid`; resolve the GUID first so repeated Shift-clicks keep the original anchor across render-list rebuilds. Range selection shows only the rows inside the range plus required parent folders; a folder row inside the range must not automatically show all descendants.

**`EnsurePinnedVisible`**: calls `SetFolderVisible` (shows folder + all descendants), only uncollapses when folder was actually hidden (`was_hidden` check). `IsAloneVisible` excludes pinned folders from visible count.

**Expanded TLT pills**: custom-drawn pill rows (not `StyledButton`). `C.bg` pill bg, colored circle in right endcap, text right-aligned, pin indicator in left endcap. 85% scale (`S(34)` height, `S(3.75)` row gap). Inactive: 40% alpha on all elements. No-color tracks: `0x58616C` (active), `0x2A3038` (inactive).

**`InspDrawSectionHeader`** accepts `opts` table: `arrow_font`, `arrow_color`, `arrow_hov_color`.

**`InspRevealTrack`** called on double-click hidden track card and on unpin when track is hidden.

---

## Design Mode

Live UI token editor via Settings. `DM(token, x1, y1, x2, y2)` registers overlay rects. `DM_DrawInChild()` before each `EndChild`. `FloatRow`/`ColorRow` guard missing API functions.

| Variable | Default | Controls |
|---|---|---|
| `design_mode_insp_max` | 295 | Inspector column width cap |
| `design_mode_win_min_w` | 280 | Window minimum width |
| `design_mode_win_max_w` | 480 | Window maximum width |
| `design_mode_two_col_mult` | 1.75 | Two-column threshold multiplier |
| `design_mode_stroke_w` | 1.5 | Stroke width in logical px |

---

## Undo Block Conventions

### Flag Semantics

| Flag | Use for | Effect |
|---|---|---|
| `-1` | Audio-affecting changes (vol, pan, FX, sends, mute/solo, envelopes) | Creates proper REAPER undo entry |
| `0` | View-state changes (visibility, collapse, selection, routing/active view, archive) | Batches op but doesn't pollute REAPER undo history |

Never use flag `0` for audio state. Never use `-1` for pure view-state.

### Cross-Frame Pattern Is Broken

`Undo_BeginBlock` in one `defer()` cycle and `Undo_EndBlock` in another cycle **does not pair**. Each cycle is an independent script invocation — unpaired calls produce "ReaScript: Run" entries instead of properly-labeled undo entries. This affects any click→drag→release pattern that spans multiple frames.

### Multi-Frame Drags — Option C Pattern

For any widget where the user clicks, drags for multiple frames, then releases:

**On click:**
```lua
xxx_before = r.GetXxx(track, ...)
xxx_moved = false
xxx_dragging = true
```

**During drag:**
```lua
if act and xxx_dragging and dy ~= 0 then
    r.SetXxx(track, ..., new_value)  -- raw write, no Begin/End
    xxx_moved = true
end
```

**On deactivate (only if moved):**
```lua
if xxx_moved and xxx_before ~= nil then
    local final = r.GetXxx(track, ...)           -- read current (post-drag)
    r.SetXxx(track, ..., xxx_before)             -- silent rollback
    r.Undo_BeginBlock()
    r.SetXxx(track, ..., final)                  -- atomic commit at final value
    r.Undo_EndBlock("Reflex: Xxx change", -1)
    xxx_before = nil; xxx_moved = false
end
```

Net result: one clean labeled undo entry per drag. The transient "ReaScript: Run" entries from raw writes during drag get superseded by the final atomic commit.

**14 sites use this pattern:** inspector vol slider, inspector dB readout drag, inspector pan, inspector wet/dry (×2 render paths), folder knobs (×4: narrow/wide × vol/pan), send knobs (×4), return knobs (×4), routing vol/pan sliders. The 12 folder/send/return knob sites all route through `NavParamKnob` as of v20.385.

**State storage:**
- `NavParamKnob` sites share 6 `{before, moved}` tables mutated in place: `fcvol_state`, `fcpan_state`, `skvol_state`, `skpan_state`, `rkvol_state`, `rkpan_state`. Folder narrow/wide share state (only one branch runs per frame).
- Non-helper sites still use flat globals: `insp_vol_before`, `insp_vol_val_before`, `insp_pan_before`, `insp_wet_before`. ROUTE.row vol/pan drag commit state moved into `Reflex_RouteControlsCore.lua` in v20.527; only `route_slider_drag_id` remains global for hover suppression in `DrawRouteRow`.

### Knob Double-Click Reset

On `_dbl` trigger during an Option C drag: write the reset value and set `_moved = true`. The deactivate handler's rollback+commit then captures that as the final value, producing one labeled entry.

### InspCleanupDragState

Called on track switch / track invalidation. Post-Option-C, drags no longer open Begin blocks — this function just clears `_dragging` flags and cached `_before` values. Never calls `Undo_EndBlock`. v20.406 added FX multi-select clearing on track switch. v20.525 softened that for visible multi-card contexts: `InspCleanupDragState({ keep_fx_selection = true })` resets drag/insert state but preserves `insp_fx_sel` when the selection's bound track will still be rendered (FLOW chain, current inspector card, or active SEND.col list). Invalidations and switches that remove the bound track from Reflex-visible surfaces still clear selection.

### Forbidden Patterns

- Cross-frame `Begin`/`End` pairs (click opens block, release closes it). Broken in ReaScript.
- `Undo_EndBlock` in cleanup paths for Option C drags. No open block to close.
- Unwrapped audio-state mutations. Produces "ReaScript: Run" instead of descriptive labels.

### Version String Source of Truth

`REFLEX_VERSION` constant near top of file. Used in settings panel title ("Reflex v<REFLEX_VERSION>"). **Bump all three together: the `* Version:` header comment, the `REFLEX_VERSION` constant, AND the `**Current version:**` line at the top of this file.**

---

## Key Technical Patterns

### View History Debouncing
TLT click handlers (`HandleTracksClick`, `HandleSongsClick`) use `ViewHistoryPushTlf()` — a 500ms-debounced wrapper. Rapid TLT clicks group into one undo entry (pre-burst state captured); Back returns to the state before the whole click sequence. All other `ViewHistoryPush()` call sites — bulk ops (`ShowAllTLFs`, `HideAllTLFs`, etc.), pin toggle, mode toggles (`RoutingViewToggle`) — fire every time without debouncing. Debounce state: `view_history_tlf_debounce` global timestamp.

### Pinned TCP Sync
When pinned, external TCP selection changes do NOT push view history. Pinned mode doesn't change `insp_track`, pin state, or any navigatable state — pushing created either dedup'd no-ops or ghost entries. Clears `insp_pin_suppress_selected` flag and selection-tracking state only.

**Unpin pre-push (v20.426).** The "pinned + secondary B selected" state isn't recorded by suppression above. At the moment of unpinning into a different track (double-click on secondary card title — header at line 6938, flow-view variant at line 9474), the secondary state would be lost from history: head was "pinned A", new push is "unpinned B", Back appears to skip a step. Fix: pre-push the live state before mutating, then mutate, then push the new state. Two entries land where one was, reflecting the actual visited states. `ViewHistoryPush`'s dedup makes the pre-push a no-op when no state actually changed (e.g. unpin without prior secondary selection), so the fix only adds entries in the case it was missing. Sites where this pattern is needed: any unpin path where `sel_track ≠ insp_track`. The pin-button toggle path (line 7014) doesn't need it — it calls `SetOnlyTrackSelected(insp_track)` first, so live state matches the existing head.

### View History Flow View Restoration (v20.428–v20.429)

Snapshot captures `flow_active` (bool) and `flow_anchor_guid` (string, when active). Restore re-establishes `flow_view_active` and resolves `flow_view_anchor` from guid, then rebuilds `flow_view_chain` via `FlowViewBuildChain`. Always clears `flow_view_browsing` and `flow_view_expanded_set` on restore — these are transient browse-state, never history-meaningful. If anchor guid no longer resolves to a valid track, flow view collapses safely (clears chain + per-track caches).

### View History Navigator And Armed View State

`ViewHistorySnapshot()` captures NAV-local state that changes what the Navigator shows but is not represented by TCP visibility alone: pins, tree expansion/layer overrides, manual includes, hidden/promoted rules, custom set membership/mode, and TLT search text. Restore writes those maps back through their persistence helpers and rebuilds the render list.

Armed View is also captured as history state: `armed_view_active`, the GUID set for `armed_view_tracks`, and the current `armed_view_saved_snap` reference. This prevents Back/Forward from restoring an armed-filtered TCP layout while leaving the command-driven Armed View flag or exit target stale.

Equality (`ViewHistorySnapshotsEqual`) compares `flow_active` and `flow_anchor_guid` alongside `pinned`, `pinned_guid`, `sel_guid`. The `pinned_guid` comparison was previously omitted — two pinned states with different pinned tracks dedup'd as equal, suppressing legitimate pushes. Fixed alongside the flow snapshot work.

**Pre/post `ViewHistoryPush()` around `FlowViewSetFocus` call sites (v20.429).** Five sites total — secondary-card unpin (already wrapped pre-v20.429), inspect-arrow click, header double-click in flow, chain-card double-click, minimal-card double-click. Without these, the unpin-and-re-anchor transition wasn't recorded as its own history entry, and Back appeared to skip the previous flow chain context.

**Push at silent track switch in pinned-flow-browse (v20.429).** When `flow_view_browsing` triggers `insp_track = sel_track` while pinned (the documented exception to the "no-push in pinned mode" rule), the new state must be captured. This branch DOES change navigatable state, unlike normal pinned TCP sync.

### Sends Rename FX Instance (v20.430)

Right-click → "Rename FX instance" originally inspector-only (Phase 1 deferred sends extension). v20.430 generalized rename state to support any track:

- Added `insp_rename_track` (`MediaTrack*`) alongside the existing `insp_rename_type` / `insp_rename_idx` / `insp_rename_buf` / `insp_rename_focus` / `insp_rename_frames` globals.
- `insp_rename_idx` convention switched from 1-based ipairs to 0-based `fx_idx` to match sends's natural indexing.
- Inspector consumer in `InspDrawFXRow` and new sends consumer in `DrawCompactTrackColumn` real-FX branch both gate on `insp_rename_track == row_track and insp_rename_idx == row_fi`. Only one row across both surfaces enters rename at a time.
- On commit, sends consumer invalidates `sends_fx_cache[track]` so the new name shows next frame; calls `InspScanTrack(track)` only when `track == insp_track` (self-send case, harmless when not).
- Stale `insp_rename_track` references are functionally inert when `insp_rename_type == nil` — both consumers gate on type first. No need to clear `_track` at every type-clear site.

### Multi-Expand Flow View (v20.431)

`flow_view_expanded_card` (single track ptr) replaced by `flow_view_expanded_set` (`{[track]=true, ...}`). Any subset of non-focus chain cards may be expanded simultaneously. Set is transient (not history-snapshotted, cleared on `FlowViewSetFocus` / `FlowViewToggle` / `FlowViewRefresh` anchor-invalid path).

Flow backend helpers live in `core/Reflex_FlowCore.lua` as of v20.524: `FlowViewBuildChain`, `FlowViewToggle`, `FlowViewSetFocus`, and `FlowViewRefresh`. `FLOW.btn` rendering, minimal-card drawing, flow arrows, and the flow render loop remain in `Reflex.lua`.

**Click rules.** Minimal card click → add to set + select + browse. Expanded non-focus card click while not selected → select (no expansion change). Expanded non-focus card click while already selected → remove only that track from the set (collapse gesture). Focus/source card click → no-op once selected (source is always full and has no expand/collapse state). Double-click any card → focus change via `FlowViewSetFocus`, set cleared.

**Drop-into-card persistence.** During `fx_drag.active`, hover over a minimal card auto-expands it (adds to `flow_view_expanded_set` + records in `fx_drag.flow_auto_expanded`). Next frame, the card renders as full and registers as a drop target via `InspDrawFXArea`. On commit, `FxDragResolveDrop` removes the dropped-onto track from `flow_auto_expanded` so it stays expanded after the drop. `FxDragClear` reverts whatever's still in `flow_auto_expanded` (non-committal hovers).

Latent bug fixed in passing: chain-card single-click on non-selected expanded card was assigning to undefined auto-global `track` (line 9812 in pre-v20.431). New multi-expand semantics make this branch a pure "select-without-expansion-change" — no longer needs the assignment.

### FX Browser Cache
Built lazily on first `FxBrowserRender` call, cached for session lifetime. Rebuild is ~20–50ms (iterates `EnumInstalledFX`) — too slow to re-run on every open. Manual refresh only: Settings gear menu → "Refresh FX list" sets `fx_browser_cache = nil`, next open rebuilds. Use after installing new plugins.

### Per-Track Cache Hygiene
Six caches keyed by `MediaTrack*` pointers can accumulate dead entries over long sessions: `insp_meter_clip`, `insp_meter_peak`, `insp_meter_display`, `insp_meter_noise`, `flow_mini_peak`, `track_fx_cache` (added v20.432; absorbed `flow_fx_cache` in v20.437). `SweepDeadTrackCaches()` runs every ~300 frames (~10s at 30fps) from `Loop`, walks each cache and drops entries whose pointer no longer validates.

### Remote Pages Persistence
`RemoteLoadPages` pipe-parse pattern requires trailing `|` in gmatch: `([^|]*)|`. Without the trailing pipe, pattern produces zero-length matches between pipes and page color/height never load. Matches `RemoteLoadButtons` pattern.

### BeginChild Guards
All 4 `BeginChild` calls (single-col `##content`, two-col `##content`, two-col `##sends_content`, Remote `##remote`) check return value. When `false`, skip entire body + `EndChild` to prevent `ImGui_EndChild` assertion crash. Remote was the holdout pre-v20.451.

### FX Name Clipping (InspDrawFXRow)
`Utf8DropLast` + "…" — never `PushClipRect` (cuts mid-glyph). Normal: full row width. Hovered: clips before button zone. Row hover via `IsMouseHoveringRect` on full row.

### Wet/Dry Parameter Resolution
Use `TrackFX_GetParamFromIdent(track, f, ":wet")` — resolves exclusively to REAPER's native wrapper param. Never scan by parameter name ("Wet") — matches internal plugin params. The A/B compare code and per-frame poll both use `wet_param_idx` from this resolution.

### PNG Icon Rendering
ImGui `AddImage` scaling is nearest-neighbor — unusable at small sizes. Provide PNGs at exact 2:1 rendered size. White-on-transparent, tinted via `DrawList_AddImage` color parameter.

### Send Envelope Naming
`InspFormatSendEnvName` matches envelope pointer via `BR_GetMediaTrackSendInfo_Envelope(track, 0, si, env_type)`. Format: `SND VOL - 27: Reverb`.

### Send Envelope Visibility
`SendEnvSetVisible`: resolve via `BR_GetMediaTrackSendInfo_Envelope`, flip `ACT`/`VIS` via gsubs, inject `PT 0 <unity> 0` if none exists (unity = 1 for vol, 0 for pan/mute).

### Flow View Stroke
White outline (`C.send_stroke`) follows `is_selected` (`chain_track == insp_track`), not `is_focus`. The stroke moves to whichever flow view card is currently being inspected. Send modules never get stroke.

### MuteOpts / SoloOpts Field Names
Return tables use `fg` / `fg_hov` for text color, not `txt`. Consistent with NavRect opts convention. The mute overlay redraw in `InspDrawTrackBlock` must reference `mc.fg`.

### ReaImGui Patterns
- **Mouse drag:** `GetMouseDelta` — no reset. Never `GetMouseDragDelta`.
- **Click detection:** `InvisibleButton` + `IsItemClicked`. Never manual rect-check.
- **Positioning:** `SetCursorScreenPos` for absolute. Never `SetCursorPos(box_x - window_x)`.
- **Keyboard focus:** `SetKeyboardFocusHere` BEFORE InputText. 3+ frame grace.
- **Draw list hierarchy:** Main window draw list behind children. Use `GetWindowDrawList` before `EndChild` for overlays. **`GetForegroundDrawList` renders ABOVE ImGui's popup layer** (v20.421) — anything drawn there will paint over open right-click menus, tooltips, etc. When using foreground draws for hover decorations (drag indicators, clipboard insert lines, dashed outlines), gate them on `not IsPopupOpen("", PopupFlags_AnyPopupId | PopupFlags_AnyPopupLevel)`. State that needs to survive across the popup-open frame (e.g. hover-track caching for stroke suppression) should run before the gate so it doesn't flicker when menus open/close.
- **ItemSpacing after widgets:** `GetCursorPosY` after `NavRect`/`InvisibleButton` includes `ItemSpacing.y`. When computing manual gaps, reset explicitly: `SetCursorPosY(ctx, known_y + widget_h)`.
- **Global drag state in flow view:** `insp_vol_dragging` is global — other tracks' `vol_row_hover` picks it up. Pair each drag flag with a `_drag_track` variable, check `== track` in hover computation.
- **Duplicate track cards in one frame (ID collision):** When rendering two track cards in the same frame (e.g. pinned primary + selected secondary), their internal widget IDs collide — FX rows use `PushID(5000 + fi)`, and buttons hash by label. Hovering/clicking widgets on one card routes to the other's handler. Wrap the entire second card — `CardBegin`/`CardEnd` and any `IsMouseHovering` rect checks on it — in `PushID("scope_name")`/`PopID`. Plumbing the `track` parameter through is not enough; ImGui routes events by ID, not by logical target. The secondary card is already wrapped in `PushID("nav_secondary_card")` at render time.
- **PushFont inside Begin/End only.** Font pushes outside a window's Begin/End block don't apply to that window's contents.
- **AlwaysAutoResize + width lock:** for fixed-width auto-height windows, use `SetNextWindowSizeConstraints(w, 0, w, 99999)` and compute content width from `GetWindowSize`, not `GetContentRegionAvail` (transient on first frame).
- **Popup first-frame GetContentRegionAvail is 0.** Any helper that reads `GetContentRegionAvail` and feeds it directly to `InvisibleButton` must guard `if avail_w < 1 then return <unchanged_value> end` — otherwise the assertion `size_arg.x != 0.0f && size_arg.y != 0.0f` fires on the popup's first frame. Applies to `SettingsRow`, `SettingsCollapsingRow`, `MenuCheckbox`.
- **Popups auto-size to InvisibleButton widths.** A popup with no declared size grows to fit its widest item. If an item uses `InvisibleButton(avail_w, ...)`, this feeds the popup's own current width back in and the popup never grows. For wide content like `MenuCheckbox` with long labels, compute `needed_w = CalcTextSize(label) + gap + control_w + padding` and pass `math.max(avail_w, needed_w)` to `InvisibleButton`.
- **Click-to-collapse containers must gate on `not IsAnyItemActive`.** A catch-all "click anywhere in card collapses it" check (distant sends, etc.) must include `not r.ImGui_IsAnyItemActive(ctx)` so knob/button clicks inside the card don't collapse the parent. On the click frame for any `InvisibleButton`, the button becomes active, so this check is true only for truly unclaimed clicks. Also capture `ct_clicked` from `DrawCompactTrackColumn` since the title InvisibleButton would otherwise prevent collapse even though we want title-row clicks to collapse.
- **Vol drag three-number alignment.** Any vol drag writing to `D_VOL` has three numbers that must agree to avoid a dead zone: (a) the dB value used when initializing from `vol=0`, (b) the lower clamp on the computed dB, (c) the threshold below which the write produces true 0. If these diverge — e.g. init at -150, clamp at -150, "write 0" at -100 — dragging up from -inf traps the user in the gap between init and write-0 threshold. Inspector vol (`InspDrawVolumeSlider` dB readout) and `RouteVolValue` both use -100 for all three. Sensitivity / 0-dB detent also harmonized at 0.15 dB/px / 0.3 dB. Note: `VolToKnobT` maps dB below -60 to t=0 (visually flat); for a *knob* with visible handle, -60 may be the better floor. For a text-only vol readout, -100 aligns with REAPER's own silence threshold.
- **Transparent tooltip windows clip stroke AA.** A `BeginTooltip` with `WindowPadding(0, 0)` and a manually-drawn rounded rect at the tooltip's outer bounds will clip the stroke's anti-aliasing pixels (~0.5px past the nominal edge). Symptom: sides look faded/barely visible, rounded corners look square. Fix: push `WindowPadding(S(2), S(2))` — the pad area is invisible because `PopupBg = 0x00000000`, but it gives the stroke clip-room to render clean edges. Used by the FX drag floating preview in `FxDragResolveDrop`.
- **FX drop target body_rect conventions.** The inspector registers `body_rect` as the **card outer bounds** (content bounds expanded by `card_pad`/`card_pad_top`/`card_pad_bot` when `opt_card_boxes` is on). Sends-view already registers outer bounds via `DrawCompactTrackColumn`'s `cx/cy/col_w/col_h`. Any visual that traces the destination card edge (e.g. dashed outline) expects outer bounds from both surfaces — if only one registers inner bounds, the outline is inconsistent between surfaces. Inspector was the buggy one in v20.403–v20.404; fixed in v20.405.
- **Mid-loop array replacement requires per-iteration validation (v20.438).** When a loop captures `n = #arr` up front and iterates `for i = 1, n`, but the loop body can replace the global `arr` (e.g. a click handler that calls `FlowViewSetFocus` rebuilding `flow_view_chain`), subsequent iterations may read past the new array's length and get nil. The flow chain render loop hits this on skip-clicks (double-clicking a non-adjacent ancestor): focus path validates via `flow_prepare_track` and breaks, but `FlowDrawMinimalCard` had no guard. Fix is one line at the top of the loop body: `if not chain_track or not r.ValidatePtr(chain_track, "MediaTrack*") then break end`. The clicked card's render in the same frame is harmless (it draws as it was at click time); the new focus appears correctly next frame.

### Height Formula Pitfalls (DrawCompactTrackColumn)
Add-FX placeholder: `(fx_count + 1)` slots when uncollapsed. FX cache refreshed before height computation. Title measured with title font. Distant sends include SND header row.

### Hover Stroke Ordering
Draw hover strokes AFTER `DrawCompactTrackColumn` via `AddRect` — strokes before get painted over by card bg.

### Other
- `Spacing()` resets cursor X to 0 — re-anchor with `SetCursorPosX` before each FX row.
- Screen-space throughout for DrawList helpers. Mixing conventions causes sub-pixel drift.
- `BeginGroup`/`EndGroup` required for `SameLine` between composite widget stacks.
- `x and false or y` always returns `y` — use if/else.
- `S(2)` at low scales rounds to 1px — use `S(3)` minimum for visible gaps.
- `CircleTessellationMaxError`, `DragDouble`, `ColorEdit4` — nil-check before use.
- Docker frame consumes ~2px of WindowPadding. `gap_px = S(UI.edge_pad) - 2`.
- Right-side dock gaps are theme-sensitive. Full `Reflex.lua` keeps the historical chrome extension for left dock and Reapertips, but when docked right under other REAPER themes it must not extend child/card width by `S(UI.edge_pad) - 3`; keep the right edge at normal `WindowPadding` and move the scroll indicator to the same inset.
- **Tooltip categorization (two categories, different gating):**
  - *Functional* tooltips — the tooltip IS the label, for a symbol/dot/thumbnail whose content varies per session and is not memorizable. **Always-on**, ignore `opt_tooltips`. Sites: `ShowRoutingTooltip` (routing pill persistent list; in `Reflex_RouteTooltipCore.lua` as of v20.530), TLT mini-circle track names, FX icon picker filenames.
  - *Descriptive* tooltips — describe memorizable behavior on a fixed symbol (single-letter buttons "R"/"A"/"X", modifier-key hints via `ShowModKeyTip`, misc action descriptions). **Gated** on `opt_tooltips` at the call site via `and opt_tooltips` in the hover condition.
  - Helpers `Tip()` / `TipDirect()` / `ShowModKeyTip()` push compact `WindowPadding`/`WindowRounding` before `SetTooltip`/`BeginTooltip`. `Tip()` is self-gating; `TipDirect()` and `ShowModKeyTip()` are always-on — call sites decide. No raw `SetTooltip` calls.
  - **FX-row tooltip (v20.424).** Both surfaces show `Shift: bypass / Opt: remove / Cmd+Shift: offline` on FX-row hover. Descriptive (gated on `opt_tooltips`). Inspector previously had no FX-row tooltip; v20.424 added one for parity. "Click: open" omitted from both — self-explanatory and was visual noise. **Suppressed during carry mode** at both call sites — the descriptive text competes with insert-indicator/dashed-outline visuals and the carry-pill messaging. Suppression check is `if not FxClipHasContent() then Tip(...)` at the call site, not inside the helper.
- Background-level labels (`C.bg_label`, `UI.bg_label_gap_above/below`): centralized style for text on script bg (e.g. "Distant Sends", "Selected track").
- Pin unpin: must call `SetOnlyTrackSelected(insp_track)` to prevent main loop's unpinned branch from switching to TCP selection on next frame. Pin state stored in view history snapshots.

---

## FX Multi-Select (v20.403–v20.406)

Inspector AND sends-view surfaces support FX multi-selection with drag adoption. Primary, secondary (pinned mode), and send modules are all valid surfaces.

### Bindings

| Modifier | Action |
|---|---|
| `Cmd+click` | Toggle individual FX selection (sets anchor) |
| `Ctrl+click` | Range-select from anchor through this row (anchor doesn't advance) |
| `Shift+click` | **Bypass** (preserved — core REAPER binding; never displaced) |
| `Opt+click` | Remove FX |
| `Cmd+Shift+click` | Offline toggle |
| Plain click | Show FX (chain/float) |
| Right-click | FX context menu |

All non-multi-select branches call `InspFxSelClear()` before their action. The "any other interaction clears" rule is strict; will be revisited when Cmd+X/C/V clipboard lands.

### State

| Global | Purpose |
|---|---|
| `insp_fx_sel` | `{[guid] = true}` — set of selected FX GUIDs |
| `insp_fx_sel_track` | `MediaTrack*` the selection belongs to; binding via `InspFxSelBindTrack` clears on mismatch |
| `insp_fx_sel_anchor` | GUID used as range-select anchor |

GUID storage survives REAPER FX reorder naturally. Selection is per-track. Switches that navigate away from the selected track clear via `InspCleanupDragState → InspFxSelClear`; FLOW browsing and other visible-card switches preserve selection when the bound track remains rendered.

### Helpers (all global assignment, file-scope)

`InspFxSelClear`, `InspFxSelCount`, `InspFxSelHas(guid)`, `InspFxSelBindTrack(track)`, `InspFxSelToggle(guid)`, `InspFxSelAdd(guid)`, `InspFxSelRangeSet(track, end_guid)`, `InspFxSelGetFis(track)`.

**Takes-a-track-arg rule (v20.406):** `InspFxSelRangeSet` and `InspFxSelGetFis` both require a `track` argument and iterate `r.TrackFX_GetCount` + `r.TrackFX_GetFXGUID` directly. They must NOT read `insp_fx` (which only holds the inspected track's FX — wrong for secondary card, wrong for sends modules). Any future selection helper that walks FX by index must follow this pattern.

### Outline Render (both surfaces)

Unified via `FxRowOutlineColor` helper (v20.422, Phase 2 of FX-row unification; moved to `core/Reflex_FXRowCore.lua` in v20.526). 4-state cascade in priority order (mutually exclusive):

1. **Drag active + row in `fx_drag.src_fis` + `fx_drag.src_surface == surface`** → operation color from live `FxDragReadMode()` (washed red for move, blue for copy)
2. **Drag inactive + `NavPasteLandedHas(track, guid)` and alpha > 0** → animated green (paste-landing pulse)
3. **Drag inactive + `FxClipHasGuid(guid)`** → carry green `C.fx_clip_carry`
4. **Drag inactive + `InspFxSelHas(guid)`** → white `C.fx_sel_outline`
5. Otherwise → nil

Empty-guid guard on all guid-based branches (defensive, near-zero cost). Caller draws its own `AddRect` — only the color/priority logic is unified, since the row rect geometry differs between surfaces. Inspector call site at end of `InspDrawFXRow`. Sends call site at end of the real-FX branch in `DrawCompactTrackColumn`. Both use `AddRect` with `math.max(1, S(1))` thickness on a row-radius matching the row bg.

**v20.422 surface gate fix.** The drag-source branch now requires `fx_drag.src_surface == surface`. Previously inspector didn't gate on surface, only on `src_track == fx.track` — in self-send edge case (an inspected track that's also a sends-view return), dragging from a sends column would falsely light up the inspector's matching rows. Fix is purely defensive; observable only in unusual self-send setups.

**v20.403 dropped the 60% black dim on move sources.** The operation-color stroke alone conveys "this is leaving" without the double signal of dimming, which made sources look "gone" before they were.

### Drag Integration

Selection is **adopted into the drag at activate, not at seed**. `FxDragTryActivate` expansion:

```
if insp_fx_sel_track == fx_drag.src_track and InspFxSelCount() > 0:
    if seed_guid not in insp_fx_sel: InspFxSelAdd(seed_guid)   -- Option C promotion
    fx_drag.src_fis = InspFxSelGetFis(fx_drag.src_track)        -- sorted ascending
```

Promotion at activate (not seed) means Cmd+click without drag doesn't visually churn — a Cmd+click that never exceeds threshold is a plain toggle, unaffected. Dragging an unselected row when a selection exists on that track promotes + drags.

**No `insp_track` gate, no surface gate** (v20.406). Selection expansion applies to inspector, secondary card (pinned mode), and sends — anywhere the selection is bound to the drag's source track.

**`fx_drag.seed_guid`** cached at `FxDragBegin` via `r.TrackFX_GetFXGUID(track, fi)`. Previously `FxDragTryActivate` iterated `insp_fx` to find the seed's guid, which fails for secondary/sends sources because `insp_fx` holds only the inspected track's FX.

### Selection Clear Sites

Every non-multi-select click branch (plain/Shift/Opt/Cmd+Shift), right-click (pre-popup), track switches that remove the selected track from visible Reflex surfaces (via `InspCleanupDragState`), Escape (via `FxDragPollEscape`, even when no drag is seeded), drag commit. v20.525: FLOW card browsing preserves FX selection if the selected FX track remains visible in the chain.

---

## FX Drag Pipeline (v20.394–v20.406)

Cross-chain FX drag-and-drop with modifier-driven copy/move variants and multi-source support.
The drag/drop backend helpers and state live in `Reflex_FXDragCore.lua` as of v20.521; `FX.row` rendering, `SEND.col` rendering, and flow-card renderers remain in `Reflex.lua` and call the same global helper names.

### Architecture

Four-stage lifecycle: **seed → activate → commit/abort → cancel**.

| Helper | Purpose |
|---|---|
| `FxDragBegin(track, fi, surface)` | Seed on mouse-down over an FX row. `fi` 0-based, `surface` = `"inspector"` \| `"sends"`. Records `start_mx`/`start_my`, caches `is_instr` and `seed_guid`. Does NOT activate. |
| `FxDragTryActivate()` | Flips `active=true` once mouse Y-delta exceeds `S(FX_DRAG_THRESHOLD)` (8 logical px). On activate, expands `src_fis` from `insp_fx_sel` if bound to src_track. |
| `FxDragIsActive()` / `FxDragSourceIs(track, surface)` | Predicates for gating other per-row behavior during drag. |
| `FxDragPollEscape()` | Called once per frame at top of Loop. Sets `cancelled` flag, clears drag state, clears selection. |
| `FxDragClear()` | Release/cancel cleanup. Resets all `fx_drag.*` fields including `tooltip_shown`/`src_chain_rect`/`is_instr`/`seed_guid`. |
| `FxDropTargetRegister(surface, track, rects, fx_count, body_rect, card_id, fx_area_bottom_y, row_x, row_w)` | Each target FX chain registers itself once per frame during render. `body_rect` = card OUTER bounds for both inspector and sends. |
| `FxDropComputeTarget(entry, mx, my)` | Returns `(target_fi0, is_end)` for a given cursor position over a registered target. |
| `FxDragResolveDrop()` | Called once at frame end (before main `End()`). Finds target, draws dashed destination outline + indicator line + floating row-style preview, commits on mouse release. |
| `FxDragAutoScrollCheck` / `FxDragApplyScroll` | Mousewheel + edge-proximity auto-scroll within `##content` and `##sends_content`. Remote `##remote` excluded. |
| `FxDragReadMode()` | Live modifier read → `(op, with_auto)` per modifier table below. |
| `FxStripAutomation(track, fx_idx)` | Post-commit envelope strip (API-only, no chunks). |
| `FxDragTrackLabel(track)` | Undo-label formatter with "Track N" fallback. |
| `FxDragLegendTip()` | Pre-drag modifier legend tooltip. Gated on `opt_tooltips`. |

### Modifier Table (v20.401)

Option C: **user intent over modifier consistency**. Default behaviors match what users would expect per operation. Opt is the "automation-variant" modifier; its semantics flip based on operation because the defaults flip.

| Modifier | Operation | Automation | Source/dest stroke color |
|---|---|---|---|
| drag | move | **yes** (default) | washed red `C.fx_drag_move` |
| Opt+drag | move | no | washed red |
| Cmd+drag | copy | **no** (default) | blue `C.fx_drag_copy` |
| Cmd+Opt+drag | copy | yes | blue |
| Shift+drag | reserved | — | — |

### Envelope Behavior (Empirical — REAPER 7.69/macOS-arm64)

`TrackFX_CopyToTrack(src, src_fi, dst, dst_fi, is_move)` **brings envelopes along in BOTH `is_move=true` and `is_move=false` modes.** This is the opposite of REAPER's UI cut/paste default (which excludes automation). No API flag exists to suppress envelope transfer — must strip post-hoc.

Reflex's defaults invert REAPER's UI convention because UX intent differs: moving a plugin implies automation follows (it's attached to the thing); copying implies fresh instance (starting over). So drag = keep envelopes (no strip needed, is_move=true), Cmd+drag = strip envelopes (is_move=false + `FxStripAutomation`).

### `FxStripAutomation` Pattern

API-only, no chunk manipulation:
1. Enumerate params: `0..NumParams-1`, plus `:wet` and `:bypass` via `TrackFX_GetParamFromIdent`
2. For each param, `GetFXEnvelope(track, fi, p, false)` — don't create
3. **Content check (v20.402):** tally `CountEnvelopePointsEx(env, -1)` plus points across all `CountAutomationItems`. If total is 0, SKIP this envelope entirely.
4. Otherwise: delete all automation items' points, delete all underlying points via `DeleteEnvelopePointEx`
5. Flip `ACTIVE=0` and `VISIBLE=0` via `GetSetEnvelopeInfo_String` so the lane disappears from UI immediately (not just on save)
6. **Force TCP layout recalc (v20.402):** if any envelope was actually stripped, call `TrackList_AdjustWindows(false)` at the end. Without this, REAPER's TCP doesn't reclaim the deactivated envelope's vertical space until the user navigates away and back.

Two distinct gotchas, both produce "ghost lane" symptoms (blank lane slot with no header/name/content), both fixed together:

**Gotcha 1 — Implicit bypass container:** `GetFXEnvelope(track, fi, bypass_idx, create=false)` returns a valid envelope handle for `:bypass` even when the user never created one — REAPER maintains an implicit bypass-envelope container on every FX. Strip-poking that empty container (flipping ACT/VIS with no points present) produces a serialized-but-hidden envelope in the track chunk. Fix: only act on envelopes with actual content. Empty envelopes are skipped; their implicit container stays untouched. (Observable in saved .RPP as stray `BYPASS 0 0 0` lines between FX entries — see EQ.RPP test project from v20.402.)

**Gotcha 2 — TCP layout cache staleness:** Even when the strip is correct (real param envelope with points, ACT=0/VIS=0 correctly flipped, REAPER's env panel agrees nothing is visible/armed), the TCP doesn't immediately reclaim the envelope's vertical slot. The lane slot remains drawn empty until a layout recalc is triggered by the user navigating away from the track. Fix: explicit `TrackList_AdjustWindows(false)` after strip, but only when something was actually stripped — avoids a cascading refresh for no-op calls.

Empty-points-alone would work for invisible envelopes on save (REAPER strips empty env blocks on save), but flipping ACT/VIS makes it visually immediate — provided the TCP layout also refreshes.

### Multi-Source Commit Algorithm (v20.403+)

`fx_drag.src_fis` is always a sorted ascending 0-based array. `FxDragResolveDrop` branches on `same_chain × op` for the commit:

**Single-source** (n=1): preserved bit-for-bit from v20.402 — single `TrackFX_CopyToTrack` call with `dst_fi0` decremented by 1 if `op=="move" and same_chain and src < dst`.

**Multi-source same-chain move:** split sources by position relative to target. Below sources (s < target) process descending with `t` decrementing each step (each move shifts higher indices down). Above sources (s > target) process ascending with `t` reset to the original target (below moves don't affect above positions).

**Multi-source same-chain copy:** ascending order, t advances per insertion, source index shifted by `(i - 1)` when `s >= target` to compensate for prior insertions shifting originals down.

**Multi-source cross-chain (move or copy):** descending order, each insert lands at target_fi0 pushing priors down by 1.

All paths wrapped in a single `Undo_BeginBlock`/`Undo_EndBlock`. `FxStripAutomation` called on each destination index per-insert when `not with_auto`.

### Insert Indicator

Operation color (washed red / blue). All positions use `S(UI.fx_gap/2) = S(3)` offset. Row-half binary for row hits; extended hit zones include half-gaps above/below each row. Anything outside the row list (card body, above first row, below last) falls through to end-of-chain — matching REAPER's "append" semantics and the rule: only precise row gaps are explicit insert points. Empty-chain indicator uses `row_x`/`row_w` for width (not `body_rect` — too wide). For empty inspector chains, `fx_bottom_y` is offset by `S(UI.section_gap)` at registration to simulate where row 0 would appear.

### Dashed Destination Outline (v20.404–v20.405)

`DrawDashedRoundedRect` traces the destination card's full rounded perimeter (including arc corners) at `body_rect + S(UI.card_r)` rounding. Thickness `S(1.5)`, dash `S(5)`, gap `S(3)`.

**Suppressed on source card** (`hit.track ~= src_track`). Internal drags use only the indicator line + source-row strokes; a dashed ring around the source card itself is redundant visual noise.

**Requires `body_rect` to be card outer bounds.** Inspector expansion at registration time by `opt_card_boxes and S(UI.card_pad/pad_top/pad_bot)`; sends already registers outer bounds via `DrawCompactTrackColumn`.

### Floating In-Flight Preview (v20.403 row-style redesign)

Rendered inside `BeginTooltip` (not `GetForegroundDrawList`) so it can extend past the script window edge onto the desktop.

**Chrome:** `PopupBg = 0x00000000`, `WindowPadding(S(2), S(2))`, `WindowBorderSize(0)`. The 2px padding is invisible (transparent bg) but gives stroke anti-aliasing clip-room.

**Content:** row-style card (fill = `C.fx_row_bg`, stroke = operation color, radius `S(3)`) with `Dummy(total_w, total_h)` to reserve auto-size space. Text:
- Single FX: name from `TrackFX_GetFXName` (vendor paren stripped). Text color = `C.fx_instr_txt` if `fx_drag.is_instr` (cached at seed), else `C.text`.
- Multi-select: `"N plugins"` in `C.text_dim`.
- Automation suffix appended when modifier variant active: `"  no auto"` (Opt+move) or `"  + auto"` (Cmd+Opt+copy).

**Sticky visibility:** `fx_drag.tooltip_shown` flips true once the cursor has ever left the source chain bounds OR when `#src_fis > 1`. Once true, stays true for the drag lifetime.

### Pre-Drag Modifier Legend (`FxDragLegendTip`)

When Cmd or Opt is held over an FX row AND no drag is yet active, shows a 4-mode legend via `TipDirect`. Gated on `opt_tooltips` (descriptive category per v20.392 tooltip categorization). Wired at both inspector `InspDrawFXRow` and sends `DrawCompactTrackColumn` FX row hover scopes. Mac symbols: `⌘ ⌥`.

### Commit Logic & Undo Labels

Release-frame commit reads mode live, branches on `is_move_flag`, calls `FxStripAutomation` only when `not with_auto`. Single `Undo_BeginBlock`/`Undo_EndBlock` pair wraps all operations. Labels pluralize with count for multi:

- `Reflex: Reorder FX` / `Reflex: Reorder 3 FX` / both with ` (no auto)` suffix
- `Reflex: Duplicate FX` / `Reflex: Duplicate 3 FX` / ` (no auto)`
- `Reflex: Move FX from SNARE to KICK` / `Reflex: Move 3 FX from SNARE to KICK` / ` (no auto)`
- `Reflex: Copy FX from SNARE to KICK` / `Reflex: Copy 3 FX from SNARE to KICK` / ` (no auto)`

`src_name`/`dst_name` use `FxDragTrackLabel` with "Track N" fallback for unnamed tracks.

### Noop Detection

Applies to single-source `op == "move"` in same-chain when target is adjacent to source. Copy-in-same-chain is valid (duplicate). Multi-source intentionally always commits — user can Ctrl+Z. Insert indicator is hidden on noop for visual de-emphasis.

### Source Visual Overlay Ordering

Must be drawn AFTER all content of the row (text, badges, hover states) so it overlays properly. Inspector: placed before the final `SetCursorPos`/`PopID` at end of `InspDrawFXRow`. Sends: placed after `PopPopupStyle()` at end of the real-FX branch in `DrawCompactTrackColumn`, before the empty-slot `else`.

### Cross-Chain Drag-Drop ID Collision

When rendering two track cards in one frame (e.g. pinned primary + selected secondary), widget IDs collide — inspector FX rows use `PushID(5000 + fi)`, sends use `"##sfxi" .. fi`. Hovering/clicking one card can route to the other's handler. Secondary card is wrapped in `PushID("nav_secondary_card")` at its render site. Any future rendering of duplicate cards in one frame must add a similar scope.

### Expand Arrow Convention (v20.395)

Opt+click on any dedicated expand arrow = toggle-all (expand/collapse all similar). Routing pill is NOT a dedicated arrow — Opt there toggles parent send instead. Cmd+click on FX rows is now multi-select toggle (v20.403+), not expand-all.

---

## API Limitations

- No inter-FX audio level metering API
- `JS_Window_SetPosition` required for FX window positioning
- Cross-window ImGui drag-drop not possible
- `CreateTrackSend(track, -1)` broken in Lua for hardware outputs
- ImGui window size constraints don't apply when docked
- No undo stack enumeration
- ImGui `AddImage` nearest-neighbor scaling — provide PNGs at 2:1
- REAPER UI has no way to change an existing send's destination track while preserving send count (only delete + recreate). Destination-change detection in `SendsViewCheckRefresh` is defensive against API-initiated or undo-replayed routing changes.
- `TrackFX_CopyToTrack` has no "copy/move without envelopes" variant — envelopes always transfer regardless of `is_move` value. Use `FxStripAutomation` post-hoc when envelope-free behavior is needed.
- No single-call `DeleteAutomationItem`. Clear its points via `DeleteEnvelopePointEx(env, ai, ...)` loop; empty auto items persist but are benign.
- ImGui DrawList has no native dashed stroke. Use `DrawDashedRoundedRect` (polyline trace + dash-phase cursor) when dashes must follow rounded corners.

---

## FX Clipboard (v20.407–v20.417)

Cmd+C / Cmd+X / Cmd+V acting on FX multi-selection (or hovered FX as fallback). Cross-track, cross-project within session. Lives alongside FX drag-drop; shares the drop target registry and several visual conventions.
The clipboard backend helpers and state live in `Reflex_FXClipboardCore.lua` as of v20.522; shortcut dispatch, footer chip UI, and source/target renderers remain in `Reflex.lua`, while the shared `FX.row` menu body moved to `Reflex_FXRowCore.lua` in v20.526.

### Architecture

Chunk-based: capture extracts each FX's chunk from `GetTrackStateChunk`; paste splices them back in via `SetTrackStateChunk`. Wet values restored after paste (defensive; chunk should preserve them but user-facing wet drift is painful to debug). FXIDs regenerated on paste via `r.genGuid("")` — `SetTrackStateChunk` preserves FXIDs verbatim, which would break selection/outline matching across pastes.

Helpers (all global assignment, file-scope):

| Helper | Purpose |
|---|---|
| `FxChunkSplitLines/JoinLines/LineKind/FindFxchain/FxRanges/ExtractFxBlock/SpliceFxBlocks/RegenFxids` | Chunk parser primitives |
| `FxClipCapture(track, fis, op, include_automation)` | Extract chunks; cut deletes originals atomically |
| `FxClipPaste(track, insert_at_fi)` | Splice + restore wet + strip automation if `!include_automation`; bumps `paste_count`; captures landed guids for pulse animation |
| `FxClipResolveHover()` | End-of-frame consumer: dashed destination outline + insert indicator on hovered card. Owns `fx_drop_targets` registry clear (moved out of drag pipeline) |
| `FxClipExecutePendingPaste()` | Deferred-paste consumer for Cmd+V keystrokes (registry must be populated before paste-target resolves) |
| `FxClipRenderCarryPill()` | Cursor-following pill via `BeginTooltip`. Auto-dismissed after first paste |
| `FxClipDoCopyOrCut(op, include_automation)` | Resolves selection-or-hover, captures, clears guid set |
| `FxClipConvertCopyToCut()` | Deletes source FX matching clipboard guids; flips `op` to "cut" |
| `FxClipCopyAllFX(track, include_automation)` | All FX from track |
| `FxClipRemoveAllFX(track)` | Clear chain (Shift+Delete) |
| `FxClipDeleteSelection()` | Delete on multi-select (Delete/Backspace) |
| `FxClipFindHoveredRow/Card` | Hover resolution against `fx_drop_targets` |
| `FxClipResolvePasteTarget()` | Paste landing logic: hovered row → hovered card → inspected track |
| `FxClipRebuildGuidSet/HasGuid` | Source-row outline matching |
| `FxStripAutomation(track, fx_idx)` | API-only envelope strip (also used by drag pipeline) |

State globals: `nav_fx_clipboard = {op, count, source_track, source_track_name, include_automation, paste_count, items[{chunk, wet, fx_name, is_instr}]}`. Plus `nav_fx_clipboard_guid_set`, `nav_fx_clip_pending_paste`, `nav_fx_paste_landed`, `nav_fx_clip_last_hover_track`.

### Keyboard Shortcuts

| Combo | Action |
|---|---|
| `⌘C` | Copy selection (or hovered single FX), no automation |
| `⌥⌘C` | Copy with automation |
| `⇧⌘C` | Copy all FX from hovered/inspected track |
| `⌘X` | Cut, no automation. Empty source case: converts existing copy-clipboard to cut |
| `⌥⌘X` | Cut with automation |
| `⌘V` | Paste below hovered row (or end of inspected chain if no row hovered) |
| `⌫` (Delete) | Delete selected FX |
| `⇧⌫` | Remove all FX from hovered/inspected track |
| `⌘B` | Toggle bypass on selection |
| `⌥⌘B` | Toggle offline on selection |
| `Esc` | Clear clipboard (full exit from carry mode) |

All clipboard/delete/bypass shortcuts gated on Reflex focused (`IsWindowFocused(RootAndChildWindows)`). See "Focus model" below.

### Right-Click Menu (REAPER-Native Layout)

Both inspector + sends surfaces match REAPER's native FX menu order: Copy all FX → Copy → Copy (w/ auto) → Cut → Cut (w/ auto) → Paste above / Paste below (`⌘V`) → ── → Remove → Remove all FX → ── → FX bypass (`⌘B`) → FX offline (`⌥⌘B`) → ── → Duplicate → Rename FX instance.

**Unified via `FxRowContextMenu` helper as of v20.419 (Phase 1 of FX-row unification); moved to `core/Reflex_FXRowCore.lua` in v20.526.** Single source for menu structure, labels, and click handlers. Rename FX instance works on inspector and SEND.col rows through the track-bound inline rename state introduced in v20.430. Post-action FX cache freshness routes through `InspMarkTrackFxDirty(track)`.

**Label shorthand (v20.424):** "(include automation)" → "(w/ auto)" everywhere. Carry-pill suffix already used "+ auto" / "no auto"; menu labels brought into alignment.

**Inspector popup style fix (v20.419 side-effect):** before Phase 1, inspector's `##fxctx` was the only `BeginPopup` site without `PushPopupStyle` wrap. Helper wraps internally — inspector now matches every other Reflex popup (slightly tighter padding/rounding). Treat as bug fix, not behavior change.

Selection-aware: when right-clicked row is part of a live multi-selection, all action items operate on the selection (pluralized labels: "Cut 3 FX (w/ auto)"). Otherwise single-row.

Right-click does NOT clear selection (changed v20.407). Right-click is also NOT gated on focus-grab suppression (right-click during carry mode is a valid gesture — opens menu with paste options).

### Visual States

Carry mode has tiered visual loudness:

**Loud (during `paste_count == 0`):**
- Carry pill follows cursor when over Reflex. When unfocused, appends "click to focus" hint in dim text.
- Source-row green outlines (`C.fx_clip_carry`) on FX matching clipboard guids
- Chip in footer with × to clear

**Hover-conditional (any time clipboard non-empty + Reflex focused):**
- Dashed destination outline on hovered card (uses `DrawDashedRoundedRect` against card outer bounds). **Suppressed on the source card itself** (visually noisy, redundant with the green source-row strokes that already mark the card; mirrors drag-pipeline convention).
- Green insert-indicator line at row gap or end-of-chain. **Drawn on all cards including the source** (v20.423) — users can paste back into the source chain at a specific row position. Earlier the entire decoration block was gated on `not is_source` and the indicator went missing when hovering the source card; v20.423 split the gate so only the dashed outline is suppressed on source.
- Card pin/selected strokes suppressed on hovered drop target via `NavCardIsDropTarget` (drag + clipboard share this)

**Confirmation (after paste, 1.1s):**
- Animated green outline on landed FX. Curve: 0–100ms ramp 0→1, 100–500ms two sin pulses 0.8↔1.0, 500–1100ms linear fade to 0
- Captured via `nav_fx_paste_landed = {track, guids, started_at}`; consumed by `NavPasteLandedAlpha()` / `NavPasteLandedHas(track, guid)`. Cascade priority above carry-green so confirmation wins until expiry

**Silent (after first paste, `paste_count >= 1`):**
- Pill, source outlines, dashed/insert all gone. Clipboard data persists; Cmd+V still pastes silently (matches REAPER's clipboard model)
- White multi-select outline re-emerges where applicable (selection data was preserved through carry — green covered it, didn't destroy it)

### Outline Cascade (Single Source of Priorities)

Unified via `FxRowOutlineColor` helper as of v20.422 (Phase 2 of FX-row unification); moved to `core/Reflex_FXRowCore.lua` in v20.526. See "Outline Render (both surfaces)" under FX Multi-Select for the canonical priority list. Both inspector (`InspDrawFXRow`) and sends (`DrawCompactTrackColumn` real-FX branch) call the same helper; outline color decisions live in one place.

### Selection Lifecycle

Copy: selection cleared on first paste (v20.424). Cut already implicitly clears (sources are gone); copy now matches. Rule: paste ends the operation, full stop. Subsequent silent pastes have no selection to clear, so no special-case needed. The white selection outline persisting through the carry-mode visual reset (pill, source-strokes, chip all gone after first paste) was the odd signal out — looked like residue from a finished action.

Cut: selection cleared (source FX deleted → stale refs).
Track switch: cleared via `InspCleanupDragState → InspFxSelClear` only when the selected FX track is no longer visible in Reflex; v20.525 preserves it across FLOW card browsing while the bound track remains rendered.
Esc / chip × / new copy: cleared as part of full clipboard clear.

### Focus Model (v20.414+)

REAPER and Reflex both bind ⌘C/⌘X/⌘V; macOS routes keystrokes to whichever window has OS focus. Earlier v20.410 attempt to widen dispatch to `focused OR hovered` created a worse bug (UI promised paste; REAPER consumed the keystroke and pasted its own clipboard). Reverted to **strict focus-required** in v20.414.

Rule: action shortcuts and drop-target indicators (dashed outline, insert line) require Reflex focused. State indicators (pill, chip, source outlines, multi-select outlines) remain on regardless of focus.

User-facing rule: *"if you see the dashed green outline, paste will land there. If you don't, click Reflex first."*

### Focus-Grab Click Suppression (v20.417, persistence fix v20.435)

When carry-pill says "click to focus" and user's focus-grab click lands on an FX row, the row's normal action (open plugin UI, toggle bypass, M/S, etc.) would fire before user can press Cmd+V. Solution: detect `nav_focus_was = false → true` transition in carry mode at top of `if visible` block, set `nav_focus_grab_eat_click = true`, gate FX-row click branches (inspector + sends, plain + modifier dispatch + drag-begin) on `not nav_focus_grab_eat_click`.

**v20.435 — persistence across press→release cycle.** The original implementation set `eat_click = true` only on the focus-transition frame (the press), then unconditionally cleared on the next frame. ImGui Selectable's `sel` return fires on RELEASE (frame N+1 from press), at which point `nav_focus_was` had already updated to `true` and `eat_click` had reset to `false` — so the action gate at `FxRowInteract` saw `eat=false` on release and fired anyway. Fix: set `eat_click` only when focus transitions during a mouse-down (`r.ImGui_IsMouseDown(ctx, 0)`), and persist until the frame after release (`not mouse_down and not r.ImGui_IsMouseReleased(ctx, 0)`). The flag now spans the entire press→release cycle so both press-frame and release-frame gates see `eat=true`.

**Bg click also gated (v20.435).** The bg-click release handler (selection clear) now checks `not nav_focus_grab_eat_click` so a focus-grab click on script bg doesn't fire deselect either — pure focus grab with no side effects.

Signal is narrow by design: requires unfocused-last-frame + focused-this-frame + clipboard-has-content + left-mouse-button-down at the moment of transition. Right-click and pure focus-restore (alt-tab) don't trigger.

### Right-Click Focus Grab (v20.435)

ImGui auto-focuses windows on left-click but not right-click. macOS default for separate-OS windows: right-click on an unfocused window delivers the click but doesn't activate the window. Workflow that exposed this: REAPER focused → user right-clicks an FX in Reflex → context menu opens → user clicks Copy → menu closes → Reflex still unfocused → ⌘V intercepted by REAPER. User had to click Reflex to focus, but every other-place-to-click had a side effect (FX row → opens plugin UI; bg → cleared clipboard pre-fix; etc).

Fix: at top of main loop after `Begin`, gate on `IsMouseClicked(1) && IsWindowHovered(... | AllowWhenBlockedByActiveItem | AllowWhenBlockedByPopup)` and call `r.ImGui_SetWindowFocus(ctx)`. Any right-click within Reflex's window bounds — FX row, header, knob, bg — triggers focus grab. Whether `SetWindowFocus` bridges OS-level activation depends on ReaImGui's docking-branch viewport implementation; if testing reveals it doesn't fully focus on macOS, fallback is `JS_Window_SetFocus(reflex_hwnd)` via JS_ReaScript.

### Bg Click Behavior (v20.435 update)

Bg click (release within 4px of press, no item hovered, no popup open) clears FX selection. **Does NOT clear the clipboard** as of v20.435 — previous behavior was contradicting the focus-grab UX (carry mode prompts user to "click to focus", but clicking bg dropped what they were carrying). Clipboard now only exits via Esc, the chip × button, paste completion, or a new copy/cut. Pin is intentionally untouched (different category: persistent view setting, not transient operation state).

### Reflex vs REAPER Clipboard Mental Model

Both clipboards are independent and run in parallel. Reflex's clipboard is in-memory Lua state, scoped to session. REAPER's clipboard is its own. Cmd+V in Reflex-focused state pastes Reflex's clipboard; Cmd+V in REAPER-focused state pastes REAPER's. There's no synchronization, and no interception (interception would require system-level keyboard hooks — explicitly out of scope, see Architectural Decisions).

### I/O Manager

`RecordIODrawManager()` is a Reflex-native floating panel opened from `HDR.input` right-click (`Edit aliases / favorites`), from the NAV global popup (`I/O Manager`), and from the Reflex Settings/gear panel. `RecordInputOpenManager(track, value)` maps launch context to the default page and optional target alias cell: audio mono/stereo/multichannel values open `Audio In`; MIDI device values open `MIDI In`; `None` and `All MIDI Inputs` open `MIDI In` without auto-edit. The panel pages are `Audio In`, `Audio Out`, `MIDI In`, and `MIDI Out`; each page has inline alias cells, subtle alternating row backgrounds, a bottom filter field, a close button, and table-backed virtualized rows with resizable/sortable columns. Audio pages also show a bottom `Restart Audio` button. First open targets ~75% of the available viewport height and can be resized taller up to the work-area constraint.

Audio aliases use REAPER config alias sections in the running install's active `reaper.ini` from `get_ini_file()` (portable-safe): inputs write `[alias_in_<IDENT_IN>]`, outputs write `[alias_out_<IDENT_OUT>]`, and commits update `nameN`, `chN`, `map_size`, and `map_hwnch` together. For section names, Reflex normalizes the runtime `GetAudioDeviceInfo("IDENT_IN"/"IDENT_OUT")` string by replacing whitespace with underscores because REAPER stores CoreAudio alias maps as e.g. `[alias_in_CoreAudio_2:_Aurora(n)-TB]` even when the live ident is `CoreAudio 2: Aurora(n)-TB`. Blank commits remove the `nameN` key rather than writing an empty alias. Audio rows keep both `#` and `HW#`; current implementation maps both to REAPER's exposed slot number and uses `GetAudioDeviceInfo("INPUTN"/"OUTPUTN")` for the hardware/original name only when it does not match the active or just-cleared alias, otherwise it falls back to neutral `Input N` / `Output N`. Output page population uses the max of REAPER live counts, `GetAudioDeviceInfo` counts/probes, and active alias-section map sizes/ch rows/name rows so pages still show devices when one source reports zero. Audio native sync is best-effort because REAPER exposes no documented alias setter; `IOMGR.audio` shows `Live`, `Written`, `Pending`, or `Native`. `HDR.input` and its popup prefer the saved active-device alias immediately for Reflex display, even while State remains `Written` until `GetInputChannelName()` confirms REAPER has refreshed. Audio refresh is explicit via `Restart Audio` (`Audio_Quit()` / `Audio_Init()`), guarded while transport is running.

MIDI pages read/manage `[mididevcache]` and `[mididevignore]` in `reaper-midihw.ini` for aliases, cached names, ignored-device rows, favorites, and presence display; actual enable state comes from the active `reaper.ini` `[REAPER]` prefs (`midiins*`, `midiins_all*`, and `midiins_cs*` bitmasks for inputs; `midiouts*` bitmasks for outputs). Input aliases use `iaN`, output aliases use `oaN`, short/original names use `in/on` and `ix/ox`, and ignored devices are tracked by `iN` / `oN` values in `[mididevignore]`. The manager shows `Present`, `Missing`, `Ignored`, `Disabled`, and `Built-in` statuses; the cache scan explicitly checks the relevant direction prefixes instead of relying on a broad prefix regex, and skips stale flag-only cache rows with no live device and no alias/original/name identity so they do not become fabricated `MIDI Input N` rows. For live API reads, `GetMIDIInputName()` / `GetMIDIOutputName()` boolean return is the presence check. REAPER-reported device names `not present`, `<not present>`, `<not found>`, and `not found` are treated as unavailable/offline even when embedded in a longer string. Right-clicking anywhere in the MIDI tables opens an options popup with `Hide unavailable, ignored, and disabled devices`, persisted in ExtState as `io_manager_midi_hide_unavailable`; when enabled, it keeps only `Present` and `Built-in` rows, hiding `Missing`, `Ignored`, `Disabled`, and any future unusable status before text filtering. MIDI table string sorting uses natural numeric comparison so names like `MIDI Input 9` sort before `MIDI Input 10`.

**Important MIDI prefs limitation:** `IOMGR.midi` displays but does **not** edit REAPER's native Preferences → MIDI Devices enable/input-control/all state. REAPER's public ReaScript API exposes MIDI device names/presence but not the prefs checkbox state directly, so Reflex reads the active `reaper.ini` preference masks for filtering only. In REAPER 7, `itN`/`otN` values in `[mididevcache]` are nonzero device bookkeeping/identity values and must not be treated as enable/control/all bitfields; `midiinflagN` is also not the primary enable gate. The removed v20.637–v20.648 `In/Out`, `All`, and `Ctl` columns were therefore misleading and are gone as of v20.649. After alias writes, `midi_reinit()` is called only when transport is stopped, otherwise a notice asks the user to stop transport to refresh devices. `HDR.input` MIDI source lists and MIDI favorites are filtered by REAPER-present inputs that appear in any enabled input/control mask (`midiins*`, `midiins_all*`, or `midiins_cs*`).

Favorite persistence remains semantic. `Audio In` and `MIDI In` share `record_input_favorites_v1` with the `HDR.input` popup (`mono:N`, `stereo:N`, `multi:N`, `midi:DEVICE:CHANNEL`). The popup keeps those semantic keys internally but displays favorites without the `Mono:`, `Stereo:`, or `MIDI:` prefixes; MIDI favorites use `C.midi_activity` yellow text. Output pages use separate ordered ExtState lists, `record_output_favorites_v1` and `record_midi_output_favorites_v1`, with the same semantic key format so future output-selection surfaces can consume them without label migration.

### Key Architectural Decisions

- **Drop target registry (`fx_drop_targets`) widened gate**: registers when `fx_drag.active OR FxClipHasContent()`. Both drag and clipboard consume from the same registry.
- **Registry clearing ownership**: moved to `FxClipResolveHover` end (was inside `FxDragResolveDrop`, which wiped before clipboard could read).
- **Deferred paste pattern**: Cmd+V sets `nav_fx_clip_pending_paste`, consumed in `FxClipResolveHover` after registry populated.
- **`body_rect` registers as card OUTER bounds** on both surfaces (for dashed outline geometry consistency). Inspector expansion at registration via `opt_card_boxes and S(UI.card_pad/pad_top/pad_bot)`; sends already registers outer bounds.
- **Cross-card ID scoping**: secondary card (pinned mode) wrapped in `PushID("nav_secondary_card")` to prevent FX-row ID collision with primary.
- **No system-level keyboard hooks**. Considered and rejected: invasive, brittle, requires JS_ReaScript extension, modifies REAPER's keymap. Custom REAPER action bound to ⌘V was also rejected (would break Cmd+V everywhere).

---

## Pending Items

### Immediate QA / Next Thread

- **Runtime-test v20.656 I/O Manager in REAPER.** Static Lua parse via `luac`/`lua` is not available in the shell, so the manager still needs a full REAPER runtime pass. Verify: NAV global `I/O Manager` row; Reflex Settings `I/O Manager` row; `HDR.input` right-click context for mono/stereo/multichannel/MIDI/None/All MIDI; launch-page selection and auto-edit focus/select-all; inline audio and MIDI alias commit/cancel with visible fallback names selected on entry; blank audio alias commits remove the alias and fall back to the HW/default name; `HW Name` no longer echoes the alias; audio input/output alias refresh notices; `Audio Out` and `MIDI Out` page population; table column resize/sort without sort-comparator errors; MIDI pages show only favorite, `Device / Alias`, `Status`, and `ID` columns; no fake MIDI `In/Out`, `All`, or `Ctl` columns remain; statuses read `Present`, `Missing`, `Ignored`, `Disabled`, or `Built-in`; natural MIDI name sorting (`MIDI Input 9` before `MIDI Input 10`); subtle alternating row backgrounds; MIDI right-click filter `Hide unavailable, ignored, and disabled devices` on both MIDI pages keeps only `Present` and `Built-in` rows; enabled-but-absent MIDI devices showing `Missing` rather than green `Enabled`; input devices absent from all `midiins*`, `midiins_all*`, and `midiins_cs*` masks showing `Disabled` and disappearing when the hide option is checked; output devices whose bit is not set in `midiouts` / `_h` / `_x` / `_x_h` showing `Disabled` and disappearing when the hide option is checked; missing MIDI names `not present`, `<not present>`, and `<not found>` showing unavailable/offline; stale flag-only MIDI cache rows not appearing as fabricated `MIDI Input N` devices; taller first-open size and max resize; flat alias/star row styling; input favorites still populate the `HDR.input` popup without `Mono:`/`Stereo:`/`MIDI:` prefixes and with MIDI favorites in yellow; output favorites persist separately; unavailable or disabled MIDI inputs stay hidden from the actual `HDR.input` selector; `Source channel` rows keep the menu open and mark the current channel with blue text; selected `HDR.input` label reads at 75% opacity.
- **Navigator release roadmap: Windows + keyboard passthrough.** Standalone `Navigator.lua` should get a release-focused pass before public use. Start with a diagnostic build, not a behavioral rewrite: add a temporary debug readout/log for `NAV.pill` / `NAV.dot` clicks showing OS (`GetOS()`), raw `ImGui_GetKeyMods()`, decoded modifiers, window focus, active item, popup state, and whether `SetNextFrameWantCaptureKeyboard` is being forced true/false. Test macOS + Windows, floating + docked, with REAPER arrange focused, Navigator focused, another ReaScript focused, a plugin window focused, and the `NAV` global/TLT popups open.

  Roadmap order:
  1. **Modifier map.** Make primary-modifier semantics platform-aware: macOS primary = Cmd, Windows primary = Ctrl. Update `NAV.arr`, `NAV.pill`, `NAV.dot`, songs rows, help/manual, and tooltips so labels say Cmd/Opt on macOS and Ctrl/Alt on Windows. Resolve the existing Windows conflict where Ctrl is currently deep expand/collapse by moving that low-frequency action to Ctrl+Alt on Windows while preserving current macOS gestures.
  2. **Capture policy experiment.** Keep `ReflexConfigureKeyboardPassthrough()` disabling ImGui nav capture. Test three standalone Navigator policies for `ReflexApplyKeyboardPassthrough()`: current `active` only, forced `false` while no text input/popup is active, and context-sensitive capture only for song search / popup keyboard nav. Verify whether REAPER global shortcuts actually pass through when Navigator is focused. Do not assume from code comments; test runtime behavior.
  3. **No continuous hard focus handoff.** Do not restore v20.588-style `JS_Window_SetFocus(GetMainHwnd())` while idle. It is global OS/REAPER focus, not Navigator-local passthrough, and it can steal focus from floating windows, plugins, and other ReaScripts.
  4. **Optional user-controlled focus return.** If capture policy cannot provide arbitrary REAPER shortcut passthrough, consider a preference such as "Return keyboard focus to REAPER after Navigator click". It must be one-shot after completed `NAV` mouse actions, gated off while popups/text inputs/active items exist, and default only after runtime testing proves it does not harm the multi-script workflow.
  5. **Fallback mirrors stay narrow.** Manual mirroring can cover essential keys only (for example Space, Up/Down, Undo/Redo) and cannot replace arbitrary user REAPER shortcuts. Avoid fake all-key forwarding, system-level hooks, or custom REAPER actions bound to common chords.

  QA matrix: Windows display scale 100/125/150%; macOS Retina/non-Retina if available; `NAV.pill` text clipping and `NAV.dot` wrapping; A/S/R icon and `Tycho-Logo-dots.png` sizing; path separator handling for `core/?.lua` and icon load; ReaImGui 0.10+ function availability; JS_ReaScript present/absent fallback; right-click focus/popup behavior; and post-action keyboard behavior after `NAV.pill`, `NAV.dot`, `NAV.arr`, A/S/R, song search, and global/TLT context menu actions.
- **MIDI input submenu scope.** v20.623 exposes `MIDI >` sources once each (`Virtual MIDI Keyboard` is not expanded into channel rows), plus `Source channel >` for the `I_RECINPUT` source-channel bits. The TCP screenshot also shows `Map input to channel >`; this has not been implemented yet because the current pass only used the `I_RECINPUT` field. If requested, first confirm the ReaScript-accessible state/API for TCP input-channel mapping rather than guessing.

### Architectural

*(none open — `insp_fx` per-source-track ownership resolved in v20.432–v20.436; see "Per-Track FX Cache" section.)*

### Features

- **NAV help / cheat sheet** — add a small circled `?` icon in the NAV global right-click menu that opens a concise explanation of the three visible NAV classes: natural TLTs, auto-promoted children from `Hide in Navigator - show children`, and manually selected custom shortcuts from `Show selected tracks in Navigator`.
- **Configurable internal key bindings** — externalize hardcoded modifier-bit helpers into user-editable mappings.
- **Button import from REAPER toolbars** (parse `reaper-menu.ini`).

### Completed since previous PK update (v20.438 → v20.672)

- ✅ **Navigator/Inspector split and Reflex NAV visual parity (v20.672).** Added a draggable 21px NAV/Inspector divider with a hover-only rounded handle, so users can choose where the NAV TLT scroll area ends. Reflex now gates side-dock chrome gap compensation to ReaperTips themes only, matching standalone Track Navigator behavior. Reflex arrow drawing was brought back to consistent disclosure glyphs at the original Reflex control scale, while embedded NAV arrows use the same shared renderer glyph path as standalone Track Navigator.

- ✅ **Embedded NAV renderer catch-up (v20.671; Navigator v20.671).** Ported the standalone Track Navigator renderer fixes into Reflex's shared `core/Reflex_NavViewCore.lua` while preserving Reflex's Windows-safe vector disclosure arrows and embedded menu behavior. Reflex NAV now uses the sticky TLT search header above the scroll child, smart row clipping for partially visible TLT pills, newer endcap modifier handling, and history pushes for tree-collapse/disclosure mutations.
- ✅ **Embedded theme + right-dock gap cleanup (v20.670; Navigator v20.670).** Folded the tested `Reflex_Theme.lua` values into `Reflex.lua`, standalone `Navigator.lua`, and `Reflex_IOManager.lua`; removed `Reflex_Theme_Default.lua` from the ReaPack package so future user-facing UI customization can move into Options instead of external files. Full Reflex now keeps normal right `WindowPadding` when docked right under non-Reapertips REAPER themes, while retaining the historical chrome compensation for left dock and Reapertips.

- ✅ **NAV range selection parity + history reconciliation (v20.669; Navigator v20.669).** Ported Track Navigator's range-selection fixes into Reflex's shared Navigator cores: body Shift-range keeps a GUID-backed anchor across repeated Shift-clicks and shows only the ranged rows plus required parents, while colored-endcap Shift ranges select only TCP-visible tracks between anchor and target. View history now also captures/restores Navigator-local maps and Armed View state so Back/Forward does not lose pins/tree/search/custom-set context or the command-driven Armed View exit target.

- ✅ **Navigator helper action fallback (v20.669; Navigator v20.669).** Reflex Navigator companion actions now pass `launch_if_missing=true` to `Reflex_NavigatorActionBridge.lua`, so direct action/mapping invocations can wake standalone `Navigator.lua` when no current Reflex/Navigator instance has registered the shared command key. Existing running Reflex instances still receive commands through the same `reflex_navigator_external_command` channel.

- ✅ **Navigator Armed View command port (v20.668; Navigator v20.668).** Ported Track Navigator's record-armed view backend into Reflex's shared `Reflex_ViewModes.lua`, including per-project state restore, mutual exclusion with A/S/R views, and `TrackNavigatorScrollToRecordArmed()` selecting/scrolling the first armed track. Added Reflex Navigator companion actions for Armed View toggle and record-armed scroll using a Reflex-specific ExtState command bridge so external bindings do not collide with standalone Track Navigator.

- ✅ **Remote default off + Windows arrow cleanup + embedded NAV phase update (v20.667; Navigator v20.667).** New installs now default `RMT` hidden (`remote_visible=false`) while preserving any existing saved preference. Reflex's right/down/up arrow controls now draw vector icons instead of `▶`/`▼`/`▲` text glyphs, avoiding Windows emoji fallback for right-pointing arrows. Embedded/standalone Reflex Navigator now matches Track Navigator 1.2.8's mirror phase: default unmirrored TLT rows keep the colored circles and indentation on the left; enabling `Mirror TLT buttons` moves them to the opposite side.

- ✅ **Remote child boundary sentinel for Windows ReaImGui (v20.666).** `RMT` now submits a tiny dummy item after its manual grid cursor advance so Windows ReaImGui records the extended child bounds before `ImGui_EndChild()`. This fixes the Windows-only `SetCursorPos()/SetCursorScreenPos() to extend window/parent boundaries` error seen when inline Remote is visible.

- ✅ **Embedded NAV menu header restore (v20.665).** Restored the `NAV.menu` title/logo/version/close header in embedded Reflex after the Track Navigator 1.2.7 shared-core port left it gated behind standalone-only menu context. The global options window now also applies a viewport max-height constraint before `Begin`, so long Navigator options stacks can scroll instead of clipping off-screen.

- ✅ **Keyboard passthrough helper restore (v20.664).** Restored `ReflexConfigureKeyboardPassthrough()` and `ReflexApplyKeyboardPassthrough()` in `core/Reflex_StyleCore.lua` after the Track Navigator 1.2.7 core refresh removed the definitions while `Reflex.lua` and standalone `Navigator.lua` still called the shared helper.

- ✅ **Footer boundary sentinel for ReaImGui 0.10 (v20.663).** Added a no-inline-Remote main-window `Dummy()` after the footer's bottom cursor reservation so ReaImGui records the extended boundary before `ImGui_End()` and no longer reports the `SetCursorPos()` boundary warning.

- ✅ **Track Navigator 1.2.7 NAV integration (v20.662; Navigator v20.662).** Ported the shared NAV cores forward into Reflex, including `Reflex_NavTreeCore.lua`, tree disclosure state, TLT search, custom-set rendering/actions, selected-tracks view (`NAV.S`), A/S/R icon assets, ReaImGui 0.10 font-size/key-mod adapters, and standalone Navigator dock/quit/search shell hooks. Reflex keeps its inspector, Flow, Sends, Remote, I/O Manager, and configurable `routing_view_depth` behavior while embedded and standalone Navigator both require ReaImGui 0.10+.

- ✅ **Native-only NAV.R routing relationship lookup (v20.661; Navigator v20.618).** Removed the SWS fallback from `core/Reflex_ViewModes.lua` for routing-view send/receive relationship resolution. `RoutingViewGetSendDests()` now uses native `"P_DESTTRACK"` only, and `RoutingViewGetRecvSources()` uses native `"P_SRCTRACK"` only. This makes standalone Navigator's no-SWS dependency claim testable even on systems that have SWS installed. Broader Reflex SWS removal remains a later audit for routing panels/send topology and send-envelope matching.

- ✅ **Native routing relationship lookup for standalone Navigator (v20.660; Navigator v20.617; superseded by v20.661).** `core/Reflex_ViewModes.lua` first moved `NAV.R` send/receive relationship resolution to REAPER's native `GetTrackSendInfo_Value(track, category, send_idx, "P_DESTTRACK"/"P_SRCTRACK")`, with SWS as a temporary fallback. v20.661 removed that fallback so SWS cannot mask native lookup failures during standalone Navigator QA.

- ✅ **Standalone Navigator keyboard diagnostic build (v20.659; Navigator v20.616).** Added a temporary standalone `Navigator.lua` diagnostic readout plus file logging (`navigator_keyboard_diag.log`) for `NAV.arr`, `NAV.pill`, `NAV.dot`, A/R, songs rows, and global/TLT popup opens. Logs include `GetOS()`, raw `ImGui_GetKeyMods()`, decoded Cmd/Ctrl/Shift/Alt, platform-primary expectation, proposed deep-expand chord, ImGui window focus/hover, JS focused window title/class when JS_ReaScript is available, active-item state, popup state, and the current `SetNextFrameWantCaptureKeyboard` active-only policy/result. `ReflexApplyKeyboardPassthrough()` behavior is unchanged; it now optionally reports capture facts to the diagnostic callback. No v20.588-style hard focus handoff was restored.

- ✅ **I/O Manager module split + safer routing/config writes (v20.658).** Moved the shared `HDR.input` / I/O backend into `core/Reflex_IOCore.lua` and the floating `IOMGR` panel UI into `core/Reflex_IOManagerCore.lua`. Added `Reflex_IOManager.lua` as a standalone REAPER action/window that uses the same shared cores. `Reflex.lua` now keeps only the inspector row drawing wrapper (`InspDrawRecordInputRow`) and installs the modules in order: I/O core before `HDR.input` consumers, I/O Manager after `nav_screen_rect` exists. INI mutations for audio/MIDI aliases now write to a same-directory temp file, keep a `.reflex.bak` copy of the previous contents, and rename into place instead of overwriting `reaper.ini` / `reaper-midihw.ini` directly. Fixed routing clipboard HW-send paste to write category `1` after `CreateTrackSend(track, nil)`, avoiding accidental writes into normal send category `0`.

- ✅ **Expanded FX latency readout (v20.657).** `FX.row2` now shows REAPER-style plugin/chain reported latency as `plugin/chain spls` (for example `128/256 spls`) to the right of the wet/dry control with a 24-retina-px (`S(15)`) gap. Reads use `TrackFX_GetNamedConfigParm(track, fx_idx, "pdc")` and `"chain_pdc_reporting"` only inside expanded visible inspector/flow/secondary `FX.row` render paths. `SEND.col` FX rows are unchanged.

- ✅ **I/O Manager MIDI input mask correction (v20.656).** Fixed the broken v20.655 `midiinflagN` gate. Input enabled state now uses the same mask family REAPER writes for MIDI Devices: `midiins*`, `midiins_all*`, and `midiins_cs*`. This restores enabled online inputs in `IOMGR.midi` and `HDR.input` while still allowing disabled inputs to be filtered by the `Hide unavailable, ignored, and disabled devices` option.

- ✅ **I/O Manager MIDI prefs-backed enabled filtering attempt (v20.655).** Superseded by v20.656. This pass correctly stopped treating `[mididevcache]` `itN` / `otN` as enable/control/all bitfields, but incorrectly used `midiinflagN` as the MIDI input enabled gate, which hid valid enabled inputs.

- ✅ **I/O Manager MIDI disabled-device hiding (v20.654).** Renamed the MIDI table options row to `Hide unavailable, ignored, and disabled devices` and kept the hide option as a strict whitelist of `Present` / `Built-in` rows. Superseded by v20.655 for actual disabled-state detection.

- ✅ **HDR.input selected-row color marker (v20.653).** Selected `HDR.input` popup rows no longer draw a checkmark. Custom rows (`Mono`, `Stereo`, `MIDI`, favorites, and `Source channel`) mark the current value by drawing the row label in `C.cmp_b`; native top-level rows (`All MIDI Inputs`, `None`) suppress ImGui's selected checkmark and push the same blue text color while selected.

- ✅ **HDR.input audio meter normalization (v20.652).** Fixed audio activity dots in the `HDR.input` selector and popup rows by preserving raw `GetInputActivityLevel()` returns and normalizing audio values after reading them. Negative dBFS-style audio returns are converted to linear amplitude before smoothing/drawing; positive linear-style returns still pass through. MIDI behavior remains on the existing recent-event path with the `GetInputActivityLevel()` fallback unchanged.

- ✅ **NAV view-history launch dormancy (v20.651).** The initial inspector selection sync now marks its single launch snapshot as a non-navigable baseline, and the footer `NAV` history back button uses `ViewHistoryCanBack()` instead of a raw stack-position expression. Result: `NAV` Previous/Next view arrows launch dormant while the baseline remains available once the first real view change creates history.

- ✅ **I/O Manager MIDI unavailable filter tightening (v20.650).** Renamed the MIDI options row to `Hide unavailable devices` and changed `RecordIOMidiFilterRows()` from hiding only `Missing`/`Ignored` rows to whitelisting only `Present` and `Built-in` rows. This preserves the existing ExtState preference key while making the checked state match the desired "enabled/present devices only" view and leaving room for any future reliable disabled/unusable status to be hidden automatically.

- ✅ **I/O Manager MIDI prefs-column removal (v20.649).** Removed the fake `In/Out`, `All`, and `Ctl` columns from `IOMGR.midi` because REAPER 7's `itN`/`otN` values are not native enable/control/all checkbox bitfields, and the public ReaScript API only exposes MIDI name/presence, not the prefs checkbox state. MIDI rows now report `Present`, `Missing`, `Ignored`, or `Built-in`, and the MIDI options popup only exposes the reliable `Hide missing and ignored devices` filter. Alias editing, favorites, natural sorting, and missing-device hiding remain.

- ✅ **I/O Manager MIDI presence-vs-enable fix (v20.648).** Corrected the `IOMGR.midi` row state model so `GetMIDIInputName()` / `GetMIDIOutputName()`'s boolean return is treated as device presence, not as merely "has a display name." A disconnected device that still has saved `itN=1` / `otN=1` enabled flags now stays `Missing` instead of being upgraded to live `Enabled`, allowing `Hide missing and ignored devices` to filter it out. Unavailable-name matching also catches embedded `not present` and `not found` strings, with or without angle brackets.

- ✅ **I/O Manager missing MIDI device correction (v20.647).** MIDI unavailable-name detection now includes REAPER's angle-bracketed `<not present>` marker and embedded `<not present>` strings, so previously-enabled-but-disconnected devices fall to `Missing` instead of staying live/green `Enabled`. `RecordIOMidiRows()` also skips stale flag-only cache entries that have no live device and no alias/original/name identity, preventing fabricated `MIDI Input N` rows from polluting `IOMGR.midi`. MIDI string sorting now uses natural numeric comparison so numbered device names sort by number rather than pure lexicographic text.

- ✅ **I/O Manager MIDI filters + favorite label cleanup (v20.646).** Replaced the MIDI table options popup's old single filter with two native menu rows: `Hide disabled devices` and `Hide missing and ignored devices`. The unavailable filter treats REAPER's `not present`, `<not found>`, and `not found` MIDI device names as offline/missing so they no longer appear as green `Enabled` rows. `HDR.input` favorite rows now display the actual input names without `Mono:`, `Stereo:`, or `MIDI:` prefixes, and MIDI favorites draw in `C.midi_activity` yellow.

- ✅ **I/O Manager restart audio + immediate Reflex alias display (v20.645).** Added an audio-page-only `Restart Audio` button to the I/O Manager bottom bar. It calls `Audio_Quit()` / `Audio_Init()`, refreshes audio alias maps, clears `HDR.input` width cache, and refuses while transport is running. `RecordIOAudioName()` now prefers the saved active-device alias map for Reflex display so `HDR.input` and the input popup update immediately after an alias commit; `IOMGR.audio.State` remains the truth indicator (`Written` until REAPER's live channel-name APIs confirm, then `Live` after audio restart/device refresh).

- ✅ **I/O Manager audio alias section normalization (v20.644).** Fixed the CoreAudio alias-map target: `GetAudioDeviceInfo("IDENT_IN")` can return an unsanitized ident like `CoreAudio 2: Aurora(n)-TB`, while REAPER stores the active alias section as `[alias_in_CoreAudio_2:_Aurora(n)-TB]`. `RecordIOAudioAliasSection()` now uses `RecordIOAudioAliasIdent()` to replace whitespace with underscores before building `[alias_in_*]` / `[alias_out_*]`, so `IOMGR.audio` reads/writes the same device-specific section REAPER uses. Existing accidentally-created raw sections such as `[alias_in_CoreAudio 2: Aurora(n)-TB]` are not auto-deleted.

- ✅ **I/O Manager native audio alias sync correction (v20.643).** Audio alias writes now target the running REAPER install via `get_ini_file()` for the exact active `reaper.ini` path, preserving portable installs instead of constructing `GetResourcePath()/reaper.ini` by assumption. Writes remain per-active-device via `GetAudioDeviceInfo("IDENT_IN"/"IDENT_OUT")` sections (`[alias_in_*]` / `[alias_out_*]`) and now update `nameN`, `chN`, `map_size`, and `map_hwnch` together. `HDR.input` and its popup no longer trust Reflex's saved alias map as a substitute for REAPER's live name; they use `GetInputChannelName()` / `GetOutputChannelName()` only. `IOMGR.audio` keeps the saved alias in the editable alias column and adds a State column: `Live` when REAPER confirms the alias, `Written` when the alias is in `reaper.ini` but REAPER has not refreshed, `Pending` for a cleared alias that REAPER still reports, and `Native` when no alias is saved. Native sync remains best-effort because REAPER exposes no documented ReaScript setter for hardware audio aliases.

- ✅ **I/O Manager alias refresh/status placement (v20.642).** First pass moved the audio-device refresh warning out of the `HDR.input` under-row toast and into the I/O Manager header/status area. v20.643 superseded the display-side alias masking from this pass so `HDR.input` only reports REAPER-live names.

- ✅ **I/O Manager audio alias clearing/HW fallback (v20.641).** Blank audio alias commits now remove the `nameN` alias key instead of saving an empty string. `IOMGR.audio` tracks recently-cleared aliases for the current session so stale REAPER channel-name APIs do not keep showing the just-cleared alias as the fallback name. `HW Name` now rejects labels matching the active or just-cleared alias and falls back to neutral `Input N` / `Output N` when REAPER only exposes the aliased label. Audio page row counts also include alias-section `map_size`, `map_hwnch`, and `chN` entries so clearing the last high-index alias does not shrink ini-backed output pages.

- ✅ **I/O Manager edit/menu/filter polish (v20.640).** Inline alias edits now seed the text field with the visible row name when no alias exists, with auto-select active so typing replaces it while arrow-key navigation can edit the existing text. Added a Reflex Settings/gear `I/O Manager` launcher. Audio/MIDI tables now draw subtle alternating row backgrounds. MIDI tables gained the right-click options-popup path from anywhere in the section; the original single enabled-only filter was superseded by v20.646's split MIDI filters.

- ✅ **I/O Manager sort comparator fix (v20.639).** Fixed `IOMGR.row` table sorting crash (`invalid order function for sorting`) by replacing the Lua `spec.ascending and cmp < 0 or cmp > 0` comparator branch with an explicit if/else. Also fixed favorite sort-key preparation for stereo/audio and MIDI rows so a valid "not favorite" value of `0` is not collapsed to the invalid sentinel `-1`.

- ✅ **I/O Manager polish/fixes (v20.638).** Reworked `IOMGR.row` rendering onto ReaImGui tables so `Audio In`, `Audio Out`, `MIDI In`, and `MIDI Out` columns are resizable and sortable. Removed filled button backgrounds from alias/name cells and favorite stars while keeping click/edit affordances. Active page tabs now stay on the full blue compare color without hover/active darkening. The manager opens at roughly 75% viewport height and can resize taller to the work-area cap. Output page discovery was hardened: audio outputs now fall back through alias-section counts and device-info probes, MIDI cache rows are gathered by explicit in/out prefix matches, and MIDI output IDs 62/63 are no longer blocked by input-only sentinel rules.

- ✅ **Reflex-native I/O Manager (v20.637).** Implemented the `ONBOARD_IO_MANAGER.md` handoff: `HDR.input` alias actions now open a Reflex panel instead of native `GetUserInputs` prompts, and the NAV global popup has a top `I/O Manager` row using the blue compare highlight. The manager provides `Audio In`, `Audio Out`, `MIDI In`, and `MIDI Out` pages with inline alias editing, independent mono/stereo/device favorite stars, filtered virtualized rows, and per-action commit. Audio aliases write `reaper.ini` alias sections for active input/output identifiers without audio-device restart. MIDI aliases and enable-state flags write `reaper-midihw.ini`, show disabled/missing/ignored devices, and call `midi_reinit()` only while stopped. `HDR.input` also now draws its selected label at 75% opacity and `Source channel` rows get no-auto-close selection where ReaImGui supports it. Current selected-row marking is color-only as of v20.653.

- ✅ **I/O Manager onboarding handoff (v20.636).** Added `ONBOARD_IO_MANAGER.md` as a self-contained next-thread prompt for replacing the v20.635 `HDR.input` native alias prompts with a full Reflex-native I/O Manager. The handoff covers entry points from `HDR.input` and the NAV global popup, audio/MIDI page structure, inline edit behavior, independent mono/stereo favorites, MIDI enable-state requirements, and housekeeping fixes for selector opacity, MIDI source-channel indicators, and disabled-device filtering.

- ✅ **HDR.input favorites + REAPER-backed aliases (v20.635).** `HDR.input` now supports global one-click favorites at the top of the record-input popup, stored as ordered semantic ExtState keys in `record_input_favorites_v1` (`mono:N`, `stereo:N`, `multi:N`, `midi:DEVICE:CHANNEL`). Favorites reuse the existing `RecordInputSet(track, value)` audio-state undo path, draw with the same activity dots as normal leaf rows, and skip unavailable devices without deleting saved order. Right-clicking the selector or any leaf/favorite row opens a context menu for add/remove/reorder favorite plus alias actions where applicable. Audio alias edits write the active `[alias_in_<IDENT_IN>]` `nameN=` entries in `reaper.ini`; MIDI alias edits write/remove `iaN` entries in `reaper-midihw.ini`, use `GetMIDIInputNameNoAlias` as fallback original-name context, and call `midi_reinit()` only while transport is stopped. Audio refresh is intentionally non-invasive: no `Audio_Quit()` / `Audio_Init()` calls.

- ✅ **Input meter contrast + narrow REAPER key mirror (v20.634).** Brightened `C.input_meter_bg` to `#4a5060` so inactive input meters remain visible against `HDR.input` / popup hover backgrounds. Added `ReflexMirrorReaperShortcuts()` as a narrow manual mirror while Reflex is focused and idle: Up/Down call REAPER previous/next track actions, Cmd+Z calls REAPER Undo, and Cmd+Shift+Z calls REAPER Redo. No Cmd+Y mapping. The mirror is gated off when a popup, active item, settings panel, FX browser, remote prompt/icon picker, or inline text edit is active.

- ✅ **All MIDI Inputs meter nudge (v20.633).** Nudged the native top-level `All MIDI Inputs` overlay meter 11px Retina right and 6px Retina down relative to the v20.632 position.

- ✅ **Native top-level input menu rows (v20.632).** `All MIDI Inputs` and `None` now render through native `ImGui_MenuItem` again so their text alignment exactly matches `Mono`, `Stereo`, and `MIDI`. The `All MIDI Inputs` MIDI activity dot is overlaid after the native row is laid out, preserving the right-side indicator without custom label positioning.

- ✅ **All MIDI Inputs native-left label alignment (v20.631).** Right-meter popup rows now draw the label at the selectable rect's left edge instead of applying the custom left row padding. This keeps `All MIDI Inputs` aligned with native top-level menu labels while preserving the right-side MIDI activity dot reservation.

- ✅ **All MIDI Inputs right-meter reservation (v20.630).** Fixed the top-level `All MIDI Inputs` popup row so it keeps a right-side meter reservation while leaving the label at normal top-level left padding. This restores the right-aligned MIDI activity circle without adding the left-side input-meter indent.

- ✅ **All MIDI Inputs row alignment (v20.629).** The top-level `All MIDI Inputs` popup row keeps its MIDI activity dot right-aligned, but no longer reserves the left-side meter prefix space, so its label aligns with the other top-level input menu rows.

- ✅ **Current-input meter in HDR.input (v20.628).** Moved the live current-input activity indicator out of the `VOL` meter bar and into the `HDR.input` selector box. The new selector meter is 20px Retina, centered in the left endcap square, works for audio and MIDI using the same activity logic as the popup meters, uses `C.input_meter_bg` (`#3a3e49`) when inactive, and leaves 16px Retina between the meter edge and faded selector text. Selector text is drawn at 50% opacity and the chevron is lightly faded. The top-level `All MIDI Inputs` popup row now right-aligns its MIDI activity dot; other popup input rows keep their left-side dot.

- ✅ **VOL MIDI activity dot size pass (v20.627).** Increased only the `VOL` meter MIDI activity dot to a 21px Retina target (`S(13.125)`); `HDR.input` popup activity dots remain at their 16px Retina target.

- ✅ **VOL MIDI activity detection + input-dot cleanup (v20.626).** MIDI activity now polls `MIDI_GetRecentInputEvent(0)` and matches recent device activity against the track's selected MIDI input, with the older `GetInputActivityLevel` path retained as fallback. `All MIDI Inputs` lights from any recent MIDI device. Removed the custom right-side selected-row marker dot from `HDR.input` leaf rows. Input-list activity dots now use a fixed manual optical nudge of 4px Retina up and left rather than right-align math.

- ✅ **HDR.input meter-dot alignment refinement (v20.625).** Input-popup activity dots now target 16px Retina diameter, right-align within their reserved prefix cell before the input name, and center vertically on the row text baseline. Custom input rows now use ImGui line height for row and text placement so labels sit centered in the selectable box. MIDI idle dots now use the same rest/background color as audio idle dots; only active MIDI hits switch to `C.midi_activity` yellow.

- ✅ **HDR.input activity dots + VOL MIDI indicator (v20.624).** `HDR.input` leaf rows now reserve a small left-side activity dot before each actual input name: Mono and Stereo rows read `GetInputActivityLevel` from the relevant hardware input channels and render with the normal Reflex audio meter color/alpha behavior, while MIDI source rows and `All MIDI Inputs` flicker fixed `C.midi_activity` yellow (`#ffcc00`) without audio color scaling. `VOL` now overlays the same yellow MIDI activity dot at the left endcap center of the main meter bar when the inspected track is record-armed with a MIDI input selected. Added `midi_activity` to the theme color tokens.

- ✅ **HDR.input cascading menu + record-arm modifiers (v20.623).** Replaced the flat `HDR.input` popup with native cascading menus: top level is `Mono >`, `Stereo >`, `MIDI >`, `All MIDI Inputs`, and `None`. Mono/stereo submenus list audio inputs; MIDI submenu lists each MIDI source once (`Virtual MIDI Keyboard` is a single row, not 17 channel rows) plus a `Source channel >` submenu for channel 1–16/all. `All MIDI Inputs` is a top-level direct item, not inside MIDI. The popup now uses native menu sizing instead of the old fixed-height child list, so it only scrolls when the screen edge actually requires it. `HDR.input` step buttons now advance within the current family only: mono through mono inputs, stereo through stereo pairs, MIDI through MIDI sources while preserving source channel. `HDR.record` modifiers: Cmd-click disarms all tracks, Opt-click arms only the clicked track, and Shift-click arms the clicked track with input set to All MIDI Inputs.

- ✅ **HDR.input sizing/chevron pass (v20.622).** Tuned `HDR.input` to the requested Retina targets: selector/step-button height is 48px Retina (`S(30)`), `HDR.row2` → `HDR.input` gap is 20px Retina (`S(12.5)`), and `VOL` → `CTRL` spacing is doubled by setting `gap_vol_ctrl=10`. Selector width now calculates against the available input list and keeps a per-track stable cache keyed by row geometry, so stepping through inputs no longer shrinks/grows every time the current label changes. The selector's right-side marker is a drawn chevron instead of the filled expand-arrow triangle, while the adjacent input step buttons now use the same rest/hover/active colors as the FX expand-arrow button, including a rest background.

- ✅ **HDR record-input selector row (v20.621).** Armed normal track cards now show `HDR.input` below `HDR.row2`: a `C.fx_ctrl_bg` rounded selector box using FX-row text sizing, a right-aligned down chevron, and two transparent square step buttons (`▼` next / `▲` previous) styled like the track-envelope expand arrow. The selector base width matches `VOL` meter/fader width, expands only when a long input name needs available row space, and ellipsizes at the limit. Clicking the selector opens a no-search, add-menu-styled full input list covering no-input, audio mono/stereo/multichannel, all-MIDI/VKB, and physical MIDI device channel entries; step buttons wrap through the same list. Setting `I_RECINPUT` is an audio-state undo operation.

- ✅ **HDR monitor hit-box/gap and card context gating (v20.620).** `HDR.mon` now uses a square hit area matching the row button height with the PNG centered inside, making right-click targeting easier. When `HDR.mon` is visible, the gap from its right edge to `HDR.M` is doubled (`2 * UI.pad_sm`), while the `HDR.record` → `HDR.mon` gap remains standard. The broad CARD right-click catch-all moved from inside `InspDrawHeader` to the end of `InspDrawTrackBlock`, after card controls/rows have registered, and now requires `not IsAnyItemHovered()`. This prevents the track-card context menu from firing over `HDR.record`, `HDR.M`, `HDR.S`, pan/ENV/FX/row controls, etc., while preserving blank-card and expanded-routing-area right-click. `CTRL.route` body right-click opens the track-card context menu; `CTRL.add_send` keeps its send-mode popup.

- ✅ **HDR record-monitor icon (v20.619).** Added `HDR.mon` to normal track cards and minimal flow cards. It appears only when `HDR.record` is armed, sits between `HDR.record` and `HDR.M` with the standard `UI.pad_sm` gap, uses `icons/rec.mon.button.png` as a Retina tintable PNG at quarter native draw dimensions, and tints rest/hover like the record-arm rest/hover colors while active monitor state is white. Left-click toggles `I_RECMON` off/on. Right-click opens a TCP-style monitor menu for normal, tape-auto, monitor track media while recording, and preserve-PDC delayed monitoring via REAPER's selected-track action.

- ✅ **HDR record-arm proportional ring geometry (v20.618).** Replaced the fixed `S(5.625)` inner radius with proportional geometry: `HDR.record` inner radius is now `outer_r * 0.5`, keeping the transparent ID at 50% of the visible OD across scale and rounding. This matches the Photoshop target ratio of 18px ID to 36px OD.

- ✅ **HDR record-arm inner-ring correction (v20.617).** Corrected `HDR.record` geometry after Photoshop measurement: the M/S/record outer circle is 38px Retina diameter, and the transparent record center is 18px Retina diameter, not radius. The inner transparent radius is now `9px ÷ 1.6 = S(5.625)`.

- ✅ **HDR record-arm button (v20.616).** Added a circular `HDR.record` button to normal track cards, placed left of `HDR.M` with the same `HDR.M`/`HDR.S` gap. It uses the unmuted mute-button rest/hover colors, draws as a stroked concentric ring with a transparent center, and turns `#ff4a4a` when `I_RECARM` is enabled. The control is wired into full `InspDrawHeader` cards and minimal flow track cards, but not `SEND.col`, `SEND.distant`, or `SEND.folder` return surfaces.

- ✅ **Targeted Add FX browser fix (v20.615).** Left-clicking `CTRL.add` / send-column add-FX `+` now always opens Reflex's internal targeted plugin browser for the clicked track instead of delegating to a saved REAPER/custom FX-browser action when that track is selected. This prevents stale `fx_browser_action.txt` actions from firing unrelated commands such as creating/arming nested return tracks. Right-click menus keep native and custom FX-browser actions explicit: `Open REAPER FX Browser` runs the native browser, and `Run Custom FX Browser Action` only appears when a custom action is defined.

- ✅ **Navigator mark version row-bottom alignment (v20.614).** Corrected the standalone global popup version text to align against the header row bottom rather than the mark's measured image bottom, with a small downward optical nudge so it reads like text sitting on the same line as the mark.

- ✅ **Navigator mark version baseline alignment (v20.613).** Bottom-aligned the standalone global popup version text to the rendered `Navigator.mark.png` row instead of vertically centering it, so `v...` sits on the same visual baseline as the new mark.

- ✅ **Navigator mark Retina scale correction (v20.612).** Corrected standalone popup `Navigator.mark.png` rendering after REAPER/Retina display testing showed the v20.611 half-size assumption still landed at 200% of intended visual size. The mark now renders at quarter native asset dimensions times Navigator UI scale.

- ✅ **Navigator mark in standalone global popup (v20.611).** Replaced the standalone NAV global popup's text `Navigator` title with `icons/Navigator.mark.png`. The PNG is treated as a 2x Photoshop mockup asset and rendered at half native pixel dimensions, scaled by Navigator UI size; the version text remains dim and right-aligned on the same row with an intentional gap.

- ✅ **NAV manual layout/dismissal pass (v20.610).** Reworked the `Help / Manual` popup into a clearer reference-card layout with section separators, consistent row rhythm, and less awkward indentation. Added explicit dismissal behavior: `Esc` inside the manual closes the manual, `Esc` in the NAV global popup closes the global popup, clicking the global popup while the manual is open closes the manual, and outside-click behavior is explicitly guarded so a click outside both popups closes the stack.

- ✅ **NAV Help / Manual popup (v20.609).** Added a bottom-row `Help / Manual` entry in the NAV global popup with a circled `?` icon aligned to the far right. The row opens a compact styled manual popup covering Navigator, custom visibility, track inspector, FX, routing/sends/flow, history/remote, and key terms such as TLT, manually shown tracks, hidden TLTs, promoted children, and ARCHIVE ignore behavior.

- ✅ **NAV customization wording/tooltips (v20.608).** Shortened global menu labels to `Show selected tracks` and `Reset custom visibility`. Added explanatory hover tooltips for showing selected tracks, hidden/promoted recovery rows, and both TLT right-click hide modes. Hidden/promoted recovery rows now hover red to communicate that clicking removes that custom visibility rule.

- ✅ **NAV global popup density pass (v20.607).** `UI size` / `Navigator size` now shares a single row with the right-aligned NAV scale controls, removing the wasted label-only row. General global options (`Ignore ARCHIVE`, `Mirror TLT buttons`) moved to the bottom below reset so the manual shown/hidden/promoted/reset customization section stays contiguous.

- ✅ **Separate full-hide TLT rule + compact reset buttons (v20.606).** Added a distinct per-project GUID-keyed `nav_hidden` layer for the normal `Hide in Navigator` behavior: hide this natural TLT and all descendants from NAV without promoting children. The existing `nav_excluded` layer remains the explicit `Hide in Navigator - show children` / promote-direct-children behavior. Priority is now: ARCHIVE auto-ignore, full hidden subtree, promoted-children rule, then manual custom shortcuts. Manual includes inside a hidden subtree are blocked/ignored until the subtree is restored. The NAV global menu now separates recovery into `Hidden in Navigator` and `Showing children instead`; reset clears `nav_included`, `nav_excluded`, and `nav_hidden`. Stale hidden/promoted GUIDs are pruned when the global menu evaluates customizations. The reset confirmation now uses side-by-side equal-width `Cancel` and `Reset` buttons instead of full-row actions.

- ✅ **NAV global menu polish pass (v20.605).** Tightened the standalone Navigator global popup width by only accounting for reset-confirmation copy while confirmation is visible, and by line-breaking the confirmation sentence before `hidden/promoted TLT rules.` Version text is now dim while `Navigator` remains white. Section labels `Manually shown tracks` and `Hidden in Navigator` are white. `Show selected tracks in Navigator` hovers green; manual-track hide rows and reset rows hover red. `Ignore ARCHIVE` now shows a compact helper tooltip explaining that any track named `ARCHIVE` and its children are excluded. General options (`Ignore ARCHIVE`, `Mirror TLT buttons`) now live in their own separated section above reset, and global popup separators use the same section-break rhythm.

- ✅ **Reset confirmation popup auto-close fix (v20.604).** Fixed `Reset Navigator customizations...` silently failing because the parent popup could auto-close before the confirmation action became reachable. `ReflexMenuItem()` now supports `no_auto_close` via `SelectableFlags_NoAutoClosePopups`, and reset confirmation is rendered inline inside the NAV global menu instead of as a child popup. `Hidden in Navigator` recovery rows also opt out of auto-close while more than one hidden TLT remains, preserving the intended click-through workflow.

- ✅ **NAV customization menu clarity + reset flow (v20.603).** The NAV global menu now keeps the `Hidden in Navigator` recovery section open while clicking through multiple hidden TLTs, closing only after the last hidden item is restored. Renamed the custom shortcut section from `Navigator items` to `Manually shown tracks`; when no TCP tracks are selected, the add row stays visible as disabled `No tracks selected` so the feature remains discoverable. Added `Reset Navigator customizations...` with red hover text and a confirmation popup. Confirmed reset clears `nav_included` manually shown tracks and `nav_excluded` hidden/promoted TLT rules, while leaving general prefs such as `Ignore ARCHIVE`, Navigator size, mirror mode, pins, and hidden live mode alone.

- ✅ **TLT terminology cleanup + NAV help design note (v20.602).** Reframed Navigator terminology from the old folder-shaped language to TLT/top-level track across current PK prose, comments, tooltips, and user-facing menu labels. Natural NAV roots are TLTs whether or not they are folders; this prevents the mental-model break where a hidden top-level leaf later gains children and starts promoting them. Internal names such as `top_folders`, `ShowAllTLFs`, and `ViewHistoryPushTlf` remain unchanged for compatibility. Added a pending NAV help/cheat-sheet item for a circled `?` in the global menu explaining natural TLTs, auto-promoted children, and manually selected custom shortcuts.

- ✅ **Natural NAV root wording clarification (v20.601).** Natural top-level `NAV.pill` / `NAV.dot` context menus now always label the exclusion action `Hide in Navigator - show children`, even when the track is currently a leaf. This matches the actual `nav_excluded` semantics: suppress the top-level NAV root and promote any direct children now or later. Custom included shortcuts keep the shorter `Hide in Navigator` wording because that action only removes a GUID from `nav_included`; it does not create child-promotion behavior.

- ✅ **Custom NAV order/context + public hide-in-NAV refinement (v20.600; wording refined v20.601).** Fixed v20.599 custom-included tracks grouping at the bottom of `NAV.*`: `BuildRenderList()` now overlays `nav_included` entries inside the main project-order scan, so custom leaf/folder shortcuts appear in track order near their parent context instead of in a post-pass. Restored the useful public `Hide in Navigator - show children` behavior: hiding a top-level NAV root removes its own `NAV.pill` / `NAV.dot` and promotes direct children; if a hidden top-level leaf later becomes a folder, its direct children will be promoted under the same rule. Hidden tracks are recovered from the NAV global menu's `Hidden in Navigator` section. Custom included items now use the wording `Hide in Navigator` instead of `Remove from Navigator`; for custom shortcuts this removes the GUID from `nav_included`, while natural NAV items use `nav_excluded`. Exact-track exclusion wins over custom inclusion, and `Ignore ARCHIVE` still wins over both.

- ✅ **Custom NAV items + public ARCHIVE auto-ignore + hidden live mode gate (v20.599; refined v20.600).** Added `core/Reflex_NavInclusionCore.lua` for per-project GUID-keyed `nav_included` persistence and the shared `NavIncludeSelectedTracks()` action. The NAV global menu now exposes `Ignore ARCHIVE` (default on) and `Show selected tracks in Navigator`, plus a compact `Navigator items` management section using the explicit popup stack primitives. Custom leaf clicks reveal only the parent chain plus the target; custom folder clicks reveal the parent chain plus that folder/subtree. The Tycho/Realist `MONITORS`, `I/O`, and `SONGS` behavior is gated behind hidden persistent `tycho_live_mode` so normal projects treat those names as ordinary folders. With `tycho_live_mode` enabled, the existing subgroup/current-song behavior remains available. `Ignore ARCHIVE` uses the separate public pref `nav_ignore_archive` and applies to tracks named `ARCHIVE` and their descendants. v20.600 moved custom items from post-pass append into the main project-order scan and renamed the custom removal row to `Hide in Navigator`.

- ✅ **NAV global menu context + focus-steal removal (v20.598).** Shared NAV renderer now accepts `menu_context`. In embedded Reflex, NAV global right-click removes the top `Navigator v...` title and first rule, and renames `UI size` to `Navigator size`; standalone `Navigator.lua` keeps its title/version and `UI size` label. Removed the aggressive keyboard passthrough focus handoff: `ReflexApplyKeyboardPassthrough()` no longer calls `JS_Window_SetFocus(GetMainHwnd())`, and standalone Navigator no longer passes `{ hard_focus_reaper = true }`. This stops Navigator from stealing focus away from REAPER floating windows and other ReaScripts. The remaining helper only uses `SetNextFrameWantCaptureKeyboard(active)` so ImGui requests keyboard capture only while an item is actively being edited/dragged.

- ✅ **Navigator global popup explicit stack rhythm (v20.597).** Added `ReflexPopupStackGap()` and `ReflexPopupRule()` to separate layout rhythm from element rendering. The Navigator global popup now lays out `Navigator v...`, separators, `UI size`, scale controls, and `Mirror TLT buttons` as `element → shared stack gap → rule/element → shared stack gap`, instead of relying on each helper's private vertical gap. `NavDrawScaleControls()` no longer adds hidden top/bottom row padding in this menu. This makes Navigator the test case for the popup style-guide rule: helpers may draw an element, but the popup stack owns inter-element spacing.

- ✅ **Static popup labels no longer add outer-edge vertical padding (v20.596).** `ReflexPopupLabel()` now defaults to `pad_y = 0`, matching its existing `pad_x = 0` behavior. This keeps static labels such as `Navigator v...` and `UI size` visually aligned to the popup content edge on both axes, instead of making the top gap equal to `WindowPadding.y + label pad_y`. Clickable rows still keep their own internal `popupGap()` Y padding because that belongs to the hover rectangle.

- ✅ **Popup outer padding matched vertically without horizontal clipping (v20.595).** `PushPopupStyle()` now uses `WindowPadding(S(10), S(10))`: the existing left/right popup gutter is preserved, and only the top/bottom outer gutter is increased to match it. This avoids the v20.593 mistake of shrinking horizontal padding to the smaller row-gap token.

- ✅ **Reverted tight popup outer padding (v20.594).** Backed out the v20.593 `WindowPadding(popupGap(), popupGap())` experiment after screenshot/user testing showed it removed too much horizontal gutter and caused content clipping in Navigator popup menus. `PushPopupStyle()` is restored to `WindowPadding(S(10), popupGap())` while the broader popup layout issue is paused for redesign instead of further incremental nudging.

- ✅ **Static NAV popup alignment split (v20.592).** `ReflexPopupLabel` now defaults to `pad_x = 0`, so non-button text such as `Navigator v...`, `UI size`, and `Ignored Folders` left-aligns with the separator/content edge instead of inheriting clickable-row hover padding. `NavDrawScaleControls()` also starts at the same content edge. `ReflexMenuItem` keeps its own internal `S(8)` text inset because that belongs to the hover rectangle, not to static popup structure.

- ✅ **Measured NAV popup row rhythm (v20.591).** Tightened the Navigator global popup spacing after screenshot QA showed remaining non-uniform visual gaps. `ReflexMenuItem` and `ReflexPopupLabel` now use `ImGui_CalcTextSize` height and center text inside explicit padded rows, instead of mixing raw `GetTextLineHeight` with `y + pad`. Popup window Y padding, row Y padding, and separator spacing now share one `S(4)` rhythm unit, and `NavDrawScaleControls()` draws the +/-/percentage controls inside the same padded row model instead of inserting a separate external gap. This makes title rows, labels, control rows, separators, and rounded hover rows advance through one consistent visual rhythm.

- ✅ **Rounded NAV popup hover rows (v20.590).** `ReflexMenuItem` now pushes transparent ImGui `Header/HeaderHovered/HeaderActive` colors around its internal `Selectable`, then draws its own rounded filled rect for hover/active states before drawing the label. Default row radius is `S(4)`, intentionally smaller than the popup window rounding so hover rows read as nested soft elements. This removes the square-corner clash in Navigator global and TLT popup hover rows.

- ✅ **Explicit NAV popup layout grid (v20.589).** Fixed the inconsistent Navigator global/TLT popup spacing shown in screenshot QA. Root cause: the popup was still mixing raw `TextColored`, `Separator`, `Dummy`, `SameLine`, nav button primitives, and custom `Selectable` rows under inherited ImGui `ItemSpacing`, so every visual element had different hidden vertical/horizontal margins. Added `ReflexPushPopupLayout`/`ReflexPopPopupLayout` to zero inherited item spacing, changed `ReflexPopupLabel` to draw labels in exact-size rows, changed `ReflexPopupSeparator` to draw a custom 1px line with explicit symmetric gaps, and made `NAV` popup call sites compute one shared content width for their rows. `NavDrawScaleControls()` now forces the cursor to the bottom of its control row after the +/-/value compound, so subsequent separators start from a deterministic y-position. Applied to both Navigator global right-click menu and `NAV.pill`/`NAV.dot` TLT context menus.

- ✅ **Hard keyboard focus handoff for Navigator REAPER shortcuts (v20.588, superseded v20.598).** v20.588 tried to fix standalone Navigator shortcut swallowing by calling `JS_Window_SetFocus(GetMainHwnd())` whenever no ImGui item was active. That proved too aggressive: Navigator could steal focus away from REAPER floating windows and other ReaScripts. v20.598 removed the hard-focus path entirely. Current policy: `ReflexApplyKeyboardPassthrough()` only applies `SetNextFrameWantCaptureKeyboard(ctx, IsAnyItemActive(ctx))`; it does not move OS focus.

- ✅ **Promoted TLT un-ignore + shared keyboard passthrough policy (v20.587).** `NAV.pill` / `NAV.dot` items promoted because their parent TLT is ignored now show `Un-ignore parent` in the TLT right-click menu. The render-list already tags promoted children with `item.ghost_parent`; `core/Reflex_NavViewCore.lua` now threads that through both expanded and collapsed TLT menus and calls `NavSetTrackExcluded(parent.track, false)`. Added shared keyboard passthrough helpers in `core/Reflex_StyleCore.lua`: `ReflexConfigureKeyboardPassthrough()` disables ImGui nav keyboard capture via `ConfigVar_NavCaptureKeyboard`, and `ReflexApplyKeyboardPassthrough()` applies `SetNextFrameWantCaptureKeyboard(ctx, IsAnyItemActive(ctx))` every frame. Reflex and Navigator now call that helper instead of open-coded blocks. Removed manual REAPER command mirrors for Cmd+Z/Cmd+Shift+Z, Space, Up, and Down to avoid double-firing once real REAPER global shortcuts pass through.

- ✅ **NAV popup geometry primitives + global menu wording (v20.586).** Tightened the v20.584 style centralization so NAV popup rows share both color and geometry. `ReflexMenuItem` now uses a custom-sized `Selectable` row with explicit internal text padding, so hover bg leaves a consistent gap around text instead of relying on raw `MenuItem` offsets. Added `ReflexPopupLabel` and `ReflexPopupSeparator` for non-clickable popup text and dividers. Shared NAV global right-click menu now starts with white `Navigator v<version>`, then a separator, then `UI size` controls, another separator, and `Mirror TLT buttons`; the old `Navigator` section label was removed. The ignored-folder recovery rows also use `ReflexMenuItem`, so they get the same dim/rest and white-hover treatment.

- ✅ **NAV TLT popup text alignment restored (v20.585).** Adjusted `ReflexMenuItem` in `core/Reflex_StyleCore.lua` to use ImGui's native `MenuItem` sizing/row measurement with transparent built-in text, then draw the themed label over it. This preserves popup/menu padding and natural right-side width while keeping the v20.584 behavior of dim resting text and white hover text for `NAV.pill` / `NAV.dot` TLT context rows.

- ✅ **Shared popup/tooltip style core + NAV TLT context menu cleanup (v20.584).** Added `core/Reflex_StyleCore.lua` and installed it from both thin shells (`Reflex.lua`, `Navigator.lua`). The module owns `PushPopupStyle`/`PopPopupStyle`, `PushTooltipStyle`/`PopTooltipStyle`, `Tip`, `TipDirect`, `ShowModKeyTip`, and `ReflexMenuItem`. Shared popup style now forces popup bg, dim resting text, grey `C.fx_ctrl_hover` row hover, active-row color, scrollbar colors, popup rounding, and menu padding consistently across Reflex + Navigator. Shared tooltip style codifies the smaller helper-tooltip padding/rounding separately from larger popup menus. `NAV.pill` / `NAV.dot` TLT right-click rows now use `ReflexMenuItem`, so `Pin`, `Unpin all`, and `Ignore this folder` share the same grey hover bg and flip text from dim to white on hover. The ignore label was simplified from the old Navigator-specific wording to `Ignore this folder`.

- ✅ **Mirror TLT Pills in shared NAV menu (v20.583).** Added the existing `nav_mirror` preference to the shared Navigator right-click popup in `core/Reflex_NavViewCore.lua` as `Mirror TLT Pills`. The toggle persists via `SavePref("nav_mirror", ...)` and affects expanded `NAV.pill` alignment in both Reflex and standalone Navigator.
- ✅ **Per-project A/R view-mode state + Active refresh flash (v20.582).** Added shared project-tab syncing in `core/Reflex_ViewModes.lua`: switching project tabs now saves the current project's Active/Routing mode state and restores the remembered state for the newly active project, or resets A/R cleanly for projects with no remembered state. `Reflex.lua` and `Navigator.lua` call `MaybeSyncViewModeProject()` before per-frame Active peak scanning. Added a two-pulse Active refresh flicker in `core/Reflex_NavViewCore.lua` using a brighter version of A's current active red when A is clicked again to rescan.
- ✅ **A/R state color correction (v20.581).** Corrected shared A/R state mapping in `core/Reflex_NavViewCore.lua`: hover keeps the charcoal rest background and changes only the glyph color (A red, R blue), while active/pressed/on state uses the colored fill with white glyph text. Disabled A/R behavior from v20.580 is preserved.
- ✅ **Disabled A/R tooltip cleanup (v20.580).** Updated shared A/R rendering in `core/Reflex_NavViewCore.lua` so R also fades to the 40% disabled state and suppresses hover color when no track is selected. Removed the click-triggered Active `No levels` popup; disabled A/R now use a single hover tooltip with a normal first line (`Active tracks view` / `Routing view`) and a muted reason line (`No levels detected` / `No track selection`). `ActiveViewToggle()` no longer sets a toast timestamp on failed entry.
- ✅ **A/R hot background + disabled Active state (v20.579).** Updated shared A/R button rendering in `core/Reflex_NavViewCore.lua` so both A and R use `#1185e0` for hover and active backgrounds. Added `ActiveViewHasSignal()` in `core/Reflex_ViewModes.lua`, reusing the existing per-frame peak cache, so A fades its full button assembly to 40% opacity when no recent qualifying level is present. Disabled A suppresses the hover color, blocks activation, and shows a brief `No levels` indication / tooltip instead of failing silently.
- ✅ **A/R PNG canvas scale tied to circle (v20.578).** Corrected shared A/R PNG rendering in `core/Reflex_NavViewCore.lua`: glyph image quads now draw at the actual A/R circle diameter (`mini_tlf_h`, same visual scale as `NAV.dot`) instead of a separate `S(40)` target. This keeps the 64px source canvas proportional to the circle across Navigator scaling and fixes the letter appearing too large relative to the button.
- ✅ **A/R PNG glyph rendering (v20.577).** Switched shared NAV A/R labels in `core/Reflex_NavViewCore.lua` from `DrawList_AddText` to tintable PNG glyphs loaded from `icons/Nav.Active.A.png` and `icons/Nav.Route.R.png`. The image quad draws at `S(40)` (`32x32` logical px at 100% NAV scale) centered inside the existing A/R circles and tints with the same rest/hover/active colors. Both Reflex and standalone Navigator pass `script_dir` into shared NAV core. Text drawing remains as a fallback only if an image fails to load, using the final hardcoded fallback offsets from v20.575.
- ✅ **Hide empty ignored-folder menu section (v20.576).** Updated shared Navigator right-click menu in `core/Reflex_NavViewCore.lua` so `Ignored Folders` is shown only when at least one TLT is currently ignored. Empty state text (`No ignored folders`) was removed to keep the menu compact.
- ✅ **Remove A/R tuning menu (v20.575).** Removed the temporary A/R label offset controls from the shared Navigator right-click menu in `core/Reflex_NavViewCore.lua`. Final offsets are hardcoded again so old saved tuning prefs cannot override them: A `x + 0.50, y + 0.00`; R `x + 1.00, y + 0.00`.
- ✅ **A/R label offset baseline (v20.574).** Updated shared A/R label offset defaults in `core/Reflex_NavViewCore.lua` to the manually chosen values from the in-script tuning panel: A `x + 0.50, y + 0.00`; R `x + 1.00, y + 0.00`. Reset now returns to these values.
- ✅ **Standalone Navigator whole-window context scope (v20.573).** Added `nav_context_scope` to shared `NavDrawSection` in `core/Reflex_NavViewCore.lua`. Reflex keeps the default NAV-bounds right-click scope so inspector right-clicks below NAV are not stolen. Standalone `Navigator.lua` passes `nav_context_scope = "window"`, so its Navigator menu opens anywhere in the standalone window background while still excluding hovered `NAV.pill` / `NAV.dot` TLT buttons.
- ✅ **NAV tuning helper wrapper (v20.572).** Refactored the Navigator right-click menu in `core/Reflex_NavViewCore.lua` so the popup calls a shared `NavDrawTuningControls()` helper instead of directly calling the A/R label adjustment UI. Current behavior is unchanged; this gives future manual tuning controls a single core helper surface to extend.
- ✅ **Manual A/R label offset controls (v20.571).** Added shared A/R label alignment controls to the Navigator right-click menu in `core/Reflex_NavViewCore.lua`. The menu now exposes A x/y and R x/y controls in raw draw-list coordinates with `0.25` step buttons plus Reset. Values persist via shared prefs (`nav_ar_a_x`, `nav_ar_a_y`, `nav_ar_r_x`, `nav_ar_r_y`), so Reflex and standalone Navigator use the same tuning. Defaults preserve v20.570's visual offsets: A `x + 0.5, y + 0.0`; R `x + 1.0, y + 0.5`.
- ✅ **A/R label nudge constants for 0.25 tuning (v20.570).** Replaced inline shared A/R label nudge ternaries in `core/Reflex_NavViewCore.lua` with explicit `AR_LABEL_NUDGE` per-glyph constants. Values are still raw draw-list coordinates, with `0.5` ≈ 1 Retina screenshot px and `0.25` as the new half-pixel fine-tuning step. Current visual offsets are unchanged: A `x + 0.5, y + 0.0`; R `x + 1.0, y + 0.5`.
- ✅ **NAV-wide context menu surface (v20.569).** Updated shared `core/Reflex_NavViewCore.lua` so the Navigator right-click menu opens anywhere inside the NAV rectangle except on actual TLT buttons. `NAV.pill` and `NAV.dot` hover now block the NAV-wide menu so their TLT-specific right-click menu still wins; blank space, `NAV.arr`, A/R buttons, row gaps, and the expanded NAV scroll area open `##navctx` in both Reflex and standalone Navigator.
- ✅ **A/R tooltip ownership fix (v20.568).** Fixed shared A/R tooltip routing in `core/Reflex_NavViewCore.lua`. `Tip()` sets a tooltip directly and does not perform its own hover check, so both A/R calls were setting tooltips every frame and whichever button drew last won (`R` in same-row mode, `A` in stacked mode). Tooltips are now gated by each button's stored `hov` result from `NavCircle`.
- ✅ **A label right 1 Retina px (v20.567).** Adjusted shared A/R label micro-nudge in `core/Reflex_NavViewCore.lua`: A moves right 1 Photoshop/Retina screenshot px. Current offsets: A `x + 0.5, y + 0.0`; R `x + 1.0, y + 0.5`.
- ✅ **R label down 1 Retina px (v20.566).** Adjusted shared A/R label micro-nudge in `core/Reflex_NavViewCore.lua`: R moves down 1 Photoshop/Retina screenshot px by using per-label raw y offsets. Current offsets: A `x + 0.0, y + 0.0`; R `x + 1.0, y + 0.5`.
- ✅ **A/R label down 1 Retina px (v20.565).** Adjusted shared A/R label micro-nudge in `core/Reflex_NavViewCore.lua`: both A and R move down 1 Photoshop/Retina screenshot px by changing raw draw-list y offset from `-0.5` to `0.0`. X offsets remain A `0.0`, R `1.0`.
- ✅ **Expanded A/R pair fallback left-align (v20.564).** Updated shared expanded NAV fallback in `core/Reflex_NavViewCore.lua`: when A/R break together below `NAV.arr`, they now render as adjacent left-aligned circles with the normal `NAV.dot` gap instead of bridging to the left/right `NAV.pill` edges. The very narrow fallback still stacks `R` then `A`.
- ✅ **NAV.arr rest color + all Reflex-window smoothing (v20.563).** Updated shared `NAV.arr` rest color to `#545a5a` in `core/Reflex_NavViewCore.lua` for both expanded (`▼`) and collapsed (`▶`) states, with hover still using `C.text`. Extended `CircleTessellationMaxError = 0.1` to Reflex's FX Browser and pop-out Remote window style stacks too, so smoothing now covers the main Reflex window, standalone Navigator, and Reflex auxiliary windows when the ReaImGui style var is available.
- ✅ **Smoother rounded corners globally (v20.562).** Promoted `CircleTessellationMaxError = 0.1` from the card-only path to the main Reflex and standalone Navigator window style stacks when the ReaImGui style var is available. This smooths rounded-rect arcs (`NAV.pill`, `NavRect`, scale controls, cards, popups inherited inside the window) in addition to the explicit 48-segment NAV circles from v20.561.
- ✅ **Smoother NAV circles (v20.561).** Added explicit `NAV_CIRCLE_SEGMENTS = 48` to both shells' `NavCircle` primitive and applied the same segment count to shared `NAV.dot` / collapsed-pill color circles and pin overlays in `core/Reflex_NavViewCore.lua`. This avoids ImGui's low auto segment count on small circles, so Reflex and standalone Navigator render rounder NAV circles without bitmap assets.
- ✅ **A/R retina nudge follow-up 4 (v20.560).** Applied the latest Photoshop-measured A label correction in `core/Reflex_NavViewCore.lua`: A moves left 1 Retina screenshot px from v20.559. Raw draw-list offsets are now A `x + 0.0`, R `x + 1.0`, both A/R `y - 0.5`.
- ✅ **A/R retina nudge follow-up 3 (v20.559).** Applied the latest Photoshop-measured A label correction in `core/Reflex_NavViewCore.lua`: A moves right 1 Retina screenshot px from v20.558. Raw draw-list offsets are now A `x + 0.5`, R `x + 1.0`, both A/R `y - 0.5`.
- ✅ **A/R retina nudge follow-up 2 (v20.558).** Applied the latest relative A/R label correction in `core/Reflex_NavViewCore.lua`: both labels move right 1 Retina screenshot px and up 1 Retina screenshot px from v20.557. Raw draw-list offsets are now A `x + 0.0`, R `x + 1.0`, both A/R `y - 0.5`.
- ✅ **A/R retina nudge follow-up (v20.557).** Applied the latest Photoshop-measured A/R label correction in `core/Reflex_NavViewCore.lua` using raw 2x Retina draw-list coordinates: A keeps `x - 0.5` and moves down 1 screenshot px to neutral y; R moves right 1 screenshot px to `x + 0.5` and down 1 screenshot px to neutral y. Layout/wrap behavior from v20.555 is unchanged.
- ✅ **A/R retina micro-nudge correction (v20.556).** Reworked A/R label micro-offsets in `core/Reflex_NavViewCore.lua` to match Photoshop measurements taken from Retina screenshots. The previous `S(0.625)` approach rounded tiny offsets up to whole ImGui coordinates, visually over-moving the letters on a 2x display. A/R text now uses raw draw-list coordinates for sublogical movement: A `x - 0.5`, both A/R `y - 0.5`, R x unchanged. Layout/wrap behavior from v20.555 is unchanged.

- ✅ **Navigator right-gap parity + collapsed A/R stack order (v20.555).** Restored Reflex's right-edge NAV width offset under NAV scale and applied the same `S(UI.edge_pad) - 3` width extension in standalone `Navigator.lua`, so the right script gap is 14 retina px tighter than the left to visually blend with REAPER's existing edge gutter. Collapsed `NAV.dot` now reverses A/R to `R` then `A` when the row is too narrow for the A/R pair after `NAV.arr`, matching the expanded stacked priority. Retuned A/R label nudges from the retina convention: A moves left/up 1 retina px (`-S(0.625)` x/y), R moves up 1 retina px.

- ✅ **Expanded A/R grouped wrapping (v20.554).** Refined shared NAV A/R behavior in `core/Reflex_NavViewCore.lua`. Expanded `NAV.arr` keeps A/R fixed at top-right until the A/R pair itself no longer fits beside the arrow (no longer factoring TLF1 into that threshold). When the pair drops, A and R stay grouped: first `A` left-aligned and `R` right-aligned to the `NAV.pill` edges on row 2 with the gap compressing as width tightens, then if the pair cannot share a row they stack as `R` then `A` so Routing remains first in a column. Collapsed `NAV.dot` remains normal flow: `NAV.arr A R TLF1 TLF2...`. Updated colors to rest/hover/active bg `#171b21`, rest text `#919394`, hover text white, A active text `#da6449`, R active text `#4b85dd`; added retina-convention nudges (A +1px x/y, R +2px x +1px y via `S(0.625)` / `S(1.25)`).

- ✅ **A/R button styling + collapsed flow simplification (v20.553).** Updated shared NAV A/R buttons in `core/Reflex_NavViewCore.lua`: rest bg/text `#2e3033`/`#98999a`, hover bg/text `#171b21`/white, active bg `#171b21`, A active text `#da6449`, R active text `#4b85dd`, with smaller `GetSteppedFont(-1)` labels. Collapsed `NAV.dot` now always flows `NAV.arr A R TLF1 TLF2...` using the full row width; A/R no longer reserve or pin to a top-right zone in collapsed mode. Expanded NAV keeps the top-right A/R header behavior opposite `NAV.arr` (with existing narrow fallback).

- ✅ **Shared NAV ignore menu + separate Navigator scale (v20.552).** Moved TLT ignore/unignore out of `HDR.name` and into shared NAV surfaces. `NAV.dot` and `NAV.pill` right-click menus now include `Ignore in Navigator - show children` for eligible top-level track entries (not `SONGS`, `ARCHIVE`, subgroup parents, or promoted ghost children). `NAV.arr` / blank top-row right-click opens a shared Navigator menu with `Navigator Size` controls plus an `Ignored Folders` checked list; clicking a checked folder un-ignores it, saves, marks NAV dirty, and the item disappears from that recovery menu. Added `NavCanExcludeTrack` / `NavSetTrackExcluded` to `core/Reflex_NavExclusionCore.lua` and kept rendering/menu behavior in `core/Reflex_NavViewCore.lua` so Reflex and standalone Navigator share it. Added `navigator_scale_v1`: Reflex's settings row is now `Reflex Size` and no longer scales `NAV.*`; standalone Navigator uses the same NAV scale.

- ✅ **Standalone Navigator dock-triangle hide (v20.551).** Matched Reflex's dock/tab color suppression in `Navigator.lua`: tab/button/nav-windowing colors are pushed to the Navigator window bg, and normal text color is restored only inside the visible window body. Fixes the blue ImGui triangle appearing in standalone Navigator's upper-left corner. No shared `NAV.*` behavior change.

- ✅ **Standalone Navigator + shared NAV modules (v20.550).** Added `Navigator.lua` as an independently runnable REAPER action/window for the top NAV section only. Extracted the shared NAV action layer into `core/Reflex_NavActionCore.lua` (`HandleTracksClick`, `HandleSongsClick`, show/hide/toggle helpers, pin restoration, and `ScrollTrackToCenter`) and the shared NAV renderer into `core/Reflex_NavViewCore.lua` (`NAV.arr`, collapsed `NAV.dot`, expanded `NAV.pill`, pin context menus, scroll indicator, and A/R buttons). `Reflex.lua` now calls the same NAV view/action modules, while standalone Navigator keeps only a thin theme/prefs/window/scan shell. Remote remains inline/pop-out only for now; standalone Remote is still a later split.

- ✅ **SEND add-card/grid consolidation (v20.549).** Folded `core/Reflex_SendAddCardCore.lua` into `core/Reflex_SendGridCore.lua` and removed the separate add-card module load. `DrawSendAddCard`, `DrawSendDimPlaceholder`, and `SendsDrawSpanningAddRow` now live beside the grouped SEND grid and section wrappers they serve, improving SEND render ownership without changing behavior.

- ✅ **SEND side-column wrapper extraction (v20.548).** Moved `DrawSendsColumn` from `Reflex.lua` into `core/Reflex_SendGridCore.lua`. The grid core now owns the side-by-side SEND wrapper used by inspector split layouts: responsive column-count override, delegation into `SendsDrawSection(..., true)`, and the empty SEND add-placeholder card. No behavior change intended.

- ✅ **SEND section wrapper extraction (v20.547).** Moved the full `SendsDrawSection` wrapper from `Reflex.lua` into `core/Reflex_SendGridCore.lua`. The grid core now owns SEND activation refresh, scroll-to, top-margin handling, fallback flat-group construction, measurement/delegation into grouped columns, spanning add-row gating, and distant-section delegation. No behavior change intended.

- ✅ **Collapsed NAV A/R click-through fix (v20.546).** Fixed A/R buttons in collapsed NAV fixed mode expanding the track nav because the trailing collapsed-row `##navtrail` click area extended through the reserved A/R zone. The trail hit box now stops at the fixed-mode A/R left boundary; flow-mode A/R and TLT dots keep the existing full-row trailing behavior. No behavior change intended outside collapsed NAV A/R clicks.

- ✅ **SEND grid measurement extraction (v20.545).** Moved the shared SEND measurement block from `SendsDrawSection` into `core/Reflex_SendGridCore.lua` as `SendsMeasureGrid`. The grid core now computes column width, padding, title height, knob wrapping, CTRL height, and the metrics passed to `SendsDrawGroups` and `SendsDrawDistantSection`. Uses `GetSteppedFont(UI.font_send_title)` instead of reaching into `Reflex.lua`'s local `scaled_fonts` table. No behavior change intended.

- ✅ **SEND group-wrapper extraction (v20.544).** Moved the outer grouped SEND block from `SendsDrawSection` into `core/Reflex_SendGridCore.lua` as `SendsDrawGroups`. The grid core now owns ungrouped label drawing, folder-chain delegation, `SEND.col` row delegation, and between-group spacing, returning the `last_conforming_last_row_full` signal for the spanning add row. Shared measurements moved later in v20.545; the full `SendsDrawSection` wrapper moved later in v20.547. No behavior change intended.

- ✅ **SEND.col group-row extraction (v20.543).** Moved the normal grouped `SEND.col` row loop from `SendsDrawSection` into new `core/Reflex_SendGridCore.lua` as `SendsDrawGroupColumns`. The grid core now owns row max-FX/SND-expanded height math, per-column cache refresh, `DrawCompactTrackColumn` calls, conforming add-card blanks, dim placeholders, and row cursor advancement. The outer group wrapper moved later in v20.544. No behavior change intended.

- ✅ **SEND spanning add-row extraction (v20.542).** Moved the full-width spanning add-send row wrapper from `SendsDrawSection` into `core/Reflex_SendAddCardCore.lua` as `SendsDrawSpanningAddRow`. The add-card core now owns last-conforming-folder lookup, row gap/cursor placement, target fallback, and the shared plus-card call for the spanning row. The grouped row grid moved later to `SendsDrawGroupColumns`; `SendsDrawSection` still owns the `last_conforming_last_row_full` gate. No behavior change intended.

- ✅ **SEND.folder chain extraction (v20.541).** Moved the conforming group folder-card loop from `SendsDrawSection` into `core/Reflex_SendFolderCore.lua` as `SendsDrawFolderChain`. The folder core now owns collapsed folder cards plus the expanded/collapsed folder-chain wrapper, including expanded height computation and title/blank expand-collapse handling. `SendsDrawSection` passes precomputed metrics and remains the overall SEND orchestrator. No behavior change intended.

- ✅ **SEND.distant section extraction (v20.540).** Moved the Distant Sends section wrapper from `SendsDrawSection` into `core/Reflex_SendDistantCore.lua` as `SendsDrawDistantSection`. The module now owns heading/gap, collapsed/expanded distant card loop, expanded height computation, forced SND-open state, SND-click collapse request handling, blank-area collapse, and exclusive expand state. `SendsDrawSection` passes its precomputed metrics and remains the overall SEND orchestrator. No behavior change intended.

- ✅ **SEND dim-placeholder renderer extraction (v20.539).** Added `DrawSendDimPlaceholder` to `core/Reflex_SendAddCardCore.lua` and replaced the inline non-final-row placeholder drawing in `SendsDrawSection`. The add-card core now owns both interactive plus cards and non-interactive dim filler cells for SEND blank grid spaces. No behavior change intended.

- ✅ **SEND FX-name cache helper extraction (v20.538).** Moved the repeated `sends_fx_cache` refresh/count pattern into new `core/Reflex_SendFxCacheCore.lua` as `SendsEnsureFxNameCache` and `SendsFxCachedCount`. Expanded `SEND.folder`, normal `SEND.col`, and expanded `SEND.distant` render paths now share the same count-change rebuild logic. `DrawCompactTrackColumn` still owns actual FX row rendering; no behavior change intended.

- ✅ **SEND add-card renderer extraction (v20.537).** Moved the duplicated SEND add-send plus-card body into new `core/Reflex_SendAddCardCore.lua` as `DrawSendAddCard`. Conforming blank cells and the spanning add row share the same renderer for placeholder fill, transparent hit area, hover plus icon, left-click send creation, and right-click send-mode popup. Current callers are `SendsDrawGroupColumns` for row blanks and `SendsDrawSpanningAddRow` for the full-width row. No behavior change intended.

- ✅ **SEND.distant collapsed-card extraction (v20.536).** Moved the collapsed `SEND.distant` spanning-card renderer from `SendsDrawSection` into new `core/Reflex_SendDistantCore.lua` as `DrawDistantSendCollapsedCard`. The module owns hover fill, title locate/peek link, SC badge fade, and the full-card expand hit area. Expanded distant cards still render through `DrawCompactTrackColumn` in `Reflex.lua`; no behavior change intended.

- ✅ **SEND.folder collapsed-card extraction (v20.534).** Moved `DrawSendFolderCard` from `Reflex.lua` into new `core/Reflex_SendFolderCore.lua`. The module owns the collapsed `SEND.folder` renderer only: title link/click state, folder M/S buttons, and folder vol/pan knobs. Expanded folder cards still render through `DrawCompactTrackColumn` in `Reflex.lua`; no behavior change intended.
- ✅ **SEND.folder font bridge fix (v20.535).** Fixed the v20.534 load error where `core/Reflex_SendFolderCore.lua` referenced `scaled_fonts`, which is local to `Reflex.lua`. The collapsed `SEND.folder` title now uses `GetSteppedFont(UI.font_send_title)`, matching the extracted font helper bridge.

- ✅ **SEND create backend extraction (v20.533).** Moved send-creation/conforming helpers from `Reflex.lua` into new `core/Reflex_SendCreateCore.lua`: `GetInheritedSendColor`, `GetSourceSendDests`, `TrackNameStartsReturns`, `IsConformingReturnsFolderForSource`, `DetermineConformTarget`, `RoutingAddSendTrack`, and `AddSendModePopup`. `SEND.col` and expanded `SEND.distant` drawing remain in `Reflex.lua`; collapsed `SEND.folder` drawing moved later in v20.534 and collapsed `SEND.distant` drawing moved later in v20.536. No behavior change intended.

- ✅ **SEND topology backend extraction (v20.532).** Moved SEND topology/list/group/refresh helpers from `Reflex.lua` into new `core/Reflex_SendTopologyCore.lua`: `AnalyzeSendTopology`, `DebugSendTopology`, `NavRoutingTargetTrack`, `SendsViewToggle`, `SendsViewBuildList`, `SendsViewBuildGroups`, `SendsViewRefresh`, and `SendsViewCheckRefresh`. `SEND.col` and expanded `SEND.distant` drawing remain in `Reflex.lua`; send-creation/conforming mutation code moved later in v20.533, collapsed `SEND.folder` drawing moved in v20.534, and collapsed `SEND.distant` drawing moved in v20.536. No behavior change intended.

- ✅ **ROUTE panel extraction (v20.531).** Moved expanded inline `ROUTE` panel rendering from `InspDrawTrackBlock` into new `core/Reflex_RoutePanelCore.lua` as `DrawRoutePanel(track, bw, hdr)`. This includes sends/receives/hardware section layout, add-popup contents, row loops, and hardware output labels. `InspDrawTrackBlock` remains the orchestrator and still owns the expanded-state gate.

- ✅ **ROUTE tooltip extraction (v20.530).** Moved `FormatChanPacked`, `FormatChanHW`, and `ShowRoutingTooltip` from `Reflex.lua` into new `core/Reflex_RouteTooltipCore.lua`. The module receives `r`, `ctx`, and `C`; `CTRL.route` pill drawing and SEND topology rendering remain in `Reflex.lua`. Expanded `ROUTE` panel layout moved later in v20.531.

- ✅ **ROUTE.row renderer extraction (v20.529).** Moved the full `DrawRouteRow` renderer from `Reflex.lua` into `core/Reflex_RouteControlsCore.lua`, alongside the row widgets extracted in v20.527. `CTRL.route` section layout and add-menu popup contents moved later in v20.531; SEND topology rendering remains in `Reflex.lua`. No behavior change intended.

- ✅ **ROUTE add-menu extraction (v20.528).** Moved `ROUTE.sends/recvs/hw` filterable add-menu helpers from `Reflex.lua` into new `core/Reflex_RouteMenuCore.lua`: `RouteFilterMatch`, `RouteAddMenuList`, `RouteSectionHeader`, `RouteBuildSortedTrackList`, and the add-menu/scroll state they own. The module receives `r`, `ctx`, `C`, and a window-height bridge; actual `ROUTE` panel layout and popup contents moved later in v20.531.

- ✅ **ROUTE.row control extraction (v20.527).** Moved route send-control widgets from `Reflex.lua` into new `core/Reflex_RouteControlsCore.lua`: `RouteVolValue`, `RoutePanValue`, `RouteMidiDropdown`, `DrawRouteModeDD`, `RouteChannelDropdown`, and the route send-mode label tables. `DrawRouteRow` later moved into the same module in v20.529, and `ROUTE` section layout moved in v20.531. `SEND.col` rendering remains in `Reflex.lua`; no behavior change intended.

- ✅ **FX.row helper extraction (v20.526).** Moved the shared `FX.row` context menu, outline cascade, and click/drag interaction kernel from `Reflex.lua` into new `core/Reflex_FXRowCore.lua`: `FxRowContextMenu`, `FxRowOutlineColor`, and `FxRowInteract`. The module receives `r`, `ctx`, `C`, the compare ext-state section, a compare check-time setter, and an FX rename bridge; actual `FX.row` drawing remains in `Reflex.lua`.

- ✅ **FLOW-visible FX selection persistence (v20.525).** Fixed `FX.row` multi-selection being lost when browsing between visible FLOW cards. `InspCleanupDragState` now accepts `keep_fx_selection`, and the selection-tracking branch computes whether `insp_fx_sel_track` will remain rendered after the switch (current card, FLOW chain, or active SEND.col list). Drag/insert state still resets on the switch; selected FX outlines persist as long as their track stays visible.

- ✅ **Flow backend extraction (v20.524).** Moved Flow View chain/focus/toggle helpers from `Reflex.lua` into new `core/Reflex_FlowCore.lua`: `FlowViewBuildChain`, `FlowViewToggle`, `FlowViewSetFocus`, and `FlowViewRefresh`. The module receives `r` plus small bridges for `insp_pinned`, `insp_pin_suppress_selected`, and `nav_scroll_target`; `FLOW.btn`, minimal-card drawing, flow arrows, flow render loop, and expanded-card click handling remain in `Reflex.lua`.

- ✅ **Core module folder organization (v20.523).** Moved module/helper files into `core/` while leaving user-facing root files in place (`Reflex.lua`, `Reflex_Theme.lua`, action scripts, generated text files, and assets). `package.path` now prepends `script_dir .. "core/?.lua;"` before the root fallback, so existing `require("Reflex_*")` names remain unchanged. No behavior change intended.

- ✅ **FX clipboard backend extraction (v20.522).** Moved FX copy/cut/paste state and helpers from `Reflex.lua` into new `Reflex_FXClipboardCore.lua`: `nav_fx_clipboard`, `nav_fx_clip_pending_paste`, `nav_fx_clip_last_hover_track`, `FxClipClear`, `FxClipHasContent`, `FxClipCount`, `FxClipCapture`, `FxClipPaste`, `FxClipFindHoveredRow`, `FxClipFindHoveredCard`, `FxClipResolvePasteTarget`, `FxClipRebuildGuidSet`, paste-landing state, `NavPasteLandedAlpha`, `NavPasteLandedHas`, `FxClipHasGuid`, `NavCardIsDropTarget`, `FxClipIsHoveredTrack`, `FxClipExecutePendingPaste`, `FxClipResolveHover`, `FxClipRenderCarryPill`, `FxClipDeleteSelection`, `FxClipConvertCopyToCut`, `FxClipDoCopyOrCut`, `FxClipCopyAllFX`, and `FxClipRemoveAllFX`. The module receives `r`, `ctx`, and `C`; keyboard shortcut dispatch, the footer clipboard chip, and FX chain renderers remain in `Reflex.lua`.

- ✅ **FX drag backend extraction (v20.521).** Moved the cross-chain FX drag/drop backend from `Reflex.lua` into new `Reflex_FXDragCore.lua`: `fx_drag`, `FX_DRAG_THRESHOLD`, `nav_fx_drag_last_hover_track`, `FxDragBegin`, `FxDragTryActivate`, `FxDragClear`, `FxDragIsActive`, `FxDragSourceIs`, `FxDragPollEscape`, `FxDragReadMode`, `FxStripAutomation`, `FxDragTrackLabel`, `FxDragLegendTip`, `fx_drop_targets`, `fx_drag_scroll_req`, `FxDropTargetRegister`, `FxDropComputeTarget`, `FxDragAutoScrollCheck`, `FxDragApplyScroll`, and `FxDragResolveDrop`. The module receives `r`, `ctx`, and `C`; `FX.row` rendering, `SEND.col` rendering, flow auto-expand, and footer chip UI remain in `Reflex.lua` with no behavior change intended.

- ✅ **Noise scan helper extraction (v20.520).** Moved `NoiseScanAllTracks` from `Reflex.lua` into new `Reflex_NoiseCore.lua`. The module installs the same global helper and receives `r` plus a `get_noise_cache` bridge so resets of `insp_meter_noise` remain visible. Settings panel rendering and `noise_scan_results` / `noise_scan_time` ownership stay in `Reflex.lua`.

- ✅ **Routing/Active View auto-scroll (v20.519).** After applying Routing View, Reflex defers a TCP scroll to `routing_view_source` so top-level source tracks are not left hidden above the current TCP scroll. After applying Active View, Reflex scrolls to the first visible result by track number. The view-mode helper uses direct JS TCP scrolling without changing selection after visibility changes settle, falling back to `ScrollTrackToCenter` only if JS scroll is unavailable.

- ✅ **Routing/Active relationship helper extraction (v20.518).** Moved the four routing-view relationship helpers from `Reflex.lua` into `Reflex_ViewModes.lua`: `RoutingViewGetParentChain`, `RoutingViewGetChildren`, `RoutingViewGetSendDests`, and `RoutingViewGetRecvSources`. The module already owned `RoutingViewScan` / `ActiveViewScan`, so this keeps the scan backend in one place. `RoutingViewDrawButton` and all UI rendering remain in `Reflex.lua`.

- ✅ **SEND inside-folder add parity (v20.517).** Fixed blank `Create send to new track (inside folder)` panels creating a new loose/`Ungrouped` return while the routing pill `+` correctly reused the existing `Returns*` folder. Two causes: SEND add panels now target the rendered `sends_view_source` instead of re-resolving through `NavRoutingTargetTrack`, and `RoutingAddSendTrack(..., target_folder)` now preserves nested-folder closures while moving the target/outer closures to the new last child. This keeps new returns inside `Returns*` even when the return folder is inside a parent folder.

- ✅ **Tight conforming SEND.folder rule (v20.516).** Aligned render-time grouping with create-time conforming. `SendsViewBuildGroups` now creates `SEND.folder` groups only for direct-child returns inside a sibling `Returns*` folder. Local sends render as normal columns unless conforming groups also exist, in which case loose/nonconforming locals appear under `Ungrouped`. Remote sends still render as `SEND.distant`, and inside-folder add blanks can only target folders that pass the same conforming predicate.

- ✅ **SEND.distant SC badge freshness (v20.515).** Fixed distant cards not showing/hiding the `SC` badge until navigating away after changing an existing send from channels 1/2 to 3/4 or back. `SendsViewCheckRefresh` now compares cached distant `is_sidechain` against live `I_DSTCHAN`; mismatch triggers `SendsViewRefresh()` so the badge and non-sidechain-before-sidechain ordering update on the next frame.

- ✅ **Remote-only SEND.distant classification (v20.514).** Fixed remote sends failing to surface when no conforming `SEND.folder` group existed. `SendsViewBuildGroups` no longer demotes distant entries back to ungrouped when `#group_order == 0`, and `SendsDrawSection` skips the flat fallback when `sends_view_distant` has entries. Also tightened the top-level source case: sends into top-level `Returns*` folders remain local folder groups, while sends into other unrelated folder contexts classify as `SEND.distant`.

- ✅ **Font helper extraction (v20.513).** Moved scaled font lookup and push/pop helpers from `Reflex.lua` into `Reflex_FontCore.lua`: `GetFontStep`, `GetSteppedFont`, `GetScaledFont`, `GetScaledItalicFont`, `GetScaledRegularFont`, `PushFont`, and `PopFont`. The module installs the same globals and receives `r`, `ctx`, the prebuilt font tables, and a `ui_scale` bridge. Font creation remains in `Reflex.lua`; all renderers still call the same helper names.

- ✅ **Meter helper extraction (v20.512).** Moved shared meter/math helpers from `Reflex.lua` into `Reflex_MeterCore.lua`: `VolToKnobT`, `MeterColor`, and `SmoothPeak`. The module installs the same globals and receives `C`. VOL slider, knob meter dots, SEND.col meter bars, flow mini meters, and peak smoothing call sites remain in `Reflex.lua`; no drawing or interaction behavior moved.

- ✅ **Color helper extraction (v20.511).** Moved shared color backend helpers from `Reflex.lua` into `Reflex_ColorCore.lua`: `TrackColorToImGui`, `ScaleColor`, and `FxStateColors`. The module installs the same globals and receives `r` plus `C`. `FX.row`, `SEND.col`, NAV.pill/NAV.dot color usage, and song button rendering still call the same helper names; no drawing or interaction behavior moved.

- ✅ **Realist backend extraction (v20.510).** Moved read-only Realist/timeline helpers from `Reflex.lua` into `Reflex_RealistCore.lua`: `GetRealistCurrentSong`, `FindSongRegionBounds`, and `ClampViewToRegion` plus the small view-lock settle state (`vl_stable`, `vl_ps`, `vl_pe`). The module installs the same globals and receives `r` plus the Realist ProjExtState section name. Track scanners, song visibility helpers, and Loop's current-song/view-lock checks still call the same helper names; no NAV.pill / NAV.dot or SONGS UI behavior moved.

- ✅ **FX selection backend extraction (v20.509).** Moved FX multi-select state and helpers from `Reflex.lua` into `Reflex_FXSelectionCore.lua`: `insp_fx_sel`, `insp_fx_sel_track`, `insp_fx_sel_anchor`, `InspFxSelClear`, `InspFxSelCount`, `InspFxSelHas`, `InspFxSelBindTrack`, `InspFxSelToggle`, `InspFxSelAdd`, `InspFxSelRangeSet`, and `InspFxSelGetFis`. The module installs the same globals and receives `r` as its only dependency. FX.row interaction, outlines, drag activation, clipboard shortcuts, and key handling remain in `Reflex.lua`; no behavior change intended.

- ✅ **Envelope backend extraction (v20.508).** Moved inspector envelope backend helpers from `Reflex.lua` into `Reflex_EnvelopeCore.lua`: `InspStripName`, `InspGetEnvAlias`, `InspSetEnvAlias`, `InspCountFXEnvelopes`, `InspGetFXEnvelopeDetails`, `InspGetAllTrackEnvelopeDetails`, `InspSetEnvelopeVisible`, `InspSetEnvelopeVisibleRaw`, `InspBuildEnvCache`, `InspInvalidateEnvCache`, `InspStripEnvSuffix`, `InspFormatSendEnvName`, `InspFormatEnvForTrackList`, `InspEnvColor`, `InspEnvSortKey`, and `InspEnvelopeState`. The module installs the same globals and receives explicit bridges for `r`, `C`, `ENV_ALIAS_SECTION`, and `InspGetFxList`. `HDR.ENV`, ENV.row drawing, FX envelope rows, and FX cache refresh logic remain in `Reflex.lua`; no UI behavior change intended.

- ✅ **A/B compare backend extraction (v20.507).** Moved `InspCmpClearAll`, `InspCmpCheckGlobal`, `InspCmpParseAssignment`, `InspCmpBuildAssignment`, `InspCmpResetAssigned`, `InspCmpApplyPhase`, `InspCmpResetAndApply`, `InspCmpTogglePhase`, `InspCmpSwitchMode`, `InspCmpFloatAll`, and `InspCmpAnyFloating` from `Reflex.lua` into `Reflex_CompareCore.lua`. The module installs the same globals and receives explicit bridges for `CMP_EXT_SECTION`, `CmpKey`, `insp_track`, `InspGetFxList`, and the local compare summary state. CMP drawing and `FX.row` A/B buttons remain in `Reflex.lua`.

- ✅ **Subgroup helper backend extraction (v20.506).** Moved `SaveSubGroupState`, `ApplySubGroupSelection`, and `ShowSubGroupSelected` from `Reflex.lua` into `Reflex_SubGroupCore.lua`. The module installs the same globals and receives `SetTrackVis` as a dependency. TRACKS click handlers and `NAV.pill` / `NAV.dot` UI remain unchanged.

- ✅ **Song helper backend extraction (v20.505).** Moved the current-song visibility helpers from `Reflex.lua` into `Reflex_SongCore.lua`: `ShowSongsForCurrentSong`, `ApplySongSectionSelection`, and `ShowSongSectionsSelected`. The module installs the same globals and receives explicit dependencies for `SONG_SECTIONS`, `GetRealistCurrentSong`, `SetTrackVis`, `GetChildren`, `ExpandChildFolders`, `songs_entry_ref`, `songs_sub`, `songs_follow_active`, `songs_follow_last`, and `songs_section_mode`. TRACKS/SONGS UI click handlers are unchanged; they still call the same helper names.

- ✅ **Track scan backend extraction (v20.504).** Moved `ScanTopFolders`, `ScanSubGroups`, `ScanSongSections`, `BuildRenderList`, and `ScanSongs` from `Reflex.lua` into `Reflex_TrackScanCore.lua`. The module installs the same globals but receives explicit bridges for the local scanner state (`top_folders`, `archive_entry`, `songs_entry_ref`, `render_list`, `song_entries`, `needs_rescan`, `needs_song_rescan`, `songs_last_click`) plus subgroup/song config (`sub_groups`, `sub_group_by_name`, `songs_sub`, `SONG_SECTIONS`). `ExcludedTrack` and `GetRealistCurrentSong` are passed as dependencies. `NAV.pill` / `NAV.dot` renderers and click handlers still read the same local state in `Reflex.lua`; only the backend scanners moved.

- ✅ **Flow card collapse isolation (v20.503).** Fixed a pre-existing multi-expand interaction bug in flow view. Clicking a selected expanded non-focus flow card now collapses only that card (`flow_view_expanded_set[track] = nil`) and leaves every other expanded flow card untouched. Clicking the selected source/focus card is now a no-op; the source/focus card is always full and has no expand/collapse state. Root cause: flow header click handling used "not secondary" as a proxy for "source/focus," but after browsing/selecting an expanded non-focus card, that card was also "not secondary," so its click took the focus-card branch and cleared the whole `flow_view_expanded_set`. The full-card blank-space focus click branch also cleared the full set. Both branches now distinguish the true source/focus via `flow_view_anchor`.

- ✅ **Track utility backend extraction (v20.502).** Moved the backend-only folder utility helpers from `Reflex.lua` into `Reflex_TrackUtilCore.lua`: `GetChildren`, `SetFolderCollapsed`, `ExpandChildFolders`, `CollapseChildFolders`, `ExpandAllChildFolders`, `SetFolderVisible`, `IsFolderVisible`, and `IsItemVisible`. The module receives `SetTrackVis` as a dependency and installs the same globals, so existing TLT click handlers, song visibility helpers, pin visibility restoration, and show/hide commands keep calling the same API. No `NAV.pill` / `NAV.dot` rendering, scan state, or UI behavior moved.

- ✅ **Nav exclusion storage rewrite — GUID-keyed, per-project (v20.501).** Fixed the same class of identity bug that pins had pre-v20.480: excluded TLTs were keyed by track name and persisted in global ExtState, so renaming a TLT dropped its excluded state and opening another project tab with the same TLT name falsely inherited the exclusion. `nav_excluded` is now keyed by track GUID and stored in `ProjExtState/0/"reflex"/"nav_excluded"`. `LoadNavExcluded()` deletes the legacy global ExtState key on load (clean break, no name-to-GUID migration). Added `MaybeReloadNavExcluded()` for project-tab switches and `ExcludedTrack(track)` for O(1) GUID lookup with `ValidatePtr` guard. Migrated reads in `BuildRenderList`, `SyncGhostVisibility`, and the `HDR.name` context menu; the menu still owns the UI, but writes `r.GetTrackGUID(track)` into the map. Renaming an excluded TLT no longer affects exclusion state, and same-named TLTs in other project tabs no longer collide.

- ✅ **Nav exclusion backend extraction (v20.500; UI moved in v20.552).** Moved excluded-TLT persistence and ghost-parent visibility sync from `Reflex.lua` into `Reflex_NavExclusionCore.lua` using the installer-module pattern. `LoadNavExcluded`, `SaveNavExcluded`, `MaybeReloadNavExcluded`, `ExcludedTrack`, `SyncGhostVisibility`, `NavCanExcludeTrack`, and `NavSetTrackExcluded` install as globals, and `nav_excluded` remains an installed global for shared NAV menus. `top_folders` remains local in the shells; the module receives a `get_top_folders` bridge, `SetTrackVis` as `set_track_vis`, and an optional `mark_dirty` callback. Ignore/unignore UI now lives on `NAV.dot` / `NAV.pill` / `NAV.arr`, not `HDR.name`.

- ✅ **Pin backend extraction (v20.499).** Moved GUID-keyed, per-project TLT pin persistence from `Reflex.lua` into `Reflex_PinCore.lua` using the established installer-module pattern. The moved API is unchanged: `LoadPinnedFolders`, `SavePinnedFolders`, `MaybeReloadPins`, and `PinnedTrack` still install as globals. `pinned_folders` remains an installed global because existing `NAV.dot` and `NAV.pill` right-click menus still read/mutate the set directly for Pin / Unpin / Unpin all. `_pin_last_proj` is now module-local inside the installer closure. `NAV.pill`, `NAV.dot`, and pin UI behavior are unchanged.

- ✅ **FX chunk backend extraction (v20.498).** Moved the pure `FxChunk*` parser/splice helpers from `Reflex.lua` into `Reflex_FXChunkCore.lua` using the established installer-module pattern. The moved API is unchanged: `FxChunkSplitLines`, `FxChunkJoinLines`, `FxChunkLineKind`, `FxChunkFindFxchain`, `FxChunkFxRanges`, `FxChunkExtractFxBlock`, `FxChunkSpliceFxBlocks`, and `FxChunkRegenFxids` still install as globals and continue to back the existing FX clipboard capture/paste flow. `FxClipCapture`, `FxClipPaste`, and carry/drop helpers later moved to `Reflex_FXClipboardCore.lua` in v20.522; `FX.row` and UI call sites remain in `Reflex.lua`. No behavior change intended.

- ✅ **Routing clipboard backend extraction (v20.497).** Moved the v20.485 routing clipboard backend from `Reflex.lua` into `Reflex_RoutingClipboard.lua` using the same installer-module pattern as `Reflex_ViewHistory`, `Reflex_RemoteCore`, `Reflex_ViewModes`, and `Reflex_FXBrowserCore`. The moved API is unchanged: `RoutingClipboardClear`, `RoutingClipboardHasContent`, `RoutingClipboardCaptureItem`, `RoutingClipboardResolveTrack`, `RoutingClipboardCopyAll`, `RoutingClipboardCopyOne`, `RoutingClipboardPaste`, and `RoutingClipboardPasteLabel` still install as globals and continue to back the existing `HDR.name` track context menu and `ROUTE.row` right-click menus. `nav_routing_clipboard` state now initializes inside the module installer. No behavior or UI changes intended.

- ✅ **Routing clipboard hit-area & link styling refinements (v20.486).** Three fixes to the v20.485 routing-clipboard menu surfaces:

  *Inspector card right-click hit area.* The v20.485 catch-all gated on `not IsAnyItemHovered(ctx)`, which blocked right-click anywhere a widget was hovered — even widgets that don't have their own right-click handlers (M/S/X buttons, knobs, sliders, send-section header text region between the "+" button and the routing pill, etc). That made the menu only fire over true blank space, which in practice meant only the HDR area below the title. v20.486 drops the `IsAnyItemHovered` gate and replaces it with a per-frame `nav_rclick_consumed` flag set by widgets that DO open their own popups on right-click: FX rows (`FxRowInteract`), FX-chain compound (`##fxchain_ctx`, both has-FX and no-FX branches), Add-FX (+) button (`##addfx_ctx`, both branches), and route-row catch-all itself. The catch-all now fires on right-click anywhere within the card rect unless one of those handlers claimed the click first. HDR.name right-click already opens the same `##trknamectx` popup, so it doesn't need to set the flag (re-OpenPopup with the same ID is idempotent within a frame).

  *Route-row right-click hit area.* Same root cause: the v20.485 row catch-all gated on `IsAnyItemHovered`, which left only narrow blank-strip regions of the row clickable. v20.486 drops the gate so right-click anywhere on the row card (vol slider, pan slider, M/X/mode/dropdowns, name area) opens the per-row Copy/Paste menu. Sub-widgets don't have their own right-click handlers, so there's no conflict. The row catch-all still claims the click via `nav_rclick_consumed = true` to prevent the inspector card catch-all from also opening trknamectx for the same right-click.

  *Track-name link in send/receive rows.* Replaced the wide `InvisibleButton` + `ScrollTrackToCenter(dest)` pattern with the standard `TitleLink` helper used elsewhere (HDR title, compact track column, FlowDrawMinimalCard, etc.). Visual change: hand cursor on hover + 1px underline drawn at the text baseline + tooltip ("Click to locate · ⌥-click to peek") matching every other locate gesture in the script. Hit-area change: `link_w = min(CalcTextSize(name), name_right - cx)` so the link width matches the actual text rather than spanning the whole pre-channel-group region. Behavior change: `LocateInREAPER` (visibility on, parent folders expanded, scroll TCP to center, select) instead of `ScrollTrackToCenter` (scroll only) — matches the global locate convention, with Opt+click peek support added for free. HW sends keep plain text (no link) since they have no "other end" track.

  *Frame flag rename.* `nav_route_row_rclick_consumed` (v20.485) renamed to `nav_rclick_consumed` (v20.486) since it now serves multiple in-card right-click handlers, not just route rows. Reset at top of `Loop` alongside other transient flags.

- ✅ **Routing clipboard — sends/receives/HW Sends copy/paste (v20.485).** Session-scoped clipboard mirroring the FX clipboard model: single slot, replaced on Copy, append-only on Paste (never replaces existing routing). Self-paste (source track == target) silently skips per-item.

  **State.** `nav_routing_clipboard = nil | { type, count, source_name, items[] }` where `type ∈ {"sends", "receives", "hw_sends"}` and each item carries `{other_guid, mode, vol, pan, mute, mono, phase, midiflags, srcchan, dstchan, autom}`. For sends `other_guid` is the destination track GUID; for receives, the source track GUID; for hw_sends, nil (with `dstchan` in REAPER's plain HW-output channel format rather than the packed format used elsewhere).

  **API (installed globals, global assignment style).** `RoutingClipboardCopyAll(track, category)` captures every item of the given category from track. `RoutingClipboardCopyOne(track, category, send_idx)` captures a single item (per-row Copy in routing view). `RoutingClipboardPaste(track)` resolves each item's `other_guid` to a live track and creates fresh sends/receives via `CreateTrackSend`, then writes all preserved fields. Receives written from the src side (category 0) since `CreateTrackSend(src, target)` returns the new index from src's POV — that's the canonical store side. Single `Undo_BeginBlock`/`EndBlock` pair around the whole paste; label pluralizes ("Paste send" / "Paste 3 sends" / etc.). `RoutingClipboardPasteLabel()` returns the user-facing label or nil when empty.

  **Cross-track receive paste is literal.** Copy receives from track A (which represent `src → A` connections), paste onto B → each `src` track now also feeds B (`src → B`). The receives' "other ends" — the sources — stay where they are; only the receiving track changes.

  **Inspector card menu.** Existing `##trknamectx` popup (the `HDR.name` / card right-click menu) extended below Rename with: separator, `Copy all sends` (disabled when 0), `Copy all receives` (disabled when 0), `Copy all HW Sends` (disabled when 0), `Paste {N} {label}` (only shown when clipboard non-empty). Disabled items use `BeginDisabled(ctx, true)` / `EndDisabled(ctx)` wrap. The old TLT ignore control moved to shared NAV menus in v20.552.

  **Blank-space right-click on inspector cards.** Two new catch-alls open `##trknamectx` from anywhere on the card not occupied by a control: one in `InspDrawInspector`'s primary-card path (after `CardEnd`), one in `InspDrawSelectedTrackCard` (alongside the existing double-click catch-all). Both use the same pattern: capture cursor screen pos before `CardBegin`, then after `CardEnd` check `IsMouseClicked(ctx, 1) and IsMouseHoveringRect(ctx, top_sx, top_sy, top_sx+bw, bot_sy) and not IsAnyItemHovered(ctx) and not nav_route_row_rclick_consumed`. The `IsAnyItemHovered` gate means right-clicks on any registered widget (HDR controls, VOL slider, FX rows, ROUTE rows' sub-widgets, env rows, mini circles, etc.) skip the catch-all. The popup's `BeginPopup` is inside `InspDrawHeader` which already ran for this frame, so `OpenPopup` from the catch-all opens on next frame's `BeginPopup` pass — 1-frame delay, imperceptible.

  **Per-row right-click in routing view (`DrawRouteRow`).** Each row gets its own `prefix .. "row_ctx" .. idx` popup with two items: `Copy {send|receive|HW send}` (single-row Copy that replaces clipboard) and `Paste {N} {label}` (only when non-empty). Same gate as card-level: `IsMouseClicked(1)` + `IsMouseHoveringRect` over the row card + `not IsAnyItemHovered`.

  **Frame-flag conflict resolution.** `nav_route_row_rclick_consumed` is a frame-scoped flag (reset to false at top of `Loop` alongside `nav_title_peek_consumed`). The route-row catch-all sets it true when it fires; both inspector card catch-alls gate on `not nav_route_row_rclick_consumed`. Without this flag, a right-click on route-row blank space would fire BOTH the row's catch-all AND the inspector card's catch-all in the same frame (route rows live inside the card, both rect tests pass, no item is hovered) and two popups would race to render. The flag makes the row-level click claim priority since route rows are more specific surfaces.

  **ID scoping.** The popup IDs (`##trknamectx`, `##s_row_ctx_N`, etc.) are auto-scoped by ImGui's `PushID` stack. Primary card runs without an ID push so its popups are unscoped; secondary card is wrapped in `PushID("nav_secondary_card")` so its popups are scoped under that ID. The catch-alls call `OpenPopup` from inside whichever scope they're in, naturally pairing with the matching `BeginPopup` on the same scope.

  **Scope.** This iteration covers inspector primary + secondary cards only, since those are where the existing `##trknamectx` lives. Other card surfaces (SEND.col return modules, SEND.folder cards, distant cards, FlowDrawMinimalCard) are not covered — right-click there is unchanged.

  Locals budget: +1 (`nav_route_row_rclick_consumed` is a global, doesn't count; the route-row popup body uses `do ... end` block with locals scoped to that block).

- ✅ **NAV vertical spacing standardized (v20.482–v20.484).** Two related fixes around the navigator section's vertical placement:

  *Top gap.* The window's `WindowPadding(S(UI.edge_pad), S(UI.edge_pad))` is symmetric (10 logical = 16 retina on both axes), but the visible top gap above NAV.arr appeared ~2 retina smaller than the standard left-side gap. Cause: NAV.arr's `arrow_ty = ... - S(1.375)` Y nudge (used for in-row optical centering of the ▼/▶ glyphs) shifts the visible top pixel of the arrow ~2 retina higher than the row's geometric top, so the perceived gap from window-top to first-visible-pixel is shorter than `WindowPadding.y` would suggest. Fix: push cursor down `S(1.25)` (1 logical px ≈ 2 retina) inside `if nav_visible then` immediately after `nav_start_y` is captured, then re-anchor `nav_start_y` from the post-push cursor so all height accounting (`nav_total_h`, `last_nav_h`) is measured from the new origin. Doesn't touch the in-row arrow nudge math.

  *Bottom gap.* The space between NAV's bottom edge and the first card top differed between expanded and collapsed states and exceeded the standard 16-retina target in both. Pre-fix structure was `Spacing(); Spacing()` after NAV followed by `BeginChild("##content", …, WindowPadding(0, S(UI.edge_pad)))`. The two `Spacing()` calls each emit a zero-height Dummy that triggers `ItemSize` to advance the cursor by `ItemSpacing.y = S(BASE_SPACING) = 5` logical, totalling 10 logical (16 retina) extra space. But: in expanded mode, `EndChild ##nav_scroll` had already advanced the cursor by 1 implicit `ItemSpacing.y` past the child bottom, so total trailing space = 3× ItemSpacing.y = 15 logical = 24 retina; in collapsed mode the branch ended with explicit `SetCursorPos(nav_sx, nav_sy + row_h)` (no implicit ItemSpacing.y), so trailing = 2× ItemSpacing.y = 10 logical = 16 retina. Plus the inner `WindowPadding(0, S(edge_pad))` of the content child = 16 retina more. Total observed gaps ~40 retina (expanded) and ~32 retina (collapsed) — both well above the desired 16 retina, and inconsistent.

  Fix: track `nav_end_y` precisely in both branches and `SetCursorPosY(nav_end_y)` before BeginChild ##content. Expanded sets `nav_end_y = nav_start_y + nav_single_row_h + _nav_h` (header height + body child height) right before `end -- navigator_expanded`. Collapsed sets `nav_end_y = nav_sy + row_h` alongside the existing `SetCursorPos(nav_sx, nav_sy + row_h)`. The `local nav_end_y = nav_start_y` declaration sits at the same scope as `nav_start_y` so both branches and the bottom-margin block all see it. With BeginChild starting flush with NAV's bottom edge, the content child's existing `WindowPadding(0, S(UI.edge_pad))` = 10 logical = 16 retina provides the standard gap exactly, identically in both modes. The `Spacing(); Spacing()` lines are deleted; the `nav_visible == false` fallback (`+1` cursor advance) is preserved.

  Locals budget: +1 (`nav_end_y`).

- ✅ **Pin storage rewrite — GUID-keyed, per-project (v20.480).** Two bugs fixed in one rewrite: (1) pins followed same-named tracks across project tabs (default project templates with shared track names made this very visible), (2) deleting a pinned track transferred the pin to whichever neighboring track inherited a similar fallback name after the renumber. Root cause was the same on both: `pinned_folders` was keyed by `item.label` (track name string) and persisted to global `ExtState/PREF/"pinned_folders"`. Names are not stable identifiers; ExtState is not project-scoped.

  **Storage:** `pinned_folders` is now keyed by track GUID (`r.GetTrackGUID(track)`). Persistence moved to `ProjExtState/0/"reflex"/"pinned_folders"` (per-project, pipe-separated GUIDs). REAPER never reuses GUIDs after track deletion, and each project has its own GUID space — both bugs disappear.

  **API:** `LoadPinnedFolders()` (reads ProjExtState, captures `_pin_last_proj` for change detection), `SavePinnedFolders()` (writes ProjExtState), `MaybeReloadPins()` (compares `r.EnumProjects(-1)` against `_pin_last_proj`, reloads on mismatch — catches tab switches), `PinnedTrack(track)` (O(1) GUID lookup with `ValidatePtr` guard).

  **Loop integration:** `MaybeReloadPins()` runs at the top of every Loop frame, after the per-frame state resets and before any pin lookup.

  **Callsite migration:** 8 sites moved from `pinned_folders[item.label]` / `pinned_folders[entry.name]` patterns to `PinnedTrack(track)` for reads, and to `r.GetTrackGUID(track)` + map mutation for toggles. Compressed-mode right-click capture state renamed `remote_ctx_tlf_label` → `remote_ctx_tlf_guid` and now captures via `r.GetTrackGUID(item.entry.track)` at right-click time. Sites: `EnsurePinnedVisible`, `IsAlone` count, `HandleTracksClick` Opt+toggle, mini-circle pin draw, mini-circle right-click capture + menu, expanded TLT pin draw, expanded TLT right-click menu.

  **Clean break, no migration shim.** `LoadPinnedFolders()` deletes the legacy global ExtState entry on every load (idempotent — no-op after the first run). Existing label-based pins are not transferred; user re-pins. Matches the v20.450 Navigator → Reflex rename approach.

  **Orphan-pin behavior.** Deleting a pinned track leaves an orphan GUID in the in-memory set and the saved ProjExtState. `PinnedTrack()` resolves GUIDs only against currently-existing tracks (via `top_folders` iteration + `ValidatePtr` guard), so orphans have no rendering or behavioral effect. They persist in storage until the user toggles a pin (which triggers a save and rewrites the set without dead entries). Acceptable: REAPER doesn't reuse GUIDs, so orphans can never accidentally re-attach.

- ✅ **Default-color TLT circle fade unified (v20.479).** Default-color tracks (`item.color == 0`, no override) used a separate 4-state `circ_col` cascade with hardcoded greys: vis+hov `0x6A7480FF`, vis `0x58616CFF`, hov `0x58616CFF`, inactive `0x2A3038FF`. Inactive value was a near-charcoal that read as a totally different blue-grey color rather than a faded version of the active state. Colored tracks didn't have this problem because their inactive state was just `(base & 0xFFFFFF00) | alpha` — same hue, lower opacity. v20.479 collapses both branches into the same logic by substituting `0x58616CFF` as the "base" for default-color tracks: `local base_for_circ = has_color and base or 0x58616CFF`, then unified `if vis and hov then ScaleColor(base_for_circ, 1.2) else (base_for_circ & 0xFFFFFF00) | alpha`. Default-color tracks now fade with alpha like colored tracks, instead of switching to a different darker hue when inactive. Active-state colors are functionally unchanged (`ScaleColor(0x58616C, 1.2)` ≈ `0x6A7480`). Applied to both surfaces (mini circle + expanded TLT). Removed `has_color` branching block at both sites.

- ✅ **Mini-circle outer-disc full diameter (v20.478).** `mini_tlf_h = S(34) = 27` logical at 100%; `nav_dot_r = floor(27/2) = 13` produces a disc of diameter 26 — 1 logical px (~2 retina) smaller than the expanded TLT pill height (`tlf_h = S(34) = 27`). Fix: introduce `nav_dot_render_r = mini_tlf_h / 2` (float, = 13.5) used ONLY as the `AddCircleFilled` radius for the outer charcoal disc; layout math (column step, hit boxes, wrap calc) still uses integer `nav_dot_r` for stable pixel-aligned offsets. `AddCircleFilled` accepts float radius. Inner colored circle and pin overlay sizes unchanged — they were already correct. Collapsed mini-circles and fully-collapsed expanded pills are now exactly the same size.

- ✅ **NAV section visual unification (v20.452–v20.477).** Long iterative session collapsing the expanded TLT view and the collapsed mini-circle view into a single coherent visual system. Goal: toggling navigator_expanded should rotate the arrow in place with no other apparent layout change, and at narrow widths the two views should be visually indistinguishable except for arrow rotation direction.

  **Design Mode removal (v20.452).** Removed ~440 lines of dead live-token-editor code: `UI_DEFAULTS`/`C_DEFAULTS`/`design_mode_*` globals, all 23 inline `DM()` overlay calls, all 3 `DM_DrawInChild()` calls. Replaced with 5 ALL_CAPS constants at file scope: `INSP_MAX_W=295`, `STROKE_W=1.5`, `WIN_MIN_W=280`, `WIN_MAX_W=480`, `TWO_COL_MULT=1.75`. Live editing was broken; constants are simpler and code reads cleaner.

  **Filterable Add-menu popup (v20.453–v20.458; extracted v20.528).** Sends/Receives/HW Outputs `+` popups gained search-with-keyboard-nav. Shared state is module-local in `Reflex_RouteMenuCore.lua` as of v20.528; helpers `RouteFilterMatch(haystack_lower, needle_lower)` (multi-word AND substring) and `RouteAddMenuList(items, on_commit)` own search input, filter, kbd nav, scrollable list, commit-and-close. All three popup closures (`##route_add_send`, `##route_add_recv`, `##route_add_hw`) use it. Sharp 2px stroke `#383C46` via double-AddRectFilled (avoids ImGui's anti-aliased gradient). Esc closes from filter; mouse-vs-kbd mode switching via the add-menu state. Per-popup cached size is kept with that module-local state. v20.458 switched to `NoScrollbar` + `DrawScrollIndicator` to match the rest of the script. `MAX_LABEL=45` chars.

  **TLT expanded-pill collapse-to-circle (v20.467–v20.471).** When `bw` shrinks enough that the pin endcap dot would be within 12 retina px (= `S(7.5)` at 100%) of the colored circle, the entire pill snaps to a perfect circle. Threshold: `bw <= tlf_h + pin_dot_r + circ_r + S(7.5)`. Below threshold: outer dark charcoal disc + colored circle filling it concentrically + pin overlay (small `C.bg`-colored dot at center) — all three layers concentric. Above threshold: normal pill with pin endcap dot (amber) at the opposite endcap from colored circle. The `pill_w = pill_collapsed and tlf_h or bw` clamp drives all pill geometry — bg rect, circle X anchor, text anchors, arrow click region — so the collapsed form is internally consistent. Pin overlay color in collapsed state was initially `0x3E3E3FFF` (grey) but switched to `C.bg` in v20.471 for a cleaner "punched through" look matching the outer pill container.

  **Mirror Nav setting (v20.468).** New pref `nav_mirror = LoadPref("nav_mirror", false)`, declared next to `navigator_expanded`/`nav_visible` with a comment flagging "keep these grouped when splitting Navigator off into a standalone script." Settings menu checkbox "Mirror Nav (right-side dock)" placed immediately after "Show Nav." When enabled, expanded TLT pill contents flow `[circle | (arrow) | text | pin]` (left-to-right, text left-aligned) instead of the default `[pin | text | (arrow) | circle]` (right-aligned). Width math is symmetric — both branches compute `text_left_anchor`/`text_right_anchor` and use whichever side is the fixed anchor; clip drops chars from end in both modes. Sub-group arrow click hit region also flips. Compressed mini-circles and inspector layout unchanged — only expanded TLT rows.

  **Mini-circle anatomy matches collapsed pill (v20.472–v20.473).** When navigator is collapsed, mini circles now render with the SAME anatomy as a fully-collapsed expanded pill: outer dark charcoal disc (`mini_tlf_h = S(34)` diameter, was `InspCtrlSz()/2 = S(11)` radius) + inner colored circle (`Round(S(9.03))` radius matching expanded `circ_r`) + pin overlay (`Round(S(3.75))` `C.bg` dot at center, was `0x3E3E3FFF`). v20.473 also matched the fade pipeline: `alpha = (vis or hov) and 0xFF or 0x66` applies to BOTH outer disc (`(C.bg & 0xFFFFFF00) | alpha`) and inner colored circle, using the expanded TLT's exact 4-state `circ_col` cascade (has_color × vis × hov). InvisibleButton registered FIRST so hover state is known at draw time, then a single-pass draw with the right colors — no separate hover-overlay redraw. Inactive non-pinned TLT in expanded view and inactive non-hovered mini circle should now be indistinguishable except for size.

  **Arrow rotates in place across expanded/collapsed (v20.474–v20.477).** Multiple sub-fixes that together achieve "toggling expanded/collapsed only changes the arrow direction; nothing else moves":

  - *Shared geometry (v20.474).* Lifted `mini_tlf_h`, `nav_dot_r`, `nav_dot_gap`, `nav_arrow_area`, `nav_left_pad_shared`, `nav_single_row_h`, `nav_arrow_step_shared`, `nav_arrow_font_shared` up to a single declaration BEFORE the `if navigator_expanded` branch. Both states pull from the same constants. Replaced the expanded-state's `InspDrawSectionHeader` call (which sized its row from header text font height + `S(6)`, much shorter than collapsed's `single_row_h`) with a custom render: `single_row_h`-tall Selectable for click + `▼` glyph drawn at the exact same `(arrow_tx, arrow_ty)` formula the collapsed `▶` uses.

  - *Down-arrow X nudge (v20.475).* `▶` and `▼` glyphs have different bounding-box asymmetry. Right-arrow uses `-S(1.375)` (1 logical px = ~2 retina px). Down-arrow needs an additional ~2 retina px of leftward nudge to appear at the same optical center, so it uses `-S(2)` (2 logical px ≈ 3 retina px). Discrete logical-px rounding from `S()` makes this the smallest available delta at 100% scale.

  - *Body cursor force-set (v20.475).* Replaced `r.ImGui_Spacing(ctx)` before the body BeginChild with `r.ImGui_SetCursorPosY(ctx, nav_start_y + nav_single_row_h)`. The previous Spacing + auto-`ItemSpacing.y` from the header Selectable produced ~21 retina px of extra gap above the first TLT — way bigger than the gap between rows in collapsed mode. SetCursorPosY bypasses both contributors, planting the body BeginChild flush with the bottom of the arrow row.

  - *Inter-row gap parity (v20.476).* Collapsed `nav_single_row_h` was `dot_r*2 + S(6)`; expanded inter-pill gap (`ItemSpacing(0, S(3.75))`) was `S(3.75)`. The S(6) - S(3.75) = ~4 retina px difference produced visibly different vertical rhythm between the two modes. Changed `nav_single_row_h` to `dot_r*2 + S(3.75)` so collapsed inter-row pitch matches expanded inter-pill pitch exactly. Side effect: arrow row in BOTH modes is ~S(2.25) shorter; arrow stays vertically centered in whatever row height applies.

  - *Left margin parity (v20.477).* `nav_left_pad_shared` was `S(4)` to keep collapsed dots/arrow off the script edge. But expanded TLT pills use the BeginChild's content edge (no padding) as their left anchor, so collapsed had ~S(4) more left margin than expanded. Set `nav_left_pad_shared = 0`; all four positions (expanded arrow, expanded pills, collapsed arrow column, collapsed dot rows) now share the same X anchor at `nav_cx`/`nav_sx`.

  **Arrow column = one dot-step (legacy from v20.462).** The arrow's hit-box width is `nav_arrow_area = nav_dot_r * 2 + nav_dot_gap` — exactly one dot-step. This makes the wrap math clean: row 1 first dot at `nav_cx + nav_left_pad + arrow_area`, rows 2+ at `nav_cx + nav_left_pad`. Difference between row 1 col 0 and row 2 col 0 = `arrow_area` = one dot step → columns vertically align across rows. Wrap guard is `dot_x > dot_start_x_wrap` (not `mi > 1`) so first dot can wrap to row 2 if the script is too narrow for `arrow + first dot` on row 1.

  **Arrow Selectable height = single_row_h (v20.467).** When nav wraps to multiple rows, dots below the arrow share its X column. If the arrow's hit box spanned all rows (`row_h = single_row_h * num_rows`), ImGui would route those dot clicks to the arrow (earlier registration wins overlap unless `AllowOverlap` opts in). Single-row hit box keeps the arrow's click area in row 1 only.

- ✅ **Remote `BeginChild` guard (v20.451).** The Remote panel's `BeginChild("##remote", ...)` was the only one of the four content children calling `EndChild` unconditionally. ReaImGui asserts on `EndChild` when the current window isn't a child, which is what happens when `BeginChild` returns false (e.g. zero-sized region). Wrapped body + `EndChild` in `if remote_open then ... end` matching the pattern PK already documented for the other three.

- ✅ **Rename: Navigator → Reflex (v20.450).** The script was originally just the track-nav row (TLT buttons + visibility manager) and that's still the conceptual meaning of "Navigator." The wider product — inspector, FX chain, sends, flow, routing, send topology, A/B compare, view history, Remote pad — is now called **Reflex**. File renames: `Navigator.lua` → `Reflex.lua`, `Navigator_Theme.lua` → `Reflex_Theme.lua`, `Navigator_WindowToggle.lua` → `Reflex_WindowToggle.lua`, `Navigator_HistoryBack.lua` / `Navigator_HistoryForward.lua` → `Reflex_HistoryBack.lua` / `Reflex_HistoryForward.lua`. Folder renamed `Scripts/Tycho/Navigator/` → `Scripts/Tycho/Reflex/`. Code: `NAV_VERSION` → `REFLEX_VERSION`, `ImGui_CreateContext("Navigator")` → `ImGui_CreateContext("Reflex")`, window title `"Navigator"` → `"Reflex"`, all undo labels `"Navigator: …"` → `"Reflex: …"`. Persistence: ExtState namespace `"track_navigator"` → `"reflex"`; ProjExtState section `"navigator_env_alias"` → `"reflex_env_alias"`; History scripts' shared key `"navigator"` → `"reflex"`; WindowToggle's `"navigator_fxwindows"` → `"reflex_fxwindows"`. **No migration shim** — fresh-start rename, all prior prefs/aliases vacated (intentional). Internal `nav_*` globals preserved (they refer to the window/script and the variable names are invisible from outside; renaming risked transcription errors). The `NAV.*` element shorthand (NAV.pill, NAV.dot, NAV.arr, etc.) preserved — these refer to the track-nav SECTION, which remains conceptually "Navigator." User must re-bind any REAPER actions that pointed to the old paths/filenames.


- ✅ **Instruments-first redesign (v20.449).** v20.445's registration approach (`RegisterFXAddCheck` populated a `pending_instr_checks` list when `InspOpenFXBrowser` ran; `DrainPendingInstrChecks` consumed entries each Loop frame, expiring after 120 frames) was too narrow and unreliable — entries timed out before users finished browsing for a plugin, and only Reflex-initiated browser opens registered. Replaced with `MonitorTrackFxCounts`: per-frame walk of all tracks, comparing live `TrackFX_GetCount` against a `nav_track_fx_counts` cache. Any growth triggers `InspMoveNewInstruments` + `InspMarkTrackFxDirty`. Skips `insp_track` (existing Loop pre-render block handles it, including `InspMoveInsertedFX` for the inspector's insert-at-position drag). Catches all add paths uniformly: sends columns, folder cards, distant sends, flow chain, REAPER's UI, scripts. `nav_track_fx_counts` added to `SweepDeadTrackCaches`. Per-frame cost: N tracks × 1–2 `TrackFX_GetCount` calls; negligible.

- ✅ **Three small fixes (v20.445).** (1) **Gear icon centering.** Footer gear render had hardcoded `-S(1)` / `-S(2)` visual-center nudges tuned for the previous font; with v20.444's explicit `'SF Pro'` family lookup the glyph metrics shifted and the nudges produced visible miscentering. Removed both. (2) **Instruments-first across all surfaces.** Old behavior: `InspMoveNewInstruments(insp_track, ...)` only ran in Loop's insp_track pre-render block, so the "Insert Instruments First" option silently no-op'd for FX added via sends columns, folder cards, distant sends, or any other non-inspector `+` button. New: `RegisterFXAddCheck(track)` helper hooked inside `InspOpenFXBrowser` (single call site covers all `+` button paths). Captures `(track, old_count, frames=120)` into a `pending_instr_checks` list. New `DrainPendingInstrChecks` runs at top of Loop, compares live count vs stored, runs the move + `InspMarkTrackFxDirty` when the count grew. Skips entries where `track == insp_track` because the existing Loop block already handles that case (and also fires `InspMoveInsertedFX` for the inspector-only insert-at-position feature). Entries self-expire after 120 frames if no FX gets added (browser cancelled). (3) **Startup focus.** First Loop frame now calls `JS_Window_SetFocus(GetMainHwnd())` so arrow keys reach REAPER's transport/nav without first clicking either window. Guarded by `nav_started` flag (one-shot). Falls back silently when `JS_Window_SetFocus` isn't available.

- ✅ **SF Pro font loading (v20.444).** Font init block now reads `family` from `Reflex_Theme.lua` `fonts.family` (default `"SF Pro"`) and passes it to `ImGui_CreateFont` instead of the generic `'sans-serif'`. ReaImGui falls back to system sans-serif if the named family isn't installed, so this is safe on systems without SF Pro. Override by setting `fonts.family = "Inter"`, `"Helvetica Neue"`, `"sans-serif"`, etc. Bold/italic/regular all use the same family; weight comes from `FontFlags_Bold`/`FontFlags_Italic` against the OS face stack.

- ✅ **Sends-in-flow-view removal (v20.439).** When in flow view + single-column mode (window too narrow for sends column on the right), inline sends rendering produced inconsistent placement: at the top when only the focus track was visible, between focus-and-its-parent when multiple chain entries were visible, etc. Removed inline sends entirely from the flow view single-column path. Sends now appear only via the right-side sends column when the window is wide enough; widen the window to see them. Non-flow single-column path unchanged (sends still render below the inspector card). `opt_sends_first` setting + variable removed entirely (became dead after the inline removals). See "v20.439" entry in the now-removed render paths in `if flow_view_active` branch.
- ✅ **Locate & Peek system (v20.440–v20.442).** Universal "track name = locate-link to that track in REAPER" gesture across HDR.name (primary + secondary + flow expanded), SEND.col title, SEND.folder title, distant collapsed/expanded title, FlowDrawMinimalCard title. Plain click is additive (locate + fall-through expand/browse); ⌥+click is strict light-touch peek (REAPER mutation only, no Reflex state change). Cursor-change-to-hand + on-hover underline + descriptive tooltip. See "Locate & Peek" section. Companion changes: inspect arrows removed from all sends-view surfaces; SND chevron moved to right endcap with new "Open sending track controls" tooltip; distant card SND-click-to-collapse race fix; `JS_Window_GetClientSize` width-vs-height bug fixed in `ScrollTrackToCenter`.
- ✅ **Top-level conforming Returns folder display (v20.443).** When source track is top-level (no parents) and conforming sends create a Returns folder, `SendsViewBuildGroups`'s grouping branch required `#path >= 3` and excluded the `path == 2` case that occurs when there's no parent intersection. Folder card never displayed even though topology was correct. Fix: added parallel branch for `depth == 1 and #path == 2` that groups by `path[2]` (the conforming folder). See "Send Topology Classifications" subsection.

### Deferred / unactionable

- **Stage B — Distant sends → folder cards.** Considered and deferred. Original rationale was that the lightweight distant-card strip was visually lighter than `DrawSendFolderCard` while carrying secondary-folder context, an "inverted hierarchy." On review the argument doesn't survive scrutiny: distant section already has its own `C.bg_label` heading making the context explicit, the lighter weight is space-efficient and arguably correct for tertiary content, and any literal-swap plan loses SND controls (functional regression) while structural-regroup plans are sizable refactors for aesthetic-only gain. Revisit only if a concrete user-experienced pain point surfaces (e.g. distant section being missed in dense sessions). Promotion of `DrawCompactTrackColumn` distant branch + `sends_distant_rendering` / `sends_distant_collapse_request` flags stay as-is — all functioning correctly.
- **Stage F (insp_fx_rects localization)** — final cleanup item from the per-track refactor; localize file-scope `insp_fx_rects` to `InspDrawFXArea` and migrate the `fx_browser_drag` handler to the `fx_drop_targets` registry. Optional — record-data integrity already correct; this is naming/scoping tidiness only.
- **Whole FX chain as a clip surface**: FX button selectable/draggable/clipable; paste replaces entire chain with fade animation. Deferred (per S. Hansen).
- **Windows platform support** — standalone `Navigator.lua` release work is now tracked in the "Navigator release roadmap: Windows + keyboard passthrough" immediate-QA item above. Broader Reflex Windows support still needs a later script-wide audit of modifier bits, DPI, path separators, font widths, and docker padding.
