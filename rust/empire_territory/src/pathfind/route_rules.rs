//! Data-driven placement route rules + cheap feasibility prechecks.

pub type RouteRuleId = i32;

pub const ROUTE_RULE_SUPPLY_OUTPOST: RouteRuleId = 0;
pub const ROUTE_RULE_SUPPLY_BARRACKS: RouteRuleId = 1;
pub const ROUTE_RULE_LAND_BRIDGE: RouteRuleId = 2;
use crate::pathfind::kernel::{RouteContext, RoutePath, SearchKernel, SearchStats};
use crate::route::{is_coastal, PortalGraph, RouteSnapshot};

/// One-time O(n) metadata derived from a snapshot for fast feasibility checks.
pub struct PlacementMeta {
    comp_has_coastal: Vec<u8>,
}

impl PlacementMeta {
    pub fn from_snapshot(snapshot: &RouteSnapshot) -> Self {
        let mut comp_has_coastal: Vec<u8> = Vec::new();
        let w = snapshot.grid_w;
        let h = snapshot.grid_h;
        for gy in 0..h {
            for gx in 0..w {
                if !is_coastal(snapshot, gx, gy) {
                    continue;
                }
                let idx = snapshot.cell_index(gx, gy);
                if idx < 0 {
                    continue;
                }
                let comp = snapshot.land_comp_at(idx as usize);
                if comp < 0 {
                    continue;
                }
                let ui = comp as usize;
                if ui >= comp_has_coastal.len() {
                    comp_has_coastal.resize(ui + 1, 0);
                }
                comp_has_coastal[ui] = 1;
            }
        }
        Self { comp_has_coastal }
    }

    fn landmass_touches_ocean(&self, comp: i32) -> bool {
        if comp < 0 {
            return false;
        }
        let ui = comp as usize;
        ui < self.comp_has_coastal.len() && self.comp_has_coastal[ui] != 0
    }
}

#[derive(Clone, Copy, Debug)]
pub struct RouteRule {
    pub id: RouteRuleId,
    pub goal_must_be_land: bool,
    pub goal_must_be_coastal: bool,
    pub attempts: &'static [RouteContext],
}

const CTX_LAND_ASTAR: RouteContext = RouteContext::astar(false, false);
const CTX_WATER_ASTAR: RouteContext = RouteContext::land_bridge_astar();

/// Start with a thin direct tube, widen in steps until a path appears.
const DEFAULT_CORRIDOR_WIDTHS: &[i32] = &[2, 4, 8, 16, 32, 48, 72, 96];
const LAND_BRIDGE_CORRIDOR_WIDTHS: &[i32] = &[4, 8, 16, 32, 48, 72, 96, 128, 160, 192, 256];
const CORRIDOR_PER_BAND_MAX_EXPAND: usize = 8192;
const DEFAULT_FULL_SEARCH_MAX_EXPAND: usize = 12_000;
/// One full-grid pass only after all corridor bands fail (land bridge).
const LAND_BRIDGE_FULL_SEARCH_MAX_EXPAND: usize = 65_536;

fn corridor_widths_for(rule_id: RouteRuleId) -> &'static [i32] {
    if rule_id == ROUTE_RULE_LAND_BRIDGE {
        LAND_BRIDGE_CORRIDOR_WIDTHS
    } else {
        DEFAULT_CORRIDOR_WIDTHS
    }
}

fn full_search_max_expand(rule_id: RouteRuleId) -> usize {
    if rule_id == ROUTE_RULE_LAND_BRIDGE {
        LAND_BRIDGE_FULL_SEARCH_MAX_EXPAND
    } else {
        DEFAULT_FULL_SEARCH_MAX_EXPAND
    }
}

pub static ROUTE_RULES: &[RouteRule] = &[
    RouteRule {
        id: ROUTE_RULE_SUPPLY_OUTPOST,
        goal_must_be_land: true,
        goal_must_be_coastal: false,
        attempts: &[CTX_LAND_ASTAR],
    },
    RouteRule {
        id: ROUTE_RULE_SUPPLY_BARRACKS,
        goal_must_be_land: true,
        goal_must_be_coastal: false,
        attempts: &[CTX_LAND_ASTAR],
    },
    RouteRule {
        id: ROUTE_RULE_LAND_BRIDGE,
        goal_must_be_land: true,
        goal_must_be_coastal: false,
        attempts: &[CTX_WATER_ASTAR],
    },
];

pub fn rule_by_id(id: RouteRuleId) -> Option<&'static RouteRule> {
    ROUTE_RULES.iter().find(|r| r.id == id)
}

