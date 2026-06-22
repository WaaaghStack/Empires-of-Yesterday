//! Outpost / land-bridge route planning with portal graph + background worker.

use std::collections::VecDeque;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

pub const ROUTE_KIND_OUTPOST: i32 = 0;
pub const ROUTE_KIND_CORRIDOR: i32 = 1;
pub const MAX_PATHFIND_EXPAND: usize = 12_000;

const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

#[derive(Clone)]
pub struct RouteSnapshot {
    pub grid_w: i32,
    pub grid_h: i32,
    pub wrap_longitude: bool,
    pub land_mask: Vec<u8>,
    pub bridge_mask: Vec<u8>,
    pub land_comp: Vec<i32>,
}

impl RouteSnapshot {
    pub fn tile_count(&self) -> usize {
        (self.grid_w * self.grid_h) as usize
    }

    pub fn cell_index(&self, gx: i32, gy: i32) -> i32 {
        if gy < 0 || gy >= self.grid_h {
            return -1;
        }
        let Some(nx) = wrap_x(gx, self.grid_w, self.wrap_longitude) else {
            return -1;
        };
        gy * self.grid_w + nx
    }

    fn is_land(&self, idx: usize) -> bool {
        idx < self.land_mask.len() && self.land_mask[idx] != 0
    }

    fn is_water(&self, idx: usize) -> bool {
        idx < self.land_mask.len() && self.land_mask[idx] == 0
    }

    fn is_route_cell(&self, idx: usize, allow_water: bool) -> bool {
        if idx >= self.land_mask.len() {
            return false;
        }
        if self.land_mask[idx] != 0 {
            return true;
        }
        allow_water
    }

    fn is_infra_cell(&self, idx: usize) -> bool {
        if idx >= self.land_mask.len() {
            return false;
        }
        if idx < self.bridge_mask.len() && self.bridge_mask[idx] != 0 {
            return true;
        }
        self.land_mask[idx] != 0
    }

    fn land_comp_at(&self, idx: usize) -> i32 {
        if idx < self.land_comp.len() {
            self.land_comp[idx]
        } else {
            -1
        }
    }
}

#[derive(Clone, Default)]
pub struct PortalGraph {
    pub source_keys: Vec<i32>,
    pub source_land_comp: Vec<i32>,
    pub bridge_landings: Vec<i32>,
    pub bridge_landing_comp: Vec<i32>,
    /// source_slot -> land_comp -> reachable via infra (sparse: comp ids per source)
    pub infra_reach: Vec<Vec<i32>>,
}

impl PortalGraph {
    pub fn rebuild(snapshot: &RouteSnapshot, sources: &[i32]) -> Self {
        let mut out = PortalGraph::default();
        let w = snapshot.grid_w;
        for &sk in sources {
            if sk < 0 {
                continue;
            }
            let ui = sk as usize;
            if ui >= snapshot.tile_count() || !snapshot.is_land(ui) {
                continue;
            }
            out.source_keys.push(sk);
            out.source_land_comp.push(snapshot.land_comp_at(ui));
            out.infra_reach.push(infra_reachable_comps(snapshot, sk, 2000));
        }
        // bridge landings filled by GDScript via add_bridge_landings
        let _ = w;
        out
    }

    pub fn set_bridge_landings(&mut self, snapshot: &RouteSnapshot, landing_keys: &[i32]) {
        self.bridge_landings.clear();
        self.bridge_landing_comp.clear();
        for &lk in landing_keys {
            if lk < 0 {
                continue;
            }
            let ui = lk as usize;
            if ui >= snapshot.tile_count() {
                continue;
            }
            self.bridge_landings.push(lk);
            self.bridge_landing_comp.push(snapshot.land_comp_at(ui));
        }
    }
}

