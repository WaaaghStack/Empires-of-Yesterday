//! World Conquest soldiers — path via nav rules toward frontier stance tiles.

use crate::pathfind::battle_nav::AgentNavMasks;
use crate::pathfind::kernel::SearchKernel;
use crate::pathfind::nav_rules::{
    is_stance_goal_at, run_nav_rule, NAV_RULE_INFANTRY_ADVANCE, NAV_RULE_INFANTRY_RETREAT,
};
use crate::sim::{
    TerritoryKernel, OWNER_CONTESTED, OWNER_FRIENDLY, OWNER_HOSTILE, OWNER_NEUTRAL,
    MIN_CLAIM_PRESSURE,
};

const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];
const HOSTILE_TERRITORY_DPS: f32 = 3.0;
const CLAIM_DOMINANCE_RATIO: f32 = 1.15;
const AURA_STACK_CAP: u32 = 5;

#[derive(Clone, Debug)]
pub struct AgentConfig {
    pub global_cap: u32,
    pub per_barracks_cap: u32,
    pub max_hp: f32,
    pub move_cells_per_sec: f32,
    pub infra_move_mult: f32,
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
            infra_move_mult: 3.0,
            aura_pressure: 0.48,
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
    living_by_barracks: std::collections::HashMap<i32, u32>,
    next_id: u32,
    pub friendly_corridor: Vec<u8>,
    pub hostile_corridor: Vec<u8>,
    pub friendly_bridge: Vec<u8>,
    pub hostile_bridge: Vec<u8>,
    nav_masks_epoch: u32,
    replan_cursor: usize,
    nav_search: SearchKernel,
}

