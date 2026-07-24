//! Navigation graph trait — shared by placement routing and future battle routing.

use crate::pathfind::kernel::RouteContext;
use crate::route::RouteSnapshot;

/// Scale for quantizing unit-sphere chords into integer A* costs.
pub const CHORD_COST_SCALE: f32 = 10_000.0;
/// Extra cost for cells off the source→goal great circle (keeps bridges from bay-hugging).
pub const GEO_DEV_COST_SCALE: f32 = 4_000.0;

/// Read-only passability view for the shared search kernel.
pub trait NavGraph {
    fn grid_w(&self) -> i32;
    fn grid_h(&self) -> i32;
    fn wrap_longitude(&self) -> bool;
    fn passable(&self, idx: usize, ctx: RouteContext) -> bool;
    /// Cost to traverse the edge `from → to` (terrain weight applies to `to`).
    fn step_cost(&self, from: usize, to: usize, ctx: RouteContext) -> i32;
    /// Admissible remaining-cost estimate (0 when unavailable).
    fn heuristic(&self, cell: i32, goal: i32) -> i32 {
        let _ = (cell, goal);
        0
    }
    /// Higher = better alignment of `from→to` with `from→goal` (tie-break only).
    fn edge_alignment(&self, from: usize, to: usize, goal: usize) -> i32 {
        let _ = (from, to, goal);
        0
    }
    /// Soft penalty for leaving the source→goal great circle (0 when unavailable).
    fn geodesic_deviation(&self, source: i32, goal: i32, cell: i32) -> i32 {
        let _ = (source, goal, cell);
        0
    }

    fn neighbor_at(&self, _idx: usize, _slot: usize) -> Option<usize> {
        None
    }

    fn neighbor_count_of(&self, _idx: usize) -> usize {
        0
    }

    fn uses_graph_neighbors(&self) -> bool {
        false
    }
}

pub fn chord_quantized(a: [f32; 3], b: [f32; 3]) -> i32 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    let dz = a[2] - b[2];
    let d = (dx * dx + dy * dy + dz * dz).sqrt();
    ((d * CHORD_COST_SCALE) as i32).max(1)
}

pub fn dir_alignment(from: [f32; 3], to: [f32; 3], goal: [f32; 3]) -> i32 {
    let ex = to[0] - from[0];
    let ey = to[1] - from[1];
    let ez = to[2] - from[2];
    let gx = goal[0] - from[0];
    let gy = goal[1] - from[1];
    let gz = goal[2] - from[2];
    let el = (ex * ex + ey * ey + ez * ez).sqrt();
    let gl = (gx * gx + gy * gy + gz * gz).sqrt();
    if el < 1e-8 || gl < 1e-8 {
        return 0;
    }
    let dot = (ex * gx + ey * gy + ez * gz) / (el * gl);
    (dot * 1000.0) as i32
}

/// |sin| of angle from cell to the source–goal plane (= distance from great circle).
pub fn geodesic_plane_deviation(source: [f32; 3], goal: [f32; 3], cell: [f32; 3]) -> f32 {
    let nx = source[1] * goal[2] - source[2] * goal[1];
    let ny = source[2] * goal[0] - source[0] * goal[2];
    let nz = source[0] * goal[1] - source[1] * goal[0];
    let nl = (nx * nx + ny * ny + nz * nz).sqrt();
    if nl < 1e-8 {
        return 0.0;
    }
    ((cell[0] * nx + cell[1] * ny + cell[2] * nz) / nl).abs()
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

    fn step_cost(&self, from: usize, to: usize, ctx: RouteContext) -> i32 {
        let terrain = if self.is_water(to) {
            ctx.water_step
        } else {
            ctx.land_step
        }
        .max(1);
        if self.uses_graph_neighbors() && self.has_cell_positions() {
            let chord = chord_quantized(self.cell_pos(from), self.cell_pos(to));
            return chord.saturating_mul(terrain);
        }
        terrain
    }

    fn heuristic(&self, cell: i32, goal: i32) -> i32 {
        if cell < 0 || goal < 0 {
            return 0;
        }
        let c = cell as usize;
        let g = goal as usize;
        if self.uses_graph_neighbors() && self.has_cell_positions() {
            // Euclidean chord ≤ any path of chords (triangle inequality) → admissible.
            return chord_quantized(self.cell_pos(c), self.cell_pos(g));
        }
        let w = self.grid_w;
        if w <= 0 {
            return 0;
        }
        let gx = cell % w;
        let gy = cell / w;
        let tx = goal % w;
        let ty = goal / w;
        let mut dx = (tx - gx).abs();
        if self.wrap_longitude {
            dx = dx.min(w - dx);
        }
        let dy = (ty - gy).abs();
        dx + dy
    }

    fn edge_alignment(&self, from: usize, to: usize, goal: usize) -> i32 {
        if !self.has_cell_positions() {
            return 0;
        }
        dir_alignment(self.cell_pos(from), self.cell_pos(to), self.cell_pos(goal))
    }

    fn geodesic_deviation(&self, source: i32, goal: i32, cell: i32) -> i32 {
        if !self.has_cell_positions() || source < 0 || goal < 0 || cell < 0 {
            return 0;
        }
        let s = source as usize;
        let g = goal as usize;
        let c = cell as usize;
        if s >= self.cell_positions.len()
            || g >= self.cell_positions.len()
            || c >= self.cell_positions.len()
        {
            return 0;
        }
        let dev = geodesic_plane_deviation(self.cell_pos(s), self.cell_pos(g), self.cell_pos(c));
        (dev * GEO_DEV_COST_SCALE) as i32
    }

    fn uses_graph_neighbors(&self) -> bool {
        self.uses_graph_neighbors()
    }

    fn neighbor_at(&self, idx: usize, slot: usize) -> Option<usize> {
        if !self.uses_graph_neighbors() || idx >= self.graph_neighbors.len() || slot >= 6 {
            return None;
        }
        let ni = self.graph_neighbors[idx][slot];
        if ni >= 0 {
            Some(ni as usize)
        } else {
            None
        }
    }

    fn neighbor_count_of(&self, idx: usize) -> usize {
        if !self.uses_graph_neighbors() || idx >= self.graph_neighbor_count.len() {
            return 0;
        }
        self.graph_neighbor_count[idx] as usize
    }
}