/// Cheap reject before A*: goal landmass unreachable without building over open water.
fn supply_outpost_feasible(snapshot: &RouteSnapshot, portal: &PortalGraph, goal_ui: usize) -> bool {
    if portal.source_keys.is_empty() || !snapshot.is_land(goal_ui) {
        return false;
    }
    let goal_comp = snapshot.land_comp_at(goal_ui);
    if goal_comp < 0 {
        return false;
    }
    for (i, _) in portal.source_keys.iter().enumerate() {
        if portal.source_land_comp.get(i) == Some(&goal_comp) {
            return true;
        }
        if let Some(reach) = portal.infra_reach.get(i) {
            if reach.contains(&goal_comp) {
                return true;
            }
        }
    }
    false
}

/// Cheap reject: no friendly source on a landmass that can reach the ocean.
fn land_bridge_feasible(
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    meta: &PlacementMeta,
) -> bool {
    if portal.source_keys.is_empty() {
        return false;
    }
    for (i, _) in portal.source_keys.iter().enumerate() {
        let comp = portal.source_land_comp.get(i).copied().unwrap_or(-1);
        if meta.landmass_touches_ocean(comp) {
            return true;
        }
    }
    let _ = snapshot;
    false
}

fn rule_feasible(
    rule: &RouteRule,
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    goal_ui: usize,
    meta: &PlacementMeta,
) -> bool {
    match rule.id {
        ROUTE_RULE_SUPPLY_OUTPOST | ROUTE_RULE_SUPPLY_BARRACKS => {
            supply_outpost_feasible(snapshot, portal, goal_ui)
        }
        ROUTE_RULE_LAND_BRIDGE => land_bridge_feasible(snapshot, portal, meta),
        _ => false,
    }
}

/// Diagnostic reject codes returned to Godot when routing fails before a path is found.
pub const ROUTE_REJECT_NONE: i32 = 0;
pub const ROUTE_REJECT_UNKNOWN_RULE: i32 = 1;
pub const ROUTE_REJECT_ASTAR_DISABLED: i32 = 2;
pub const ROUTE_REJECT_INVALID_GOAL: i32 = 3;
pub const ROUTE_REJECT_GOAL_NOT_LAND: i32 = 4;
pub const ROUTE_REJECT_GOAL_NOT_COASTAL: i32 = 5;
pub const ROUTE_REJECT_INFEASIBLE: i32 = 6;
pub const ROUTE_REJECT_NO_PATH: i32 = 7;
pub const ROUTE_REJECT_NO_SOURCES: i32 = 8;

pub fn run_route_rule(
    kernel: &mut SearchKernel,
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    rule_id: RouteRuleId,
    allow_astar: bool,
) -> Option<(RoutePath, SearchStats)> {
    run_route_rule_with_reject(
        kernel,
        snapshot,
        portal,
        target_gx,
        target_gy,
        rule_id,
        allow_astar,
    )
    .and_then(|r| r.path)
}

pub struct RouteRuleOutcome {
    pub path: Option<(RoutePath, SearchStats)>,
    pub reject: i32,
}

// I8: allow_astar=false must NOT hard-reject. It runs a capped pathfind (hover / AI).
// ROUTE_REJECT_ASTAR_DISABLED means "cheap budget exhausted" — callers may retry with full A*.
/// Cheap path budget when allow_astar=false: thin corridors only (still searches).
const CHEAP_CORRIDOR_WIDTHS: &[i32] = &[2, 4, 8, 16, 32];
const CHEAP_CORRIDOR_PER_BAND_MAX_EXPAND: usize = 2_048;
const CHEAP_FULL_SEARCH_MAX_EXPAND: usize = 4_000;

