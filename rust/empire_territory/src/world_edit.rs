//! World-edit operations (beachhead, bridge corridors, claimable) — Phase 3 authority in Rust.

use crate::sim::{
    TerritoryKernel, OWNER_FRIENDLY, OWNER_NEUTRAL, OWNER_UNCLAIMABLE,
};

const HEIGHT_MAX: f32 = 100.0;
const IMPASSABLE_MOVE_COST: f32 = 50.0;
const BRIDGE_PRESSURE_FLOW_MULT: f32 = 2.8;

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
                self.grid_w,
                self.grid_h,
                &self.passable_mask,
                gx,
                gy,
                &mut self.friendly_reachable,
                &mut touched,
            )
        } else {
            flood_passable_into_mask(
                self.grid_w,
                self.grid_h,
                &self.passable_mask,
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
                    self.grid_w,
                    self.grid_h,
                    &self.passable_mask,
                    gx,
                    gy,
                    &mut self.friendly_reachable,
                    &mut Vec::new(),
                )
            } else {
                flood_passable_into_mask(
                    self.grid_w,
                    self.grid_h,
                    &self.passable_mask,
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

    pub fn sync_bridge_corridors(
        &mut self,
        specs: &[CorridorPathSpec],
        force_full: bool,
    ) -> WorldEditResult {
        let mut out = WorldEditResult::default();
        if !self.world_edit_ready || specs.is_empty() && !force_full {
            return out;
        }
        let mut touched = Vec::new();
        if force_full {
            self.friendly_bridge_reachable.fill(0);
            self.hostile_bridge_reachable.fill(0);
            self.friendly_corridor_land.fill(0);
            self.hostile_corridor_land.fill(0);
        }
        for spec in specs {
            let new_synced = self.sync_corridor_path_cells(
                spec.team,
                &spec.path_keys,
                spec.built_cells,
                if force_full { 1 } else { spec.synced_cells },
                &mut touched,
            );
            out.synced_updates.push((spec.sid, new_synced));
        }
        let nav_reconciled = self.reconcile_corridor_land_nav(specs);
        if !touched.is_empty() {
            let delta = self.apply_claimable_cells(&touched);
            out.changed = !delta.indices.is_empty();
            out.claimable_delta = delta;
        }
        if nav_reconciled {
            out.changed = true;
        }
        out
    }

    fn sync_corridor_path_cells(
        &mut self,
        team: u8,
        packed: &[i32],
        built_cells: i32,
        synced_cells: i32,
        touched: &mut Vec<i32>,
    ) -> i32 {
        if packed.is_empty() {
            return synced_cells;
        }
        let built_cells = built_cells.clamp(1, packed.len() as i32);
        let synced_cells = synced_cells.clamp(1, built_cells);
        let land_reach = if team == OWNER_FRIENDLY {
            self.friendly_reachable.clone()
        } else {
            self.hostile_reachable.clone()
        };
        let src_idx = packed[0] as usize;
        if src_idx >= self.tile_count || land_reach[src_idx] == 0 {
            return synced_cells;
        }
        if synced_cells <= 1 {
            let src_gx = (src_idx as i32) % self.grid_w;
            let src_gy = (src_idx as i32) / self.grid_w;
            if land_at(&self.land_mask, self.grid_w, self.grid_h, src_gx, src_gy)
                && self.corridor_land_mut(team)[src_idx] == 0
            {
                self.corridor_land_mut(team)[src_idx] = 1;
            }
        }
        if synced_cells >= built_cells {
            return built_cells;
        }
        let mut chain_ok = true;
        for i in 1..synced_cells as usize {
            let prev_key = packed[i] as usize;
            if prev_key >= self.tile_count {
                chain_ok = false;
                break;
            }
            let bridge = self.bridge_mask(team);
            let corridor = self.corridor_land(team);
            if bridge[prev_key] == 0 && corridor[prev_key] == 0 && land_reach[prev_key] == 0 {
                chain_ok = false;
                break;
            }
        }
        for i in synced_cells as usize..built_cells as usize {
            let cell_key = packed[i] as usize;
            if cell_key >= self.tile_count {
                chain_ok = false;
                continue;
            }
            if !chain_ok {
                continue;
            }
            let gx = (cell_key as i32) % self.grid_w;
            let gy = (cell_key as i32) / self.grid_w;
            if !land_at(&self.land_mask, self.grid_w, self.grid_h, gx, gy) {
                if self.bridge_mask_mut(team)[cell_key] == 0 {
                    self.bridge_mask_mut(team)[cell_key] = 1;
                    touched.push(packed[i]);
                }
            } else if self.corridor_land_mut(team)[cell_key] == 0 {
                self.corridor_land_mut(team)[cell_key] = 1;
                if land_reach[cell_key] == 0 {
                    touched.push(packed[i]);
                }
            }
        }
        built_cells
    }

    fn bridge_mask(&self, team: u8) -> &[u8] {
        if team == OWNER_FRIENDLY {
            &self.friendly_bridge_reachable
        } else {
            &self.hostile_bridge_reachable
        }
    }

    fn bridge_mask_mut(&mut self, team: u8) -> &mut [u8] {
        if team == OWNER_FRIENDLY {
            &mut self.friendly_bridge_reachable
        } else {
            &mut self.hostile_bridge_reachable
        }
    }

    fn corridor_land(&self, team: u8) -> &[u8] {
        if team == OWNER_FRIENDLY {
            &self.friendly_corridor_land
        } else {
            &self.hostile_corridor_land
        }
    }

    fn corridor_land_mut(&mut self, team: u8) -> &mut [u8] {
        if team == OWNER_FRIENDLY {
            &mut self.friendly_corridor_land
        } else {
            &mut self.hostile_corridor_land
        }
    }

    fn reconcile_corridor_land_nav(&mut self, specs: &[CorridorPathSpec]) -> bool {
        let mut any = false;
        for spec in specs {
            if self.reconcile_packed_corridor_land(spec.team, &spec.path_keys, spec.built_cells) {
                any = true;
            }
        }
        any
    }

    fn reconcile_packed_corridor_land(
        &mut self,
        team: u8,
        packed: &[i32],
        built_cells: i32,
    ) -> bool {
        if packed.is_empty() || built_cells <= 0 {
            return false;
        }
        let n = (built_cells as usize).min(packed.len());
        let mut any = false;
        for i in 0..n {
            let cell_key = packed[i] as usize;
            if cell_key >= self.tile_count {
                continue;
            }
            let gx = (cell_key as i32) % self.grid_w;
            let gy = (cell_key as i32) / self.grid_w;
            if land_at(&self.land_mask, self.grid_w, self.grid_h, gx, gy)
                && self.corridor_land_mut(team)[cell_key] == 0
            {
                self.corridor_land_mut(team)[cell_key] = 1;
                any = true;
            }
        }
        any
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
    grid_w: i32,
    grid_h: i32,
    passable_mask: &[u8],
    start_gx: i32,
    start_gy: i32,
    mask: &mut [u8],
    touched: &mut Vec<i32>,
) -> bool {
    let start_idx = cell_index(start_gx, start_gy, grid_w, grid_h);
    if start_idx < 0 {
        return false;
    }
    let start_ui = start_idx as usize;
    if start_ui >= passable_mask.len() || passable_mask[start_ui] == 0 || start_ui >= mask.len() {
        return false;
    }
    let mut any_new = false;
    if mask[start_ui] == 0 {
        mask[start_ui] = 1;
        any_new = true;
        touched.push(start_idx);
    }
    let mut queue = vec![(start_gx, start_gy)];
    let mut head = 0usize;
    while head < queue.len() {
        let (cx, cy) = queue[head];
        head += 1;
        for (dx, dy) in crate::sim::CARDINAL {
            let nx = cx + dx;
            let ny = cy + dy;
            if nx < 0 || ny < 0 || nx >= grid_w || ny >= grid_h {
                continue;
            }
            let nidx = cell_index(nx, ny, grid_w, grid_h);
            if nidx < 0 {
                continue;
            }
            let nui = nidx as usize;
            if nui >= passable_mask.len() || passable_mask[nui] == 0 || nui >= mask.len() {
                continue;
            }
            if mask[nui] != 0 {
                continue;
            }
            mask[nui] = 1;
            any_new = true;
            touched.push(nidx);
            queue.push((nx, ny));
        }
    }
    any_new
}
