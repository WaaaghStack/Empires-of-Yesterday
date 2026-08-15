//! Battle / unit navigation rule profiles (soldiers, future military units).

use crate::pathfind::battle_nav::{AgentNavMasks, BattleNavView};
use crate::pathfind::kernel::{RouteContext, RoutePath, SearchKernel, SearchStats};
use crate::route::MAX_PATHFIND_EXPAND;
use crate::sim::TerritoryKernel;

pub type NavRuleId = i32;

/// Infantry — march to nearest safe stance tile one step back from unclaimed land.
pub const NAV_RULE_INFANTRY_ADVANCE: NavRuleId = 0;
/// Back-compat alias — same rule as advance.
pub const NAV_RULE_INFANTRY_FRONTLINE: NavRuleId = NAV_RULE_INFANTRY_ADVANCE;
/// Retreat to nearest friendly supply when cut off in enemy territory.
pub const NAV_RULE_INFANTRY_RETREAT: NavRuleId = 1;
/// Bomber — fly to nearest unowned land (incl. unreached islands) and hold on target.
pub const NAV_RULE_BOMBER_STRIKE: NavRuleId = 2;

/// How a military unit selects its search goal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavGoalMode {
    FixedTile,
    NearestFrontierStance,
    NearestFriendlySupply,
    NearestPressureTarget,
    /// Any non-team land — air ignores ferry claimable reachability.
    NearestAirStrikeTarget,
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
    flight_mode: false,
};

/// Hard expand budget for infantry ferry BFS.
/// Do NOT use `tile_count` (~64k) — late-game free tiles shrink and stuck agents
/// thrash full-map ferry searches, collapsing FPS (sim phase 89→269ms).
pub const FERRY_MAX_EXPAND: usize = 8_000;

/// Same infantry search costs, but water + unclaimable land are passable (ferry).
const CTX_INFANTRY_FERRY: RouteContext = RouteContext {
    allow_water: true,
    infra_only: false,
    use_astar: false,
    land_step: 1,
    water_step: 2,
    max_expand: FERRY_MAX_EXPAND,
    corridor: None,
    flight_mode: false,
};

/// Public ferry search context (agents free-goal soft claims).
/// Fixed expand cap — `tile_count` is ignored (kept for call-site compat).
pub fn infantry_ferry_context(_tile_count: usize) -> RouteContext {
    CTX_INFANTRY_FERRY.with_max_expand(FERRY_MAX_EXPAND.min(MAX_PATHFIND_EXPAND))
}

/// Player paint is a rare order — allow a longer ferry/land search than auto-hunt.
pub const PAINT_MAX_EXPAND: usize = 24_000;

#[allow(dead_code)]
pub fn infantry_paint_context() -> RouteContext {
    CTX_INFANTRY_FERRY.with_max_expand(PAINT_MAX_EXPAND)
}

pub fn any_land_advance_goal(view: &BattleNavView<'_>, tile_count: usize) -> bool {
    for idx in 0..tile_count {
        if view.is_advance_goal(idx) {
            return true;
        }
    }
    false
}

const CTX_BOMBER_BFS: RouteContext = RouteContext {
    allow_water: true,
    infra_only: false,
    use_astar: false,
    land_step: 1,
    water_step: 1,
    max_expand: MAX_PATHFIND_EXPAND,
    corridor: None,
    flight_mode: true,
};

