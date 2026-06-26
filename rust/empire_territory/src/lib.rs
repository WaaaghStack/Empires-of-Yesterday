//! Empire Territory Sim — Rust GDExtension for high-performance territory conquest simulation.

mod agents;
mod builders;
mod fluid_bake;
mod grid_query;
mod pathfind;
mod resources;
mod route;
mod sim;
mod structures;
mod tape_codec;
mod world_edit;
mod world_session;

use fluid_bake::bake_fluid_rgba;
use godot::builtin::Variant;
use godot::prelude::*;
use rayon::prelude::*;
use std::sync::Arc;
use agents::{AgentConfig, AgentLayer};
use builders::{
    work_grid_pos, BuilderConfig, BuilderLayer, BuilderStepEvents, PathCompletionEvent,
};
use resources::ResourceWallet;
use route::{
    find_route, PortalGraph, RoutePlannerState, RouteSnapshot,
};
use structures::{
    kind_from_str, kind_to_str, state_from_str, state_to_str, PersistedCorridor, StructureRecord,
    StructureStore,
};
use sim::{Spawner, TerritoryKernel};
use tape_codec::{decode_pressure_v2, encode_pressure_v2, pack_territory_tape_v2};
use world_edit::{ClaimableDelta, CorridorPathSpec, WorldEditResult};
use world_session::{tick_world_session, WorldSessionConfig, WorldSessionEvents};

type GdDictionary = Dictionary<Variant, Variant>;

struct EmpireTerritoryExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EmpireTerritoryExtension {}

fn packed_byte_to_vec(arr: &PackedByteArray) -> Vec<u8> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(0)).collect()
}

fn packed_f32_to_vec(arr: &PackedFloat32Array) -> Vec<f32> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(0.0)).collect()
}

fn vec_to_packed_byte(data: &[u8]) -> PackedByteArray {
    PackedByteArray::from(data)
}

fn vec_to_packed_f32(data: &[f32]) -> PackedFloat32Array {
    PackedFloat32Array::from(data)
}

fn vec_to_packed_i32(data: &[i32]) -> PackedInt32Array {
    PackedInt32Array::from(data)
}

fn structure_record_from_dict(spec: &GdDictionary) -> Option<StructureRecord> {
    let id: i32 = spec.get("id").and_then(|v| v.try_to().ok())?;
    let team: u8 = spec.get("team").and_then(|v| v.try_to().ok()).unwrap_or(1);
    let kind: GString = spec
        .get("kind")
        .and_then(|v| v.try_to().ok())
        .unwrap_or_default();
    let state: GString = spec
        .get("state")
        .and_then(|v| v.try_to().ok())
        .unwrap_or_default();
    let gx: i32 = spec.get("gx").and_then(|v| v.try_to().ok()).unwrap_or(0);
    let gy: i32 = spec.get("gy").and_then(|v| v.try_to().ok()).unwrap_or(0);
    let path: PackedInt32Array = spec
        .get("path_keys")
        .and_then(|v| v.try_to().ok())
        .unwrap_or_default();
    let path_keys: Vec<i32> = (0..path.len())
        .map(|j| path.get(j).unwrap_or(-1))
        .collect();
    let path_built: f32 = spec
        .get("path_built")
        .and_then(|v| v.try_to().ok())
        .unwrap_or(1.0);
    let path_len: i32 = spec
        .get("path_len")
        .and_then(|v| v.try_to().ok())
        .unwrap_or(path_keys.len() as i32);
    let corridor_synced_built: i32 = spec
        .get("corridor_synced_built")
        .and_then(|v| v.try_to().ok())
        .unwrap_or(1);
    let health: f32 = spec.get("health").and_then(|v| v.try_to().ok()).unwrap_or(-1.0);
    let build_remaining: f32 = spec
        .get("build_remaining")
        .and_then(|v| v.try_to().ok())
        .unwrap_or(-1.0);
    let spawn_timer: f32 = spec
        .get("spawn_timer")
        .and_then(|v| v.try_to().ok())
        .unwrap_or(0.0);
    Some(StructureRecord {
        id,
        team,
        kind: kind_from_str(kind.to_string().as_str()),
        state: state_from_str(state.to_string().as_str()),
        gx,
        gy,
        path_keys,
        path_built,
        path_len,
        corridor_synced_built,
        health,
        build_remaining,
        spawn_timer,
    })
}

