//! Simple-water territory propagation kernel (ports BattleTileControl.gd).

pub const FLOW_CONDUCTIVITY: f32 = 0.32;
pub const BRIDGE_PIPE_SUCTION_RATE: f32 = 0.22;
pub const MIN_FLOW_DELTA: f32 = 0.1;
pub const MAX_OUTFLOW_FRAC: f32 = 0.5;
pub const MIN_CLAIM_PRESSURE: f32 = 0.04;
pub const CLAIM_DOMINANCE_RATIO: f32 = 1.15;
pub const ADAPTIVE_FRONTIER_EPS: i32 = 16;
pub const ACTIVE_PRESSURE_EPS: f32 = 0.05;
pub const ACTIVE_REBUILD_INTERVAL: i32 = 3;

pub const OWNER_NEUTRAL: u8 = 0;
pub const OWNER_FRIENDLY: u8 = 1;
pub const OWNER_HOSTILE: u8 = 2;
pub const OWNER_CONTESTED: u8 = 3;
pub const OWNER_UNCLAIMABLE: u8 = 4;

const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

#[inline]
fn effective_height(pressure: f32, elevation: f32) -> f32 {
    pressure + elevation
}

#[derive(Clone, Debug)]
pub struct Spawner {
    pub team: u8,
    pub gx: i32,
    pub gy: i32,
}

pub struct TerritoryKernel {
    pub grid_w: i32,
    pub grid_h: i32,
    pub tile_count: usize,
    pub claimable_mask: Vec<u8>,
    pub elevation: Vec<f32>,
    pub terrain_flow_mult: Vec<f32>,
    pub claim_ratio_mult: Vec<f32>,
    pub owners: Vec<u8>,
    pub pressure_friendly: Vec<f32>,
    pub pressure_hostile: Vec<f32>,
    pf_next: Vec<f32>,
    ph_next: Vec<f32>,
    pub friendly_spawn_rate: f32,
    pub hostile_spawn_rate: f32,
    pub player_home_idx: i32,
    pub enemy_home_idx: i32,
    pub spawners: Vec<Spawner>,
    pub friendly_tiles: i32,
    pub hostile_tiles: i32,
    prev_friendly_tiles: i32,
    prev_hostile_tiles: i32,
    pub use_active_set: bool,
    pub use_adaptive_double_pass: bool,
    pub wrap_longitude: bool,
    bridge_pipe_prev: Vec<i32>,
    bridge_pipe_next: Vec<i32>,
    bridge_water_mask: Vec<u8>,
    corridor_land_mask: Vec<u8>,
    active_indices: Vec<usize>,
    active_seen: Vec<u8>,
    frontier_changed: bool,
    rounds_since_active_rebuild: i32,
    gradient_halo_scratch: Vec<usize>,
    gradient_pass_seen: Vec<u8>,
    active_dirty_mark: Vec<u8>,
    active_dirty_list: Vec<usize>,
    owner_dirty_idx: Vec<i32>,
    owner_dirty_val: Vec<u8>,
    /// Bumped on ownership/claimable changes near a tile (soldier path invalidation).
    pub nav_dirty_stamp: Vec<u32>,
    nav_epoch: u32,
}

const INCREMENTAL_ACTIVE_MAX_DIRTY: usize = 4096;

impl TerritoryKernel {
    pub fn new(
        grid_w: i32,
        grid_h: i32,
        claimable_mask: Vec<u8>,
        elevation: Vec<f32>,
        terrain_flow_mult: Vec<f32>,
        claim_ratio_mult: Vec<f32>,
        owners: Vec<u8>,
        pressure_friendly: Vec<f32>,
        pressure_hostile: Vec<f32>,
        friendly_spawn_rate: f32,
        hostile_spawn_rate: f32,
        player_home_idx: i32,
        enemy_home_idx: i32,
        spawners: Vec<Spawner>,
        friendly_tiles: i32,
        hostile_tiles: i32,
        use_active_set: bool,
        use_adaptive_double_pass: bool,
        wrap_longitude: bool,
    ) -> Self {
        let tile_count = (grid_w * grid_h) as usize;
        let mut kernel = Self {
            grid_w,
            grid_h,
            tile_count,
            claimable_mask,
            elevation,
            terrain_flow_mult,
            claim_ratio_mult,
            owners,
            pressure_friendly,
            pressure_hostile,
            pf_next: vec![0.0; tile_count],
            ph_next: vec![0.0; tile_count],
            friendly_spawn_rate,
            hostile_spawn_rate,
            player_home_idx,
            enemy_home_idx,
            spawners,
            friendly_tiles,
            hostile_tiles,
            prev_friendly_tiles: friendly_tiles,
            prev_hostile_tiles: hostile_tiles,
            use_active_set,
            use_adaptive_double_pass,
            wrap_longitude,
            bridge_pipe_prev: vec![-1; tile_count],
            bridge_pipe_next: vec![-1; tile_count],
            bridge_water_mask: vec![0; tile_count],
            corridor_land_mask: vec![0; tile_count],
            active_indices: Vec::new(),
            active_seen: vec![0; tile_count],
            frontier_changed: true,
            rounds_since_active_rebuild: 0,
            gradient_halo_scratch: Vec::new(),
            gradient_pass_seen: vec![0; tile_count],
            active_dirty_mark: vec![0; tile_count],
            active_dirty_list: Vec::new(),
            owner_dirty_idx: Vec::new(),
            owner_dirty_val: Vec::new(),
            nav_dirty_stamp: vec![0; tile_count],
            nav_epoch: 0,
        };
        if use_active_set {
            kernel.rebuild_active_indices();
        }
        kernel
    }

