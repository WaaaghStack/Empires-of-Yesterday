//! Simple-water territory propagation kernel (ports BattleTileControl.gd).

pub const FLOW_CONDUCTIVITY: f32 = 0.32;
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
    active_indices: Vec<usize>,
    active_seen: Vec<u8>,
    frontier_changed: bool,
    rounds_since_active_rebuild: i32,
}

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
            active_indices: Vec::new(),
            active_seen: vec![0; tile_count],
            frontier_changed: true,
            rounds_since_active_rebuild: 0,
        };
        if use_active_set {
            kernel.rebuild_active_indices();
        }
        kernel
    }

    pub fn advance_round(&mut self) {
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
    }

    fn inject_placed_spawners(&mut self) {
        for sp in &self.spawners {
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
        }
    }

    fn run_gradient_cancel_sync_pass(&mut self) {
        self.spread_pressure_gradient();
        self.cancel_overlapping_pressure();
        self.sync_ownership_from_pressures();
    }

    fn spread_pressure_gradient(&mut self) {
        self.gradient_flow_pass_into(true);
        std::mem::swap(&mut self.pressure_friendly, &mut self.pf_next);
        self.gradient_flow_pass_into(false);
        std::mem::swap(&mut self.pressure_hostile, &mut self.ph_next);
    }

    fn gradient_flow_pass_into(&mut self, friendly: bool) {
        let tile_count = self.tile_count;
        let w = self.grid_w;
        let h = self.grid_h;

        let (src, dst) = if friendly {
            (&self.pressure_friendly, &mut self.pf_next)
        } else {
            (&self.pressure_hostile, &mut self.ph_next)
        };
        dst.copy_from_slice(src);

        if self.use_active_set && !self.active_indices.is_empty() {
            let indices: Vec<usize> = self.active_indices.clone();
            let claimable: Vec<u8> = self.claimable_mask.clone();
            let elevation: Vec<f32> = self.elevation.clone();
            let flow_mult: Vec<f32> = self.terrain_flow_mult.clone();
            let src_copy: Vec<f32> = src.to_vec();
            let mut scratch: Vec<usize> = Vec::new();
            let mut seen: Vec<u8> = vec![0; tile_count];

            for &idx in &indices {
                seen[idx] = 1;
            }
            for &idx in &indices {
                Self::gradient_flow_tile_static(
                    w,
                    h,
                    idx,
                    &src_copy,
                    dst,
                    &claimable,
                    &elevation,
                    &flow_mult,
                    &mut scratch,
                    &mut seen,
                );
            }
            for ni in scratch {
                Self::gradient_flow_tile_static(
                    w,
                    h,
                    ni,
                    &src_copy,
                    dst,
                    &claimable,
                    &elevation,
                    &flow_mult,
                    &mut Vec::new(),
                    &mut seen,
                );
            }
            return;
        }

        let claimable = self.claimable_mask.clone();
        let elevation = self.elevation.clone();
        let flow_mult = self.terrain_flow_mult.clone();
        let src_copy = src.to_vec();
        for gy in 0..h {
            for gx in 0..w {
                let idx = (gy * w + gx) as usize;
                if claimable[idx] == 0 {
                    continue;
                }
                Self::gradient_flow_tile_static(
                    w,
                    h,
                    idx,
                    &src_copy,
                    dst,
                    &claimable,
                    &elevation,
                    &flow_mult,
                    &mut Vec::new(),
                    &mut vec![0; tile_count],
                );
            }
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
        let gx = (idx as i32) % w;
        let gy = (idx as i32) / w;
        let elev_s = elevation[idx];
        let h_src = effective_height(p, elev_s);

        let mut n_count = 0usize;
        let mut want_total = 0.0f32;
        let mut targets = [0usize; 4];
        let mut amounts = [0.0f32; 4];

        for (dx, dy) in CARDINAL {
            let nx = gx + dx;
            let ny = gy + dy;
            if nx < 0 || ny < 0 || nx >= w || ny >= h {
                continue;
            }
            let ni = (ny * w + nx) as usize;
            if claimable[ni] == 0 {
                continue;
            }
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

    fn set_owner_at(&mut self, idx: usize, new_owner: u8) {
        let old = self.owners[idx];
        if old == new_owner {
            return;
        }
        self.adjust_owner_count(old, -1);
        self.adjust_owner_count(new_owner, 1);
        self.owners[idx] = new_owner;
        self.frontier_changed = true;
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
        if force
            || self.frontier_changed
            || self.rounds_since_active_rebuild >= ACTIVE_REBUILD_INTERVAL
        {
            self.rebuild_active_indices();
            self.frontier_changed = false;
            self.rounds_since_active_rebuild = 0;
        }
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
                    let nx = gx + dx;
                    let ny = gy + dy;
                    if nx < 0 || ny < 0 || nx >= w || ny >= self.grid_h {
                        continue;
                    }
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