fn infra_reachable_comps(snapshot: &RouteSnapshot, start_key: i32, max_expand: usize) -> Vec<i32> {
    let mut seen_comps: Vec<i32> = Vec::new();
    let mut search = PathSearch::new(snapshot.tile_count());
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    search.begin();
    let start_ui = start_key as usize;
    if !snapshot.is_infra_cell(start_ui) {
        return seen_comps;
    }
    search.stamp[start_ui] = search.gen;
    search.queue.push_back(start_key);
    let mut expanded = 0usize;
    while let Some(cur) = search.queue.pop_front() {
        if expanded >= max_expand {
            break;
        }
        expanded += 1;
        let cur_ui = cur as usize;
        if snapshot.is_land(cur_ui) {
            let comp = snapshot.land_comp_at(cur_ui);
            if comp >= 0 && !seen_comps.contains(&comp) {
                seen_comps.push(comp);
            }
        }
        let cx = cur % w;
        let cy = cur / w;
        for (dx, dy) in CARDINAL {
            let ny = cy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = wrap_x(cx + dx, w, snapshot.wrap_longitude) else {
                continue;
            };
            let ni = ny * w + nx;
            let nui = ni as usize;
            if !snapshot.is_infra_cell(nui) || search.stamp[nui] == search.gen {
                continue;
            }
            search.stamp[nui] = search.gen;
            search.queue.push_back(ni);
        }
    }
    seen_comps
}

pub struct RouteResult {
    pub path: Vec<i32>,
    pub source_key: i32,
}

struct PathSearch {
    parent: Vec<i32>,
    stamp: Vec<u32>,
    source_key: Vec<i32>,
    g_score: Vec<i32>,
    gen: u32,
    queue: VecDeque<i32>,
}

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

    fn begin(&mut self) {
        self.gen = self.gen.wrapping_add(1);
        if self.gen == 0 {
            self.gen = 1;
            self.stamp.fill(0);
        }
        self.queue.clear();
    }
}

pub fn find_route(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    kind: i32,
    allow_astar: bool,
) -> Option<RouteResult> {
    if kind == ROUTE_KIND_CORRIDOR {
        return find_corridor_route(snapshot, portal, target_gx, target_gy);
    }
    find_outpost_route(snapshot, portal, target_gx, target_gy, allow_astar)
}

fn find_outpost_route(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    allow_astar: bool,
) -> Option<RouteResult> {
    let goal = snapshot.cell_index(target_gx, target_gy);
    if goal < 0 {
        return None;
    }
    let goal_ui = goal as usize;
    if !snapshot.is_land(goal_ui) {
        return None;
    }
    let goal_comp = snapshot.land_comp_at(goal_ui);
    let sources = &portal.source_keys;

    // Portal strategy: pick which searches to run.
    let same_mass = portal
        .source_land_comp
        .iter()
        .any(|&c| c >= 0 && c == goal_comp);
    if same_mass {
        if let Some(r) = bfs_land(snapshot, sources, goal, false) {
            return Some(r);
        }
    }

    if let Some(landing) = nearest_bridge_landing(portal, goal_comp) {
        if let Some(r) = bfs_land(snapshot, &[landing], goal, false) {
            return Some(r);
        }
    }

    let infra_needed = portal.infra_reach.iter().any(|comps| comps.contains(&goal_comp));
    if infra_needed || !same_mass {
        if let Some(r) = bfs_infra(snapshot, sources, goal) {
            return Some(r);
        }
    }

    if let Some(r) = greedy_bridge(snapshot, sources, goal) {
        return Some(r);
    }

    if allow_astar {
        return astar_route(snapshot, sources, goal);
    }
    None
}

fn nearest_bridge_landing(portal: &PortalGraph, goal_comp: i32) -> Option<i32> {
    if goal_comp < 0 {
        return None;
    }
    for (i, &comp) in portal.bridge_landing_comp.iter().enumerate() {
        if comp == goal_comp {
            return Some(portal.bridge_landings[i]);
        }
    }
    None
}

