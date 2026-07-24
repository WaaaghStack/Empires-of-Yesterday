# Audit: cell-world transition, bugs, and UI/UX issues

**Date:** 2026-07-18  
**Stage:** Audit list + **implement pass** (2026-07-19) for high/medium FPS-safe items.  
**Scope:** Equal-area sphere/cell world migration, live SCD1 presentation, unit occupancy/pathing, structures/build UX, dual-truth and late-game cost hotspots.

Related docs: [INDEX.md](INDEX.md), [REQUEST_SCD1_VERSIONED_PULL.md](REQUEST_SCD1_VERSIONED_PULL.md), [DESIGN.md](../DESIGN.md), [PERFORMANCE.md](../PERFORMANCE.md), [RUST.md](../RUST.md).

### Implement status (2026-07-19)

| Status | Items |
|--------|--------|
| **Closed** | A1–A4 (sphere dual-address, radian sectors, equirect bake sampling, sphere cell helpers); D1–D4 (barracks/hangar roads, bridge landing angular, AI geo distance, builder snap angular); B1–B4 (structure tombstones/`removed_ids`, `last_version` rewind on full/sim_gen, per-domain full cooldown, bridge_corridors on full apply); C1, C2, C4 (free-miss skip, soft goal claims, no free BFS when free exhausted); E1–E3 (DESIGN 5 s barracks/hangar; PERFORMANCE/RUST SCD1 live) |
| **Deferred** | A5 full icosphere-only mesh; A6 Rust pick hot path; A7–A10 packing/fingerprint polish; B5–B8 living-set/bomber scale/overlay mix/territory chunk seed; C3 path-block queue feel; D5–D10 dual-feed polish; E4 logistics 25 s recal; E5 FULL_RESYNC metrics |
| **Contract** | Rust = sim engine; Godot = SCD1 visualization only. Path-block remains wait-without-pathfind. |

---

## How to read this list

Each item:

| Field | Meaning |
|-------|---------|
| **Category** | `bug` · `UI-UX` · `perf-risk` · `dual-truth` · `docs` · `other` |
| **Severity** | `high` · `medium` · `low` |
| **Anchors** | File paths and symbols for follow-up work |

---

## Prioritized fix order (recommended)

1. **Sphere addressing** — `cell_index` dual-address (`gy==0`), radian sector math, bake/mesh row-0 sampling.  
2. **Sphere distance / AI / bridge helpers** still treating cell IDs as 2D grid coords.  
3. **SCD1 correctness** — structure tombstones; `last_version` rewind on epoch reset.  
4. **Pathing cost** — free-goal then contested double BFS; goal-claim or skip free search when free count is 0.  
5. **Docs drift** — PERFORMANCE/RUST/DESIGN still describe old pipelines or 60 s build times.  
6. **Presentation polish** — living-set unit pull cost, bomber scale UX, overlay encoding mix.  
7. **Residual healers** — logistics full recal ~25 s; full territory seed hitch (Policy 7).

---

## A. Sphere / cell world (geometry, addressing, map gen)

### A1. Dual-address collision: `(cell_id, 0)` vs equirect `(gx, 0)`

| | |
|--|--|
| **Category** | bug / dual-truth |
| **Severity** | **high** |
| **Description** | In `sphere_mode`, `cell_index` treats any `(gx, 0)` with `0 ≤ gx < cell_count` as a **gameplay cell id**. Equirect row `gy == 0` also uses `gy == 0` with `gx ∈ [0, grid_width)`. Callers that walk overlay pixels via `is_land_cell` / `get_tile_height` therefore resolve the entire north scanline as cells `0…359` instead of `equirect_to_cell`. |
| **Anchors** | `BattleMapData.gd` — `cell_index` (~99–108), `gameplay_tile_count` |

### A2. Sector bins use degrees on radian lat/lon

