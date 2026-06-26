//! Battle / unit navigation rule profiles (soldiers, future military units).

use crate::pathfind::battle_nav::{AgentNavMasks, BattleNavView};
use crate::pathfind::kernel::{RouteContext, RoutePath, SearchKernel, SearchStats};
use crate::route::MAX_PATHFIND_EXPAND;
use crate::sim::TerritoryKernel;

pub type NavRuleId = i32;

/// Infantry — march toward nearest unclaimed claimable land (via land + team infra).
pub const NAV_RULE_INFANTRY_ADVANCE: NavRuleId = 0;
/// Back-compat alias — same rule as advance.
pub const NAV_RULE_INFANTRY_FRONTLINE: NavRuleId = NAV_RULE_INFANTRY_ADVANCE;
/// Retreat to nearest friendly supply when cut off in enemy territory.
pub const NAV_RULE_INFANTRY_RETREAT: NavRuleId = 1;

/// How a military unit selects its search goal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavGoalMode {
    FixedTile,
    NearestUnclaimedLand,
    NearestFriendlySupply,
}

#[derive(Clone, Copy, Debug)]
pub struct NavRule {
    pub id: NavRuleId,
    pub goal_mode: NavGoalMode,
    pub search: RouteContext,
}

const CTX_INFANTRY_BFS: RouteContext = RouteContext {
    allow_water: false,
    infra_only: false,
    use_astar: false,
    land_step: 1,
    water_step: 2,
    max_expand: MAX_PATHFIND_EXPAND,
    corridor: None,
};

pub const NAV_RULES: &[NavRule] = &[
    NavRule {
        id: NAV_RULE_INFANTRY_ADVANCE,
        goal_mode: NavGoalMode::NearestUnclaimedLand,
        search: CTX_INFANTRY_BFS,
    },
    NavRule {
        id: NAV_RULE_INFANTRY_RETREAT,
        goal_mode: NavGoalMode::NearestFriendlySupply,
        search: CTX_INFANTRY_BFS,
    },
];

pub fn rule_by_id(id: NavRuleId) -> Option<&'static NavRule> {
    NAV_RULES.iter().find(|r| r.id == id)
}

pub struct NavRuleOutcome {
    pub path: Option<RoutePath>,
    pub stats: SearchStats,
}

/// Run a soldier nav rule from `start` for `team` using synced corridor/bridge masks.
pub fn run_nav_rule(
    search: &mut SearchKernel,
    territory: &TerritoryKernel,
    masks: &AgentNavMasks<'_>,
    start_gx: i32,
    start_gy: i32,
    team: u8,
    rule_id: NavRuleId,
) -> NavRuleOutcome {
    let rule = match rule_by_id(rule_id) {
        Some(r) => r,
        None => {
            return NavRuleOutcome {
                path: None,
                stats: SearchStats::default(),
            };
        }
    };
    let start = territory.cell_index(start_gx, start_gy);
    if start < 0 {
        return NavRuleOutcome {
            path: None,
            stats: SearchStats::default(),
        };
    }
    let view = BattleNavView::new(territory, masks, team);
    let ctx = rule.search;
    let outcome = match rule.goal_mode {
        NavGoalMode::NearestUnclaimedLand => search.find_nearest_goal(
            &view,
            &[start],
            ctx,
            |idx| view.is_advance_goal(idx),
        ),
        NavGoalMode::NearestFriendlySupply => search.find_nearest_goal(
            &view,
            &[start],
            ctx,
            |idx| view.is_retreat_goal(idx),
        ),
        NavGoalMode::FixedTile => None,
    };
    match outcome {
        Some((path, stats)) => NavRuleOutcome {
            path: Some(path),
            stats,
        },
        None => NavRuleOutcome {
            path: None,
            stats: SearchStats::default(),
        },
    }
}