pub fn run_route_rule_with_reject(
    kernel: &mut SearchKernel,
    snapshot: &RouteSnapshot,
    portal: &PortalGraph,
    target_gx: i32,
    target_gy: i32,
    rule_id: RouteRuleId,
    allow_astar: bool,
) -> Option<RouteRuleOutcome> {
    let rule = rule_by_id(rule_id)?;

    let goal = snapshot.cell_index(target_gx, target_gy);
    if goal < 0 {
        return Some(RouteRuleOutcome {
            path: None,
            reject: ROUTE_REJECT_INVALID_GOAL,
        });
    }
    let goal_ui = goal as usize;
    if rule.goal_must_be_land && !snapshot.is_land(goal_ui) {
        return Some(RouteRuleOutcome {
            path: None,
            reject: ROUTE_REJECT_GOAL_NOT_LAND,
        });
    }
    if rule.goal_must_be_coastal && !is_coastal(snapshot, target_gx, target_gy) {
        return Some(RouteRuleOutcome {
            path: None,
            reject: ROUTE_REJECT_GOAL_NOT_COASTAL,
        });
    }

    if portal.source_keys.is_empty() {
        return Some(RouteRuleOutcome {
            path: None,
            reject: ROUTE_REJECT_NO_SOURCES,
        });
    }

    let meta = PlacementMeta::from_snapshot(snapshot);
    if !rule_feasible(rule, snapshot, portal, goal_ui, &meta) {
        return Some(RouteRuleOutcome {
            path: None,
            reject: ROUTE_REJECT_INFEASIBLE,
        });
    }

    let sources = &portal.source_keys;
    // I8: allow_astar=false still runs capped multi-source pathfind (never hard-reject here).
    // allow_astar=true: full corridor ladder + full expand (player click placement).
    let (widths, band_cap, full_cap) = if allow_astar {
        (
            corridor_widths_for(rule.id),
            CORRIDOR_PER_BAND_MAX_EXPAND,
            full_search_max_expand(rule.id),
        )
    } else {
        (
            CHEAP_CORRIDOR_WIDTHS,
            CHEAP_CORRIDOR_PER_BAND_MAX_EXPAND,
            CHEAP_FULL_SEARCH_MAX_EXPAND,
        )
    };
    // Pathfind expand caps always apply (B5) — multi-source search is bounded by full_cap.
    debug_assert!(full_cap > 0 && band_cap > 0);
    for &ctx in rule.attempts {
        if let Some(result) = kernel.find_path_corridor_widening(
            snapshot,
            sources,
            goal,
            ctx,
            widths,
            band_cap,
        ) {
            return Some(RouteRuleOutcome {
                path: Some(result),
                reject: ROUTE_REJECT_NONE,
            });
        }
        if let Some(result) = kernel.find_path(
            snapshot,
            sources,
            goal,
            ctx.with_max_expand(full_cap),
        ) {
            return Some(RouteRuleOutcome {
                path: Some(result),
                reject: ROUTE_REJECT_NONE,
            });
        }
    }
    Some(RouteRuleOutcome {
        path: None,
        reject: if allow_astar {
            ROUTE_REJECT_NO_PATH
        } else {
            // Cheap budget exhausted after a real search attempt — not a hard disable (I8).
            ROUTE_REJECT_ASTAR_DISABLED
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::route::PortalGraph;

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
    fn supply_feasibility_rejects_unreachable_landmass() {
        let snap = test_snapshot();
        let portal = test_portal();
        // Goal on landmass 1; source only reaches landmass 0.
        assert!(!supply_outpost_feasible(&snap, &portal, 12));
        assert!(supply_outpost_feasible(&snap, &portal, 1));
    }

    #[test]
    fn land_bridge_feasibility_requires_ocean_access() {
        let snap = test_snapshot();
        let meta = PlacementMeta::from_snapshot(&snap);
        let mut portal = PortalGraph::default();
        // Source on landmass 0 (coastal row y=0).
        portal.source_keys.push(0);
        portal.source_land_comp.push(0);
        portal.infra_reach.push(vec![0]);
        assert!(land_bridge_feasible(&snap, &portal, &meta));
    }

    #[test]
    fn land_bridge_cross_ocean_earth_scale() {
        let w = 360i32;
        let h = 180i32;
        let n = (w * h) as usize;
        let mut land_mask = vec![0u8; n];
        let mut land_comp = vec![-1i32; n];
        for gy in 0..h {
            for gx in 0..w {
                let idx = (gy * w + gx) as usize;
                // Water band across middle; two continents north and south.
                if gy < 70 || gy > 110 {
                    land_mask[idx] = 1;
                    land_comp[idx] = if gx < 180 { 0 } else { 1 };
                }
            }
        }
        // No land bridge at the longitude seam — forces ocean crossing.
        for gy in 68..=71 {
            for gx in 178..=182 {
                let idx = (gy * w + gx) as usize;
                land_mask[idx] = 0;
                land_comp[idx] = -1;
            }
        }
        let snap = RouteSnapshot {
            grid_w: w,
            grid_h: h,
            wrap_longitude: true,
            land_mask,
            bridge_mask: vec![0u8; n],
            land_comp,
        };
        let home = snap.cell_index(20, 69);
        let goal_gx = 300i32;
        let goal_gy = 69i32; // coastal row adjacent to water band at gy=70
        assert!(is_coastal(&snap, goal_gx, goal_gy));
        let portal = PortalGraph::rebuild(&snap, &[home]);
        let mut kernel = SearchKernel::new(n);
        let r = run_route_rule_with_reject(
            &mut kernel,
            &snap,
            &portal,
            goal_gx,
            goal_gy,
            ROUTE_RULE_LAND_BRIDGE,
            true,
        )
        .expect("rule outcome");
        let (path, stats) = r.path.expect("path");
        assert!(
            stats.expand_count < 5_000,
            "expand_count={} corridor search should stay small",
            stats.expand_count
        );
        assert!(!path.path.is_empty());
    }

    fn load_earth_fixture() -> Option<(RouteSnapshot, i32)> {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata/earth424242_route.bin");
        let bytes = std::fs::read(path).ok()?;
        if bytes.len() < 8 {
            return None;
        }
        let w = i32::from_le_bytes(bytes[0..4].try_into().ok()?);
        let h = i32::from_le_bytes(bytes[4..8].try_into().ok()?);
        let n = (w * h) as usize;
        let mask_end = 8 + n;
        let comp_end = mask_end + n * 4;
        if bytes.len() < comp_end {
            return None;
        }
        let land_mask: Vec<u8> = bytes[8..mask_end].to_vec();
        let mut land_comp = vec![-1i32; n];
        for i in 0..n {
            let off = mask_end + i * 4;
            land_comp[i] = i32::from_le_bytes(bytes[off..off + 4].try_into().ok()?);
        }
        let snap = RouteSnapshot {
            grid_w: w,
            grid_h: h,
            wrap_longitude: true,
            land_mask,
            bridge_mask: vec![0u8; n],
            land_comp,
        };
        // seed 424242 player home from EarthMapGenerator
        let home = snap.cell_index(59, 91);
        Some((snap, home))
    }

    #[test]
    fn earth424242_land_bridge_route() {
        let Some((snap, home)) = load_earth_fixture() else {
            eprintln!("skip earth424242_land_bridge_route: run tools/export_earth_route_fixture.gd");
            return;
        };
        let portal = PortalGraph::rebuild(&snap, &[home]);
        let mut kernel = SearchKernel::new(snap.tile_count());
        let r = run_route_rule_with_reject(
            &mut kernel,
            &snap,
            &portal,
            310,
            136,
            ROUTE_RULE_LAND_BRIDGE,
            true,
        )
        .expect("rule outcome");
        assert_eq!(
            r.reject, ROUTE_REJECT_NONE,
            "earth land bridge should route home=(59,91) landing=(310,136)"
        );
        let (path, stats) = r.path.expect("path");
        assert!(!path.path.is_empty());
        eprintln!("earth424242 path_len={} expand={}", path.path.len(), stats.expand_count);
    }

    #[test]
    fn run_rule_returns_none_when_infeasible_without_search() {
        let snap = test_snapshot();
        let portal = test_portal();
        let mut kernel = SearchKernel::new(snap.tile_count());
        let r = run_route_rule_with_reject(
            &mut kernel,
            &snap,
            &portal,
            2,
            2,
            ROUTE_RULE_SUPPLY_OUTPOST,
            true,
        )
        .expect("rule outcome");
        assert_eq!(r.reject, ROUTE_REJECT_INFEASIBLE);
        assert!(r.path.is_none());
    }

    /// I8: allow_astar=false must still pathfind (capped), not hard-reject before search.
    #[test]
    fn allow_astar_false_still_finds_short_path() {
        let w = 5i32;
        let h = 3i32;
        let n = (w * h) as usize;
        // Single connected landmass on top row.
        let mut land_mask = vec![0u8; n];
        let mut land_comp = vec![-1i32; n];
        for gx in 0..w {
            let idx = gx as usize; // gy=0
            land_mask[idx] = 1;
            land_comp[idx] = 0;
        }
        let snap = RouteSnapshot {
            grid_w: w,
            grid_h: h,
            wrap_longitude: false,
            land_mask,
            bridge_mask: vec![0u8; n],
            land_comp,
        };
        let mut portal = PortalGraph::default();
        portal.source_keys.push(0);
        portal.source_land_comp.push(0);
        portal.infra_reach.push(vec![0]);
        let mut kernel = SearchKernel::new(n);
        let r = run_route_rule_with_reject(
            &mut kernel,
            &snap,
            &portal,
            4,
            0,
            ROUTE_RULE_SUPPLY_OUTPOST,
            false, // capped pathfind — must still succeed on a short land route
        )
        .expect("rule outcome");
        assert_eq!(
            r.reject, ROUTE_REJECT_NONE,
            "allow_astar=false must not hard-reject feasible short routes"
        );
        let (path, stats) = r.path.expect("path under cheap budget");
        assert!(!path.path.is_empty());
        assert!(
            stats.expand_count <= CHEAP_FULL_SEARCH_MAX_EXPAND
                || stats.expand_count <= CHEAP_CORRIDOR_PER_BAND_MAX_EXPAND,
            "expand_count={} must respect cheap caps",
            stats.expand_count
        );
    }

    #[test]
    fn pathfind_caps_are_positive() {
        assert!(CORRIDOR_PER_BAND_MAX_EXPAND > 0);
        assert!(DEFAULT_FULL_SEARCH_MAX_EXPAND > 0);
        assert!(CHEAP_FULL_SEARCH_MAX_EXPAND > 0);
        assert!(CHEAP_CORRIDOR_PER_BAND_MAX_EXPAND > 0);
    }
}
