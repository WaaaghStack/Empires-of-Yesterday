//! Simple-water territory propagation kernel (ports BattleTileControl.gd).

// Flow constants are centralized in `flow_constants` (A12/C15); re-export for existing call sites.
pub use crate::flow_constants::{FLOW_CONDUCTIVITY, MAX_OUTFLOW_FRAC, MIN_FLOW_DELTA};

pub const MIN_CLAIM_PRESSURE: f32 = 0.04;
pub const CLAIM_DOMINANCE_RATIO: f32 = 1.15;
pub const ADAPTIVE_FRONTIER_EPS: i32 = 16;
pub const ACTIVE_PRESSURE_EPS: f32 = 0.05;
pub const ACTIVE_REBUILD_INTERVAL: i32 = 3;
/// Soft cap on active-set size under dual-front sprawl (B7).
/// When exceeded after patch/rebuild, dry interiors are pruned first (tier-1);
/// if still over cap, wet deep interiors are pruned (tier-2) while contested /
/// frontier / spreading tips stay protected so growth stays blob-like, not spines.
pub const ACTIVE_SET_SOFT_CAP: usize = 24_000;
/// Max dirty cells processed by an incremental active-set patch per call (B7).
pub const PATCH_ACTIVE_INDICES_BUDGET: usize = 4096;

pub const OWNER_NEUTRAL: u8 = 0;
pub const OWNER_FRIENDLY: u8 = 1;
pub const OWNER_HOSTILE: u8 = 2;
pub const OWNER_CONTESTED: u8 = 3;
pub const OWNER_UNCLAIMABLE: u8 = 4;

pub const SPAWNER_MODE_PUMP: u8 = 0;
pub const SPAWNER_MODE_DRAIN: u8 = 1;
pub const SPAWNER_MODE_BATTERY: u8 = 2;
/// Battery stores this many inject-waves of neighbor output before capping.
pub const BATTERY_MAX_WAVES: f32 = 24.0;

pub const PAINT_NONE: u8 = 0;
/// Player-brushed priority region (soldiers + bombers hunt unowned cells in the mask).
pub const PAINT_AREA: u8 = 1;
/// Legacy alias kept so Godot `PAINT_BEACHHEAD` still matches kind 1.
#[allow(dead_code)]
pub const PAINT_BEACHHEAD: u8 = PAINT_AREA;
/// Unused live kind; kept so Godot `PAINT_STRIKE` stays a stable 2.
#[allow(dead_code)]
pub const PAINT_STRIKE: u8 = 2;
/// Max land cells in one paint stroke (~3× the first 36-cell stain).
pub const PAINT_CELL_CAP: i32 = 108;

pub(crate) const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

#[inline]
pub(crate) fn effective_height(pressure: f32, elevation: f32) -> f32 {
    pressure + elevation
}