fn persisted_corridor_from_dict(slot: usize, spec: &GdDictionary) -> Option<PersistedCorridor> {
    let path: PackedInt32Array = spec
        .get("path_keys")
        .and_then(|v| v.try_to().ok())
        .unwrap_or_default();
    if path.is_empty() {
        return None;
    }
    let path_keys: Vec<i32> = (0..path.len())
        .map(|j| path.get(j).unwrap_or(-1))
        .collect();
    Some(PersistedCorridor {
        slot,
        team: spec.get("team").and_then(|v| v.try_to().ok()).unwrap_or(1),
        path_keys,
        corridor_synced_built: spec
            .get("corridor_synced_built")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1),
    })
}

fn structure_record_to_dict(record: &StructureRecord) -> GdDictionary {
    let mut out = GdDictionary::new();
    out.set("id", record.id);
    out.set("team", record.team);
    let kind = GString::from(kind_to_str(record.kind));
    let state = GString::from(state_to_str(record.state));
    out.set("kind", &kind);
    out.set("state", &state);
    out.set("gx", record.gx);
    out.set("gy", record.gy);
    out.set("path_keys", &vec_to_packed_i32(&record.path_keys));
    out.set("path_built", record.path_built);
    out.set("path_len", record.path_len);
    out.set("corridor_synced_built", record.corridor_synced_built);
    if record.health >= 0.0 {
        out.set("health", record.health);
    }
    if record.build_remaining >= 0.0 {
        out.set("build_remaining", record.build_remaining);
    }
    if record.spawn_timer > 0.0 {
        out.set("spawn_timer", record.spawn_timer);
    }
    out
}

fn world_session_events_dict(events: &WorldSessionEvents, friendly_aurelium: f32) -> GdDictionary {
    let mut out = GdDictionary::new();
    out.set("friendly_aurelium", friendly_aurelium);
    out.set("friendly_aurelium_spent", events.friendly_aurelium_spent);
    out.set("needs_sim_sync", events.needs_sim_sync);
    out.set("marker_dirty", events.marker_dirty);
    out.set("activated_sids", &vec_to_packed_i32(&events.activated_sids));
    out.set(
        "activated_spawner_sids",
        &vec_to_packed_i32(&events.activated_spawner_sids),
    );
    out.set("destroyed_sids", &vec_to_packed_i32(&events.destroyed_sids));
    out.set(
        "spawned_barracks_sids",
        &vec_to_packed_i32(&events.spawned_barracks_sids),
    );
    out
}

fn builder_step_events_dict(events: &BuilderStepEvents) -> GdDictionary {
    let mut out = GdDictionary::new();
    out.set("visual_dirty", events.visual_dirty);
    let mut arrivals = Array::<Variant>::new();
    for ev in &events.cell_arrivals {
        let mut entry = GdDictionary::new();
        entry.set("sid", ev.sid);
        entry.set("seg_from_idx", ev.seg_from_idx);
        entry.set("kind", &GString::from(builders::kind_str(ev.kind)));
        arrivals.push(&entry);
    }
    out.set("cell_arrivals", &arrivals);
    let mut completions = Array::<Variant>::new();
    for ev in &events.path_completions {
        let mut entry = path_completion_dict(ev);
        completions.push(&entry);
    }
    out.set("path_completions", &completions);
    out.set(
        "completed_corridor_sids",
        &vec_to_packed_i32(&events.completed_corridor_sids),
    );
    let mut teams = PackedByteArray::new();
    for t in &events.reassign_teams {
        teams.push(*t);
    }
    out.set("reassign_teams", &teams);
    out
}

fn path_completion_dict(ev: &PathCompletionEvent) -> GdDictionary {
    let mut entry = GdDictionary::new();
    entry.set("sid", ev.sid);
    entry.set("gx", ev.gx);
    entry.set("gy", ev.gy);
    entry.set("team", ev.team);
    entry.set("is_corridor_link", ev.is_corridor_link);
    entry.set("kind", &GString::from(builders::kind_str(ev.kind)));
    entry
}

fn f32_triple_from_array(arr: &PackedFloat32Array) -> [f32; 3] {
    [
        arr.get(0).unwrap_or(0.0),
        arr.get(1).unwrap_or(0.0),
        arr.get(2).unwrap_or(0.0),
    ]
}

