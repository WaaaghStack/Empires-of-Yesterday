//! Shared per-team logistics network — timer road growth, strain, wave audit (replaces builder bots).

use std::collections::{HashMap, HashSet, VecDeque};

use crate::sim::{OWNER_FRIENDLY, OWNER_HOSTILE};
use crate::structures::{
    has_build_phase, is_corridor_path_kind, kind_to_str, StructureRecord, StructureStore,
    KIND_BARRACKS, KIND_CORRIDOR_LINK, KIND_HANGAR, KIND_SPAWNER, STATE_ACTIVE,
    STATE_BUILDING, STATE_CONNECTING,
};

const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

#[derive(Clone, Debug)]
pub struct LogisticsConfig {
    pub road_cells_per_sec: f32,
    pub outpost_build_sec: f32,
    pub barracks_build_sec: f32,
    pub hangar_build_sec: f32,
    pub outpost_max_health: f32,
    pub reconcile_cells_per_frame: usize,
    pub full_recal_interval_sec: f32,
    pub placement_heat_decay_per_sec: f32,
    pub burst_base: f32,
    pub burst_ratio: f32,
    pub structure_drain_spawner: f32,
    pub structure_drain_barracks: f32,
    pub structure_drain_hangar: f32,
    pub structure_drain_corridor: f32,
    pub strain_sensitivity: f32,
}

