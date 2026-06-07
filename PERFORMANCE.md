# Performance tuning — Empires of Yesterday

## Territory conquest resolve

Canonical design: [DESIGN.md](DESIGN.md) §4.1.

| Phase | Focus | Key files |
|-------|--------|-----------|
| 0 | Phase timers (`inject`, `gradient`, `cancel`, `sync`, `conquest`, `record_frame`); `BATTLE_PERF_LOG=1` | `BattlePerfProfiler.gd`, `BattleTerritorySim.gd`, `qa_runner.gd` |
| 1 | `record_stride=4`, raw owners on tape, soften on playback, incremental tile counts, pressure keyframes | `BattlePacing.gd`, `BattleTerritorySim.gd`, `BattleTerritoryTape.gd`, `BattleViewer.gd` |
| 2 | Ping-pong gradient, fixed 4-neighbor scratch, `claimable_mask`, incremental conquest counts, adaptive 2nd spread | `BattleTileControl.gd` |
| 3 | Frontier `active_indices` sim (golden vs full grid in QA) | `BattleTileControl.gd`, `qa_runner.gd` |
| 4 | Delta tape frames, `BattleReplayPack` v2, log pressure codec v2 (v1 load compat) | `BattleReplayPack.gd`, `BattleTilePressureCodec.gd` |
| 5 | `end_reason`, dominance/stall early end, queue vs viewer round caps | `BattleTerritorySim.gd`, `BattlePacing.gd` |
| 6 | `FLUID_ALPHA_PRESSURE_MAX=100_000`, strided replay lerp, skip re-resolve when SQL tape loaded | `BattleTileFluidField.gd`, `BattleViewer.gd` |
| 7 | `resolve_ms < 3000` on 96×72 fixture; golden tape regression | `qa_runner.gd`, `QA_LIFECYCLE.md` |
| 9 | **Option D:** pre-bake display frames after sim; playback = texture swap; wall-clock timer | `BattleTerritoryReplayBake.gd`, `BattleTerritoryTape.gd`, `BattleViewer.gd` |
| 10 | **GPU live territory** — compute spread on GPU; display shader samples sim textures; CPU tape/resolve unchanged | `BattleTerritoryGpuField.gd`, `shaders/territory/*.glsl`, `BattleTerritorySim.gd`, `BattleViewer.gd`, `WorldRTSScreen.gd` |

**Knobs:** `BattlePacing.RESOLVE_TAPE_RECORD_STRIDE` (default 4), `RESOLVE_MAX_ROUNDS_CAP` (960 queue), `VIEWER_MAX_ROUNDS_CAP` (3200), `BATTLE_PERF_LOG=1`, `BATTLE_REPLAY_LOG=1`, `TERRITORY_MAX_SEGMENT_SECONDS` (1.25), `OVERLAY_MAX_UPDATES_PER_SEC` (12 in viewer), `BATTLE_TERRITORY_BACKEND` (`gpu` default for live, `cpu` for legacy live), `BATTLE_GPU_COMPARE=1` (optional CPU vs GPU parity in qa_runner).

**GPU live targets (Phase 10):** 96×72 Engage sim+display &lt; **2 ms** combined on mid hardware; 192×144 RTS World sim dispatch &lt; **4 ms** per frame budget. **Non-goals:** GPU tape encode, GPU headless resolve, multiplayer sync.

### RTS World live play (CPU path)

| Change | File | Effect |
|--------|------|--------|
| Terrain baked to one `ImageTexture` | `WorldRTSTerrainBake.gd`, `WorldRTSScreen.gd` | Removes thousands of `ColorRect` nodes |
| Active-set rebuild every 3 rounds (or on frontier change) | `BattleTileControl.gd` | Avoids full-grid scan each sim round |
| Cancel pressure on active tiles only | `BattleTileControl.gd` | Cheaper overlap pass as front grows |
| Overlay: cached land mask + byte buffers | `BattleTileOwnershipOverlay.gd` | Faster `apply_live_state` |
| Adaptive sim rounds when frontier &gt; 4500 tiles | `WorldRTSConfig.gd`, `WorldRTSScreen.gd` | Late-battle frame time cap |
| Lower default sim/overlay rates for world | `WorldRTSConfig.gd` | 10 r/s, 8 max/frame, 5 Hz overlay |

Env: `BATTLE_TERRITORY_BACKEND=gpu` to try GPU sim on world (experimental).

