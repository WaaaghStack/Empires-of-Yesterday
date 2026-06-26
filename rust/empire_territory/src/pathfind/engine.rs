//! Route engine — rule registry and single entry point for all placement pathfinding.

use crate::pathfind::kernel::{SearchKernel, SearchStats};
use crate::pathfind::route_rules::{run_route_rule_with_reject, ROUTE_REJECT_NONE};
use crate::route::{PortalGraph, RouteResult, RouteSnapshot, ROUTE_KIND_CORRIDOR, ROUTE_KIND_OUTPOST};

pub use crate::pathfind::route_rules::{
    RouteRuleId, ROUTE_RULE_LAND_BRIDGE, ROUTE_RULE_SUPPLY_BARRACKS, ROUTE_RULE_SUPPLY_OUTPOST,
};

#[derive(Clone, Debug)]
pub struct EngineResult {
    pub result: RouteResult,
    pub stats: SearchStats,
    pub rule_id: RouteRuleId,
    pub reject: i32,
}

pub struct RouteEngine {
    kernel: SearchKernel,
}

impl RouteEngine {
    pub fn new(tile_count: usize) -> Self {
        Self {
            kernel: SearchKernel::new(tile_count),
        }
    }

    pub fn find_route(
        &mut self,
        snapshot: &RouteSnapshot,
        portal: &PortalGraph,
        target_gx: i32,
        target_gy: i32,
        rule_id: RouteRuleId,
        allow_astar: bool,
    ) -> Option<EngineResult> {
        let routed = run_route_rule_with_reject(
            &mut self.kernel,
            snapshot,
            portal,
            target_gx,
            target_gy,
            rule_id,
            allow_astar,
        )?;
        let (result, stats) = match routed.path {
            Some((path, stats)) => (
                RouteResult {
                    path: path.path,
                    source_key: path.source_key,
                },
                stats,
            ),
            None => (
                RouteResult {
                    path: Vec::new(),
                    source_key: -1,
                },
                SearchStats::default(),
            ),
        };
        Some(EngineResult {
            result,
            stats,
            rule_id,
            reject: routed.reject,
        })
    }
}

pub fn kind_to_rule(kind: i32) -> RouteRuleId {
    if kind == ROUTE_KIND_CORRIDOR {
        ROUTE_RULE_LAND_BRIDGE
    } else {
        ROUTE_RULE_SUPPLY_OUTPOST
    }
}

/// Legacy `ROUTE_KIND_*` dispatch used by Godot FFI and async worker.
pub fn find_route_by_kind(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    kind: i32,
    allow_astar: bool,
) -> Option<EngineResult> {
    let rule_id = kind_to_rule(kind);
    find_route_by_rule(
        snapshot,
        portal,
        target_gx,
        target_gy,
        rule_id,
        allow_astar,
    )
}

pub fn find_route_by_rule(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    rule_id: RouteRuleId,
    allow_astar: bool,
) -> Option<EngineResult> {
    let mut engine = RouteEngine::new(snapshot.tile_count());
    engine.find_route(
        snapshot,
        portal,
        target_gx,
        target_gy,
        rule_id,
        allow_astar,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pathfind::route_rules::ROUTE_REJECT_INFEASIBLE;

    fn test_snapshot() -> RouteSnapshot {
        let w = 5i32;
        let h = 3i32;
        let n = (w * h) as usize;
        let mut land_mask = vec![0u8; n];
        let mut land_comp = vec![-1i32; n];
        for gy in 0..h {
            for gx in 0..w {
                let idx = (gy * w + gx) as usize;
                if gy != 1 {
                    land_mask[idx] = 1;
                    land_comp[idx] = if gx < 2 { 0 } else { 1 };
                }
            }
        }
        RouteSnapshot {
            grid_w: w,
            grid_h: h,
            wrap_longitude: false,
            land_mask,
            bridge_mask: vec![0u8; n],
            land_comp,
        }
    }

    fn test_portal() -> PortalGraph {
        let mut portal = PortalGraph::default();
        portal.source_keys.push(0);
        portal.source_land_comp.push(0);
        portal.infra_reach.push(vec![0]);
        portal
    }

    #[test]
    fn engine_supply_outpost_finds_path() {
        let snap = test_snapshot();
        let portal = test_portal();
        let r = find_route_by_rule(&snap, &portal, 1, 0, ROUTE_RULE_SUPPLY_OUTPOST, true);
        assert!(r.is_some());
    }

    #[test]
    fn engine_land_bridge_finds_path() {
        let snap = test_snapshot();
        let portal = test_portal();
        let r = find_route_by_rule(&snap, &portal, 4, 2, ROUTE_RULE_LAND_BRIDGE, true);
        assert!(r.is_some());
        let path = &r.unwrap().result.path;
        assert!(path.len() >= 2);
        assert!(path.iter().any(|&k| snap.is_water(k as usize)));
    }

    #[test]
    fn engine_rejects_unreachable_outpost_without_expanding() {
        let snap = test_snapshot();
        let portal = test_portal();
        let r = find_route_by_rule(&snap, &portal, 4, 2, ROUTE_RULE_SUPPLY_OUTPOST, true);
        assert!(r.is_some());
        assert_eq!(r.unwrap().reject, ROUTE_REJECT_INFEASIBLE);
    }

    #[test]
    fn kind_dispatch_matches_rules() {
        let snap = test_snapshot();
        let portal = test_portal();
        let outpost = find_route_by_kind(
            &snap,
            &portal,
            1,
            0,
            ROUTE_KIND_OUTPOST,
            true,
        );
        let corridor = find_route_by_kind(
            &snap,
            &portal,
            4,
            2,
            ROUTE_KIND_CORRIDOR,
            true,
        );
        assert!(outpost.is_some());
        assert!(corridor.is_some());
    }
}