fn find_corridor_route(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    landing_gx: i32,
    landing_gy: i32,
) -> Option<RouteResult> {
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    let landing_key = snapshot.cell_index(landing_gx, landing_gy);
    if landing_key < 0 {
        return None;
    }
    let landing_ui = landing_key as usize;
    if !snapshot.is_land(landing_ui) || !is_coastal(snapshot, landing_gx, landing_gy) {
        return None;
    }
    let landing_water = water_neighbor_keys(snapshot, landing_gx, landing_gy);
    if landing_water.is_empty() {
        return None;
    }

    let n = snapshot.tile_count();
    let mut water_parent = vec![-1i32; n];
    let mut water_stamp = vec![0u32; n];
    let mut water_g_score = vec![0i32; n];
    let water_gen: u32 = 1;
    let mut water_queue: VecDeque<i32> = VecDeque::new();
    for &gk in &landing_water {
        let ui = gk as usize;
        if ui >= n || water_stamp[ui] == water_gen {
            continue;
        }
        water_stamp[ui] = water_gen;
        water_parent[ui] = gk;
        water_g_score[ui] = 0;
        water_queue.push_back(gk);
    }
    if water_queue.is_empty() {
        return None;
    }
    let mut head = 0usize;
    while head < water_queue.len() {
        let cur = water_queue[head];
        head += 1;
        let cur_ui = cur as usize;
        let cx = cur % w;
        let cy = cur / w;
        for (dx, dy) in CARDINAL {
            let ny = cy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = wrap_x(cx + dx, w, snapshot.wrap_longitude) else {
                continue;
            };
            let ni = ny * w + nx;
            let nui = ni as usize;
            if !snapshot.is_water(nui) || water_stamp[nui] == water_gen {
                continue;
            }
            water_stamp[nui] = water_gen;
            water_parent[nui] = cur;
            water_g_score[nui] = water_g_score[cur_ui] + 1;
            water_queue.push_back(ni);
        }
    }

    let mut search = PathSearch::new(n);
    search.begin();
    let land_gen = search.gen;
    search.queue.clear();
    for &sk in &portal.source_keys {
        if sk < 0 {
            continue;
        }
        let ui = sk as usize;
        if !snapshot.is_land(ui) || search.stamp[ui] == land_gen {
            continue;
        }
        search.stamp[ui] = land_gen;
        search.parent[ui] = -1;
        search.g_score[ui] = 0;
        search.source_key[ui] = sk;
        search.queue.push_back(sk);
    }
    if search.queue.is_empty() {
        return None;
    }

    let mut best_coast: i32 = -1;
    let mut best_dep: i32 = -1;
    let mut best_source: i32 = -1;
    let mut best_len: i32 = i32::MAX;
    head = 0;
    while head < search.queue.len() {
        let cur_key = search.queue[head];
        head += 1;
        let cur_ui = cur_key as usize;
        let cur_dist = search.g_score[cur_ui];
        let cx = cur_key % w;
        let cy = cur_key / w;
        if cur_dist + 3 < best_len && cell_has_water_neighbor(snapshot, cx, cy) {
            let dep_water = water_neighbor_keys(snapshot, cx, cy);
            for &dep_key in &dep_water {
                let dep_ui = dep_key as usize;
                if water_stamp[dep_ui] != water_gen {
                    continue;
                }
                let total = cur_dist + water_g_score[dep_ui] + 3;
                if total < best_len {
                    best_len = total;
                    best_coast = cur_key;
                    best_dep = dep_key;
                    best_source = search.source_key[cur_ui];
                }
            }
        }
        for (dx, dy) in CARDINAL {
            let ny = cy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = wrap_x(cx + dx, w, snapshot.wrap_longitude) else {
                continue;
            };
            let ni = ny * w + nx;
            let nui = ni as usize;
            if !snapshot.is_land(nui) || search.stamp[nui] == land_gen {
                continue;
            }
            search.stamp[nui] = land_gen;
            search.parent[nui] = cur_key;
            search.g_score[nui] = cur_dist + 1;
            search.source_key[nui] = search.source_key[cur_ui];
            search.queue.push_back(ni);
        }
    }

    if best_coast < 0 || best_dep < 0 {
        return None;
    }

    let land_path = reconstruct_path(&search.parent, best_coast);
    let mut water_path = reconstruct_path(&water_parent, best_dep);
    water_path.reverse();
    let mut full = land_path;
    for k in water_path {
        if full.last().copied() != Some(k) {
            full.push(k);
        }
    }
    if full.last().copied() != Some(landing_key) {
        full.push(landing_key);
    }
    if full.len() < 2 {
        return None;
    }
    Some(RouteResult {
        path: full,
        source_key: best_source,
    })
}

fn bfs_land(
    snapshot: &RouteSnapshot,
    sources: &[i32],
    goal: i32,
    allow_water: bool,
) -> Option<RouteResult> {
    bfs_route(snapshot, sources, goal, allow_water, false)
}

