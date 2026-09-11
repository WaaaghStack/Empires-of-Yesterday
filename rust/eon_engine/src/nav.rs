//! Battle locomotion tables. Authority is these static rows, not JSON.
//!
//! Join: kind ⋈ locomotor ⋈ policy(situation) → one intent per body per tick.
//! Squad guides (and land bodies) steer around `NavBlocker`s. Air ignores land blockers.
//! `ST_IDLE` is only legal for TrainHold (in slot) and is not used for HaltAim.

use crate::model::{AttackStyle, UnitDomain, UnitKind};

/// What the body/guide is trying to do this tick.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavIntent {
    FollowGuide,
    CloseContact,
    HaltAim,
    Overfly,
    RoutHome,
    TrainHold,
}

/// Closed situation vocab. Policy rows key off this, not ad-hoc if-ladders.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavSituation {
    Routing,
    Train,
    DriveBy,
    HaltInReach,
    Advance,
    AaClose,
    AirIgnore,
    FollowLane,
}

#[derive(Clone, Copy, Debug)]
pub struct Locomotor {
    pub kind: UnitKind,
    pub domain: UnitDomain,
    pub blocked_by_hill: bool,
    pub blocked_by_ruin: bool,
    pub ford_ok: bool,
}

#[derive(Clone, Copy, Debug)]
pub struct NavPolicy {
    pub situation: NavSituation,
    pub style: AttackStyle,
    pub intent: NavIntent,
}

/// Solid occupancy for land. Air sets `blocks_air` only if we ever need no-fly.
#[derive(Clone, Copy, Debug)]
pub struct NavBlocker {
    pub cx: f32,
    pub cy: f32,
    pub r: f32,
    pub blocks_land: bool,
    pub blocks_air: bool,
}

impl NavBlocker {
    pub const fn land(cx: f32, cy: f32, r: f32) -> Self {
        Self {
            cx,
            cy,
            r,
            blocks_land: true,
            blocks_air: false,
        }
    }
}