    pub fn cell_index(&self, gx: i32, gy: i32) -> i32 {
        if gy < 0 || gy >= self.grid_h {
            return -1;
        }
        let Some(nx) = Self::wrap_nx(gx, self.grid_w, self.wrap_longitude) else {
            return -1;
        };
        gy * self.grid_w + nx
    }

    pub fn advance_round(&mut self) {
        self.advance_territory_round();
    }

    /// Run soldier agents then territory propagation (world conquest).
    pub fn advance_round_with_agents(&mut self, agents: &mut crate::agents::AgentLayer) {
        agents.tick(self);
        self.advance_territory_round();
    }

    fn advance_territory_round(&mut self) {
        self.owner_dirty_idx.clear();
        self.owner_dirty_val.clear();
        self.prev_friendly_tiles = self.friendly_tiles;
        self.prev_hostile_tiles = self.hostile_tiles;

        self.inject_home(self.player_home_idx, self.friendly_spawn_rate, true);
        self.inject_home(self.enemy_home_idx, self.hostile_spawn_rate, false);
        self.inject_placed_spawners();

        self.run_gradient_cancel_sync_pass();
        let frontier_delta = (self.friendly_tiles - self.prev_friendly_tiles).unsigned_abs()
            + (self.hostile_tiles - self.prev_hostile_tiles).unsigned_abs();
        if self.use_adaptive_double_pass && frontier_delta > ADAPTIVE_FRONTIER_EPS as u32 {
            self.run_gradient_cancel_sync_pass();
        }

        self.preserve_homes();
        self.maybe_rebuild_active_indices(false);
    }

    pub fn advance_rounds(&mut self, n: i32) {
        for _ in 0..n.max(0) {
            self.advance_round();
        }
    }

    /// Sync claimable tiles after bridge outposts open new landmasses (GDScript reachability extend).
    pub fn sync_pressures_from(&mut self, pressure_friendly: Vec<f32>, pressure_hostile: Vec<f32>) {
        if pressure_friendly.len() == self.tile_count {
            self.pressure_friendly = pressure_friendly;
        }
        if pressure_hostile.len() == self.tile_count {
            self.pressure_hostile = pressure_hostile;
        }
        self.frontier_changed = true;
        if self.use_active_set {
            self.rebuild_active_indices();
        }
    }

    /// Boost pressure along a completed bridge/corridor path (mirrors BattleTileControl.gd).
    pub fn inject_corridor_pressure_pulse(
        &mut self,
        path_keys: &[i32],
        team: u8,
        amount_scale: f32,
    ) {
        if path_keys.is_empty() || self.tile_count == 0 {
            return;
        }
        let base = if team == OWNER_FRIENDLY {
            self.friendly_spawn_rate
        } else {
            self.hostile_spawn_rate
        };
        let pulse = (base * amount_scale).max(12.0);
        let last_i = path_keys.len() - 1;
        for (i, &idx_i) in path_keys.iter().enumerate() {
            if idx_i < 0 {
                continue;
            }
            let idx = idx_i as usize;
            if idx >= self.tile_count || self.claimable_mask[idx] == 0 {
                continue;
            }
            let from_home = pulse * 0.96f32.powi(i as i32);
            let from_landing = pulse * 0.96f32.powi((last_i - i) as i32);
            let amt = from_home.max(from_landing);
            if team == OWNER_FRIENDLY {
                self.pressure_friendly[idx] += amt;
            } else {
                self.pressure_hostile[idx] += amt;
            }
            self.mark_pressure_dirty(idx);
        }
    }

