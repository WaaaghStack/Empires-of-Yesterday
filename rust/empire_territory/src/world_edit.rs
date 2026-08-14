//! World-edit operations (beachhead, bridge corridors, claimable) — Phase 3 authority in Rust.

use crate::flow_constants::BRIDGE_PRESSURE_FLOW_MULT;
use crate::sim::{
    TerritoryKernel, OWNER_FRIENDLY, OWNER_NEUTRAL, OWNER_UNCLAIMABLE,
};

const HEIGHT_MAX: f32 = 100.0;
const IMPASSABLE_MOVE_COST: f32 = 50.0;

#[derive(Clone, Debug, Default)]
pub struct ClaimableDelta {
    pub indices: Vec<i32>,
    pub claimable: Vec<u8>,
    pub owners: Vec<u8>,
    pub elevation: Vec<f32>,
    pub terrain_flow_mult: Vec<f32>,
    pub claim_ratio_mult: Vec<f32>,
}

#[derive(Clone, Debug)]
pub struct CorridorPathSpec {
    pub sid: i32,
    pub team: u8,
    pub path_keys: Vec<i32>,
    pub built_cells: i32,
    pub synced_cells: i32,
}

#[derive(Clone, Debug, Default)]
pub struct WorldEditResult {
    pub changed: bool,
    pub claimable_delta: ClaimableDelta,
    pub synced_updates: Vec<(i32, i32)>,
}

impl TerritoryKernel {
    pub fn init_world_terrain(
        &mut self,
        passable_mask: Vec<u8>,
        land_mask: Vec<u8>,
        tile_height: Vec<f32>,
        move_cost: Vec<f32>,
        defense: Vec<f32>,
        cover_cells: Vec<u8>,
    ) {
        if passable_mask.len() == self.tile_count {
            self.passable_mask = passable_mask;
        }
        if land_mask.len() == self.tile_count {
            self.land_mask = land_mask;
        }
        if tile_height.len() == self.tile_count {
            self.tile_height = tile_height;
        }
        if move_cost.len() == self.tile_count {
            self.move_cost = move_cost;
        }
        if defense.len() == self.tile_count {
            self.defense = defense;
        }
        if cover_cells.len() == self.tile_count {
            self.cover_cells = cover_cells;
        }
        self.world_edit_ready = !self.passable_mask.is_empty() && !self.land_mask.is_empty();
    }

    pub fn init_reachability_masks(
        &mut self,
        friendly_reachable: Vec<u8>,
        hostile_reachable: Vec<u8>,
        friendly_bridge: Vec<u8>,
        hostile_bridge: Vec<u8>,
        friendly_corridor: Vec<u8>,
        hostile_corridor: Vec<u8>,
    ) {
        if friendly_reachable.len() == self.tile_count {
            self.friendly_reachable = friendly_reachable;
        }
        if hostile_reachable.len() == self.tile_count {
            self.hostile_reachable = hostile_reachable;
        }
        if friendly_bridge.len() == self.tile_count {
            self.friendly_bridge_reachable = friendly_bridge;
        }
        if hostile_bridge.len() == self.tile_count {
            self.hostile_bridge_reachable = hostile_bridge;
        }
        if friendly_corridor.len() == self.tile_count {
            self.friendly_corridor_land = friendly_corridor;
        }
        if hostile_corridor.len() == self.tile_count {
            self.hostile_corridor_land = hostile_corridor;
        }
    }

    pub fn extend_beachhead_from_landing(&mut self, gx: i32, gy: i32, team: u8) -> WorldEditResult {
        let mut out = WorldEditResult::default();
        if !self.world_edit_ready {
            return out;
        }
        let mut touched = Vec::new();
        let flooded = if team == OWNER_FRIENDLY {
            flood_passable_into_mask(
                self.graph_topology,
                &self.neighbors,
                &self.neighbor_count,
                self.tile_count,
                self.grid_w,
                self.grid_h,
                self.wrap_longitude,
                // Land only — never flood claimable across ocean (ferry transit uses land_mask separately).
                &self.land_mask,
                gx,
                gy,
                &mut self.friendly_reachable,
                &mut touched,
            )
        } else {
            flood_passable_into_mask(
                self.graph_topology,
                &self.neighbors,
                &self.neighbor_count,
                self.tile_count,
                self.grid_w,
                self.grid_h,
                self.wrap_longitude,
                &self.land_mask,
                gx,
                gy,
                &mut self.hostile_reachable,
                &mut touched,
            )
        };
        if !flooded {
            return out;
        }
        out.claimable_delta = self.apply_claimable_cells(&touched);
        out.changed = !out.claimable_delta.indices.is_empty();
        out
    }