fn bfs_infra(snapshot: &RouteSnapshot, sources: &[i32], goal: i32) -> Option<RouteResult> {
    bfs_route(snapshot, sources, goal, false, true)
}

fn bfs_route(
    snapshot: &RouteSnapshot,
    sources: &[i32],
    goal: i32,
    allow_water: bool,
    infra_only: bool,
) -> Option<RouteResult> {
    let mut search = PathSearch::new(snapshot.tile_count());
    search.begin();
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    for &sk in sources {
        if sk < 0 {
            continue;
        }
        let ui = sk as usize;
        let pass = if infra_only {
            snapshot.is_infra_cell(ui)
        } else {
            snapshot.is_route_cell(ui, allow_water)
        };
        if !pass || search.stamp[ui] == search.gen {
            continue;
        }
        search.stamp[ui] = search.gen;
        search.parent[ui] = -1;
        search.source_key[ui] = sk;
        search.queue.push_back(sk);
    }
    if search.queue.is_empty() {
        return None;
    }
    let mut head = 0usize;
    let mut expanded = 0usize;
    while head < search.queue.len() {
        if expanded >= MAX_PATHFIND_EXPAND {
            return None;
        }
        let cur = search.queue[head];
        head += 1;
        expanded += 1;
        if cur == goal {
            let path = reconstruct_path(&search.parent, goal);
            let src = search.source_key[cur as usize];
            return Some(RouteResult {
                path,
                source_key: src,
            });
        }
        let cx = cur % w;
        let cy = cur / w;
        for (dx, dy) in CARDINAL {
            let ny = cy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = wrap_x(cx + dx, w, snapshot.wrap_longitude) else {
                continue;
            };
            let ni = ny * w + nx;
            let nui = ni as usize;
            let pass = if infra_only {
                snapshot.is_infra_cell(nui)
            } else {
                snapshot.is_route_cell(nui, allow_water)
            };
            if !pass || search.stamp[nui] == search.gen {
                continue;
            }
            search.stamp[nui] = search.gen;
            search.parent[nui] = cur;
            search.source_key[nui] = search.source_key[cur as usize];
            search.queue.push_back(ni);
        }
    }
    None
}

fn greedy_bridge(snapshot: &RouteSnapshot, sources: &[i32], goal: i32) -> Option<RouteResult> {
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    let mut start_key = -1i32;
    let mut start_h = i32::MAX;
    for &sk in sources {
        if sk < 0 {
            continue;
        }
        let ui = sk as usize;
        if !snapshot.is_land(ui) {
            continue;
        }
        let hh = heuristic(sk, goal, w);
        if hh < start_h {
            start_h = hh;
            start_key = sk;
        }
    }
    if start_key < 0 {
        return None;
    }
    let mut search = PathSearch::new(snapshot.tile_count());
    search.begin();
    let mut path = vec![start_key];
    search.stamp[start_key as usize] = search.gen;
    let mut cur = start_key;
    let max_steps = w + h + 128;
    for _ in 0..max_steps {
        if cur == goal {
            return Some(RouteResult {
                path,
                source_key: start_key,
            });
        }
        let cx = cur % w;
        let cy = cur / w;
        let cur_h = heuristic(cur, goal, w);
        let mut best_key = -1i32;
        let mut best_h = i32::MAX;
        let mut equal_key = -1i32;
        let mut uphill_key = -1i32;
        for (dx, dy) in CARDINAL {
            let ny = cy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = wrap_x(cx + dx, w, snapshot.wrap_longitude) else {
                continue;
            };
            let ni = ny * w + nx;
            let nui = ni as usize;
            if !snapshot.is_route_cell(nui, true) || search.stamp[nui] == search.gen {
                continue;
            }
            let nh = heuristic(ni, goal, w);
            if nh < best_h {
                best_h = nh;
                best_key = ni;
            } else if nh == cur_h && equal_key < 0 {
                equal_key = ni;
            } else if nh == cur_h + 1 && uphill_key < 0 {
                uphill_key = ni;
            }
        }
        if best_key < 0 {
            best_key = equal_key;
        }
        if best_key < 0 {
            best_key = uphill_key;
        }
        if best_key < 0 {
            return None;
        }
        search.stamp[best_key as usize] = search.gen;
        cur = best_key;
        path.push(cur);
    }
    None
}