    pub fn update_claimable(
        &mut self,
        claimable_mask: Vec<u8>,
        elevation: Vec<f32>,
        terrain_flow_mult: Vec<f32>,
        claim_ratio_mult: Vec<f32>,
        owners: Vec<u8>,
    ) {
        if claimable_mask.len() != self.tile_count {
            return;
        }
        self.claimable_mask = claimable_mask;
        if elevation.len() == self.tile_count {
            self.elevation = elevation;
        }
        if terrain_flow_mult.len() == self.tile_count {
            self.terrain_flow_mult = terrain_flow_mult;
        }
        if claim_ratio_mult.len() == self.tile_count {
            self.claim_ratio_mult = claim_ratio_mult;
        }
        if owners.len() == self.tile_count {
            self.owners = owners;
        }
        self.recount_ownership_tiles();
        self.frontier_changed = true;
        if self.use_active_set {
            self.rebuild_active_indices();
        }
    }

    pub fn update_bridge_pipe(
        &mut self,
        bridge_pipe_prev: Vec<i32>,
        bridge_pipe_next: Vec<i32>,
        bridge_water_mask: Vec<u8>,
        corridor_land_mask: Vec<u8>,
    ) {
        if bridge_pipe_prev.len() != self.tile_count {
            return;
        }
        self.bridge_pipe_prev = bridge_pipe_prev;
        if bridge_pipe_next.len() == self.tile_count {
            self.bridge_pipe_next = bridge_pipe_next;
        }
        if bridge_water_mask.len() == self.tile_count {
            self.bridge_water_mask = bridge_water_mask;
        }
        if corridor_land_mask.len() == self.tile_count {
            self.corridor_land_mask = corridor_land_mask;
        }
    }

    fn recount_ownership_tiles(&mut self) {
        self.friendly_tiles = 0;
        self.hostile_tiles = 0;
        for idx in 0..self.tile_count {
            if self.claimable_mask[idx] == 0 {
                continue;
            }
            match self.owners[idx] {
                OWNER_FRIENDLY => self.friendly_tiles += 1,
                OWNER_HOSTILE => self.hostile_tiles += 1,
                _ => {}
            }
        }
    }

    fn inject_home(&mut self, idx: i32, amount: f32, is_friendly: bool) {
        if idx < 0 || amount <= 0.0 {
            return;
        }
        let i = idx as usize;
        if i >= self.tile_count {
            return;
        }
        if is_friendly {
            self.pressure_friendly[i] += amount;
        } else {
            self.pressure_hostile[i] += amount;
        }
        self.mark_active_dirty(i);
    }

    fn inject_placed_spawners(&mut self) {
        let spawners: Vec<Spawner> = self.spawners.clone();
        let mut dirty: Vec<usize> = Vec::new();
        for sp in &spawners {
            if sp.gx < 0 || sp.gy < 0 {
                continue;
            }
            let idx = sp.gy * self.grid_w + sp.gx;
            if idx < 0 || idx as usize >= self.tile_count {
                continue;
            }
            let ui = idx as usize;
            if self.claimable_mask[ui] == 0 {
                continue;
            }
            let amount = if sp.team == OWNER_FRIENDLY {
                self.friendly_spawn_rate
            } else {
                self.hostile_spawn_rate
            };
            if sp.team == OWNER_FRIENDLY {
                self.pressure_friendly[ui] += amount;
            } else {
                self.pressure_hostile[ui] += amount;
            }
            dirty.push(ui);
        }
        for ui in dirty {
            self.mark_active_dirty(ui);
        }
    }

    fn run_gradient_cancel_sync_pass(&mut self) {
        self.spread_pressure_gradient();
        self.cancel_overlapping_pressure();
        self.sync_ownership_from_pressures();
    }

    fn spread_pressure_gradient(&mut self) {
        self.gradient_flow_pass_into(true);
        self.bridge_pipe_suction_pass(true);
        std::mem::swap(&mut self.pressure_friendly, &mut self.pf_next);
        self.gradient_flow_pass_into(false);
        self.bridge_pipe_suction_pass(false);
        std::mem::swap(&mut self.pressure_hostile, &mut self.ph_next);
    }