    pub fn extend_reachability_from_spawners(&mut self) -> WorldEditResult {
        let mut out = WorldEditResult::default();
        if !self.world_edit_ready || self.spawners.is_empty() {
            return out;
        }
        let spawners: Vec<(u8, i32, i32)> = self
            .spawners
            .iter()
            .map(|sp| (sp.team, sp.gx, sp.gy))
            .collect();
        let mut any_new = false;
        for (team, gx, gy) in spawners {
            let flooded = if team == OWNER_FRIENDLY {
                flood_passable_into_mask(
                    self.graph_topology,
                    &self.neighbors,
                    &self.neighbor_count,
                    self.tile_count,
                    self.grid_w,
                    self.grid_h,
                    self.wrap_longitude,
                    &self.land_mask,
                    gx,
                    gy,
                    &mut self.friendly_reachable,
                    &mut Vec::new(),
                )
            } else {
                flood_passable_into_mask(
                    self.graph_topology,
                    &self.neighbors,
                    &self.neighbor_count,
                    self.tile_count,
                    self.grid_w,
                    self.grid_h,
                    self.wrap_longitude,
                    &self.land_mask,
                    gx,
                    gy,
                    &mut self.hostile_reachable,
                    &mut Vec::new(),
                )
            };
            if flooded {
                any_new = true;
            }
        }
        if any_new {
            out.claimable_delta = self.apply_reachability_to_claimable();
            out.changed = !out.claimable_delta.indices.is_empty();
        }
        out
    }

    /// R1: land bridges are removed. Corridor cells never stamp bridge / corridor-land masks,
    /// so this only drops any stale bridge reachability left over from a pre-R1 save and then
    /// reports the resulting claimable delta. Ferry beachheads open whole landmasses for
    /// infantry; air strikes open a single cell via `open_claimable_for_air_strike`.
    pub fn sync_bridge_corridors(
        &mut self,
        specs: &[CorridorPathSpec],
        _force_full: bool,
    ) -> WorldEditResult {
        let mut out = WorldEditResult::default();
        // Every corridor reports "fully synced" so Godot stops re-submitting the same path.
        for spec in specs {
            let synced = spec.path_keys.len().max(1) as i32;
            out.synced_updates.push((spec.sid, synced));
        }
        if !self.world_edit_ready {
            return out;
        }
        let stale: Vec<i32> = (0..self.tile_count)
            .filter(|&idx| {
                self.friendly_bridge_reachable[idx] != 0
                    || self.hostile_bridge_reachable[idx] != 0
                    || self.friendly_corridor_land[idx] != 0
                    || self.hostile_corridor_land[idx] != 0
            })
            .map(|idx| idx as i32)
            .collect();
        if stale.is_empty() {
            return out;
        }
        self.friendly_bridge_reachable.fill(0);
        self.hostile_bridge_reachable.fill(0);
        self.friendly_corridor_land.fill(0);
        self.hostile_corridor_land.fill(0);
        let delta = self.apply_claimable_cells(&stale);
        out.changed = !delta.indices.is_empty();
        out.claimable_delta = delta;
        out
    }

