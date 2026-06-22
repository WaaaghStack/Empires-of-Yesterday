//! Empire Territory Sim — Rust GDExtension for high-performance territory conquest simulation.

mod agents;
mod fluid_bake;
mod route;
mod sim;
mod tape_codec;

use fluid_bake::bake_fluid_rgba;
use godot::builtin::Variant;
use godot::prelude::*;
use rayon::prelude::*;
use std::sync::Arc;
use agents::{AgentConfig, AgentLayer};
use route::{
    find_route, PortalGraph, RoutePlannerState, RouteSnapshot,
};
use sim::{Spawner, TerritoryKernel};
use tape_codec::{decode_pressure_v2, encode_pressure_v2, pack_territory_tape_v2};

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
        );
    }

    #[func]
    fn update_bridge_pipe(
        &mut self,
        bridge_pipe_prev: PackedInt32Array,
        bridge_pipe_next: PackedInt32Array,
        bridge_water_mask: PackedByteArray,
        corridor_land_mask: PackedByteArray,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        let prev: Vec<i32> = (0..bridge_pipe_prev.len())
            .map(|i| bridge_pipe_prev.get(i).unwrap_or(-1))
            .collect();
        let next: Vec<i32> = (0..bridge_pipe_next.len())
            .map(|i| bridge_pipe_next.get(i).unwrap_or(-1))
            .collect();
        kernel.update_bridge_pipe(
            prev,
            next,
            packed_byte_to_vec(&bridge_water_mask),
            packed_byte_to_vec(&corridor_land_mask),
        );
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
    fn inject_corridor_pressure_pulse(
        &mut self,
        path_keys: PackedInt32Array,
        team: u8,
        amount_scale: f32,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        let keys: Vec<i32> = (0..path_keys.len())
            .map(|i| path_keys.get(i).unwrap_or(-1))
            .collect();
        kernel.inject_corridor_pressure_pulse(&keys, team, amount_scale);
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
        let mut out = GdDictionary::new();
        out.set("owner_indices", &vec_to_packed_i32(&idx));
        out.set("owner_values", &vec_to_packed_byte(&vals));
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
        let snap = match self.state.snapshot.lock().ok().and_then(|g| g.clone()) {
            Some(s) => s,
            None => return out,
        };
        let portal = match self.state.portal.lock() {
            Ok(g) => g.clone(),
            Err(_) => return out,
        };
        if let Some(res) = find_route(&snap, &portal, target_gx, target_gy, kind, allow_astar) {
            out.set("path_packed", &vec_to_packed_i32(&res.path));
            out.set("source_key", res.source_key);
            out.set("found", true);
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