    fn bridge_pipe_suction_pass(&mut self, friendly: bool) {
        if BRIDGE_PIPE_SUCTION_RATE <= 0.0 {
            return;
        }
        let dst = if friendly {
            &mut self.pf_next
        } else {
            &mut self.ph_next
        };
        let claimable = &self.claimable_mask;
        let prev = &self.bridge_pipe_prev;
        let next = &self.bridge_pipe_next;
        let bw = &self.bridge_water_mask;
        let cl = &self.corridor_land_mask;
        let rate = BRIDGE_PIPE_SUCTION_RATE;
        let tile_count = self.tile_count;
        for idx in 0..tile_count {
            if claimable[idx] == 0 {
                continue;
            }
            let on_pipe = bw.get(idx).copied().unwrap_or(0) > 0
                || cl.get(idx).copied().unwrap_or(0) > 0;
            if !on_pipe {
                continue;
            }
            let prev_i = prev.get(idx).copied().unwrap_or(-1);
            let next_i = next.get(idx).copied().unwrap_or(-1);
            if prev_i >= 0 {
                let pi = prev_i as usize;
                if pi < tile_count && claimable[pi] != 0 && dst[pi] > dst[idx] {
                    let pull = (dst[pi] - dst[idx]) * rate;
                    let cap = pull.min(dst[pi] * 0.18);
                    if cap > 0.001 {
                        dst[pi] -= cap;
                        dst[idx] += cap;
                    }
                }
            }
            if next_i >= 0 {
                let ni = next_i as usize;
                if ni < tile_count && claimable[ni] != 0 && dst[idx] > dst[ni] {
                    let push = (dst[idx] - dst[ni]) * rate;
                    let cap_n = push.min(dst[idx] * 0.18);
                    if cap_n > 0.001 {
                        dst[idx] -= cap_n;
                        dst[ni] += cap_n;
                    }
                }
            }
        }
    }

    fn gradient_flow_pass_into(&mut self, friendly: bool) {
        let w = self.grid_w;
        let h = self.grid_h;
        let tile_count = self.tile_count;
        let wrap_longitude = self.wrap_longitude;

        if friendly {
            self.pf_next.copy_from_slice(&self.pressure_friendly);
        } else {
            self.ph_next.copy_from_slice(&self.pressure_hostile);
        }

        let (src, dst) = if friendly {
            (&self.pressure_friendly, &mut self.pf_next)
        } else {
            (&self.pressure_hostile, &mut self.ph_next)
        };

        if self.use_active_set && !self.active_indices.is_empty() {
            self.gradient_pass_seen.fill(0);
            for &idx in &self.active_indices {
                if idx < tile_count {
                    self.gradient_pass_seen[idx] = 1;
                }
            }
            let active_copy: Vec<usize> = self.active_indices.clone();
            self.gradient_halo_scratch.clear();
            for &idx in &active_copy {
                Self::gradient_flow_tile_static(
                    w,
                    h,
                    idx,
                    src,
                    dst,
                    &self.claimable_mask,
                    &self.elevation,
                    &self.terrain_flow_mult,
                    wrap_longitude,
                    &self.bridge_pipe_prev,
                    &self.bridge_pipe_next,
                    &self.bridge_water_mask,
                    &self.corridor_land_mask,
                    &mut self.gradient_halo_scratch,
                    &mut self.gradient_pass_seen,
                );
            }
            let halo: Vec<usize> = self.gradient_halo_scratch.clone();
            for ni in halo {
                Self::gradient_flow_tile_static(
                    w,
                    h,
                    ni,
                    src,
                    dst,
                    &self.claimable_mask,
                    &self.elevation,
                    &self.terrain_flow_mult,
                    wrap_longitude,
                    &self.bridge_pipe_prev,
                    &self.bridge_pipe_next,
                    &self.bridge_water_mask,
                    &self.corridor_land_mask,
                    &mut Vec::new(),
                    &mut self.gradient_pass_seen,
                );
            }
            return;
        }

        self.gradient_pass_seen.fill(0);
        for gy in 0..h {
            for gx in 0..w {
                let idx = (gy * w + gx) as usize;
                if self.claimable_mask[idx] == 0 {
                    continue;
                }
                Self::gradient_flow_tile_static(
                    w,
                    h,
                    idx,
                    src,
                    dst,
                    &self.claimable_mask,
                    &self.elevation,
                    &self.terrain_flow_mult,
                    wrap_longitude,
                    &self.bridge_pipe_prev,
                    &self.bridge_pipe_next,
                    &self.bridge_water_mask,
                    &self.corridor_land_mask,
                    &mut Vec::new(),
                    &mut self.gradient_pass_seen,
                );
            }
        }
    }