pub const NAV_RULES: &[NavRule] = &[
    NavRule {
        id: NAV_RULE_INFANTRY_ADVANCE,
        goal_mode: NavGoalMode::NearestFrontierStance,
        search: CTX_INFANTRY_BFS,
    },
    NavRule {
        id: NAV_RULE_INFANTRY_RETREAT,
        goal_mode: NavGoalMode::NearestFriendlySupply,
        search: CTX_INFANTRY_BFS,
    },
    NavRule {
        id: NAV_RULE_BOMBER_STRIKE,
        goal_mode: NavGoalMode::NearestAirStrikeTarget,
        search: CTX_BOMBER_BFS,
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
    // No claimable unowned land left anywhere → skip land BFS, ferry immediately.
    if rule_id == NAV_RULE_INFANTRY_ADVANCE
        && !any_land_advance_goal(&view, territory.tile_count)
    {
        return run_ferry_advance_rule(search, territory, masks, start_gx, start_gy, team);
    }
    let ctx = rule.search;
    let outcome = match rule.goal_mode {
        NavGoalMode::NearestFrontierStance => search.find_nearest_goal(
            &view,
            &[start],
            ctx,
            |idx| view.is_stance_goal(idx),
        ),
        NavGoalMode::NearestFriendlySupply => search.find_nearest_goal(
            &view,
            &[start],
            ctx,
            |idx| view.is_retreat_goal(idx),
        ),
        NavGoalMode::NearestPressureTarget => search.find_nearest_goal(
            &view,
            &[start],
            ctx,
            |idx| view.is_advance_goal(idx),
        ),
        NavGoalMode::NearestAirStrikeTarget => search.find_nearest_goal(
            &view,
            &[start],
            ctx,
            |idx| view.is_air_strike_goal(idx),
        ),
        NavGoalMode::FixedTile => None,
    };
    if let Some((path, stats)) = outcome {
        return NavRuleOutcome {
            path: Some(path),
            stats,
        };
    }
    // Land BFS miss while land goals still exist: do NOT fall through to ferry.
    // (Ferry-on-budget-miss was late-game thrash; ferry only when no land goals —
    // handled at the top of this function / free-goal path in agents.)
    NavRuleOutcome {
        path: None,
        stats: SearchStats::default(),
    }
}

/// Infantry ferry: same pathfinder with water allowed; goal is nearest unowned land.
pub fn run_ferry_advance_rule(
    search: &mut SearchKernel,
    territory: &TerritoryKernel,
    masks: &AgentNavMasks<'_>,
    start_gx: i32,
    start_gy: i32,
    team: u8,
) -> NavRuleOutcome {
    let start = territory.cell_index(start_gx, start_gy);
    if start < 0 {
        return NavRuleOutcome {
            path: None,
            stats: SearchStats::default(),
        };
    }
    let view = BattleNavView::new(territory, masks, team);
    let ctx = infantry_ferry_context(territory.tile_count);
    match search.find_nearest_goal(&view, &[start], ctx, |idx| view.is_ferry_landing_goal(idx))
    {
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

/// Bomber air-strike search — optional `exclude_goal_idx` skips the current tile when rotating targets.
pub fn run_bomber_strike_rule(
    search: &mut SearchKernel,
    territory: &TerritoryKernel,
    masks: &AgentNavMasks<'_>,
    start_gx: i32,
    start_gy: i32,
    team: u8,
    exclude_goal_idx: Option<i32>,
    max_expand: usize,
) -> NavRuleOutcome {
    let start = territory.cell_index(start_gx, start_gy);
    if start < 0 {
        return NavRuleOutcome {
            path: None,
            stats: SearchStats::default(),
        };
    }
    let view = BattleNavView::new(territory, masks, team);
    let expand = max_expand
        .max(1)
        .min(MAX_PATHFIND_EXPAND)
        .min(territory.tile_count.max(1));
    let ctx = CTX_BOMBER_BFS.with_max_expand(expand);
    let exclude = exclude_goal_idx.unwrap_or(-1);
    match search.find_nearest_goal(&view, &[start], ctx, |idx| {
        view.is_air_strike_goal(idx) && (exclude < 0 || idx as i32 != exclude)
    }) {
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

/// True when a soldier is already standing on a valid stance tile.
pub fn is_stance_goal_at(
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
    view.is_stance_goal(idx as usize)
}

/// True when a tile is a pressure target (unowned land soldiers fight over).
pub fn is_pressure_target_at(
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

/// True when a tile is an air strike target (any non-team land; air ignores ferry gate).
pub fn is_air_strike_target_at(
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
    view.is_air_strike_goal(idx as usize)
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
    fn ferry_context_caps_expand_not_tile_count() {
        let ctx = infantry_ferry_context(64_800);
        assert_eq!(ctx.max_expand, FERRY_MAX_EXPAND);
        assert!(ctx.max_expand <= MAX_PATHFIND_EXPAND);
        assert!(
            ctx.max_expand < 64_800,
            "ferry must not expand to full tile_count (late FPS thrash)"
        );
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
        let goal = *path.path.last().unwrap() as usize;
        let view = BattleNavView::new(&k, &masks, OWNER_FRIENDLY);
        assert!(view.is_stance_goal(goal));
        assert_eq!(k.owners[goal], OWNER_FRIENDLY);
        assert!(view.is_advance_goal(2));
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
        assert!(view.is_stance_goal(goal));
        assert_eq!(k.owners[goal], OWNER_HOSTILE);
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
        assert!(view.is_stance_goal(goal));
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

    #[test]
    fn bomber_may_target_unclaimable_island_over_water() {
        let w = 9i32;
        let h = 3i32;
        let n = (w * h) as usize;
        let mut claimable = vec![1u8; n];
        let mut owners = vec![OWNER_FRIENDLY; n];
        // water row
        for gx in 0..w {
            let idx = (1 * w + gx) as usize;
            claimable[idx] = 0;
            owners[idx] = OWNER_NEUTRAL;
        }
        // isolated island — land but not claimable; air may still strike it
        let island_idx = (2 * w + 7) as usize;
        claimable[island_idx] = 0;
        owners[island_idx] = OWNER_NEUTRAL;

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
            3,
            Vec::new(),
            3,
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

        let masks = empty_masks();
        let view = BattleNavView::new(&k, &masks, OWNER_FRIENDLY);
        assert!(!view.is_advance_goal(island_idx));
        assert!(
            view.is_air_strike_goal(island_idx),
            "air may strike unreached islands without ferry beachhead"
        );

        let mut search = SearchKernel::new(n);
        let out = run_bomber_strike_rule(
            &mut search,
            &k,
            &masks,
            0,
            0,
            OWNER_FRIENDLY,
            None,
            5000,
        );
        let path = out.path.expect("bomber path to island");
        let goal = *path.path.last().unwrap() as usize;
        assert_eq!(goal, island_idx);
        assert!(view.is_air_strike_goal(goal));
    }

    #[test]
    fn bomber_strike_exclude_finds_next_nearest_land() {
        let w = 5i32;
        let h = 1i32;
        let n = (w * h) as usize;
        let claimable = vec![1u8; n];
        let mut owners = vec![OWNER_FRIENDLY; n];
        owners[1] = OWNER_NEUTRAL;
        owners[3] = OWNER_NEUTRAL;

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
            1,
            Vec::new(),
            1,
            0,
            false,
            false,
            false,
        );
        k.land_mask = vec![1u8; n];

        let masks = empty_masks();
        let mut search = SearchKernel::new(n);
        let out = run_bomber_strike_rule(
            &mut search,
            &k,
            &masks,
            1,
            0,
            OWNER_FRIENDLY,
            Some(1),
            5000,
        );
        let path = out.path.expect("alternate strike path");
        let goal = *path.path.last().unwrap() as usize;
        assert_eq!(goal, 3);
    }

    #[test]
    fn bomber_strike_respects_expand_budget() {
        let w = 40i32;
        let h = 1i32;
        let n = (w * h) as usize;
        let claimable = vec![1u8; n];
        let mut owners = vec![OWNER_FRIENDLY; n];
        let far_idx = (w - 1) as usize;
        owners[far_idx] = OWNER_NEUTRAL;

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
            1,
            Vec::new(),
            1,
            0,
            false,
            false,
            false,
        );
        k.land_mask = vec![1u8; n];

        let masks = empty_masks();
        let mut search = SearchKernel::new(n);
        let narrow = run_bomber_strike_rule(
            &mut search,
            &k,
            &masks,
            0,
            0,
            OWNER_FRIENDLY,
            None,
            8,
        );
        assert!(narrow.path.is_none());

        let wide = run_bomber_strike_rule(
            &mut search,
            &k,
            &masks,
            0,
            0,
            OWNER_FRIENDLY,
            None,
            5000,
        );
        let path = wide.path.expect("wide search reaches far target");
        assert_eq!(*path.path.last().unwrap() as usize, far_idx);
    }

    #[test]
    fn ferry_crosses_water_when_land_front_exhausted() {
        // Row0: friendly land fully owned | water row1 | neutral island row2
        let w = 5i32;
        let h = 3i32;
        let n = (w * h) as usize;
        let mut claimable = vec![0u8; n];
        let mut owners = vec![OWNER_NEUTRAL; n];
        for gx in 0..w {
            let home = (0 * w + gx) as usize;
            claimable[home] = 1;
            owners[home] = OWNER_FRIENDLY;
            let water = (1 * w + gx) as usize;
            claimable[water] = 0;
            owners[water] = OWNER_NEUTRAL;
            let island = (2 * w + gx) as usize;
            claimable[island] = 0; // unclaimable until beachhead
            owners[island] = crate::sim::OWNER_UNCLAIMABLE;
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
            3,
            Vec::new(),
            3,
            0,
            false,
            false,
            false,
        );
        k.land_mask = (0..n)
            .map(|i| {
                let gy = (i as i32) / w;
                if gy == 1 {
                    0
                } else {
                    1
                }
            })
            .collect();

        let masks = empty_masks();
        let view = BattleNavView::new(&k, &masks, OWNER_FRIENDLY);
        // No land advance goals on home row (all friendly).
        for gx in 0..w {
            assert!(!view.is_advance_goal((0 * w + gx) as usize));
            assert!(!view.is_ferry_landing_goal((0 * w + gx) as usize));
            assert!(view.is_ferry_landing_goal((2 * w + gx) as usize));
        }

        let mut search = SearchKernel::new(n);
        let land_only = search.find_nearest_goal(
            &view,
            &[(0 * w) as i32],
            CTX_INFANTRY_BFS,
            |idx| view.is_stance_goal(idx),
        );
        assert!(land_only.is_none(), "land search must fail when continent is done");

        let out = run_nav_rule(
            &mut search,
            &k,
            &masks,
            0,
            0,
            OWNER_FRIENDLY,
            NAV_RULE_INFANTRY_ADVANCE,
        );
        let path = out.path.expect("ferry path to island");
        assert!(
            path.path.iter().any(|&c| {
                let ui = c as usize;
                ui < k.land_mask.len() && k.land_mask[ui] == 0
            }),
            "ferry path should cross water"
        );
        let goal = *path.path.last().unwrap() as usize;
        assert!(view.is_ferry_landing_goal(goal));
        assert_eq!(goal / (w as usize), 2);
    }
}