fn claimable_delta_dict(delta: &ClaimableDelta) -> GdDictionary {
    let mut d = GdDictionary::new();
    d.set("indices", &vec_to_packed_i32(&delta.indices));
    d.set("claimable", &vec_to_packed_byte(&delta.claimable));
    d.set("owners", &vec_to_packed_byte(&delta.owners));
    d.set("elevation", &vec_to_packed_f32(&delta.elevation));
    d.set("flow_mult", &vec_to_packed_f32(&delta.terrain_flow_mult));
    d.set("claim_mult", &vec_to_packed_f32(&delta.claim_ratio_mult));
    d
}

fn world_edit_result_dict(result: &WorldEditResult) -> GdDictionary {
    let mut d = GdDictionary::new();
    d.set("changed", result.changed);
    d.set("claimable_delta", &claimable_delta_dict(&result.claimable_delta));
    let mut synced = Array::<Variant>::new();
    for (sid, built) in &result.synced_updates {
        let mut entry = GdDictionary::new();
        entry.set("sid", *sid);
        entry.set("corridor_synced_built", *built);
        synced.push(&entry);
    }
    d.set("synced_updates", &synced);
    d
}

fn corridor_specs_from_array(specs: Array<Variant>) -> Vec<CorridorPathSpec> {
    let mut out = Vec::new();
    for i in 0..specs.len() {
        let Some(v) = specs.get(i) else {
            continue;
        };
        let Ok(spec) = v.try_to::<GdDictionary>() else {
            continue;
        };
        let sid: i32 = spec.get("sid").and_then(|v| v.try_to().ok()).unwrap_or(-1);
        let team: u8 = spec.get("team").and_then(|v| v.try_to().ok()).unwrap_or(1);
        let path: PackedInt32Array = spec
            .get("path_keys")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let built: i32 = spec
            .get("built_cells")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        let synced: i32 = spec
            .get("synced_cells")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1);
        let keys: Vec<i32> = (0..path.len())
            .map(|j| path.get(j).unwrap_or(-1))
            .collect();
        out.push(CorridorPathSpec {
            sid,
            team,
            path_keys: keys,
            built_cells: built,
            synced_cells: synced,
        });
    }
    out
}