**Replay vs resolve:** `resolve_ms` is headless sim + tape build; `total_duration()` is spectator watch time at 1× (normalized). Wall-clock lag was caused by full fluid rebuild every frame — replay clock now advances every tick, overlay throttled.

---

This document summarizes runtime optimizations for tactical maps (**campaign sectors: 8–18 rooms each; legacy planet: 12–16 rooms in one hull**) with 12+ units, and the knobs you can adjust.

**Campaign mode** loads a fresh smaller map per navigation node (lower peak room/enemy count per session than one full planet run, but multiple missions per run).

## Root causes addressed (pass 1)

1. **Hive meta error flood** — `get_meta("hive", null)` still errors in Godot 4.6 when the key is missing (null default). `_hive_in_room()` ran every frame per soldier and spammed 121+ console errors, tanking FPS and risking instability.
2. **O(n²) scene scans** — Soldiers and enemies called `get_tree().get_nodes_in_group()` every frame for rooms, doors, enemies, soldiers, and hives.
3. **Fog / LOS every frame** — `_update_fog_of_war()` iterated all soldiers × all frontier rooms × all enemies for line-of-sight checks at 60 Hz.
4. **Uncached pathfinding** — Corridor path rebuilds were uncapped; door toggles did not invalidate the path cache.
5. **HUD / minimap / comms at 60 Hz** — Roster, minimap redraw, and comms RichText rebuild ran every frame.

## Root causes addressed (pass 3 — multi-squad scale)

1. **Soldier×room fog nesting** — Fog pass refactored to room-first iteration via `MissionEntityIndex.fog_reveal_rooms()` with one living-soldier list per tick and a single `rebuild_frontier()` after batched reveals.
2. **Dead unit process leak** — KIA soldiers set `PROCESS_MODE_DISABLED`, unregister from `MissionEntityIndex` immediately, and are removed from `active_units` so `_process` never runs again.
3. **Per-soldier combat rescans** — `CombatCoordinator` assigns targets at 10 Hz using room-scoped enemy/hive lists from the entity index; soldiers consume assigned targets instead of independent 0.15 s full scans.
4. **Uncapped pathfind under load** — `DynamicPathGraph` max A* finds per frame scales with living soldier count (4 → 3 → 2).

## Optimizations applied (pass 3)

| Area | Change | Expected impact |
|------|--------|-----------------|
| Fog pass | Room-first single sweep via `MissionEntityIndex`; one soldier list per tick | Less redundant fog bookkeeping at 12+ units |
| Dead units | `PROCESS_MODE_DISABLED` + immediate index unregister | Zero `_process` cost for KIA operators |
| Combat coordinator | 10 Hz shared target assignment, room-scoped caches | ~6× less combat target scanning vs per-unit 0.15 s |
| Pathfind cap | Dynamic budget: ≥8 alive → 2/frame, ≥4 → 3/frame, else 4/frame | Smoother frames during large squad movement |

## Root causes addressed (pass 4 — idle work at scale)

1. **Door `_process` on every bulkhead** — ~58 doors ran each frame and each idle-close check scanned all soldiers via `get_nodes_in_group`. Doors now sleep when closed; proximity uses `TacticalMap.get_living_soldiers_cached()`.
2. **Combat LOS on every enemy** — S&D nearest-target picked from the full living enemy list (~12 soldiers × N enemies × LOS at 10 Hz). Now room-first + 520 px radius candidates from `MissionEntityIndex`.
3. **Fog enemy visibility on all enemies** — Every fog tick iterated `active_enemies`. Now `get_enemies_for_fog_check()` (revealed rooms + near soldiers + already-spotted).
4. **Room label redraw storm** — `_refresh_status()` called `queue_redraw()` even when status text unchanged. Redraw only when text changes.
5. **Per-soldier squad mark tick** — `MissionStateLib.tick_squad_mark()` ran 12×/frame; moved to one call on `TacticalMap`.
6. **Squad separation O(n²)** — Near-camera soldiers scanned all soldiers in the tree; now `get_squad_mates()` at 20 Hz.
7. **Dormant hive `_process`** — Each dormant hive polled activation every frame; batched on `TacticalMap` at 0.2 s with hives sleeping until active or focus-marked.
8. **LOS room lookup** — `_room_containing()` repeated for every LOS call; grid-key cache per fog/combat frame via `LineOfSight.begin_frame_cache()`.