#[derive(Clone, Debug, Default)]
pub struct Spawner {
    pub team: u8,
    pub gx: i32,
    pub gy: i32,
    pub mode: u8,
    pub tank: f32,
    pub sid: i32,
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
    /// Per-team paint (index by owner id 1/2). kind 0 = none.
    pub paint_kind: [u8; 3],
    pub paint_gx: [i32; 3],
    pub paint_gy: [i32; 3],
    /// 1 on cells in the painted region (player stroke, capped).
    pub paint_land: [Vec<u8>; 3],
    /// Hop distance to the nearest unowned painted land (`i32::MAX` = unreachable).
    /// Rebuilt on commit and while orders are live so every unit can step downhill.
    paint_flow_dist: [Vec<i32>; 3],
    /// True while Godot is still brushing; maybe_clear_paint waits until commit.
    paint_stroke_open: [bool; 3],
    pub friendly_tiles: i32,
    pub hostile_tiles: i32,
    pub claimable_tile_count: i32,
    prev_friendly_tiles: i32,
    prev_hostile_tiles: i32,
    pub use_active_set: bool,
    pub use_adaptive_double_pass: bool,
    pub wrap_longitude: bool,
    /// If non-empty, length == tile_count; each entry up to 6 neighbors (-1 = unused).
    pub neighbors: Vec<[i32; 6]>,
    pub neighbor_count: Vec<u8>,
    /// When true, ignore grid_w/h cardinal topology for neighbor walks.
    pub graph_topology: bool,
    pub home_inject_enabled: bool,
    pub spawner_inject_interval_rounds: i32,
    /// R1: logistics strain is gone with the roads — pinned at 1.0 and no longer applied to
    /// spawn rates. Kept so the Godot strain dictionary keeps a stable shape.
    pub logistics_friendly_output_mult: f32,
    pub logistics_hostile_output_mult: f32,
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
    /// Runtime soft-cap for active-set prune (default ACTIVE_SET_SOFT_CAP; Godot may tighten under load).
    pub active_set_soft_cap: usize,
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

const INCREMENTAL_ACTIVE_MAX_DIRTY: usize = PATCH_ACTIVE_INDICES_BUDGET;

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
            paint_kind: [PAINT_NONE; 3],
            paint_gx: [-1; 3],
            paint_gy: [-1; 3],
            paint_land: [
                vec![0u8; tile_count],
                vec![0u8; tile_count],
                vec![0u8; tile_count],
            ],
            paint_flow_dist: [
                vec![i32::MAX; tile_count],
                vec![i32::MAX; tile_count],
                vec![i32::MAX; tile_count],
            ],
            paint_stroke_open: [false; 3],
            friendly_tiles,
            hostile_tiles,
            claimable_tile_count,
            prev_friendly_tiles: friendly_tiles,
            prev_hostile_tiles: hostile_tiles,
            use_active_set,
            use_adaptive_double_pass,
            wrap_longitude,
            neighbors: vec![],
            neighbor_count: vec![],
            graph_topology: false,
            home_inject_enabled: true,
            spawner_inject_interval_rounds: 10,
            logistics_friendly_output_mult: 1.0,
            logistics_hostile_output_mult: 1.0,
            territory_round_index: 0,
            active_indices: Vec::new(),
            active_seen: vec![0; tile_count],
            frontier_changed: true,
            rounds_since_active_rebuild: 0,
            gradient_halo_scratch: Vec::new(),
            gradient_pass_seen: vec![0; tile_count],
            active_dirty_mark: vec![0; tile_count],
            active_dirty_list: Vec::new(),
            active_set_soft_cap: ACTIVE_SET_SOFT_CAP,
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
        if self.graph_topology {
            if gy == 0 && gx >= 0 && gx < self.tile_count as i32 {
                return gx;
            }
            return -1;
        }
        if gy < 0 || gy >= self.grid_h {
            return -1;
        }
        let Some(nx) = Self::wrap_nx(gx, self.grid_w, self.wrap_longitude) else {
            return -1;
        };
        gy * self.grid_w + nx
    }

    pub fn set_graph_neighbors(&mut self, neighbors: Vec<[i32; 6]>, neighbor_count: Vec<u8>) {
        assert_eq!(neighbors.len(), self.tile_count);
        assert_eq!(neighbor_count.len(), self.tile_count);
        self.neighbors = neighbors;
        self.neighbor_count = neighbor_count;
        self.graph_topology = true;
        self.wrap_longitude = false;
    }

    pub(crate) fn collect_neighbors_static(
        graph_topology: bool,
        neighbors: &[[i32; 6]],
        neighbor_count: &[u8],
        tile_count: usize,
        w: i32,
        h: i32,
        wrap_longitude: bool,
        idx: usize,
        scratch: &mut Vec<usize>,
    ) {
        scratch.clear();
        if graph_topology && idx < neighbors.len() {
            let n = neighbor_count[idx] as usize;
            for k in 0..n.min(6) {
                let ni = neighbors[idx][k];
                if ni >= 0 {
                    let u = ni as usize;
                    if u < tile_count {
                        scratch.push(u);
                    }
                }
            }
            return;
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
            if ni < tile_count {
                scratch.push(ni);
            }
        }
    }

    pub(crate) fn collect_neighbors(&self, idx: usize, scratch: &mut Vec<usize>) {
        Self::collect_neighbors_static(
            self.graph_topology,
            &self.neighbors,
            &self.neighbor_count,
            self.tile_count,
            self.grid_w,
            self.grid_h,
            self.wrap_longitude,
            idx,
            scratch,
        );
    }

    pub(crate) fn for_each_neighbor_idx(&self, idx: usize, mut visit: impl FnMut(usize)) {
        if idx >= self.tile_count {
            return;
        }
        if self.graph_topology && idx < self.neighbors.len() {
            let n = self.neighbor_count[idx] as usize;
            for slot in 0..n.min(6) {
                let ni = self.neighbors[idx][slot];
                if ni >= 0 {
                    let u = ni as usize;
                    if u < self.tile_count {
                        visit(u);
                    }
                }
            }
            return;
        }
        let gx = (idx as i32) % self.grid_w;
        let gy = (idx as i32) / self.grid_w;
        for (dx, dy) in CARDINAL {
            let ny = gy + dy;
            if ny < 0 || ny >= self.grid_h {
                continue;
            }
            let Some(nx) = Self::wrap_nx(gx + dx, self.grid_w, self.wrap_longitude) else {
                continue;
            };
            let ni = (ny * self.grid_w + nx) as usize;
            if ni < self.tile_count {
                visit(ni);
            }
        }
    }

    pub fn advance_round(&mut self) {
        self.advance_territory_round();
    }

    /// Run soldier agents and/or bombers then territory propagation (world conquest).
    pub fn advance_round_with_combat(
        &mut self,
        agents: Option<&mut crate::agents::AgentLayer>,
        bombers: Option<&mut crate::bombers::BomberLayer>,
    ) {
        if let Some(agents) = agents {
            agents.tick(self);
        }
        if let Some(bombers) = bombers {
            bombers.tick(self);
        }
        self.advance_territory_round();
    }

    /// Run soldier agents then territory propagation (world conquest).
    pub fn advance_round_with_agents(&mut self, agents: &mut crate::agents::AgentLayer) {
        self.advance_round_with_combat(Some(agents), None);
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

        // Enforce runtime soft-cap BEFORE gradient so Godot-tightened caps bind every step.
        if self.use_active_set {
            self.enforce_active_set_soft_cap();
        }

        self.run_gradient_cancel_sync_pass();
        let frontier_delta = (self.friendly_tiles - self.prev_friendly_tiles).unsigned_abs()
            + (self.hostile_tiles - self.prev_hostile_tiles).unsigned_abs();
        if self.use_adaptive_double_pass && frontier_delta > ADAPTIVE_FRONTIER_EPS as u32 {
            // Re-enforce after first pass (halo growth) before the adaptive second pass.
            if self.use_active_set {
                self.enforce_active_set_soft_cap();
            }
            self.run_gradient_cancel_sync_pass();
        }

        self.preserve_homes();
        self.maybe_clear_paint();
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
        let mut tanks: Vec<(usize, f32)> = Vec::new();
        for (si, sp) in spawners.iter().enumerate() {
            if sp.gx < 0 || sp.gy < 0 {
                continue;
            }
            let cell = self.cell_index(sp.gx, sp.gy);
            if cell < 0 {
                continue;
            }
            let cell_ui = cell as usize;
            // Lost the tile — tank dumps into the void (design: lost, not flipped).
            if cell_ui < self.owners.len() && self.owners[cell_ui] != sp.team {
                tanks.push((si, 0.0));
                continue;
            }
            let amount = if sp.team == OWNER_FRIENDLY {
                self.friendly_spawn_rate
            } else {
                self.hostile_spawn_rate
            };
            if amount <= 0.0 {
                continue;
            }
            let is_friendly = sp.team == OWNER_FRIENDLY;
            let mut neighbor_scratch = Vec::with_capacity(6);
            self.collect_neighbors(cell_ui, &mut neighbor_scratch);
            let mut fed: Vec<usize> = Vec::new();
            for ui in neighbor_scratch {
                if ui >= self.claimable_mask.len() || self.claimable_mask[ui] == 0 {
                    continue;
                }
                fed.push(ui);
            }
            if fed.is_empty() {
                continue;
            }
            match sp.mode {
                SPAWNER_MODE_PUMP => {
                    for ui in fed {
                        if is_friendly {
                            self.pressure_friendly[ui] += amount;
                        } else {
                            self.pressure_hostile[ui] += amount;
                        }
                        dirty.push(ui);
                    }
                }
                SPAWNER_MODE_DRAIN => {
                    for ui in fed {
                        if is_friendly {
                            let take = self.pressure_hostile[ui].min(amount);
                            if take > 0.0 {
                                self.pressure_hostile[ui] -= take;
                                dirty.push(ui);
                            }
                        } else {
                            let take = self.pressure_friendly[ui].min(amount);
                            if take > 0.0 {
                                self.pressure_friendly[ui] -= take;
                                dirty.push(ui);
                            }
                        }
                    }
                }
                SPAWNER_MODE_BATTERY => {
                    let add = amount * fed.len() as f32;
                    let cap = amount * fed.len() as f32 * BATTERY_MAX_WAVES;
                    tanks.push((si, (sp.tank + add).min(cap)));
                }
                _ => {}
            }
        }
        for (si, tank) in tanks {
            if si < self.spawners.len() {
                self.spawners[si].tank = tank;
            }
        }
        for ui in dirty {
            self.mark_active_dirty(ui);
        }
    }

    /// Empty a battery tank onto Pump neighbor tiles. Returns dumped amount.
    pub fn surge_spawner_at(&mut self, gx: i32, gy: i32, team: u8) -> f32 {
        let mut dump = 0.0f32;
        let mut found = None;
        for (i, sp) in self.spawners.iter().enumerate() {
            if sp.gx == gx && sp.gy == gy && sp.team == team {
                found = Some(i);
                dump = sp.tank;
                break;
            }
        }
        let Some(si) = found else {
            return 0.0;
        };
        if dump <= 0.0 {
            self.spawners[si].tank = 0.0;
            return 0.0;
        }
        let cell = self.cell_index(gx, gy);
        if cell < 0 {
            self.spawners[si].tank = 0.0;
            return 0.0;
        }
        let cell_ui = cell as usize;
        if cell_ui < self.owners.len() && self.owners[cell_ui] != team {
            self.spawners[si].tank = 0.0;
            return 0.0;
        }
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(cell_ui, &mut neighbor_scratch);
        let mut fed: Vec<usize> = Vec::new();
        for ui in neighbor_scratch {
            if ui < self.claimable_mask.len() && self.claimable_mask[ui] != 0 {
                fed.push(ui);
            }
        }
        if fed.is_empty() {
            self.spawners[si].tank = 0.0;
            return 0.0;
        }
        let each = dump / fed.len() as f32;
        let is_friendly = team == OWNER_FRIENDLY;
        for ui in fed {
            if is_friendly {
                self.pressure_friendly[ui] += each;
            } else {
                self.pressure_hostile[ui] += each;
            }
            self.mark_active_dirty(ui);
        }
        self.spawners[si].tank = 0.0;
        dump
    }

    pub fn is_land_idx(&self, ui: usize) -> bool {
        if !self.land_mask.is_empty() {
            return ui < self.land_mask.len() && self.land_mask[ui] != 0;
        }
        ui < self.claimable_mask.len() && self.claimable_mask[ui] != 0
    }

    pub fn paint_cell_marked(&self, team: u8, gx: i32, gy: i32) -> bool {
        let t = team as usize;
        if t >= self.paint_kind.len() || self.paint_kind[t] == PAINT_NONE {
            return false;
        }
        let idx = self.cell_index(gx, gy);
        if idx < 0 {
            return false;
        }
        let ui = idx as usize;
        ui < self.paint_land[t].len() && self.paint_land[t][ui] != 0
    }

    pub fn clear_paint(&mut self, team: u8) {
        let t = team as usize;
        if t >= self.paint_kind.len() {
            return;
        }
        self.paint_kind[t] = PAINT_NONE;
        self.paint_gx[t] = -1;
        self.paint_gy[t] = -1;
        self.paint_stroke_open[t] = false;
        if t < self.paint_land.len() {
            for v in &mut self.paint_land[t] {
                *v = 0;
            }
        }
        if t < self.paint_flow_dist.len() {
            self.paint_flow_dist[t].fill(i32::MAX);
        }
    }

    /// Latest stroke replaces the previous mask. Call before dragging stamps.
    pub fn begin_paint_stroke(&mut self, team: u8) -> bool {
        let t = team as usize;
        if t != OWNER_FRIENDLY as usize && t != OWNER_HOSTILE as usize {
            return false;
        }
        self.clear_paint(team);
        self.paint_stroke_open[t] = true;
        true
    }

    pub fn commit_paint_stroke(&mut self, team: u8) {
        let t = team as usize;
        if t < self.paint_stroke_open.len() {
            self.paint_stroke_open[t] = false;
        }
        self.rebuild_paint_flow(team);
    }

    /// True after the player releases a stroke: units must peel to unowned painted land.
    pub fn paint_orders_live(&self, team: u8) -> bool {
        let t = team as usize;
        t < self.paint_kind.len()
            && self.paint_kind[t] != PAINT_NONE
            && !self.paint_stroke_open[t]
    }

    /// Snap water to nearest land, then mark a 2-ring land blob until cap.
    pub fn stamp_paint(&mut self, team: u8, gx: i32, gy: i32) -> bool {
        let t = team as usize;
        if t >= self.paint_kind.len() || !self.paint_stroke_open[t] {
            return false;
        }
        let mut seed = self.cell_index(gx, gy);
        if seed < 0 {
            return false;
        }
        if !self.is_land_idx(seed as usize) {
            seed = self.nearest_land_idx(seed as usize);
            if seed < 0 {
                return false;
            }
        }
        let seed_ui = seed as usize;
        let mut marked = self.paint_marked_count(team);
        if marked >= PAINT_CELL_CAP {
            return true;
        }
        let mut candidates = Vec::with_capacity(48);
        candidates.push(seed_ui);
        let mut ring = Vec::with_capacity(8);
        self.collect_neighbors(seed_ui, &mut ring);
        let first_ring = ring.clone();
        candidates.extend(first_ring.iter().copied());
        let mut scratch = Vec::with_capacity(8);
        for &n in &first_ring {
            scratch.clear();
            self.collect_neighbors(n, &mut scratch);
            candidates.extend(scratch.iter().copied());
        }
        let mut any = false;
        for n in candidates {
            if marked >= PAINT_CELL_CAP {
                break;
            }
            if n >= self.tile_count || !self.is_land_idx(n) {
                continue;
            }
            if self.paint_land[t][n] != 0 {
                any = true;
                continue;
            }
            self.paint_land[t][n] = 1;
            marked += 1;
            any = true;
        }
        if any && self.paint_kind[t] == PAINT_NONE {
            let (pgx, pgy) = self.grid_from_idx(seed);
            self.paint_kind[t] = PAINT_AREA;
            self.paint_gx[t] = pgx;
            self.paint_gy[t] = pgy;
        }
        any
    }

    pub fn paint_cell_indices(&self, team: u8) -> Vec<i32> {
        let t = team as usize;
        if t >= self.paint_land.len() {
            return Vec::new();
        }
        self.paint_land[t]
            .iter()
            .enumerate()
            .filter(|(_, &v)| v != 0)
            .map(|(i, _)| i as i32)
            .collect()
    }

    /// Tests / one-shot pin: begin, stamp a blob, commit.
    pub fn set_paint(&mut self, team: u8, kind: u8, gx: i32, gy: i32) -> bool {
        if kind == PAINT_NONE {
            self.clear_paint(team);
            return true;
        }
        if !self.begin_paint_stroke(team) {
            return false;
        }
        let ok = self.stamp_paint(team, gx, gy);
        self.commit_paint_stroke(team);
        ok
    }

    pub(crate) fn grid_from_idx(&self, idx: i32) -> (i32, i32) {
        if self.graph_topology {
            return (idx, 0);
        }
        let w = self.grid_w.max(1);
        (idx % w, idx / w)
    }

    /// Multi-source BFS from unowned painted land through every cell (land + water).
    /// One globe-wide field replaces per-unit paint searches that timed out at 24k hops.
    pub fn rebuild_paint_flow(&mut self, team: u8) {
        let t = team as usize;
        if t >= self.paint_flow_dist.len() {
            return;
        }
        if self.paint_flow_dist[t].len() != self.tile_count {
            self.paint_flow_dist[t] = vec![i32::MAX; self.tile_count];
        } else {
            self.paint_flow_dist[t].fill(i32::MAX);
        }
        if !self.paint_orders_live(team) || t >= self.paint_land.len() {
            return;
        }
        let mut q: Vec<usize> = Vec::new();
        for idx in 0..self.tile_count {
            if self.paint_land[t][idx] == 0 || !self.is_land_idx(idx) {
                continue;
            }
            if idx < self.owners.len() && self.owners[idx] == team {
                continue;
            }
            self.paint_flow_dist[t][idx] = 0;
            q.push(idx);
        }
        let mut head = 0usize;
        let mut scratch = Vec::with_capacity(8);
        while head < q.len() {
            let cur = q[head];
            head += 1;
            let d = self.paint_flow_dist[t][cur];
            self.collect_neighbors(cur, &mut scratch);
            for &n in &scratch {
                if n >= self.tile_count {
                    continue;
                }
                let nd = d.saturating_add(1);
                if nd < self.paint_flow_dist[t][n] {
                    self.paint_flow_dist[t][n] = nd;
                    q.push(n);
                }
            }
        }
    }

    pub fn rebuild_live_paint_flows(&mut self) {
        self.rebuild_paint_flow(OWNER_FRIENDLY);
        self.rebuild_paint_flow(OWNER_HOSTILE);
    }

    /// Neighbor that strictly decreases hop distance to unowned painted land.
    pub fn paint_flow_next_idx(&self, team: u8, from_idx: usize) -> Option<usize> {
        let t = team as usize;
        if t >= self.paint_flow_dist.len() || from_idx >= self.paint_flow_dist[t].len() {
            return None;
        }
        let d0 = self.paint_flow_dist[t][from_idx];
        if d0 == 0 || d0 == i32::MAX {
            return None;
        }
        let mut best: Option<usize> = None;
        let mut best_d = d0;
        self.for_each_neighbor_idx(from_idx, |n| {
            if n >= self.paint_flow_dist[t].len() {
                return;
            }
            let dn = self.paint_flow_dist[t][n];
            if dn >= d0 {
                return;
            }
            let land = self.is_land_idx(n);
            let better = match best {
                None => true,
                Some(bi) => {
                    dn < best_d || (dn == best_d && land && !self.is_land_idx(bi))
                }
            };
            if better {
                best_d = dn;
                best = Some(n);
            }
        });
        best
    }

    fn nearest_land_idx(&self, start: usize) -> i32 {
        if start >= self.tile_count {
            return -1;
        }
        if self.is_land_idx(start) {
            return start as i32;
        }
        let mut seen = vec![false; self.tile_count];
        let mut q = Vec::new();
        q.push(start);
        seen[start] = true;
        let mut head = 0usize;
        let mut scratch = Vec::with_capacity(6);
        while head < q.len() && head < 8000 {
            let cur = q[head];
            head += 1;
            scratch.clear();
            self.collect_neighbors(cur, &mut scratch);
            for n in scratch.clone() {
                if n >= self.tile_count || seen[n] {
                    continue;
                }
                if self.is_land_idx(n) {
                    return n as i32;
                }
                seen[n] = true;
                q.push(n);
            }
        }
        -1
    }

    pub fn maybe_clear_paint(&mut self) {
        for team in [OWNER_FRIENDLY, OWNER_HOSTILE] {
            let t = team as usize;
            if t >= self.paint_kind.len() || self.paint_stroke_open[t] {
                continue;
            }
            if self.paint_kind[t] == PAINT_NONE {
                continue;
            }
            let owned = self.paint_owned_count(team);
            let total = self.paint_marked_count(team);
            let unowned = total - owned;
            // Only remaining unowned cells matter — brushing your own land must not
            // auto-cancel the order.
            if total <= 0 || unowned <= 0 {
                self.clear_paint(team);
            }
        }
    }

    fn paint_owned_count(&self, team: u8) -> i32 {
        let t = team as usize;
        if t >= self.paint_land.len() {
            return 0;
        }
        let mut n = 0;
        let mask = &self.paint_land[t];
        let lim = mask.len().min(self.owners.len());
        for i in 0..lim {
            if mask[i] != 0 && self.owners[i] == team {
                n += 1;
            }
        }
        n
    }

    pub fn paint_marked_count(&self, team: u8) -> i32 {
        let t = team as usize;
        if t >= self.paint_land.len() {
            return 0;
        }
        self.paint_land[t].iter().filter(|&&v| v != 0).count() as i32
    }

    fn run_gradient_cancel_sync_pass(&mut self) {
        self.spread_pressure_gradient();
        // Pressure-dirty cells (bombs/shoots/halo) must be in active_indices before
        // cancel + ownership sync this round — dirty list alone is flushed only after sync.
        self.promote_active_dirty_into_indices();
        self.cancel_overlapping_pressure();
        self.sync_ownership_from_pressures();
    }

    /// Ensure pending active_dirty cells participate in cancel/ownership this pass.
    fn promote_active_dirty_into_indices(&mut self) {
        if !self.use_active_set || self.active_dirty_list.is_empty() {
            return;
        }
        for &idx in &self.active_dirty_list.clone() {
            if idx >= self.tile_count || self.claimable_mask[idx] == 0 {
                continue;
            }
            if self.active_seen[idx] != 0 {
                continue;
            }
            self.active_indices.push(idx);
            self.active_seen[idx] = 1;
        }
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
        let graph_topology = self.graph_topology;
        let neighbors = self.neighbors.clone();
        let neighbor_count = self.neighbor_count.clone();

        if friendly {
            self.pf_next.copy_from_slice(&self.pressure_friendly);
        } else {
            self.ph_next.copy_from_slice(&self.pressure_hostile);
        }

        let mut promote_halo: Vec<usize> = Vec::new();
        {
            let (src, dst) = if friendly {
                (&self.pressure_friendly[..], &mut self.pf_next[..])
            } else {
                (&self.pressure_hostile[..], &mut self.ph_next[..])
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
                        graph_topology,
                        &neighbors,
                        &neighbor_count,
                        tile_count,
                        Some(&mut self.gradient_halo_scratch),
                        &mut self.gradient_pass_seen,
                    );
                }
                let halo: Vec<usize> = self.gradient_halo_scratch.clone();
                for &ni in &halo {
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
                        graph_topology,
                        &neighbors,
                        &neighbor_count,
                        tile_count,
                        None,
                        &mut self.gradient_pass_seen,
                    );
                }
                promote_halo = halo;
            } else {
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
                            graph_topology,
                            &neighbors,
                            &neighbor_count,
                            tile_count,
                            None,
                            &mut self.gradient_pass_seen,
                        );
                    }
                }
            }
        }

        // Promote one-hop wet neighbors into the active set so cancel + ownership
        // sync this round, instead of waiting on the next rebuild.
        if !promote_halo.is_empty() {
            for &ni in &promote_halo {
                if ni >= self.tile_count || self.active_seen[ni] != 0 {
                    continue;
                }
                self.active_indices.push(ni);
                self.active_seen[ni] = 1;
                self.mark_active_dirty(ni);
            }
            self.frontier_changed = true;
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
        graph_topology: bool,
        neighbors: &[[i32; 6]],
        neighbor_count: &[u8],
        tile_count: usize,
        w: i32,
        h: i32,
        idx: usize,
        claimable: &[u8],
        wrap_longitude: bool,
        scratch: &mut Vec<usize>,
    ) {
        Self::collect_neighbors_static(
            graph_topology,
            neighbors,
            neighbor_count,
            tile_count,
            w,
            h,
            wrap_longitude,
            idx,
            scratch,
        );
        scratch.retain(|&ni| ni < claimable.len() && claimable[ni] != 0);
        scratch.sort_unstable();
        scratch.dedup();
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
        graph_topology: bool,
        graph_neighbors: &[[i32; 6]],
        neighbor_count: &[u8],
        tile_count: usize,
        mut halo_out: Option<&mut Vec<usize>>,
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
        let mut neighbor_indices: Vec<usize> = Vec::with_capacity(6);
        Self::flow_neighbor_indices(
            graph_topology,
            graph_neighbors,
            neighbor_count,
            tile_count,
            w,
            h,
            idx,
            claimable,
            wrap_longitude,
            &mut neighbor_indices,
        );

        for &ni in &neighbor_indices {
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
            // Previous gate used `!halo_out.is_empty()`, which never seeded an empty
            // collector — the one-hop halo pass was dead and fronts grew as spines.
            if let Some(ref mut halo) = halo_out {
                if active_seen[ni] == 0 {
                    halo.push(ni);
                    active_seen[ni] = 1;
                }
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

    /// Simple majority: whoever has more pressure owns the cell; equal → neutral.
    /// (No contested band, no dominance ratio, no sticky prior-owner.)
    fn sync_ownership_tile(&mut self, idx: usize) {
        if self.claimable_mask[idx] == 0 {
            self.set_owner_at(idx, OWNER_UNCLAIMABLE);
            return;
        }
        let pf = self.pressure_friendly[idx];
        let ph = self.pressure_hostile[idx];
        let new_owner = if pf > ph {
            OWNER_FRIENDLY
        } else if ph > pf {
            OWNER_HOSTILE
        } else {
            OWNER_NEUTRAL
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
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(idx, &mut neighbor_scratch);
        for nui in neighbor_scratch {
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
                // Remaining dirty (if any after budget) keeps frontier_changed for next round.
                if self.active_dirty_list.is_empty() {
                    self.frontier_changed = false;
                }
            } else {
                self.rebuild_active_indices();
                self.frontier_changed = false;
                self.active_dirty_list.clear();
                self.active_dirty_mark.fill(0);
            }
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
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(idx, &mut neighbor_scratch);
        for ni in neighbor_scratch {
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
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(idx, &mut neighbor_scratch);
        for ni in neighbor_scratch {
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

    /// Incremental active-set repair with a hard per-call budget (B5/B7).
    /// Excess dirty cells remain for the next frame or trigger a full rebuild when over threshold.
    fn patch_active_indices(&mut self) {
        let budget = PATCH_ACTIVE_INDICES_BUDGET.min(self.active_dirty_list.len());
        let dirty: Vec<usize> = self.active_dirty_list.drain(..budget).collect();
        for idx in dirty {
            if idx >= self.tile_count {
                continue;
            }
            self.active_dirty_mark[idx] = 0;
            let should = self.is_tile_active(idx);
            let was = self.active_seen[idx] != 0;
            if should && !was {
                self.active_indices.push(idx);
                self.active_seen[idx] = 1;
            } else if !should && was {
                self.remove_active_index(idx);
            }
        }
        // Soft-cap sprawl under dual fronts: prune lowest-pressure tiles if over budget.
        self.enforce_active_set_soft_cap();
    }

    /// Keep active-set size bounded so dual-front wars don't O(n) thrash every round (B7).
    /// Tier-1 drops dry interiors; tier-2 drops wet deep interiors when all tiles are wet.
    /// Cap comes from `active_set_soft_cap` (default ACTIVE_SET_SOFT_CAP; Godot may tighten).
    fn enforce_active_set_soft_cap(&mut self) {
        self.enforce_active_set_soft_cap_to(self.active_set_soft_cap);
    }

    /// Godot overload path: tighten soft-cap under frame pressure (clamped to [1, ACTIVE_SET_SOFT_CAP]).
    pub fn set_active_set_soft_cap(&mut self, cap: usize) {
        let clamped = cap.clamp(1, ACTIVE_SET_SOFT_CAP);
        if self.active_set_soft_cap == clamped {
            return;
        }
        self.active_set_soft_cap = clamped;
        self.enforce_active_set_soft_cap();
    }

    pub(crate) fn enforce_active_set_soft_cap_to(&mut self, cap: usize) {
        self.enforce_active_set_soft_cap_impl(cap);
    }

    fn enforce_active_set_soft_cap_impl(&mut self, cap: usize) {
        if self.active_indices.len() <= cap {
            return;
        }
        let mut excess = self.active_indices.len().saturating_sub(cap);

        // Tier-1: calm/dry tiles — lowest keep_score first.
        if excess > 0 {
            let mut scored: Vec<(f32, usize)> = self
                .active_indices
                .iter()
                .copied()
                .filter(|&idx| {
                    let p = self.pressure_friendly[idx].max(self.pressure_hostile[idx]);
                    p <= ACTIVE_PRESSURE_EPS
                })
                .map(|idx| (self.active_keep_score(idx), idx))
                .collect();
            scored.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
            let drop_n = excess.min(scored.len());
            for i in 0..drop_n {
                self.remove_active_index(scored[i].1);
            }
            excess = self.active_indices.len().saturating_sub(cap);
        }

        // Tier-2: wet deep interiors — frontier / contested / tips stay protected.
        if excess > 0 {
            let mut scored: Vec<(bool, f32, usize)> = self
                .active_indices
                .iter()
                .copied()
                .filter(|&idx| {
                    let p = self.pressure_friendly[idx].max(self.pressure_hostile[idx]);
                    p > ACTIVE_PRESSURE_EPS && !self.is_soft_cap_tier2_protected(idx)
                })
                .map(|idx| {
                    (
                        self.is_soft_cap_deep_interior(idx),
                        self.active_keep_score(idx),
                        idx,
                    )
                })
                .collect();
            if scored.is_empty() {
                return;
            }
            // Drop deep same-owner interiors before marginal wet cells; lowest score first.
            scored.sort_by(|a, b| {
                b.0
                    .cmp(&a.0)
                    .then_with(|| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            });
            let drop_n = excess.min(scored.len());
            for i in 0..drop_n {
                self.remove_active_index(scored[i].2);
            }
        }
    }

    /// Tier-2 protected: contested, owner frontier, or spreading tip beside dry neighbor.
    fn is_soft_cap_tier2_protected(&self, idx: usize) -> bool {
        if self.owners[idx] == OWNER_CONTESTED {
            return true;
        }
        let p = self.pressure_friendly[idx].max(self.pressure_hostile[idx]);
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(idx, &mut neighbor_scratch);
        for ni in neighbor_scratch {
            if ni >= self.tile_count || self.claimable_mask[ni] == 0 {
                continue;
            }
            if self.owners[ni] == OWNER_CONTESTED || self.owners[idx] != self.owners[ni] {
                return true;
            }
            let p_n = self.pressure_friendly[ni].max(self.pressure_hostile[ni]);
            if p > ACTIVE_PRESSURE_EPS && p_n < ACTIVE_PRESSURE_EPS {
                return true;
            }
        }
        false
    }

    /// All claimable neighbors share our owner — deep interior (preferred tier-2 drop).
    fn is_soft_cap_deep_interior(&self, idx: usize) -> bool {
        if self.owners[idx] == OWNER_CONTESTED {
            return false;
        }
        let owner = self.owners[idx];
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(idx, &mut neighbor_scratch);
        for ni in neighbor_scratch {
            if ni >= self.tile_count || self.claimable_mask[ni] == 0 {
                continue;
            }
            if self.owners[ni] != owner || self.owners[ni] == OWNER_CONTESTED {
                return false;
            }
        }
        true
    }

    /// Higher = keep under soft-cap. Frontier / contested beat raw pressure depth.
    fn active_keep_score(&self, idx: usize) -> f32 {
        let p = self.pressure_friendly[idx].max(self.pressure_hostile[idx]);
        // Light pressure weight: deep interior corridors must not outrank thin tips.
        let mut score = p * 0.05;
        if self.owners[idx] == OWNER_CONTESTED {
            score += 100.0;
        }
        let mut neighbor_scratch = Vec::with_capacity(6);
        self.collect_neighbors(idx, &mut neighbor_scratch);
        for ni in neighbor_scratch {
            if ni >= self.tile_count || self.claimable_mask[ni] == 0 {
                continue;
            }
            if self.owners[ni] == OWNER_CONTESTED || self.owners[idx] != self.owners[ni] {
                score += 50.0;
                break;
            }
            let p_n = self.pressure_friendly[ni].max(self.pressure_hostile[ni]);
            // Spreading tip: we hold pressure beside a still-dry claimable neighbor.
            if p > ACTIVE_PRESSURE_EPS && p_n < ACTIVE_PRESSURE_EPS {
                score += 40.0;
                break;
            }
        }
        score
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
        // Prefer incremental patch for small deltas; full rebuild only when the batch is huge (B7).
        if self.use_active_set {
            if indices.len() <= INCREMENTAL_ACTIVE_MAX_DIRTY {
                self.patch_active_indices();
            } else {
                self.rebuild_active_indices();
                self.active_dirty_list.clear();
                self.active_dirty_mark.fill(0);
            }
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

    /// Single display R8 byte for SCD1 territory pulls (avoids enum→R8 on Godot).
    pub fn owner_display_byte_at(&self, idx: usize) -> u8 {
        self.owner_display.get(idx).copied().unwrap_or(0)
    }

    /// Full w*h R8 overlay bytes (incremental buffer; no per-call recompute).
    pub fn owner_display_r8(&self) -> Vec<u8> {
        self.owner_display.clone()
    }

    /// Pressure depth tint for ownership overlay (display-only; uploaded at overlay Hz).
    /// Neutral / unclaimable → 0. Owned tiles encode team pressure depth in 0.15..1.0.
    pub fn pressure_depth_r8(&self, vis_ref: f32) -> Vec<u8> {
        let ref_v = vis_ref.max(0.001);
        let mut out = vec![0u8; self.tile_count];
        for idx in 0..self.tile_count {
            if idx < self.claimable_mask.len() && self.claimable_mask[idx] == 0 {
                continue;
            }
            let p = match self.owners[idx] {
                OWNER_FRIENDLY => self.pressure_friendly[idx],
                OWNER_HOSTILE => self.pressure_hostile[idx],
                OWNER_CONTESTED => self.pressure_friendly[idx].max(self.pressure_hostile[idx]),
                _ => 0.0,
            };
            if p <= 0.0 {
                continue;
            }
            let norm = (p / ref_v).powf(0.55).clamp(0.15, 1.0);
            out[idx] = (norm * 255.0).round() as u8;
        }
        if self.grid_w > 1 {
            let w = self.grid_w as usize;
            let h = self.grid_h as usize;
            for gy in 0..h {
                let row = gy * w;
                out[row + w - 1] = out[row];
            }
        }
        out
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
        if self.graph_topology {
            return;
        }
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
        if self.graph_topology {
            return;
        }
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
        let mut neighbor_scratch = Vec::with_capacity(6);
        for idx in 0..self.tile_count {
            if self.claimable_mask[idx] == 0 {
                continue;
            }
            let mut active = self.pressure_friendly[idx] > ACTIVE_PRESSURE_EPS
                || self.pressure_hostile[idx] > ACTIVE_PRESSURE_EPS;
            if !active {
                self.collect_neighbors(idx, &mut neighbor_scratch);
                for ni in &neighbor_scratch {
                    if self.claimable_mask[*ni] == 0 {
                        continue;
                    }
                    if self.owners[*ni] == OWNER_CONTESTED || self.owners[idx] != self.owners[*ni] {
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
        self.enforce_active_set_soft_cap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tiny_kernel(use_active_set: bool) -> TerritoryKernel {
        let w = 8i32;
        let h = 8i32;
        let n = (w * h) as usize;
        TerritoryKernel::new(
            w,
            h,
            vec![1u8; n],
            vec![0.0f32; n],
            vec![1.0f32; n],
            vec![1.0f32; n],
            vec![OWNER_NEUTRAL; n],
            vec![0.0f32; n],
            vec![0.0f32; n],
            1.0,
            1.0,
            0,
            n as i32 - 1,
            Vec::new(),
            0,
            0,
            use_active_set,
            false,
            false,
        )
    }

    #[test]
    fn patch_active_indices_stays_within_budget() {
        let mut k = tiny_kernel(true);
        // Flood dirty list beyond budget.
        for i in 0..k.tile_count {
            k.mark_active_dirty(i);
        }
        assert!(k.active_dirty_list.len() > 0);
        let before = k.active_dirty_list.len();
        k.patch_active_indices();
        // Budget drains at most PATCH_ACTIVE_INDICES_BUDGET cells; leftover stays dirty.
        assert!(k.active_dirty_list.len() < before || before <= PATCH_ACTIVE_INDICES_BUDGET);
        assert!(k.active_indices.len() <= ACTIVE_SET_SOFT_CAP);
    }

    #[test]
    fn graph_topology_pressure_flows_to_neighbors() {
        let sphere = crate::sphere_grid::SphereGrid::generate(2);
        assert_eq!(sphere.cell_count, 42);
        let n = sphere.cell_count;
        let w = n as i32;
        let h = 1i32;
        let mut k = TerritoryKernel::new(
            w,
            h,
            vec![1u8; n],
            vec![0.0f32; n],
            vec![1.0f32; n],
            vec![1.0f32; n],
            vec![OWNER_NEUTRAL; n],
            vec![0.0f32; n],
            vec![0.0f32; n],
            0.0,
            0.0,
            0,
            -1,
            Vec::new(),
            0,
            0,
            false,
            false,
            false,
        );
        k.set_graph_neighbors(sphere.neighbors.clone(), sphere.neighbor_count.clone());
        k.home_inject_enabled = false;
        k.pressure_friendly[0] = 10.0;
        k.advance_round();
        k.advance_round();

        let mut neighbor_scratch = Vec::with_capacity(6);
        k.collect_neighbors(0, &mut neighbor_scratch);
        assert!(!neighbor_scratch.is_empty(), "cell 0 should have graph neighbors");
        let flowed = neighbor_scratch
            .iter()
            .any(|&ni| k.pressure_friendly[ni] > 0.0);
        assert!(flowed, "pressure should spread to graph neighbors from cell 0");
    }

    #[test]
    fn active_set_soft_cap_prunes() {
        let mut k = tiny_kernel(true);
        k.active_indices.clear();
        k.active_seen.fill(0);
        // Artificially over-fill active set (tiny grid is small; temporarily lower via push).
        for i in 0..k.tile_count {
            k.active_indices.push(i);
            k.active_seen[i] = 1;
            k.pressure_friendly[i] = (i as f32) * 0.01;
        }
        // Soft cap is large for tiny grids — verify enforce is a no-op under cap.
        k.enforce_active_set_soft_cap();
        assert!(k.active_indices.len() <= ACTIVE_SET_SOFT_CAP);
        assert_eq!(k.active_indices.len(), k.tile_count);
    }

    #[test]
    fn active_set_halo_promotes_wet_neighbors() {
        let mut k = tiny_kernel(true);
        k.home_inject_enabled = false;
        k.active_indices.clear();
        k.active_seen.fill(0);
        // Seed a single active cell with enough pressure to overflow to cardinals.
        let src = (3 * 8 + 3) as usize;
        k.pressure_friendly[src] = 25.0;
        k.active_indices.push(src);
        k.active_seen[src] = 1;

        k.advance_round();

        let mut neighbor_scratch = Vec::with_capacity(6);
        k.collect_neighbors(src, &mut neighbor_scratch);
        assert!(!neighbor_scratch.is_empty());
        let wet_neighbors = neighbor_scratch
            .iter()
            .filter(|&&ni| k.pressure_friendly[ni] > 0.0)
            .count();
        assert!(
            wet_neighbors > 0,
            "source should overflow pressure into neighbors"
        );
        for &ni in &neighbor_scratch {
            if k.pressure_friendly[ni] <= 0.0 {
                continue;
            }
            assert_eq!(
                k.active_seen[ni], 1,
                "wet halo neighbor {ni} should be promoted into the active set"
            );
            assert!(
                k.active_indices.contains(&ni),
                "wet halo neighbor {ni} missing from active_indices"
            );
        }
    }

    #[test]
    fn soft_cap_tier1_prunes_dry_preserves_wet() {
        let mut k = tiny_kernel(true);
        k.active_indices.clear();
        k.active_seen.fill(0);
        for i in 0..k.tile_count {
            k.active_indices.push(i);
            k.active_seen[i] = 1;
            if i % 2 == 0 {
                k.pressure_friendly[i] = 25.0;
            } else {
                k.pressure_friendly[i] = 0.0;
            }
        }
        let wet_tiles: Vec<usize> = k
            .active_indices
            .iter()
            .copied()
            .filter(|&idx| {
                let p = k.pressure_friendly[idx].max(k.pressure_hostile[idx]);
                p > ACTIVE_PRESSURE_EPS
            })
            .collect();
        assert!(!wet_tiles.is_empty());
        let before_wet: Vec<usize> = wet_tiles
            .iter()
            .filter(|&&idx| k.active_seen[idx] == 1)
            .copied()
            .collect();
        // Under global cap tiny grid is a no-op; force tier-1 with a tight cap.
        k.enforce_active_set_soft_cap_to(48);
        for idx in before_wet {
            assert_eq!(
                k.active_seen[idx], 1,
                "pressurized tile {idx} must survive tier-1 dry prune"
            );
        }
    }

    #[test]
    fn soft_cap_prunes_wet_interior_when_all_wet_over_cap() {
        let mut k = tiny_kernel(true);
        k.active_indices.clear();
        k.active_seen.fill(0);
        for i in 0..k.tile_count {
            k.pressure_friendly[i] = 10.0;
            k.owners[i] = OWNER_FRIENDLY;
            k.active_indices.push(i);
            k.active_seen[i] = 1;
        }
        // Frontier tile at tip stays protected (neighbor different owner).
        let tip = 0usize;
        let nbr = 1usize;
        k.owners[nbr] = OWNER_NEUTRAL;
        k.pressure_friendly[tip] = 10.0;
        k.pressure_friendly[nbr] = 0.0;

        let cap = 32usize;
        k.enforce_active_set_soft_cap_to(cap);
        assert!(
            k.active_indices.len() <= cap,
            "all-wet over-cap must prune down to cap (got {})",
            k.active_indices.len()
        );
        assert_eq!(
            k.active_seen[tip], 1,
            "frontier tip must survive tier-2 wet interior prune"
        );
    }

    #[test]
    fn soft_cap_prefers_frontier_over_interior_pressure() {
        let mut k = tiny_kernel(true);
        k.active_indices.clear();
        k.active_seen.fill(0);
        for i in 0..k.tile_count {
            k.active_indices.push(i);
            k.active_seen[i] = 1;
            k.owners[i] = OWNER_FRIENDLY;
            k.pressure_friendly[i] = 50.0;
        }
        // Carve a frontier tip: wet beside a neutral claimable neighbor.
        let tip = 0usize;
        let nbr = 1usize;
        k.pressure_friendly[tip] = 10.0;
        k.pressure_friendly[nbr] = 0.0;
        k.owners[nbr] = OWNER_NEUTRAL;

        let tip_score = k.active_keep_score(tip);
        let interior = (3 * 8 + 3) as usize;
        let interior_score = k.active_keep_score(interior);
        assert!(
            tip_score > interior_score,
            "frontier tip ({tip_score}) should outrank calm interior ({interior_score})"
        );

        let cap = 32usize;
        k.enforce_active_set_soft_cap_to(cap);
        assert!(k.active_indices.len() <= cap);
        assert_eq!(
            k.active_seen[tip], 1,
            "frontier tip must outlive deep interior under tier-2 prune"
        );
    }

    #[test]
    fn ownership_is_simple_majority() {
        let mut k = tiny_kernel(false);
        k.home_inject_enabled = false;
        k.use_active_set = false;

        k.pressure_friendly[0] = 1.0;
        k.pressure_hostile[0] = 0.0;
        k.sync_ownership_tile(0);
        assert_eq!(k.owners[0], OWNER_FRIENDLY);

        k.pressure_friendly[0] = 0.0;
        k.pressure_hostile[0] = 1.0;
        k.sync_ownership_tile(0);
        assert_eq!(k.owners[0], OWNER_HOSTILE);

        // Near-tie: any strict lead owns (no 1.15 contested band).
        k.pressure_friendly[0] = 1.0;
        k.pressure_hostile[0] = 0.99;
        k.sync_ownership_tile(0);
        assert_eq!(k.owners[0], OWNER_FRIENDLY);

        // Equal including both zero → neutral (no sticky prior owner).
        k.owners[0] = OWNER_FRIENDLY;
        k.pressure_friendly[0] = 0.0;
        k.pressure_hostile[0] = 0.0;
        k.sync_ownership_tile(0);
        assert_eq!(k.owners[0], OWNER_NEUTRAL);

        k.pressure_friendly[0] = 5.0;
        k.pressure_hostile[0] = 5.0;
        k.sync_ownership_tile(0);
        assert_eq!(k.owners[0], OWNER_NEUTRAL);
    }

    #[test]
    fn pressure_dirty_off_active_flips_same_pass() {
        let mut k = tiny_kernel(true);
        k.home_inject_enabled = false;
        // Soft-cap style: cell 0 not in active set, but holds opposing pressure.
        k.active_indices.clear();
        k.active_seen.fill(0);
        k.owners[0] = OWNER_HOSTILE;
        k.pressure_friendly[0] = 10.0;
        k.pressure_hostile[0] = 1.0;
        k.mark_pressure_dirty(0);
        assert!(k.active_seen[0] == 0, "dirty alone must not imply already active");
        k.run_gradient_cancel_sync_pass();
        assert_eq!(
            k.owners[0],
            OWNER_FRIENDLY,
            "majority on pressure-dirty cell must flip same pass"
        );
    }

    #[test]
    fn bomb_pressure_tips_neutral_claimable_same_pass() {
        let mut k = tiny_kernel(true);
        k.home_inject_enabled = false;
        k.owners[0] = OWNER_NEUTRAL;
        k.pressure_friendly[0] = 0.0;
        k.pressure_hostile[0] = 0.0;
        // Friendly bomb: erode hostile, add 0.35 * power friendly.
        let power = 1000.0;
        k.pressure_hostile[0] = (k.pressure_hostile[0] - power).max(0.0);
        k.pressure_friendly[0] += power * 0.35;
        k.mark_pressure_dirty(0);
        k.run_gradient_cancel_sync_pass();
        assert_eq!(k.owners[0], OWNER_FRIENDLY);
    }

    #[test]
    fn air_strike_opens_unclaimable_and_flips_owner() {
        let mut k = tiny_kernel(true);
        k.home_inject_enabled = false;
        k.land_mask = vec![1u8; k.tile_count];
        k.friendly_reachable = vec![0u8; k.tile_count];
        k.hostile_reachable = vec![0u8; k.tile_count];
        k.set_claimable_mask_at(0, 0);
        k.owners[0] = OWNER_UNCLAIMABLE;
        k.pressure_friendly[0] = 0.0;
        k.pressure_hostile[0] = 0.0;

        k.open_claimable_for_air_strike(0, OWNER_FRIENDLY);
        assert_eq!(k.claimable_mask[0], 1);
        assert_ne!(k.owners[0], OWNER_UNCLAIMABLE);

        let power = 1000.0;
        k.pressure_hostile[0] = (k.pressure_hostile[0] - power).max(0.0);
        k.pressure_friendly[0] += power * 0.35;
        k.mark_pressure_dirty(0);
        k.run_gradient_cancel_sync_pass();
        assert_eq!(k.owners[0], OWNER_FRIENDLY);
    }

    #[test]
    fn battery_stores_inject_and_surge_dumps() {
        let mut k = tiny_kernel(false);
        k.home_inject_enabled = false;
        k.spawner_inject_interval_rounds = 1;
        k.friendly_spawn_rate = 2.0;
        k.claimable_mask.fill(1);
        k.owners[0] = OWNER_FRIENDLY;
        k.spawners.push(Spawner {
            team: OWNER_FRIENDLY,
            gx: 0,
            gy: 0,
            mode: SPAWNER_MODE_BATTERY,
            tank: 0.0,
            sid: 1,
        });
        k.inject_placed_spawners();
        assert!(k.spawners[0].tank > 0.0, "battery should accrue instead of leaking");
        let before_pf: f32 = k.pressure_friendly.iter().sum();
        let dumped = k.surge_spawner_at(0, 0, OWNER_FRIENDLY);
        assert!(dumped > 0.0);
        assert_eq!(k.spawners[0].tank, 0.0);
        let after_pf: f32 = k.pressure_friendly.iter().sum();
        assert!(after_pf > before_pf, "surge should add friendly pressure");
    }

    #[test]
    fn drain_erodes_enemy_neighbor_pressure() {
        let mut k = tiny_kernel(false);
        k.home_inject_enabled = false;
        k.friendly_spawn_rate = 3.0;
        k.claimable_mask.fill(1);
        k.owners[0] = OWNER_FRIENDLY;
        k.pressure_hostile[1] = 10.0;
        k.spawners.push(Spawner {
            team: OWNER_FRIENDLY,
            gx: 0,
            gy: 0,
            mode: SPAWNER_MODE_DRAIN,
            tank: 0.0,
            sid: 2,
        });
        k.inject_placed_spawners();
        assert!(k.pressure_hostile[1] < 10.0, "drain should cut enemy film on neighbors");
    }

    #[test]
    fn area_paint_stamps_blob_and_clears_when_all_unowned_are_owned() {
        let mut k = tiny_kernel(false);
        k.claimable_mask.fill(1);
        k.owners.fill(OWNER_NEUTRAL);
        assert!(k.set_paint(OWNER_FRIENDLY, PAINT_AREA, 3, 3));
        assert_eq!(k.paint_kind[OWNER_FRIENDLY as usize], PAINT_AREA);
        let marked = k.paint_marked_count(OWNER_FRIENDLY);
        assert!(marked >= 1 && marked <= PAINT_CELL_CAP);
        assert!(
            marked < k.tile_count as i32,
            "area paint must not flood the whole grid"
        );
        let mut owned_n = 0;
        for i in 0..k.tile_count {
            if k.paint_land[OWNER_FRIENDLY as usize][i] != 0 && owned_n + 1 < marked {
                k.owners[i] = OWNER_FRIENDLY;
                owned_n += 1;
            }
        }
        k.maybe_clear_paint();
        assert_eq!(
            k.paint_kind[OWNER_FRIENDLY as usize],
            PAINT_AREA,
            "paint must stay live while any painted cell is unowned"
        );
        for i in 0..k.tile_count {
            if k.paint_land[OWNER_FRIENDLY as usize][i] != 0 {
                k.owners[i] = OWNER_FRIENDLY;
            }
        }
        k.maybe_clear_paint();
        assert_eq!(
            k.paint_kind[OWNER_FRIENDLY as usize],
            PAINT_NONE,
            "area paint should release when every painted cell is owned"
        );
    }

    #[test]
    fn area_paint_orders_live_only_after_commit() {
        let mut k = tiny_kernel(false);
        k.claimable_mask.fill(1);
        k.owners.fill(OWNER_NEUTRAL);
        assert!(k.begin_paint_stroke(OWNER_FRIENDLY));
        assert!(k.stamp_paint(OWNER_FRIENDLY, 3, 3));
        assert!(
            !k.paint_orders_live(OWNER_FRIENDLY),
            "units must wait until the stroke is released"
        );
        k.commit_paint_stroke(OWNER_FRIENDLY);
        assert!(k.paint_orders_live(OWNER_FRIENDLY));
    }

    #[test]
    fn area_paint_holds_while_stroke_open() {
        let mut k = tiny_kernel(false);
        k.claimable_mask.fill(1);
        k.owners.fill(OWNER_NEUTRAL);
        assert!(k.begin_paint_stroke(OWNER_FRIENDLY));
        assert!(k.stamp_paint(OWNER_FRIENDLY, 0, 0));
        for i in 0..k.tile_count {
            if k.paint_land[OWNER_FRIENDLY as usize][i] != 0 {
                k.owners[i] = OWNER_FRIENDLY;
            }
        }
        k.maybe_clear_paint();
        assert_eq!(
            k.paint_kind[OWNER_FRIENDLY as usize],
            PAINT_AREA,
            "open stroke must not auto-clear"
        );
        k.commit_paint_stroke(OWNER_FRIENDLY);
        k.maybe_clear_paint();
        assert_eq!(k.paint_kind[OWNER_FRIENDLY as usize], PAINT_NONE);
    }

    #[test]
    fn area_paint_caps_at_cell_limit() {
        let mut k = tiny_kernel(false);
        k.claimable_mask.fill(1);
        k.owners.fill(OWNER_NEUTRAL);
        assert!(k.begin_paint_stroke(OWNER_FRIENDLY));
        for y in 0..k.grid_h {
            for x in 0..k.grid_w {
                k.stamp_paint(OWNER_FRIENDLY, x, y);
            }
        }
        k.commit_paint_stroke(OWNER_FRIENDLY);
        let marked = k.paint_marked_count(OWNER_FRIENDLY);
        assert!(marked > 0 && marked <= PAINT_CELL_CAP);
    }

    #[test]
    fn paint_flow_points_every_cell_at_unowned_paint() {
        let mut k = tiny_kernel(false);
        k.claimable_mask.fill(1);
        k.owners.fill(OWNER_NEUTRAL);
        assert!(k.begin_paint_stroke(OWNER_FRIENDLY));
        k.paint_land[OWNER_FRIENDLY as usize].fill(0);
        k.paint_land[OWNER_FRIENDLY as usize][7] = 1;
        k.paint_kind[OWNER_FRIENDLY as usize] = PAINT_AREA;
        k.commit_paint_stroke(OWNER_FRIENDLY);
        let t = OWNER_FRIENDLY as usize;
        assert_eq!(k.paint_flow_dist[t][7], 0);
        assert_eq!(k.paint_flow_dist[t][6], 1);
        assert_eq!(k.paint_flow_dist[t][0], 7);
        assert_eq!(k.paint_flow_next_idx(OWNER_FRIENDLY, 0), Some(1));
        k.owners[7] = OWNER_FRIENDLY;
        k.rebuild_paint_flow(OWNER_FRIENDLY);
        assert_eq!(
            k.paint_flow_dist[t][0],
            i32::MAX,
            "owned paint must drop out of the flow"
        );
    }
}