/// True when a soldier is already standing on an advance-rule goal tile.
pub fn is_advance_goal_at(
    territory: &TerritoryKernel,
    masks: &AgentNavMasks<'_>,
    team: u8,
    gx: i32,
    gy: i32,
) -> bool {
    let idx = territory.cell_index(gx, gy);
    if idx < 0 {
        return false;
    }
    let view = BattleNavView::new(territory, masks, team);
    view.is_advance_goal(idx as usize)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::{
        TerritoryKernel, OWNER_FRIENDLY, OWNER_HOSTILE, OWNER_NEUTRAL,
    };

    fn tiny_kernel() -> TerritoryKernel {
        let w = 7i32;
        let h = 3i32;
        let n = (w * h) as usize;
        let mut claimable = vec![1u8; n];
        let mut owners = vec![OWNER_NEUTRAL; n];
        for gx in 0..2 {
            owners[(0 * w + gx) as usize] = OWNER_FRIENDLY;
        }
        owners[(0 * w + 2) as usize] = OWNER_NEUTRAL;
        for gx in 4..w {
            owners[(0 * w + gx) as usize] = OWNER_NEUTRAL;
            owners[(2 * w + gx) as usize] = OWNER_HOSTILE;
        }
        // water strip at gy=1
        for gx in 0..w {
            let idx = (1 * w + gx) as usize;
            claimable[idx] = 0;
        }
        let mut k = TerritoryKernel::new(
            w,
            h,
            claimable,
            vec![0.0; n],
            vec![1.0; n],
            vec![1.0; n],
            owners,
            vec![0.0; n],
            vec![0.0; n],
            1.0,
            1.0,
            0,
            4,
            Vec::new(),
            2,
            0,
            false,
            false,
            false,
        );
        k.land_mask = (0..n)
            .map(|i| {
                let gy = (i as i32) / w;
                if gy == 1 { 0 } else { 1 }
            })
            .collect();
        k
    }

    fn empty_masks<'a>() -> AgentNavMasks<'a> {
        AgentNavMasks::default()
    }

    #[test]
    fn friendly_advances_to_nearest_neutral() {
        let k = tiny_kernel();
        let masks = empty_masks();
        let mut search = SearchKernel::new(k.tile_count);
        let start_gx = 0;
        let start_gy = 0;
        let out = run_nav_rule(
            &mut search,
            &k,
            &masks,
            start_gx,
            start_gy,
            OWNER_FRIENDLY,
            NAV_RULE_INFANTRY_ADVANCE,
        );
        let path = out.path.expect("path");
        assert!(!path.path.is_empty());
        let goal = *path.path.last().unwrap();
        let view = BattleNavView::new(&k, &masks, OWNER_FRIENDLY);
        assert!(view.is_advance_goal(goal as usize));
    }

    #[test]
    fn hostile_uses_own_team_for_goal() {
        let mut k = tiny_kernel();
        let masks = empty_masks();
        let start_idx = (0 * k.grid_w + 4) as usize;
        k.owners[start_idx] = OWNER_HOSTILE;
        let mut search = SearchKernel::new(k.tile_count);
        let out = run_nav_rule(
            &mut search,
            &k,
            &masks,
            4,
            0,
            OWNER_HOSTILE,
            NAV_RULE_INFANTRY_ADVANCE,
        );
        let path = out.path.expect("hostile path");
        let goal = *path.path.last().unwrap() as usize;
        let view = BattleNavView::new(&k, &masks, OWNER_HOSTILE);
        assert!(view.is_advance_goal(goal));
        assert_ne!(k.owners[goal], OWNER_HOSTILE);
    }

    #[test]
    fn bridge_connects_landmasses() {
        let w = 7i32;
        let h = 3i32;
        let n = (w * h) as usize;
        let mut claimable = vec![1u8; n];
        let mut owners = vec![OWNER_NEUTRAL; n];
        for gx in 0..5 {
            owners[(0 * w + gx) as usize] = OWNER_FRIENDLY;
        }
        for gx in 5..w {
            let top = (0 * w + gx) as usize;
            owners[top] = OWNER_FRIENDLY;
            claimable[top] = 0;
            owners[(2 * w + gx) as usize] = OWNER_NEUTRAL;
        }
        for gx in 0..w {
            let idx = (1 * w + gx) as usize;
            claimable[idx] = 0;
        }
        let mut k = TerritoryKernel::new(
            w,
            h,
            claimable,
            vec![0.0; n],
            vec![1.0; n],
            vec![1.0; n],
            owners,
            vec![0.0; n],
            vec![0.0; n],
            1.0,
            1.0,
            0,
            5,
            Vec::new(),
            5,
            0,
            false,
            false,
            false,
        );
        k.land_mask = (0..n)
            .map(|i| {
                let gy = (i as i32) / w;
                if gy == 1 { 0 } else { 1 }
            })
            .collect();
        let mut bridge = vec![0u8; n];
        for gx in 3..5 {
            let bridge_idx = (1 * w + gx) as usize;
            bridge[bridge_idx] = 1;
            k.claimable_mask[bridge_idx] = 1;
        }
        let masks = AgentNavMasks {
            friendly_corridor: &[],
            hostile_corridor: &[],
            friendly_bridge: &bridge,
            hostile_bridge: &[],
        };
        let mut search = SearchKernel::new(n);
        let out = run_nav_rule(
            &mut search,
            &k,
            &masks,
            0,
            0,
            OWNER_FRIENDLY,
            NAV_RULE_INFANTRY_ADVANCE,
        );
        let path = out.path.expect("bridge path");
        assert!(
            path.path.iter().any(|&c| bridge[(c as usize)] != 0),
            "path should cross bridge"
        );
        let goal = *path.path.last().unwrap() as usize;
        let view = BattleNavView::new(&k, &masks, OWNER_FRIENDLY);
        assert!(view.is_advance_goal(goal));
    }

    #[test]
    fn retreat_finds_friendly_cell() {
        let mut k = tiny_kernel();
        let enemy_idx = (0 * k.grid_w + 0) as usize;
        k.owners[enemy_idx] = OWNER_HOSTILE;
        let masks = empty_masks();
        let mut search = SearchKernel::new(k.tile_count);
        let out = run_nav_rule(
            &mut search,
            &k,
            &masks,
            0,
            0,
            OWNER_FRIENDLY,
            NAV_RULE_INFANTRY_RETREAT,
        );
        let path = out.path.expect("retreat path");
        let goal = *path.path.last().unwrap() as usize;
        let view = BattleNavView::new(&k, &masks, OWNER_FRIENDLY);
        assert!(view.is_retreat_goal(goal));
    }
}