| | |
|--|--|
| **Category** | bug |
| **Severity** | **high** |
| **Description** | `sector_col_row_for_grid` in sphere mode uses `(lon + 180) / 360` and `(90 - lat) / 180`, but `cell_lat` / `cell_lon` are filled with **radians** (`asin` / `atan2` in `SphereGridLib` / `sphere_grid.rs`). Almost all cells collapse into a few sector bins; `region_id_for_grid` inherits the error. |
| **Anchors** | `BattleMapData.gd` — `sector_col_row_for_grid` (~260–274); `SphereGridLib.gd` (~74–78) |

### A3. Planet visual bake samples land/height through dual `(gx,gy)` API

| | |
|--|--|
| **Category** | bug / dual-truth |
| **Severity** | **high** |
| **Description** | Albedo/height bakes loop equirect `gx,gy` and call `is_land_cell` / `get_tile_height`. Combined with A1, pole row samples wrong sphere cells. Cached images under world pack can freeze incorrect poles. |
| **Anchors** | `PlanetVisualBake.gd` — `build_albedo_image` / `build_height_image`; `WorldPackLib.gd` cache keys |

### A4. 2D `cell_center` / `world_to_grid` / snap still rectangular

| | |
|--|--|
| **Category** | dual-truth / incomplete migration |
| **Severity** | **high** |
| **Description** | Sphere gameplay is linear cell ids + 3D `cell_positions`, but `cell_center`, `world_to_grid`, and sphere `snap_world_to_cell_center` still use flat 2D math / clamp `y=0`. Any remaining 2D world path disagrees with globe picks and sim cell ids. |
| **Anchors** | `BattleMapData.gd` — `cell_center`, `world_to_grid`, `snap_world_to_cell_center` (~293–321) |

### A5. Gameplay mesh (icosphere cells) vs default render mesh (equirect quads)

| | |
|--|--|
| **Category** | dual-truth / UI-UX |
| **Severity** | **medium** |
| **Description** | Sim authority is sphere cells; default globe build is meridian equirect quads (full `build_sphere_grid_mesh` is debug/QA-only). Owner/fluid textures are equirect LUTs; picks use geodesic `nearest_cell`. Two geometries for one world → visual vs pick mismatch risk. |
| **Anchors** | `EarthGlobeMap.gd` — `_build_globe_mesh_for_detail` (~390–401); `EarthGlobeMesh.gd` |

### A6. `nearest_cell` O(N) GDScript; Rust pick path unused / cold-regenerate risk

| | |
|--|--|
| **Category** | perf-risk |
| **Severity** | **high** |
| **Description** | Globe pick runs full scan over ~64k positions in GDScript. Rust `sphere_nearest_cell` exists but is not used on the main pick path; cold FFI can regenerate an entire f=80 grid — catastrophic if ever called without cache. |
| **Anchors** | `SphereGridLib.gd` — `nearest_cell`; `EarthGlobeMap.gd` — `pick_grid_from_viewport`; `lib.rs` — `sphere_nearest_cell` |

### A7. Resource spacing: cell distance vs degrees of arc

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **medium** |
| **Description** | Rect maps use integer cell spacing (`RESOURCE_BLOB_MIN_SPACING` / exclusion as cell counts). Sphere path uses the same numbers as **degrees** of arc on unit vectors. Density/exclusion semantics diverge without named angular config. |
| **Anchors** | `WorldConquestConfig.gd` resource spacing constants; `WorldConquestMapGenerator.gd` sphere vs rect scatter |

### A8. World pack caches lack content fingerprint

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **medium** |
| **Description** | Grid/LUT/land/elev caches key primarily on map id + frequency (`_VER` only). Updating land masks, elev bins, or generator algorithm can still serve stale pack data without a content hash. |
| **Anchors** | `WorldPackLib.gd` — load/save grid, equirect LUT, world cells |

### A9. Equirect→cell LUT is image-space flood, not geodesic nearest

