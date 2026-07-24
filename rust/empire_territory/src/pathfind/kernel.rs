//! Single goal-directed search kernel (A* with optional uniform-cost mode).

use crate::pathfind::graph::NavGraph;
use crate::route::{reconstruct_path, wrap_x, CARDINAL};

fn for_each_neighbor<G: NavGraph>(
    graph: &G,
    cur: i32,
    w: i32,
    h: i32,
    mut visit: impl FnMut(i32, i32, i32),
) {
    if graph.uses_graph_neighbors() {
        let cur_ui = cur as usize;
        let n = graph.neighbor_count_of(cur_ui);
        for slot in 0..n {
            if let Some(nui) = graph.neighbor_at(cur_ui, slot) {
                let ni = nui as i32;
                let nx = ni % w;
                let ny = ni / w;
                visit(ni, nx, ny);
            }
        }
        return;
    }
    let cx = cur % w;
    let cy = cur / w;
    for (dx, dy) in CARDINAL {
        let ny = cy + dy;
        if ny < 0 || ny >= h {
            continue;
        }
        let Some(nx) = wrap_x(cx + dx, w, graph.wrap_longitude()) else {
            continue;
        };
        let ni = ny * w + nx;
        visit(ni, nx, ny);
    }
}

/// Optional search tube around a source→goal segment (longitude-aware).
#[derive(Clone, Copy, Debug)]
pub struct CorridorBand {
    pub sx: i32,
    pub sy: i32,
    pub gx: i32,
    pub gy: i32,
    pub half_width: i32,
}

impl CorridorBand {
    /// Manhattan distance from a cell to the wrapped source→goal segment (cardinal grid).
    pub fn contains(&self, px: i32, py: i32, grid_w: i32) -> bool {
        if self.half_width < 0 {
            return true;
        }
        let bx = unwrap_x_toward(self.sx, self.gx, grid_w);
        for shift in [0, -grid_w, grid_w] {
            let dist = manhattan_dist_to_segment(px + shift, py, self.sx, self.sy, bx, self.gy);
            if dist <= self.half_width {
                return true;
            }
        }
        false
    }
}

fn manhattan_dist_to_segment(px: i32, py: i32, ax: i32, ay: i32, bx: i32, by: i32) -> i32 {
    let abx = bx - ax;
    let aby = by - ay;
    if abx == 0 && aby == 0 {
        return (px - ax).abs() + (py - ay).abs();
    }
    let t_num = (px - ax) * abx + (py - ay) * aby;
    let ab_len_sq = abx * abx + aby * aby;
    let (cx, cy) = if t_num <= 0 {
        (ax, ay)
    } else if t_num >= ab_len_sq {
        (bx, by)
    } else {
        (
            ax + (t_num * abx) / ab_len_sq,
            ay + (t_num * aby) / ab_len_sq,
        )
    };
    (px - cx).abs() + (py - cy).abs()
}

fn unwrap_x_toward(sx: i32, tx: i32, w: i32) -> i32 {
    let mut dx = tx - sx;
    if dx > w / 2 {
        dx -= w;
    } else if dx < -w / 2 {
        dx += w;
    }
    sx + dx
}

/// Per-search passability and cost configuration (rule profile input).
#[derive(Clone, Copy, Debug)]
pub struct RouteContext {
    pub allow_water: bool,
    pub infra_only: bool,
    /// When true, use Manhattan heuristic (A*). When false, uniform-cost (Dijkstra/BFS).
    pub use_astar: bool,
    pub land_step: i32,
    pub water_step: i32,
    pub max_expand: usize,
    /// When set, only cells inside the tube around sx,sy→gx,gy are searchable.
    pub corridor: Option<CorridorBand>,
    /// Flight units: passable over any in-bounds cell (water, mountains, enemy land).
    pub flight_mode: bool,
}

impl RouteContext {
    pub const fn astar(allow_water: bool, infra_only: bool) -> Self {
        Self::astar_with_costs(allow_water, infra_only, 1, 2)
    }

    /// Land bridge: water allowed. Mild land premium — geometric + geodesic bias
    /// already discourage continent marches; a large land tax forces bay-hugging.
    pub const fn land_bridge_astar() -> Self {
        Self::astar_with_costs(true, false, 2, 1)
    }

