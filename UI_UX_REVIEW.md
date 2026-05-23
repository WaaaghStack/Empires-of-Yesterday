# UI/UX Review — Multi-Squad Expansion

*Empires of Yesterday · Godot 4.6 · May 23, 2026*

This document records interaction fixes after the 12-marine / 3-squad expansion and lists follow-up UX improvements.

---

## What Was Broken

| Screen | Issue | Root cause |
|--------|-------|------------|
| **SquadSelection** | Bottom marine cards clipped; unlock/start buttons unreachable | 12 cards (260×320) in a fixed panel with no scroll; decorative `ColorRect` could steal clicks |
| **BetweenMissionHub** | Heal, augments, intel, recruit, modifier panels overflowed panel | All hub sections stacked in a fixed-height `VBoxContainer` without outer scroll |
| **TacticalMap — comms** | Log grew past panel; mouse wheel did nothing | `CommsScroll` did not expand; `RichTextLabel` internal scroll disabled but parent scroll not configured |
| **TacticalMap — roster** | 3 squad headers + summaries clipped | Roster `ScrollContainer` had no minimum height or scroll config |
| **TacticalMap — HUD** | Order / ability / mission buttons cut off or unclickable | Tall HUD content in fixed panel; `PlayArea` control blocked pointer events over map margins |
| **TacticalMap — deploy** | Map clicks sometimes ignored or hit wrong layer | Full-screen `PlayArea` used default `MOUSE_FILTER_STOP`; only `SubViewportContainer` should capture map input |
| **Codex** | Long lore + portrait grid overflowed | No scroll wrapper around body + portraits |
| **MissionDebrief / RunSummary** | Stats text could clip on small windows | Rich text not in `ScrollContainer` |
| **All menus** | Background `ColorRect` blocked edge buttons | Default mouse filter on full-screen backgrounds |
| **ControlsOverlay** | When open, clicks passed through to map | Script forced `MOUSE_FILTER_IGNORE` even when visible |

---

## Fixes Applied

### Shared (`GameTheme.gd`)
- `ignore_mouse()` — set decorative overlays to `MOUSE_FILTER_IGNORE`
- `configure_scroll()` — vertical auto-scroll, disabled horizontal, `follow_focus`
- `scroll_to_bottom()` — auto-tail comms log after new lines

### Per screen
- **SquadSelection** — `SoldierScroll` wraps 4-column marine grid; background ignores mouse
- **BetweenMissionHub** — `HubScroll` wraps all hub options; squad list keeps nested scroll; Launch/Abort pinned below scroll
- **TacticalMap** — `PlayArea` ignores mouse; comms + roster + HUD each scroll; dedicated **Objective [O]** button; comms auto-scroll; overlay blocks clicks when visible
- **MainMenu, Codex, MissionDebrief, RunSummary** — background ignore + content scroll where needed
- **ControlsOverlay** — `MOUSE_FILTER_STOP` when visible, `IGNORE` when hidden

---

## Quick UX Wins Implemented

- [x] Dedicated **Objective [O]** button in order panel
- [x] Comms log scroll (mouse wheel + visible scrollbar when overflowing)
- [x] Squad roster scroll for 3 squad headers
- [x] Hub scroll for all between-op options
- [x] Visible scrollbars on overflowing panels (`SCROLL_MODE_AUTO`)
- [x] **Deploy zone banner** — live Alpha / Bravo / Charlie assignment status before BEGIN MISSION
- [x] **Squad camera follow** — HUD buttons + F1–F3; active follow highlighted; clears on edge pan
- [x] **Zoom indicator** — bottom-right play area shows zoom %; mouse wheel over map zooms with clamped bounds

---

## Commander camera & deploy UX

*Added May 23, 2026 — post camera/deploy pass*

### Implemented this pass
1. **Deploy zone banner** — Play-area banner tracks which squads are assigned and which room is pending
2. **Follow squad buttons** — Alpha / Bravo / Charlie toggle with pressed-state highlight; F1–F3 mirrors selection + follow
3. **Zoom readout** — `Zoom N%` overlay on tactical map; wheel zoom respects min/max and hull bounds

### Remaining suggestions (prioritized)

#### P1 — High impact
1. **Squad card expand/collapse** — Roster shows squad headers only; expand to reveal 4 operator rows per squad
2. **Operator hotkeys 5–12** — Direct operator focus beyond 1–4 in multi-squad roster
3. **Comms filter tabs styling** — Toggle group with active accent; filtered count badge
4. **Camera follow on deploy** — After BEGIN MISSION, auto-follow Alpha until player pans

#### P2 — Medium impact
5. **Minimap click-to-jump** — Click minimap sector to pan camera (draw-only today)
6. **Minimap legend** — Squad colors, hive rooms, threat pings
7. **Hub section headers** — Collapsible Heal / Augments / Intel panels
8. **Deploy room preview** — Ghost formation dots in selected room before confirm
9. **Scroll hints** — Fade gradient when panel content is clipped

#### P3 — Polish
10. **Sticky action bars** — Pin BEGIN MISSION / Launch outside scroll on long forms
11. **Touch / trackpad** — Larger hit targets on follow buttons and comms filters
12. **Objective HUD chip** — Click mission banner to pan to next incomplete objective room
13. **Keyboard focus order** — Tab through roster, follow row, order panel
14. **Middle-drag pan** — Optional drag-to-pan on map (edge pan only today)

---

## Remaining UX Suggestions (Prioritized)

### P1 — High impact
1. **Squad card expand/collapse** — Roster shows squad headers only; expand to reveal 4 `OperatorRosterCard` rows per squad (design in `MULTI_SQUAD_DESIGN.md`)
2. **Operator hotkeys 5–12** — Extend selection keys beyond 1–4 for direct operator focus in multi-squad roster
3. **Deploy flow clarity** — Banner showing “Assign Alpha → Bravo → Charlie deploy zones” with room name per squad before BEGIN MISSION
4. **Comms filter tabs styling** — Toggle group with active accent; show filtered count badge

### P2 — Medium impact
5. **Minimap click-to-jump** — Click minimap sector to pan camera (currently draw-only, `MOUSE_FILTER_IGNORE`)
6. **Minimap legend** — Tiny key for squad colors, hive rooms, threat pings
7. **Hub section headers** — Collapsible panels (Heal / Augments / Intel / Recruit / Modifiers) to reduce scroll on repeat visits
8. **SquadSelection squad grouping** — Visual dividers or tabs for Alpha / Bravo / Charlie instead of flat 12-card grid
9. **Scroll hints** — Fade gradient at bottom of scroll areas when content is clipped (first-run tooltip)

### P3 — Polish
10. **Sticky action bars** — Pin Deploy / Launch / BEGIN MISSION outside scroll on all long forms
11. **Touch / trackpad** — Larger hit targets on comms filter chips and squad header buttons
12. **Objective HUD chip** — Compact primary objective + progress in mission banner with click-to-focus relevant room
13. **Keyboard focus order** — Tab order through roster cards and order panel for accessibility
14. **Responsive layout** — Anchor panels to viewport edges on ultrawide instead of fixed pixel offsets

---

## QA

Run headless validation:

```bash
godot --headless --path . --scene res://qa_runner.tscn
```

Expected: exit code **0**, `qa_report.txt` ends with `RESULT: PASS`.

---

## Related Docs

- [`MULTI_SQUAD_DESIGN.md`](MULTI_SQUAD_DESIGN.md) — multi-squad architecture and roster UI plan
- [`PHASE1_DECISIONS.md`](PHASE1_DECISIONS.md) — baseline UI decisions