| | |
|--|--|
| **Category** | dual-truth (design debt) |
| **Severity** | **low–medium** |
| **Description** | LUT seeds lon/lat then 4-connected flood. Overlay ownership/pressure assignment can disagree with ray-pick `nearest_cell` on the same surface point. |
| **Anchors** | `SphereGridLib.build_equirect_to_cell`; `sphere_grid.rs` equivalent |

### A10. GDScript / Rust sphere generators are dual mirrors

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **low** |
| **Description** | `SphereGridLib` prefers Rust `generate_sphere_grid` but falls back to pure GDScript. Slight float/vertex differences + mixed cache sources can pair GDScript positions with a Rust-built LUT. |
| **Anchors** | `SphereGridLib.generate`; `rust/.../sphere_grid.rs` |

---

## B. Live presentation / SCD1 / units UI

### B1. Structures SCD1 has no tombstones (incremental)

| | |
|--|--|
| **Category** | bug |
| **Severity** | **high** |
| **Description** | Incremental structures pull only upserts rows with `version > last`. Removes bump epoch but do not emit deleted sids. Apply never drops missing rows on incremental batches; Screen destroy path manually clears cache. Rust-only removes without that path leave ghost markers/cache until full resync. |
| **Anchors** | `WorldConquestScreen.gd` — `_apply_scd1_structures`; `lib.rs` — `pull_domain_since` structures / `structure_store_remove` |

### B2. SCD1 `last_version` does not rewind when high-water resets

| | |
|--|--|
| **Category** | bug |
| **Severity** | **high** |
| **Description** | `_apply_high_water` only advances when `hw > last`. `bump_sim_generation` zeros domain epochs. Client can keep stale high `last` → `session_mismatch` / cooldown / empty paints. `reset_for_new_match` helps rematch; mid-life re-setup without client reset is brittle. |
| **Anchors** | `Scd1DomainPull.gd` — `_apply_high_water`; `domain_version.rs` — `bump_sim_generation` |

### B3. Full-pull cooldown is global across domains

| | |
|--|--|
| **Category** | bug / SCD1 policy |
| **Severity** | **medium** |
| **Description** | One cooldown timestamp gates all domains. A full resync on one domain can deny allow-listed full pulls on others for ~3 s (`full_denied_cooldown`). |
| **Anchors** | `Scd1DomainPull.gd` — `_cooldown_ok`, `pull_domain` |

### B4. Structures pull includes `bridge_corridors` but apply ignores them

| | |
|--|--|
| **Category** | dual-truth / SCD1 completeness |
| **Severity** | **medium** |
| **Description** | Rust packs `bridge_corridors` for view; Godot apply only consumes structure `rows`. Bridge ribbons still depend on `battle_data.bridge_corridors` and side sync paths. |
| **Anchors** | `lib.rs` structures domain pack; `WorldConquestScreen._apply_scd1_structures` |

### B5. Agents/bombers living-set pull = full visual pool rebuild at 4 Hz

| | |
|--|--|
| **Category** | perf-risk / UI-UX |
| **Severity** | **medium** |
| **Description** | Correct for multi-unit living set (avoids teleport pops), but each due tick still rebuilds full row packs and resets Sprite3D pools. Cost tracks living count, not “who moved.” |
| **Anchors** | `lib.rs` agents/bombers pull; `WorldConquestScreen._flush_live_presentation_delta`; `EarthGlobeMap.sync_soldiers` / `sync_bombers` |

### B6. Bomber billboard scale encodes search expand budget

| | |
|--|--|
| **Category** | UI-UX |
| **Severity** | **medium** |
| **Description** | Bomber visual scale lerps with `search_expand_limit` (failed strike searches grow the craft). Reads as size power-up, not pathfinding stress. |
| **Anchors** | `EarthGlobeMap.gd` — `_bomber_scope_visual_scale`, `_place_pooled_bomber` |

### B7. Overlay queue can mix owner vs display encodings