    fn wrap_nx(nx: i32, w: i32, wrap_longitude: bool) -> Option<i32> {
        if nx < 0 || nx >= w {
            if wrap_longitude {
                Some((nx + w) % w)
            } else {
                None
            }
        } else {
            Some(nx)
        }
    }

    pub fn wrap_nx_public(nx: i32, w: i32, wrap_longitude: bool) -> Option<i32> {
        Self::wrap_nx(nx, w, wrap_longitude)
    }

    fn pipe_neighbor_indices(
        idx: usize,
        claimable: &[u8],
        bridge_pipe_prev: &[i32],
        bridge_pipe_next: &[i32],
    ) -> [usize; 2] {
        let mut out = [usize::MAX; 2];
        let mut n = 0usize;
        if idx < bridge_pipe_prev.len() {
            let prev_i = bridge_pipe_prev[idx];
            if prev_i >= 0 {
                let pi = prev_i as usize;
                if pi < claimable.len() && claimable[pi] != 0 {
                    out[n] = pi;
                    n += 1;
                }
            }
        }
        if idx < bridge_pipe_next.len() {
            let next_i = bridge_pipe_next[idx];
            if next_i >= 0 {
                let ni = next_i as usize;
                if ni < claimable.len() && claimable[ni] != 0 {
                    if n == 0 || out[0] != ni {
                        out[n] = ni;
                    }
                }
            }
        }
        out
    }

    /// Bridge/corridor tiles prefer pipe topology; land uses cardinal neighbors.
    fn flow_neighbor_indices(
        w: i32,
        h: i32,
        idx: usize,
        claimable: &[u8],
        wrap_longitude: bool,
        bridge_pipe_prev: &[i32],
        bridge_pipe_next: &[i32],
        bridge_water_mask: &[u8],
        corridor_land_mask: &[u8],
        scratch: &mut Vec<usize>,
    ) {
        scratch.clear();
        let on_pipe = bridge_water_mask.get(idx).copied().unwrap_or(0) > 0
            || corridor_land_mask.get(idx).copied().unwrap_or(0) > 0;
        if on_pipe {
            let pipe = Self::pipe_neighbor_indices(idx, claimable, bridge_pipe_prev, bridge_pipe_next);
            for pi in pipe {
                if pi != usize::MAX && !scratch.iter().any(|&x| x == pi) {
                    scratch.push(pi);
                }
            }
        }
        let gx = (idx as i32) % w;
        let gy = (idx as i32) / w;
        for (dx, dy) in CARDINAL {
            let ny = gy + dy;
            if ny < 0 || ny >= h {
                continue;
            }
            let Some(nx) = Self::wrap_nx(gx + dx, w, wrap_longitude) else {
                continue;
            };
            let ni = (ny * w + nx) as usize;
            if ni >= claimable.len() || claimable[ni] == 0 {
                continue;
            }
            if scratch.iter().any(|&x| x == ni) {
                continue;
            }
            scratch.push(ni);
        }
    }

    fn gradient_flow_tile_static(
        w: i32,
        h: i32,
        idx: usize,
        src: &[f32],
        dst: &mut [f32],
        claimable: &[u8],
        elevation: &[f32],
        flow_mult: &[f32],
        wrap_longitude: bool,
        bridge_pipe_prev: &[i32],
        bridge_pipe_next: &[i32],
        bridge_water_mask: &[u8],
        corridor_land_mask: &[u8],
        halo_out: &mut Vec<usize>,
        active_seen: &mut [u8],
    ) {
        if claimable[idx] == 0 {
            return;
        }
        let p = src[idx];
        if p <= 0.0 {
            return;
        }
        let elev_s = elevation[idx];
        let h_src = effective_height(p, elev_s);

        let mut n_count = 0usize;
        let mut want_total = 0.0f32;
        let mut targets = [0usize; 6];
        let mut amounts = [0.0f32; 6];
        let mut neighbors: Vec<usize> = Vec::with_capacity(6);
        Self::flow_neighbor_indices(
            w,
            h,
            idx,
            claimable,
            wrap_longitude,
            bridge_pipe_prev,
            bridge_pipe_next,
            bridge_water_mask,
            corridor_land_mask,
            &mut neighbors,
        );

        for &ni in &neighbors {
            let p_n = src[ni];
            let h_n = effective_height(p_n, elevation[ni]);
            let dh = h_src - h_n;
            if dh <= MIN_FLOW_DELTA {
                continue;
            }
            let edge_flow = (flow_mult[idx] * flow_mult[ni]).sqrt();
            let amount = dh * FLOW_CONDUCTIVITY * edge_flow;
            targets[n_count] = ni;
            amounts[n_count] = amount;
            n_count += 1;
            want_total += amount;
            if !halo_out.is_empty() && active_seen[ni] == 0 {
                halo_out.push(ni);
                active_seen[ni] = 1;
            }
        }

        if want_total <= 0.0 {
            return;
        }
        let cap = (p * MAX_OUTFLOW_FRAC).min(want_total);
        let scale = cap / want_total;
        dst[idx] -= cap;
        for i in 0..n_count {
            dst[targets[i]] += amounts[i] * scale;
        }
    }

