//! Godot dictionary / packed-array conversion helpers (extracted from lib.rs — C3).
//! Keeps the GDExtension class surface thin; pure conversion lives here.

use godot::builtin::Variant;
use godot::prelude::*;

use crate::builders::{kind_str as builders_kind_str, BuilderStepEvents, PathCompletionEvent};
use crate::logistics::{
    kind_str as logistics_kind_str, LogisticsStepEvents, PathCompletionEvent as LogisticsPathCompletion,
};
use crate::structures::{
    kind_from_str, kind_to_str, state_from_str, state_to_str, PersistedCorridor, StructureRecord,
};
use crate::world_edit::{ClaimableDelta, CorridorPathSpec, WorldEditResult};
use crate::world_session::WorldSessionEvents;
use crate::sim::Spawner;

pub type GdDictionary = Dictionary<Variant, Variant>;

pub fn packed_byte_to_vec(arr: &PackedByteArray) -> Vec<u8> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(0)).collect()
}

pub fn packed_f32_to_vec(arr: &PackedFloat32Array) -> Vec<f32> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(0.0)).collect()
}

pub fn vec_to_packed_byte(data: &[u8]) -> PackedByteArray {
    PackedByteArray::from(data)
}

pub fn vec_to_packed_f32(data: &[f32]) -> PackedFloat32Array {
    PackedFloat32Array::from(data)
}

pub fn packed_i32_to_vec(arr: &PackedInt32Array) -> Vec<i32> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(-1)).collect()
}

pub fn graph_neighbors_from_packed(flat: &[i32], tile_count: usize) -> Vec<[i32; 6]> {
    let mut out = Vec::with_capacity(tile_count);
    for i in 0..tile_count {
        let base = i * 6;
        let mut row = [-1i32; 6];
        for k in 0..6 {
            row[k] = flat.get(base + k).copied().unwrap_or(-1);
        }
        out.push(row);
    }
    out
}

pub fn vec_to_packed_i32(data: &[i32]) -> PackedInt32Array {
    PackedInt32Array::from(data)
}

pub fn structure_record_from_dict(spec: &GdDictionary) -> Option<StructureRecord> {
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
        version: spec
            .get("version")
            .and_then(|v| v.try_to::<i64>().ok())
            .map(|v| v.max(0) as u64)
            .unwrap_or(0),
    })
}