    pub const fn astar_with_costs(
        allow_water: bool,
        infra_only: bool,
        land_step: i32,
        water_step: i32,
    ) -> Self {
        Self {
            allow_water,
            infra_only,
            use_astar: true,
            land_step,
            water_step,
            max_expand: crate::route::MAX_PATHFIND_EXPAND,
            corridor: None,
            flight_mode: false,
        }
    }

    pub const fn with_corridor(mut self, band: CorridorBand) -> Self {
        self.corridor = Some(band);
        self
    }

    pub const fn with_max_expand(mut self, max_expand: usize) -> Self {
        self.max_expand = max_expand;
        self
    }
}

#[derive(Clone, Debug)]
pub struct RoutePath {
    pub path: Vec<i32>,
    pub source_key: i32,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct SearchStats {
    pub expand_count: usize,
}

struct PathSearch {
    parent: Vec<i32>,
    pub(crate) stamp: Vec<u32>,
    source_key: Vec<i32>,
    g_score: Vec<i32>,
    pub(crate) gen: u32,
    queue: VecDeque<i32>,
}

use std::collections::VecDeque;

impl PathSearch {
    fn new(n: usize) -> Self {
        Self {
            parent: vec![-1; n],
            stamp: vec![0; n],
            source_key: vec![-1; n],
            g_score: vec![0; n],
            gen: 0,
            queue: VecDeque::new(),
        }
    }

    pub(crate) fn begin(&mut self) {
        self.gen = self.gen.wrapping_add(1);
        if self.gen == 0 {
            self.gen = 1;
            self.stamp.fill(0);
        }
        self.queue.clear();
    }
}

pub struct SearchKernel {
    search: PathSearch,
    heap: Vec<(i32, i32)>,
}

impl SearchKernel {
    pub fn new(tile_count: usize) -> Self {
        Self {
            search: PathSearch::new(tile_count),
            heap: Vec::new(),
        }
    }

    pub fn ensure_capacity(&mut self, tile_count: usize) {
        if self.search.parent.len() != tile_count {
            *self = Self::new(tile_count);
        }
    }

    pub fn find_path<G: NavGraph>(
        &mut self,
        graph: &G,
        sources: &[i32],
        goal: i32,
        ctx: RouteContext,
    ) -> Option<(RoutePath, SearchStats)> {
        if ctx.use_astar {
            self.astar(graph, sources, goal, ctx)
        } else {
            self.uniform_cost(graph, sources, goal, ctx)
        }
    }

    /// Uniform-cost expansion from `sources` until the first dequeued cell satisfies `is_goal`.
    pub fn find_nearest_goal<G, F>(
        &mut self,
        graph: &G,
        sources: &[i32],
        ctx: RouteContext,
        mut is_goal: F,
    ) -> Option<(RoutePath, SearchStats)>
    where
        G: NavGraph,
        F: FnMut(usize) -> bool,
    {
        self.search.begin();
        let w = graph.grid_w();
        let h = graph.grid_h();
        for &sk in sources {
            if sk < 0 {
                continue;
            }
            let ui = sk as usize;
            if !graph.passable(ui, ctx) || self.search.stamp[ui] == self.search.gen {
                continue;
            }
            let sx = sk % w;
            let sy = sk / w;
            if !Self::in_corridor(graph, ctx, sx, sy, w) {
                continue;
            }
            self.search.stamp[ui] = self.search.gen;
            self.search.parent[ui] = -1;
            self.search.source_key[ui] = sk;
            self.search.queue.push_back(sk);
        }
        if self.search.queue.is_empty() {
            return None;
        }
        let mut head = 0usize;
        let mut expanded = 0usize;
        while head < self.search.queue.len() {
            if expanded >= ctx.max_expand {
                return None;
            }
            let cur = self.search.queue[head];
            head += 1;
            expanded += 1;
            let cur_ui = cur as usize;
            if is_goal(cur_ui) {
                let path = reconstruct_path(&self.search.parent, cur);
                return Some((
                    RoutePath {
                        path,
                        source_key: self.search.source_key[cur_ui],
                    },
                    SearchStats {
                        expand_count: expanded,
                    },
                ));
            }
            for_each_neighbor(graph, cur, w, h, |ni, nx, ny| {
                let nui = ni as usize;
                if !graph.passable(nui, ctx) || self.search.stamp[nui] == self.search.gen {
                    return;
                }
                if !Self::in_corridor(graph, ctx, nx, ny, w) {
                    return;
                }
                self.search.stamp[nui] = self.search.gen;
                self.search.parent[nui] = cur;
                self.search.source_key[nui] = self.search.source_key[cur_ui];
                self.search.queue.push_back(ni);
            });
        }
        None
    }

