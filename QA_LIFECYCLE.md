# QA Lifecycle — Empires of Yesterday (World Conquest)

Headless smoke tests catch parse errors, broken scene refs, sim regressions, and backend divergence before playtest.

---

## When to run QA

| Trigger | Action |
|---------|--------|
| Before every commit | `qa_runner.tscn` headless; fix failures before pushing. |
| After any propagation / flow change | QA **plus** `bridge_invasion_smoke_test.gd` — the Rust parity gate must pass. Rebuild the Rust DLL if `rust/empire_territory/src/` changed (see RUST.md). |
| After placement / routing changes | `bridge_invasion_smoke_test.gd` + `island_outpost_smoke_test.gd` + an in-game placement check. |
| When upgrading Godot | QA first; watch for typed-array and `class_name` changes. |

---

## Commands

**Windows (Steam Godot 4.6):**

```powershell
$GODOT = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

# Primary QA (exit 0 = PASS; report in qa_report.txt)
& $GODOT --headless --path . res://qa_runner.tscn

# Bridge / outpost routing smoke (writes bridge_invasion_smoke_result.txt)
& $GODOT --headless --path . -s res://bridge_invasion_smoke_test.gd

# Island outpost smoke
& $GODOT --headless --path . -s res://island_outpost_smoke_test.gd
```

---

## What `qa_runner` validates

1. **Script loads** — every core `.gd` parses (the list in `SCRIPT_PATHS` must stay in sync with the repo).
2. **Scene loads** — `MainMenu.tscn`, `WorldConquestScreen.tscn`.
3. **RunLog autoload** — session log path exists and is writable.
4. **World Conquest smoke** — 360×180 Earth map generates with HQs, ≥ 8000 claimable land tiles, globe + fluid meshes build.
5. **Gradient downhill flow** — pressure flows to lower effective height on a real map.
6. **Mountain headroom (synthetic 8×8 map)** — shallow pressure (50) cannot climb a 100-elevation peak; deep pressure (160) pours over. Deterministic — never skips.
7. **Rust vs CPU parity** — 16 rounds on the world map, per-tile owner arrays must match exactly. **Runs by default** when the GDExtension is loaded; logs a WARN if the DLL is missing. Skip explicitly with `BATTLE_RUST_COMPARE=0`.

### Optional env-gated checks

| Env | Check |
|-----|-------|
| `BATTLE_WORLD_CONQUEST_BENCH=1` | 60 sim-sec live bench; fails above 8 ms/step. |
| `BATTLE_RUST_BAKE_COMPARE=1` | Rust vs GDScript fluid RGBA bake (capped at 64 rounds). |
| `BATTLE_RUST_ACTIVE_COMPARE=1` | Rust active-set vs full-grid owner drift (≤ 8 tiles). |

---

## Session logs

Every launch writes `logs/latest_run.txt` (overwritten) and a timestamped archive in `logs/`. `RunLog.info/warn/error` plus engine print/push_* output are captured. Outpost placement that falls back to a standalone (routeless) build logs a `WARN` line — check for it when verifying placement changes.

---

## Failure triage

1. Read the first `FAIL` line in console / `qa_report.txt`.
2. **Script load failure** — parse error; open the file, check strict typing.
3. **Rust parity failure** — propagation changed in one implementation only. Diff `BattleTileControl.gd` flow code against `rust/empire_territory/src/sim.rs`, rebuild the DLL (`setup_rust.ps1`), rerun.
4. **Smoke routing failure** — inspect `WorldConquestOutpostBuild.gd` routing tiers (mainland BFS → infrastructure BFS → bridge-landing land route → greedy bridge → A*).
5. Fix with a minimal diff and rerun until exit code 0.

## Extending `qa_runner`

Add new scripts/scenes to `SCRIPT_PATHS` / `SCENE_PATHS`; add invariants as `_validate_*()` functions called from `_run_all()`; use `_fail()` / `_log()`. Prefer synthetic fixtures (see `_build_synthetic_mountain_map`) over seed-hunting on real maps — tests that can SKIP are tests you don't have.