## Optimizations applied (pass 4)

| Area | Change | Expected impact |
|------|--------|-----------------|
| Doors | `set_process(false)` when closed; cached soldier list for proximity | ~58× fewer door ticks + no group scans |
| Combat coordinator | Room + radius enemy candidates before LOS | ~10× fewer LOS calls in S&D |
| Fog enemies | Subset via `get_enemies_for_fog_check()` | Scales with contact, not map enemy count |
| Room labels | `queue_redraw()` only on status text change | Less canvas text work |
| Squad mark | Single `tick_squad_mark` on map | 12× → 1× per frame |
| Separation | Squad mates cache + 20 Hz throttle | O(squad) not O(all soldiers) |
| Dormant hives | Map-batched activation; hive sleeps | ~N_hives fewer idle `_process` |
| LineOfSight | Per-frame room-at-point cache | Faster repeated LOS in one tick |

## Root causes addressed (pass 2 — 1 FPS fix)

1. **Fog frontier rebuild in inner loop** — `entity_index.rebuild_frontier()` ran inside every soldier×room fog iteration (~12×35×20/sec), an O(n³) catastrophe. Now runs **once** after a fog pass when any room was newly revealed.
2. **Per-fog-pass room intel refresh** — `room.refresh_intel()` on all rooms every fog tick forced `_refresh_status()` + `queue_redraw()` across the whole map. Removed; rooms update on state-change signals only.
3. **12× global enemy count scans** — Each soldier in S&D mode called `living_enemy_count()` (full tree scan) every frame via `_update_snd_label()`. Now cached on `MissionEntityIndex` and labels throttled to 10 Hz.
4. **Hive activation scan** — Each dormant hive called `get_nodes_in_group("rooms")` every frame. Now throttled to 0.2 s and uses cached `TacticalMap.rooms`.
5. **Swarm adapt log spam** — Deploy triggered `on_disturbance()` per soldier (12 comms lines + RichText rebuilds). Log debounced to once per 12 s.
6. **Ghost path preview on planet** — Paused multi-select issued up to 12 A* path previews per mouse move. Planet maps: ghost paths only with **one** selected unit.
7. **Off-screen unit/process load** — All soldiers, enemies, and hives ran full `_process`/`_physics_process` at 60 Hz. Distant units sleep; visible enemies stay active.

## Optimizations applied

| Area | Change | Expected impact |
|------|--------|-----------------|
| Fog frontier | Single `rebuild_frontier()` after pass, not per soldier×room | **Primary 1 FPS fix** — ~100× less fog bookkeeping |
| Fog timing | 0.5 s timer + dirty flag (room enter, door toggle) | ~2 Hz fog instead of ~20 Hz |
| Fog enemy LOS | Skip enemies farther than 480 px from any soldier | Fewer LOS checks on large maps |
| Room intel | No per-fog `refresh_intel()` sweep | Eliminates mass `queue_redraw()` |
| Entity index | Cached `living_enemy_count` on register/unregister | O(1) S&D label counts |
| Hive lookup | `Room.get_attached_hive()` + `MissionEntityIndex.get_hive_in_room()` with `has_meta` guards | Eliminates error flood |
| Hive activation | 0.2 s tick + cached room list | ~5× less dormant hive work |
| Soldier UI | S&D/explore labels + path line at 10 Hz | ~6× less per-unit UI work |
| Soldier separation | Skipped when unit far from camera | Less O(n²) separation |
| Comms log | Append-only BBCode, cap 40 lines, 10 Hz batch | No full RichText rebuild per line |
| Minimap | 0.5 s refresh or on fog reveal | ~2 Hz canvas work |
| HUD roster | Refresh every 0.1 s (10 Hz) | ~6× less UI churn vs 60 Hz |
| Ghost preview | Planet: single selected unit only | Avoids 12× A* on mouse move |
| Process tiers | Off-screen units/hives `set_process(false)` every 0.2 s | Lower AI/movement cost off-camera |
| Orbital bar | Evolution bonus recalc every 0.5 s | Less per-frame board polling |
| SwarmDirector | Adapt log cooldown 12 s; `tick()` 1 Hz | No deploy comms flood |
| Planet size | Default generation **12–16 rooms**; 1–2 nest hives | Fewer rooms/enemies/fog cells |
| Map enemy cap | **22** living enemies map-wide (`TacticalMap.MAP_ENEMY_CAP`) | Prevents hive swarm FPS collapse |
| LineOfSight | Cache room-at-endpoints in segment tests | Faster LOS on corridor checks |
| Path graph | Max 3 A* rebuilds per frame; invalidate on door open/close | Smoother movement spikes |
| Fog pass (pass 3) | Room-first sweep in `MissionEntityIndex.fog_reveal_rooms()` | Single soldier list + batched reveals |
| Dead units (pass 3) | `PROCESS_MODE_DISABLED` on KIA; index unregister | No zombie `_process` on casualties |
| Combat coordinator (pass 3) | 10 Hz `CombatCoordinator.gd` target batch | Shared room enemy/hive lists |
| Pathfind budget (pass 3) | 4/3/2 finds per frame by alive count | Scales with squad size |