pub const LOCOMOTOR: [Locomotor; 8] = [
    Locomotor {
        kind: UnitKind::Soldier,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::Bomber,
        domain: UnitDomain::Air,
        blocked_by_hill: false,
        blocked_by_ruin: false,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::Stovebreaker,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::AshWarden,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::WalkMapper,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::LedgerPiece,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::RollingHearth,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
    Locomotor {
        kind: UnitKind::CeilingClerk,
        domain: UnitDomain::Land,
        blocked_by_hill: true,
        blocked_by_ruin: true,
        ford_ok: true,
    },
];

/// Style-keyed policy. Kind-specific exceptions (AA close on air) use situation, not extra rows.
pub const NAV_POLICY: [NavPolicy; 10] = [
    NavPolicy {
        situation: NavSituation::Routing,
        style: AttackStyle::Hold,
        intent: NavIntent::RoutHome,
    },
    NavPolicy {
        situation: NavSituation::Train,
        style: AttackStyle::Train,
        intent: NavIntent::TrainHold,
    },
    NavPolicy {
        situation: NavSituation::DriveBy,
        style: AttackStyle::DriveBy,
        intent: NavIntent::Overfly,
    },
    NavPolicy {
        situation: NavSituation::HaltInReach,
        style: AttackStyle::Hold,
        intent: NavIntent::HaltAim,
    },
    NavPolicy {
        situation: NavSituation::HaltInReach,
        style: AttackStyle::Charge,
        intent: NavIntent::HaltAim,
    },
    NavPolicy {
        situation: NavSituation::Advance,
        style: AttackStyle::Hold,
        intent: NavIntent::FollowGuide,
    },
    NavPolicy {
        situation: NavSituation::Advance,
        style: AttackStyle::Charge,
        intent: NavIntent::CloseContact,
    },
    NavPolicy {
        situation: NavSituation::AaClose,
        style: AttackStyle::Hold,
        intent: NavIntent::CloseContact,
    },
    NavPolicy {
        situation: NavSituation::AirIgnore,
        style: AttackStyle::Hold,
        intent: NavIntent::FollowGuide,
    },
    NavPolicy {
        situation: NavSituation::FollowLane,
        style: AttackStyle::Hold,
        intent: NavIntent::FollowGuide,
    },
];

pub fn locomotor(kind: UnitKind) -> Locomotor {
    LOCOMOTOR[kind as usize]
}

pub fn situation(
    kind: UnitKind,
    routing: bool,
    has_target: bool,
    target_air: bool,
    in_reach: bool,
) -> NavSituation {
    let style = kind.attack_style();
    if routing {
        return NavSituation::Routing;
    }
    if style == AttackStyle::Train {
        return NavSituation::Train;
    }
    if style == AttackStyle::DriveBy {
        return NavSituation::DriveBy;
    }
    if has_target && target_air && kind.vs_air() >= 1.0 {
        return if in_reach {
            NavSituation::HaltInReach
        } else {
            NavSituation::AaClose
        };
    }
    if has_target && target_air {
        return NavSituation::AirIgnore;
    }
    if has_target && in_reach {
        return NavSituation::HaltInReach;
    }
    if has_target {
        return NavSituation::Advance;
    }
    NavSituation::FollowLane
}

pub fn intent(kind: UnitKind, sit: NavSituation) -> NavIntent {
    let style = kind.attack_style();
    if sit == NavSituation::Routing {
        return NavIntent::RoutHome;
    }
    if sit == NavSituation::AirIgnore || sit == NavSituation::FollowLane {
        return NavIntent::FollowGuide;
    }
    if let Some(row) = NAV_POLICY
        .iter()
        .find(|p| p.situation == sit && p.style == style)
    {
        return row.intent;
    }
    if let Some(row) = NAV_POLICY.iter().find(|p| p.situation == sit) {
        return row.intent;
    }
    match style {
        AttackStyle::Train => NavIntent::TrainHold,
        AttackStyle::DriveBy => NavIntent::Overfly,
        AttackStyle::Charge => NavIntent::CloseContact,
        AttackStyle::Hold => NavIntent::FollowGuide,
    }
}

pub fn idle_legal(intent: NavIntent) -> bool {
    intent == NavIntent::TrainHold
}

fn dist2(ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let dx = bx - ax;
    let dy = by - ay;
    dx * dx + dy * dy
}

fn segment_hits_circle(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32, r: f32) -> bool {
    let abx = bx - ax;
    let aby = by - ay;
    let ab2 = (abx * abx + aby * aby).max(1e-8);
    let t = ((cx - ax) * abx + (cy - ay) * aby) / ab2;
    let t = t.clamp(0.0, 1.0);
    let px = ax + t * abx;
    let py = ay + t * aby;
    dist2(px, py, cx, cy) < r * r
}

fn tangent_points(px: f32, py: f32, cx: f32, cy: f32, r: f32) -> Option<((f32, f32), (f32, f32))> {
    let dx = px - cx;
    let dy = py - cy;
    let d2 = dx * dx + dy * dy;
    let r2 = r * r;
    if d2 <= r2 + 1e-3 {
        return None;
    }
    let a = r2 / d2;
    let b = r * (d2 - r2).sqrt() / d2;
    Some((
        (cx + a * dx - b * dy, cy + a * dy + b * dx),
        (cx + a * dx + b * dy, cy + a * dy - b * dx),
    ))
}

fn rim_step(fx: f32, fy: f32, dest: (f32, f32), cx: f32, cy: f32, r: f32) -> (f32, f32) {
    let dx = fx - cx;
    let dy = fy - cy;
    let d = (dx * dx + dy * dy).sqrt();
    let (nx, ny) = if d < 1e-3 {
        let ex = dest.0 - cx;
        let ey = dest.1 - cy;
        let ed = (ex * ex + ey * ey).sqrt().max(1e-3);
        (-ey / ed, ex / ed)
    } else {
        (dx / d, dy / d)
    };
    let p1 = (cx + nx * r - ny * 10.0, cy + ny * r + nx * 10.0);
    let p2 = (cx + nx * r + ny * 10.0, cy + ny * r - nx * 10.0);
    pick_bypass(p1, p2, dest)
}

/// Slab midline (matches battle BATTLE_HEIGHT/2). Tall lines walk the south pass together.
const TANGENT_PREFER_Y: f32 = 300.0;

fn pick_bypass(a: (f32, f32), b: (f32, f32), dest: (f32, f32)) -> (f32, f32) {
    let s1 = dist2(a.0, a.1, dest.0, dest.1) + (a.1 - TANGENT_PREFER_Y).abs() * 20.0;
    let s2 = dist2(b.0, b.1, dest.0, dest.1) + (b.1 - TANGENT_PREFER_Y).abs() * 20.0;
    if s1 <= s2 {
        a
    } else {
        b
    }
}

fn bypass_circle(from: (f32, f32), dest: (f32, f32), cx: f32, cy: f32, r: f32) -> (f32, f32) {
    let (fx, fy) = from;
    let clearance = r + 1.6;
    if dist2(fx, fy, cx, cy) <= (r + 0.75) * (r + 0.75) {
        return rim_step(fx, fy, dest, cx, cy, clearance);
    }
    if !segment_hits_circle(fx, fy, dest.0, dest.1, cx, cy, r) {
        return dest;
    }
    match tangent_points(fx, fy, cx, cy, r) {
        Some((t1, t2)) => pick_bypass(t1, t2, dest),
        None => rim_step(fx, fy, dest, cx, cy, clearance),
    }
}

fn blockers_for(domain: UnitDomain, blockers: &[NavBlocker]) -> impl Iterator<Item = &NavBlocker> {
    blockers.iter().filter(move |b| match domain {
        UnitDomain::Air => b.blocks_air,
        UnitDomain::Land | UnitDomain::Naval => b.blocks_land,
    })
}

/// Next waypoint toward `to`, going around solid blockers for this domain.
pub fn waypoint(
    from_x: f32,
    from_y: f32,
    to_x: f32,
    to_y: f32,
    domain: UnitDomain,
    blockers: &[NavBlocker],
) -> (f32, f32) {
    let mut dest = (to_x, to_y);
    for b in blockers_for(domain, blockers) {
        dest = bypass_circle((from_x, from_y), dest, b.cx, b.cy, b.r);
    }
    dest
}

pub fn steer(
    from_x: f32,
    from_y: f32,
    to_x: f32,
    to_y: f32,
    step: f32,
    domain: UnitDomain,
    blockers: &[NavBlocker],
) -> (f32, f32) {
    let (tx, ty) = waypoint(from_x, from_y, to_x, to_y, domain, blockers);
    let inside = blockers_for(domain, blockers)
        .any(|b| dist2(from_x, from_y, b.cx, b.cy) < b.r * b.r);
    if inside {
        return (tx, ty);
    }
    let dx = tx - from_x;
    let dy = ty - from_y;
    let d = (dx * dx + dy * dy).sqrt();
    if d <= step || d < 1e-4 {
        (tx, ty)
    } else {
        (from_x + dx / d * step, from_y + dy / d * step)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_kind_has_a_locomotor_row() {
        for kind in UnitKind::ALL {
            let row = locomotor(kind);
            assert_eq!(row.kind, kind);
            assert_eq!(row.domain, kind.domain());
        }
    }

    #[test]
    fn idle_is_only_legal_for_the_train() {
        assert!(idle_legal(NavIntent::TrainHold));
        assert!(!idle_legal(NavIntent::FollowGuide));
        assert!(!idle_legal(NavIntent::HaltAim));
        assert!(!idle_legal(NavIntent::CloseContact));
    }

    #[test]
    fn hold_line_follows_the_guide_until_reach() {
        let s = situation(UnitKind::Soldier, false, true, false, false);
        assert_eq!(s, NavSituation::Advance);
        assert_eq!(intent(UnitKind::Soldier, s), NavIntent::FollowGuide);
        let halt = situation(UnitKind::Soldier, false, true, false, true);
        assert_eq!(intent(UnitKind::Soldier, halt), NavIntent::HaltAim);
    }

    #[test]
    fn land_does_not_chase_air() {
        let s = situation(UnitKind::Soldier, false, true, true, false);
        assert_eq!(s, NavSituation::AirIgnore);
        assert_eq!(intent(UnitKind::Soldier, s), NavIntent::FollowGuide);
    }

    #[test]
    fn clerks_close_on_air() {
        let s = situation(UnitKind::CeilingClerk, false, true, true, false);
        assert_eq!(s, NavSituation::AaClose);
        assert_eq!(intent(UnitKind::CeilingClerk, s), NavIntent::CloseContact);
    }

    #[test]
    fn charge_closes_until_contact() {
        let s = situation(UnitKind::Stovebreaker, false, true, false, false);
        assert_eq!(intent(UnitKind::Stovebreaker, s), NavIntent::CloseContact);
    }

    #[test]
    fn steer_goes_around_a_circle_instead_of_sticking() {
        let hill = [NavBlocker::land(0.0, 0.0, 40.0)];
        let mut x = -80.0;
        let mut y = 0.0;
        let mut max_abs_y: f32 = 0.0;
        for _ in 0..80 {
            let (nx, ny) = steer(x, y, 80.0, 0.0, 6.0, UnitDomain::Land, &hill);
            x = nx;
            y = ny;
            max_abs_y = max_abs_y.max(y.abs());
            assert!(
                x * x + y * y >= 40.0 * 40.0 - 1.0,
                "land walked into the blocker at ({x:.1},{y:.1})"
            );
        }
        assert!(x > 0.0, "should clear the far side (x={x:.1} y={y:.1})");
        assert!(max_abs_y > 8.0, "should detour off the centerline (max|y|={max_abs_y:.1})");
    }

    #[test]
    fn land_starting_inside_walks_around_not_back() {
        let hill = [NavBlocker::land(0.0, 0.0, 40.0)];
        let mut x = -20.0;
        let mut y = 0.0;
        let mut max_abs_y: f32 = 0.0;
        for i in 0..90 {
            let (nx, ny) = steer(x, y, 80.0, 0.0, 6.0, UnitDomain::Land, &hill);
            x = nx;
            y = ny;
            max_abs_y = max_abs_y.max(y.abs());
            if i == 0 {
                continue;
            }
            assert!(
                x * x + y * y >= 40.0 * 40.0 - 2.0,
                "land walked into the blocker at ({x:.1},{y:.1})"
            );
        }
        assert!(x > 0.0, "inside start must still clear the far side (x={x:.1} y={y:.1})");
        assert!(max_abs_y > 8.0, "must leave the blocked chord (max|y|={max_abs_y:.1})");
    }

    #[test]
    fn air_ignores_land_blockers() {
        let hill = [NavBlocker::land(0.0, 0.0, 40.0)];
        let (x, y) = steer(-80.0, 0.0, 80.0, 0.0, 200.0, UnitDomain::Air, &hill);
        assert!(x > 70.0 && y.abs() < 0.01, "air should fly the chord ({x:.1},{y:.1})");
    }
}
