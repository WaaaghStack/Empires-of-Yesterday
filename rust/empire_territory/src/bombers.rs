//! World Conquest bombers — flight-band units spawned from hangars.

use crate::pathfind::battle_nav::AgentNavMasks;
use crate::pathfind::kernel::SearchKernel;
use crate::pathfind::nav_rules::{is_air_strike_target_at, run_bomber_strike_rule};
use crate::sim::{TerritoryKernel, OWNER_FRIENDLY};

#[derive(Clone, Debug)]
pub struct BomberConfig {
    pub global_cap: u32,
    pub per_hangar_cap: u32,
    pub max_hp: f32,
    pub move_cells_per_sec: f32,
    pub infra_move_mult: f32,
    pub bomb_power: f32,
    pub bomb_interval_sec: f32,
    pub orphan_dps: f32,
    pub step_dt: f32,
    pub replans_per_tick: u32,
    pub replan_fallback_rounds: i32,
    /// BFS cell budget for the first strike search from this bomber's position.
    pub search_expand_initial: usize,
    /// Added to the search budget after a failed strike search.
    pub search_expand_step: usize,
    /// Hard cap on per-search expansion (still below full-map unless needed).
    pub search_expand_max: usize,
    /// Seconds on the same plan before forcing a full route re-evaluation.
    pub plan_reeval_sec: f32,
}

