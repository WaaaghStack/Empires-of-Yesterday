//! Empire Territory Sim — Rust GDExtension for high-performance territory conquest simulation.
//!
//! lib.rs is the GDExtension class surface (C3). Conversion helpers live in `ffi_convert`;
//! domain logic lives in modules (`logistics`, `sim`, `world_session`, …). Prefer not growing
//! pure helpers here — extract to domain modules or `ffi_convert`.

mod agents;
mod bombers;
mod builders;
mod domain_version;
mod economy;
mod ffi_convert;
mod flow_constants;
mod fluid_bake;
mod grid_query;
mod logistics;
mod pathfind;
mod presentation_txn;
mod resources;
mod route;
mod sim;
mod structures;
mod tape_codec;
mod world_edit;
mod world_session;

use economy::{
    fill_structure_row, f32_at, i32_at, u32_at, ContentTables, MAX_KINDS, RESOURCE_SLOTS,
};
use ffi_convert::{
    corridor_specs_from_array, f32_triple_from_array, logistics_step_events_dict,
    packed_byte_to_vec, packed_f32_to_vec, persisted_corridor_from_dict, spawners_from_dict,
    structure_record_from_dict, structure_record_to_dict, vec_to_packed_byte, vec_to_packed_f32,
    vec_to_packed_i32, world_edit_result_dict, world_session_events_dict, GdDictionary,
};
use fluid_bake::bake_fluid_rgba;
use godot::builtin::Variant;
use godot::prelude::*;
use rayon::prelude::*;
use std::sync::Arc;
use agents::{AgentConfig, AgentLayer};
use bombers::{BomberConfig, BomberLayer};
use builders::{BuilderConfig, BuilderLayer};
use logistics::{clamp_reconcile_budget, LogisticsConfig, LogisticsLayer};
use resources::ResourceWallet;
use route::{PortalGraph, RoutePlannerState, RouteSnapshot};
use structures::{state_from_str, StructureStore};
use sim::{Spawner, TerritoryKernel};
use tape_codec::{decode_pressure_v2, encode_pressure_v2, pack_territory_tape_v2};
use domain_version::{
    decide_full_pull, full_pull_allowed_by_cooldown, DomainBook, DomainId, FullPullReason,
    FULL_PULL_COOLDOWN,
};
use presentation_txn::PresentationTxn;
use world_session::{tick_world_session, WorldSessionConfig};
use std::time::Instant;

struct EmpireTerritoryExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EmpireTerritoryExtension {}

/// Main simulation object exposed to GDScript.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct TerritorySim {
    base: Base<RefCounted>,
    kernel: Option<TerritoryKernel>,
    agents: Option<AgentLayer>,
    agents_enabled: bool,
    agent_snap_teams: Vec<u8>,
    agent_snap_gx: Vec<i32>,
    agent_snap_gy: Vec<i32>,
    bombers: Option<BomberLayer>,
    bombers_enabled: bool,
    bomber_snap_teams: Vec<u8>,
    bomber_snap_gx: Vec<i32>,
    bomber_snap_gy: Vec<i32>,
    bomber_snap_search_scope: Vec<i32>,
    structure_store: StructureStore,
    /// SCD1 per-domain epochs (docs/REQUEST_SCD1_VERSIONED_PULL.md).
    domain_book: DomainBook,
    /// Parallel to kernel.owners — last domain version when cell owner changed.
    owner_cell_version: Vec<u64>,
    /// Parallel to logistics built mask length — version when road cell became built.
    road_cell_version: Vec<u64>,
    /// Wallet domain version stamp.
    wallet_version: u64,
    /// Gap full-pull cooldown tracking (server-side helper for Godot; also used in tests).
    last_full_pull_at: Option<Instant>,
    /// Legacy change feed — not used on live SCD1 path (QA/goldens only).
    presentation_txn: PresentationTxn,
    world_session_cfg: WorldSessionConfig,
    world_session_enabled: bool,
    builder_layer: BuilderLayer,
    logistics_layer: LogisticsLayer,
    builder_cfg: BuilderConfig,
    logistics_cfg: LogisticsConfig,
    builder_enabled: bool,
    logistics_enabled: bool,
    resource_wallet: ResourceWallet,
    resource_wallet_enabled: bool,
    content_tables: ContentTables,
    player_home_gx: i32,
    player_home_gy: i32,
    enemy_home_gx: i32,
    enemy_home_gy: i32,
}

#[godot_api]
impl TerritorySim {
    #[func]
    fn hello(&self) -> GString {
        "Hello from Rust (empire_territory) — simple water sim active.".into()
    }

    #[func]
    fn version(&self) -> GString {
        env!("CARGO_PKG_VERSION").into()
    }

    #[func]
    fn is_ready(&self) -> bool {
        self.kernel.is_some()
    }

