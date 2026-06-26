//! Battle tile passability view for soldier nav rules (`NavGraph` for `TerritoryKernel`).

use crate::pathfind::graph::NavGraph;
use crate::pathfind::kernel::RouteContext;
use crate::sim::{TerritoryKernel, OWNER_FRIENDLY};

/// Per-team corridor + bridge masks synced from Godot / world-edit authority.
#[derive(Clone, Debug, Default)]
pub struct AgentNavMasks<'a> {
    pub friendly_corridor: &'a [u8],
    pub hostile_corridor: &'a [u8],
    pub friendly_bridge: &'a [u8],
    pub hostile_bridge: &'a [u8],
}

impl<'a> AgentNavMasks<'a> {
    pub fn corridor_for(&self, team: u8) -> &'a [u8] {
        if team == OWNER_FRIENDLY {
            self.friendly_corridor
        } else {
            self.hostile_corridor
        }
    }

    pub fn bridge_for(&self, team: u8) -> &'a [u8] {
        if team == OWNER_FRIENDLY {
            self.friendly_bridge
        } else {
            self.hostile_bridge
        }
    }
}

/// Read-only battle navigation graph — team selects which infra masks apply.
pub struct BattleNavView<'a> {
    pub kernel: &'a TerritoryKernel,
    pub masks: &'a AgentNavMasks<'a>,
    pub team: u8,
}

impl<'a> BattleNavView<'a> {
    pub fn new(kernel: &'a TerritoryKernel, masks: &'a AgentNavMasks<'a>, team: u8) -> Self {
        Self {
            kernel,
            masks,
            team,
        }
    }

    fn corridor(&self, idx: usize) -> bool {
        let c = self.masks.corridor_for(self.team);
        idx < c.len() && c[idx] != 0
    }

    fn bridge(&self, idx: usize) -> bool {
        let b = self.masks.bridge_for(self.team);
        idx < b.len() && b[idx] != 0
    }

    fn is_infra(&self, idx: usize) -> bool {
        self.corridor(idx) || self.bridge(idx)
    }

    /// Claimable land tile (not open water).
    pub fn is_land_cell(&self, idx: usize) -> bool {
        if idx >= self.kernel.tile_count {
            return false;
        }
        if !self.kernel.land_mask.is_empty() {
            return idx < self.kernel.land_mask.len() && self.kernel.land_mask[idx] != 0;
        }
        // Fallback when land_mask not synced: claimable non-bridge-water cells.
        self.kernel.claimable_mask[idx] != 0 && !self.bridge(idx)
    }

    /// Matches `AgentLayer::is_passable_at` — claimable land + team infra (incl. bridge water).
    pub fn is_passable_cell(&self, idx: usize) -> bool {
        if idx >= self.kernel.tile_count {
            return false;
        }
        if self.kernel.claimable_mask[idx] != 0 {
            return true;
        }
        self.is_infra(idx)
    }

    /// Nearest-unclaimed advance goal: claimable land not owned by this soldier's team.
    pub fn is_advance_goal(&self, idx: usize) -> bool {
        if !self.is_land_cell(idx) {
            return false;
        }
        if self.kernel.claimable_mask[idx] == 0 {
            return false;
        }
        self.kernel.owners[idx] != self.team
    }

    /// Retreat goal: back on friendly-owned or team infra.
    pub fn is_retreat_goal(&self, idx: usize) -> bool {
        if !self.is_passable_cell(idx) {
            return false;
        }
        if self.is_infra(idx) {
            return true;
        }
        if !self.is_land_cell(idx) {
            return false;
        }
        let o = self.kernel.owners[idx];
        o == self.team
            || o == crate::sim::OWNER_NEUTRAL
            || o == crate::sim::OWNER_CONTESTED
    }
}

impl NavGraph for BattleNavView<'_> {
    fn grid_w(&self) -> i32 {
        self.kernel.grid_w
    }

    fn grid_h(&self) -> i32 {
        self.kernel.grid_h
    }

    fn wrap_longitude(&self) -> bool {
        self.kernel.wrap_longitude
    }

    fn passable(&self, idx: usize, _ctx: RouteContext) -> bool {
        self.is_passable_cell(idx)
    }

    fn step_cost(&self, idx: usize, ctx: RouteContext) -> i32 {
        if self.is_infra(idx) {
            ctx.land_step
        } else if self.is_land_cell(idx) {
            ctx.land_step
        } else {
            ctx.water_step
        }
    }
}
