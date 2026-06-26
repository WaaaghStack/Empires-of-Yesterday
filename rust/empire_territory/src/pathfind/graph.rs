//! Navigation graph trait — shared by placement routing and future battle routing.

use crate::pathfind::kernel::RouteContext;
use crate::route::RouteSnapshot;

/// Read-only passability view for the shared search kernel.
pub trait NavGraph {
    fn grid_w(&self) -> i32;
    fn grid_h(&self) -> i32;
    fn wrap_longitude(&self) -> bool;
    fn passable(&self, idx: usize, ctx: RouteContext) -> bool;
    fn step_cost(&self, idx: usize, ctx: RouteContext) -> i32;
}

impl NavGraph for RouteSnapshot {
    fn grid_w(&self) -> i32 {
        self.grid_w
    }

    fn grid_h(&self) -> i32 {
        self.grid_h
    }

    fn wrap_longitude(&self) -> bool {
        self.wrap_longitude
    }

    fn passable(&self, idx: usize, ctx: RouteContext) -> bool {
        if ctx.infra_only {
            self.is_infra_cell(idx)
        } else {
            self.is_route_cell(idx, ctx.allow_water)
        }
    }

    fn step_cost(&self, idx: usize, ctx: RouteContext) -> i32 {
        if self.is_water(idx) {
            ctx.water_step
        } else {
            ctx.land_step
        }
    }
}