impl AgentLayer {
    pub fn new(config: AgentConfig) -> Self {
        Self {
            agents: Vec::new(),
            config,
            friendly_deficit_dps: 0.0,
            hostile_deficit_dps: 0.0,
            living_by_barracks: std::collections::HashMap::new(),
            next_id: 1,
            friendly_corridor: Vec::new(),
            hostile_corridor: Vec::new(),
            friendly_bridge: Vec::new(),
            hostile_bridge: Vec::new(),
            nav_masks_epoch: 0,
            replan_cursor: 0,
            nav_search: SearchKernel::new(1),
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

        self.run_budgeted_replans(kernel);

        for i in 0..n {
            let team = self.agents[i].team;
            let gx = self.agents[i].gx;
            let gy = self.agents[i].gy;
            let mut move_rate = self.config.move_cells_per_sec;
            let idx = kernel.cell_index(gx, gy);
            if idx >= 0 {
                let ui = idx as usize;
                if ui < kernel.tile_count && self.is_network_cell(team, ui) {
                    move_rate *= self.config.infra_move_mult;
                }
            }
            self.agents[i].move_accum += move_rate * dt;
            while self.agents[i].move_accum >= 1.0 {
                self.agents[i].move_accum -= 1.0;
                let sx = self.agents[i].step_gx;
                let sy = self.agents[i].step_gy;
                if sx >= 0 && (sx != self.agents[i].gx || sy != self.agents[i].gy) {
                    if !self.is_passable(kernel, team, sx, sy) {
                        self.agents[i].step_gx = -1;
                        self.agents[i].step_gy = -1;
                        self.agents[i].retarget_cd = 0;
                        break;
                    }
                    self.agents[i].gx = sx;
                    self.agents[i].gy = sy;
                    self.advance_deploy_path_after_move(kernel, i);
                    self.sync_step_from_deploy_path(kernel, i);
                } else if self.holding_at_goal(kernel, team, &self.agents[i]) {
                    break;
                } else {
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

        let mut urgent: Vec<usize> = Vec::new();
        let mut normal: Vec<usize> = Vec::new();

        for i in 0..n {
            let team = self.agents[i].team;
            let holding = self.holding_at_goal(kernel, team, &self.agents[i]);
            let stuck = self.agents[i].step_gx < 0 && !holding;
            let nav_stale = self.nav_stale_for_agent(kernel, &self.agents[i]);
            let fallback_due = self.agents[i].retarget_cd <= 0;

            if stuck {
                urgent.push(i);
                continue;
            }

            if holding {
                if nav_stale {
                    normal.push(i);
                } else if fallback_due {
                    self.agents[i].retarget_cd -= 1;
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

        let mut budget = self.config.replans_per_tick.max(1) as usize;
        if !urgent.is_empty() {
            budget = budget.max(urgent.len().min(24));
        }
        let urgent_cap = budget.min(urgent.len());
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
        let (gx, gy, goal_gx, goal_gy, id, team) = {
            let agent = &self.agents[agent_i];
            (
                agent.gx,
                agent.gy,
                agent.goal_gx,
                agent.goal_gy,
                agent.id,
                agent.team,
            )
        };
        let stamp = self.snapshot_nav_stamp(kernel, gx, gy, goal_gx, goal_gy);
        let masks_epoch = self.nav_masks_epoch;
        let stagger = (id as i32 % 7).max(1);
        let holding = self.holding_at_goal(kernel, team, &self.agents[agent_i]);
        let agent = &mut self.agents[agent_i];
        if agent.step_gx >= 0 || holding {
            agent.retarget_cd = self.config.replan_fallback_rounds + stagger;
        } else {
            agent.retarget_cd = 0;
        }
        agent.goal_nav_stamp = stamp;
        agent.goal_nav_masks_epoch = masks_epoch;
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
            max_stamp = max_stamp.max(kernel.nav_stamp_at(x, y));
            for (dx, dy) in CARDINAL {
                max_stamp = max_stamp.max(kernel.nav_stamp_at(x + dx, y + dy));
            }
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
        let start_idx = kernel.cell_index(gx, gy);
        if start_idx < 0 {
            self.agents[agent_i].step_gx = -1;
            self.agents[agent_i].step_gy = -1;
            return;
        }

        let start_ui = start_idx as usize;
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
            is_stance_goal_at(kernel, &masks, team, gx, gy)
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
            gx,
            gy,
            team,
            NAV_RULE_INFANTRY_ADVANCE,
        );

        if let Some(route) = outcome.path {
            if route.path.len() >= 2 {
                let w = kernel.grid_w;
                let goal_idx = *route.path.last().unwrap();
                let (goal_x, goal_y) = Self::grid_from_idx(goal_idx, w);
                self.agents[agent_i].goal_gx = goal_x;
                self.agents[agent_i].goal_gy = goal_y;
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

    fn holding_at_goal(&self, kernel: &TerritoryKernel, team: u8, agent: &Agent) -> bool {
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
        for (dx, dy) in CARDINAL {
            let ni = kernel.cell_index(gx + dx, gy + dy);
            if ni < 0 {
                continue;
            }
            let nui = ni as usize;
            let o = kernel.owners[nui];
            if o == team || o == OWNER_NEUTRAL || o == OWNER_CONTESTED {
                return true;
            }
            if self.is_network_cell(team, nui) {
                return true;
            }
        }
        false
    }

    fn remove_dead(&mut self, dead: &[u32]) {
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

    fn find_spawn_cell(
        &self,
        kernel: &TerritoryKernel,
        team: u8,
        bx: i32,
        by: i32,
    ) -> Option<(i32, i32)> {
        for (dx, dy) in CARDINAL {
            let gx = bx + dx;
            let gy = by + dy;
            if !self.is_passable(kernel, team, gx, gy) {
                continue;
            }
            let idx = kernel.cell_index(gx, gy);
            if idx < 0 {
                continue;
            }
            if self.is_network_cell(team, idx as usize)
                && kernel.owners[idx as usize] == team
            {
                return Some((gx, gy));
            }
        }
        for (dx, dy) in CARDINAL {
            let gx = bx + dx;
            let gy = by + dy;
            if !self.is_passable(kernel, team, gx, gy) {
                continue;
            }
            let idx = kernel.cell_index(gx, gy);
            if idx < 0 {
                continue;
            }
            if kernel.owners[idx as usize] == team {
                return Some((gx, gy));
            }
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
        false
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
        let shooter_on_infra = {
            let shooter_idx = kernel.cell_index(gx, gy);
            if shooter_idx < 0 {
                false
            } else {
                let ui = shooter_idx as usize;
                let (corridor, bridge) = if team == OWNER_FRIENDLY {
                    (friendly_corridor, friendly_bridge)
                } else {
                    (hostile_corridor, hostile_bridge)
                };
                (ui < corridor.len() && corridor[ui] != 0)
                    || (ui < bridge.len() && bridge[ui] != 0)
            }
        };
        for (dx, dy) in CARDINAL {
            let nx = gx + dx;
            let ny = gy + dy;
            let idx = kernel.cell_index(nx, ny);
            if idx < 0 {
                continue;
            }
            let ui = idx as usize;
            if kernel.claimable_mask[ui] == 0 {
                continue;
            }
            if kernel.owners[ui] != enemy && kernel.owners[ui] != OWNER_CONTESTED {
                continue;
            }
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
                kernel.pressure_hostile[ui] = (kernel.pressure_hostile[ui] - erode).max(0.0);
                kernel.pressure_friendly[ui] += erode * 0.35;
            } else {
                kernel.pressure_friendly[ui] = (kernel.pressure_friendly[ui] - erode).max(0.0);
                kernel.pressure_hostile[ui] += erode * 0.35;
            }
        }
    }
}

fn grid_distance(kernel: &TerritoryKernel, x0: i32, y0: i32, x1: i32, y1: i32) -> i32 {
    let mut dx = (x0 - x1).abs();
    if kernel.wrap_longitude {
        dx = dx.min(kernel.grid_w - dx);
    }
    dx + (y0 - y1).abs()
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
    let (corridor, bridge) = if team == OWNER_FRIENDLY {
        (friendly_corridor, friendly_bridge)
    } else {
        (hostile_corridor, hostile_bridge)
    };
    for (dx, dy) in CARDINAL {
        let nx = gx + dx;
        let ny = gy + dy;
        let ni = kernel.cell_index(nx, ny);
        if ni < 0 {
            continue;
        }
        let nui = ni as usize;
        let o = kernel.owners[nui];
        if o == team || o == OWNER_NEUTRAL || o == OWNER_CONTESTED {
            return true;
        }
        if (nui < corridor.len() && corridor[nui] != 0)
            || (nui < bridge.len() && bridge[nui] != 0)
        {
            return true;
        }
    }
    false
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
