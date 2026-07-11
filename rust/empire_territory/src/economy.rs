//! Compiled content tables for World Conquest — populated once from GDScript bake.

use crate::logistics::LogisticsConfig;
use crate::structures::{KIND_BARRACKS, KIND_CORRIDOR_LINK, KIND_HANGAR, KIND_SPAWNER};
use crate::world_session::WorldSessionConfig;

pub const MAX_KINDS: usize = 4;
pub const MAX_UNITS: usize = 2;
pub const RESOURCE_SLOTS: usize = 3;

pub const UNIT_SOLDIER: usize = 0;
pub const UNIT_BOMBER: usize = 1;

#[derive(Clone, Debug)]
pub struct ContentTables {
    pub structure_build_sec: [f32; MAX_KINDS],
    pub structure_max_health: [f32; MAX_KINDS],
    pub structure_logistics_drain: [f32; MAX_KINDS],
    pub structure_spawn_interval: [f32; MAX_KINDS],
    pub structure_spawn_max_active: [u32; MAX_KINDS],
    /// -1 when structure does not spawn units.
    pub structure_spawn_unit: [i32; MAX_KINDS],
    pub structure_spawn_resources: [[f32; RESOURCE_SLOTS]; MAX_KINDS],
    pub unit_global_cap: [u32; MAX_UNITS],
    pub unit_upkeep_resources: [[f32; RESOURCE_SLOTS]; MAX_UNITS],
}

impl Default for ContentTables {
    fn default() -> Self {
        let mut spawn_resources = [[0.0f32; RESOURCE_SLOTS]; MAX_KINDS];
        spawn_resources[KIND_BARRACKS as usize][0] = 3.0;
        spawn_resources[KIND_HANGAR as usize][0] = 3.0;
        Self {
            structure_build_sec: [5.0, 60.0, 0.0, 60.0],
            structure_max_health: [10.0; MAX_KINDS],
            structure_logistics_drain: [0.04, 0.06, 0.03, 0.06],
            structure_spawn_interval: [0.0, 10.0, 0.0, 10.0],
            structure_spawn_max_active: [0, 5, 0, 5],
            structure_spawn_unit: [-1, UNIT_SOLDIER as i32, -1, UNIT_BOMBER as i32],
            structure_spawn_resources: spawn_resources,
            unit_global_cap: [100, 100],
            unit_upkeep_resources: [[0.15, 0.0, 0.0], [0.0, 0.0, 0.0]],
        }
    }
}

impl ContentTables {
    pub fn soldier_spawn_cost(&self) -> f32 {
        self.structure_spawn_resources[KIND_BARRACKS as usize][0]
    }

    pub fn bomber_spawn_cost(&self) -> f32 {
        self.structure_spawn_resources[KIND_HANGAR as usize][0]
    }

    pub fn can_afford_resources(wallet: &[f32; RESOURCE_SLOTS], cost: &[f32; RESOURCE_SLOTS]) -> bool {
        wallet[0] >= cost[0] && wallet[1] >= cost[1] && wallet[2] >= cost[2]
    }

    pub fn apply_resource_cost(wallet: &mut [f32; RESOURCE_SLOTS], cost: &[f32; RESOURCE_SLOTS]) {
        for i in 0..RESOURCE_SLOTS {
            wallet[i] -= cost[i];
        }
    }

    pub fn apply_to_logistics(&self, cfg: &mut LogisticsConfig, road_cells_per_sec: f32) {
        cfg.road_cells_per_sec = road_cells_per_sec;
        cfg.outpost_build_sec = self.structure_build_sec[KIND_SPAWNER as usize];
        cfg.barracks_build_sec = self.structure_build_sec[KIND_BARRACKS as usize];
        cfg.hangar_build_sec = self.structure_build_sec[KIND_HANGAR as usize];
        cfg.outpost_max_health = self.structure_max_health[KIND_SPAWNER as usize];
        cfg.structure_drain_spawner = self.structure_logistics_drain[KIND_SPAWNER as usize];
        cfg.structure_drain_barracks = self.structure_logistics_drain[KIND_BARRACKS as usize];
        cfg.structure_drain_hangar = self.structure_logistics_drain[KIND_HANGAR as usize];
        cfg.structure_drain_corridor = self.structure_logistics_drain[KIND_CORRIDOR_LINK as usize];
    }

    pub fn apply_to_world_session(
        &self,
        cfg: &mut WorldSessionConfig,
        outpost_enemy_dps: f32,
        upkeep_deficit_dps: f32,
    ) {
        cfg.outpost_build_sec = self.structure_build_sec[KIND_SPAWNER as usize];
        cfg.barracks_build_sec = self.structure_build_sec[KIND_BARRACKS as usize];
        cfg.hangar_build_sec = self.structure_build_sec[KIND_HANGAR as usize];
        cfg.outpost_max_health = self.structure_max_health[KIND_SPAWNER as usize];
        cfg.outpost_enemy_dps = outpost_enemy_dps;
        cfg.barracks_spawn_interval = self.structure_spawn_interval[KIND_BARRACKS as usize];
        cfg.barracks_max_active = self.structure_spawn_max_active[KIND_BARRACKS as usize];
        cfg.global_soldier_cap = self.unit_global_cap[UNIT_SOLDIER];
        cfg.soldier_spawn_cost = self.soldier_spawn_cost();
        cfg.hangar_spawn_interval = self.structure_spawn_interval[KIND_HANGAR as usize];
        cfg.hangar_max_active = self.structure_spawn_max_active[KIND_HANGAR as usize];
        cfg.global_bomber_cap = self.unit_global_cap[UNIT_BOMBER];
        cfg.bomber_spawn_cost = self.bomber_spawn_cost();
        cfg.soldier_upkeep_per_sec = self.unit_upkeep_resources[UNIT_SOLDIER][0];
        cfg.upkeep_deficit_dps = upkeep_deficit_dps;
    }
}

pub fn f32_at(packed: &[f32], idx: usize, default: f32) -> f32 {
    packed.get(idx).copied().unwrap_or(default)
}

pub fn u32_at(packed: &[i32], idx: usize, default: u32) -> u32 {
    packed
        .get(idx)
        .copied()
        .map(|v| v.max(0) as u32)
        .unwrap_or(default)
}

pub fn i32_at(packed: &[i32], idx: usize, default: i32) -> i32 {
    packed.get(idx).copied().unwrap_or(default)
}

pub fn fill_structure_row(
    tables: &mut ContentTables,
    kind: usize,
    build_sec: f32,
    max_health: f32,
    logistics_drain: f32,
    spawn_interval: f32,
    spawn_max_active: u32,
    spawn_unit: i32,
    spawn_resources: [f32; RESOURCE_SLOTS],
) {
    if kind >= MAX_KINDS {
        return;
    }
    tables.structure_build_sec[kind] = build_sec;
    tables.structure_max_health[kind] = max_health;
    tables.structure_logistics_drain[kind] = logistics_drain;
    tables.structure_spawn_interval[kind] = spawn_interval;
    tables.structure_spawn_max_active[kind] = spawn_max_active;
    tables.structure_spawn_unit[kind] = spawn_unit;
    tables.structure_spawn_resources[kind] = spawn_resources;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_soldier_spawn_cost() {
        let t = ContentTables::default();
        assert!((t.soldier_spawn_cost() - 3.0).abs() < f32::EPSILON);
    }
}
