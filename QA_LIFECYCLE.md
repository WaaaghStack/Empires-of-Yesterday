# QA Lifecycle — Empires of Yesterday

Headless smoke tests catch load/parse errors, broken resource refs, and core run-loop invariants before they reach playtest or release. Use this document as the single reference for **when** to run QA, **how** to run it, and **what to do when it fails**.

---

## When to run QA

| Trigger | Action |
|---------|--------|
| **Before every commit** (recommended) | Run headless `qa_runner.tscn`; fix failures before pushing. |
| **After completing a feature phase** (A–F or equivalent) | Run QA + manual playtest checklist below; add new smoke checks to `qa_runner.gd` if the phase introduces invariants. |
| **After territory perf program phases** | Headless QA; standard 96×72 fixture gate **`resolve_ms < 3000`** (was 12 s). Golden active-set + tape regression in `qa_runner.gd`. |
| **Before a release / demo build** | Full headless QA + complete manual run loop (4 ops, hub between each). |
| **After merging large refactors** | QA + spot-check scene transitions and autoload singletons. |
| **When upgrading Godot** | QA first; watch for typing (`Array[T]`), `class_name`, and preload changes. |

---

## Commands

### Headless QA (primary)

**Windows (Steam Godot 4.6):**

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" `
  --headless --path "c:\Users\Komba\OneDrive\Documents\GitHub\Empires-of-Yesterday" `
  res://qa_runner.tscn
```

**Generic (Godot on PATH):**

```bash
godot --headless --path . res://qa_runner.tscn
```

**Exit codes:** `0` = PASS, `1` = FAIL. Report written to `qa_report.txt`.

**Alternate entry point:** `qa_validate.gd` is an older SceneTree-based validator with a smaller script/scene list. Prefer `qa_runner.tscn` — it includes Phase A–F smoke tests and full scene coverage.

### Optional manual checks (no Godot required)

```powershell
# Verify all res:// paths referenced in .gd/.tscn files exist on disk
Select-String -Path *.gd,*.tscn -Pattern 'path="res://[^"]+"' |
  ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
```

Confirm autoloads in `project.godot` match singleton scripts that must exist at boot:

- `RunLog` → `RunLog.gd`
- `SaveManager` → `SaveManager.gd`
- `RunState` → `RunState.gd`
- `PortraitPool` → `PortraitPool.gd`

---

## Session log files

Each game launch writes session logs to the **project workspace** under **`logs/`** (resolved at runtime via `ProjectSettings.globalize_path("res://").path_join("logs")`):

| File | Purpose |
|------|---------|
| `logs/latest_run.txt` | Always overwritten — current / most recent session (primary path for agents / IDE) |
| `logs/run_YYYY-MM-DD_HH-mm-ss.txt` | Timestamped archive copy for the same session |

**Example path** (this repo on Windows):

`c:\Users\Komba\OneDrive\Documents\GitHub\Empires-of-Yesterday\logs\latest_run.txt`

The `logs/` directory is gitignored. On startup the game prints `Session log: <absolute workspace path>` to the Godot console and to tactical comms when the map loads. The `RunLog` autoload captures comms (`TacticalMap.log_message`), explicit `RunLog.info/warn/error` calls, lifecycle events, and Godot engine `print` / `push_error` / `push_warning` output via a custom `Logger`.

---

## What `qa_runner` validates

### Script load (33 scripts)

All core gameplay scripts load without parse errors, including hub/run systems: `BetweenMissionHub`, `RunState`, `RunLog`, `SaveManager`, `OpModifier`, `MapVisuals`, `ProceduralMapGenerator`, `TacticalMap`, etc.

### Scene load + instantiate (14 scenes)

Including full run loop scenes: `MainMenu`, `SquadSelection`, `TacticalMap`, `MissionDebrief`, `BetweenMissionHub`, `RunSummary`, `Codex`, plus unit/room prefabs.

### Soldier resources (4 `.tres`)

Marine roster templates load as `SoldierResource`.

### OrderType enum

`OrderType.Type.EXPLORE == 6` (order hotkey contract).

### Portrait pool

`PortraitPool.get_portrait_count()` and random assignment (warns if zero PNGs; uses class-color fallback).

### Map generation

- Seed `12345`, op 2, `scavenge` template → non-empty room list, correct `op_index`.
- Cross-room pathfinding: corridor rects populated, `find_path` between rooms, corridor midpoints walkable.

### RunState flow

`start_run` / seed override / `next_op_seed` / `advance_after_success` / class unlock / `end_run`.

### Phase A–F smoke tests

| Check | Expectation |
|-------|-------------|
| Objective templates | 6 templates: `standard`, `silent_extract`, `scavenge`, `hold_purge`, `black_site`, `vip_recovery` |
| `hold_purge` map | Generated map has non-empty `hold_room_id` |
| `RunAugment.gd` | Script loads (4 augments: overwatch, docs, field intel, spare parts) |
| Facility themes | Generated map `facility_theme` ∈ `MapVisuals.FACILITY_THEMES` (`industrial`, `bio`, `command`) |
| Op 4 finale | Handcrafted layout, ≥ 5 rooms |
| Daily share code | `SaveManager.get_daily_share_code()` format `EOY-YYYY-MM-DD-<seed>` |

### Not yet in headless QA (manual playtest)

