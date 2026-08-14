//! Read-only grid probes for World Conquest (Phase 5 — Rust grid authority).

use crate::sim::{effective_height, TerritoryKernel, OWNER_UNCLAIMABLE};

#[derive(Clone, Copy, Debug)]
pub struct TileProbe {
    pub valid: bool,
    pub owner: u8,
    pub claimable: bool,
    pub pf: f32,
    pub ph: f32,
    pub f_bridge: bool,
    pub h_bridge: bool,
    pub f_corridor: bool,
    pub h_corridor: bool,
    pub f_reach: bool,
    pub h_reach: bool,
    pub flow_mult: f32,
    pub elev: f32,
    pub h_friendly: f32,
    pub h_hostile: f32,
}

impl TileProbe {
    fn invalid() -> Self {
        Self {
            valid: false,
            owner: OWNER_UNCLAIMABLE,
            claimable: false,
            pf: 0.0,
            ph: 0.0,
            f_bridge: false,
            h_bridge: false,
            f_corridor: false,
            h_corridor: false,
            f_reach: false,
            h_reach: false,
            flow_mult: 0.0,
            elev: 0.0,
            h_friendly: 0.0,
            h_hostile: 0.0,
        }
    }
}

impl TerritoryKernel {
    pub fn owner_at_index(&self, idx: usize) -> u8 {
        if idx >= self.tile_count {
            return OWNER_UNCLAIMABLE;
        }
        self.owners[idx]
    }

    pub fn claimable_at_index(&self, idx: usize) -> bool {
        idx < self.tile_count && self.claimable_mask[idx] != 0
    }

    pub fn claimable_tile_count(&self) -> i32 {
        self.claimable_tile_count
    }

    pub fn recount_claimable_tiles(&mut self) {
        self.claimable_tile_count = self
            .claimable_mask
            .iter()
            .filter(|&&c| c != 0)
            .count() as i32;
    }

    pub fn claim_ratio_mult_at(&self, idx: usize) -> f32 {
        if idx >= self.claim_ratio_mult.len() {
            return 1.0;
        }
        self.claim_ratio_mult[idx]
    }

    pub fn query_tile(&self, gx: i32, gy: i32) -> TileProbe {
        let idx = self.cell_index(gx, gy);
        if idx < 0 {
            return TileProbe::invalid();
        }
        let ui = idx as usize;
        if ui >= self.tile_count {
            return TileProbe::invalid();
        }
        let elev = self.elevation[ui];
        TileProbe {
            valid: true,
            owner: self.owners[ui],
            claimable: self.claimable_mask[ui] != 0,
            pf: self.pressure_friendly[ui],
            ph: self.pressure_hostile[ui],
            f_bridge: self.friendly_bridge_reachable[ui] != 0,
            h_bridge: self.hostile_bridge_reachable[ui] != 0,
            f_corridor: self.friendly_corridor_land[ui] != 0,
            h_corridor: self.hostile_corridor_land[ui] != 0,
            f_reach: self.friendly_reachable[ui] != 0,
            h_reach: self.hostile_reachable[ui] != 0,
            flow_mult: self.terrain_flow_mult[ui],
            elev,
            h_friendly: effective_height(self.pressure_friendly[ui], elev),
            h_hostile: effective_height(self.pressure_hostile[ui], elev),
        }
    }

    pub fn claim_tile_at(&mut self, gx: i32, gy: i32, team: u8) -> bool {
        let idx = self.cell_index(gx, gy);
        if idx < 0 {
            return false;
        }
        let ui = idx as usize;
        if ui >= self.tile_count || self.claimable_mask[ui] == 0 {
            return false;
        }
        if self.owners[ui] == team {
            return true;
        }
        self.set_owner_at(ui, team);
        true
    }
}