    /// Shadow-board search: try a thin tube along source→goal, widening until a path appears.
    pub fn find_path_corridor_widening<G: NavGraph>(
        &mut self,
        graph: &G,
        sources: &[i32],
        goal: i32,
        base_ctx: RouteContext,
        half_widths: &[i32],
        per_band_max_expand: usize,
    ) -> Option<(RoutePath, SearchStats)> {
        if graph.uses_graph_neighbors() {
            return self.find_path(
                graph,
                sources,
                goal,
                base_ctx.with_max_expand(per_band_max_expand),
            );
        }
        let w = graph.grid_w();
        let gx = goal % w;
        let gy = goal / w;
        let mut best: Option<(RoutePath, SearchStats)> = None;
        for &sk in sources {
            if sk < 0 {
                continue;
            }
            let sx = sk % w;
            let sy = sk / w;
            for &half_w in half_widths {
                let band = CorridorBand {
                    sx,
                    sy,
                    gx,
                    gy,
                    half_width: half_w,
                };
                let ctx = base_ctx
                    .with_corridor(band)
                    .with_max_expand(per_band_max_expand);
                let Some(result) = self.find_path(graph, &[sk], goal, ctx) else {
                    continue;
                };
                let replace = match &best {
                    None => true,
                    Some((prev, _)) => result.0.path.len() < prev.path.len(),
                };
                if replace {
                    best = Some(result);
                }
                break;
            }
        }
        best
    }

    fn in_corridor<G: NavGraph>(graph: &G, ctx: RouteContext, px: i32, py: i32, grid_w: i32) -> bool {
        if graph.uses_graph_neighbors() {
            return true;
        }
        match ctx.corridor {
            Some(band) => band.contains(px, py, grid_w),
            None => true,
        }
    }

    fn uniform_cost<G: NavGraph>(
        &mut self,
        graph: &G,
        sources: &[i32],
        goal: i32,
        ctx: RouteContext,
    ) -> Option<(RoutePath, SearchStats)> {
        self.search.begin();
        let w = graph.grid_w();
        let h = graph.grid_h();
        for &sk in sources {
            if sk < 0 {
                continue;
            }
            let ui = sk as usize;
            if !graph.passable(ui, ctx) || self.search.stamp[ui] == self.search.gen {
                continue;
            }
            let sx = sk % w;
            let sy = sk / w;
            if !Self::in_corridor(graph, ctx, sx, sy, w) {
                continue;
            }
            self.search.stamp[ui] = self.search.gen;
            self.search.parent[ui] = -1;
            self.search.source_key[ui] = sk;
            self.search.queue.push_back(sk);
        }
        if self.search.queue.is_empty() {
            return None;
        }
        let mut head = 0usize;
        let mut expanded = 0usize;
        while head < self.search.queue.len() {
            if expanded >= ctx.max_expand {
                return None;
            }
            let cur = self.search.queue[head];
            head += 1;
            expanded += 1;
            if cur == goal {
                let path = reconstruct_path(&self.search.parent, goal);
                let src = self.search.source_key[cur as usize];
                return Some((
                    RoutePath {
                        path,
                        source_key: src,
                    },
                    SearchStats {
                        expand_count: expanded,
                    },
                ));
            }
            for_each_neighbor(graph, cur, w, h, |ni, nx, ny| {
                let nui = ni as usize;
                if !graph.passable(nui, ctx) || self.search.stamp[nui] == self.search.gen {
                    return;
                }
                if !Self::in_corridor(graph, ctx, nx, ny, w) {
                    return;
                }
                self.search.stamp[nui] = self.search.gen;
                self.search.parent[nui] = cur;
                self.search.source_key[nui] = self.search.source_key[cur as usize];
                self.search.queue.push_back(ni);
            });
        }
        None
    }