    #[func]
    fn setup_from_dict(&mut self, config: GdDictionary) -> bool {
        let grid_w: i32 = config.get("grid_w").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let grid_h: i32 = config.get("grid_h").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let tile_count = (grid_w * grid_h) as usize;
        if tile_count <= 0 {
            self.kernel = None;
            return false;
        }

        let use_active_set: bool = config
            .get("use_active_set")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(false);
        let use_adaptive_double_pass: bool = config
            .get("use_adaptive_double_pass")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(!use_active_set);

        let claimable: PackedByteArray = config
            .get("claimable")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let elevation: PackedFloat32Array = config
            .get("elevation")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let flow_mult: PackedFloat32Array = config
            .get("flow_mult")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let claim_mult: PackedFloat32Array = config
            .get("claim_mult")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let owners: PackedByteArray = config
            .get("owners")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let pressure_friendly: PackedFloat32Array = config
            .get("pressure_friendly")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let pressure_hostile: PackedFloat32Array = config
            .get("pressure_hostile")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();

        let friendly_spawn_rate: f32 = config
            .get("friendly_spawn_rate")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0.0);
        let hostile_spawn_rate: f32 = config
            .get("hostile_spawn_rate")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0.0);
        let player_home_idx: i32 = config
            .get("player_home_idx")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(-1);
        let enemy_home_idx: i32 = config
            .get("enemy_home_idx")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(-1);
        let friendly_tiles: i32 = config
            .get("friendly_tiles")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        let hostile_tiles: i32 = config
            .get("hostile_tiles")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        let wrap_longitude: bool = config
            .get("wrap_longitude")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(false);

        self.kernel = Some(TerritoryKernel::new(
            grid_w,
            grid_h,
            packed_byte_to_vec(&claimable),
            packed_f32_to_vec(&elevation),
            packed_f32_to_vec(&flow_mult),
            packed_f32_to_vec(&claim_mult),
            packed_byte_to_vec(&owners),
            packed_f32_to_vec(&pressure_friendly),
            packed_f32_to_vec(&pressure_hostile),
            friendly_spawn_rate,
            hostile_spawn_rate,
            player_home_idx,
            enemy_home_idx,
            spawners_from_dict(&config),
            friendly_tiles,
            hostile_tiles,
            use_active_set,
            use_adaptive_double_pass,
            wrap_longitude,
        ));
        if let Some(kernel) = self.kernel.as_mut() {
            let inject_interval: i32 = config
                .get("pressure_inject_interval_rounds")
                .or_else(|| config.get("spawner_inject_interval_rounds"))
                .and_then(|v| v.try_to().ok())
                .unwrap_or(10);
            kernel.spawner_inject_interval_rounds = inject_interval.max(1);
            let passable: PackedByteArray = config
                .get("passable_mask")
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            let land: PackedByteArray = config
                .get("land_mask")
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            if passable.len() > 0 && land.len() > 0 {
                let tile_h: PackedFloat32Array = config
                    .get("tile_height")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let move_c: PackedFloat32Array = config
                    .get("move_cost")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let defense: PackedFloat32Array = config
                    .get("defense")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let cover: PackedByteArray = config
                    .get("cover_cells")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                kernel.init_world_terrain(
                    packed_byte_to_vec(&passable),
                    packed_byte_to_vec(&land),
                    packed_f32_to_vec(&tile_h),
                    packed_f32_to_vec(&move_c),
                    packed_f32_to_vec(&defense),
                    packed_byte_to_vec(&cover),
                );
            }
            let fr: PackedByteArray = config
                .get("friendly_reachable")
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            // SCD1: new world — bump sim generation and size cell version vectors.
            self.domain_book.bump_sim_generation();
            self.owner_cell_version = vec![0u64; tile_count];
            self.road_cell_version = vec![0u64; tile_count];
            self.wallet_version = 0;
            if fr.len() > 0 {
                let hr: PackedByteArray = config
                    .get("hostile_reachable")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let fb: PackedByteArray = config
                    .get("friendly_bridge_reachable")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let hb: PackedByteArray = config
                    .get("hostile_bridge_reachable")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let fcl: PackedByteArray = config
                    .get("friendly_corridor_land")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let hcl: PackedByteArray = config
                    .get("hostile_corridor_land")
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                kernel.init_reachability_masks(
                    packed_byte_to_vec(&fr),
                    packed_byte_to_vec(&hr),
                    packed_byte_to_vec(&fb),
                    packed_byte_to_vec(&hb),
                    packed_byte_to_vec(&fcl),
                    packed_byte_to_vec(&hcl),
                );
            }
        }
        true
    }

    #[func]
    fn update_claimable(
        &mut self,
        claimable: PackedByteArray,
        elevation: PackedFloat32Array,
        flow_mult: PackedFloat32Array,
        claim_mult: PackedFloat32Array,
        owners: PackedByteArray,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        kernel.update_claimable(
            packed_byte_to_vec(&claimable),
            packed_f32_to_vec(&elevation),
            packed_f32_to_vec(&flow_mult),
            packed_f32_to_vec(&claim_mult),
            packed_byte_to_vec(&owners),
        );
    }

    #[func]
    fn update_claimable_delta(
        &mut self,
        indices: PackedInt32Array,
        claimable: PackedByteArray,
        owners: PackedByteArray,
        elevation: PackedFloat32Array,
        flow_mult: PackedFloat32Array,
        claim_mult: PackedFloat32Array,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        let idx_vec: Vec<i32> = (0..indices.len())
            .map(|i| indices.get(i).unwrap_or(-1))
            .collect();
        kernel.apply_claimable_delta(
            &idx_vec,
            &packed_byte_to_vec(&claimable),
            &packed_byte_to_vec(&owners),
            &packed_f32_to_vec(&elevation),
            &packed_f32_to_vec(&flow_mult),
            &packed_f32_to_vec(&claim_mult),
        );
    }

    #[func]
    fn set_home_inject_enabled(&mut self, enabled: bool) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        kernel.set_home_inject_enabled(enabled);
    }

    #[func]
    fn world_edit_ready(&self) -> bool {
        self.kernel
            .as_ref()
            .map(|k| k.world_edit_ready)
            .unwrap_or(false)
    }

    #[func]
    fn extend_beachhead_from_landing(&mut self, gx: i32, gy: i32, team: u8) -> GdDictionary {
        let Some(kernel) = self.kernel.as_mut() else {
            return GdDictionary::new();
        };
        world_edit_result_dict(&kernel.extend_beachhead_from_landing(gx, gy, team))
    }

    #[func]
    fn sync_bridge_corridors_rust(
        &mut self,
        specs: Array<Variant>,
        force_full: bool,
        sid_filter: PackedInt32Array,
    ) -> GdDictionary {
        let Some(kernel) = self.kernel.as_mut() else {
            return GdDictionary::new();
        };
        if force_full && self.structure_store.ready {
            for st in self.structure_store.structures.values_mut() {
                st.corridor_synced_built = 1;
            }
            for corridor in self.structure_store.persisted_corridors.iter_mut() {
                corridor.corridor_synced_built = 1;
            }
        }
        let filter: Vec<i32> = (0..sid_filter.len())
            .map(|i| sid_filter.get(i).unwrap_or(-1))
            .filter(|&sid| sid >= 0)
            .collect();
        let parsed = if self.structure_store.ready {
            self.structure_store
                .corridor_specs(&filter, filter.is_empty())
        } else {
            corridor_specs_from_array(specs)
        };
        let result = kernel.sync_bridge_corridors(&parsed, force_full);
        if self.structure_store.ready {
            for (sid, built) in &result.synced_updates {
                self.structure_store.patch_corridor_synced(*sid, *built);
            }
        }
        world_edit_result_dict(&result)
    }

    #[func]
    fn structure_store_ready(&self) -> bool {
        self.structure_store.ready
    }

    #[func]
    fn sync_structure_store(
        &mut self,
        structures: Array<Variant>,
        corridors: Array<Variant>,
    ) -> bool {
        let mut records = Vec::new();
        for i in 0..structures.len() {
            let Some(v) = structures.get(i) else {
                continue;
            };
            let Ok(spec) = v.try_to::<GdDictionary>() else {
                continue;
            };
            if let Some(record) = structure_record_from_dict(&spec) {
                records.push(record);
            }
        }
        let mut persisted = Vec::new();
        for i in 0..corridors.len() {
            let Some(v) = corridors.get(i) else {
                continue;
            };
            let Ok(spec) = v.try_to::<GdDictionary>() else {
                continue;
            };
            if let Some(corridor) = persisted_corridor_from_dict(i, &spec) {
                persisted.push(corridor);
            }
        }
        self.structure_store.rebuild_from_records(records, persisted);
        true
    }

    #[func]
    fn structure_store_upsert(&mut self, spec: GdDictionary) -> bool {
        let Some(mut record) = structure_record_from_dict(&spec) else {
            return false;
        };
        let v = self.domain_book.touch(DomainId::Structures);
        record.version = v;
        self.structure_store.upsert(record);
        true
    }

    #[func]
    fn structure_store_remove(&mut self, sid: i32) {
        if self.structure_store.structures.contains_key(&sid) {
            self.structure_store.remove(sid);
            let _ = self.domain_book.touch(DomainId::Structures);
        }
    }

    #[func]
    fn structure_store_patch_path_built(&mut self, sid: i32, path_built: f32) -> bool {
        if !self.structure_store.patch_path_built(sid, path_built) {
            return false;
        }
        let v = self.domain_book.touch(DomainId::Structures);
        if let Some(st) = self.structure_store.structures.get_mut(&sid) {
            st.version = v;
        }
        true
    }

    #[func]
    fn structure_store_patch_state(
        &mut self,
        sid: i32,
        state: GString,
        path_built: f32,
    ) -> bool {
        let pb = if path_built >= 0.0 {
            Some(path_built)
        } else {
            None
        };
        if !self.structure_store.patch_state(
            sid,
            state_from_str(state.to_string().as_str()),
            pb,
        ) {
            return false;
        }
        let v = self.domain_book.touch(DomainId::Structures);
        if let Some(st) = self.structure_store.structures.get_mut(&sid) {
            st.version = v;
        }
        true
    }

    #[func]
    fn structure_connecting_count(&self, team: u8) -> i32 {
        self.structure_store.connecting_count(team)
    }

    #[func]
    fn get_structure_snapshot(&self) -> GdDictionary {
        let mut structures: Array<Variant> = Array::new();
        let mut ids: Vec<i32> = self.structure_store.structures.keys().copied().collect();
        ids.sort_unstable();
        for id in ids {
            let Some(record) = self.structure_store.structures.get(&id) else {
                continue;
            };
            let entry = structure_record_to_dict(record);
            structures.push(&entry);
        }
        let mut corridor_synced: Array<Variant> = Array::new();
        for corridor in &self.structure_store.persisted_corridors {
            let mut entry = GdDictionary::new();
            entry.set("slot", corridor.slot as i32);
            entry.set("corridor_synced_built", corridor.corridor_synced_built);
            corridor_synced.push(&entry);
        }
        let mut out = GdDictionary::new();
        out.set("structures", &structures);
        out.set("corridor_synced", &corridor_synced);
        out
    }

    /// SCD1: domain high-water epoch for Godot last_version tracking.
    #[func]
    fn scd1_domain_epoch(&self, domain: GString) -> i64 {
        DomainId::from_str(domain.to_string().as_str())
            .map(|d| self.domain_book.epoch(d) as i64)
            .unwrap_or(0)
    }

    #[func]
    fn scd1_sim_generation(&self) -> i64 {
        self.domain_book.sim_generation as i64
    }

    /// Pure allow-list decision for full pull (Policy 2). `hard_error` forces HardError.
    #[func]
    fn scd1_decide_full_pull(
        &self,
        last_version: i64,
        domain: GString,
        client_sim_gen: i64,
        hard_error: bool,
    ) -> GString {
        let d = match DomainId::from_str(domain.to_string().as_str()) {
            Some(x) => x,
            None => return GString::from(""),
        };
        let high = self.domain_book.epoch(d);
        let last = last_version.max(0) as u64;
        let cgen = client_sim_gen.max(0) as u64;
        match decide_full_pull(last, high, cgen, self.domain_book.sim_generation, hard_error) {
            Some(r) => GString::from(r.as_str()),
            None => GString::from(""),
        }
    }

    /// Policy 3: whether a full pull is allowed now (3s cooldown).
    #[func]
    fn scd1_full_pull_cooldown_ok(&self) -> bool {
        full_pull_allowed_by_cooldown(self.last_full_pull_at, Instant::now())
    }

    /// Record that a full pull ran (starts cooldown). Logs FULL_RESYNC (Policy 6).
    #[func]
    fn scd1_note_full_pull(&mut self, reason: GString) {
        self.last_full_pull_at = Some(Instant::now());
        godot_print!(
            "FULL_RESYNC reason={} cooldown_secs={}",
            reason,
            FULL_PULL_COOLDOWN.as_secs()
        );
    }

    /// SCD1 domain pull: full current rows with version > last_version (or all if full=true).
    /// Returns { high_water, empty, full, sim_generation, rows|domain-specific packs }.
    #[func]
    fn pull_domain_since(&mut self, domain: GString, last_version: i64, force_full: bool) -> GdDictionary {
        let mut out = GdDictionary::new();
        let Some(d) = DomainId::from_str(domain.to_string().as_str()) else {
            out.set("error", true);
            out.set("empty", true);
            out.set("high_water", 0i64);
            return out;
        };
        let high = self.domain_book.epoch(d);
        let last = last_version.max(0) as u64;
        out.set("sim_generation", self.domain_book.sim_generation as i64);
        out.set("high_water", high as i64);
        out.set("domain", &GString::from(d.as_str()));
        let full = force_full || last == 0;
        out.set("full", full);
        if !full && last >= high {
            out.set("empty", true);
            return out;
        }
        out.set("empty", false);
        match d {
            DomainId::Structures => {
                let mut rows: Array<Variant> = Array::new();
                let mut ids: Vec<i32> = self.structure_store.structures.keys().copied().collect();
                ids.sort_unstable();
                for id in ids {
                    let Some(record) = self.structure_store.structures.get(&id) else {
                        continue;
                    };
                    if !full && record.version <= last {
                        continue;
                    }
                    let entry = structure_record_to_dict(record);
                    rows.push(&entry);
                }
                // Persisted corridors for view (landing pins / ribbons).
                let mut corridors: Array<Variant> = Array::new();
                for (i, c) in self.structure_store.persisted_corridors.iter().enumerate() {
                    let mut entry = GdDictionary::new();
                    entry.set("id", -(i as i32 + 1));
                    entry.set("team", c.team);
                    entry.set("path_keys", &vec_to_packed_i32(&c.path_keys));
                    entry.set("kind", &GString::from("corridor_link"));
                    entry.set("state", &GString::from("active"));
                    if let Some(&pk) = c.path_keys.last() {
                        let gw = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(1).max(1);
                        entry.set("gx", pk % gw);
                        entry.set("gy", pk / gw);
                    }
                    corridors.push(&entry);
                }
                out.set("rows", &rows);
                out.set("bridge_corridors", &corridors);
                out.set("empty", rows.is_empty() && !full);
            }
            DomainId::Territory => {
                let Some(kernel) = self.kernel.as_ref() else {
                    out.set("empty", true);
                    return out;
                };
                if self.owner_cell_version.len() != kernel.owners.len() {
                    // Safety: treat as full owners dump.
                }
                let mut idxs: Vec<i32> = Vec::new();
                let mut vals: Vec<u8> = Vec::new();
                if full {
                    for (i, &o) in kernel.owners.iter().enumerate() {
                        idxs.push(i as i32);
                        vals.push(o);
                    }
                } else {
                    let n = kernel.owners.len().min(self.owner_cell_version.len());
                    for i in 0..n {
                        if self.owner_cell_version[i] > last {
                            idxs.push(i as i32);
                            vals.push(kernel.owners[i]);
                        }
                    }
                }
                out.set("indices", &vec_to_packed_i32(&idxs));
                out.set("owners", &vec_to_packed_byte(&vals));
                out.set("friendly_tiles", kernel.friendly_tiles);
                out.set("hostile_tiles", kernel.hostile_tiles);
                out.set("empty", idxs.is_empty());
            }
            DomainId::Roads => {
                let mask_f = self.logistics_layer.built_mask(1);
                let mask_h = self.logistics_layer.built_mask(2);
                let mut idxs: Vec<i32> = Vec::new();
                let mut teams: Vec<u8> = Vec::new();
                if full {
                    for i in 0..mask_f.len().max(mask_h.len()) {
                        let bf = if i < mask_f.len() { mask_f[i] } else { 0 };
                        let bh = if i < mask_h.len() { mask_h[i] } else { 0 };
                        if bf != 0 || bh != 0 {
                            idxs.push(i as i32);
                            teams.push(if bf != 0 { 1 } else { 2 });
                        }
                    }
                } else {
                    let n = self.road_cell_version.len();
                    for i in 0..n {
                        if self.road_cell_version[i] <= last {
                            continue;
                        }
                        let bf = if i < mask_f.len() { mask_f[i] } else { 0 };
                        let bh = if i < mask_h.len() { mask_h[i] } else { 0 };
                        if bf != 0 || bh != 0 {
                            idxs.push(i as i32);
                            teams.push(if bf != 0 { 1 } else { 2 });
                        }
                    }
                }
                out.set("indices", &vec_to_packed_i32(&idxs));
                out.set("teams", &vec_to_packed_byte(&teams));
                out.set("empty", idxs.is_empty());
            }
            // Agents/bombers are living-set domains: Godot replaces the full visual pool on apply.
            // When the domain high-water advances, return *all* living units — not only rows with
            // version > last. Filtering by row version drops stationary units and looks like teleport.
            // empty=false whenever high > last (even with 0 living) so deaths clear the pool.
            DomainId::Agents => {
                let mut rows: Array<Variant> = Array::new();
                if let Some(layer) = self.agents.as_ref() {
                    for a in &layer.agents {
                        if a.hp <= 0.0 {
                            continue;
                        }
                        let mut e = GdDictionary::new();
                        e.set("id", a.id as i32);
                        e.set("team", a.team);
                        e.set("gx", a.gx);
                        e.set("gy", a.gy);
                        e.set("hp", a.hp);
                        e.set("version", a.version as i64);
                        rows.push(&e);
                    }
                }
                out.set("rows", &rows);
                out.set("empty", rows.is_empty() && high <= last);
            }
            DomainId::Bombers => {
                let mut rows: Array<Variant> = Array::new();
                let mut bomb_gx = PackedInt32Array::new();
                let mut bomb_gy = PackedInt32Array::new();
                let mut bomb_teams = PackedByteArray::new();
                if let Some(layer) = self.bombers.as_mut() {
                    for b in &layer.bombers {
                        if b.hp <= 0.0 {
                            continue;
                        }
                        let mut e = GdDictionary::new();
                        e.set("id", b.id as i32);
                        e.set("team", b.team);
                        e.set("gx", b.gx);
                        e.set("gy", b.gy);
                        e.set("hp", b.hp);
                        e.set("search_scope", b.search_expand_limit as i32);
                        e.set("version", b.version as i64);
                        rows.push(&e);
                    }
                    // One-shot attack FX: drain pending drops with this living-set pull.
                    let events = layer.take_bomb_events();
                    for ev in &events {
                        bomb_gx.push(ev.gx);
                        bomb_gy.push(ev.gy);
                        bomb_teams.push(ev.team);
                    }
                }
                out.set("rows", &rows);
                out.set("bomb_gx", &bomb_gx);
                out.set("bomb_gy", &bomb_gy);
                out.set("bomb_teams", &bomb_teams);
                // Domain advance or pending bomb FX both require apply (may clear living set).
                out.set(
                    "empty",
                    rows.is_empty() && bomb_teams.is_empty() && high <= last,
                );
            }
            DomainId::Wallet => {
                if !full && self.wallet_version <= last {
                    out.set("empty", true);
                    return out;
                }
                out.set(
                    "friendly",
                    &PackedFloat32Array::from(&self.resource_wallet.friendly[..]),
                );
                out.set(
                    "hostile",
                    &PackedFloat32Array::from(&self.resource_wallet.hostile[..]),
                );
                out.set("version", self.wallet_version as i64);
                out.set("empty", false);
            }
        }
        out
    }

    #[func]
    fn configure_content_tables(&mut self, config: GdDictionary) {
        let build_sec: Vec<f32> = config
            .get("structure_build_sec")
            .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0.0)).collect())
            .unwrap_or_default();
        let max_health: Vec<f32> = config
            .get("structure_max_health")
            .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0.0)).collect())
            .unwrap_or_default();
        let logistics_drain: Vec<f32> = config
            .get("structure_logistics_drain")
            .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0.0)).collect())
            .unwrap_or_default();
        let spawn_interval: Vec<f32> = config
            .get("structure_spawn_interval")
            .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0.0)).collect())
            .unwrap_or_default();
        let spawn_max_active: Vec<i32> = config
            .get("structure_spawn_max_active")
            .and_then(|v| v.try_to::<PackedInt32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0)).collect())
            .unwrap_or_default();
        let spawn_unit: Vec<i32> = config
            .get("structure_spawn_unit")
            .and_then(|v| v.try_to::<PackedInt32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(-1)).collect())
            .unwrap_or_default();
        let spawn_resources: Vec<f32> = config
            .get("structure_spawn_resources")
            .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0.0)).collect())
            .unwrap_or_default();
        let unit_global_cap: Vec<i32> = config
            .get("unit_global_cap")
            .and_then(|v| v.try_to::<PackedInt32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0)).collect())
            .unwrap_or_default();
        let unit_upkeep: Vec<f32> = config
            .get("unit_upkeep_resources")
            .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
            .map(|p| (0..p.len()).map(|i| p.get(i).unwrap_or(0.0)).collect())
            .unwrap_or_default();

        let mut tables = ContentTables::default();
        let defaults = tables.clone();
        for kind in 0..MAX_KINDS {
            let mut res = [0.0f32; RESOURCE_SLOTS];
            for r in 0..RESOURCE_SLOTS {
                let idx = kind * RESOURCE_SLOTS + r;
                res[r] = f32_at(&spawn_resources, idx, 0.0);
            }
            fill_structure_row(
                &mut tables,
                kind,
                f32_at(&build_sec, kind, defaults.structure_build_sec[kind]),
                f32_at(&max_health, kind, defaults.structure_max_health[kind]),
                f32_at(
                    &logistics_drain,
                    kind,
                    defaults.structure_logistics_drain[kind],
                ),
                f32_at(
                    &spawn_interval,
                    kind,
                    defaults.structure_spawn_interval[kind],
                ),
                u32_at(&spawn_max_active, kind, defaults.structure_spawn_max_active[kind]),
                i32_at(&spawn_unit, kind, defaults.structure_spawn_unit[kind]),
                res,
            );
        }
        for unit in 0..economy::MAX_UNITS {
            tables.unit_global_cap[unit] =
                u32_at(&unit_global_cap, unit, defaults.unit_global_cap[unit]);
            for r in 0..RESOURCE_SLOTS {
                let idx = unit * RESOURCE_SLOTS + r;
                tables.unit_upkeep_resources[unit][r] =
                    f32_at(&unit_upkeep, idx, defaults.unit_upkeep_resources[unit][r]);
            }
        }
        self.content_tables = tables;

        let road_cells_per_sec: f32 = config
            .get("road_cells_per_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.logistics_cfg.road_cells_per_sec);
        let outpost_enemy_dps: f32 = config
            .get("outpost_enemy_dps")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.world_session_cfg.outpost_enemy_dps);

        self.content_tables
            .apply_to_logistics(&mut self.logistics_cfg, road_cells_per_sec);
        self.logistics_cfg.reconcile_cells_per_frame = clamp_reconcile_budget(
            config
                .get("reconcile_cells_per_frame")
                .and_then(|v| v.try_to::<i32>().ok())
                .unwrap_or(self.logistics_cfg.reconcile_cells_per_frame as i32)
                .max(0) as usize,
        );
        self.logistics_cfg.full_recal_interval_sec = config
            .get("full_recal_interval_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.logistics_cfg.full_recal_interval_sec);
        self.logistics_cfg.placement_heat_decay_per_sec = config
            .get("placement_heat_decay_per_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.logistics_cfg.placement_heat_decay_per_sec);
        self.logistics_cfg.burst_base = config
            .get("burst_base")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.logistics_cfg.burst_base);
        self.logistics_cfg.burst_ratio = config
            .get("burst_ratio")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.logistics_cfg.burst_ratio);
        self.logistics_cfg.strain_sensitivity = config
            .get("strain_sensitivity")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.logistics_cfg.strain_sensitivity);

        let upkeep_deficit_dps: f32 = config
            .get("soldier_upkeep_deficit_dps")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(self.world_session_cfg.upkeep_deficit_dps);

        self.content_tables
            .apply_to_world_session(&mut self.world_session_cfg, outpost_enemy_dps, upkeep_deficit_dps);
    }

    #[func]
    fn configure_world_session(&mut self, config: GdDictionary, enabled: bool) {
        self.world_session_cfg = WorldSessionConfig {
            outpost_build_sec: config
                .get("outpost_build_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(5.0),
            barracks_build_sec: config
                .get("barracks_build_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(60.0),
            outpost_max_health: config
                .get("outpost_max_health")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(10.0),
            outpost_enemy_dps: config
                .get("outpost_enemy_dps")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(3.0),
            barracks_spawn_interval: config
                .get("barracks_spawn_interval")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(10.0),
            barracks_max_active: config
                .get("barracks_max_active")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(5),
            global_soldier_cap: config
                .get("global_soldier_cap")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(100),
            soldier_spawn_cost: config
                .get("soldier_spawn_cost")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(3.0),
            hangar_build_sec: config
                .get("hangar_build_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(60.0),
            hangar_spawn_interval: config
                .get("hangar_spawn_interval")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(10.0),
            hangar_max_active: config
                .get("hangar_max_active")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(5),
            global_bomber_cap: config
                .get("global_bomber_cap")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(100),
            bomber_spawn_cost: config
                .get("bomber_spawn_cost")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(3.0),
            soldier_upkeep_per_sec: config
                .get("soldier_upkeep_per_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(self.world_session_cfg.soldier_upkeep_per_sec),
            upkeep_deficit_dps: config
                .get("upkeep_deficit_dps")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(self.world_session_cfg.upkeep_deficit_dps),
        };
        self.world_session_enabled = enabled;
    }

    #[func]
    fn world_session_enabled(&self) -> bool {
        self.world_session_enabled
            && self.structure_store.ready
            && self.kernel.is_some()
    }

    #[func]
    fn world_session_tick(&mut self, dt: f32, friendly_aurelium: f32) -> GdDictionary {
        if !self.world_session_enabled() {
            return GdDictionary::new();
        }
        let Some(kernel) = self.kernel.as_ref() else {
            return GdDictionary::new();
        };
        let cfg = self.world_session_cfg.clone();
        let tables = self.content_tables.clone();
        let agents_ptr = self.agents.as_mut();
        let bombers_ptr = self.bombers.as_mut();
        let (events, friendly_aurelium_out) = if self.resource_wallet_enabled {
            // Snapshot so any upkeep/spawn/spend mutates bump wallet SCD1 high-water.
            let pre_f = self.resource_wallet.friendly;
            let pre_h = self.resource_wallet.hostile;
            let events = tick_world_session(
                kernel,
                &mut self.structure_store,
                agents_ptr,
                bombers_ptr,
                dt,
                Some(&mut self.resource_wallet),
                None,
                &tables,
                &cfg,
            );
            if pre_f != self.resource_wallet.friendly || pre_h != self.resource_wallet.hostile {
                self.wallet_version = self.domain_book.touch(DomainId::Wallet);
            }
            (events, self.resource_wallet.friendly[0])
        } else {
            let mut wallet_au = friendly_aurelium;
            let events = tick_world_session(
                kernel,
                &mut self.structure_store,
                agents_ptr,
                bombers_ptr,
                dt,
                None,
                Some(&mut wallet_au),
                &tables,
                &cfg,
            );
            (events, wallet_au)
        };
        // SCD1: stamp structure versions for activates / destroys so pulls see BUILDING→ACTIVE.
        if !events.activated_sids.is_empty()
            || !events.destroyed_sids.is_empty()
            || events.marker_dirty
        {
            let sv = self.domain_book.touch(DomainId::Structures);
            for &sid in &events.activated_sids {
                if let Some(st) = self.structure_store.structures.get_mut(&sid) {
                    st.version = sv;
                }
            }
            for &sid in &events.activated_spawner_sids {
                if let Some(st) = self.structure_store.structures.get_mut(&sid) {
                    st.version = sv;
                }
            }
        }
        // Living-set domains: spawn must advance high-water so the next pull includes new units.
        if !events.spawned_barracks_sids.is_empty() {
            let av = self.domain_book.touch(DomainId::Agents);
            if let Some(agents) = self.agents.as_mut() {
                for a in &mut agents.agents {
                    if a.version == 0 {
                        a.version = av;
                    }
                }
            }
        }
        if !events.spawned_hangar_sids.is_empty() {
            let bv = self.domain_book.touch(DomainId::Bombers);
            if let Some(bombers) = self.bombers.as_mut() {
                for b in &mut bombers.bombers {
                    if b.version == 0 {
                        b.version = bv;
                    }
                }
            }
        }
        world_session_events_dict(&events, friendly_aurelium_out)
    }

    /// Configure logistics network (sole live road/path_built authority — A6/A7/C8).
    /// Despite the historical name, this does **not** enable builder-bot path growth.
    /// `builder_layer.legacy_path_growth_enabled` stays false; only logistics advances path_built.
    #[func]
    fn configure_builders(&mut self, config: GdDictionary, enabled: bool) {
        self.logistics_cfg = LogisticsConfig {
            road_cells_per_sec: config
                .get("road_cells_per_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(1.0),
            outpost_build_sec: config
                .get("outpost_build_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(5.0),
            barracks_build_sec: config
                .get("barracks_build_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(60.0),
            hangar_build_sec: config
                .get("hangar_build_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(60.0),
            outpost_max_health: config
                .get("outpost_max_health")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(10.0),
            reconcile_cells_per_frame: clamp_reconcile_budget(
                config
                    .get("reconcile_cells_per_frame")
                    .and_then(|v| v.try_to::<i32>().ok())
                    .unwrap_or(logistics::LOGISTICS_RECONCILE_CELLS_PER_FRAME_DEFAULT as i32)
                    .max(0) as usize,
            ),
            full_recal_interval_sec: config
                .get("full_recal_interval_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(25.0),
            placement_heat_decay_per_sec: config
                .get("placement_heat_decay_per_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.85),
            burst_base: config
                .get("burst_base")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.02),
            burst_ratio: config
                .get("burst_ratio")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(1.35),
            structure_drain_spawner: config
                .get("structure_drain_spawner")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.04),
            structure_drain_barracks: config
                .get("structure_drain_barracks")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.06),
            structure_drain_hangar: config
                .get("structure_drain_hangar")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.06),
            structure_drain_corridor: config
                .get("structure_drain_corridor")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.03),
            strain_sensitivity: config
                .get("strain_sensitivity")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(1.0),
        };
        self.player_home_gx = config
            .get("player_home_gx")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        self.player_home_gy = config
            .get("player_home_gy")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        self.enemy_home_gx = config
            .get("enemy_home_gx")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        self.enemy_home_gy = config
            .get("enemy_home_gy")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        // Logistics sole authority — do not dual-step builders for path_built (A6/A7/C8).
        self.logistics_enabled = enabled;
        self.builder_enabled = false;
        self.builder_layer.legacy_path_growth_enabled = false;
        if self.logistics_enabled {
            self.logistics_layer.player_home = (self.player_home_gx, self.player_home_gy);
            self.logistics_layer.enemy_home = (self.enemy_home_gx, self.enemy_home_gy);
            if let Some(kernel) = &self.kernel {
                let tile_count = kernel.tile_count;
                self.logistics_layer.configure(
                    tile_count,
                    kernel.grid_w,
                    kernel.grid_h,
                    &self.logistics_cfg,
                );
                self.logistics_layer
                    .seed_from_store(&self.structure_store, &self.logistics_cfg);
            }
        }
    }

    #[func]
    fn builder_authority_enabled(&self) -> bool {
        // Name is historical; reports logistics authority readiness.
        self.logistics_enabled && self.kernel.is_some()
    }

    fn ensure_logistics_network(&mut self) {
        if self.logistics_layer.is_configured() {
            return;
        }
        let Some(kernel) = self.kernel.as_ref() else {
            return;
        };
        self.logistics_layer.player_home = (self.player_home_gx, self.player_home_gy);
        self.logistics_layer.enemy_home = (self.enemy_home_gx, self.enemy_home_gy);
        self.logistics_layer.configure(
            kernel.tile_count,
            kernel.grid_w,
            kernel.grid_h,
            &self.logistics_cfg,
        );
        if self.structure_store.ready {
            self.logistics_layer
                .seed_from_store(&self.structure_store, &self.logistics_cfg);
        }
    }

    #[func]
    fn builder_enqueue_job(&mut self, sid: i32, team: u8) {
        if sid < 0 || !self.logistics_enabled {
            return;
        }
        self.ensure_logistics_network();
        let grid_w = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(0);
        self.logistics_layer.register_terminal(
            sid,
            &mut self.structure_store,
            team,
            grid_w,
            &self.logistics_cfg,
        );
    }

    #[func]
    fn builder_cancel_job(&mut self, sid: i32) {
        if sid < 0 {
            return;
        }
        let Some(st) = self.structure_store.structures.get(&sid) else {
            return;
        };
        let team = st.team;
        self.logistics_layer.unregister_terminal(sid, &self.structure_store, team);
    }

    #[func]
    fn builder_assign_jobs(&mut self, _team_filter: i32) {
        // Logistics network has no idle-bot job assignment.
    }

    /// Advance logistics road growth (sole path_built authority under live).
    /// Never dual-steps the legacy builder bot layer (A6/A7/C8).
    #[func]
    fn builder_step(&mut self, dt: f32) -> GdDictionary {
        if !self.builder_authority_enabled() {
            return GdDictionary::new();
        }
        // Guard: builders must not advance path_built while logistics is active.
        debug_assert!(!self.builder_layer.legacy_path_growth_enabled);
        self.ensure_logistics_network();
        let (grid_w, grid_h) = self
            .kernel
            .as_ref()
            .map(|k| (k.grid_w, k.grid_h))
            .unwrap_or((0, 0));
        let events = self.logistics_layer.step_frame(
            dt,
            &mut self.structure_store,
            grid_w,
            grid_h,
            &self.logistics_cfg,
        );
        if let Some(kernel) = self.kernel.as_mut() {
            kernel.logistics_friendly_output_mult = events.friendly_output_mult;
            kernel.logistics_hostile_output_mult = events.hostile_output_mult;
        }
        // SCD1: stamp structure + road domain versions from logistics writes.
        if !events.cell_arrivals.is_empty()
            || !events.path_completions.is_empty()
            || !events.new_built_cells.is_empty()
        {
            if !events.new_built_cells.is_empty() {
                let rv = self.domain_book.touch(DomainId::Roads);
                for &key in &events.new_built_cells {
                    if key >= 0 && (key as usize) < self.road_cell_version.len() {
                        self.road_cell_version[key as usize] = rv;
                    }
                }
            }
            if !events.cell_arrivals.is_empty() || !events.path_completions.is_empty() {
                let sv = self.domain_book.touch(DomainId::Structures);
                for ev in &events.cell_arrivals {
                    if let Some(st) = self.structure_store.structures.get_mut(&ev.sid) {
                        st.version = sv;
                    }
                }
                for ev in &events.path_completions {
                    if let Some(st) = self.structure_store.structures.get_mut(&ev.sid) {
                        st.version = sv;
                    }
                }
            }
        }
        // Legacy txn feed (not live SCD1 path).
        self.presentation_txn.merge_logistics(&events);
        self.presentation_txn
            .fill_path_built_from_arrivals(&self.structure_store, &events);
        logistics_step_events_dict(&events)
    }

    /// Drain the presentation transaction log for Godot visuals.
    /// Main tables (owners / structures / logistics) stay in Rust; this is the change feed only.
    #[func]
    fn pull_presentation_txn(&mut self, include_full_structure_snapshot: bool) -> GdDictionary {
        // Fold any remaining owner dirty (if advance did not already stash via sync_owners_delta_into_txn).
        if let Some(kernel) = self.kernel.as_mut() {
            let (idx, vals) = kernel.take_owner_dirty();
            let (display_idx, display_vals) = kernel.take_display_dirty();
            if !idx.is_empty() || !display_idx.is_empty() {
                self.presentation_txn.push_owner_delta(
                    idx,
                    vals,
                    display_idx,
                    display_vals,
                    kernel.friendly_tiles,
                    kernel.hostile_tiles,
                );
            } else {
                self.presentation_txn.friendly_tiles = kernel.friendly_tiles;
                self.presentation_txn.hostile_tiles = kernel.hostile_tiles;
            }
        }
        let mut out = self.presentation_txn.take().to_dict();
        if include_full_structure_snapshot && self.structure_store.ready {
            // Rare: full table read for placement/debug — not the per-frame path.
            out.set("structures", &self.get_structure_snapshot());
        }
        out
    }

    #[func]
    fn get_network_built_mask(&self, team: u8) -> PackedByteArray {
        vec_to_packed_byte(&self.logistics_layer.built_mask(team))
    }

    #[func]
    fn get_logistics_strain(&self) -> GdDictionary {
        let mut out = GdDictionary::new();
        let friendly_mult = self
            .kernel
            .as_ref()
            .map(|k| k.logistics_friendly_output_mult)
            .unwrap_or(1.0);
        let hostile_mult = self
            .kernel
            .as_ref()
            .map(|k| k.logistics_hostile_output_mult)
            .unwrap_or(1.0);
        out.set("friendly_output_mult", friendly_mult);
        out.set("hostile_output_mult", hostile_mult);
        out
    }

    #[func]
    fn get_builder_visual_snapshot(&self) -> GdDictionary {
        GdDictionary::new()
    }

    #[func]
    fn configure_resource_wallet(&mut self, enabled: bool) {
        self.resource_wallet_enabled = enabled;
    }

    #[func]
    fn resource_wallet_enabled(&self) -> bool {
        self.resource_wallet_enabled
    }

    #[func]
    fn sync_resource_balances(
        &mut self,
        friendly: PackedFloat32Array,
        hostile: PackedFloat32Array,
    ) {
        self.resource_wallet.friendly = f32_triple_from_array(&friendly);
        self.resource_wallet.hostile = f32_triple_from_array(&hostile);
        self.wallet_version = self.domain_book.touch(DomainId::Wallet);
    }

    #[func]
    fn apply_resource_tick_delta(
        &mut self,
        friendly_delta: PackedFloat32Array,
        hostile_delta: PackedFloat32Array,
    ) {
        if !self.resource_wallet_enabled {
            return;
        }
        self.resource_wallet
            .apply_delta(&f32_triple_from_array(&friendly_delta), &f32_triple_from_array(&hostile_delta));
        // SCD1: any wallet mutation must bump domain high-water so pulls see income/spend.
        self.wallet_version = self.domain_book.touch(DomainId::Wallet);
    }

    #[func]
    fn get_resource_balances(&self) -> GdDictionary {
        let mut out = GdDictionary::new();
        out.set(
            "friendly",
            &PackedFloat32Array::from(&self.resource_wallet.friendly[..]),
        );
        out.set(
            "hostile",
            &PackedFloat32Array::from(&self.resource_wallet.hostile[..]),
        );
        out
    }

    #[func]
    fn structure_store_enter_building(
        &mut self,
        sid: i32,
        build_remaining: f32,
        max_health: f32,
    ) -> bool {
        self.structure_store
            .enter_building_phase(sid, build_remaining, max_health)
    }

    #[func]
    fn world_conquest_advance_rounds(
        &mut self,
        n: i32,
        friendly_deficit_dps: f32,
        hostile_deficit_dps: f32,
    ) -> GdDictionary {
        if self.agents_enabled {
            if let Some(agents) = self.agents.as_mut() {
                agents.friendly_deficit_dps = friendly_deficit_dps.max(0.0);
                agents.hostile_deficit_dps = hostile_deficit_dps.max(0.0);
            }
        }
        self.advance_rounds(n);
        // Owner dirty stays in the kernel until pull_presentation_txn (or legacy sync_owners_delta).
        // Still return a sync dict for backends that mirror into GDScript tile_control.
        self.sync_owners_delta_into_txn()
    }

    /// Take owner dirty from the kernel, stash into the presentation txn, and return the same shape
    /// as sync_owners_delta (for BattleTerritoryRustBackend last_* buffers).
    fn sync_owners_delta_into_txn(&mut self) -> GdDictionary {
        let Some(kernel) = self.kernel.as_mut() else {
            return GdDictionary::new();
        };
        let (idx, vals) = kernel.take_owner_dirty();
        let (display_idx, display_vals) = kernel.take_display_dirty();
        let friendly = kernel.friendly_tiles;
        let hostile = kernel.hostile_tiles;
        self.presentation_txn.push_owner_delta(
            idx.clone(),
            vals.clone(),
            display_idx.clone(),
            display_vals.clone(),
            friendly,
            hostile,
        );
        let mut out = GdDictionary::new();
        out.set("owner_indices", &vec_to_packed_i32(&idx));
        out.set("owner_values", &vec_to_packed_byte(&vals));
        out.set("display_indices", &vec_to_packed_i32(&display_idx));
        out.set("display_r8", &vec_to_packed_byte(&display_vals));
        out.set("friendly_tiles", friendly);
        out.set("hostile_tiles", hostile);
        out
    }

    #[func]
    fn get_world_edit_mirror(&self) -> GdDictionary {
        let Some(kernel) = self.kernel.as_ref() else {
            return GdDictionary::new();
        };
        let mut d = GdDictionary::new();
        d.set(
            "friendly_reachable",
            &vec_to_packed_byte(kernel.friendly_reachable_mask()),
        );
        d.set(
            "hostile_reachable",
            &vec_to_packed_byte(kernel.hostile_reachable_mask()),
        );
        d.set(
            "friendly_bridge_reachable",
            &vec_to_packed_byte(kernel.friendly_bridge_mask()),
        );
        d.set(
            "hostile_bridge_reachable",
            &vec_to_packed_byte(kernel.hostile_bridge_mask()),
        );
        d.set(
            "friendly_corridor_land",
            &vec_to_packed_byte(kernel.friendly_corridor_mask()),
        );
        d.set(
            "hostile_corridor_land",
            &vec_to_packed_byte(kernel.hostile_corridor_mask()),
        );
        d
    }

    #[func]
    fn sync_pressures_from(
        &mut self,
        pressure_friendly: PackedFloat32Array,
        pressure_hostile: PackedFloat32Array,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        kernel.sync_pressures_from(
            packed_f32_to_vec(&pressure_friendly),
            packed_f32_to_vec(&pressure_hostile),
        );
    }

    #[func]
    fn update_spawners(
        &mut self,
        spawner_teams: PackedByteArray,
        spawner_gx: PackedInt32Array,
        spawner_gy: PackedInt32Array,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        let count = spawner_teams
            .len()
            .min(spawner_gx.len())
            .min(spawner_gy.len());
        kernel.spawners.clear();
        for i in 0..count {
            kernel.spawners.push(Spawner {
                team: spawner_teams.get(i).unwrap_or(0),
                gx: spawner_gx.get(i).unwrap_or(-1),
                gy: spawner_gy.get(i).unwrap_or(-1),
            });
        }
    }

    #[func]
    fn configure_agents(&mut self, config: GdDictionary) -> bool {
        let global_cap: u32 = config
            .get("global_cap")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(100);
        let per_barracks_cap: u32 = config
            .get("per_barracks_cap")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(5);
        let max_hp: f32 = config
            .get("max_hp")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(10.0);
        let move_cells_per_sec: f32 = config
            .get("move_cells_per_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1.0);
        let infra_move_mult: f32 = config
            .get("infra_move_mult")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(3.0);
        let aura_pressure: f32 = config
            .get("aura_pressure")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0.12);
        let shoot_erode_per_sec: f32 = config
            .get("shoot_erode_per_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0.4);
        let orphan_dps: f32 = config
            .get("orphan_dps")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1.0);
        let step_dt: f32 = config
            .get("step_dt")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1.0 / 14.0);
        let replans_per_tick: u32 = config
            .get("replans_per_tick")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(6);
        let replan_fallback_rounds: i32 = config
            .get("replan_fallback_rounds")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(42);
        let agent_cfg = AgentConfig {
            global_cap,
            per_barracks_cap,
            max_hp,
            move_cells_per_sec,
            infra_move_mult,
            aura_pressure,
            shoot_erode_per_step: shoot_erode_per_sec * step_dt,
            orphan_dps,
            step_dt,
            replans_per_tick,
            replan_fallback_rounds,
        };
        self.agents = Some(AgentLayer::new(agent_cfg));
        self.agents_enabled = true;
        true
    }

    #[func]
    fn configure_bombers(&mut self, config: GdDictionary) -> bool {
        let global_cap: u32 = config
            .get("global_cap")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(100);
        let per_hangar_cap: u32 = config
            .get("per_hangar_cap")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(5);
        let max_hp: f32 = config
            .get("max_hp")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(100.0);
        let move_cells_per_sec: f32 = config
            .get("move_cells_per_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(2.0);
        let infra_move_mult: f32 = config
            .get("infra_move_mult")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(3.0);
        let bomb_power: f32 = config
            .get("bomb_power")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1000.0);
        let bomb_interval_sec: f32 = config
            .get("bomb_interval_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(10.0);
        let orphan_dps: f32 = config
            .get("orphan_dps")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1.0);
        let step_dt: f32 = config
            .get("step_dt")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1.0 / 14.0);
        let replans_per_tick: u32 = config
            .get("replans_per_tick")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(6);
        let replan_fallback_rounds: i32 = config
            .get("replan_fallback_rounds")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(42);
        let search_expand_initial: usize = config
            .get("search_expand_initial")
            .and_then(|v| v.try_to::<i32>().ok())
            .map(|v| v.max(1) as usize)
            .unwrap_or(5_000);
        let search_expand_step: usize = config
            .get("search_expand_step")
            .and_then(|v| v.try_to::<i32>().ok())
            .map(|v| v.max(1) as usize)
            .unwrap_or(5_000);
        let search_expand_max: usize = config
            .get("search_expand_max")
            .and_then(|v| v.try_to::<i32>().ok())
            .map(|v| v.max(1) as usize)
            .unwrap_or(40_000);
        let plan_reeval_sec: f32 = config
            .get("plan_reeval_sec")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(25.0);
        let bomber_cfg = BomberConfig {
            global_cap,
            per_hangar_cap,
            max_hp,
            move_cells_per_sec,
            infra_move_mult,
            bomb_power,
            bomb_interval_sec,
            orphan_dps,
            step_dt,
            replans_per_tick,
            replan_fallback_rounds,
            search_expand_initial,
            search_expand_step,
            search_expand_max,
            plan_reeval_sec,
        };
        self.bombers = Some(BomberLayer::new(bomber_cfg));
        self.bombers_enabled = true;
        true
    }

    #[func]
    fn bombers_active(&self) -> bool {
        self.bombers_enabled && self.bombers.is_some()
    }

    #[func]
    fn update_agent_nav_masks(
        &mut self,
        friendly_corridor: PackedByteArray,
        hostile_corridor: PackedByteArray,
        friendly_bridge: PackedByteArray,
        hostile_bridge: PackedByteArray,
    ) {
        let Some(agents) = self.agents.as_mut() else {
            return;
        };
        agents.update_nav_masks(
            packed_byte_to_vec(&friendly_corridor),
            packed_byte_to_vec(&hostile_corridor),
            packed_byte_to_vec(&friendly_bridge),
            packed_byte_to_vec(&hostile_bridge),
        );
        if let Some(bombers) = self.bombers.as_mut() {
            bombers.update_nav_masks(
                packed_byte_to_vec(&friendly_corridor),
                packed_byte_to_vec(&hostile_corridor),
                packed_byte_to_vec(&friendly_bridge),
                packed_byte_to_vec(&hostile_bridge),
            );
        }
    }

    #[func]
    fn set_agent_deficit_dps(&mut self, friendly_dps: f32, hostile_dps: f32) {
        let Some(agents) = self.agents.as_mut() else {
            return;
        };
        agents.friendly_deficit_dps = friendly_dps.max(0.0);
        agents.hostile_deficit_dps = hostile_dps.max(0.0);
    }

    #[func]
    fn try_spawn_agent(
        &mut self,
        barracks_id: i32,
        team: u8,
        bx: i32,
        by: i32,
    ) -> bool {
        let Some(kernel) = self.kernel.as_mut() else {
            return false;
        };
        let Some(agents) = self.agents.as_mut() else {
            return false;
        };
        if !agents.try_spawn(kernel, barracks_id, team, bx, by) {
            return false;
        }
        let v = self.domain_book.touch(DomainId::Agents);
        if let Some(a) = agents.agents.last_mut() {
            a.version = v;
        }
        true
    }

    #[func]
    fn agents_active(&self) -> bool {
        self.agents_enabled && self.agents.is_some()
    }

    #[func]
    fn notify_hangar_destroyed(&mut self, hangar_id: i32) {
        let Some(bombers) = self.bombers.as_mut() else {
            return;
        };
        bombers.on_hangar_destroyed(hangar_id);
    }

    #[func]
    fn bomber_living_count(&self) -> i32 {
        self.bombers
            .as_ref()
            .map(|b| b.living_count() as i32)
            .unwrap_or(0)
    }

    #[func]
    fn bomber_living_for_hangar(&self, hangar_id: i32) -> i32 {
        self.bombers
            .as_ref()
            .map(|b| b.living_for_hangar(hangar_id) as i32)
            .unwrap_or(0)
    }

    #[func]
    fn try_spawn_bomber(
        &mut self,
        hangar_id: i32,
        team: u8,
        gx: i32,
        gy: i32,
    ) -> bool {
        let Some(kernel) = self.kernel.as_ref() else {
            return false;
        };
        let Some(bombers) = self.bombers.as_mut() else {
            return false;
        };
        if !bombers.try_spawn(kernel, hangar_id, team, gx, gy) {
            return false;
        }
        let v = self.domain_book.touch(DomainId::Bombers);
        if let Some(b) = bombers.bombers.last_mut() {
            b.version = v;
        }
        true
    }

    #[func]
    fn get_bomber_snapshot(&mut self) -> GdDictionary {
        let mut out = GdDictionary::new();
        let Some(bombers) = self.bombers.as_mut() else {
            return out;
        };
        let n = bombers.bombers.len();
        self.bomber_snap_teams.clear();
        self.bomber_snap_gx.clear();
        self.bomber_snap_gy.clear();
        self.bomber_snap_search_scope.clear();
        self.bomber_snap_teams.reserve(n);
        self.bomber_snap_gx.reserve(n);
        self.bomber_snap_gy.reserve(n);
        self.bomber_snap_search_scope.reserve(n);
        for b in &bombers.bombers {
            self.bomber_snap_teams.push(b.team);
            self.bomber_snap_gx.push(b.gx);
            self.bomber_snap_gy.push(b.gy);
            self.bomber_snap_search_scope.push(b.search_expand_limit as i32);
        }
        out.set("teams", &vec_to_packed_byte(&self.bomber_snap_teams));
        out.set("gx", &vec_to_packed_i32(&self.bomber_snap_gx));
        out.set("gy", &vec_to_packed_i32(&self.bomber_snap_gy));
        out.set("search_scope", &vec_to_packed_i32(&self.bomber_snap_search_scope));
        out.set("count", n as i32);
        let events = bombers.take_bomb_events();
        let mut bomb_gx = PackedInt32Array::new();
        let mut bomb_gy = PackedInt32Array::new();
        let mut bomb_teams = PackedByteArray::new();
        for ev in &events {
            bomb_gx.push(ev.gx);
            bomb_gy.push(ev.gy);
            bomb_teams.push(ev.team);
        }
        out.set("bomb_gx", &bomb_gx);
        out.set("bomb_gy", &bomb_gy);
        out.set("bomb_teams", &bomb_teams);
        out
    }

    #[func]
    fn notify_barracks_destroyed(&mut self, barracks_id: i32) {
        let Some(agents) = self.agents.as_mut() else {
            return;
        };
        agents.on_barracks_destroyed(barracks_id);
    }

    #[func]
    fn agent_living_count(&self) -> i32 {
        self.agents
            .as_ref()
            .map(|a| a.living_count() as i32)
            .unwrap_or(0)
    }

    #[func]
    fn agent_living_for_barracks(&self, barracks_id: i32) -> i32 {
        self.agents
            .as_ref()
            .map(|a| a.living_for_barracks(barracks_id) as i32)
            .unwrap_or(0)
    }

    #[func]
    fn get_agent_snapshot(&mut self) -> GdDictionary {
        let mut out = GdDictionary::new();
        let Some(agents) = &self.agents else {
            return out;
        };
        let n = agents.agents.len();
        self.agent_snap_teams.clear();
        self.agent_snap_gx.clear();
        self.agent_snap_gy.clear();
        self.agent_snap_teams.reserve(n);
        self.agent_snap_gx.reserve(n);
        self.agent_snap_gy.reserve(n);
        for a in &agents.agents {
            self.agent_snap_teams.push(a.team);
            self.agent_snap_gx.push(a.gx);
            self.agent_snap_gy.push(a.gy);
        }
        out.set("teams", &vec_to_packed_byte(&self.agent_snap_teams));
        out.set("gx", &vec_to_packed_i32(&self.agent_snap_gx));
        out.set("gy", &vec_to_packed_i32(&self.agent_snap_gy));
        out.set("count", n as i32);
        out
    }

    #[func]
    fn advance_round(&mut self) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        if self.agents_enabled {
            if let Some(agents) = self.agents.as_mut() {
                if agents.living_count() > 0 {
                    // Snapshot positions; stamp SCD1 on move/death so living-set pulls refresh.
                    let before: Vec<(u32, i32, i32, f32)> = agents
                        .agents
                        .iter()
                        .map(|a| (a.id, a.gx, a.gy, a.hp))
                        .collect();
                    let before_count = before.len();
                    agents.tick(kernel);
                    let mut any = agents.agents.len() != before_count;
                    if any {
                        let _ = self.domain_book.touch(DomainId::Agents);
                    }
                    for a in &mut agents.agents {
                        if a.hp <= 0.0 {
                            continue;
                        }
                        let changed = before
                            .iter()
                            .find(|(id, _, _, _)| *id == a.id)
                            .map(|(_, gx, gy, hp)| *gx != a.gx || *gy != a.gy || (*hp - a.hp).abs() > 0.01)
                            .unwrap_or(true);
                        if changed {
                            if !any {
                                let _ = self.domain_book.touch(DomainId::Agents);
                                any = true;
                            }
                            a.version = self.domain_book.epoch(DomainId::Agents);
                        }
                    }
                }
            }
        }
        if self.bombers_enabled {
            if let Some(bombers) = self.bombers.as_mut() {
                if bombers.living_count() > 0 {
                    let before: Vec<(u32, i32, i32, f32)> = bombers
                        .bombers
                        .iter()
                        .map(|b| (b.id, b.gx, b.gy, b.hp))
                        .collect();
                    let before_count = before.len();
                    let bombs_before = bombers.pending_bomb_events.len();
                    bombers.tick(kernel);
                    let bombed = bombers.pending_bomb_events.len() > bombs_before;
                    let mut any = bombers.bombers.len() != before_count || bombed;
                    if any {
                        let _ = self.domain_book.touch(DomainId::Bombers);
                    }
                    for b in &mut bombers.bombers {
                        if b.hp <= 0.0 {
                            continue;
                        }
                        let changed = before
                            .iter()
                            .find(|(id, _, _, _)| *id == b.id)
                            .map(|(_, gx, gy, hp)| *gx != b.gx || *gy != b.gy || (*hp - b.hp).abs() > 0.01)
                            .unwrap_or(true);
                        if changed {
                            if !any {
                                let _ = self.domain_book.touch(DomainId::Bombers);
                                any = true;
                            }
                            b.version = self.domain_book.epoch(DomainId::Bombers);
                        }
                    }
                }
            }
        }
        kernel.advance_round();
        // Stamp territory cell versions for owner dirty this round (SCD1 pull source).
        let (dirty_idx, dirty_val) = kernel.take_owner_dirty();
        let (display_idx, display_vals) = kernel.take_display_dirty();
        if !dirty_idx.is_empty() {
            let tv = self.domain_book.touch(DomainId::Territory);
            if self.owner_cell_version.len() < kernel.owners.len() {
                self.owner_cell_version.resize(kernel.owners.len(), 0);
            }
            for &idx in &dirty_idx {
                if idx >= 0 && (idx as usize) < self.owner_cell_version.len() {
                    self.owner_cell_version[idx as usize] = tv;
                }
            }
            // Keep legacy txn available for QA paths only.
            self.presentation_txn.push_owner_delta(
                dirty_idx,
                dirty_val,
                display_idx,
                display_vals,
                kernel.friendly_tiles,
                kernel.hostile_tiles,
            );
        }
    }

    #[func]
    fn advance_rounds(&mut self, n: i32) {
        let count = n.max(0);
        for _ in 0..count {
            self.advance_round();
        }
    }

    #[func]
    fn sync_owners_delta(&mut self) -> GdDictionary {
        let Some(kernel) = self.kernel.as_mut() else {
            return GdDictionary::new();
        };
        let (idx, vals) = kernel.take_owner_dirty();
        let (display_idx, display_vals) = kernel.take_display_dirty();
        let mut out = GdDictionary::new();
        out.set("owner_indices", &vec_to_packed_i32(&idx));
        out.set("owner_values", &vec_to_packed_byte(&vals));
        out.set("display_indices", &vec_to_packed_i32(&display_idx));
        out.set("display_r8", &vec_to_packed_byte(&display_vals));
        out.set("friendly_tiles", kernel.friendly_tiles);
        out.set("hostile_tiles", kernel.hostile_tiles);
        out
    }

    #[func]
    fn sync_into_tile_control(&self) -> GdDictionary {
        let Some(kernel) = &self.kernel else {
            return GdDictionary::new();
        };
        let mut out = GdDictionary::new();
        let owners = vec_to_packed_byte(&kernel.owners);
        let pressure_friendly = vec_to_packed_f32(&kernel.pressure_friendly);
        let pressure_hostile = vec_to_packed_f32(&kernel.pressure_hostile);
        out.set("owners", &owners);
        out.set("pressure_friendly", &pressure_friendly);
        out.set("pressure_hostile", &pressure_hostile);
        out.set("friendly_tiles", kernel.friendly_tiles);
        out.set("hostile_tiles", kernel.hostile_tiles);
        out
    }

    #[func]
    fn get_owners(&self) -> PackedByteArray {
        match &self.kernel {
            Some(k) => vec_to_packed_byte(&k.owners),
            None => PackedByteArray::new(),
        }
    }

    #[func]
    fn owner_at_index(&self, idx: i32) -> u8 {
        match &self.kernel {
            Some(k) => k.owner_at_index(idx.max(0) as usize),
            None => sim::OWNER_UNCLAIMABLE,
        }
    }

    #[func]
    fn claimable_at_index(&self, idx: i32) -> bool {
        match &self.kernel {
            Some(k) => k.claimable_at_index(idx.max(0) as usize),
            None => false,
        }
    }

    #[func]
    fn get_claimable_tile_count(&self) -> i32 {
        match &self.kernel {
            Some(k) => k.claimable_tile_count(),
            None => 0,
        }
    }

    #[func]
    fn claimable_tile_count(&self) -> i32 {
        self.get_claimable_tile_count()
    }

    #[func]
    fn claim_ratio_mult_at(&self, idx: i32) -> f32 {
        match &self.kernel {
            Some(k) => k.claim_ratio_mult_at(idx.max(0) as usize),
            None => 1.0,
        }
    }

    #[func]
    fn query_tile(&self, gx: i32, gy: i32) -> GdDictionary {
        let Some(kernel) = &self.kernel else {
            return GdDictionary::new();
        };
        let probe = kernel.query_tile(gx, gy);
        if !probe.valid {
            return GdDictionary::new();
        }
        let mut out = GdDictionary::new();
        out.set("valid", true);
        out.set("gx", gx);
        out.set("gy", gy);
        out.set("owner", probe.owner);
        out.set("claimable", probe.claimable);
        out.set("pf", probe.pf);
        out.set("ph", probe.ph);
        out.set("f_bridge", probe.f_bridge);
        out.set("h_bridge", probe.h_bridge);
        out.set("f_corridor", probe.f_corridor);
        out.set("h_corridor", probe.h_corridor);
        out.set("f_reach", probe.f_reach);
        out.set("h_reach", probe.h_reach);
        out.set("flow_mult", probe.flow_mult);
        out
    }

    #[func]
    fn claim_tile_at(&mut self, gx: i32, gy: i32, team: u8) -> bool {
        let Some(kernel) = self.kernel.as_mut() else {
            return false;
        };
        kernel.claim_tile_at(gx, gy, team)
    }

    /// Fast path for the globe ownership overlay texture.
    /// Returns pre-mapped R8 bytes (0/128/192/255 per the display rules) with seam fix applied.
    /// GDScript can do set_data(FORMAT_R8, this) + update with no per-cell script work.
    #[func]
    fn get_owner_display_r8(&self) -> PackedByteArray {
        match &self.kernel {
            Some(k) => vec_to_packed_byte(&k.owner_display_r8()),
            None => PackedByteArray::new(),
        }
    }

    #[func]
    fn get_pressure_friendly(&self) -> PackedFloat32Array {
        match &self.kernel {
            Some(k) => vec_to_packed_f32(&k.pressure_friendly),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    fn get_pressure_hostile(&self) -> PackedFloat32Array {
        match &self.kernel {
            Some(k) => vec_to_packed_f32(&k.pressure_hostile),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    fn pressure_overlay_peak(&self) -> f32 {
        let Some(k) = &self.kernel else {
            return 10000.0;
        };
        let mut peak = 0.01_f32;
        for &p in &k.pressure_friendly {
            if p > peak {
                peak = p;
            }
        }
        for &p in &k.pressure_hostile {
            if p > peak {
                peak = p;
            }
        }
        peak
    }

    #[func]
    fn get_friendly_tiles(&self) -> i32 {
        self.kernel.as_ref().map(|k| k.friendly_tiles).unwrap_or(0)
    }

    #[func]
    fn get_hostile_tiles(&self) -> i32 {
        self.kernel.as_ref().map(|k| k.hostile_tiles).unwrap_or(0)
    }

    #[func]
    fn encode_pressure_v2(&self, pressure: PackedFloat32Array) -> PackedByteArray {
        vec_to_packed_byte(&encode_pressure_v2(&packed_f32_to_vec(&pressure)))
    }

    #[func]
    fn decode_pressure_v2(&self, blob: PackedByteArray) -> PackedFloat32Array {
        vec_to_packed_f32(&decode_pressure_v2(&packed_byte_to_vec(&blob)))
    }

    #[func]
    fn bake_fluid_rgba(
        &self,
        grid_w: i32,
        grid_h: i32,
        land_mask: PackedByteArray,
        pressure_friendly: PackedFloat32Array,
        pressure_hostile: PackedFloat32Array,
        power_scale: f32,
    ) -> PackedByteArray {
        let bytes = bake_fluid_rgba(
            grid_w,
            grid_h,
            &packed_byte_to_vec(&land_mask),
            &packed_f32_to_vec(&pressure_friendly),
            &packed_f32_to_vec(&pressure_hostile),
            power_scale,
        );
        vec_to_packed_byte(&bytes)
    }

    #[func]
    fn bake_fluid_frames_parallel(
        &self,
        grid_w: i32,
        grid_h: i32,
        land_mask: PackedByteArray,
        frames_friendly: Array<Variant>,
        frames_hostile: Array<Variant>,
        power_scale: f32,
    ) -> Array<Variant> {
        let land = packed_byte_to_vec(&land_mask);
        let n = frames_friendly.len().min(frames_hostile.len());
        let pf_vecs: Vec<Vec<f32>> = (0..n)
            .filter_map(|i| {
                frames_friendly
                    .get(i)
                    .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
                    .map(|a| packed_f32_to_vec(&a))
            })
            .collect();
        let ph_vecs: Vec<Vec<f32>> = (0..n)
            .filter_map(|i| {
                frames_hostile
                    .get(i)
                    .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
                    .map(|a| packed_f32_to_vec(&a))
            })
            .collect();
        let count = pf_vecs.len().min(ph_vecs.len());

        let baked_bytes: Vec<Vec<u8>> = (0..count)
            .into_par_iter()
            .map(|i| {
                bake_fluid_rgba(
                    grid_w,
                    grid_h,
                    &land,
                    &pf_vecs[i],
                    &ph_vecs[i],
                    power_scale,
                )
            })
            .collect();

        let mut out = Array::<Variant>::new();
        for bytes in baked_bytes {
            out.push(&vec_to_packed_byte(&bytes).to_variant());
        }
        out
    }

    #[func]
    fn pack_territory_tape_from_dict(&self, config: GdDictionary) -> PackedByteArray {
        let grid_w: u16 = config.get("grid_w").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let grid_h: u16 = config.get("grid_h").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let record_stride: u16 = config
            .get("record_stride")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1);
        let frame_count: u32 = config
            .get("frame_count")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        if frame_count == 0 {
            return PackedByteArray::new();
        }

        let rounds: PackedInt32Array = config
            .get("frame_rounds")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let friendly: PackedInt32Array = config
            .get("frame_friendly")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let hostile: PackedInt32Array = config
            .get("frame_hostile")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let full_flags: PackedByteArray = config
            .get("frame_full_flags")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let owner_blobs: Array<Variant> = config
            .get("frame_owner_blobs")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let delta_blobs: Array<Variant> = config
            .get("frame_delta_blobs")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let pf_blobs: Array<Variant> = config
            .get("frame_pressure_f")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let ph_blobs: Array<Variant> = config
            .get("frame_pressure_h")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();

        let fc = frame_count as usize;
        let mut frame_rounds = Vec::with_capacity(fc);
        let mut frame_friendly = Vec::with_capacity(fc);
        let mut frame_hostile = Vec::with_capacity(fc);
        let mut frame_full_flags = Vec::with_capacity(fc);
        let mut frame_owner_full = Vec::with_capacity(fc);
        let mut frame_owner_deltas = Vec::with_capacity(fc);
        let mut frame_pressure_f = Vec::with_capacity(fc);
        let mut frame_pressure_h = Vec::with_capacity(fc);

        for i in 0..fc {
            frame_rounds.push(rounds.get(i).unwrap_or(0) as u32);
            frame_friendly.push(friendly.get(i).unwrap_or(0) as u16);
            frame_hostile.push(hostile.get(i).unwrap_or(0) as u16);
            frame_full_flags.push(full_flags.get(i).unwrap_or(0));

            if frame_full_flags[i] != 0 {
                let blob: PackedByteArray = owner_blobs
                    .get(i)
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                frame_owner_full.push(packed_byte_to_vec(&blob));
                frame_owner_deltas.push(Vec::new());
            } else {
                frame_owner_full.push(Vec::new());
                let delta_blob: PackedByteArray = delta_blobs
                    .get(i)
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let raw = packed_byte_to_vec(&delta_blob);
                let mut deltas = Vec::new();
                let mut j = 0;
                while j + 2 < raw.len() {
                    let idx = u16::from_le_bytes([raw[j], raw[j + 1]]);
                    let owner = raw[j + 2];
                    deltas.push((idx, owner));
                    j += 3;
                }
                frame_owner_deltas.push(deltas);
            }

            let pf: PackedByteArray = pf_blobs
                .get(i)
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            let ph: PackedByteArray = ph_blobs
                .get(i)
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            frame_pressure_f.push(packed_byte_to_vec(&pf));
            frame_pressure_h.push(packed_byte_to_vec(&ph));
        }

        vec_to_packed_byte(&pack_territory_tape_v2(
            grid_w,
            grid_h,
            record_stride,
            frame_count,
            &frame_rounds,
            &frame_friendly,
            &frame_hostile,
            &frame_full_flags,
            &frame_owner_full,
            &frame_owner_deltas,
            &frame_pressure_f,
            &frame_pressure_h,
        ))
    }
}

/// Async outpost / land-bridge route planner (portal graph + background thread).
#[derive(GodotClass)]
#[class(base=RefCounted)]
struct RoutePlanner {
    base: Base<RefCounted>,
    state: RoutePlannerState,
    next_request_id: i32,
}

#[godot_api]
impl IRefCounted for RoutePlanner {
    fn init(base: Base<Self::Base>) -> Self {
        Self {
            base,
            state: RoutePlannerState::new(),
            next_request_id: 1,
        }
    }
}

#[godot_api]
impl RoutePlanner {
    #[func]
    fn is_available() -> bool {
        true
    }

    #[func]
    fn set_map_snapshot(
        &mut self,
        grid_w: i32,
        grid_h: i32,
        wrap_longitude: bool,
        land_mask: PackedByteArray,
        bridge_mask: PackedByteArray,
        land_comp: PackedInt32Array,
    ) -> bool {
        let n = (grid_w * grid_h) as usize;
        if n <= 0 {
            return false;
        }
        let lm = packed_byte_to_vec(&land_mask);
        let bm = packed_byte_to_vec(&bridge_mask);
        let lc: Vec<i32> = (0..land_comp.len())
            .map(|i| land_comp.get(i).unwrap_or(-1))
            .collect();
        if lm.len() < n || bm.len() < n || lc.len() < n {
            return false;
        }
        let snap = Arc::new(RouteSnapshot {
            grid_w,
            grid_h,
            wrap_longitude,
            land_mask: lm,
            bridge_mask: bm,
            land_comp: lc,
        });
        if let Ok(mut guard) = self.state.snapshot.lock() {
            *guard = Some(snap);
        }
        true
    }

    #[func]
    fn update_infra_mask(&mut self, bridge_mask: PackedByteArray) -> bool {
        let snap = match self.state.snapshot.lock().ok().and_then(|g| g.clone()) {
            Some(s) => s,
            None => return false,
        };
        let n = snap.tile_count();
        if n <= 0 {
            return false;
        }
        let bm = packed_byte_to_vec(&bridge_mask);
        if bm.len() < n {
            return false;
        }
        let mut next = (*snap).clone();
        next.bridge_mask.copy_from_slice(&bm[..n]);
        if let Ok(mut guard) = self.state.snapshot.lock() {
            *guard = Some(Arc::new(next));
        }
        true
    }

    #[func]
    fn rebuild_portal_graph(
        &mut self,
        source_keys: PackedInt32Array,
        bridge_landing_keys: PackedInt32Array,
    ) -> bool {
        let snap = match self.state.snapshot.lock().ok().and_then(|g| g.clone()) {
            Some(s) => s,
            None => return false,
        };
        let sources: Vec<i32> = (0..source_keys.len())
            .map(|i| source_keys.get(i).unwrap_or(-1))
            .collect();
        let mut portal = PortalGraph::rebuild(&snap, &sources);
        let landings: Vec<i32> = (0..bridge_landing_keys.len())
            .map(|i| bridge_landing_keys.get(i).unwrap_or(-1))
            .collect();
        portal.set_bridge_landings(&snap, &landings);
        if let Ok(mut guard) = self.state.portal.lock() {
            *guard = portal;
        }
        true
    }

    #[func]
    fn route_planner_api_version(&self) -> i32 {
        3
    }

    #[func]
    fn find_route_sync(
        &self,
        target_gx: i32,
        target_gy: i32,
        kind: i32,
        allow_astar: bool,
    ) -> GdDictionary {
        let mut out = GdDictionary::new();
        out.set("path_packed", &PackedInt32Array::new());
        out.set("source_key", -1);
        out.set("found", false);
        out.set("reject", 0);
        out.set("expand_count", 0);
        let snap = match self.state.snapshot.lock().ok().and_then(|g| g.clone()) {
            Some(s) => s,
            None => return out,
        };
        let portal = match self.state.portal.lock() {
            Ok(g) => g.clone(),
            Err(_) => return out,
        };
        if let Some(res) = crate::route::find_route_detail(
            &snap,
            &portal,
            target_gx,
            target_gy,
            kind,
            allow_astar,
        ) {
            out.set("reject", res.reject);
            out.set("expand_count", res.expand_count as i32);
            if !res.result.path.is_empty() {
                out.set("path_packed", &vec_to_packed_i32(&res.result.path));
                out.set("source_key", res.result.source_key);
                out.set("found", true);
            }
        }
        out
    }

    #[func]
    fn start_route_async(
        &mut self,
        target_gx: i32,
        target_gy: i32,
        kind: i32,
        allow_astar: bool,
    ) -> i32 {
        let snap = match self.state.snapshot.lock().ok().and_then(|g| g.clone()) {
            Some(s) => s,
            None => return -1,
        };
        let portal = match self.state.portal.lock() {
            Ok(g) => Arc::new(g.clone()),
            Err(_) => return -1,
        };
        let worker_guard = match self.state.worker.lock() {
            Ok(g) => g,
            Err(_) => return -1,
        };
        let Some(worker) = worker_guard.as_ref() else {
            return -1;
        };
        let req_id = self.next_request_id;
        self.next_request_id += 1;
        if worker.start_route(
            req_id,
            snap,
            portal,
            target_gx,
            target_gy,
            kind,
            allow_astar,
        ) {
            req_id
        } else {
            -1
        }
    }

    #[func]
    fn cancel_route(&mut self, request_id: i32) {
        if let Ok(worker_guard) = self.state.worker.lock() {
            if let Some(worker) = worker_guard.as_ref() {
                worker.cancel(request_id);
            }
        }
    }

    #[func]
    fn poll_route(&self) -> GdDictionary {
        let mut out = GdDictionary::new();
        out.set("ready", false);
        out.set("request_id", -1);
        out.set("path_packed", &PackedInt32Array::new());
        out.set("source_key", -1);
        out.set("found", false);
        let worker_guard = match self.state.worker.lock() {
            Ok(g) => g,
            Err(_) => return out,
        };
        let Some(worker) = worker_guard.as_ref() else {
            return out;
        };
        let Some(res) = worker.poll() else {
            return out;
        };
        out.set("ready", true);
        out.set("request_id", res.request_id);
        out.set("path_packed", &vec_to_packed_i32(&res.path));
        out.set("source_key", res.source_key);
        out.set("found", res.found);
        out
    }
}