    fn apply_claimable_cells(&mut self, cell_indices: &[i32]) -> ClaimableDelta {
        let mut delta = ClaimableDelta::default();
        if cell_indices.is_empty() {
            return delta;
        }
        for &cell_key in cell_indices {
            let idx = cell_key as usize;
            if idx >= self.tile_count {
                continue;
            }
            let gx = (idx as i32) % self.grid_w;
            let gy = (idx as i32) / self.grid_w;
            let was = self.claimable_mask[idx];
            let now = self.is_claimable_index(idx);
            if now == (was != 0) {
                continue;
            }
            self.apply_claimable_at(idx, gx, gy, now);
            delta.indices.push(cell_key);
            delta.claimable.push(self.claimable_mask[idx]);
            delta.owners.push(self.owners[idx]);
            delta.elevation.push(self.elevation[idx]);
            delta.terrain_flow_mult.push(self.terrain_flow_mult[idx]);
            delta.claim_ratio_mult.push(self.claim_ratio_mult[idx]);
        }
        if !delta.indices.is_empty() {
            self.frontier_changed = true;
            if self.use_active_set {
                self.rebuild_active_indices();
            }
        }
        delta
    }

    fn apply_reachability_to_claimable(&mut self) -> ClaimableDelta {
        let mut delta = ClaimableDelta::default();
        for idx in 0..self.tile_count {
            let gx = (idx as i32) % self.grid_w;
            let gy = (idx as i32) / self.grid_w;
            let was = self.claimable_mask[idx];
            let now = self.is_claimable_index(idx);
            if now == (was != 0) {
                continue;
            }
            self.apply_claimable_at(idx, gx, gy, now);
            delta.indices.push(idx as i32);
            delta.claimable.push(self.claimable_mask[idx]);
            delta.owners.push(self.owners[idx]);
            delta.elevation.push(self.elevation[idx]);
            delta.terrain_flow_mult.push(self.terrain_flow_mult[idx]);
            delta.claim_ratio_mult.push(self.claim_ratio_mult[idx]);
        }
        self.recount_ownership_tiles();
        self.frontier_changed = true;
        if self.use_active_set {
            self.rebuild_active_indices();
        }
        delta
    }

    fn apply_claimable_at(&mut self, idx: usize, gx: i32, gy: i32, now: bool) {
        if now {
            self.set_claimable_mask_at(idx, 1);
            self.elevation[idx] = self.tile_elevation_at(gx, gy);
            self.terrain_flow_mult[idx] = self.flow_mult_for_bridge_or_land(gx, gy, idx);
            self.claim_ratio_mult[idx] = self.claim_mult_for_tile(gx, gy, true);
            if self.owners[idx] == OWNER_UNCLAIMABLE {
                self.set_owner_at(idx, OWNER_NEUTRAL);
            } else {
                self.bump_nav_dirty(idx);
                self.mark_active_dirty(idx);
                self.refresh_display_at(idx);
            }
        } else {
            self.set_claimable_mask_at(idx, 0);
            self.set_owner_at(idx, OWNER_UNCLAIMABLE);
            self.pressure_friendly[idx] = 0.0;
            self.pressure_hostile[idx] = 0.0;
            self.mark_active_dirty(idx);
        }
    }

    /// Air strike: open one land cell for ownership (no island flood).
    /// Stamps team reachability so later reachability rebuilds do not wipe the paint.
    pub fn open_claimable_for_air_strike(&mut self, idx: usize, team: u8) {
        if idx >= self.tile_count {
            return;
        }
        let gx = (idx as i32) % self.grid_w;
        let gy = (idx as i32) / self.grid_w;
        if !self.is_land(gx, gy) {
            return;
        }
        if self.claimable_mask[idx] != 0 {
            return;
        }
        if team == OWNER_FRIENDLY {
            if idx < self.friendly_reachable.len() {
                self.friendly_reachable[idx] = 1;
            }
        } else if idx < self.hostile_reachable.len() {
            self.hostile_reachable[idx] = 1;
        }
        self.apply_claimable_at(idx, gx, gy, true);
    }

    fn is_claimable_index(&self, idx: usize) -> bool {
        if idx >= self.tile_count {
            return false;
        }
        let gx = (idx as i32) % self.grid_w;
        let gy = (idx as i32) / self.grid_w;
        if self.is_land(gx, gy) {
            return self.friendly_reachable[idx] > 0
                || self.hostile_reachable[idx] > 0
                || self.friendly_corridor_land[idx] > 0
                || self.hostile_corridor_land[idx] > 0;
        }
        self.friendly_bridge_reachable[idx] > 0 || self.hostile_bridge_reachable[idx] > 0
    }