| | |
|--|--|
| **Category** | bug / UI-UX |
| **Severity** | **medium** |
| **Description** | Queue flags R8 vs display mode when empty; subsequent enqueues of the other encoding can append under the wrong mode → wrong ownership colors until reconcile. |
| **Anchors** | `OutpostConstructionQueue.gd` — `enqueue_overlay_delta` / `enqueue_overlay_display_delta` |

### B8. Territory full seed dumps entire owner grid in one batch

| | |
|--|--|
| **Category** | perf-risk |
| **Severity** | **medium** |
| **Description** | Start/full territory pull can enumerate all owner cells (~64k) in one FFI apply frame. REQUEST Policy 7 prefers chunked multi-frame seed. |
| **Anchors** | `lib.rs` Territory domain; `WorldConquestScreen` SCD1 flush; REQUEST Policy 7 |

---

## C. Soldier / bomber pathing and occupancy

### C1. Free-goal then contested double BFS

| | |
|--|--|
| **Category** | perf-risk |
| **Severity** | **high** |
| **Description** | Replan tries free-goal nearest search first; on miss runs unrestricted search. Infantry expands up to `MAX_PATHFIND_EXPAND`; bombers expand further on failure. Urgent budget up to ~24 units/tick → worst-case many double BFS when free goals are scarce (late game). Occupancy map O(1) helps filters, not double expand. |
| **Anchors** | `agents.rs` — `replan_route` / `find_advance_path`; `bombers.rs` — `replan_route` / `find_strike_path` |

### C2. Free goals are not claimed — stampede then goal_taken storms

| | |
|--|--|
| **Category** | UI-UX / sim design |
| **Severity** | **medium** |
| **Description** | Free filter uses **current** cell occupancy only. Many units can target the same free stance/strike; only after occupation do others get `goal_taken` urgent replan. Causes lines, wait chains, and feeds C1. |
| **Anchors** | `agents.rs` / `bombers.rs` — `goal_taken`, free goal predicate |

### C3. Path-block wait can freeze units behind a stationary peer

| | |
|--|--|
| **Category** | UI-UX |
| **Severity** | **medium** |
| **Description** | Next cell occupied → wait one move step without clearing step; unit is not “stuck” for urgent replan unless goal taken / timer / nav stale. Dense corridors can queue indefinitely behind a holder. Intentional anti-thrash; still a play feel risk. |
| **Anchors** | `agents.rs` / `bombers.rs` move loops |

### C4. No “free_count == 0 → skip free search” fast path

| | |
|--|--|
| **Category** | perf-risk |
| **Severity** | **medium** |
| **Description** | When no free goals remain, free BFS still runs until expand fails, then contested BFS runs. Endgame cost spike is structural, not occupancy-map related. |
| **Anchors** | Same replan free-then-contested pattern as C1 |

---

## D. Structures, build UX, dual feeds

### D1. Barracks/hangar roads omitted from Godot `road_cells_for_team`

| | |
|--|--|
| **Category** | bug |
| **Severity** | **high** |
| **Description** | Infra packing walks spawner paths only; barracks/hangar `path_keys` omitted. Live portal rebuild may merge Rust `network_built`, but hover/resource/non-authority paths can miss multi-structure roads. |
| **Anchors** | `WorldConquestOutpostBuild.gd` — `road_cells_for_team`; `WorldConquestResources.gd`; `WorldConquestScreen` portal rebuild |

### D2. Bridge landing helper uses lat/lon-style grid keys (sphere-unsafe)

| | |
|--|--|
| **Category** | bug |
| **Severity** | **high** |
| **Description** | `_nearest_bridge_landing_for_target` uses packed keys and Euclidean `(dx,dy)` on coordinates that on sphere are cell ids (`Vector2i(cell_id, 0)`). “Nearest” landing is ID arithmetic, not graph/geo distance. |
| **Anchors** | `WorldConquestOutpostBuild.gd` — `_nearest_bridge_landing_for_target` |

### D3. Enemy AI scores candidates with 2D distance on cell ids