    fn cancel_overlapping_pressure(&mut self) {
        if self.use_active_set && !self.active_indices.is_empty() {
            for &idx in &self.active_indices {
                if self.claimable_mask[idx] == 0 {
                    continue;
                }
                let pf = self.pressure_friendly[idx];
                let ph = self.pressure_hostile[idx];
                if pf > 0.0 && ph > 0.0 {
                    let cancel = pf.min(ph);
                    self.pressure_friendly[idx] -= cancel;
                    self.pressure_hostile[idx] -= cancel;
                }
            }
            return;
        }
        for idx in 0..self.tile_count {
            if self.claimable_mask[idx] == 0 {
                self.pressure_friendly[idx] = 0.0;
                self.pressure_hostile[idx] = 0.0;
                continue;
            }
            let pf = self.pressure_friendly[idx];
            let ph = self.pressure_hostile[idx];
            if pf > 0.0 && ph > 0.0 {
                let cancel = pf.min(ph);
                self.pressure_friendly[idx] -= cancel;
                self.pressure_hostile[idx] -= cancel;
            }
        }
    }

    fn sync_ownership_from_pressures(&mut self) {
        if self.use_active_set && !self.active_indices.is_empty() {
            let indices: Vec<usize> = self.active_indices.clone();
            for idx in indices {
                self.sync_ownership_tile(idx);
            }
            return;
        }
        for idx in 0..self.tile_count {
            self.sync_ownership_tile(idx);
        }
    }

    fn sync_ownership_tile(&mut self, idx: usize) {
        if self.claimable_mask[idx] == 0 {
            self.set_owner_at(idx, OWNER_UNCLAIMABLE);
            return;
        }
        let pf = self.pressure_friendly[idx];
        let ph = self.pressure_hostile[idx];
        let tile_ratio = CLAIM_DOMINANCE_RATIO * self.claim_ratio_mult[idx];
        let new_owner = if pf < MIN_CLAIM_PRESSURE && ph < MIN_CLAIM_PRESSURE {
            let cur = self.owners[idx];
            if cur != OWNER_FRIENDLY && cur != OWNER_HOSTILE {
                OWNER_NEUTRAL
            } else {
                cur
            }
        } else if pf > ph * tile_ratio {
            OWNER_FRIENDLY
        } else if ph > pf * tile_ratio {
            OWNER_HOSTILE
        } else {
            OWNER_CONTESTED
        };
        self.set_owner_at(idx, new_owner);
    }

    #[inline]
    pub fn nav_stamp_at(&self, gx: i32, gy: i32) -> u32 {
        let idx = self.cell_index(gx, gy);
        if idx < 0 {
            return 0;
        }
        let ui = idx as usize;
        if ui >= self.nav_dirty_stamp.len() {
            return 0;
        }
        self.nav_dirty_stamp[ui]
    }