    fn is_land(&self, gx: i32, gy: i32) -> bool {
        land_at(&self.land_mask, self.grid_w, self.grid_h, gx, gy)
    }

    fn is_passable(&self, gx: i32, gy: i32) -> bool {
        let idx = cell_index(gx, gy, self.grid_w, self.grid_h);
        if idx < 0 {
            return false;
        }
        self.passable_mask.get(idx as usize).copied().unwrap_or(0) > 0
    }

    fn is_bridge_water_index(&self, idx: usize) -> bool {
        if idx >= self.tile_count {
            return false;
        }
        let gx = (idx as i32) % self.grid_w;
        let gy = (idx as i32) / self.grid_w;
        if self.is_land(gx, gy) {
            return false;
        }
        self.friendly_bridge_reachable[idx] > 0 || self.hostile_bridge_reachable[idx] > 0
    }

    fn tile_elevation_at(&self, gx: i32, gy: i32) -> f32 {
        let idx = cell_index(gx, gy, self.grid_w, self.grid_h);
        if idx < 0 {
            return 0.0;
        }
        let h = self.tile_height.get(idx as usize).copied().unwrap_or(0.0);
        h.clamp(0.0, 1.0) * HEIGHT_MAX
    }

    fn flow_mult_for_tile(&self, gx: i32, gy: i32, claimable: bool) -> f32 {
        if !claimable {
            return 0.0;
        }
        let idx = cell_index(gx, gy, self.grid_w, self.grid_h);
        if idx < 0 {
            return 0.0;
        }
        let mv = self.move_cost.get(idx as usize).copied().unwrap_or(IMPASSABLE_MOVE_COST);
        if mv >= IMPASSABLE_MOVE_COST {
            return 0.0;
        }
        (1.0 / mv.max(1.0)).clamp(0.42, 1.05)
    }

    fn flow_mult_for_bridge_or_land(&self, gx: i32, gy: i32, idx: usize) -> f32 {
        if self.is_bridge_water_index(idx) {
            return BRIDGE_PRESSURE_FLOW_MULT;
        }
        self.flow_mult_for_tile(gx, gy, true)
    }

    fn claim_mult_for_tile(&self, gx: i32, gy: i32, claimable: bool) -> f32 {
        if !claimable {
            return 1.0;
        }
        let idx = cell_index(gx, gy, self.grid_w, self.grid_h);
        if idx < 0 {
            return 1.0;
        }
        let ui = idx as usize;
        let def = self.defense.get(ui).copied().unwrap_or(1.0);
        let mut mult = 1.0 + (def - 1.0) * 0.35;
        if self.cover_cells.get(ui).copied().unwrap_or(0) > 0 {
            mult += 0.1;
        }
        mult.clamp(1.0, 1.45)
    }

    pub fn friendly_reachable_mask(&self) -> &[u8] {
        &self.friendly_reachable
    }

    pub fn hostile_reachable_mask(&self) -> &[u8] {
        &self.hostile_reachable
    }

    pub fn friendly_bridge_mask(&self) -> &[u8] {
        &self.friendly_bridge_reachable
    }

    pub fn hostile_bridge_mask(&self) -> &[u8] {
        &self.hostile_bridge_reachable
    }

    pub fn friendly_corridor_mask(&self) -> &[u8] {
        &self.friendly_corridor_land
    }

    pub fn hostile_corridor_mask(&self) -> &[u8] {
        &self.hostile_corridor_land
    }
}

fn cell_index(gx: i32, gy: i32, grid_w: i32, grid_h: i32) -> i32 {
    if gx < 0 || gy < 0 || gx >= grid_w || gy >= grid_h {
        return -1;
    }
    gy * grid_w + gx
}

fn land_at(land_mask: &[u8], grid_w: i32, grid_h: i32, gx: i32, gy: i32) -> bool {
    let idx = cell_index(gx, gy, grid_w, grid_h);
    if idx < 0 {
        return false;
    }
    land_mask.get(idx as usize).copied().unwrap_or(0) > 0
}