impl Default for BomberConfig {
    fn default() -> Self {
        Self {
            global_cap: 100,
            per_hangar_cap: 5,
            max_hp: 100.0,
            move_cells_per_sec: 2.0,
            infra_move_mult: 3.0,
            bomb_power: 1000.0,
            bomb_interval_sec: 10.0,
            orphan_dps: 1.0,
            step_dt: 1.0 / 14.0,
            replans_per_tick: 6,
            replan_fallback_rounds: 42,
            search_expand_initial: 5_000,
            search_expand_step: 5_000,
            search_expand_max: 40_000,
            plan_reeval_sec: 25.0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct BombDropEvent {
    pub gx: i32,
    pub gy: i32,
    pub team: u8,
}

#[derive(Clone, Debug)]
pub struct Bomber {
    pub id: u32,
    pub team: u8,
    pub hangar_id: i32,
    pub gx: i32,
    pub gy: i32,
    pub hp: f32,
    pub orphan: bool,
    /// SCD1 bombers domain version stamp.
    pub version: u64,
    pub goal_gx: i32,
    pub goal_gy: i32,
    pub step_gx: i32,
    pub step_gy: i32,
    pub move_accum: f32,
    pub retarget_cd: i32,
    pub bomb_cd: f32,
    /// Current BFS expansion budget for strike searches.
    pub search_expand_limit: usize,
    /// Time spent executing the current route / hold plan.
    pub plan_age_sec: f32,
    deploy_path: Vec<i32>,
    deploy_path_pos: usize,
    goal_nav_stamp: u32,
    goal_nav_masks_epoch: u32,
}

pub struct BomberLayer {
    pub bombers: Vec<Bomber>,
    pub config: BomberConfig,
    living_by_hangar: std::collections::HashMap<i32, u32>,
    next_id: u32,
    pub friendly_corridor: Vec<u8>,
    pub hostile_corridor: Vec<u8>,
    pub friendly_bridge: Vec<u8>,
    pub hostile_bridge: Vec<u8>,
    nav_masks_epoch: u32,
    replan_cursor: usize,
    nav_search: SearchKernel,
    pub pending_bomb_events: Vec<BombDropEvent>,
}

impl BomberLayer {
    pub fn new(config: BomberConfig) -> Self {
        Self {
            bombers: Vec::new(),
            config,
            living_by_hangar: std::collections::HashMap::new(),
            next_id: 1,
            friendly_corridor: Vec::new(),
            hostile_corridor: Vec::new(),
            friendly_bridge: Vec::new(),
            hostile_bridge: Vec::new(),
            nav_masks_epoch: 0,
            replan_cursor: 0,
            nav_search: SearchKernel::new(1),
            pending_bomb_events: Vec::new(),
        }
    }

    pub fn update_nav_masks(
        &mut self,
        friendly_corridor: Vec<u8>,
        hostile_corridor: Vec<u8>,
        friendly_bridge: Vec<u8>,
        hostile_bridge: Vec<u8>,
    ) {
        let changed = self.friendly_corridor != friendly_corridor
            || self.hostile_corridor != hostile_corridor
            || self.friendly_bridge != friendly_bridge
            || self.hostile_bridge != hostile_bridge;
        self.friendly_corridor = friendly_corridor;
        self.hostile_corridor = hostile_corridor;
        self.friendly_bridge = friendly_bridge;
        self.hostile_bridge = hostile_bridge;
        if !changed {
            return;
        }
        self.nav_masks_epoch = self.nav_masks_epoch.wrapping_add(1);
        if self.nav_masks_epoch == 0 {
            self.nav_masks_epoch = 1;
        }
    }

    pub fn living_count(&self) -> u32 {
        self.bombers.len() as u32
    }

    pub fn living_for_hangar(&self, hangar_id: i32) -> u32 {
        *self.living_by_hangar.get(&hangar_id).unwrap_or(&0)
    }

    pub fn try_spawn(
        &mut self,
        kernel: &TerritoryKernel,
        hangar_id: i32,
        team: u8,
        gx: i32,
        gy: i32,
    ) -> bool {
        if self.bombers.len() as u32 >= self.config.global_cap {
            return false;
        }
        if self.living_for_hangar(hangar_id) >= self.config.per_hangar_cap {
            return false;
        }
        if kernel.cell_index(gx, gy) < 0 {
            return false;
        }
        let id = self.next_id;
        self.next_id += 1;
        self.bombers.push(Bomber {
            id,
            team,
            hangar_id,
            gx,
            gy,
            hp: self.config.max_hp,
            orphan: false,
            version: 0,
            goal_gx: gx,
            goal_gy: gy,
            step_gx: -1,
            step_gy: -1,
            move_accum: 0.0,
            retarget_cd: 0,
            bomb_cd: self.config.bomb_interval_sec,
            search_expand_limit: self.config.search_expand_initial,
            plan_age_sec: 0.0,
            deploy_path: Vec::new(),
            deploy_path_pos: 0,
            goal_nav_stamp: 0,
            goal_nav_masks_epoch: 0,
        });
        let last = self.bombers.len() - 1;
        self.replan_route(kernel, last, false);
        self.finish_replan(kernel, last);
        *self
            .living_by_hangar
            .entry(hangar_id)
            .or_insert(0) += 1;
        true
    }

    pub fn on_hangar_destroyed(&mut self, hangar_id: i32) {
        for bomber in &mut self.bombers {
            if bomber.hangar_id == hangar_id && !bomber.orphan {
                bomber.orphan = true;
            }
        }
        self.living_by_hangar.remove(&hangar_id);
    }

    pub fn take_bomb_events(&mut self) -> Vec<BombDropEvent> {
        std::mem::take(&mut self.pending_bomb_events)
    }

    pub fn tick(&mut self, kernel: &mut TerritoryKernel) {
        let dt = self.config.step_dt;
        let mut dead: Vec<u32> = Vec::new();
        let n = self.bombers.len();

        for i in 0..n {
            self.bombers[i].plan_age_sec += dt;
        }

        self.run_budgeted_replans(kernel);

        for i in 0..n {
            let team = self.bombers[i].team;
            let gx = self.bombers[i].gx;
            let gy = self.bombers[i].gy;
            let mut move_rate = self.config.move_cells_per_sec;
            let idx = kernel.cell_index(gx, gy);
            if idx >= 0 {
                let ui = idx as usize;
                if ui < kernel.tile_count && self.is_network_cell(team, ui) {
                    move_rate *= self.config.infra_move_mult;
                }
            }
            self.bombers[i].move_accum += move_rate * dt;
            while self.bombers[i].move_accum >= 1.0 {
                self.bombers[i].move_accum -= 1.0;
                let sx = self.bombers[i].step_gx;
                let sy = self.bombers[i].step_gy;
                if sx >= 0 && (sx != self.bombers[i].gx || sy != self.bombers[i].gy) {
                    if !self.is_in_bounds(kernel, sx, sy) {
                        self.bombers[i].step_gx = -1;
                        self.bombers[i].step_gy = -1;
                        self.bombers[i].retarget_cd = 0;
                        break;
                    }
                    self.bombers[i].gx = sx;
                    self.bombers[i].gy = sy;
                    self.advance_deploy_path_after_move(kernel, i);
                    self.sync_step_from_deploy_path(kernel, i);
                } else if self.holding_at_goal(kernel, team, &self.bombers[i]) {
                    break;
                } else {
                    self.bombers[i].retarget_cd = 0;
                    break;
                }
            }
        }

        for i in 0..n {
            let team = self.bombers[i].team;
            if self.holding_at_goal(kernel, team, &self.bombers[i]) {
                self.bombers[i].bomb_cd -= dt;
                if self.bombers[i].bomb_cd <= 0.0 {
                    let gx = self.bombers[i].gx;
                    let gy = self.bombers[i].gy;
                    self.apply_bomb_to_kernel(kernel, team, gx, gy);
                    self.pending_bomb_events.push(BombDropEvent { gx, gy, team });
                    self.bombers[i].bomb_cd = self.config.bomb_interval_sec;
                    self.bombers[i].retarget_cd = 0;
                }
            }

            if self.bombers[i].orphan {
                let dps = self.config.orphan_dps;
                if dps > 0.0 {
                    self.bombers[i].hp -= dps * dt;
                }
            }

            if self.bombers[i].hp <= 0.0 {
                dead.push(self.bombers[i].id);
            }
        }

        if !dead.is_empty() {
            self.remove_dead(&dead);
        }
    }

    fn apply_bomb_to_kernel(
        &self,
        kernel: &mut TerritoryKernel,
        team: u8,
        gx: i32,
        gy: i32,
    ) {
        let power = self.config.bomb_power;
        if power <= 0.0 {
            return;
        }
        let idx = kernel.cell_index(gx, gy);
        if idx < 0 {
            return;
        }
        let ui = idx as usize;
        if ui >= kernel.tile_count {
            return;
        }
        if team == OWNER_FRIENDLY {
            kernel.pressure_hostile[ui] = (kernel.pressure_hostile[ui] - power).max(0.0);
            kernel.pressure_friendly[ui] += power * 0.35;
        } else {
            kernel.pressure_friendly[ui] = (kernel.pressure_friendly[ui] - power).max(0.0);
            kernel.pressure_hostile[ui] += power * 0.35;
        }
        kernel.mark_pressure_dirty(ui);
    }

    fn run_budgeted_replans(&mut self, kernel: &TerritoryKernel) {
        let n = self.bombers.len();
        if n == 0 {
            return;
        }

        let mut urgent: Vec<(usize, bool)> = Vec::new();
        let mut normal: Vec<(usize, bool)> = Vec::new();

        for i in 0..n {
            let team = self.bombers[i].team;
            let holding = self.holding_at_goal(kernel, team, &self.bombers[i]);
            let stuck = self.bombers[i].step_gx < 0 && !holding;
            let nav_stale = self.nav_stale_for_bomber(kernel, &self.bombers[i]);
            let fallback_due = self.bombers[i].retarget_cd <= 0;
            let plan_reeval_due = self.bombers[i].plan_age_sec >= self.config.plan_reeval_sec;

            if plan_reeval_due {
                self.bombers[i].search_expand_limit = self.config.search_expand_initial;
                self.bombers[i].plan_age_sec = 0.0;
                normal.push((i, false));
                continue;
            }

            if stuck {
                urgent.push((i, false));
                continue;
            }

            if holding {
                if nav_stale {
                    normal.push((i, false));
                } else if fallback_due {
                    normal.push((i, true));
                } else {
                    self.bombers[i].retarget_cd -= 1;
                }
                continue;
            }

            if nav_stale || fallback_due {
                normal.push((i, false));
                continue;
            }

            self.bombers[i].retarget_cd -= 1;
        }

        let mut budget = self.config.replans_per_tick.max(1) as usize;
        if !urgent.is_empty() {
            budget = budget.max(urgent.len().min(24));
        }
        let urgent_cap = budget.min(urgent.len());
        for &(i, prefer_alternate) in urgent.iter().take(urgent_cap) {
            self.replan_route(kernel, i, prefer_alternate);
            self.finish_replan(kernel, i);
            budget = budget.saturating_sub(1);
        }

        if normal.is_empty() || budget == 0 {
            return;
        }

        let m = normal.len();
        let attempts = m.min(budget);
        for t in 0..attempts {
            let slot = (self.replan_cursor + t) % m;
            let (i, prefer_alternate) = normal[slot];
            self.replan_route(kernel, i, prefer_alternate);
            self.finish_replan(kernel, i);
        }
        self.replan_cursor = self.replan_cursor.wrapping_add(attempts);
    }

    fn finish_replan(&mut self, kernel: &TerritoryKernel, bomber_i: usize) {
        let (gx, gy, goal_gx, goal_gy, id, team) = {
            let bomber = &self.bombers[bomber_i];
            (
                bomber.gx,
                bomber.gy,
                bomber.goal_gx,
                bomber.goal_gy,
                bomber.id,
                bomber.team,
            )
        };
        let stamp = self.snapshot_nav_stamp(kernel, gx, gy, goal_gx, goal_gy);
        let masks_epoch = self.nav_masks_epoch;
        let stagger = (id as i32 % 7).max(1);
        let holding = self.holding_at_goal(kernel, team, &self.bombers[bomber_i]);
        let bomber = &mut self.bombers[bomber_i];
        if bomber.step_gx >= 0 || holding {
            bomber.retarget_cd = self.config.replan_fallback_rounds + stagger;
            bomber.plan_age_sec = 0.0;
        } else {
            bomber.retarget_cd = 0;
        }
        bomber.goal_nav_stamp = stamp;
        bomber.goal_nav_masks_epoch = masks_epoch;
    }

    fn nav_stale_for_bomber(&self, kernel: &TerritoryKernel, bomber: &Bomber) -> bool {
        if bomber.goal_nav_masks_epoch < self.nav_masks_epoch {
            return true;
        }
        let stamp = self.snapshot_nav_stamp(
            kernel,
            bomber.gx,
            bomber.gy,
            bomber.goal_gx,
            bomber.goal_gy,
        );
        stamp > bomber.goal_nav_stamp
    }

    fn snapshot_nav_stamp(
        &self,
        kernel: &TerritoryKernel,
        gx: i32,
        gy: i32,
        goal_gx: i32,
        goal_gy: i32,
    ) -> u32 {
        kernel
            .nav_stamp_at(gx, gy)
            .max(kernel.nav_stamp_at(goal_gx, goal_gy))
    }

    fn capped_search_expand(&self, kernel: &TerritoryKernel, bomber: &Bomber) -> usize {
        let cap = self
            .config
            .search_expand_max
            .max(self.config.search_expand_initial)
            .min(kernel.tile_count.max(self.config.search_expand_initial));
        bomber.search_expand_limit.min(cap)
    }

    fn note_strike_search_result(&mut self, bomber_i: usize, kernel: &TerritoryKernel, found: bool) {
        if found {
            self.bombers[bomber_i].search_expand_limit = self.config.search_expand_initial;
            return;
        }
        let cap = self
            .config
            .search_expand_max
            .max(self.config.search_expand_initial)
            .min(kernel.tile_count.max(self.config.search_expand_initial));
        let next = self.bombers[bomber_i].search_expand_limit + self.config.search_expand_step;
        self.bombers[bomber_i].search_expand_limit = next.min(cap);
    }

    fn replan_route(
        &mut self,
        kernel: &TerritoryKernel,
        bomber_i: usize,
        prefer_alternate_goal: bool,
    ) {
        let gx = self.bombers[bomber_i].gx;
        let gy = self.bombers[bomber_i].gy;
        let team = self.bombers[bomber_i].team;
        let start_idx = kernel.cell_index(gx, gy);
        if start_idx < 0 {
            self.bombers[bomber_i].step_gx = -1;
            self.bombers[bomber_i].step_gy = -1;
            return;
        }

        let masks = AgentNavMasks {
            friendly_corridor: &self.friendly_corridor,
            hostile_corridor: &self.hostile_corridor,
            friendly_bridge: &self.friendly_bridge,
            hostile_bridge: &self.hostile_bridge,
        };

        if !prefer_alternate_goal && is_air_strike_target_at(kernel, &masks, team, gx, gy) {
            self.bombers[bomber_i].goal_gx = gx;
            self.bombers[bomber_i].goal_gy = gy;
            self.bombers[bomber_i].deploy_path = vec![start_idx];
            self.bombers[bomber_i].deploy_path_pos = 0;
            self.bombers[bomber_i].step_gx = -1;
            self.bombers[bomber_i].step_gy = -1;
            self.note_strike_search_result(bomber_i, kernel, true);
            return;
        }

        self.nav_search.ensure_capacity(kernel.tile_count);
        let exclude = if prefer_alternate_goal {
            Some(start_idx)
        } else {
            None
        };
        let max_expand = self.capped_search_expand(kernel, &self.bombers[bomber_i]);
        let outcome = run_bomber_strike_rule(
            &mut self.nav_search,
            kernel,
            &masks,
            gx,
            gy,
            team,
            exclude,
            max_expand,
        );

        if outcome.path.is_none()
            && prefer_alternate_goal
            && is_air_strike_target_at(kernel, &masks, team, gx, gy)
        {
            self.bombers[bomber_i].goal_gx = gx;
            self.bombers[bomber_i].goal_gy = gy;
            self.bombers[bomber_i].deploy_path = vec![start_idx];
            self.bombers[bomber_i].deploy_path_pos = 0;
            self.bombers[bomber_i].step_gx = -1;
            self.bombers[bomber_i].step_gy = -1;
            self.note_strike_search_result(bomber_i, kernel, true);
            return;
        }

        if let Some(route) = outcome.path {
            if route.path.len() >= 2 {
                let w = kernel.grid_w;
                let goal_idx = *route.path.last().unwrap();
                let (goal_x, goal_y) = Self::grid_from_idx(goal_idx, w);
                self.bombers[bomber_i].goal_gx = goal_x;
                self.bombers[bomber_i].goal_gy = goal_y;
                self.bombers[bomber_i].deploy_path = route.path;
                self.bombers[bomber_i].deploy_path_pos = 0;
                self.sync_step_from_deploy_path(kernel, bomber_i);
                self.note_strike_search_result(bomber_i, kernel, true);
                return;
            }
            if route.path.len() == 1 {
                let w = kernel.grid_w;
                let goal_idx = route.path[0];
                let (goal_x, goal_y) = Self::grid_from_idx(goal_idx, w);
                self.bombers[bomber_i].goal_gx = goal_x;
                self.bombers[bomber_i].goal_gy = goal_y;
                self.bombers[bomber_i].deploy_path = route.path;
                self.bombers[bomber_i].deploy_path_pos = 0;
                self.bombers[bomber_i].step_gx = -1;
                self.bombers[bomber_i].step_gy = -1;
                self.note_strike_search_result(bomber_i, kernel, true);
                return;
            }
        }

        self.bombers[bomber_i].step_gx = -1;
        self.bombers[bomber_i].step_gy = -1;
        self.bombers[bomber_i].deploy_path.clear();
        self.bombers[bomber_i].deploy_path_pos = 0;
        self.note_strike_search_result(bomber_i, kernel, false);
    }

    fn holding_at_goal(&self, kernel: &TerritoryKernel, team: u8, bomber: &Bomber) -> bool {
        let masks = AgentNavMasks {
            friendly_corridor: &self.friendly_corridor,
            hostile_corridor: &self.hostile_corridor,
            friendly_bridge: &self.friendly_bridge,
            hostile_bridge: &self.hostile_bridge,
        };
        is_air_strike_target_at(kernel, &masks, team, bomber.gx, bomber.gy)
    }

    fn is_network_cell(&self, team: u8, idx: usize) -> bool {
        let (corridor, bridge) = if team == OWNER_FRIENDLY {
            (&self.friendly_corridor, &self.friendly_bridge)
        } else {
            (&self.hostile_corridor, &self.hostile_bridge)
        };
        (idx < corridor.len() && corridor[idx] != 0) || (idx < bridge.len() && bridge[idx] != 0)
    }

    fn is_in_bounds(&self, kernel: &TerritoryKernel, gx: i32, gy: i32) -> bool {
        kernel.cell_index(gx, gy) >= 0
    }

    fn sync_step_from_deploy_path(&mut self, kernel: &TerritoryKernel, bomber_i: usize) {
        let team = self.bombers[bomber_i].team;
        if self.holding_at_goal(kernel, team, &self.bombers[bomber_i]) {
            self.bombers[bomber_i].step_gx = -1;
            self.bombers[bomber_i].step_gy = -1;
            return;
        }

        let w = kernel.grid_w;
        let pos = self.bombers[bomber_i].deploy_path_pos;
        let path = self.bombers[bomber_i].deploy_path.clone();
        if pos + 1 < path.len() {
            let next_idx = path[pos + 1];
            let (sx, sy) = Self::grid_from_idx(next_idx, w);
            self.bombers[bomber_i].step_gx = sx;
            self.bombers[bomber_i].step_gy = sy;
        } else {
            self.bombers[bomber_i].step_gx = -1;
            self.bombers[bomber_i].step_gy = -1;
        }
    }

    fn advance_deploy_path_after_move(&mut self, kernel: &TerritoryKernel, bomber_i: usize) {
        let cur_idx = kernel.cell_index(self.bombers[bomber_i].gx, self.bombers[bomber_i].gy);
        if cur_idx < 0 {
            return;
        }
        let path = &self.bombers[bomber_i].deploy_path;
        let pos = self.bombers[bomber_i].deploy_path_pos;
        if pos + 1 < path.len() && path[pos + 1] == cur_idx {
            self.bombers[bomber_i].deploy_path_pos = pos + 1;
        } else if !path.is_empty() && path[pos] != cur_idx {
            if let Some(found) = path.iter().position(|&c| c == cur_idx) {
                self.bombers[bomber_i].deploy_path_pos = found;
            }
        }
    }

    fn remove_dead(&mut self, dead: &[u32]) {
        self.bombers.retain(|b| {
            if dead.contains(&b.id) {
                if !b.orphan {
                    if let Some(c) = self.living_by_hangar.get_mut(&b.hangar_id) {
                        *c = c.saturating_sub(1);
                    }
                }
                false
            } else {
                true
            }
        });
    }

    fn grid_from_idx(idx: i32, w: i32) -> (i32, i32) {
        (idx % w, idx / w)
    }
}