## Tuning knobs

### `RunState.get_planet_config()`

```gdscript
"planet_room_min": 12,
"planet_room_max": 16,
```

Pass overrides into `ProceduralMapGenerator.generate_planet(seed, config)`.

### `TacticalMap.gd` constants

- `FOG_UPDATE_INTERVAL_SEC` — seconds between fog passes (default `0.5`); also runs when `_fog_dirty`
- `FOG_LOS_RANGE` — skip enemy LOS if farther than this from all soldiers (default `480`)
- `HUD_REFRESH_INTERVAL` — seconds between roster refresh (default `0.1`)
- `MINIMAP_REFRESH_INTERVAL` — seconds between minimap redraw (default `0.5`); also on fog reveal
- `COMMS_REFRESH_INTERVAL` — seconds between comms display flush (default `0.1`)
- `MAX_COMMS_LINES` — comms buffer cap (default `40`)
- `UNIT_TIER_INTERVAL` — seconds between off-screen process tier updates (default `0.2`)
- `UNIT_SLEEP_RADIUS` — world px beyond camera center to sleep units (default `960`)
- `ORBITAL_BAR_INTERVAL` — seconds between evolution orbital bonus recalc (default `0.5`)

### `SoldierUnit.gd`

- `UI_REFRESH_INTERVAL` — seconds between S&D/explore labels and path line (default `0.25`)
- Combat targets assigned by `CombatCoordinator` at 10 Hz (no per-unit combat rescan interval)

### `CombatCoordinator.gd`

- `TICK_INTERVAL` — seconds between combat target batch passes (default `0.1`)

### `DynamicPathGraph.gd`

- `set_max_finds_per_frame(max)` — runtime cap on uncached A* runs per frame
- Default max finds: **4** when fewer than 4 soldiers alive; **3** at 4–7; **2** at 8+
- `TacticalMap._update_pathfind_budget()` sets this each frame from living soldier count

### `Hive.gd`

- Dormant activation batched on `TacticalMap` every **0.2 s** via `tick_dormant_activation()`; hive `_process` only when **ACTIVE** or focus-mark timer running

### `Door.gd`

- `_process` only while animating or open (idle auto-close); `bind_tactical_map()` for cached soldier proximity

### `SoldierUnit.gd` (pass 4)

- `SEPARATION_INTERVAL` — seconds between separation pushes (default `0.05`)

### `EnemyUnit.gd`

- Distant AI interval: enemies farther than **640 px** from the nearest soldier use a 3-frame tick instead of 2.

### `SwarmDirector.gd`

- `_adapt_log_cooldown` — seconds between adapt pressure comms (default `12`)

## Profiling

While a mission runs, `RunLog.perf()` can emit a line like (verbose mode only, max every 5 s):

```text
PERF fog=1.2ms rooms=28 enemies=42 soldiers=12
```

Use `logs/latest_run.txt` to confirm fog ms stays low after changes. Call `RunLog.set_verbose(true)` to enable PERF/DEBUG and engine print capture.

## RunLog I/O

Session logs batch-flush to disk every **0.25 s** (immediate flush on window close). Engine `print()` capture is off during gameplay unless verbose. Max **10 000** lines per session.

## QA

```bash
godot --headless --path . res://qa_runner.tscn
```

Planet map smoke test expects **12–16** rooms and **1–2** regular hive rooms.

## Further ideas (not implemented)

- Spatial hash for LOS only among co-located / adjacent rooms
- Shared enemy AI coordinator tick on TacticalMap (single nearest-soldier query per enemy batch)
- Static minimap texture baked on layout load