fn spawners_from_dict(config: &GdDictionary) -> Vec<Spawner> {
    let teams = config
        .get("spawner_teams")
        .and_then(|v| v.try_to::<PackedByteArray>().ok())
        .unwrap_or_default();
    let gx = config
        .get("spawner_gx")
        .and_then(|v| v.try_to::<PackedInt32Array>().ok())
        .unwrap_or_default();
    let gy = config
        .get("spawner_gy")
        .and_then(|v| v.try_to::<PackedInt32Array>().ok())
        .unwrap_or_default();
    let count = teams.len().min(gx.len()).min(gy.len());
    let mut spawners = Vec::with_capacity(count);
    for i in 0..count {
        spawners.push(Spawner {
            team: teams.get(i).unwrap_or(0),
            gx: gx.get(i).unwrap_or(-1),
            gy: gy.get(i).unwrap_or(-1),
        });
    }
    spawners
}

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
    structure_store: StructureStore,
    world_session_cfg: WorldSessionConfig,
    world_session_enabled: bool,
    builder_layer: BuilderLayer,
    builder_cfg: BuilderConfig,
    builder_enabled: bool,
    resource_wallet: ResourceWallet,
    resource_wallet_enabled: bool,
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
        let Some(record) = structure_record_from_dict(&spec) else {
            return false;
        };
        self.structure_store.upsert(record);
        true
    }

    #[func]
    fn structure_store_remove(&mut self, sid: i32) {
        self.structure_store.remove(sid);
    }

    #[func]
    fn structure_store_patch_path_built(&mut self, sid: i32, path_built: f32) -> bool {
        self.structure_store.patch_path_built(sid, path_built)
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
        self.structure_store
            .patch_state(sid, state_from_str(state.to_string().as_str()), pb)
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
        let mut wallet = if self.resource_wallet_enabled {
            self.resource_wallet.friendly[0]
        } else {
            friendly_aurelium
        };
        let agents_ptr = self.agents.as_mut();
        let events = tick_world_session(
            kernel,
            &mut self.structure_store,
            agents_ptr,
            dt,
            &mut wallet,
            &self.world_session_cfg,
        );
        if self.resource_wallet_enabled {
            self.resource_wallet.friendly[0] = wallet;
        }
        world_session_events_dict(&events, wallet)
    }

    #[func]
    fn configure_builders(&mut self, config: GdDictionary, enabled: bool) {
        self.builder_cfg = BuilderConfig {
            road_cells_per_sec: config
                .get("road_cells_per_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(1.0),
            bots_per_home: config
                .get("bots_per_home")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(2),
            orbit_radius_cells: config
                .get("orbit_radius_cells")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(3.5),
            orbit_speed: config
                .get("orbit_speed")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.55),
            return_sec: config
                .get("return_sec")
                .and_then(|v| v.try_to().ok())
                .unwrap_or(0.45),
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
        self.builder_enabled = enabled;
        if enabled {
            self.builder_layer.player_home = (self.player_home_gx, self.player_home_gy);
            self.builder_layer.enemy_home = (self.enemy_home_gx, self.enemy_home_gy);
            self.builder_layer.init_bots(&self.builder_cfg);
        }
    }

    #[func]
    fn builder_authority_enabled(&self) -> bool {
        self.builder_enabled && self.structure_store.ready && self.kernel.is_some()
    }

    #[func]
    fn builder_enqueue_job(&mut self, sid: i32, team: u8) {
        if sid < 0 {
            return;
        }
        self.builder_layer.enqueue_job(sid, team);
        if self.builder_enabled {
            let grid_w = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(0);
            self.builder_layer.assign_builder_jobs(
                &self.structure_store,
                grid_w,
                &self.builder_cfg,
                team as i32,
            );
        }
    }

    #[func]
    fn builder_cancel_job(&mut self, sid: i32) {
        if sid < 0 {
            return;
        }
        let grid_w = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(0);
        self.builder_layer.cancel_job(
            sid,
            &self.structure_store,
            grid_w,
            &self.builder_cfg,
        );
    }

    #[func]
    fn builder_assign_jobs(&mut self, team_filter: i32) {
        let grid_w = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(0);
        self.builder_layer.assign_builder_jobs(
            &self.structure_store,
            grid_w,
            &self.builder_cfg,
            team_filter,
        );
    }

    #[func]
    fn builder_step(&mut self, dt: f32) -> GdDictionary {
        if !self.builder_authority_enabled() {
            return GdDictionary::new();
        }
        let grid_w = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(0);
        let events = self.builder_layer.step_frame(
            dt,
            &mut self.structure_store,
            grid_w,
            &self.builder_cfg,
        );
        builder_step_events_dict(&events)
    }

    #[func]
    fn get_builder_visual_snapshot(&self) -> GdDictionary {
        let mut out = GdDictionary::new();
        if !self.builder_enabled {
            return out;
        }
        let grid_w = self.kernel.as_ref().map(|k| k.grid_w).unwrap_or(0);
        let n = self.builder_layer.bots.len();
        let mut xs = Vec::with_capacity(n);
        let mut ys = Vec::with_capacity(n);
        let mut teams_vec = Vec::with_capacity(n);
        for bot in &self.builder_layer.bots {
            let (x, y) = work_grid_pos(
                bot,
                &self.structure_store,
                grid_w,
                &self.builder_cfg,
                &self.builder_layer,
            );
            xs.push(x);
            ys.push(y);
            teams_vec.push(bot.team);
        }
        out.set("pos_x", &vec_to_packed_f32(&xs));
        out.set("pos_y", &vec_to_packed_f32(&ys));
        out.set("teams", &vec_to_packed_byte(&teams_vec));
        out
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
        self.sync_owners_delta()
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
    fn agents_active(&self) -> bool {
        self.agents_enabled && self.agents.is_some()
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
        agents.try_spawn(kernel, barracks_id, team, bx, by)
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
        if let Some(kernel) = self.kernel.as_mut() {
            if self.agents_enabled {
                if let Some(agents) = self.agents.as_mut() {
                    if agents.living_count() > 0 {
                        kernel.advance_round_with_agents(agents);
                        return;
                    }
                }
            }
            kernel.advance_round();
        }
    }

    #[func]
    fn advance_rounds(&mut self, n: i32) {
        let count = n.max(0);
        if count <= 0 {
            return;
        }
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        if self.agents_enabled {
            if let Some(agents) = self.agents.as_mut() {
                if agents.living_count() > 0 {
                    for _ in 0..count {
                        kernel.advance_round_with_agents(agents);
                    }
                    return;
                }
            }
        }
        kernel.advance_rounds(count);
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