impl Default for LogisticsConfig {
    fn default() -> Self {
        Self {
            road_cells_per_sec: 1.0,
            outpost_build_sec: 5.0,
            barracks_build_sec: 60.0,
            hangar_build_sec: 60.0,
            outpost_max_health: 10.0,
            reconcile_cells_per_frame: 648,
            full_recal_interval_sec: 25.0,
            placement_heat_decay_per_sec: 0.85,
            burst_base: 0.02,
            burst_ratio: 1.35,
            structure_drain_spawner: 0.04,
            structure_drain_barracks: 0.06,
            structure_drain_hangar: 0.06,
            structure_drain_corridor: 0.03,
            strain_sensitivity: 1.0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct CellArrivalEvent {
    pub sid: i32,
    pub seg_from_idx: i32,
    pub kind: u8,
}

#[derive(Clone, Debug)]
pub struct PathCompletionEvent {
    pub sid: i32,
    pub gx: i32,
    pub gy: i32,
    pub team: u8,
    pub is_corridor_link: bool,
    pub kind: u8,
}

#[derive(Clone, Debug, Default)]
pub struct LogisticsStepEvents {
    pub visual_dirty: bool,
    pub cell_arrivals: Vec<CellArrivalEvent>,
    pub path_completions: Vec<PathCompletionEvent>,
    pub completed_corridor_sids: Vec<i32>,
    pub new_built_cells: Vec<i32>,
    pub friendly_output_mult: f32,
    pub hostile_output_mult: f32,
}

#[derive(Clone, Debug)]
struct TeamNetwork {
    tile_count: usize,
    grid_w: i32,
    grid_h: i32,
    home_key: i32,
    built: Vec<u8>,
    planned: Vec<u8>,
    target: Vec<u8>,
    grow_queue: VecDeque<i32>,
    grow_queued: HashSet<i32>,
    /// Fractional build progress per upcoming network cell (parallel road fronts).
    cell_grow_progress: HashMap<i32, f32>,
    placement_heat: f32,
    burst_strain: f32,
    reconcile_cursor: usize,
    full_recal_timer: f32,
}

impl TeamNetwork {
    fn new(tile_count: usize, grid_w: i32, grid_h: i32, home_key: i32) -> Self {
        let mut built = vec![0u8; tile_count];
        if home_key >= 0 && (home_key as usize) < tile_count {
            built[home_key as usize] = 1;
        }
        Self {
            tile_count,
            grid_w,
            grid_h,
            home_key,
            built,
            planned: vec![0u8; tile_count],
            target: vec![0u8; tile_count],
            grow_queue: VecDeque::new(),
            grow_queued: HashSet::new(),
            cell_grow_progress: HashMap::new(),
            placement_heat: 0.0,
            burst_strain: 0.0,
            reconcile_cursor: 0,
            full_recal_timer: 25.0,
        }
    }

    fn cell_index(&self, gx: i32, gy: i32) -> i32 {
        if gy < 0 || gy >= self.grid_h || self.grid_w <= 0 {
            return -1;
        }
        let mut nx = gx;
        if nx < 0 {
            nx += self.grid_w;
        } else if nx >= self.grid_w {
            nx -= self.grid_w;
        }
        if nx < 0 || nx >= self.grid_w {
            return -1;
        }
        gy * self.grid_w + nx
    }

    fn is_built(&self, key: i32) -> bool {
        key >= 0 && (key as usize) < self.tile_count && self.built[key as usize] != 0
    }

    fn is_planned(&self, key: i32) -> bool {
        key >= 0 && (key as usize) < self.tile_count && self.planned[key as usize] != 0
    }

    fn mark_built(&mut self, key: i32) {
        if key < 0 || (key as usize) >= self.tile_count {
            return;
        }
        let ui = key as usize;
        self.built[ui] = 1;
        self.planned[ui] = 0;
        self.target[ui] = 1;
        self.grow_queued.remove(&key);
    }

    fn enqueue_planned_path(&mut self, path: &[i32]) {
        for &key in path {
            if key < 0 || (key as usize) >= self.tile_count {
                continue;
            }
            if self.is_built(key) {
                continue;
            }
            let ui = key as usize;
            if self.planned[ui] == 0 {
                self.planned[ui] = 1;
                self.target[ui] = 1;
            }
            if self.grow_queued.insert(key) {
                self.grow_queue.push_back(key);
            }
        }
    }

    /// Re-enqueue any unbuilt cells on a connecting route (shared-network cells may skip growth credit).
    fn ensure_path_enqueued(&mut self, path: &[i32]) {
        self.enqueue_planned_path(path);
    }

    /// Next cell to grow along a path in order — never skip ahead on a route.
    fn next_grow_cell_on_path(&self, path: &[i32]) -> Option<i32> {
        for &key in path {
            if self.is_built(key) {
                continue;
            }
            if !self.is_planned(key) {
                return None;
            }
            if self.adjacent_to_built(key) || key == self.home_key {
                return Some(key);
            }
            return None;
        }
        None
    }

    /// Each connecting route feeds its next cell; independent fronts build in parallel.
    fn step_path_growth_for_sids(
        &mut self,
        sids: &[i32],
        store: &mut StructureStore,
        dt: f32,
        road_cells_per_sec: f32,
        result: &mut LogisticsStepEvents,
    ) -> Vec<i32> {
        let mut new_cells = Vec::new();
        if dt <= 0.0 || road_cells_per_sec <= 0.0 || sids.is_empty() {
            return new_cells;
        }

        self.cell_grow_progress.retain(|key, _| {
            *key >= 0
                && (*key as usize) < self.tile_count
                && self.built[*key as usize] == 0
        });

        for &sid in sids {
            let Some(st) = store.structures.get(&sid) else {
                continue;
            };
            let path = &st.path_keys;
            let Some(next_key) = self.next_grow_cell_on_path(path) else {
                continue;
            };
            let entry = self.cell_grow_progress.entry(next_key).or_insert(0.0);
            *entry += road_cells_per_sec * dt;
        }

        let mut ready: Vec<i32> = self
            .cell_grow_progress
            .iter()
            .filter(|(key, progress)| {
                **progress >= 1.0
                    && **key >= 0
                    && (**key as usize) < self.tile_count
                    && self.built[**key as usize] == 0
            })
            .map(|(key, _)| *key)
            .collect();
        ready.sort_unstable();

        for key in ready {
            if self.is_built(key) {
                continue;
            }
            let Some(progress) = self.cell_grow_progress.get_mut(&key) else {
                continue;
            };
            if *progress < 1.0 {
                continue;
            }
            *progress -= 1.0;
            self.mark_built(key);
            self.grow_queue.retain(|&k| k != key);
            credit_path_growth_for_cell(sids, store, key, result);
            new_cells.push(key);
        }

        self.cell_grow_progress
            .retain(|_, progress| *progress >= 0.001);

        new_cells
    }

    fn adjacent_to_built(&self, key: i32) -> bool {
        if key < 0 || self.grid_w <= 0 {
            return false;
        }
        let gx = key % self.grid_w;
        let gy = key / self.grid_w;
        for (dx, dy) in CARDINAL {
            let nk = self.cell_index(gx + dx, gy + dy);
            if self.is_built(nk) {
                return true;
            }
        }
        false
    }

    fn consecutive_built_prefix(path: &[i32], built: &[u8]) -> f32 {
        let mut n = 0usize;
        for &key in path {
            if key < 0 || (key as usize) >= built.len() || built[key as usize] == 0 {
                break;
            }
            n += 1;
        }
        (n.max(1)) as f32
    }

    fn drain_for_kind(kind: u8, cfg: &LogisticsConfig) -> f32 {
        match kind {
            KIND_SPAWNER => cfg.structure_drain_spawner,
            KIND_BARRACKS => cfg.structure_drain_barracks,
            KIND_HANGAR => cfg.structure_drain_hangar,
            KIND_CORRIDOR_LINK => cfg.structure_drain_corridor,
            _ => 0.0,
        }
    }

    fn connectivity_factor(st: &StructureRecord) -> f32 {
        if st.path_keys.is_empty() {
            return 0.2;
        }
        let built = st.path_built;
        let len = st.path_keys.len() as f32;
        if built >= len {
            1.0
        } else if built > 1.0 {
            0.5
        } else {
            0.2
        }
    }

    fn new_cells_on_path(path: &[i32], built: &[u8]) -> Vec<i32> {
        let mut out = Vec::new();
        for &key in path {
            if key < 0 || (key as usize) >= built.len() {
                continue;
            }
            if built[key as usize] != 0 {
                continue;
            }
            out.push(key);
        }
        out
    }

    fn compute_ongoing_strain(&self, store: &StructureStore, team: u8, cfg: &LogisticsConfig) -> f32 {
        let mut sum = 0.0_f32;
        for st in store.structures.values() {
            if st.team != team {
                continue;
            }
            if st.state != STATE_ACTIVE && st.state != STATE_BUILDING {
                continue;
            }
            if !is_corridor_path_kind(st.kind) && !has_build_phase(st.kind) {
                continue;
            }
            let drain = Self::drain_for_kind(st.kind, cfg);
            if drain <= 0.0 {
                continue;
            }
            sum += drain * Self::connectivity_factor(st);
        }
        sum
    }

    fn effective_output_mult(&self, ongoing: f32, cfg: &LogisticsConfig) -> f32 {
        let total = self.burst_strain + ongoing;
        1.0 / (1.0 + total * cfg.strain_sensitivity)
    }

    fn tick_heat(&mut self, dt: f32, cfg: &LogisticsConfig) {
        if dt <= 0.0 {
            return;
        }
        self.placement_heat *= cfg.placement_heat_decay_per_sec.powf(dt);
        if self.placement_heat < 0.01 {
            self.placement_heat = 0.0;
        }
        self.burst_strain *= cfg.placement_heat_decay_per_sec.powf(dt * 0.5);
    }

    fn on_placement(&mut self, cfg: &LogisticsConfig) {
        self.placement_heat += 1.0;
        let exp = (self.placement_heat - 1.0).max(0.0);
        self.burst_strain += cfg.burst_base * cfg.burst_ratio.powf(exp);
    }

    fn rebuild_target_from_store(&mut self, store: &StructureStore, team: u8) {
        self.target.fill(0);
        if self.home_key >= 0 && (self.home_key as usize) < self.tile_count {
            self.target[self.home_key as usize] = 1;
        }
        for st in store.structures.values() {
            if st.team != team || !is_corridor_path_kind(st.kind) {
                continue;
            }
            for &key in &st.path_keys {
                if key >= 0 && (key as usize) < self.tile_count {
                    self.target[key as usize] = 1;
                }
            }
        }
        for ui in 0..self.tile_count {
            if self.built[ui] != 0 {
                self.target[ui] = 1;
            }
        }
    }

    /// Partitioned target/built invariant repair. Intentionally empty until a real
    /// check is implemented — must not burn `budget` on a no-op cursor walk.
    fn wave_audit(&mut self, _budget: usize) {
        // When implementing: walk `reconcile_cursor` over `tile_count` with real
        // target-vs-built validation; do not reintroduce empty spin loops.
    }
}

#[derive(Clone, Debug, Default)]
pub struct LogisticsLayer {
    pub friendly: Option<TeamNetwork>,
    pub hostile: Option<TeamNetwork>,
    pub player_home: (i32, i32),
    pub enemy_home: (i32, i32),
}

impl LogisticsLayer {
    pub fn is_configured(&self) -> bool {
        self.friendly.is_some() && self.hostile.is_some()
    }

    pub fn configure(
        &mut self,
        tile_count: usize,
        grid_w: i32,
        grid_h: i32,
        cfg: &LogisticsConfig,
    ) {
        let player_key = if self.player_home.0 >= 0 {
            gy_key(self.player_home.0, self.player_home.1, grid_w)
        } else {
            -1
        };
        let enemy_key = if self.enemy_home.0 >= 0 {
            gy_key(self.enemy_home.0, self.enemy_home.1, grid_w)
        } else {
            -1
        };
        let mut friendly = TeamNetwork::new(tile_count, grid_w, grid_h, player_key);
        let mut hostile = TeamNetwork::new(tile_count, grid_w, grid_h, enemy_key);
        friendly.full_recal_timer = cfg.full_recal_interval_sec;
        hostile.full_recal_timer = cfg.full_recal_interval_sec;
        self.friendly = Some(friendly);
        self.hostile = Some(hostile);
    }

    pub fn register_terminal(
        &mut self,
        sid: i32,
        store: &mut StructureStore,
        team: u8,
        grid_w: i32,
        cfg: &LogisticsConfig,
    ) {
        let path = store
            .structures
            .get(&sid)
            .map(|st| st.path_keys.clone())
            .unwrap_or_default();
        if path.is_empty() {
            return;
        }
        let net = self.network_mut(team);
        let Some(net) = net else {
            return;
        };
        net.on_placement(cfg);
        if let Some(&source_key) = path.first() {
            net.mark_built(source_key);
        }
        let new_cells = TeamNetwork::new_cells_on_path(&path, &net.built);
        net.enqueue_planned_path(&new_cells);
        if let Some(st_mut) = store.structures.get_mut(&sid) {
            let initial = TeamNetwork::consecutive_built_prefix(&path, &net.built);
            st_mut.path_built = initial.max(st_mut.path_built);
        }
        let _ = grid_w;
    }

    pub fn unregister_terminal(&mut self, sid: i32, store: &StructureStore, team: u8) {
        let _ = sid;
        let net = self.network_mut(team);
        let Some(net) = net else {
            return;
        };
        net.full_recal_timer = 0.0;
        net.rebuild_target_from_store(store, team);
    }

    fn network_mut(&mut self, team: u8) -> Option<&mut TeamNetwork> {
        if team == OWNER_HOSTILE {
            self.hostile.as_mut()
        } else {
            self.friendly.as_mut()
        }
    }

    fn network(&self, team: u8) -> Option<&TeamNetwork> {
        if team == OWNER_HOSTILE {
            self.hostile.as_ref()
        } else {
            self.friendly.as_ref()
        }
    }

    pub fn seed_from_store(&mut self, store: &StructureStore, cfg: &LogisticsConfig) {
        for team in [OWNER_FRIENDLY, OWNER_HOSTILE] {
            let net = self.network_mut(team);
            let Some(net) = net else {
                continue;
            };
            for st in store.structures.values() {
                if st.team != team || !is_corridor_path_kind(st.kind) {
                    continue;
                }
                let built_n = st.path_built.floor() as i32;
                let limit = built_n.min(st.path_keys.len() as i32);
                for (i, &pk) in st.path_keys.iter().enumerate() {
                    if (i as i32) < limit {
                        if pk >= 0 && (pk as usize) < net.tile_count {
                            net.built[pk as usize] = 1;
                            net.planned[pk as usize] = 0;
                            net.target[pk as usize] = 1;
                        }
                    }
                }
                let new_cells = TeamNetwork::new_cells_on_path(&st.path_keys, &net.built);
                net.enqueue_planned_path(&new_cells);
            }
            net.rebuild_target_from_store(store, team);
        }
        let _ = cfg;
    }

    pub fn built_mask(&self, team: u8) -> Vec<u8> {
        self.network(team)
            .map(|n| n.built.clone())
            .unwrap_or_default()
    }

    pub fn step_frame(
        &mut self,
        dt: f32,
        store: &mut StructureStore,
        grid_w: i32,
        grid_h: i32,
        cfg: &LogisticsConfig,
    ) -> LogisticsStepEvents {
        let mut result = LogisticsStepEvents::default();
        if dt <= 0.0 {
            result.friendly_output_mult = 1.0;
            result.hostile_output_mult = 1.0;
            return result;
        }
        let tile_count = (grid_w * grid_h) as usize;
        if tile_count == 0 {
            result.friendly_output_mult = 1.0;
            result.hostile_output_mult = 1.0;
            return result;
        }
        if self.friendly.is_none() || self.hostile.is_none() {
            self.configure(tile_count, grid_w, grid_h, cfg);
        }

        for team in [OWNER_FRIENDLY, OWNER_HOSTILE] {
            self.step_team(dt, store, cfg, team, &mut result);
        }
        result.friendly_output_mult = self
            .friendly
            .as_ref()
            .map(|n| {
                n.effective_output_mult(n.compute_ongoing_strain(store, OWNER_FRIENDLY, cfg), cfg)
            })
            .unwrap_or(1.0);
        result.hostile_output_mult = self
            .hostile
            .as_ref()
            .map(|n| {
                n.effective_output_mult(n.compute_ongoing_strain(store, OWNER_HOSTILE, cfg), cfg)
            })
            .unwrap_or(1.0);
        result
    }

    fn step_team(
        &mut self,
        dt: f32,
        store: &mut StructureStore,
        cfg: &LogisticsConfig,
        team: u8,
        result: &mut LogisticsStepEvents,
    ) {
        let net = if team == OWNER_HOSTILE {
            self.hostile.as_mut()
        } else {
            self.friendly.as_mut()
        };
        let Some(net) = net else {
            return;
        };

        net.tick_heat(dt, cfg);
        net.full_recal_timer -= dt;
        if net.full_recal_timer <= 0.0 {
            net.full_recal_timer = cfg.full_recal_interval_sec;
            net.rebuild_target_from_store(store, team);
        }
        net.wave_audit(cfg.reconcile_cells_per_frame);

        let connecting_sids: Vec<i32> = store
            .structures
            .values()
            .filter(|st| {
                st.team == team
                    && st.state == STATE_CONNECTING
                    && is_corridor_path_kind(st.kind)
            })
            .map(|st| st.id)
            .collect();

        for &sid in &connecting_sids {
            let Some(st) = store.structures.get(&sid) else {
                continue;
            };
            if st.path_keys.len() >= 2 {
                net.ensure_path_enqueued(&st.path_keys);
            }
        }

        let growth_sids: Vec<i32> = connecting_sids
            .iter()
            .copied()
            .filter(|sid| {
                store
                    .structures
                    .get(sid)
                    .map(|st| st.path_keys.len() >= 2)
                    .unwrap_or(false)
            })
            .collect();

        let new_cells = net.step_path_growth_for_sids(
            &growth_sids,
            store,
            dt,
            cfg.road_cells_per_sec,
            result,
        );
        if !new_cells.is_empty() {
            result.new_built_cells.extend(new_cells.iter().copied());
            result.visual_dirty = true;
        }
        if !connecting_sids.is_empty() {
            let completions: Vec<PathCompletionEvent> =
                sync_structures_for_team(net, store, cfg, team, result);
            for ev in completions {
                if ev.is_corridor_link {
                    result.completed_corridor_sids.push(ev.sid);
                }
                result.path_completions.push(ev);
            }
        }
    }
}

fn credit_path_growth_for_cell(
    sids: &[i32],
    store: &mut StructureStore,
    key: i32,
    result: &mut LogisticsStepEvents,
) {
    for &sid in sids {
        let Some(st) = store.structures.get(&sid) else {
            continue;
        };
        if st.state != STATE_CONNECTING {
            continue;
        }
        let next_idx = st.path_built.floor() as usize;
        let path = st.path_keys.clone();
        if next_idx >= path.len() || path[next_idx] != key {
            continue;
        }
        let kind = st.kind;
        let old_built = st.path_built;
        let Some(st_mut) = store.structures.get_mut(&sid) else {
            continue;
        };
        st_mut.path_built = (next_idx + 1) as f32;
        if st_mut.path_built > old_built + 0.001 {
            let seg_from = (next_idx as i32 - 1).max(0);
            result.cell_arrivals.push(CellArrivalEvent {
                sid,
                seg_from_idx: seg_from,
                kind,
            });
            result.visual_dirty = true;
        }
    }
}

fn sync_path_built_from_prefix(
    st: &mut StructureRecord,
    built: &[u8],
    result: &mut LogisticsStepEvents,
) {
    if st.path_keys.is_empty() {
        return;
    }
    let prefix = TeamNetwork::consecutive_built_prefix(&st.path_keys, built);
    let old_built = st.path_built;
    if prefix <= old_built + 0.001 {
        return;
    }
    let old_cells = old_built.floor() as i32;
    let new_cells = prefix.floor() as i32;
    let sid = st.id;
    let kind = st.kind;
    st.path_built = prefix;
    for seg in old_cells..new_cells {
        result.cell_arrivals.push(CellArrivalEvent {
            sid,
            seg_from_idx: (seg - 1).max(0),
            kind,
        });
    }
    result.visual_dirty = true;
}

fn gy_key(gx: i32, gy: i32, grid_w: i32) -> i32 {
    if grid_w <= 0 || gx < 0 || gy < 0 {
        return -1;
    }
    gy * grid_w + gx
}

fn sync_structures_for_team(
    net: &TeamNetwork,
    store: &mut StructureStore,
    cfg: &LogisticsConfig,
    team: u8,
    result: &mut LogisticsStepEvents,
) -> Vec<PathCompletionEvent> {
    let mut completions = Vec::new();
    let sids: Vec<i32> = store
        .structures
        .values()
        .filter(|st| st.team == team && st.state == STATE_CONNECTING)
        .map(|st| st.id)
        .collect();

    for sid in sids {
        let Some(st) = store.structures.get(&sid) else {
            continue;
        };
        if !is_corridor_path_kind(st.kind) {
            continue;
        }
        let path_len = st.path_keys.len();
        if path_len < 2 {
            if let Some(done) = on_path_completed(store, sid, cfg) {
                completions.push(done);
            }
            continue;
        }
        if let Some(st_mut) = store.structures.get_mut(&sid) {
            sync_path_built_from_prefix(st_mut, &net.built, result);
        }

        let still_connecting = store
            .structures
            .get(&sid)
            .map(|s| s.state == STATE_CONNECTING)
            .unwrap_or(false);
        let path_built = store
            .structures
            .get(&sid)
            .map(|s| s.path_built)
            .unwrap_or(0.0);
        if still_connecting && path_built >= path_len as f32 {
            if let Some(done) = on_path_completed(store, sid, cfg) {
                completions.push(done);
            }
        }
    }
    completions
}

fn build_sec_for_kind(kind: u8, cfg: &LogisticsConfig) -> f32 {
    if kind == KIND_BARRACKS {
        cfg.barracks_build_sec
    } else if kind == KIND_HANGAR {
        cfg.hangar_build_sec
    } else {
        cfg.outpost_build_sec
    }
}

fn on_path_completed(
    store: &mut StructureStore,
    sid: i32,
    cfg: &LogisticsConfig,
) -> Option<PathCompletionEvent> {
    let Some(st) = store.structures.get_mut(&sid) else {
        return None;
    };
    let path_len = if st.path_keys.is_empty() {
        st.path_len
    } else {
        st.path_keys.len() as i32
    };
    st.path_len = path_len;
    st.path_built = path_len as f32;
    let kind = st.kind;
    let is_corridor_link = kind == KIND_CORRIDOR_LINK;
    if !is_corridor_link {
        let build_sec = build_sec_for_kind(kind, cfg);
        st.state = crate::structures::STATE_BUILDING;
        st.build_remaining = build_sec;
        if has_build_phase(kind) {
            st.health = cfg.outpost_max_health;
        }
    }
    Some(PathCompletionEvent {
        sid,
        gx: st.gx,
        gy: st.gy,
        team: st.team,
        is_corridor_link,
        kind,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::structures::{KIND_SPAWNER, StructureRecord};

    #[test]
    fn logistics_grows_path_and_completes() {
        let mut layer = LogisticsLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            ..Default::default()
        };
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 1,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 3,
            gy: 0,
            path_keys: vec![0, 1, 2, 3],
            path_built: 1.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.ready = true;
        layer.configure(16, 16, 16, &cfg);
        layer.register_terminal(1, &mut store, OWNER_FRIENDLY, 16, &cfg);
        let dt = 1.0;
        let mut done = false;
        for _ in 0..32 {
            let frame = layer.step_frame(dt, &mut store, 16, 16, &cfg);
            if !frame.path_completions.is_empty() {
                done = true;
                break;
            }
        }
        assert!(done, "logistics should complete connecting path");
    }

    #[test]
    fn logistics_grows_multiple_routes_in_parallel() {
        let mut layer = LogisticsLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            ..Default::default()
        };
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 1,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 2,
            gy: 0,
            path_keys: vec![0, 1, 2],
            path_built: 1.0,
            path_len: 3,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.upsert(StructureRecord {
            id: 2,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 2,
            gy: 1,
            path_keys: vec![0, 16, 17, 18],
            path_built: 1.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.ready = true;
        layer.configure(256, 16, 16, &cfg);
        layer.register_terminal(1, &mut store, OWNER_FRIENDLY, 16, &cfg);
        layer.register_terminal(2, &mut store, OWNER_FRIENDLY, 16, &cfg);
        let frame = layer.step_frame(1.0, &mut store, 16, 16, &cfg);
        let net = layer.friendly.as_ref().unwrap();
        assert!(net.is_built(1), "route 1 should grow horizontally");
        assert!(net.is_built(16), "route 2 should grow vertically in parallel");
        assert_eq!(frame.new_built_cells.len(), 2);
    }

    #[test]
    fn logistics_grows_paths_in_order_not_queue_skip() {
        let mut layer = LogisticsLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            ..Default::default()
        };
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 1,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 2,
            gy: 0,
            path_keys: vec![0, 1, 2],
            path_built: 1.0,
            path_len: 3,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.upsert(StructureRecord {
            id: 2,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 2,
            gy: 1,
            path_keys: vec![0, 16, 17, 18],
            path_built: 1.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.ready = true;
        layer.configure(256, 16, 16, &cfg);
        layer.register_terminal(1, &mut store, OWNER_FRIENDLY, 16, &cfg);
        layer.register_terminal(2, &mut store, OWNER_FRIENDLY, 16, &cfg);
        for _ in 0..16 {
            layer.step_frame(1.0, &mut store, 16, 16, &cfg);
        }
        let st1 = store.structures.get(&1).unwrap();
        assert!(
            st1.path_built >= 3.0,
            "path A should complete in order, got path_built={}",
            st1.path_built
        );
    }

    #[test]
    fn logistics_completes_when_path_fully_built() {
        let mut layer = LogisticsLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            ..Default::default()
        };
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        let path = vec![0, 1, 2, 3];
        store.upsert(StructureRecord {
            id: 8,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 3,
            gy: 0,
            path_keys: path.clone(),
            path_built: 3.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.ready = true;
        layer.configure(16, 16, 16, &cfg);
        layer.register_terminal(8, &mut store, OWNER_FRIENDLY, 16, &cfg);
        let net = layer.friendly.as_mut().unwrap();
        for &key in &path {
            if key >= 0 && (key as usize) < net.built.len() {
                net.built[key as usize] = 1;
            }
        }
        let frame = layer.step_frame(0.016, &mut store, 16, 16, &cfg);
        assert!(
            !frame.path_completions.is_empty(),
            "path_built catch-up should complete connecting structure"
        );
        assert_eq!(
            store.structures.get(&8).unwrap().state,
            STATE_BUILDING,
            "structure should enter building phase"
        );
    }

    #[test]
    fn logistics_syncs_path_built_from_shared_network_mask() {
        let mut layer = LogisticsLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            ..Default::default()
        };
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        let path = vec![0, 1, 2, 3];
        store.upsert(StructureRecord {
            id: 9,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 3,
            gy: 0,
            path_keys: path.clone(),
            path_built: 2.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
        });
        store.ready = true;
        layer.configure(16, 16, 16, &cfg);
        layer.register_terminal(9, &mut store, OWNER_FRIENDLY, 16, &cfg);
        let net = layer.friendly.as_mut().unwrap();
        for &key in &path {
            if key >= 0 && (key as usize) < net.built.len() {
                net.built[key as usize] = 1;
            }
        }
        let frame = layer.step_frame(0.016, &mut store, 16, 16, &cfg);
        assert!(
            !frame.path_completions.is_empty(),
            "shared mask should sync path_built and complete"
        );
        assert_eq!(
            store.structures.get(&9).unwrap().path_built,
            4.0,
            "path_built should match full path"
        );
    }
}

pub fn kind_str(kind: u8) -> &'static str {
    kind_to_str(kind)
}
