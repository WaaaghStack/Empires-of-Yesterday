//! Route planner snapshot, portal graph, async worker — search logic lives in `pathfind`.

use std::collections::VecDeque;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

use crate::pathfind::engine::find_route_by_kind;

pub const ROUTE_KIND_OUTPOST: i32 = 0;
pub const ROUTE_KIND_CORRIDOR: i32 = 1;
pub const MAX_PATHFIND_EXPAND: usize = 12_000;

pub(crate) const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

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

    pub(crate) fn is_land(&self, idx: usize) -> bool {
        idx < self.land_mask.len() && self.land_mask[idx] != 0
    }

    pub(crate) fn is_water(&self, idx: usize) -> bool {
        idx < self.land_mask.len() && self.land_mask[idx] == 0
    }

    pub(crate) fn is_route_cell(&self, idx: usize, allow_water: bool) -> bool {
        if idx >= self.land_mask.len() {
            return false;
        }
        if self.land_mask[idx] != 0 {
            return true;
        }
        allow_water
    }

    pub(crate) fn is_infra_cell(&self, idx: usize) -> bool {
        if idx >= self.land_mask.len() {
            return false;
        }
        if idx < self.bridge_mask.len() && self.bridge_mask[idx] != 0 {
            return true;
        }
        self.land_mask[idx] != 0
    }

    pub(crate) fn land_comp_at(&self, idx: usize) -> i32 {
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

#[derive(Clone, Debug)]
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

/// Single entry for sync + async route worker — delegates to `pathfind` rule engine.
pub fn find_route(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    kind: i32,
    allow_astar: bool,
) -> Option<RouteResult> {
    find_route_detail(snapshot, portal, target_gx, target_gy, kind, allow_astar)
        .filter(|r| !r.result.path.is_empty())
        .map(|r| r.result)
}

#[derive(Clone, Debug)]
pub struct RouteLookup {
    pub result: RouteResult,
    pub reject: i32,
    pub expand_count: usize,
}

pub fn find_route_detail(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    kind: i32,
    allow_astar: bool,
) -> Option<RouteLookup> {
    find_route_by_kind(
        snapshot,
        portal,
        target_gx,
        target_gy,
        kind,
        allow_astar,
    )
    .map(|r| RouteLookup {
        result: r.result,
        reject: r.reject,
        expand_count: r.stats.expand_count,
    })
}

pub(crate) fn reconstruct_path(parent: &[i32], goal: i32) -> Vec<i32> {
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

pub(crate) fn heuristic(cell: i32, goal: i32, w: i32) -> i32 {
    let gx = cell % w;
    let gy = cell / w;
    let tx = goal % w;
    let ty = goal / w;
    let mut dx = (tx - gx).abs();
    dx = dx.min(w - dx);
    let dy = (ty - gy).abs();
    dx + dy
}

pub(crate) fn wrap_x(gx: i32, w: i32, wrap: bool) -> Option<i32> {
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

pub(crate) fn cardinal_adjacent(a: i32, b: i32, w: i32) -> bool {
    let ax = a % w;
    let ay = a / w;
    let bx = b % w;
    let by = b / w;
    let mut dx = (ax - bx).abs();
    dx = dx.min(w - dx);
    let dy = (ay - by).abs();
    dx + dy == 1
}

pub(crate) fn is_coastal(snapshot: &RouteSnapshot, gx: i32, gy: i32) -> bool {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn test_snapshot() -> RouteSnapshot {
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
        }
    }

    #[test]
    fn find_route_dispatches_through_pathfind_engine() {
        let snap = test_snapshot();
        let mut portal = PortalGraph::default();
        portal.source_keys.push(0);
        portal.source_land_comp.push(0);
        portal.infra_reach.push(vec![0]);
        let outpost = find_route(&snap, &portal, 1, 0, ROUTE_KIND_OUTPOST, true);
        assert!(outpost.is_some());
        let corridor = find_route(&snap, &portal, 4, 2, ROUTE_KIND_CORRIDOR, true);
        assert!(corridor.is_some());
        let path = &corridor.unwrap().path;
        assert!(path.iter().any(|&k| snap.is_water(k as usize)));
    }
}