fn flood_passable_into_mask(
    graph_topology: bool,
    neighbors: &[[i32; 6]],
    neighbor_count: &[u8],
    tile_count: usize,
    grid_w: i32,
    grid_h: i32,
    wrap_longitude: bool,
    passable_mask: &[u8],
    start_gx: i32,
    start_gy: i32,
    mask: &mut [u8],
    touched: &mut Vec<i32>,
) -> bool {
    let start_idx = if graph_topology {
        if start_gy == 0 && start_gx >= 0 && start_gx < grid_w as i32 {
            start_gx
        } else {
            -1
        }
    } else if start_gx < 0 || start_gy < 0 || start_gx >= grid_w || start_gy >= grid_h {
        -1
    } else {
        start_gy * grid_w + start_gx
    };
    if start_idx < 0 {
        return false;
    }
    let start_ui = start_idx as usize;
    if start_ui >= passable_mask.len()
        || passable_mask[start_ui] == 0
        || start_ui >= mask.len()
    {
        return false;
    }
    let mut any_new = false;
    if mask[start_ui] == 0 {
        mask[start_ui] = 1;
        any_new = true;
        touched.push(start_idx);
    }
    let mut queue = vec![start_ui];
    let mut head = 0usize;
    let mut neighbor_scratch = Vec::with_capacity(6);
    while head < queue.len() {
        let cur_ui = queue[head];
        head += 1;
        TerritoryKernel::collect_neighbors_static(
            graph_topology,
            neighbors,
            neighbor_count,
            tile_count,
            grid_w,
            grid_h,
            wrap_longitude,
            cur_ui,
            &mut neighbor_scratch,
        );
        for &nui in &neighbor_scratch {
            if nui >= passable_mask.len()
                || passable_mask[nui] == 0
                || nui >= mask.len()
            {
                continue;
            }
            if mask[nui] != 0 {
                continue;
            }
            mask[nui] = 1;
            any_new = true;
            touched.push(nui as i32);
            queue.push(nui);
        }
    }
    any_new
}

#[cfg(test)]
mod tests {
    use crate::sim::{TerritoryKernel, OWNER_FRIENDLY, OWNER_NEUTRAL};

    fn line_graph_kernel() -> TerritoryKernel {
        let n = 4;
        let mut neighbors = vec![[-1i32; 6]; n];
        let mut neighbor_count = vec![0u8; n];
        neighbors[0] = [1, -1, -1, -1, -1, -1];
        neighbor_count[0] = 1;
        neighbors[1] = [0, 2, -1, -1, -1, -1];
        neighbor_count[1] = 2;
        neighbors[2] = [1, 3, -1, -1, -1, -1];
        neighbor_count[2] = 2;
        neighbors[3] = [2, -1, -1, -1, -1, -1];
        neighbor_count[3] = 1;
        let mut k = TerritoryKernel::new(
            n as i32,
            1,
            vec![1u8; n],
            vec![0.0f32; n],
            vec![1.0f32; n],
            vec![1.0f32; n],
            vec![OWNER_NEUTRAL; n],
            vec![0.0f32; n],
            vec![0.0f32; n],
            0.0,
            0.0,
            0,
            -1,
            Vec::new(),
            0,
            0,
            false,
            false,
            false,
        );
        k.set_graph_neighbors(neighbors, neighbor_count);
        k.passable_mask = vec![1u8; n];
        k.land_mask = vec![1u8; n];
        k.friendly_reachable = vec![0u8; n];
        k.hostile_reachable = vec![0u8; n];
        k.world_edit_ready = true;
        k
    }

    #[test]
    fn graph_flood_reaches_beyond_cardinal_on_strip() {
        let mut k = line_graph_kernel();
        k.extend_beachhead_from_landing(0, 0, OWNER_FRIENDLY);
        assert!(k.friendly_reachable[0] > 0);
        assert!(k.friendly_reachable[1] > 0);
        assert!(
            k.friendly_reachable[2] > 0,
            "graph flood from cell 0 must reach cell 2 (not cardinal on 1×N strip)"
        );
        assert!(k.friendly_reachable[3] > 0);
    }
}
