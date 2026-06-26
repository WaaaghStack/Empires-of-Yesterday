//! Unified A* pathfinding kernel + rule-based route profiles.

pub mod battle_nav;
pub mod engine;
pub mod graph;
pub mod kernel;
pub mod nav_rules;
pub mod route_rules;

pub use engine::{
    find_route_by_kind, find_route_by_rule, kind_to_rule, RouteEngine,
    ROUTE_RULE_LAND_BRIDGE, ROUTE_RULE_SUPPLY_BARRACKS, ROUTE_RULE_SUPPLY_OUTPOST,
};
pub use route_rules::RouteRuleId;
pub use graph::NavGraph;
pub use kernel::{RouteContext, RoutePath, SearchStats};
pub use battle_nav::{AgentNavMasks, BattleNavView};
pub use nav_rules::{
    is_advance_goal_at, run_nav_rule, NavGoalMode, NavRule, NavRuleId, NavRuleOutcome,
    NAV_RULE_INFANTRY_ADVANCE, NAV_RULE_INFANTRY_FRONTLINE, NAV_RULE_INFANTRY_RETREAT,
};
pub use route_rules::{PlacementMeta, RouteRule, ROUTE_RULES};