| | |
|--|--|
| **Category** | bug |
| **Severity** | **high** |
| **Description** | Sphere candidate collection may BFS, but scoring still uses `Vector2i.distance_to` on homes. Toward-player preference is effectively ID-biased on sphere. Spacing correctly uses angular metrics elsewhere. |
| **Anchors** | `EnemyStrategy.gd` — `_score_outpost_cell` / `_score_bridge_cell` |

### D4. Builder path snap on sphere uses numeric cell_id proximity

| | |
|--|--|
| **Category** | bug |
| **Severity** | **medium** |
| **Description** | Sphere branch of path snap minimizes absolute packed-key delta, not neighbor hops. Can jump to wrong vertices for chained/visual work (legacy or non-authority paths). |
| **Anchors** | `BuilderAgentLib.gd` — `_snap_pos_to_work_path` / work grid helpers |

### D5. Enemy AI plan snapshot can read stale Godot owner mirror

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **medium** |
| **Description** | Placement reject uses Rust `owner_at_index`; AI snapshot may use `tile_control.owners` only as fresh as delta apply. Risk: plans on wrong ownership until reconcile. |
| **Anchors** | `WorldConquestScreen.gd` enemy plan snapshot; `BattleTerritorySim.owner_at_index` |

### D6. Supply wallet dual: supply in Screen, resources in Rust SCD1

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **medium** |
| **Description** | Tile income and structure **supply** mutate Screen-local supply; resource wallet is Rust SCD1. Afford is supply-only today; future mixed costs would split truth. |
| **Anchors** | `WorldConquestScreen.gd` supply fields; `EconomyLib` / `EconomyCatalog`; wallet SCD1 |

### D7. Spawner inject still dual-fed via BattleTileControl list

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **medium** |
| **Description** | Activation reloads spawners from `placed_structures` render cache into Rust. SCD1 structure lag can briefly desync inject points from ACTIVE rows. |
| **Anchors** | `WorldConquestScreen` spawner sync; `BattleTileControl` spawner list |

### D8. Live builder arrivals skip construction-queue cell-advance paint

| | |
|--|--|
| **Category** | UI-UX |
| **Severity** | **medium** |
| **Description** | Under builder authority, Godot cell-arrival handler no-ops invent; roads come from network pending + SCD1 roads. CONNECTING growth can feel batchy vs cell-by-cell under frame caps. |
| **Anchors** | `WorldConquestScreen._on_rust_builder_cell_arrival`; `OutpostConstructionQueue` |

### D9. Sphere forces sync placement route (async disabled)

| | |
|--|--|
| **Category** | UI-UX |
| **Severity** | **low–medium** |
| **Description** | Intentional: sphere disables async route placement after failures. Players always hit sync route cost; flat maps keep “Planning…” async UX. |
| **Anchors** | `WorldConquestScreen.gd` placement async flag / sphere branch |

### D10. BuilderAgentLib remains a dual-sim fallback if flags off

| | |
|--|--|
| **Category** | dual-truth |
| **Severity** | **low** (live flags on) |
| **Description** | Live correctly prefers Rust `builder_step` and refuses GDScript step under authority. Misconfigured flags re-enable dual `path_built` writes. |
| **Anchors** | `BuilderAgentLib.step_frame`; `WORLD_DATASET_BUILDER_AUTHORITY` |

---

## E. Docs and residual architecture

### E1. DESIGN.md still lists barracks/hangar build as 60 s

| | |
|--|--|
| **Category** | docs |
| **Severity** | **high** (truth mismatch) |
| **Description** | Live `WorldConquestConfig` sets `BARRACKS_BUILD_SEC` / `HANGAR_BUILD_SEC` to **5.0** (same as outpost). DESIGN glossary still says **60 s**. |
| **Anchors** | `WorldConquestConfig.gd`; `DESIGN.md` structure table (~53–54) |

### E2. PERFORMANCE.md still describes PresentationTxn as live pipeline