    fn astar<G: NavGraph>(
        &mut self,
        graph: &G,
        sources: &[i32],
        goal: i32,
        ctx: RouteContext,
    ) -> Option<(RoutePath, SearchStats)> {
        self.search.begin();
        let w = graph.grid_w();
        let h = graph.grid_h();
        let gen = self.search.gen;
        let goal_ui = goal as usize;
        self.heap.clear();
        for &sk in sources {
            if sk < 0 {
                continue;
            }
            let ui = sk as usize;
            if !graph.passable(ui, ctx) {
                continue;
            }
            let sx = sk % w;
            let sy = sk / w;
            if !Self::in_corridor(graph, ctx, sx, sy, w) {
                continue;
            }
            self.search.g_score[ui] = 0;
            self.search.stamp[ui] = gen;
            self.search.parent[ui] = -1;
            self.search.source_key[ui] = sk;
            let f = graph.heuristic(sk, goal);
            heap_push(&mut self.heap, sk, f);
        }
        if self.heap.is_empty() {
            return None;
        }
        let mut expanded = 0usize;
        while let Some((cur, f_popped)) = heap_pop(&mut self.heap) {
            if expanded >= ctx.max_expand {
                return None;
            }
            let cur_ui = cur as usize;
            if self.search.stamp[cur_ui] != gen {
                continue;
            }
            let cur_g = self.search.g_score[cur_ui];
            // Skip stale heap entries (a better g was found after this push).
            let f_now = cur_g.saturating_add(graph.heuristic(cur, goal));
            if f_popped > f_now {
                continue;
            }
            expanded += 1;
            if cur == goal {
                let path = reconstruct_path(&self.search.parent, goal);
                return Some((
                    RoutePath {
                        path,
                        source_key: self.search.source_key[cur_ui],
                    },
                    SearchStats {
                        expand_count: expanded,
                    },
                ));
            }
            for_each_neighbor(graph, cur, w, h, |ni, nx, ny| {
                let nui = ni as usize;
                if !graph.passable(nui, ctx) {
                    return;
                }
                if !Self::in_corridor(graph, ctx, nx, ny, w) {
                    return;
                }
                let src_key = self.search.source_key[cur_ui];
                let step = graph
                    .step_cost(cur_ui, nui, ctx)
                    .saturating_add(graph.geodesic_deviation(src_key, goal, ni));
                let tentative = cur_g.saturating_add(step);
                let unseen = self.search.stamp[nui] != gen;
                let better = unseen || tentative < self.search.g_score[nui];
                let tie_better = if !unseen && tentative == self.search.g_score[nui] {
                    let old_parent = self.search.parent[nui];
                    let old_align = if old_parent < 0 {
                        i32::MIN
                    } else {
                        graph.edge_alignment(old_parent as usize, nui, goal_ui)
                    };
                    graph.edge_alignment(cur_ui, nui, goal_ui) > old_align
                } else {
                    false
                };
                if better || tie_better {
                    self.search.stamp[nui] = gen;
                    self.search.g_score[nui] = tentative;
                    self.search.parent[nui] = cur;
                    self.search.source_key[nui] = self.search.source_key[cur_ui];
                    heap_push(
                        &mut self.heap,
                        ni,
                        tentative.saturating_add(graph.heuristic(ni, goal)),
                    );
                }
            });
        }
        None
    }
}

fn heap_push(heap: &mut Vec<(i32, i32)>, key: i32, f: i32) {
    heap.push((key, f));
    let mut i = heap.len() - 1;
    while i > 0 {
        let p = (i - 1) / 2;
        if heap[p].1 <= heap[i].1 {
            break;
        }
        heap.swap(p, i);
        i = p;
    }
}

fn heap_pop(heap: &mut Vec<(i32, i32)>) -> Option<(i32, i32)> {
    if heap.is_empty() {
        return None;
    }
    let out = heap[0];
    let last = heap.pop().unwrap();
    if !heap.is_empty() {
        heap[0] = last;
        let mut i = 0usize;
        loop {
            let l = i * 2 + 1;
            let r = l + 1;
            let mut smallest = i;
            if l < heap.len() && heap[l].1 < heap[smallest].1 {
                smallest = l;
            }
            if r < heap.len() && heap[r].1 < heap[smallest].1 {
                smallest = r;
            }
            if smallest == i {
                break;
            }
            heap.swap(i, smallest);
            i = smallest;
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::route::RouteSnapshot;

    fn tiny_snapshot() -> RouteSnapshot {
        let w = 5i32;
        let h = 3i32;
        let n = (w * h) as usize;
        let mut land_mask = vec![0u8; n];
        let mut land_comp = vec![-1i32; n];
        for gy in 0..h {
            for gx in 0..w {
                let idx = (gy * w + gx) as usize;
                if gy != 1 {
                    land_mask[idx] = 1;
                    land_comp[idx] = if gx < 2 { 0 } else { 1 };
                }
            }
        }
        RouteSnapshot {
            grid_w: w,
            grid_h: h,
            wrap_longitude: false,
            land_mask,
            bridge_mask: vec![0u8; n],
            land_comp,
            graph_neighbors: vec![],
            graph_neighbor_count: vec![],
            cell_positions: vec![],
        }
    }

    #[test]
    fn corridor_widening_finds_bridge_with_small_expand() {
        let snap = tiny_snapshot();
        let mut kernel = SearchKernel::new(snap.tile_count());
        let ctx = RouteContext::land_bridge_astar();
        let (path, stats) = kernel
            .find_path_corridor_widening(
                &snap,
                &[0],
                4,
                ctx,
                &[2, 4, 8, 16],
                2048,
            )
            .expect("corridor path");
        assert_eq!(path.path.last().copied(), Some(4));
        assert!(
            stats.expand_count < 500,
            "expand_count={}",
            stats.expand_count
        );
    }

    #[test]
    fn geometric_sphere_cost_prefers_shorter_chords() {
        // Diamond: 0→1→3 is short; 0→2→3 is long (same hop count).
        let mut neighbors = vec![[-1i32; 6]; 4];
        let mut neighbor_count = vec![0u8; 4];
        let edges = [(0, 1), (1, 0), (0, 2), (2, 0), (1, 3), (3, 1), (2, 3), (3, 2)];
        for (a, b) in edges {
            let slot = neighbor_count[a] as usize;
            neighbors[a][slot] = b as i32;
            neighbor_count[a] += 1;
        }
        let positions = vec![
            [0.0, 0.0, 1.0],
            [0.05, 0.0, 0.9987], // near 0
            [0.8, 0.0, 0.6],     // far from 0 and 3
            [0.1, 0.0, 0.995],   // near 1
        ];
        let snap = RouteSnapshot {
            grid_w: 4,
            grid_h: 1,
            wrap_longitude: false,
            land_mask: vec![1u8; 4],
            bridge_mask: vec![0u8; 4],
            land_comp: vec![0; 4],
            graph_neighbors: neighbors,
            graph_neighbor_count: neighbor_count,
            cell_positions: positions,
        };
        let mut kernel = SearchKernel::new(4);
        let ctx = RouteContext::astar(false, false).with_max_expand(64);
        let (path, _) = kernel
            .find_path(&snap, &[0], 3, ctx)
            .expect("geometric path");
        assert_eq!(path.path, vec![0, 1, 3], "path={:?}", path.path);
    }

    #[test]
    fn geodesic_penalty_avoids_bay_detour() {
        // 0 ---- 1 ---- 3  (on great-circle band)
        //  \           /
        //   ---- 2 ----     (2 is far off-plane → expensive)
        let mut neighbors = vec![[-1i32; 6]; 4];
        let mut neighbor_count = vec![0u8; 4];
        let edges = [
            (0, 1),
            (1, 0),
            (1, 3),
            (3, 1),
            (0, 2),
            (2, 0),
            (2, 3),
            (3, 2),
        ];
        for (a, b) in edges {
            let slot = neighbor_count[a] as usize;
            neighbors[a][slot] = b as i32;
            neighbor_count[a] += 1;
        }
        let positions = vec![
            [0.0, 0.0, 1.0],
            [0.1, 0.0, 0.995],
            [0.05, 0.7, 0.7], // off the equator plane of 0→3
            [0.2, 0.0, 0.98],
        ];
        let snap = RouteSnapshot {
            grid_w: 4,
            grid_h: 1,
            wrap_longitude: false,
            land_mask: vec![0u8; 4], // all water
            bridge_mask: vec![0u8; 4],
            land_comp: vec![-1; 4],
            graph_neighbors: neighbors,
            graph_neighbor_count: neighbor_count,
            cell_positions: positions,
        };
        let mut kernel = SearchKernel::new(4);
        let ctx = RouteContext::land_bridge_astar().with_max_expand(64);
        let (path, _) = kernel
            .find_path(&snap, &[0], 3, ctx)
            .expect("bridge path");
        assert_eq!(path.path, vec![0, 1, 3], "path={:?}", path.path);
    }
}