pub fn persisted_corridor_from_dict(slot: usize, spec: &GdDictionary) -> Option<PersistedCorridor> {
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

pub fn structure_record_to_dict(record: &StructureRecord) -> GdDictionary {
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
    out.set("version", record.version as i64);
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

pub fn world_session_events_dict(events: &WorldSessionEvents, friendly_aurelium: f32) -> GdDictionary {
    let mut out = GdDictionary::new();
    out.set("friendly_aurelium", friendly_aurelium);
    out.set("friendly_aurelium_spent", events.friendly_aurelium_spent);
    out.set("friendly_deficit_dps", events.friendly_deficit_dps);
    out.set("hostile_deficit_dps", events.hostile_deficit_dps);
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
    out.set(
        "spawned_hangar_sids",
        &vec_to_packed_i32(&events.spawned_hangar_sids),
    );
    out
}

/// Legacy builder-step dict adapter (unused under logistics authority; kept for API parity).
#[allow(dead_code)]
pub fn builder_step_events_dict(events: &BuilderStepEvents) -> GdDictionary {
    logistics_step_events_dict_from_builder(events)
}

pub fn logistics_step_events_dict(events: &LogisticsStepEvents) -> GdDictionary {
    let mut out = GdDictionary::new();
    out.set("visual_dirty", events.visual_dirty);
    let mut arrivals = Array::<Variant>::new();
    for ev in &events.cell_arrivals {
        let mut entry = GdDictionary::new();
        entry.set("sid", ev.sid);
        entry.set("seg_from_idx", ev.seg_from_idx);
        entry.set("kind", &GString::from(logistics_kind_str(ev.kind)));
        arrivals.push(&entry);
    }
    out.set("cell_arrivals", &arrivals);
    let mut completions = Array::<Variant>::new();
    for ev in &events.path_completions {
        let entry = logistics_path_completion_dict(ev);
        completions.push(&entry);
    }
    out.set("path_completions", &completions);
    out.set(
        "completed_corridor_sids",
        &vec_to_packed_i32(&events.completed_corridor_sids),
    );
    out.set("new_built_cells", &vec_to_packed_i32(&events.new_built_cells));
    out.set("friendly_output_mult", events.friendly_output_mult);
    out.set("hostile_output_mult", events.hostile_output_mult);
    // I9: network-wide version for Godot caches — never per-cell.
    out.set("road_network_version", events.road_network_version as i64);
    out.set("reconcile_cells_examined", events.reconcile_cells_examined as i64);
    out.set("reassign_teams", &PackedByteArray::new());
    out
}

pub fn logistics_step_events_dict_from_builder(events: &BuilderStepEvents) -> GdDictionary {
    let mut out = GdDictionary::new();
    out.set("visual_dirty", events.visual_dirty);
    let mut arrivals = Array::<Variant>::new();
    for ev in &events.cell_arrivals {
        let mut entry = GdDictionary::new();
        entry.set("sid", ev.sid);
        entry.set("seg_from_idx", ev.seg_from_idx);
        entry.set("kind", &GString::from(builders_kind_str(ev.kind)));
        arrivals.push(&entry);
    }
    out.set("cell_arrivals", &arrivals);
    let mut completions = Array::<Variant>::new();
    for ev in &events.path_completions {
        let entry = path_completion_dict(ev);
        completions.push(&entry);
    }
    out.set("path_completions", &completions);
    out.set(
        "completed_corridor_sids",
        &vec_to_packed_i32(&events.completed_corridor_sids),
    );
    out.set("new_built_cells", &PackedInt32Array::new());
    out.set("friendly_output_mult", 1.0f32);
    out.set("hostile_output_mult", 1.0f32);
    out.set("road_network_version", 0i64);
    out.set("reconcile_cells_examined", 0i64);
    let mut teams = PackedByteArray::new();
    for t in &events.reassign_teams {
        teams.push(*t);
    }
    out.set("reassign_teams", &teams);
    out
}

fn logistics_path_completion_dict(ev: &LogisticsPathCompletion) -> GdDictionary {
    let mut entry = GdDictionary::new();
    entry.set("sid", ev.sid);
    entry.set("gx", ev.gx);
    entry.set("gy", ev.gy);
    entry.set("team", ev.team);
    entry.set("is_corridor_link", ev.is_corridor_link);
    entry.set("kind", &GString::from(logistics_kind_str(ev.kind)));
    entry
}

fn path_completion_dict(ev: &PathCompletionEvent) -> GdDictionary {
    let mut entry = GdDictionary::new();
    entry.set("sid", ev.sid);
    entry.set("gx", ev.gx);
    entry.set("gy", ev.gy);
    entry.set("team", ev.team);
    entry.set("is_corridor_link", ev.is_corridor_link);
    entry.set("kind", &GString::from(builders_kind_str(ev.kind)));
    entry
}

pub fn f32_triple_from_array(arr: &PackedFloat32Array) -> [f32; 3] {
    [
        arr.get(0).unwrap_or(0.0),
        arr.get(1).unwrap_or(0.0),
        arr.get(2).unwrap_or(0.0),
    ]
}

pub fn claimable_delta_dict(delta: &ClaimableDelta) -> GdDictionary {
    let mut d = GdDictionary::new();
    d.set("indices", &vec_to_packed_i32(&delta.indices));
    d.set("claimable", &vec_to_packed_byte(&delta.claimable));
    d.set("owners", &vec_to_packed_byte(&delta.owners));
    d.set("elevation", &vec_to_packed_f32(&delta.elevation));
    d.set("flow_mult", &vec_to_packed_f32(&delta.terrain_flow_mult));
    d.set("claim_mult", &vec_to_packed_f32(&delta.claim_ratio_mult));
    d
}

pub fn world_edit_result_dict(result: &WorldEditResult) -> GdDictionary {
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

pub fn corridor_specs_from_array(specs: Array<Variant>) -> Vec<CorridorPathSpec> {
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

pub fn spawners_from_dict(config: &GdDictionary) -> Vec<Spawner> {
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