fn astar_route(snapshot: &RouteSnapshot, sources: &[i32], goal: i32) -> Option<RouteResult> {
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    let mut search = PathSearch::new(snapshot.tile_count());
    search.begin();
    let gen = search.gen;
    let mut heap: Vec<(i32, i32)> = Vec::new();
    for &sk in sources {
        if sk < 0 {
            continue;
        }
        let ui = sk as usize;
        if !snapshot.is_route_cell(ui, true) {
            continue;
        }
        search.g_score[ui] = 0;
        search.stamp[ui] = gen;
        search.parent[ui] = -1;
        search.source_key[ui] = sk;
        let f = heuristic(sk, goal, w);
        heap_push(&mut heap, sk, f);
    }
    if heap.is_empty() {
        return None;
    }
    let mut expanded = 0usize;
    while let Some((cur, _f)) = heap_pop(&mut heap) {
        if expanded >= MAX_PATHFIND_EXPAND {
            return None;
        }
        let cur_ui = cur as usize;
        if search.stamp[cur_ui] != gen {
            continue;
        }
        expanded += 1;
        if cur == goal {
            let path = reconstruct_path(&search.parent, goal);
            return Some(RouteResult {
                path,
                source_key: search.source_key[cur_ui],
            });
        }
        let cx = cur % w;
        let cy = cur / w;
        let cur_g = search.g_score[cur_ui];
        for (dx, dy) in CARDINAL {
            let ny = cy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = wrap_x(cx + dx, w, snapshot.wrap_longitude) else {
                continue;
            };
            let ni = ny * w + nx;
            let nui = ni as usize;
            if !snapshot.is_route_cell(nui, true) {
                continue;
            }
            let step = if snapshot.is_water(nui) { 2 } else { 1 };
            let tentative = cur_g + step;
            if search.stamp[nui] != gen || tentative < search.g_score[nui] {
                search.stamp[nui] = gen;
                search.g_score[nui] = tentative;
                search.parent[nui] = cur;
                search.source_key[nui] = search.source_key[cur_ui];
                heap_push(&mut heap, ni, tentative + heuristic(ni, goal, w));
            }
        }
    }
    None
}

fn reconstruct_path(parent: &[i32], goal: i32) -> Vec<i32> {
    let mut out = Vec::new();
    let mut cur = goal;
    while cur >= 0 {
        out.push(cur);
        let ui = cur as usize;
        if ui >= parent.len() {
            break;
        }
        cur = parent[ui];
    }
    out.reverse();
    out
}

fn heuristic(cell: i32, goal: i32, w: i32) -> i32 {
    let gx = cell % w;
    let gy = cell / w;
    let tx = goal % w;
    let ty = goal / w;
    let mut dx = (tx - gx).abs();
    dx = dx.min(w - dx);
    let dy = (ty - gy).abs();
    dx + dy
}

fn wrap_x(gx: i32, w: i32, wrap: bool) -> Option<i32> {
    if wrap {
        let mut nx = gx % w;
        if nx < 0 {
            nx += w;
        }
        Some(nx)
    } else if gx >= 0 && gx < w {
        Some(gx)
    } else {
        None
    }
}

fn is_coastal(snapshot: &RouteSnapshot, gx: i32, gy: i32) -> bool {
    let idx = snapshot.cell_index(gx, gy);
    if idx < 0 {
        return false;
    }
    if !snapshot.is_land(idx as usize) {
        return false;
    }
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    for (dx, dy) in CARDINAL {
        let ny = gy + dy;
        if ny < 0 || ny >= h {
            return true;
        }
        let Some(nx) = wrap_x(gx + dx, w, snapshot.wrap_longitude) else {
            return true;
        };
        let ni = snapshot.cell_index(nx, ny);
        if ni < 0 || snapshot.is_water(ni as usize) {
            return true;
        }
    }
    false
}

fn cell_has_water_neighbor(snapshot: &RouteSnapshot, gx: i32, gy: i32) -> bool {
    water_neighbor_keys(snapshot, gx, gy).len() > 0
}

