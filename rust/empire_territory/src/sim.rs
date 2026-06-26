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

pub(crate) const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

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
    pub claimable_tile_count: i32,
    prev_friendly_tiles: i32,
    prev_hostile_tiles: i32,
    pub use_active_set: bool,
    pub use_adaptive_double_pass: bool,
    pub wrap_longitude: bool,
    pub home_inject_enabled: bool,
    pub spawner_inject_interval_rounds: i32,
    territory_round_index: u32,
    // World-edit terrain + reachability (Phase 3 — Rust authority during WC play)
    pub(crate) passable_mask: Vec<u8>,
    pub(crate) land_mask: Vec<u8>,
    pub(crate) tile_height: Vec<f32>,
    pub(crate) move_cost: Vec<f32>,
    pub(crate) defense: Vec<f32>,
    pub(crate) cover_cells: Vec<u8>,
    pub(crate) friendly_reachable: Vec<u8>,
    pub(crate) hostile_reachable: Vec<u8>,
    pub(crate) friendly_bridge_reachable: Vec<u8>,
    pub(crate) hostile_bridge_reachable: Vec<u8>,
    pub(crate) friendly_corridor_land: Vec<u8>,
    pub(crate) hostile_corridor_land: Vec<u8>,
    pub(crate) world_edit_ready: bool,
    active_indices: Vec<usize>,
    active_seen: Vec<u8>,
    pub(crate) frontier_changed: bool,
    rounds_since_active_rebuild: i32,
    gradient_halo_scratch: Vec<usize>,
    gradient_pass_seen: Vec<u8>,
    active_dirty_mark: Vec<u8>,
    active_dirty_list: Vec<usize>,
    owner_dirty_idx: Vec<i32>,
    owner_dirty_val: Vec<u8>,
    /// Pre-mapped R8 ownership overlay (0/128/192/255 + seam); authoritative display buffer.
    owner_display: Vec<u8>,
    display_dirty_idx: Vec<i32>,
    display_dirty_val: Vec<u8>,
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
        let claimable_tile_count = claimable_mask.iter().filter(|&&c| c != 0).count() as i32;
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
            claimable_tile_count,
            prev_friendly_tiles: friendly_tiles,
            prev_hostile_tiles: hostile_tiles,
            use_active_set,
            use_adaptive_double_pass,
            wrap_longitude,
            home_inject_enabled: true,
            spawner_inject_interval_rounds: 10,
            territory_round_index: 0,
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
            owner_display: Vec::new(),
            display_dirty_idx: Vec::new(),
            display_dirty_val: Vec::new(),
            nav_dirty_stamp: vec![0; tile_count],
            nav_epoch: 0,
            passable_mask: Vec::new(),
            land_mask: Vec::new(),
            tile_height: Vec::new(),
            move_cost: Vec::new(),
            defense: Vec::new(),
            cover_cells: Vec::new(),
            friendly_reachable: vec![0; tile_count],
            hostile_reachable: vec![0; tile_count],
            friendly_bridge_reachable: vec![0; tile_count],
            hostile_bridge_reachable: vec![0; tile_count],
            friendly_corridor_land: vec![0; tile_count],
            hostile_corridor_land: vec![0; tile_count],
            world_edit_ready: false,
        };
        kernel.rebuild_owner_display();
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
        // Dirty owner/display lists accumulate until sync_owners_delta() — do not clear per round
        // or multi-round batches drop all but the last round's overlay deltas.
        self.prev_friendly_tiles = self.friendly_tiles;
        self.prev_hostile_tiles = self.hostile_tiles;
        self.territory_round_index = self.territory_round_index.saturating_add(1);

        if self.home_inject_enabled && self.should_inject_pressure_sources_this_round() {
            self.inject_home(self.player_home_idx, self.friendly_spawn_rate, true);
            self.inject_home(self.enemy_home_idx, self.hostile_spawn_rate, false);
        }
        if self.should_inject_pressure_sources_this_round() {
            self.inject_placed_spawners();
        }

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
            self.rebuild_owner_display();
        }
        self.recount_claimable_tiles();
        self.recount_ownership_tiles();
        self.frontier_changed = true;
        if self.use_active_set {
            self.rebuild_active_indices();
        }
    }

    fn spread_pressure_gradient(&mut self) {
        self.gradient_flow_pass_into(true);
        std::mem::swap(&mut self.pressure_friendly, &mut self.pf_next);
        self.gradient_flow_pass_into(false);
        std::mem::swap(&mut self.pressure_hostile, &mut self.ph_next);
    }

    pub(crate) fn recount_ownership_tiles(&mut self) {
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
            let amount = if sp.team == OWNER_FRIENDLY {
                self.friendly_spawn_rate
            } else {
                self.hostile_spawn_rate
            };
            let is_friendly = sp.team == OWNER_FRIENDLY;
            // Pump adjacent tiles — not the spawner cell (so the tile under it can flip).
            for (dx, dy) in CARDINAL {
                let nx = sp.gx + dx;
                let ny = sp.gy + dy;
                let ni = self.cell_index(nx, ny);
                if ni < 0 {
                    continue;
                }
                let ui = ni as usize;
                if self.claimable_mask[ui] == 0 {
                    continue;
                }
                if is_friendly {
                    self.pressure_friendly[ui] += amount;
                } else {
                    self.pressure_hostile[ui] += amount;
                }
                dirty.push(ui);
            }
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

    pub fn set_home_inject_enabled(&mut self, enabled: bool) {
        self.home_inject_enabled = enabled;
    }

    fn should_inject_pressure_sources_this_round(&self) -> bool {
        let interval = self.spawner_inject_interval_rounds.max(1) as u32;
        (self.territory_round_index - 1) % interval == 0
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

    fn flow_neighbor_indices(
        w: i32,
        h: i32,
        idx: usize,
        claimable: &[u8],
        wrap_longitude: bool,
        scratch: &mut Vec<usize>,
    ) {
        scratch.clear();
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

    pub(crate) fn set_claimable_mask_at(&mut self, idx: usize, new_val: u8) {
        if idx >= self.tile_count {
            return;
        }
        let old = self.claimable_mask[idx];
        if old == new_val {
            return;
        }
        self.claimable_mask[idx] = new_val;
        if old == 0 && new_val != 0 {
            self.claimable_tile_count += 1;
        } else if old != 0 && new_val == 0 {
            self.claimable_tile_count -= 1;
        }
    }

    pub(crate) fn set_owner_at(&mut self, idx: usize, new_owner: u8) {
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
        self.refresh_display_at(idx);
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

    /// HQ capitals only — operational spawners are not force-owned here.
    fn preserve_homes(&mut self) {
        self.claim_home_idx(self.player_home_idx, OWNER_FRIENDLY);
        self.claim_home_idx(self.enemy_home_idx, OWNER_HOSTILE);
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

    pub(crate) fn mark_active_dirty(&mut self, idx: usize) {
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
        elevation: &[f32],
        terrain_flow_mult: &[f32],
        claim_ratio_mult: &[f32],
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
                    self.set_claimable_mask_at(ui, new_claimable);
                    self.bump_nav_dirty(ui);
                    self.mark_active_dirty(ui);
                    self.refresh_display_at(ui);
                }
            }
            if i < elevation.len() {
                self.elevation[ui] = elevation[i];
            }
            if i < terrain_flow_mult.len() {
                self.terrain_flow_mult[ui] = terrain_flow_mult[i];
            }
            if i < claim_ratio_mult.len() {
                self.claim_ratio_mult[ui] = claim_ratio_mult[i];
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
        if self.use_active_set {
            self.rebuild_active_indices();
        }
    }

    pub fn take_owner_dirty(&mut self) -> (Vec<i32>, Vec<u8>) {
        (
            std::mem::take(&mut self.owner_dirty_idx),
            std::mem::take(&mut self.owner_dirty_val),
        )
    }

    pub fn take_display_dirty(&mut self) -> (Vec<i32>, Vec<u8>) {
        (
            std::mem::take(&mut self.display_dirty_idx),
            std::mem::take(&mut self.display_dirty_val),
        )
    }

    /// Full w*h R8 overlay bytes (incremental buffer; no per-call recompute).
    pub fn owner_display_r8(&self) -> Vec<u8> {
        self.owner_display.clone()
    }

    fn display_byte_for(&self, idx: usize) -> u8 {
        if idx >= self.tile_count {
            return 0;
        }
        if idx < self.claimable_mask.len() && self.claimable_mask[idx] == 0 {
            return 0;
        }
        match self.owners[idx] {
            OWNER_FRIENDLY => 128,
            OWNER_HOSTILE => 192,
            OWNER_CONTESTED => 255,
            _ => 0,
        }
    }

    fn push_display_dirty(&mut self, idx: usize, byte: u8) {
        self.display_dirty_idx.push(idx as i32);
        self.display_dirty_val.push(byte);
    }

    pub(crate) fn refresh_display_at(&mut self, idx: usize) {
        if idx >= self.tile_count {
            return;
        }
        let byte = self.display_byte_for(idx);
        if self.owner_display[idx] == byte {
            return;
        }
        self.owner_display[idx] = byte;
        self.push_display_dirty(idx, byte);
        let w = self.grid_w as usize;
        if w >= 2 && idx % w == 0 {
            let seam = idx + w - 1;
            if seam < self.tile_count && self.owner_display[seam] != byte {
                self.owner_display[seam] = byte;
                self.push_display_dirty(seam, byte);
            }
        }
    }

    fn rebuild_owner_display(&mut self) {
        self.owner_display.resize(self.tile_count, 0);
        for idx in 0..self.tile_count {
            self.owner_display[idx] = self.display_byte_for(idx);
        }
        self.apply_longitude_seam_to_display();
    }

    fn apply_longitude_seam_to_display(&mut self) {
        let w = self.grid_w as usize;
        if w < 2 {
            return;
        }
        let h = self.grid_h as usize;
        for gy in 0..h {
            let row = gy * w;
            self.owner_display[row + w - 1] = self.owner_display[row];
        }
    }

    pub fn mark_pressure_dirty(&mut self, idx: usize) {
        self.mark_active_dirty(idx);
        self.frontier_changed = true;
    }

    pub(crate) fn rebuild_active_indices(&mut self) {
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
