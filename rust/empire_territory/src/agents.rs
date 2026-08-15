//! World Conquest soldiers — path via nav rules toward frontier stance tiles.

use std::collections::HashMap;

use crate::pathfind::battle_nav::{AgentNavMasks, BattleNavView};
use crate::pathfind::kernel::{RoutePath, SearchKernel};
use crate::pathfind::nav_rules::{
    is_stance_goal_at, rule_by_id, run_nav_rule, NAV_RULE_INFANTRY_ADVANCE, NAV_RULE_INFANTRY_RETREAT,
};
use crate::sim::{
    TerritoryKernel, OWNER_CONTESTED, OWNER_FRIENDLY, OWNER_HOSTILE, OWNER_NEUTRAL,
    OWNER_UNCLAIMABLE, MIN_CLAIM_PRESSURE,
};

const HOSTILE_TERRITORY_DPS: f32 = 3.0;
const CLAIM_DOMINANCE_RATIO: f32 = 1.15;
const AURA_STACK_CAP: u32 = 5;
/// After free-goal BFS misses, skip free search for this many replan cycles (C1/C4 FPS).
const FREE_GOAL_MISS_SKIP_TICKS: u8 = 8;

type CellKey = (i32, i32);

#[derive(Clone, Debug)]
pub struct AgentConfig {
    pub global_cap: u32,
    pub per_barracks_cap: u32,
    pub max_hp: f32,
    pub move_cells_per_sec: f32,
    /// Move rate multiplier while on open water (ferry).
    pub ferry_move_mult: f32,
    pub aura_pressure: f32,
    pub shoot_erode_per_step: f32,
    pub orphan_dps: f32,
    pub step_dt: f32,
    pub replans_per_tick: u32,
    pub replan_fallback_rounds: i32,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            global_cap: 100,
            per_barracks_cap: 5,
            max_hp: 40.0,
            move_cells_per_sec: 1.0,
            ferry_move_mult: 0.25,
            aura_pressure: 5.0,
            shoot_erode_per_step: 1.6 / 14.0,
            orphan_dps: 4.0,
            step_dt: 1.0 / 14.0,
            replans_per_tick: 6,
            replan_fallback_rounds: 42,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Agent {
    pub id: u32,
    pub team: u8,
    pub barracks_id: i32,
    pub gx: i32,
    pub gy: i32,
    pub hp: f32,
    pub orphan: bool,
    /// SCD1 agents domain version stamp.
    pub version: u64,
    pub goal_gx: i32,
    pub goal_gy: i32,
    pub step_gx: i32,
    pub step_gy: i32,
    pub move_accum: f32,
    pub retarget_cd: i32,
    /// Cell indices along the planned route toward the nav-rule goal.
    deploy_path: Vec<i32>,
    /// Index into `deploy_path` for the soldier's current cell.
    deploy_path_pos: usize,
    goal_nav_stamp: u32,
    goal_nav_masks_epoch: u32,
}

pub struct AgentLayer {
    pub agents: Vec<Agent>,
    pub config: AgentConfig,
    pub friendly_deficit_dps: f32,
    pub hostile_deficit_dps: f32,
    living_by_barracks: HashMap<i32, u32>,
    /// Live ground occupancy: cell → soldier id (one living soldier per cell).
    occupant_at: HashMap<CellKey, u32>,
    /// Soft free-goal claims: goal cell → agent id (C2 stampede cap, one claimer per free tile).
    goal_claims: HashMap<CellKey, u32>,
    /// Per-team countdown: skip free-goal BFS while > 0 after a free miss (C4).
    free_miss_cd: [u8; 3],
    /// Per-team `any_land_advance_goal` cache for the current budgeted replan pass.
    /// `None` = unset this tick; filled lazily on first use.
    land_advance_goal_cache: [Option<bool>; 3],
    next_id: u32,
    pub friendly_corridor: Vec<u8>,
    pub hostile_corridor: Vec<u8>,
    pub friendly_bridge: Vec<u8>,
    pub hostile_bridge: Vec<u8>,
    nav_masks_epoch: u32,
    replan_cursor: usize,
    nav_search: SearchKernel,
    /// Test-only: how many times replan invoked free-goal BFS (free_goals_only=true).
    #[cfg(test)]
    free_goal_bfs_calls: u32,
    /// Test-only: how many times replan invoked contested/unrestricted BFS.
    #[cfg(test)]
    contested_bfs_calls: u32,
    /// Cleared by caller; set when ferry landing expands claimable reachability.
    pub beachhead_expanded: bool,
}

impl AgentLayer {
    pub fn new(config: AgentConfig) -> Self {
        Self {
            agents: Vec::new(),
            config,
            friendly_deficit_dps: 0.0,
            hostile_deficit_dps: 0.0,
            living_by_barracks: HashMap::new(),
            occupant_at: HashMap::new(),
            goal_claims: HashMap::new(),
            free_miss_cd: [0; 3],
            land_advance_goal_cache: [None; 3],
            next_id: 1,
            friendly_corridor: Vec::new(),
            hostile_corridor: Vec::new(),
            friendly_bridge: Vec::new(),
            hostile_bridge: Vec::new(),
            nav_masks_epoch: 0,
            replan_cursor: 0,
            nav_search: SearchKernel::new(1),
            #[cfg(test)]
            free_goal_bfs_calls: 0,
            #[cfg(test)]
            contested_bfs_calls: 0,
            beachhead_expanded: false,
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
        // Nav masks changed → free goals may reappear; clear free-miss skip.
        self.free_miss_cd = [0; 3];
        self.land_advance_goal_cache = [None; 3];
    }

    /// Player paint committed or cleared — peel off the local front this tick.
    pub fn notify_paint_orders(&mut self, kernel: &TerritoryKernel, team: u8) {
        self.nav_masks_epoch = self.nav_masks_epoch.wrapping_add(1);
        if self.nav_masks_epoch == 0 {
            self.nav_masks_epoch = 1;
        }
        let t = team as usize;
        if t < self.free_miss_cd.len() {
            self.free_miss_cd[t] = 0;
        }
        self.land_advance_goal_cache = [None; 3];
        for i in 0..self.agents.len() {
            if self.agents[i].team == team {
                self.agents[i].retarget_cd = 0;
                self.steer_agent_to_paint(kernel, i);
            }
        }
    }

    pub fn living_count(&self) -> u32 {
        self.agents.len() as u32
    }

    pub fn living_count_for_team(&self, team: u8) -> u32 {
        self.agents.iter().filter(|a| a.team == team).count() as u32
    }

    pub fn living_for_barracks(&self, barracks_id: i32) -> u32 {
        *self.living_by_barracks.get(&barracks_id).unwrap_or(&0)
    }

    pub fn try_spawn(
        &mut self,
        kernel: &TerritoryKernel,
        barracks_id: i32,
        team: u8,
        bx: i32,
        by: i32,
    ) -> bool {
        if self.agents.len() as u32 >= self.config.global_cap {
            return false;
        }
        if self.living_for_barracks(barracks_id) >= self.config.per_barracks_cap {
            return false;
        }
        let Some((gx, gy)) = self.find_spawn_cell(kernel, team, bx, by) else {
            return false;
        };
        let id = self.next_id;
        self.next_id += 1;
        self.agents.push(Agent {
            id,
            team,
            barracks_id,
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
            deploy_path: Vec::new(),
            deploy_path_pos: 0,
            goal_nav_stamp: 0,
            goal_nav_masks_epoch: 0,
        });
        self.set_occupant(gx, gy, id);
        let last = self.agents.len() - 1;
        self.replan_route(kernel, last);
        self.finish_replan(kernel, last);
        *self
            .living_by_barracks
            .entry(barracks_id)
            .or_insert(0) += 1;
        true
    }

    pub fn on_barracks_destroyed(&mut self, barracks_id: i32) {
        for agent in &mut self.agents {
            if agent.barracks_id == barracks_id && !agent.orphan {
                agent.orphan = true;
            }
        }
        self.living_by_barracks.remove(&barracks_id);
    }

    pub fn tick(&mut self, kernel: &mut TerritoryKernel) {
        let dt = self.config.step_dt;
        let mut dead: Vec<u32> = Vec::new();
        let n = self.agents.len();

        kernel.rebuild_live_paint_flows();
        self.run_budgeted_replans(kernel);

        for i in 0..n {
            let team = self.agents[i].team;
            let gx = self.agents[i].gx;
            let gy = self.agents[i].gy;
            let mut move_rate = self.config.move_cells_per_sec;
            let idx = kernel.cell_index(gx, gy);
            if idx >= 0 {
                let ui = idx as usize;
                // R1: no road/bridge speed bonus — land speed is uniform.
                // Ferry: open water is slower than land.
                let on_water = !kernel.land_mask.is_empty()
                    && ui < kernel.land_mask.len()
                    && kernel.land_mask[ui] == 0;
                if on_water {
                    move_rate *= self.config.ferry_move_mult.max(0.01);
                }
            }
            self.agents[i].move_accum += move_rate * dt;
            while self.agents[i].move_accum >= 1.0 {
                if kernel.paint_orders_live(team) {
                    self.steer_agent_to_paint(kernel, i);
                }
                let sx = self.agents[i].step_gx;
                let sy = self.agents[i].step_gy;
                let id = self.agents[i].id;
                if sx >= 0 && (sx != self.agents[i].gx || sy != self.agents[i].gy) {
                    // Path blocked by peer: wait one sim move step (no pathfind thrash).
                    if self.ground_occupied_by_other(sx, sy, id) {
                        self.agents[i].move_accum = self.agents[i].move_accum.min(1.0);
                        break;
                    }
                    if !self.is_passable(kernel, team, sx, sy) {
                        self.agents[i].move_accum -= 1.0;
                        self.agents[i].step_gx = -1;
                        self.agents[i].step_gy = -1;
                        self.agents[i].retarget_cd = 0;
                        break;
                    }
                    self.agents[i].move_accum -= 1.0;
                    let old_gx = self.agents[i].gx;
                    let old_gy = self.agents[i].gy;
                    self.agents[i].gx = sx;
                    self.agents[i].gy = sy;
                    self.move_occupant(old_gx, old_gy, sx, sy, id);
                    self.maybe_ferry_beachhead(kernel, team, sx, sy);
                    self.advance_deploy_path_after_move(kernel, i);
                    self.sync_step_from_deploy_path(kernel, i);
                } else if self.holding_at_goal(kernel, team, &self.agents[i]) {
                    break;
                } else {
                    self.agents[i].move_accum -= 1.0;
                    self.agents[i].retarget_cd = 0;
                    break;
                }
            }
        }

        self.apply_batched_aura(kernel);

        for i in 0..n {
            let gx = self.agents[i].gx;
            let gy = self.agents[i].gy;
            let idx = kernel.cell_index(gx, gy);
            if idx >= 0 {
                let ui = idx as usize;
                let team = self.agents[i].team;
                Self::apply_shoot_to_kernel(
                    kernel,
                    team,
                    gx,
                    gy,
                    self.config.shoot_erode_per_step,
                    &self.friendly_corridor,
                    &self.hostile_corridor,
                    &self.friendly_bridge,
                    &self.hostile_bridge,
                );
                let mut dps = territory_dps_at(kernel, team, ui);
                if self.agents[i].orphan {
                    dps += self.config.orphan_dps;
                }
                let deficit = if team == OWNER_FRIENDLY {
                    self.friendly_deficit_dps
                } else {
                    self.hostile_deficit_dps
                };
                dps += deficit;
                if dps > 0.0 {
                    self.agents[i].hp -= dps * dt;
                }
            }

            if self.agents[i].hp <= 0.0 {
                dead.push(self.agents[i].id);
            }
        }

        if !dead.is_empty() {
            self.remove_dead(&dead);
        }
    }

    fn run_budgeted_replans(&mut self, kernel: &TerritoryKernel) {
        let n = self.agents.len();
        if n == 0 {
            return;
        }
        // Tick free-miss skip counters (C4) once per budgeted replan pass.
        for cd in self.free_miss_cd.iter_mut() {
            *cd = cd.saturating_sub(1);
        }
        // Fresh land-goal cache for this tick (scanned once per team).
        self.land_advance_goal_cache = [None; 3];

        let mut urgent: Vec<usize> = Vec::new();
        let mut normal: Vec<usize> = Vec::new();

        for i in 0..n {
            let team = self.agents[i].team;
            if kernel.paint_orders_live(team) {
                // Globe-wide paint flow steers every unit in the move loop.
                continue;
            }
            let id = self.agents[i].id;
            let holding = self.holding_at_goal(kernel, team, &self.agents[i]);
            let stuck = self.agents[i].step_gx < 0 && !holding;
            let nav_stale = self.nav_stale_for_agent(kernel, &self.agents[i]);
            let fallback_due = self.agents[i].retarget_cd <= 0;
            // Goal taken by another soldier → reassess to next free conquest goal.
            let goal_taken = self.ground_occupied_by_other(
                self.agents[i].goal_gx,
                self.agents[i].goal_gy,
                id,
            );

            if goal_taken {
                urgent.push(i);
                continue;
            }

            // Stuck after a failed replan must honor retarget_cd backoff — otherwise
            // every stuck unit is urgent every tick and ferry thrash returns.
            if stuck {
                if fallback_due {
                    urgent.push(i);
                } else {
                    self.agents[i].retarget_cd -= 1;
                }
                continue;
            }

            if holding {
                if nav_stale {
                    normal.push(i);
                } else {
                    self.agents[i].retarget_cd -= 1;
                }
                continue;
            }

            if nav_stale || fallback_due {
                normal.push(i);
                continue;
            }

            self.agents[i].retarget_cd -= 1;
        }

        // Cap urgent replans at replans_per_tick — do not inflate to min(24) when many
        // units lose path at once (endgame pile-up / same-goal stampede).
        let mut budget = self.config.replans_per_tick.max(1) as usize;
        // Many stuck: reserve ~half the budget for normal rotation so we don't thrash
        // the same stuck set every tick (late-game ferry miss pile-up).
        let urgent_cap = if urgent.len() > budget {
            ((budget + 1) / 2).max(1).min(urgent.len())
        } else {
            budget.min(urgent.len())
        };
        for &i in urgent.iter().take(urgent_cap) {
            self.replan_route(kernel, i);
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
            let i = normal[slot];
            self.replan_route(kernel, i);
            self.finish_replan(kernel, i);
        }
        self.replan_cursor = self.replan_cursor.wrapping_add(attempts);
    }

    fn finish_replan(&mut self, kernel: &TerritoryKernel, agent_i: usize) {
        let (gx, gy, goal_gx, goal_gy, id) = {
            let agent = &self.agents[agent_i];
            (
                agent.gx,
                agent.gy,
                agent.goal_gx,
                agent.goal_gy,
                agent.id,
            )
        };
        let stamp = self.snapshot_nav_stamp(kernel, gx, gy, goal_gx, goal_gy);
        let masks_epoch = self.nav_masks_epoch;
        let stagger = (id as i32 % 7).max(1);
        let agent = &mut self.agents[agent_i];
        // Always back off after a replan — never retarget_cd=0 on stuck/no-path
        // (that caused urgent ferry thrash every tick as free tiles shrink).
        agent.retarget_cd = self.config.replan_fallback_rounds + stagger;
        agent.goal_nav_stamp = stamp;
        agent.goal_nav_masks_epoch = masks_epoch;
    }

    /// Cached per team per budgeted replan tick — avoids O(tiles) scan per replan.
    fn team_has_land_advance_goal(&mut self, kernel: &TerritoryKernel, team: u8) -> bool {
        let ti = team as usize;
        if ti >= self.land_advance_goal_cache.len() {
            let masks = AgentNavMasks {
                friendly_corridor: &self.friendly_corridor,
                hostile_corridor: &self.hostile_corridor,
                friendly_bridge: &self.friendly_bridge,
                hostile_bridge: &self.hostile_bridge,
            };
            let view = BattleNavView::new(kernel, &masks, team);
            return crate::pathfind::nav_rules::any_land_advance_goal(&view, kernel.tile_count);
        }
        if let Some(cached) = self.land_advance_goal_cache[ti] {
            return cached;
        }
        let masks = AgentNavMasks {
            friendly_corridor: &self.friendly_corridor,
            hostile_corridor: &self.hostile_corridor,
            friendly_bridge: &self.friendly_bridge,
            hostile_bridge: &self.hostile_bridge,
        };
        let view = BattleNavView::new(kernel, &masks, team);
        let has = crate::pathfind::nav_rules::any_land_advance_goal(&view, kernel.tile_count);
        self.land_advance_goal_cache[ti] = Some(has);
        has
    }

    fn nav_stale_for_agent(&self, kernel: &TerritoryKernel, agent: &Agent) -> bool {
        if agent.goal_nav_masks_epoch < self.nav_masks_epoch {
            return true;
        }
        let stamp =
            self.snapshot_nav_stamp(kernel, agent.gx, agent.gy, agent.goal_gx, agent.goal_gy);
        stamp > agent.goal_nav_stamp
    }

    fn snapshot_nav_stamp(
        &self,
        kernel: &TerritoryKernel,
        gx: i32,
        gy: i32,
        goal_gx: i32,
        goal_gy: i32,
    ) -> u32 {
        let mut max_stamp = 0u32;
        for (x, y) in [(gx, gy), (goal_gx, goal_gy)] {
            let idx = kernel.cell_index(x, y);
            if idx < 0 {
                continue;
            }
            max_stamp = max_stamp.max(kernel.nav_stamp_at(x, y));
            let w = kernel.grid_w;
            kernel.for_each_neighbor_idx(idx as usize, |ni| {
                let nx = ni as i32 % w;
                let ny = ni as i32 / w;
                max_stamp = max_stamp.max(kernel.nav_stamp_at(nx, ny));
            });
        }
        max_stamp
    }

    fn apply_batched_aura(&self, kernel: &mut TerritoryKernel) {
        use std::collections::HashMap;
        let mut friendly_counts: HashMap<usize, u32> = HashMap::new();
        let mut hostile_counts: HashMap<usize, u32> = HashMap::new();
        for agent in &self.agents {
            let idx = kernel.cell_index(agent.gx, agent.gy);
            if idx < 0 {
                continue;
            }
            let ui = idx as usize;
            if agent.team == OWNER_FRIENDLY {
                *friendly_counts.entry(ui).or_insert(0) += 1;
            } else {
                *hostile_counts.entry(ui).or_insert(0) += 1;
            }
        }
        let aura = self.config.aura_pressure;
        if aura <= 0.0 {
            return;
        }
        for (ui, count) in friendly_counts {
            if ui >= kernel.tile_count || kernel.claimable_mask[ui] == 0 {
                continue;
            }
            let stacks = count.min(AURA_STACK_CAP) as f32;
            kernel.pressure_friendly[ui] += aura * stacks;
            kernel.mark_pressure_dirty(ui);
        }
        for (ui, count) in hostile_counts {
            if ui >= kernel.tile_count || kernel.claimable_mask[ui] == 0 {
                continue;
            }
            let stacks = count.min(AURA_STACK_CAP) as f32;
            kernel.pressure_hostile[ui] += aura * stacks;
            kernel.mark_pressure_dirty(ui);
        }
    }

    fn replan_route(&mut self, kernel: &TerritoryKernel, agent_i: usize) {
        let gx = self.agents[agent_i].gx;
        let gy = self.agents[agent_i].gy;
        let team = self.agents[agent_i].team;
        let except_id = self.agents[agent_i].id;
        let start_idx = kernel.cell_index(gx, gy);
        if start_idx < 0 {
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            return;
        }

        let start_ui = start_idx as usize;
        let paint_active = kernel.paint_orders_live(team);
        if paint_active {
            self.steer_agent_to_paint(kernel, agent_i);
            return;
        }

        let enemy = enemy_team(team);
        if kernel.owners[start_ui] == enemy
            && !self.adjacent_to_team_supply(kernel, team, gx, gy)
        {
            if let Some((goal_x, goal_y, step_x, step_y)) =
                self.plan_retreat_route(kernel, team, gx, gy)
            {
                self.agents[agent_i].goal_gx = goal_x;
                self.agents[agent_i].goal_gy = goal_y;
                self.agents[agent_i].step_gx = step_x;
                self.agents[agent_i].step_gy = step_y;
                self.agents[agent_i].deploy_path.clear();
                self.agents[agent_i].deploy_path_pos = 0;
                return;
            }
        }

        let hold = {
            let masks = AgentNavMasks {
                friendly_corridor: &self.friendly_corridor,
                hostile_corridor: &self.hostile_corridor,
                friendly_bridge: &self.friendly_bridge,
                hostile_bridge: &self.hostile_bridge,
            };
            !paint_active && is_stance_goal_at(kernel, &masks, team, gx, gy)
        };
        if hold {
            self.agents[agent_i].goal_gx = gx;
            self.agents[agent_i].goal_gy = gy;
            self.agents[agent_i].deploy_path = vec![start_idx];
            self.agents[agent_i].deploy_path_pos = 0;
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            return;
        }

        self.nav_search.ensure_capacity(kernel.tile_count);
        self.clear_goal_claim_for_agent(except_id);

        // Prefer free goals only when team free-miss cooldown is clear (C1/C4).
        let team_i = team as usize;
        let try_free = team_i < self.free_miss_cd.len() && self.free_miss_cd[team_i] == 0;
        let has_land_goals = self.team_has_land_advance_goal(kernel, team);
        let mut outcome = if try_free {
            #[cfg(test)]
            {
                self.free_goal_bfs_calls = self.free_goal_bfs_calls.wrapping_add(1);
            }
            Self::find_advance_path(
                &mut self.nav_search,
                kernel,
                &self.friendly_corridor,
                &self.hostile_corridor,
                &self.friendly_bridge,
                &self.hostile_bridge,
                &self.occupant_at,
                &self.goal_claims,
                gx,
                gy,
                start_idx,
                team,
                except_id,
                true,
                has_land_goals,
            )
        } else {
            None
        };
        if try_free && outcome.is_none() {
            // No free goal found → skip free BFS for a few replan cycles (FPS).
            if team_i < self.free_miss_cd.len() {
                self.free_miss_cd[team_i] = FREE_GOAL_MISS_SKIP_TICKS;
            }
        }
        if outcome.is_none() {
            #[cfg(test)]
            {
                self.contested_bfs_calls = self.contested_bfs_calls.wrapping_add(1);
            }
            outcome = Self::find_advance_path(
                &mut self.nav_search,
                kernel,
                &self.friendly_corridor,
                &self.hostile_corridor,
                &self.friendly_bridge,
                &self.hostile_bridge,
                &self.occupant_at,
                &self.goal_claims,
                gx,
                gy,
                start_idx,
                team,
                except_id,
                false,
                has_land_goals,
            );
        }

        if let Some(route) = outcome {
            if route.path.len() >= 2 {
                let w = kernel.grid_w;
                let goal_idx = *route.path.last().unwrap();
                let (goal_x, goal_y) = Self::grid_from_idx(goal_idx, w);
                self.agents[agent_i].goal_gx = goal_x;
                self.agents[agent_i].goal_gy = goal_y;
                self.claim_goal(goal_x, goal_y, except_id);
                self.agents[agent_i].deploy_path = route.path;
                self.agents[agent_i].deploy_path_pos = 0;
                self.sync_step_from_deploy_path(kernel, agent_i);
                return;
            }
            if route.path.len() == 1 {
                let w = kernel.grid_w;
                let goal_idx = route.path[0];
                let (goal_x, goal_y) = Self::grid_from_idx(goal_idx, w);
                self.agents[agent_i].goal_gx = goal_x;
                self.agents[agent_i].goal_gy = goal_y;
                self.claim_goal(goal_x, goal_y, except_id);
                self.agents[agent_i].deploy_path = route.path;
                self.agents[agent_i].deploy_path_pos = 0;
                self.agents[agent_i].step_gx = -1;
                self.agents[agent_i].step_gy = -1;
                return;
            }
        }

        self.agents[agent_i].step_gx = -1;
        self.agents[agent_i].step_gy = -1;
        self.agents[agent_i].deploy_path.clear();
        self.agents[agent_i].deploy_path_pos = 0;
    }

    fn steer_agent_to_paint(&mut self, kernel: &TerritoryKernel, agent_i: usize) {
        let team = self.agents[agent_i].team;
        let gx = self.agents[agent_i].gx;
        let gy = self.agents[agent_i].gy;
        let except_id = self.agents[agent_i].id;
        let start_idx = kernel.cell_index(gx, gy);
        if start_idx < 0 || !kernel.paint_orders_live(team) {
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            return;
        }
        let start_ui = start_idx as usize;
        self.clear_goal_claim_for_agent(except_id);
        if kernel.paint_cell_marked(team, gx, gy)
            && kernel.is_land_idx(start_ui)
            && start_ui < kernel.owners.len()
            && kernel.owners[start_ui] != team
        {
            self.agents[agent_i].goal_gx = gx;
            self.agents[agent_i].goal_gy = gy;
            self.agents[agent_i].deploy_path = vec![start_idx];
            self.agents[agent_i].deploy_path_pos = 0;
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            return;
        }
        let Some(next) = kernel.paint_flow_next_idx(team, start_ui) else {
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            self.agents[agent_i].deploy_path.clear();
            self.agents[agent_i].deploy_path_pos = 0;
            return;
        };
        let (sx, sy) = kernel.grid_from_idx(next as i32);
        self.agents[agent_i].goal_gx = sx;
        self.agents[agent_i].goal_gy = sy;
        self.agents[agent_i].step_gx = sx;
        self.agents[agent_i].step_gy = sy;
        self.agents[agent_i].deploy_path.clear();
        self.agents[agent_i].deploy_path_pos = 0;
    }

    fn claim_goal(&mut self, gx: i32, gy: i32, agent_id: u32) {
        self.goal_claims.insert((gx, gy), agent_id);
    }

    fn clear_goal_claim_for_agent(&mut self, agent_id: u32) {
        self.goal_claims.retain(|_, &mut id| id != agent_id);
    }

    fn find_advance_path(
        nav_search: &mut SearchKernel,
        kernel: &TerritoryKernel,
        friendly_corridor: &[u8],
        hostile_corridor: &[u8],
        friendly_bridge: &[u8],
        hostile_bridge: &[u8],
        occupant_at: &HashMap<CellKey, u32>,
        goal_claims: &HashMap<CellKey, u32>,
        gx: i32,
        gy: i32,
        start_idx: i32,
        team: u8,
        except_id: u32,
        free_goals_only: bool,
        has_land_goals: bool,
    ) -> Option<RoutePath> {
        let masks = AgentNavMasks {
            friendly_corridor,
            hostile_corridor,
            friendly_bridge,
            hostile_bridge,
        };
        if !free_goals_only {
            return run_nav_rule(
                nav_search,
                kernel,
                &masks,
                gx,
                gy,
                team,
                NAV_RULE_INFANTRY_ADVANCE,
            )
            .path;
        }
        let rule = rule_by_id(NAV_RULE_INFANTRY_ADVANCE)?;
        let view = BattleNavView::new(kernel, &masks, team);
        let w = kernel.grid_w.max(1);
        let is_free_cell = |idx: usize| {
            let cx = (idx as i32) % w;
            let cy = (idx as i32) / w;
            let key = (cx, cy);
            match occupant_at.get(&key) {
                Some(&oid) if oid != except_id => return false,
                _ => {}
            }
            match goal_claims.get(&key) {
                Some(&cid) if cid != except_id => false,
                _ => true,
            }
        };
        // No claimable unowned land → ferry only (avoid burning expand on owned continent).
        if !has_land_goals {
            let ferry_ctx = crate::pathfind::nav_rules::infantry_ferry_context(kernel.tile_count);
            let is_free_ferry = |idx: usize| view.is_ferry_landing_goal(idx) && is_free_cell(idx);
            return nav_search
                .find_nearest_goal(&view, &[start_idx], ferry_ctx, is_free_ferry)
                .map(|(path, _)| path);
        }
        let is_free_stance = |idx: usize| view.is_stance_goal(idx) && is_free_cell(idx);
        if let Some((path, _)) =
            nav_search.find_nearest_goal(&view, &[start_idx], rule.search, is_free_stance)
        {
            return Some(path);
        }
        // Land goals exist but free land miss → do NOT ferry (contested land-only follows).
        // Ferry only when no land advance goals remain for the team.
        None
    }

    fn holding_at_goal(&self, kernel: &TerritoryKernel, team: u8, agent: &Agent) -> bool {
        if kernel.paint_orders_live(team) {
            let idx = kernel.cell_index(agent.gx, agent.gy);
            if idx < 0 {
                return false;
            }
            let ui = idx as usize;
            return kernel.paint_cell_marked(team, agent.gx, agent.gy)
                && kernel.is_land_idx(ui)
                && ui < kernel.owners.len()
                && kernel.owners[ui] != team;
        }
        let masks = AgentNavMasks {
            friendly_corridor: &self.friendly_corridor,
            hostile_corridor: &self.hostile_corridor,
            friendly_bridge: &self.friendly_bridge,
            hostile_bridge: &self.hostile_bridge,
        };
        is_stance_goal_at(kernel, &masks, team, agent.gx, agent.gy)
    }

    fn is_network_cell(&self, team: u8, idx: usize) -> bool {
        let (corridor, bridge) = if team == OWNER_FRIENDLY {
            (&self.friendly_corridor, &self.friendly_bridge)
        } else {
            (&self.hostile_corridor, &self.hostile_bridge)
        };
        (idx < corridor.len() && corridor[idx] != 0) || (idx < bridge.len() && bridge[idx] != 0)
    }

    fn sync_step_from_deploy_path(&mut self, kernel: &TerritoryKernel, agent_i: usize) {
        let team = self.agents[agent_i].team;
        if self.holding_at_goal(kernel, team, &self.agents[agent_i]) {
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            return;
        }

        let w = kernel.grid_w;
        let pos = self.agents[agent_i].deploy_path_pos;
        let path = self.agents[agent_i].deploy_path.clone();
        if pos + 1 < path.len() {
            let next_idx = path[pos + 1];
            let (sx, sy) = Self::grid_from_idx(next_idx, w);
            self.agents[agent_i].step_gx = sx;
            self.agents[agent_i].step_gy = sy;
        } else {
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
        }
    }

    fn advance_deploy_path_after_move(&mut self, kernel: &TerritoryKernel, agent_i: usize) {
        let cur_idx = kernel.cell_index(self.agents[agent_i].gx, self.agents[agent_i].gy);
        if cur_idx < 0 {
            return;
        }
        let path = &self.agents[agent_i].deploy_path;
        let pos = self.agents[agent_i].deploy_path_pos;
        if pos + 1 < path.len() && path[pos + 1] == cur_idx {
            self.agents[agent_i].deploy_path_pos = pos + 1;
        } else if !path.is_empty() && path[pos] != cur_idx {
            if let Some(found) = path.iter().position(|&c| c == cur_idx) {
                self.agents[agent_i].deploy_path_pos = found;
            }
        }
    }

    fn plan_retreat_route(
        &mut self,
        kernel: &TerritoryKernel,
        team: u8,
        start_gx: i32,
        start_gy: i32,
    ) -> Option<(i32, i32, i32, i32)> {
        self.nav_search.ensure_capacity(kernel.tile_count);
        let masks = AgentNavMasks {
            friendly_corridor: &self.friendly_corridor,
            hostile_corridor: &self.hostile_corridor,
            friendly_bridge: &self.friendly_bridge,
            hostile_bridge: &self.hostile_bridge,
        };
        let outcome = run_nav_rule(
            &mut self.nav_search,
            kernel,
            &masks,
            start_gx,
            start_gy,
            team,
            NAV_RULE_INFANTRY_RETREAT,
        );
        let route = outcome.path?;
        if route.path.len() >= 2 {
            let w = kernel.grid_w;
            let goal_idx = *route.path.last().unwrap();
            let (goal_x, goal_y) = Self::grid_from_idx(goal_idx, w);
            let (step_x, step_y) = Self::grid_from_idx(route.path[1], w);
            return Some((goal_x, goal_y, step_x, step_y));
        }
        None
    }

    fn grid_from_idx(idx: i32, w: i32) -> (i32, i32) {
        (idx % w, idx / w)
    }

    fn adjacent_to_team_supply(&self, kernel: &TerritoryKernel, team: u8, gx: i32, gy: i32) -> bool {
        let idx = kernel.cell_index(gx, gy);
        if idx < 0 {
            return false;
        }
        let (corridor, bridge) = if team == OWNER_FRIENDLY {
            (&self.friendly_corridor, &self.friendly_bridge)
        } else {
            (&self.hostile_corridor, &self.hostile_bridge)
        };
        let mut found = false;
        kernel.for_each_neighbor_idx(idx as usize, |nui| {
            if found {
                return;
            }
            let o = kernel.owners[nui];
            if o == team || o == OWNER_NEUTRAL || o == OWNER_CONTESTED {
                found = true;
                return;
            }
            if (nui < corridor.len() && corridor[nui] != 0)
                || (nui < bridge.len() && bridge[nui] != 0)
            {
                found = true;
            }
        });
        found
    }

    fn remove_dead(&mut self, dead: &[u32]) {
        let clear: Vec<(i32, i32, u32)> = self
            .agents
            .iter()
            .filter(|a| dead.contains(&a.id))
            .map(|a| (a.gx, a.gy, a.id))
            .collect();
        for (gx, gy, id) in clear {
            self.clear_occupant(gx, gy, id);
            self.clear_goal_claim_for_agent(id);
        }
        if !dead.is_empty() {
            // Free tiles opened → allow free-goal search again.
            self.free_miss_cd = [0; 3];
            self.land_advance_goal_cache = [None; 3];
        }
        self.agents.retain(|a| {
            if dead.contains(&a.id) {
                if !a.orphan {
                    if let Some(c) = self.living_by_barracks.get_mut(&a.barracks_id) {
                        *c = c.saturating_sub(1);
                    }
                }
                false
            } else {
                true
            }
        });
    }

    fn set_occupant(&mut self, gx: i32, gy: i32, id: u32) {
        self.occupant_at.insert((gx, gy), id);
    }

    fn clear_occupant(&mut self, gx: i32, gy: i32, id: u32) {
        if self.occupant_at.get(&(gx, gy)).copied() == Some(id) {
            self.occupant_at.remove(&(gx, gy));
        }
    }

    fn move_occupant(&mut self, from_gx: i32, from_gy: i32, to_gx: i32, to_gy: i32, id: u32) {
        self.clear_occupant(from_gx, from_gy, id);
        self.set_occupant(to_gx, to_gy, id);
    }

    /// True if another living soldier already occupies this ground cell (O(1) map).
    fn ground_occupied_by_other(&self, gx: i32, gy: i32, except_id: u32) -> bool {
        match self.occupant_at.get(&(gx, gy)) {
            Some(&id) => id != except_id,
            None => false,
        }
    }

    fn find_spawn_cell(
        &self,
        kernel: &TerritoryKernel,
        team: u8,
        bx: i32,
        by: i32,
    ) -> Option<(i32, i32)> {
        let bidx = kernel.cell_index(bx, by);
        if bidx < 0 {
            return None;
        }
        let w = kernel.grid_w;
        let mut network_pick: Option<(i32, i32)> = None;
        let mut team_pick: Option<(i32, i32)> = None;
        kernel.for_each_neighbor_idx(bidx as usize, |nui| {
            // Sphere / graph topology: cell id is the index; rect maps use row-major.
            let (gx, gy) = if kernel.graph_topology {
                (nui as i32, 0)
            } else {
                (nui as i32 % w, nui as i32 / w)
            };
            if !self.is_passable(kernel, team, gx, gy) {
                return;
            }
            if self.ground_occupied_by_other(gx, gy, u32::MAX) {
                return;
            }
            if self.is_network_cell(team, nui) && kernel.owners[nui] == team && network_pick.is_none()
            {
                network_pick = Some((gx, gy));
            } else if kernel.owners[nui] == team && team_pick.is_none() {
                team_pick = Some((gx, gy));
            }
        });
        if let Some(pick) = network_pick.or(team_pick) {
            return Some(pick);
        }
        // Sphere HQ seeds a single owned cell — allow spawn on the barracks tile itself.
        let bui = bidx as usize;
        if bui < kernel.owners.len()
            && kernel.owners[bui] == team
            && self.is_passable(kernel, team, bx, by)
            && !self.ground_occupied_by_other(bx, by, u32::MAX)
        {
            return Some((bx, by));
        }
        None
    }

    fn is_passable_at(
        kernel: &TerritoryKernel,
        friendly_corridor: &[u8],
        hostile_corridor: &[u8],
        friendly_bridge: &[u8],
        hostile_bridge: &[u8],
        team: u8,
        gx: i32,
        gy: i32,
    ) -> bool {
        let idx = kernel.cell_index(gx, gy);
        if idx < 0 {
            return false;
        }
        let ui = idx as usize;
        if ui >= kernel.tile_count {
            return false;
        }
        if kernel.claimable_mask[ui] != 0 {
            return true;
        }
        let (corridor, bridge) = if team == OWNER_FRIENDLY {
            (friendly_corridor, friendly_bridge)
        } else {
            (hostile_corridor, hostile_bridge)
        };
        if ui < corridor.len() && corridor[ui] != 0 {
            return true;
        }
        if ui < bridge.len() && bridge[ui] != 0 {
            return true;
        }
        // Ferry transit: open water and unclaimable land (pathfinder gates when water is used).
        if !kernel.land_mask.is_empty() {
            return ui < kernel.land_mask.len();
        }
        false
    }

    /// After ferrying onto a new landmass, flood claimable like a bridge beachhead.
    /// Floods contiguous *land* only — never across water.
    fn maybe_ferry_beachhead(
        &mut self,
        kernel: &mut TerritoryKernel,
        team: u8,
        gx: i32,
        gy: i32,
    ) {
        let idx = kernel.cell_index(gx, gy);
        if idx < 0 {
            return;
        }
        let ui = idx as usize;
        if ui >= kernel.tile_count {
            return;
        }
        let is_land = if !kernel.land_mask.is_empty() {
            ui < kernel.land_mask.len() && kernel.land_mask[ui] != 0
        } else {
            false
        };
        if !is_land {
            return;
        }
        if kernel.claimable_mask[ui] != 0 && kernel.owners[ui] != OWNER_UNCLAIMABLE {
            return;
        }
        let result = kernel.extend_beachhead_from_landing(gx, gy, team);
        if result.changed {
            self.beachhead_expanded = true;
        }
    }

    fn is_passable(&self, kernel: &TerritoryKernel, team: u8, gx: i32, gy: i32) -> bool {
        Self::is_passable_at(
            kernel,
            &self.friendly_corridor,
            &self.hostile_corridor,
            &self.friendly_bridge,
            &self.hostile_bridge,
            team,
            gx,
            gy,
        )
    }

    fn apply_shoot_to_kernel(
        kernel: &mut TerritoryKernel,
        team: u8,
        gx: i32,
        gy: i32,
        erode: f32,
        friendly_corridor: &[u8],
        hostile_corridor: &[u8],
        friendly_bridge: &[u8],
        hostile_bridge: &[u8],
    ) {
        if erode <= 0.0 {
            return;
        }
        let enemy = enemy_team(team);
        let shooter_idx = kernel.cell_index(gx, gy);
        if shooter_idx < 0 {
            return;
        }
        let shooter_ui = shooter_idx as usize;
        let (corridor, bridge) = if team == OWNER_FRIENDLY {
            (friendly_corridor, friendly_bridge)
        } else {
            (hostile_corridor, hostile_bridge)
        };
        let shooter_on_infra = (shooter_ui < corridor.len() && corridor[shooter_ui] != 0)
            || (shooter_ui < bridge.len() && bridge[shooter_ui] != 0);
        let w = kernel.grid_w;
        let mut neighbor_scratch = Vec::with_capacity(6);
        kernel.collect_neighbors(shooter_ui, &mut neighbor_scratch);
        for &nui in &neighbor_scratch {
            if kernel.claimable_mask[nui] == 0 {
                continue;
            }
            let owner = kernel.owners[nui];
            // Majority lock: tip enemy / neutral / legacy contested tiles.
            if owner != enemy && owner != OWNER_NEUTRAL && owner != OWNER_CONTESTED {
                continue;
            }
            let nx = nui as i32 % w;
            let ny = nui as i32 / w;
            let on_front = adjacent_to_team_supply_at(
                kernel,
                team,
                nx,
                ny,
                friendly_corridor,
                hostile_corridor,
                friendly_bridge,
                hostile_bridge,
            );
            if !on_front && !(shooter_on_infra && grid_distance(kernel, gx, gy, nx, ny) == 1) {
                continue;
            }
            if team == OWNER_FRIENDLY {
                kernel.pressure_hostile[nui] = (kernel.pressure_hostile[nui] - erode).max(0.0);
                kernel.pressure_friendly[nui] += erode * 0.35;
            } else {
                kernel.pressure_friendly[nui] = (kernel.pressure_friendly[nui] - erode).max(0.0);
                kernel.pressure_hostile[nui] += erode * 0.35;
            }
            kernel.mark_pressure_dirty(nui);
        }
    }
}

fn grid_distance(kernel: &TerritoryKernel, x0: i32, y0: i32, x1: i32, y1: i32) -> i32 {
    if kernel.graph_topology {
        return graph_hop_distance(kernel, x0, y0, x1, y1);
    }
    let mut dx = (x0 - x1).abs();
    if kernel.wrap_longitude {
        dx = dx.min(kernel.grid_w - dx);
    }
    dx + (y0 - y1).abs()
}

const GRAPH_HOP_DISTANCE_CAP: i32 = 64;

fn graph_hop_distance(kernel: &TerritoryKernel, x0: i32, y0: i32, x1: i32, y1: i32) -> i32 {
    let start = kernel.cell_index(x0, y0);
    let goal = kernel.cell_index(x1, y1);
    if start < 0 || goal < 0 {
        return i32::MAX;
    }
    if start == goal {
        return 0;
    }
    let mut depth = vec![-1i32; kernel.tile_count];
    let start_ui = start as usize;
    depth[start_ui] = 0;
    let mut queue = vec![start_ui];
    let mut head = 0usize;
    let mut neighbor_scratch = Vec::with_capacity(6);
    while head < queue.len() {
        let cur_ui = queue[head];
        head += 1;
        let d = depth[cur_ui];
        if d >= GRAPH_HOP_DISTANCE_CAP {
            continue;
        }
        kernel.collect_neighbors(cur_ui, &mut neighbor_scratch);
        for &nui in &neighbor_scratch {
            if depth[nui] >= 0 {
                continue;
            }
            if nui as i32 == goal {
                return d + 1;
            }
            depth[nui] = d + 1;
            queue.push(nui);
        }
    }
    i32::MAX
}

fn enemy_team(team: u8) -> u8 {
    if team == OWNER_FRIENDLY {
        OWNER_HOSTILE
    } else {
        OWNER_FRIENDLY
    }
}

fn adjacent_to_team_supply_at(
    kernel: &TerritoryKernel,
    team: u8,
    gx: i32,
    gy: i32,
    friendly_corridor: &[u8],
    hostile_corridor: &[u8],
    friendly_bridge: &[u8],
    hostile_bridge: &[u8],
) -> bool {
    let idx = kernel.cell_index(gx, gy);
    if idx < 0 {
        return false;
    }
    let (corridor, bridge) = if team == OWNER_FRIENDLY {
        (friendly_corridor, friendly_bridge)
    } else {
        (hostile_corridor, hostile_bridge)
    };
    let mut found = false;
    kernel.for_each_neighbor_idx(idx as usize, |nui| {
        if found {
            return;
        }
        let o = kernel.owners[nui];
        if o == team || o == OWNER_NEUTRAL || o == OWNER_CONTESTED {
            found = true;
            return;
        }
        if (nui < corridor.len() && corridor[nui] != 0)
            || (nui < bridge.len() && bridge[nui] != 0)
        {
            found = true;
        }
    });
    found
}

fn territory_dps_at(kernel: &TerritoryKernel, team: u8, idx: usize) -> f32 {
    if idx >= kernel.tile_count {
        return 0.0;
    }
    let owner = kernel.owners[idx];
    let pf = kernel.pressure_friendly[idx];
    let ph = kernel.pressure_hostile[idx];
    let ratio = CLAIM_DOMINANCE_RATIO
        * if idx < kernel.claim_ratio_mult.len() {
            kernel.claim_ratio_mult[idx]
        } else {
            1.0
        };

    if team == OWNER_FRIENDLY {
        if owner == OWNER_HOSTILE {
            return HOSTILE_TERRITORY_DPS;
        }
        if ph >= MIN_CLAIM_PRESSURE && ph > pf * ratio {
            return HOSTILE_TERRITORY_DPS;
        }
    } else {
        if owner == OWNER_FRIENDLY {
            return HOSTILE_TERRITORY_DPS;
        }
        if pf >= MIN_CLAIM_PRESSURE && pf > ph * ratio {
            return HOSTILE_TERRITORY_DPS;
        }
    }
    0.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::{TerritoryKernel, OWNER_FRIENDLY, OWNER_NEUTRAL};

    fn line_graph_kernel() -> TerritoryKernel {
        let n = 4;
        let mut neighbors = vec![[-1i32; 6]; n];
        let mut neighbor_count = vec![0u8; n];
        neighbors[0] = [1, -1, -1, -1, -1, -1];
        neighbor_count[0] = 1;
        neighbors[1] = [0, 2, -1, -1, -1, -1];
        neighbor_count[1] = 2;
        neighbors[2] = [1, 3, -1, -1, -1, -1];
        neighbor_count[2] = 2;
        neighbors[3] = [2, -1, -1, -1, -1, -1];
        neighbor_count[3] = 1;
        let mut k = TerritoryKernel::new(
            n as i32,
            1,
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
        k.set_graph_neighbors(neighbors, neighbor_count);
        k
    }

    #[test]
    fn graph_hop_distance_follows_edges() {
        let k = line_graph_kernel();
        assert_eq!(graph_hop_distance(&k, 0, 0, 3, 0), 3);
        assert_eq!(grid_distance(&k, 0, 0, 3, 0), 3);
    }

    #[test]
    fn graph_neighbor_supply_detects_team_owned_neighbor() {
        let mut k = line_graph_kernel();
        k.owners[3] = OWNER_FRIENDLY;
        let corridor: [u8; 4] = [0; 4];
        let bridge: [u8; 4] = [0; 4];
        assert!(adjacent_to_team_supply_at(
            &k,
            OWNER_FRIENDLY,
            2,
            0,
            &corridor,
            &corridor,
            &bridge,
            &bridge,
        ));
    }

    fn push_test_agent(layer: &mut AgentLayer, id: u32, team: u8, gx: i32, gy: i32) {
        layer.agents.push(Agent {
            id,
            team,
            barracks_id: 1,
            gx,
            gy,
            hp: 40.0,
            orphan: false,
            version: 1,
            goal_gx: gx,
            goal_gy: gy,
            step_gx: -1,
            step_gy: -1,
            move_accum: 0.0,
            retarget_cd: 0,
            deploy_path: Vec::new(),
            deploy_path_pos: 0,
            goal_nav_stamp: 0,
            goal_nav_masks_epoch: 0,
        });
        layer.set_occupant(gx, gy, id);
    }

    /// C1/C4: when free_miss_cd > 0, replan must not run free-goal BFS (single contested expand).
    #[test]
    fn free_miss_cd_skips_free_goal_bfs() {
        let mut k = line_graph_kernel();
        // No claimable → no stance hold (would early-return before free/contested BFS).
        k.claimable_mask = vec![0u8; 4];
        k.owners = vec![OWNER_FRIENDLY; 4];
        let mut layer = AgentLayer::new(AgentConfig::default());
        layer.friendly_corridor = vec![0; 4];
        layer.hostile_corridor = vec![0; 4];
        layer.friendly_bridge = vec![0; 4];
        layer.hostile_bridge = vec![0; 4];
        push_test_agent(&mut layer, 1, OWNER_FRIENDLY, 0, 0);

        // Exhausted free goals: skip free search.
        layer.free_miss_cd[OWNER_FRIENDLY as usize] = FREE_GOAL_MISS_SKIP_TICKS;
        layer.free_goal_bfs_calls = 0;
        layer.contested_bfs_calls = 0;
        layer.replan_route(&k, 0);
        assert_eq!(
            layer.free_goal_bfs_calls, 0,
            "free_miss_cd must skip free-goal BFS"
        );
        assert_eq!(
            layer.contested_bfs_calls, 1,
            "replan should run exactly one contested expand when free skipped"
        );

        // Cooldown clear: free search runs first (may miss then contested).
        layer.free_miss_cd[OWNER_FRIENDLY as usize] = 0;
        layer.free_goal_bfs_calls = 0;
        layer.contested_bfs_calls = 0;
        layer.replan_route(&k, 0);
        assert_eq!(
            layer.free_goal_bfs_calls, 1,
            "free search must run when free_miss_cd is 0"
        );
        // No free stance on this map → free miss arms skip + contested follows.
        assert_eq!(layer.contested_bfs_calls, 1);
        assert!(
            layer.free_miss_cd[OWNER_FRIENDLY as usize] > 0,
            "free miss must arm free_miss_cd for subsequent replans"
        );
    }

    /// Stuck / no-path replan must back off — never leave retarget_cd at 0.
    #[test]
    fn stuck_replan_sets_retarget_backoff() {
        let mut k = line_graph_kernel();
        k.claimable_mask = vec![0u8; 4];
        k.owners = vec![OWNER_FRIENDLY; 4];
        let mut layer = AgentLayer::new(AgentConfig::default());
        layer.friendly_corridor = vec![0; 4];
        layer.hostile_corridor = vec![0; 4];
        layer.friendly_bridge = vec![0; 4];
        layer.hostile_bridge = vec![0; 4];
        push_test_agent(&mut layer, 1, OWNER_FRIENDLY, 0, 0);
        assert_eq!(layer.agents[0].step_gx, -1);
        layer.replan_route(&k, 0);
        layer.finish_replan(&k, 0);
        assert!(
            layer.agents[0].retarget_cd > 0,
            "failed replan must set retarget_cd backoff, got {}",
            layer.agents[0].retarget_cd
        );
        assert!(
            layer.agents[0].retarget_cd >= layer.config.replan_fallback_rounds,
            "backoff should be at least replan_fallback_rounds"
        );
    }

    #[test]
    fn paint_flow_steers_every_soldier_toward_brush() {
        let mut k = line_graph_kernel();
        k.owners = vec![OWNER_HOSTILE; 4];
        k.owners[3] = OWNER_NEUTRAL;
        assert!(k.begin_paint_stroke(OWNER_FRIENDLY));
        k.paint_land[OWNER_FRIENDLY as usize].fill(0);
        k.paint_land[OWNER_FRIENDLY as usize][3] = 1;
        k.paint_kind[OWNER_FRIENDLY as usize] = crate::sim::PAINT_AREA;
        k.commit_paint_stroke(OWNER_FRIENDLY);

        let mut layer = AgentLayer::new(AgentConfig::default());
        layer.friendly_corridor = vec![0; 4];
        layer.hostile_corridor = vec![0; 4];
        layer.friendly_bridge = vec![0; 4];
        layer.hostile_bridge = vec![0; 4];
        push_test_agent(&mut layer, 1, OWNER_FRIENDLY, 0, 0);
        layer.agents[0].step_gx = 0;
        layer.agents[0].step_gy = 0;
        layer.notify_paint_orders(&k, OWNER_FRIENDLY);
        assert_eq!(
            (layer.agents[0].step_gx, layer.agents[0].step_gy),
            (1, 0),
            "release must turn the soldier toward painted land"
        );

        layer.replan_route(&k, 0);
        assert_eq!(
            (layer.agents[0].step_gx, layer.agents[0].step_gy),
            (1, 0),
            "paint must override retreat back to the local front"
        );

        layer.agents[0].move_accum = 1.0;
        layer.tick(&mut k);
        assert_eq!(layer.agents[0].gx, 1);
        assert_eq!(layer.agents[0].gy, 0);
    }
}