fn water_neighbor_keys(snapshot: &RouteSnapshot, gx: i32, gy: i32) -> Vec<i32> {
    let mut out = Vec::new();
    let w = snapshot.grid_w;
    let h = snapshot.grid_h;
    for (dx, dy) in CARDINAL {
        let ny = gy + dy;
        if ny < 0 || ny >= h {
            continue;
        }
        let Some(nx) = wrap_x(gx + dx, w, snapshot.wrap_longitude) else {
            continue;
        };
        let ni = snapshot.cell_index(nx, ny);
        if ni >= 0 && snapshot.is_water(ni as usize) {
            out.push(ni);
        }
    }
    out
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

// --- Async worker ---

struct RouteJob {
    request_id: i32,
    target_gx: i32,
    target_gy: i32,
    kind: i32,
    allow_astar: bool,
    snapshot: Arc<RouteSnapshot>,
    portal: Arc<PortalGraph>,
}

pub struct RouteJobResult {
    pub request_id: i32,
    pub path: Vec<i32>,
    pub source_key: i32,
    pub found: bool,
}

pub struct RouteWorker {
    pending: Arc<Mutex<Option<RouteJob>>>,
    notify_tx: Sender<()>,
    result_rx: Receiver<RouteJobResult>,
    _handle: JoinHandle<()>,
}

impl RouteWorker {
    pub fn new() -> Self {
        let pending: Arc<Mutex<Option<RouteJob>>> = Arc::new(Mutex::new(None));
        let (notify_tx, notify_rx) = mpsc::channel::<()>();
        let (result_tx, result_rx) = mpsc::channel::<RouteJobResult>();
        let pending_worker = Arc::clone(&pending);
        let handle = thread::spawn(move || route_worker_loop(pending_worker, notify_rx, result_tx));
        Self {
            pending,
            notify_tx,
            result_rx,
            _handle: handle,
        }
    }

    pub fn start_route(
        &self,
        request_id: i32,
        snapshot: Arc<RouteSnapshot>,
        portal: Arc<PortalGraph>,
        target_gx: i32,
        target_gy: i32,
        kind: i32,
        allow_astar: bool,
    ) -> bool {
        if let Ok(mut slot) = self.pending.lock() {
            *slot = Some(RouteJob {
                request_id,
                target_gx,
                target_gy,
                kind,
                allow_astar,
                snapshot,
                portal,
            });
        }
        self.notify_tx.send(()).is_ok()
    }

    pub fn cancel(&self, _request_id: i32) {
        if let Ok(mut slot) = self.pending.lock() {
            *slot = None;
        }
    }

    pub fn poll(&self) -> Option<RouteJobResult> {
        self.result_rx.try_recv().ok()
    }
}

fn route_worker_loop(
    pending: Arc<Mutex<Option<RouteJob>>>,
    notify_rx: Receiver<()>,
    result_tx: Sender<RouteJobResult>,
) {
    while notify_rx.recv().is_ok() {
        // Coalesce bursts: only run the latest job in the slot.
        loop {
            if notify_rx.try_recv().is_ok() {
                continue;
            }
            let job = pending.lock().ok().and_then(|mut g| g.take());
            let Some(job) = job else {
                break;
            };
            let found_route = find_route(
                &job.snapshot,
                &job.portal,
                job.target_gx,
                job.target_gy,
                job.kind,
                job.allow_astar,
            );
            let (path, source_key, found) = match found_route {
                Some(r) => (r.path, r.source_key, true),
                None => (Vec::new(), -1, false),
            };
            let _ = result_tx.send(RouteJobResult {
                request_id: job.request_id,
                path,
                source_key,
                found,
            });
            break;
        }
    }
}

/// Shared planner state for Godot binding.
pub struct RoutePlannerState {
    pub snapshot: Arc<Mutex<Option<Arc<RouteSnapshot>>>>,
    pub portal: Arc<Mutex<PortalGraph>>,
    pub worker: Mutex<Option<RouteWorker>>,
}

impl RoutePlannerState {
    pub fn new() -> Self {
        Self {
            snapshot: Arc::new(Mutex::new(None)),
            portal: Arc::new(Mutex::new(PortalGraph::default())),
            worker: Mutex::new(Some(RouteWorker::new())),
        }
    }
}