| | |
|--|--|
| **Category** | docs |
| **Severity** | **high** |
| **Description** | Live paint is SCD1 (`Scd1DomainPull` / `pull_domain_since`). PERFORMANCE still centers PresentationTxn and omits SCD1 gap policies. Misleading for perf work. |
| **Anchors** | `PERFORMANCE.md` L7–14; contrast `WorldConquestScreen._flush_live_presentation_delta` |

### E3. RUST.md mixed: SCD1 at top, PresentationTxn as live paint later

| | |
|--|--|
| **Category** | docs |
| **Severity** | **medium** |
| **Description** | Intro correctly documents SCD1; API table still lists `pull_presentation_txn` as live paint. |
| **Anchors** | `RUST.md` |

### E4. Logistics full recal ~25 s still active

| | |
|--|--|
| **Category** | perf-risk |
| **Severity** | **medium** |
| **Description** | REQUEST demotes logistics full recal as correctness crutch. `LOGISTICS_FULL_RECAL_SEC := 25.0` and rebuild-on-timer remain — uncorrelated mid-match spikes. |
| **Anchors** | `WorldConquestConfig.LOGISTICS_FULL_RECAL_SEC`; `logistics.rs` |

### E5. FULL_RESYNC metrics incomplete vs Policy 6

| | |
|--|--|
| **Category** | other / ops |
| **Severity** | **low** |
| **Description** | Policy 6 wants reason + cost_ms + high_water + last_was. Logs mainly reason + cooldown. |
| **Anchors** | `Scd1DomainPull._note_full`; REQUEST Policy 6 |

---

## F. Category coverage notes

| Area | Result |
|------|--------|
| Cell / sphere world | Multiple high findings (A1–A10) |
| Live presentation / SCD1 / units | Multiple findings (B1–B8) |
| Pathing / occupancy / endgame cost | Multiple findings (C1–C4) |
| Structures / build UX | Multiple findings (D1–D10) |
| Docs / residual healers | E1–E5 |

No category was skipped without inspection.

---

## Suggested next implementation batches (not done here)

| Batch | Items | Theme |
|-------|-------|--------|
| 1 | A1, A2, A3, A4 | Sphere addressing and bake correctness |
| 2 | D2, D3, D4 | Sphere-safe distance / AI / bridge math |
| 3 | B1, B2, B3, B4 | SCD1 correctness |
| 4 | C1, C2, C4 | Pathing cost + free-goal claims |
| 5 | E1, E2, E3 | Doc truth |
| 6 | B5–B8, D5–D10, E4–E5 | Polish and residual thrash |

---

## Explicit non-goals of this document

- No gameplay, sim, UI, or DLL implementation changes were made for this audit.  
- No FPS measurement or interactive playthrough as a gate.  
- Not a complete line-by-line review of every file in the monorepo.

---

## Inspection summary (modules touched for evidence)

- Map/cells: `BattleMapData.gd`, `SphereGridLib.gd`, `WorldPackLib.gd`, `PlanetVisualBake.gd`, `WorldConquestMapGenerator.gd`, `EarthGlobeMap.gd`, `EarthGlobeMesh.gd`, `rust/.../sphere_grid.rs`  
- SCD1/presentation: `WorldConquestScreen.gd`, `Scd1DomainPull.gd`, `lib.rs` pull domains, `EarthGlobeMap` unit billboards  
- Units/path: `agents.rs`, `bombers.rs`, pathfind (`battle_nav`, `kernel`, `nav_rules`)  
- Build/AI: `WorldConquestOutpostBuild.gd`, `OutpostConstructionQueue.gd`, `BuilderAgentLib.gd`, `EnemyStrategy.gd`, `EconomyCatalog`/`EconomyLib`  
- Docs: `docs/INDEX.md`, REQUEST SCD1, DESIGN, PERFORMANCE, RUST  

**Findings file:** `docs/AUDIT_CELL_WORLD_BUGS_UX.md`  
**Item count:** 38 discrete findings (A1–A10, B1–B8, C1–C4, D1–D10, E1–E5).