- `IntelTerminal.tscn` / `VipEscort.tscn` instantiate during black-site / VIP missions
- `OpModifier.all_modifiers()` count (currently 12)
- Ghost-path rendering, contact-report UI, class abilities in combat
- Hub intel shop purchases and recruit draft UI

Add these to `qa_runner.gd` when stabilizing the next phase.

---

## Manual playtest checklist

Use after headless PASS when changing gameplay, UI, or scene flow.

### Full run loop (≈30–45 min)

- [ ] **Main Menu** — New Run, Continue (mid-run), Daily Seed Run, Codex all navigate without errors
- [ ] **Daily seed** — Share code displays (`EOY-…`); same calendar day → same seed
- [ ] **Squad select** — Up to 4 marines; deploy disabled until ≥1 selected; class unlock tokens work
- [ ] **Tactical map deploy** — Click secure room (green), BEGIN MISSION
- [ ] **Orders** — Move (M), Clear (C), Defend (D), Extract (E), SND (S), Explore (X); right-click targets
- [ ] **Pause / unpause** — Space toggles; abilities (R) respect cooldown
- [ ] **Fog & LOS** — Hidden rooms/enemies until revealed; doors block sight
- [ ] **Mission win** — Clear objectives, extract at Command Bridge
- [ ] **Debrief** — Stats, seed, credits shown
- [ ] **Between-op hub** — Heal squad; pick op modifier (3 choices); run augment (first hub visit); intel shop; KIA recruit if applicable
- [ ] **Repeat for ops 2–3** — Difficulty scaling, varied objective templates
- [ ] **Op 4 finale** — Handcrafted map loads; run completes
- [ ] **Run summary** — Credits, ops cleared, daily best update; return to menu or new run

### Phase A–F regression areas

| Area | What to verify |
|------|----------------|
| **Objectives (6 templates)** | Each template generates valid map + win condition (standard purge, silent extract, scavenge caches, hold & purge timer, black-site terminals, VIP escort) |
| **Ghost paths** | Order path preview renders; clears when order completes or is cancelled |
| **Contact reports** | Last-contact marker on rooms after hostile sighting; label updates |
| **Class abilities** | Assault / Support / Marksman / Breacher abilities fire and respect `OpModifier` cooldown tweaks |
| **Hub systems** | Heal efficiency (Doc's Kit augment), intel costs (Field Intel), modifier synergies per objective |
| **Map themes** | Room colors match `industrial` / `bio` / `command` theme for the op |
| **Finale map** | Op 4 uses handcrafted layout, not pure procedural |

---

## How to extend `qa_runner`

1. **New script** — Add path to `SCRIPT_PATHS` in `qa_runner.gd`.
2. **New scene** — Add to `SCENE_PATHS`; runner loads and instantiates each entry.
3. **New invariant** — Add a function (e.g. `_validate_my_feature()`) and call it from `_ready()`.
4. **Use `_fail()` / `_log()`** — Failures append to `_failures` and set exit code 1.
5. **Autoload-dependent checks** — Safe in `qa_runner.tscn` (autoloads are available). For `qa_validate.gd` (SceneTree root), autoloads may not be present — prefer `qa_runner.tscn`.
6. **Re-run until PASS** — Commit the new check only when green locally.

Example — validate a new scene:

```gdscript
func _validate_intel_terminal() -> void:
    var packed: PackedScene = load("res://IntelTerminal.tscn")
    if packed == null or packed.instantiate() == null:
        _fail("IntelTerminal scene failed to load/instantiate")
    else:
        _log("OK  IntelTerminal.tscn")
```

---

## Failure triage

1. **Read console output and `qa_report.txt`** — First `FAIL:` line is usually the root cause.
2. **Script load failure** — Open the `.gd` in Godot editor or check for syntax/typing errors (Godot 4.6 strict arrays).
3. **Scene load failure** — Missing `ext_resource` path, broken UID, or script error on attached node.
4. **Resource failure** — Missing `.tres` or wrong export type on resource script.
5. **Map / pathfinding failure** — Inspect `ProceduralMapGenerator.gd`, `DynamicPathGraph.gd`, objective template branch.
6. **RunState / SaveManager failure** — Autoload conflict, duplicate function, or changed API without updating QA expectations.
7. **Phase smoke failure** — Compare constant arrays (`OBJECTIVE_TEMPLATES`, `FACILITY_THEMES`) and generator options against test seed.
8. **Fix with minimal diff** — Restore the invariant; avoid unrelated refactors.
9. **Re-run headless QA** — Repeat until exit code 0.
10. **Document blockers** — If a failure requires design input or missing assets, note in PR/commit message and skip gating only with team agreement.

### Common Godot 4.6 issues

- Untyped `Array` vs `Array[T]` mismatch
- `class_name` conflicts or missing global class registration
- `preload()` paths to renamed/moved files
- Duplicate `func` names in the same script
- Scene refs using old filenames after renames

---

## Quick reference

| Item | Location |
|------|----------|
| QA runner scene | `qa_runner.tscn` + `qa_runner.gd` |
| Legacy validator | `qa_validate.gd` (SceneTree, narrower scope) |
| QA report output | `qa_report.txt` |
| Session log (latest) | `logs/latest_run.txt` (workspace; absolute path printed at startup) |
| Autoload config | `project.godot` → `[autoload]` |
| Design decisions | `EMPIRE_VISION.md` |