    pub fn bump_nav_dirty(&mut self, idx: usize) {
        if idx >= self.tile_count {
            return;
        }
        self.nav_epoch = self.nav_epoch.wrapping_add(1);
        if self.nav_epoch == 0 {
            self.nav_epoch = 1;
            self.nav_dirty_stamp.fill(0);
        }
        let epoch = self.nav_epoch;
        self.nav_dirty_stamp[idx] = epoch;
        let w = self.grid_w;
        let gx = (idx as i32) % w;
        let gy = (idx as i32) / w;
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let ni = self.cell_index(gx + dx, gy + dy);
            if ni < 0 {
                continue;
            }
            let nui = ni as usize;
            if nui < self.tile_count {
                self.nav_dirty_stamp[nui] = epoch;
            }
        }
    }

    fn set_owner_at(&mut self, idx: usize, new_owner: u8) {
        let old = self.owners[idx];
        if old == new_owner {
            return;
        }
        self.adjust_owner_count(old, -1);
        self.adjust_owner_count(new_owner, 1);
        self.owners[idx] = new_owner;
        self.frontier_changed = true;
        self.owner_dirty_idx.push(idx as i32);
        self.owner_dirty_val.push(new_owner);
        self.mark_active_dirty(idx);
        self.bump_nav_dirty(idx);
    }

    fn adjust_owner_count(&mut self, owner: u8, delta: i32) {
        if delta == 0 {
            return;
        }
        match owner {
            OWNER_FRIENDLY => self.friendly_tiles = (self.friendly_tiles + delta).max(0),
            OWNER_HOSTILE => self.hostile_tiles = (self.hostile_tiles + delta).max(0),
            _ => {}
        }
    }

    fn preserve_homes(&mut self) {
        self.claim_home_idx(self.player_home_idx, OWNER_FRIENDLY);
        self.claim_home_idx(self.enemy_home_idx, OWNER_HOSTILE);
        let spawners: Vec<Spawner> = self.spawners.clone();
        for sp in spawners {
            if sp.gx < 0 || sp.gy < 0 {
                continue;
            }
            let owner = if sp.team == OWNER_FRIENDLY {
                OWNER_FRIENDLY
            } else {
                OWNER_HOSTILE
            };
            let idx = (sp.gy * self.grid_w + sp.gx) as usize;
            if idx < self.tile_count {
                self.set_owner_at(idx, owner);
            }
        }
    }

    fn claim_home_idx(&mut self, idx: i32, owner: u8) {
        if idx < 0 {
            return;
        }
        let ui = idx as usize;
        if ui >= self.tile_count || self.claimable_mask[ui] == 0 {
            return;
        }
        self.set_owner_at(ui, owner);
    }

    fn maybe_rebuild_active_indices(&mut self, force: bool) {
        if !self.use_active_set {
            return;
        }
        self.rounds_since_active_rebuild += 1;
        let periodic = self.rounds_since_active_rebuild >= ACTIVE_REBUILD_INTERVAL;
        if force || periodic {
            self.rebuild_active_indices();
            self.frontier_changed = false;
            self.rounds_since_active_rebuild = 0;
            self.active_dirty_list.clear();
            self.active_dirty_mark.fill(0);
            return;
        }
        if self.frontier_changed && !self.active_dirty_list.is_empty() {
            if self.active_dirty_list.len() <= INCREMENTAL_ACTIVE_MAX_DIRTY {
                self.patch_active_indices();
            } else {
                self.rebuild_active_indices();
            }
            self.frontier_changed = false;
            self.active_dirty_list.clear();
            self.active_dirty_mark.fill(0);
        }
    }

    fn mark_active_dirty(&mut self, idx: usize) {
        if !self.use_active_set || idx >= self.tile_count {
            return;
        }
        if self.active_dirty_mark[idx] == 0 {
            self.active_dirty_mark[idx] = 1;
            self.active_dirty_list.push(idx);
        }
        let w = self.grid_w;
        let gx = (idx as i32) % w;
        let gy = (idx as i32) / w;
        for (dx, dy) in CARDINAL {
            let ny = gy + dy;
            if ny < 0 || ny >= self.grid_h {
                continue;
            }
            let Some(nx) = Self::wrap_nx(gx + dx, w, self.wrap_longitude) else {
                continue;
            };
            let ni = (ny * w + nx) as usize;
            if ni >= self.tile_count || self.active_dirty_mark[ni] != 0 {
                continue;
            }
            self.active_dirty_mark[ni] = 1;
            self.active_dirty_list.push(ni);
        }
    }

    fn is_tile_active(&self, idx: usize) -> bool {
        if idx >= self.tile_count || self.claimable_mask[idx] == 0 {
            return false;
        }
        if self.pressure_friendly[idx] > ACTIVE_PRESSURE_EPS
            || self.pressure_hostile[idx] > ACTIVE_PRESSURE_EPS
        {
            return true;
        }
        let w = self.grid_w;
        let gx = (idx as i32) % w;
        let gy = (idx as i32) / w;
        for (dx, dy) in CARDINAL {
            let ny = gy + dy;
            if ny < 0 || ny >= self.grid_h {
                continue;
            }
            let Some(nx) = Self::wrap_nx(gx + dx, w, self.wrap_longitude) else {
                continue;
            };
            let ni = (ny * w + nx) as usize;
            if self.claimable_mask[ni] == 0 {
                continue;
            }
            if self.owners[ni] == OWNER_CONTESTED || self.owners[idx] != self.owners[ni] {
                return true;
            }
        }
        false
    }

    fn remove_active_index(&mut self, idx: usize) {
        if idx >= self.active_seen.len() || self.active_seen[idx] == 0 {
            return;
        }
        self.active_seen[idx] = 0;
        if let Some(pos) = self.active_indices.iter().position(|&i| i == idx) {
            self.active_indices.swap_remove(pos);
        }
    }

    fn patch_active_indices(&mut self) {
        let dirty: Vec<usize> = self.active_dirty_list.clone();
        for idx in dirty {
            if idx >= self.tile_count {
                continue;
            }
            let should = self.is_tile_active(idx);
            let was = self.active_seen[idx] != 0;
            if should && !was {
                self.active_indices.push(idx);
                self.active_seen[idx] = 1;
            } else if !should && was {
                self.remove_active_index(idx);
            }
        }
    }

    pub fn apply_claimable_delta(
        &mut self,
        indices: &[i32],
        claimable: &[u8],
        owners: &[u8],
    ) {
        for (i, &idx_i) in indices.iter().enumerate() {
            if idx_i < 0 {
                continue;
            }
            let ui = idx_i as usize;
            if ui >= self.tile_count {
                continue;
            }
            if i < claimable.len() {
                let new_claimable = claimable[i];
                if self.claimable_mask[ui] != new_claimable {
                    self.claimable_mask[ui] = new_claimable;
                    self.bump_nav_dirty(ui);
                }
            }
            if i < owners.len() {
                let new_owner = owners[i];
                if self.owners[ui] != new_owner {
                    self.set_owner_at(ui, new_owner);
                }
            } else {
                self.mark_active_dirty(ui);
            }
        }
        self.frontier_changed = true;
    }

    pub fn take_owner_dirty(&mut self) -> (Vec<i32>, Vec<u8>) {
        (
            std::mem::take(&mut self.owner_dirty_idx),
            std::mem::take(&mut self.owner_dirty_val),
        )
    }

    /// Returns a full w*h R8 byte array suitable for the ownership overlay texture.
    /// Includes the display mapping (0/128/192/255) and longitude seam fix.
    /// This lets GDScript do a fast set_data + update with zero per-tile loop in script.
    pub fn owner_display_r8(&self) -> Vec<u8> {
        let mut out = vec![0u8; self.tile_count];
        for (i, &ow) in self.owners.iter().enumerate() {
            if i < self.claimable_mask.len() && self.claimable_mask[i] == 0 {
                out[i] = 0;
                continue;
            }
            out[i] = match ow {
                OWNER_FRIENDLY => 128,
                OWNER_HOSTILE => 192,
                OWNER_CONTESTED => 255,
                _ => 0,
            };
        }
        // Longitude seam copy (right edge mirrors left) so repeat sampling on the globe looks correct.
        let w = self.grid_w as usize;
        if w >= 2 {
            let h = self.grid_h as usize;
            for gy in 0..h {
                let row = gy * w;
                out[row + w - 1] = out[row];
            }
        }
        out
    }

    pub fn mark_pressure_dirty(&mut self, idx: usize) {
        self.mark_active_dirty(idx);
        self.frontier_changed = true;
    }

    fn rebuild_active_indices(&mut self) {
        self.active_indices.clear();
        if self.tile_count == 0 {
            return;
        }
        self.active_seen.fill(0);
        let w = self.grid_w;
        for idx in 0..self.tile_count {
            if self.claimable_mask[idx] == 0 {
                continue;
            }
            let mut active = self.pressure_friendly[idx] > ACTIVE_PRESSURE_EPS
                || self.pressure_hostile[idx] > ACTIVE_PRESSURE_EPS;
            if !active {
                let gx = (idx as i32) % w;
                let gy = (idx as i32) / w;
                for (dx, dy) in CARDINAL {
                    let ny = gy + dy;
                    if ny < 0 || ny >= self.grid_h {
                        continue;
                    }
                    let Some(nx) = Self::wrap_nx(gx + dx, w, self.wrap_longitude) else {
                        continue;
                    };
                    let ni = (ny * w + nx) as usize;
                    if self.claimable_mask[ni] == 0 {
                        continue;
                    }
                    if self.owners[ni] == OWNER_CONTESTED || self.owners[idx] != self.owners[ni] {
                        active = true;
                        break;
                    }
                }
            }
            if active {
                self.active_indices.push(idx);
                self.active_seen[idx] = 1;
            }
        }
    }
}
