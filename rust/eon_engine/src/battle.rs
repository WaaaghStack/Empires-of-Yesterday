//! Battle resolver — squad formation *guides* + individual line-of-sight combat.
//!
//! Rust is the only combat authority. The squad brain paints a moving formation field
//! (facing, interval, engagement line, morale). Each body is attracted to its slot, then
//! breaks it to fight whoever is in local perception. One loop, many kind profiles
//! (land / air / later naval). Resolved once, baked for the HD-2D replay.

use crate::ledger::{Account, Ledger, Phase};
use crate::model::{AgentKind, FactionId, ProvinceId, UnitDomain, UnitKind, World};
use crate::rng::Rng;

/// Linear scale vs the original 200×120 prototype. Combat reach stays unscaled.
pub const MAP_SCALE: f32 = 5.0;
pub const BATTLE_WIDTH: f32 = 200.0 * MAP_SCALE;
pub const BATTLE_HEIGHT: f32 = 120.0 * MAP_SCALE;
/// Hard cap for one resolve (Custom Battle stress + campaign). Viewer/FFI share this.
pub const MAX_BATTLE_UNITS: u32 = 10_000;
const DT: f32 = 1.0;
const MAX_TICKS: u32 = 1400;
const RECORD_STRIDE: u32 = 3;
const ROUT_CASUALTY_FRAC: f32 = 0.6;
const ATTACK_COOLDOWN: u32 = 3;
const GRID_CELL: f32 = 10.0;
const CONSECRATE: f32 = 8.0;
/// Gap between the two engagement lines at first bind. Individuals close to weapon reach.
const ENGAGE_GAP: f32 = 4.0;
/// Hold ST_FIRE long enough that RECORD_STRIDE still bakes a flash for the viewer.
const FIRE_HOLD: u32 = RECORD_STRIDE + 1;
/// How fast the formation *guide* marches (individuals can peel off faster).
const GUIDE_SPEED: f32 = 1.15 * MAP_SCALE;
/// After a break, squad *guides* chase the remaining enemy mass. Individual LOS stays local.
/// Close to this before slowing to shoot the fleeing backs.
const PURSUE_CONTACT: f32 = 9.0;
/// Stay this far inside the rim so chasers do not pile on the escape wall.
const PURSUE_LEASH: f32 = 8.0;

pub const ST_IDLE: u8 = 0;
pub const ST_MARCH: u8 = 1;
pub const ST_AIM: u8 = 2;
pub const ST_FIRE: u8 = 3;
pub const ST_DEAD: u8 = 4;
pub const ST_ROUT: u8 = 5;
/// Reached the map rim while routing — escaped (still a survivor, not a corpse).
pub const ST_FLED: u8 = 6;
/// Non-lethal stagger. Viewer plays a hit react; the body does not teleport-fill.
pub const ST_HIT: u8 = 7;
/// Rim band: routers that hit this fade out of the sim instead of idling at the wall.
const ESCAPE_RIM: f32 = 3.0;
/// How many ticks a wounded body holds ST_HIT before moving again.
const HIT_STAGGER: u32 = 2;
/// One bomb per pass; the aircraft flies through instead of hovering to shoot.
const BOMB_COOLDOWN: u32 = 32;
/// Horizontal window to pickle a bomb over a ground target.
const DROP_XY: f32 = 22.0;
/// How far past the enemy the outbound leg continues.
const OVERFLY: f32 = 70.0;
const GRAVITY: f32 = 0.38;
const FALL_DMG: f32 = 7.0;

/// Shared with the viewer so the diorama matches movement cost (tide still ignores height).
pub const RIVER_X: f32 = BATTLE_WIDTH * 0.5;
pub const RIVER_HALF: f32 = 6.0 * MAP_SCALE;
pub const HILL_CX: f32 = 52.0 * MAP_SCALE;
pub const HILL_CY: f32 = 92.0 * MAP_SCALE;
pub const HILL_R: f32 = 28.0 * MAP_SCALE;
/// Solid mass the viewer hill occupies. Land walks *around* this; air flies over.
pub const HILL_BLOCK_R: f32 = HILL_R * 0.92;
/// Small ruin AABB (matches the diorama boxes near the south-west corner).
pub const RUIN_CX: f32 = 20.0 * MAP_SCALE;
pub const RUIN_CY: f32 = 11.0 * MAP_SCALE;
pub const RUIN_R: f32 = 5.5 * MAP_SCALE;
/// Extra dominion dumped when the victor was not already the owner (nested result txn).
const BATTLE_CLAIM: f32 = 10.0;
const Y_PAD: f32 = 8.0 * MAP_SCALE;
const WING_Y: f32 = 24.0 * MAP_SCALE;
const DEPLOY_INSET: f32 = 32.0 * MAP_SCALE;

/// Group/regiment shape. Formation is an attractor, not a rail.
#[repr(u8)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FormationKind {
    #[default]
    Line = 0,
    DoubleLine = 1,
    Column = 2,
    Wedge = 3,
}

impl FormationKind {
    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => FormationKind::DoubleLine,
            2 => FormationKind::Column,
            3 => FormationKind::Wedge,
            _ => FormationKind::Line,
        }
    }
}

/// March intent after deploy. Attack left = enemy's left = our right as we face them.
#[repr(u8)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum BattleOrder {
    #[default]
    Front = 0,
    Left = 1,
    Right = 2,
    Rear = 3,
}

impl BattleOrder {
    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => BattleOrder::Left,
            2 => BattleOrder::Right,
            3 => BattleOrder::Rear,
            _ => BattleOrder::Front,
        }
    }
}

/// One regiment's deploy on the slab (Custom Battle / planned fight).
#[derive(Clone, Copy, Debug)]
pub struct SquadDeploy {
    pub x: f32,
    pub y: f32,
    pub facing: f32,
    pub formation: FormationKind,
    pub order: BattleOrder,
}

/// Optional Custom Battle plan. Campaign fights pass `None` (default rectangles + Front).
#[derive(Clone, Debug, Default)]
pub struct BattlePlan {
    pub order_a: BattleOrder,
    pub order_d: BattleOrder,
    pub deploys: Vec<SquadDeploy>,
}

/// Dense occupancy grid. HashMap cells made thousand-body searches scan the whole 5× slab.
struct SpatialGrid {
    cols: i32,
    rows: i32,
    buckets: Vec<Vec<usize>>,
}

impl SpatialGrid {
    fn new(cols: i32, rows: i32) -> Self {
        let cols = cols.max(1);
        let rows = rows.max(1);
        Self {
            cols,
            rows,
            buckets: vec![Vec::with_capacity(8); (cols * rows) as usize],
        }
    }

    fn cell(x: f32, y: f32) -> (i32, i32) {
        ((x / GRID_CELL).floor() as i32, (y / GRID_CELL).floor() as i32)
    }

    fn idx(&self, gx: i32, gy: i32) -> Option<usize> {
        if gx < 0 || gy < 0 || gx >= self.cols || gy >= self.rows {
            None
        } else {
            Some((gy * self.cols + gx) as usize)
        }
    }

    fn bucket(&self, gx: i32, gy: i32) -> &[usize] {
        match self.idx(gx, gy) {
            Some(i) => &self.buckets[i],
            None => &[],
        }
    }

    fn rebuild(&mut self, units: &[Unit]) {
        for b in &mut self.buckets {
            b.clear();
        }
        for (i, u) in units.iter().enumerate() {
            if !in_fight(u) {
                continue;
            }
            let (gx, gy) = Self::cell(u.x, u.y);
            if let Some(idx) = self.idx(gx, gy) {
                self.buckets[idx].push(i);
            }
        }
    }
}

#[derive(Clone, Debug)]
struct Unit {
    faction: FactionId,
    kind: UnitKind,
    squad: u32,
    x: f32,
    y: f32,
    z: f32,
    hp: f32,
    alive: bool,
    next_attack: u32,
    slot_dx: f32,
    slot_dy: f32,
    facing: u8,
    state: u8,
    aim_x: f32,
    aim_y: f32,
    hit_until: u32,
    fire_until: u32,
    vx: f32,
    vy: f32,
    vz: f32,
}

#[derive(Clone, Debug)]
struct SquadState {
    id: u32,
    initial: u32,
    routing: bool,
    faction: FactionId,
    guide_x: f32,
    guide_y: f32,
    engage_x: f32,
    engage_y: f32,
    home_x: f32,
    face_sign: f32,
    is_air: bool,
    /// Bombers fly outbound across the front, then reverse for the next pass.
    air_outbound: bool,
    order: BattleOrder,
}

/// One recorded frame (wide row) for the replay/viewer.
#[derive(Clone, Debug)]
pub struct Frame {
    pub tick: u32,
    pub units: Vec<UnitSnapshot>,
}

#[derive(Clone, Copy, Debug)]
pub struct UnitSnapshot {
    pub faction: FactionId,
    pub kind: UnitKind,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub alive: bool,
    pub facing: u8,
    pub state: u8,
    /// Aim point for fire/aim ticks (zeros when idle). Viewer tracers read this; they do not invent targets.
    pub aim_x: f32,
    pub aim_y: f32,
}

/// The finished battle report — the wide-row projection of the battle journal.
#[derive(Clone, Debug)]
pub struct BattleReport {
    pub province: ProvinceId,
    pub attacker: FactionId,
    pub defender: FactionId,
    pub winner: Option<FactionId>,
    pub ticks: u32,
    pub initial: Vec<(FactionId, u32)>,
    pub casualties: Vec<(FactionId, u32)>,
    pub survivors: Vec<(FactionId, u32)>,
    pub frames: Vec<Frame>,
    pub owner_before: Option<FactionId>,
    pub owner_after: Option<FactionId>,
    pub elevation: u8,
}

impl BattleReport {
    pub fn casualties_of(&self, f: FactionId) -> u32 {
        self.casualties.iter().find(|(k, _)| *k == f).map(|(_, v)| *v).unwrap_or(0)
    }
    pub fn survivors_of(&self, f: FactionId) -> u32 {
        self.survivors.iter().find(|(k, _)| *k == f).map(|(_, v)| *v).unwrap_or(0)
    }
    /// Reconcile the report: for each side, initial == casualties + survivors.
    pub fn reconciles(&self) -> bool {
        self.initial.iter().all(|(f, init)| {
            *init == self.casualties_of(*f) + self.survivors_of(*f)
        })
    }
    pub fn digest(&self) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut mix = |x: u64| {
            h ^= x;
            h = h.wrapping_mul(0x0000_0100_0000_01B3);
        };
        mix(self.ticks as u64);
        mix(self.winner.map(|w| w as u64 + 1).unwrap_or(0));
        mix(self.owner_after.map(|w| w as u64 + 1).unwrap_or(0));
        mix(self.elevation as u64);
        for (f, c) in &self.casualties {
            mix(*f as u64);
            mix(*c as u64);
        }
        h
    }
}

/// Resolve a battle between all armies of `attacker` vs `defender` sitting in `province`.
/// Applies casualties + consecration back to the World ledger and prunes the armies.
pub fn resolve_battle_in_province(
    world: &mut World,
    ledger: &mut Ledger,
    province: ProvinceId,
    attacker: FactionId,
    defender: FactionId,
    base_seed: u64,
) -> BattleReport {
    resolve_battle_with_plan(world, ledger, province, attacker, defender, base_seed, None)
}

/// Same as [`resolve_battle_in_province`], with an optional Custom Battle deploy/order plan.
pub fn resolve_battle_with_plan(
    world: &mut World,
    ledger: &mut Ledger,
    province: ProvinceId,
    attacker: FactionId,
    defender: FactionId,
    base_seed: u64,
    plan: Option<&BattlePlan>,
) -> BattleReport {
    let owner_before = world.provinces[province as usize].owner(&world.cfg);
    let elevation = world.provinces[province as usize].elevation;
    let elev_f = elevation as f32;
    let mut atk_mod = std::collections::HashMap::new();
    let mut perc_mod = std::collections::HashMap::new();
    let mut rout_frac = std::collections::HashMap::new();
    for &f in &[attacker, defender] {
        atk_mod.insert(f, faction_attack_mod(world, f, province));
        perc_mod.insert(f, faction_perception_mod(world, f, province));
        rout_frac.insert(f, faction_rout_frac(world, f, province));
    }

    // Collect squads present for each side (indexes into world.armies).
    let sides = [attacker, defender];
    let mut units: Vec<Unit> = Vec::new();
    let mut squads: Vec<SquadState> = Vec::new();
    let mut next_sid = 0u32;

    for (side_idx, &fac) in sides.iter().enumerate() {
        for army in world.armies.iter().filter(|a| a.faction == fac && a.province == province) {
            for src in &army.squads {
                if src.count == 0 {
                    continue;
                }
                for part in src.clone().into_regiments() {
                    if units.len() as u32 >= MAX_BATTLE_UNITS {
                        break;
                    }
                    let take = part
                        .count
                        .min(MAX_BATTLE_UNITS.saturating_sub(units.len() as u32));
                    if take == 0 {
                        break;
                    }
                    let sid = next_sid;
                    next_sid += 1;
                    let is_air = part.kind.domain() == UnitDomain::Air;
                    squads.push(SquadState {
                        id: sid,
                        initial: take,
                        routing: false,
                        faction: fac,
                        guide_x: 0.0,
                        guide_y: BATTLE_HEIGHT * 0.5,
                        engage_x: 0.0,
                        engage_y: BATTLE_HEIGHT * 0.5,
                        home_x: 0.0,
                        face_sign: 0.0,
                        is_air,
                        air_outbound: true,
                        order: BattleOrder::Front,
                    });
                    for _ in 0..take {
                        units.push(Unit {
                            faction: fac,
                            kind: part.kind,
                            squad: sid,
                            x: 0.0,
                            y: 0.0,
                            z: part.kind.cruise_z(),
                            hp: part.kind.base_hp(),
                            alive: true,
                            next_attack: 0,
                            slot_dx: 0.0,
                            slot_dy: 0.0,
                            facing: if side_idx == 0 { 0 } else { 4 },
                            state: ST_IDLE,
                            aim_x: 0.0,
                            aim_y: 0.0,
                            hit_until: 0,
                            fire_until: 0,
                            vx: 0.0,
                            vy: 0.0,
                            vz: 0.0,
                        });
                    }
                }
            }
        }
    }

    let order_a = plan.map(|p| p.order_a).unwrap_or(BattleOrder::Front);
    let order_d = plan.map(|p| p.order_d).unwrap_or(BattleOrder::Front);
    let use_plan = plan
        .map(|p| p.deploys.len() == squads.len() && !p.deploys.is_empty())
        .unwrap_or(false);
    if use_plan {
        if let Some(p) = plan {
            layout_from_plan(&mut units, &squads, p);
        }
    }
    for (side_idx, &fac) in sides.iter().enumerate() {
        let baseline = if side_idx == 0 { DEPLOY_INSET } else { BATTLE_WIDTH - DEPLOY_INSET };
        let dir = if side_idx == 0 { 1.0 } else { -1.0 };
        if !use_plan {
            layout_regiment_blocks(&mut units, &squads, fac, baseline, dir);
        }
        let _ = dir;
    }
    relax_deploy(&mut units);
    for (side_idx, &fac) in sides.iter().enumerate() {
        let baseline = if side_idx == 0 { DEPLOY_INSET } else { BATTLE_WIDTH - DEPLOY_INSET };
        let dir = if side_idx == 0 { 1.0 } else { -1.0 };
        let contact = if side_idx == 0 {
            BATTLE_WIDTH * 0.5 - ENGAGE_GAP * 0.5
        } else {
            BATTLE_WIDTH * 0.5 + ENGAGE_GAP * 0.5
        };
        let order = if side_idx == 0 { order_a } else { order_d };
        let deploys = if use_plan {
            plan.map(|p| p.deploys.as_slice())
        } else {
            None
        };
        bind_squad_guides(
            &mut squads,
            &mut units,
            fac,
            baseline,
            contact,
            dir,
            order,
            deploys,
        );
    }

    let initial: Vec<(FactionId, u32)> = sides
        .iter()
        .map(|&f| (f, units.iter().filter(|u| u.faction == f).count() as u32))
        .collect();

    let mut rng = Rng::stream(base_seed, world.turn, Phase::Battles.stream_key(), province as u64);
    let mut frames: Vec<Frame> = Vec::new();
    let mut tick = 0u32;

    record_frame(&mut frames, tick, &units);

    let grid_cols = (BATTLE_WIDTH / GRID_CELL).ceil() as i32 + 1;
    let grid_rows = (BATTLE_HEIGHT / GRID_CELL).ceil() as i32 + 1;
    let mut grid = SpatialGrid::new(grid_cols, grid_rows);
    while tick < MAX_TICKS && both_sides_fighting(&units, attacker, defender) {
        tick += 1;
        update_squad_morale(&mut squads, &units, &rout_frac);
        march_guides(&mut squads, &units);
        let routing_a = squads.iter().any(|s| s.faction == attacker && s.routing);
        let routing_d = squads.iter().any(|s| s.faction == defender && s.routing);

        grid.rebuild(&units);

        for i in 0..units.len() {
            if !units[i].alive {
                units[i].state = ST_DEAD;
                if airborne(&units[i]) {
                    step_ballistic(&mut units[i]);
                }
                continue;
            }
            if units[i].state == ST_FLED {
                continue;
            }
            if airborne(&units[i]) {
                step_ballistic(&mut units[i]);
                if units[i].alive && units[i].z > 0.12 {
                    units[i].state = ST_HIT;
                }
                continue;
            }
            let (ux, uy, uz, kind, fac, squad_id) = {
                let u = &units[i];
                (u.x, u.y, u.z, u.kind, u.faction, u.squad)
            };
            let sq_i = squad_id as usize;
            if sq_i >= squads.len() {
                continue;
            }
            let routing = squads[sq_i].routing;
            let slot_x = squads[sq_i].guide_x + units[i].slot_dx;
            let slot_y = squads[sq_i].guide_y + units[i].slot_dy;
            let face_sign = squads[sq_i].face_sign;
            let cohesion = kind.cohesion();
            let speed = kind.move_speed()
                * MAP_SCALE
                * terrain_speed(ux, uy, elev_f, kind.domain());
            let reach = kind.reach();
            // Local LOS only. Map scale is for march distance, not "see the whole slab".
            let perception = kind.perception() * perc_mod.get(&fac).copied().unwrap_or(1.0);
            let cruise_z = kind.cruise_z();
            let enemy_routing = if fac == attacker { routing_d } else { routing_a };
            let is_air = kind.domain() == UnitDomain::Air;

            if routing {
                units[i].x += -face_sign * speed * 1.35 * DT;
                units[i].x = units[i].x.clamp(1.0, BATTLE_WIDTH - 1.0);
                if !is_air {
                    let (x, y) = slide_land(units[i].x, units[i].y);
                    units[i].x = x;
                    units[i].y = y;
                }
                units[i].z = cruise_z;
                units[i].facing = octant(-face_sign, 0.0);
                units[i].aim_x = 0.0;
                units[i].aim_y = 0.0;
                if at_home_rim(units[i].x, face_sign) {
                    units[i].state = ST_FLED;
                } else {
                    units[i].state = ST_ROUT;
                }
                continue;
            }

            if units[i].hit_until >= tick && units[i].kind.domain() != UnitDomain::Air {
                units[i].state = ST_HIT;
                continue;
            }

            let (target, dist) = nearest_enemy(i, ux, uy, uz, fac, perception, &units, &grid);

            if is_air {
                let dest_x = if enemy_routing {
                    target.map(|j| units[j].x).unwrap_or(slot_x)
                } else if squads[sq_i].air_outbound {
                    squads[sq_i].engage_x + face_sign * OVERFLY
                } else {
                    squads[sq_i].home_x + face_sign * 4.0
                };
                let dest_y = squads[sq_i].engage_y + units[i].slot_dy;
                let dx = dest_x - ux;
                let dy = dest_y - uy;
                let d = (dx * dx + dy * dy).sqrt();
                let step = speed * DT;
                if d > 0.4 {
                    units[i].x += dx / d * step;
                    units[i].y += dy / d * step;
                }
                let (fdx, fdy) = if let Some(j) = target {
                    units[i].aim_x = units[j].x;
                    units[i].aim_y = units[j].y;
                    (units[j].x - ux, units[j].y - uy)
                } else {
                    units[i].aim_x = 0.0;
                    units[i].aim_y = 0.0;
                    (dx, dy)
                };
                units[i].z = cruise_z;
                let (xmin, xmax) = if enemy_routing {
                    (
                        ESCAPE_RIM + PURSUE_LEASH,
                        BATTLE_WIDTH - ESCAPE_RIM - PURSUE_LEASH,
                    )
                } else {
                    (2.0, BATTLE_WIDTH - 2.0)
                };
                units[i].x = units[i].x.clamp(xmin, xmax);
                units[i].y = units[i].y.clamp(2.0, BATTLE_HEIGHT - 2.0);
                units[i].facing = octant(fdx, fdy);
                units[i].state = ST_MARCH;
                hold_fire_pose(&mut units[i], tick);
                continue;
            }

            let (state, fdx, fdy) = if let Some(j) = target {
                let (ex, ey) = (units[j].x, units[j].y);
                units[i].aim_x = ex;
                units[i].aim_y = ey;
                let fdx = ex - ux;
                let fdy = ey - uy;
                let target_routing = units[j].state == ST_ROUT
                    || squads
                        .get(units[j].squad as usize)
                        .map(|s| s.routing)
                        .unwrap_or(false);
                if target_routing {
                    let inv = 1.0 / dist.max(1e-3);
                    let close = speed * 1.3 * DT;
                    if dist > PURSUE_CONTACT {
                        units[i].x += fdx * inv * close;
                        units[i].y += fdy * inv * close;
                        (ST_MARCH, fdx, fdy)
                    } else {
                        units[i].x += fdx * inv * close * 0.28;
                        units[i].y += fdy * inv * close * 0.28;
                        (ST_AIM, fdx, fdy)
                    }
                } else if dist <= reach {
                    units[i].x += (slot_x - ux) * cohesion * 0.12;
                    units[i].y += (slot_y - uy) * cohesion * 0.12;
                    (ST_AIM, fdx, fdy)
                } else {
                    let inv = 1.0 / dist.max(1e-3);
                    let close = (1.0 - cohesion * 0.35) * speed * DT;
                    units[i].x += fdx * inv * close + (slot_x - ux) * cohesion * 0.25;
                    units[i].y += fdy * inv * close + (slot_y - uy) * cohesion * 0.25;
                    (ST_MARCH, fdx, fdy)
                }
            } else {
                units[i].aim_x = 0.0;
                units[i].aim_y = 0.0;
                let dx = slot_x - ux;
                let dy = slot_y - uy;
                let d = (dx * dx + dy * dy).sqrt();
                if d > 0.35 {
                    let step = speed.min(d) * DT;
                    units[i].x += dx / d * step;
                    units[i].y += dy / d * step;
                    (ST_MARCH, dx, dy)
                } else {
                    units[i].x = slot_x;
                    units[i].y = slot_y;
                    (ST_IDLE, face_sign, 0.0)
                }
            };

            units[i].z += (cruise_z - units[i].z) * 0.35;
            let (xmin, xmax) = if enemy_routing {
                (
                    ESCAPE_RIM + PURSUE_LEASH,
                    BATTLE_WIDTH - ESCAPE_RIM - PURSUE_LEASH,
                )
            } else {
                (2.0, BATTLE_WIDTH - 2.0)
            };
            units[i].x = units[i].x.clamp(xmin, xmax);
            units[i].y = units[i].y.clamp(2.0, BATTLE_HEIGHT - 2.0);
            let (x, y) = slide_land(units[i].x, units[i].y);
            units[i].x = x;
            units[i].y = y;
            units[i].facing = octant(fdx, fdy);
            units[i].state = state;
            hold_fire_pose(&mut units[i], tick);
        }

        separate_bodies(&mut units, &mut grid);
        apply_land_slide(&mut units);
        grid.rebuild(&units);

        let mut hits: Vec<(usize, usize, f32)> = Vec::new();
        let mut bombs: Vec<(usize, f32, f32, f32, f32)> = Vec::new();
        for i in 0..units.len() {
            if !in_fight(&units[i]) || units[i].state == ST_ROUT {
                continue;
            }
            if airborne(&units[i]) {
                continue;
            }
            let sq_i = units[i].squad as usize;
            if sq_i >= squads.len() || squads[sq_i].routing {
                continue;
            }
            if tick < units[i].next_attack || units[i].hit_until >= tick {
                continue;
            }
            let (ux, uy, uz, kind, fac) = {
                let u = &units[i];
                (u.x, u.y, u.z, u.kind, u.faction)
            };
            let jitter = 0.9 + 0.2 * rng.next_f32();
            let am = atk_mod.get(&fac).copied().unwrap_or(1.0);
            if kind.domain() == UnitDomain::Air {
                if !squads[sq_i].air_outbound {
                    continue;
                }
                let (target, dist) = nearest_land_enemy_xy(i, ux, uy, fac, DROP_XY, &units, &grid);
                let Some(j) = target else {
                    continue;
                };
                if dist > DROP_XY {
                    continue;
                }
                let radius = kind.blast_radius();
                if radius <= 0.01 {
                    continue;
                }
                bombs.push((
                    i,
                    units[j].x,
                    units[j].y,
                    kind.base_attack() * jitter * am,
                    radius,
                ));
                continue;
            }
            let (target, dist) = nearest_enemy(i, ux, uy, uz, fac, kind.reach(), &units, &grid);
            let Some(j) = target else {
                continue;
            };
            if dist > kind.reach() {
                continue;
            }
            let mut dmg = kind.base_attack() * jitter * am;
            if units[j].kind.domain() == UnitDomain::Air {
                dmg *= kind.vs_air();
            }
            hits.push((i, j, dmg));
        }
        for (i, j, dmg) in hits {
            if !in_fight(&units[j]) {
                continue;
            }
            let (tx, ty) = (units[j].x, units[j].y);
            units[j].hp -= dmg;
            if units[j].hp <= 0.0 {
                units[j].alive = false;
                units[j].state = ST_DEAD;
            } else if units[j].kind.domain() != UnitDomain::Air {
                // Small-arms do not pin aircraft. A staggered bomber becomes a piñata.
                units[j].state = ST_HIT;
                units[j].hit_until = tick + HIT_STAGGER;
            }
            let (ux, uy) = (units[i].x, units[i].y);
            units[i].next_attack = tick + ATTACK_COOLDOWN;
            units[i].state = ST_FIRE;
            units[i].fire_until = tick + FIRE_HOLD;
            units[i].facing = octant(tx - ux, ty - uy);
            units[i].aim_x = tx;
            units[i].aim_y = ty;
        }
        for (i, bx, by, dmg, radius) in bombs {
            if !in_fight(&units[i]) {
                continue;
            }
            apply_blast(&mut units, bx, by, radius, dmg, &mut rng);
            units[i].next_attack = tick + BOMB_COOLDOWN;
            units[i].state = ST_FIRE;
            units[i].fire_until = tick + FIRE_HOLD;
            units[i].aim_x = bx;
            units[i].aim_y = by;
            units[i].facing = octant(bx - units[i].x, by - units[i].y);
        }

        if tick % RECORD_STRIDE == 0 {
            record_frame(&mut frames, tick, &units);
        }
    }
    record_frame(&mut frames, tick, &units);

    // Tally.
    let survivors: Vec<(FactionId, u32)> = sides
        .iter()
        .map(|&f| (f, units.iter().filter(|u| u.alive && u.faction == f).count() as u32))
        .collect();
    let casualties: Vec<(FactionId, u32)> = initial
        .iter()
        .map(|(f, init)| {
            let surv = survivors.iter().find(|(k, _)| k == f).map(|(_, v)| *v).unwrap_or(0);
            (*f, init - surv)
        })
        .collect();

    let a_alive = survivors.iter().find(|(f, _)| *f == attacker).map(|(_, v)| *v).unwrap_or(0);
    let d_alive = survivors.iter().find(|(f, _)| *f == defender).map(|(_, v)| *v).unwrap_or(0);
    let winner = match a_alive.cmp(&d_alive) {
        std::cmp::Ordering::Greater => Some(attacker),
        std::cmp::Ordering::Less => Some(defender),
        std::cmp::Ordering::Equal => None,
    };

    // Post casualties back to the World ledger (alive → casualties transfer, per faction).
    for (f, c) in &casualties {
        if *c > 0 {
            ledger.post(
                world.turn,
                Phase::Battles,
                "casualties",
                vec![
                    (Account::UnitsAlive(*f), -(*c as f64)),
                    (Account::Casualties(*f), *c as f64),
                ],
                format!("battle prov{province} f{f} lost {c}"),
            );
        }
    }

    // Prune casualties from the armies (front squads first, deterministic by army/squad order).
    for &f in &sides {
        let mut to_remove = casualties.iter().find(|(k, _)| *k == f).map(|(_, v)| *v).unwrap_or(0);
        for army in world.armies.iter_mut().filter(|a| a.faction == f && a.province == province) {
            for sq in army.squads.iter_mut() {
                if to_remove == 0 {
                    break;
                }
                let take = to_remove.min(sq.count);
                sq.count -= take;
                to_remove -= take;
            }
        }
    }
    world.armies.retain(|a| !a.is_empty());

    // Victor consecrates the province; if they were not already owner, claim extra mass so the
    // nested battle result can flip the majority (tide still ignores elevation).
    if let Some(w) = winner {
        world.provinces[province as usize].dom[w as usize] += CONSECRATE;
        world.provinces[province as usize].revealed = true;
        ledger.post(
            world.turn,
            Phase::Battles,
            "consecrate",
            vec![
                (Account::Dominion(w), CONSECRATE as f64),
                (Account::DominionSource(w), -(CONSECRATE as f64)),
            ],
            format!("victor f{w} consecrates prov{province}"),
        );
        if owner_before != Some(w) {
            world.provinces[province as usize].dom[w as usize] += BATTLE_CLAIM;
            ledger.post(
                world.turn,
                Phase::Battles,
                "battle_claim",
                vec![
                    (Account::Dominion(w), BATTLE_CLAIM as f64),
                    (Account::DominionSource(w), -(BATTLE_CLAIM as f64)),
                ],
                format!("battle_result prov{province} f{w} claims the field"),
            );
        }
    }
    ledger.assert_balanced();
    let owner_after = world.provinces[province as usize].owner(&world.cfg);

    BattleReport {
        province,
        attacker,
        defender,
        winner,
        ticks: tick,
        initial,
        casualties,
        survivors,
        frames,
        owner_before,
        owner_after,
        elevation,
    }
}

fn hold_fire_pose(u: &mut Unit, tick: u32) {
    if u.fire_until >= tick
        && u.alive
        && u.state != ST_DEAD
        && u.state != ST_ROUT
        && u.state != ST_FLED
        && u.state != ST_HIT
    {
        u.state = ST_FIRE;
    }
}

fn in_fight(u: &Unit) -> bool {
    u.alive && u.state != ST_FLED
}

/// Land movement cost. Air ignores ground. Hill/river match the viewer diorama uniforms.
pub fn terrain_speed(x: f32, y: f32, elevation: f32, domain: UnitDomain) -> f32 {
    if domain != UnitDomain::Land {
        return 1.0;
    }
    let dx = x - HILL_CX;
    let dy = y - HILL_CY;
    let hill = (dx * dx + dy * dy).sqrt();
    let hill_slow = if hill < HILL_R {
        0.62 + 0.38 * (hill / HILL_R)
    } else {
        1.0
    };
    let river = (x - RIVER_X).abs();
    let river_slow = if river < RIVER_HALF { 0.70 } else { 1.0 };
    let elev_slow = 1.0 - (elevation / 220.0).clamp(0.0, 0.22);
    (hill_slow * river_slow * elev_slow).clamp(0.45, 1.0)
}

fn faction_attack_mod(world: &World, fac: FactionId, province: ProvinceId) -> f32 {
    let mut m = 1.0;
    for a in world.agents.iter().filter(|a| a.alive && a.province == province) {
        if a.faction == fac {
            match a.kind {
                AgentKind::Prophet => m += 0.12 + 0.03 * a.level as f32,
                AgentKind::Priest => m += 0.06 + 0.02 * a.level as f32,
                AgentKind::Scout => m += 0.04,
                _ => {}
            }
        } else if a.kind == AgentKind::Spy {
            m -= 0.08 + 0.02 * a.level as f32;
        }
    }
    m.clamp(0.55, 1.65)
}

fn faction_perception_mod(world: &World, fac: FactionId, province: ProvinceId) -> f32 {
    let mut m: f32 = 1.0;
    for a in world
        .agents
        .iter()
        .filter(|a| a.alive && a.faction == fac && a.province == province)
    {
        if a.kind == AgentKind::Scout {
            m += 0.18;
        }
    }
    m.min(1.4)
}

fn faction_rout_frac(world: &World, fac: FactionId, province: ProvinceId) -> f32 {
    let mut t = ROUT_CASUALTY_FRAC;
    for a in world
        .agents
        .iter()
        .filter(|a| a.alive && a.faction == fac && a.province == province)
    {
        if matches!(a.kind, AgentKind::Prophet | AgentKind::Priest) {
            t += 0.06 + 0.02 * a.level as f32;
        }
    }
    t.min(0.85)
}

fn at_home_rim(x: f32, face_sign: f32) -> bool {
    if face_sign > 0.0 {
        x <= ESCAPE_RIM
    } else {
        x >= BATTLE_WIDTH - ESCAPE_RIM
    }
}

fn both_sides_fighting(units: &[Unit], a: FactionId, d: FactionId) -> bool {
    let fighting = |f: FactionId| units.iter().any(|u| in_fight(u) && u.faction == f);
    fighting(a) && fighting(d)
}

fn in_circle(x: f32, y: f32, cx: f32, cy: f32, r: f32) -> bool {
    let dx = x - cx;
    let dy = y - cy;
    dx * dx + dy * dy < r * r
}

/// Land occupancy: hill and ruin are solid; the river is a ford, not a wall.
pub fn land_blocked(x: f32, y: f32) -> bool {
    in_circle(x, y, HILL_CX, HILL_CY, HILL_BLOCK_R) || in_circle(x, y, RUIN_CX, RUIN_CY, RUIN_R)
}

fn push_out(x: f32, y: f32, cx: f32, cy: f32, r: f32) -> (f32, f32) {
    let dx = x - cx;
    let dy = y - cy;
    let d = (dx * dx + dy * dy).sqrt().max(1e-3);
    (cx + dx / d * r, cy + dy / d * r)
}

pub fn slide_land(x: f32, y: f32) -> (f32, f32) {
    let mut x = x;
    let mut y = y;
    for _ in 0..3 {
        if in_circle(x, y, HILL_CX, HILL_CY, HILL_BLOCK_R) {
            (x, y) = push_out(x, y, HILL_CX, HILL_CY, HILL_BLOCK_R + 1.6);
        }
        if in_circle(x, y, RUIN_CX, RUIN_CY, RUIN_R) {
            (x, y) = push_out(x, y, RUIN_CX, RUIN_CY, RUIN_R + 1.2);
        }
    }
    (
        x.clamp(2.0, BATTLE_WIDTH - 2.0),
        y.clamp(2.0, BATTLE_HEIGHT - 2.0),
    )
}

fn slide_land_pad(x: f32, y: f32, pad: f32) -> (f32, f32) {
    let hill_r = HILL_BLOCK_R + pad + 1.6;
    let ruin_r = RUIN_R + pad + 1.2;
    let mut x = x;
    let mut y = y;
    if in_circle(x, y, RUIN_CX, RUIN_CY, ruin_r) {
        (x, y) = push_out(x, y, RUIN_CX, RUIN_CY, ruin_r);
    }
    if !in_circle(x, y, HILL_CX, HILL_CY, hill_r) {
        return (
            x.clamp(4.0, BATTLE_WIDTH - 4.0),
            y.clamp(4.0, BATTLE_HEIGHT - 4.0),
        );
    }
    let mut best = (x, y);
    let mut best_d = f32::MAX;
    let n = 48;
    for i in 0..n {
        let a = (i as f32) * std::f32::consts::TAU / n as f32;
        let hx = HILL_CX + a.cos() * hill_r;
        let hy = HILL_CY + a.sin() * hill_r;
        if hx < 8.0 || hx > BATTLE_WIDTH - 8.0 || hy < 8.0 || hy > BATTLE_HEIGHT - 8.0 {
            continue;
        }
        if in_circle(hx, hy, RUIN_CX, RUIN_CY, ruin_r) {
            continue;
        }
        let d = (hx - x).hypot(hy - y);
        if d < best_d {
            best_d = d;
            best = (hx, hy);
        }
    }
    if best_d < f32::MAX {
        return best;
    }
    let (x, y) = push_out(x, y, HILL_CX, HILL_CY, hill_r);
    (
        x.clamp(4.0, BATTLE_WIDTH - 4.0),
        y.clamp(4.0, BATTLE_HEIGHT - 4.0),
    )
}

fn apply_land_slide(units: &mut [Unit]) {
    for u in units.iter_mut() {
        if !in_fight(u) || u.kind.domain() != UnitDomain::Land {
            continue;
        }
        if airborne(u) {
            continue;
        }
        if !land_blocked(u.x, u.y) {
            continue;
        }
        let (x, y) = slide_land(u.x, u.y);
        u.x = x;
        u.y = y;
    }
}

fn relax_deploy(units: &mut [Unit]) {
    let cols = (BATTLE_WIDTH / GRID_CELL).ceil() as i32 + 1;
    let rows = (BATTLE_HEIGHT / GRID_CELL).ceil() as i32 + 1;
    let mut grid = SpatialGrid::new(cols, rows);
    for _ in 0..3 {
        separate_bodies(units, &mut grid);
    }
    apply_land_slide(units);
}

fn order_engage_y(order: BattleOrder, face_sign: f32, guide_y: f32) -> f32 {
    match order {
        BattleOrder::Front => guide_y,
        // Attack left = enemy's left = our right as we face them.
        BattleOrder::Left => {
            if face_sign > 0.0 {
                WING_Y
            } else {
                BATTLE_HEIGHT - WING_Y
            }
        }
        BattleOrder::Right => {
            if face_sign > 0.0 {
                BATTLE_HEIGHT - WING_Y
            } else {
                WING_Y
            }
        }
        BattleOrder::Rear => {
            if guide_y < BATTLE_HEIGHT * 0.5 {
                Y_PAD
            } else {
                BATTLE_HEIGHT - Y_PAD
            }
        }
    }
}

fn guide_dest(s: &SquadState) -> (f32, f32) {
    match s.order {
        BattleOrder::Rear => {
            let wrap_y = s.engage_y;
            let enemy_home = if s.face_sign > 0.0 {
                BATTLE_WIDTH - DEPLOY_INSET
            } else {
                DEPLOY_INSET
            };
            if (s.guide_y - wrap_y).abs() > 5.0 {
                (s.guide_x, wrap_y)
            } else {
                (enemy_home, wrap_y)
            }
        }
        _ => (s.engage_x, s.engage_y),
    }
}

fn step_toward(x: f32, y: f32, tx: f32, ty: f32, step: f32) -> (f32, f32) {
    let dx = tx - x;
    let dy = ty - y;
    let d = (dx * dx + dy * dy).sqrt();
    if d <= step || d < 1e-4 {
        (tx, ty)
    } else {
        (x + dx / d * step, y + dy / d * step)
    }
}

fn layout_from_plan(units: &mut [Unit], squads: &[SquadState], plan: &BattlePlan) {
    for (i, s) in squads.iter().enumerate() {
        let d = plan.deploys[i];
        place_squad_at(units, s.id, d.x, d.y, d.facing, d.formation, s.is_air);
    }
}

fn formation_slots(
    count: usize,
    sp: f32,
    formation: FormationKind,
    air: bool,
) -> Vec<(f32, f32)> {
    if count == 0 {
        return Vec::new();
    }
    if air {
        let w = (count.saturating_sub(1) as f32) * sp * 1.4;
        return (0..count)
            .map(|m| (0.0, m as f32 * sp * 1.4 - w * 0.5))
            .collect();
    }
    let mut slots: Vec<(f32, f32)> = Vec::with_capacity(count);
    match formation {
        FormationKind::Line => {
            let files = count.min(20).max(1);
            let ranks = (count + files - 1) / files;
            fill_grid(&mut slots, count, files, ranks, sp, 1.0);
        }
        FormationKind::DoubleLine => {
            let files = ((count + 1) / 2).min(16).max(1);
            let ranks = (count + files - 1) / files;
            fill_grid(&mut slots, count, files, ranks, sp, 1.55);
        }
        FormationKind::Column => {
            let files = count.min(6).max(1);
            let ranks = (count + files - 1) / files;
            fill_grid(&mut slots, count, files, ranks, sp, 1.0);
        }
        FormationKind::Wedge => {
            let mut placed = 0usize;
            let mut rank = 0usize;
            while placed < count {
                let files = (3 + rank * 2).min(18);
                let take = files.min(count - placed);
                let w = (take.saturating_sub(1) as f32) * sp;
                for i in 0..take {
                    let left = i as f32 * sp - w * 0.5;
                    let fwd = -(rank as f32) * sp * 1.05;
                    slots.push((fwd, left));
                }
                placed += take;
                rank += 1;
            }
        }
    }
    if slots.len() > 1 {
        let n = slots.len() as f32;
        let mf = slots.iter().map(|c| c.0).sum::<f32>() / n;
        let ml = slots.iter().map(|c| c.1).sum::<f32>() / n;
        for c in &mut slots {
            c.0 -= mf;
            c.1 -= ml;
        }
    }
    slots
}

fn fill_grid(slots: &mut Vec<(f32, f32)>, count: usize, files: usize, ranks: usize, sp: f32, rank_gap: f32) {
    let fw = (files.saturating_sub(1) as f32) * sp;
    let rd = (ranks.saturating_sub(1) as f32) * sp * rank_gap;
    for m in 0..count {
        let file = m % files;
        let rank = m / files;
        let fwd = rd * 0.5 - rank as f32 * sp * rank_gap;
        let left = file as f32 * sp - fw * 0.5;
        slots.push((fwd, left));
    }
}

fn place_squad_at(
    units: &mut [Unit],
    sid: u32,
    ox: f32,
    oy: f32,
    facing: f32,
    formation: FormationKind,
    air: bool,
) {
    let members: Vec<usize> = units
        .iter()
        .enumerate()
        .filter(|(_, u)| u.squad == sid)
        .map(|(i, _)| i)
        .collect();
    if members.is_empty() {
        return;
    }
    let kind = units[members[0]].kind;
    let sp = kind.spacing();
    let slots = formation_slots(members.len(), sp, formation, air);
    let (fx, fy) = (facing.cos(), facing.sin());
    let (lx, ly) = (-fy, fx);
    let face = octant(fx, fy);
    let (ox, oy) = if air || !land_blocked(ox, oy) {
        (ox, oy)
    } else {
        slide_land_pad(ox, oy, 8.0 * MAP_SCALE)
    };
    for (m, &ui) in members.iter().enumerate() {
        let (fwd, left) = slots.get(m).copied().unwrap_or((0.0, 0.0));
        let x = ox + fx * fwd + lx * left;
        let y = oy + fy * fwd + ly * left;
        units[ui].x = x.clamp(2.0, BATTLE_WIDTH - 2.0);
        units[ui].y = y.clamp(2.0, BATTLE_HEIGHT - 2.0);
        units[ui].z = kind.cruise_z();
        units[ui].facing = face;
    }
}

fn layout_regiment_blocks(
    units: &mut [Unit],
    squads: &[SquadState],
    fac: FactionId,
    baseline: f32,
    dir: f32,
) {
    let mut land: Vec<u32> = Vec::new();
    let mut air: Vec<u32> = Vec::new();
    for s in squads.iter().filter(|s| s.faction == fac) {
        if s.is_air {
            air.push(s.id);
        } else {
            land.push(s.id);
        }
    }
    place_blocks(units, &land, baseline, dir, false);
    place_blocks(units, &air, baseline - dir * 10.0 * MAP_SCALE, dir, true);
}

fn place_blocks(units: &mut [Unit], sids: &[u32], baseline: f32, dir: f32, air: bool) {
    if sids.is_empty() {
        return;
    }
    let n = sids.len();
    let along_y = n.min(12).max(1);
    let y_pad = Y_PAD;
    let mut y_hi = BATTLE_HEIGHT - y_pad;
    if !air {
        y_hi = y_hi
            .min(HILL_CY - HILL_BLOCK_R - 10.0 * MAP_SCALE)
            .max(y_pad + 24.0 * MAP_SCALE);
    }
    let usable = (y_hi - y_pad).max(8.0);
    for (k, &sid) in sids.iter().enumerate() {
        let members: Vec<usize> = units
            .iter()
            .enumerate()
            .filter(|(_, u)| u.squad == sid)
            .map(|(i, _)| i)
            .collect();
        if members.is_empty() {
            continue;
        }
        let kind = units[members[0]].kind;
        let sp = kind.spacing();
        let count = members.len();
        let files = if air {
            count.max(1)
        } else {
            ((count as f32).sqrt().round() as usize).clamp(4, 12)
        };
        let ranks = (count + files - 1) / files;
        let col = k / along_y;
        let row = k % along_y;
        let cy = if along_y <= 1 {
            y_pad + usable * 0.5
        } else {
            y_pad + usable * (row as f32) / (along_y as f32 - 1.0)
        };
        let block_h = (files.saturating_sub(1) as f32) * sp;
        let x0 = baseline - dir * col as f32 * (ranks as f32 * sp + 7.0);
        let face = if dir > 0.0 { 0 } else { 4 };
        let (ox, oy) = (x0, cy);
        for (m, &ui) in members.iter().enumerate() {
            let file = m % files;
            let rank = m / files;
            units[ui].x = ox - dir * rank as f32 * sp;
            units[ui].y = (oy - block_h * 0.5 + file as f32 * sp).clamp(4.0, BATTLE_HEIGHT - 4.0);
            units[ui].z = kind.cruise_z();
            units[ui].facing = face;
        }
    }
}

fn separate_bodies(units: &mut [Unit], grid: &mut SpatialGrid) {
    let n = units.len();
    for _ in 0..2 {
        grid.rebuild(units);
        let mut px = vec![0.0f32; n];
        let mut py = vec![0.0f32; n];
        for i in 0..n {
            if !in_fight(&units[i]) {
                continue;
            }
            if airborne(&units[i]) {
                continue;
            }
            let (ux, uy, uz, di, ri) = {
                let u = &units[i];
                (u.x, u.y, u.z, u.kind.domain(), u.kind.spacing())
            };
            let (cx, cy) = SpatialGrid::cell(ux, uy);
            for gy in (cy - 1)..=(cy + 1) {
                for gx in (cx - 1)..=(cx + 1) {
                    for &j in grid.bucket(gx, gy) {
                        if j <= i || !in_fight(&units[j]) {
                            continue;
                        }
                        if airborne(&units[j]) {
                            continue;
                        }
                        if units[j].kind.domain() != di {
                            continue;
                        }
                        let dx = units[j].x - ux;
                        let dy = units[j].y - uy;
                        let dz = units[j].z - uz;
                        let d2 = dx * dx + dy * dy + dz * dz;
                        let min_d = (ri + units[j].kind.spacing()) * 0.5;
                        if d2 >= min_d * min_d {
                            continue;
                        }
                        let d = d2.sqrt();
                        let (nx, ny) = if d < 1e-3 {
                            let s = if i % 2 == 0 { 1.0 } else { -1.0 };
                            (0.0, s)
                        } else {
                            (dx / d, dy / d)
                        };
                        let push = (min_d - d) * 0.52;
                        px[i] -= nx * push;
                        py[i] -= ny * push;
                        px[j] += nx * push;
                        py[j] += ny * push;
                    }
                }
            }
        }
        for i in 0..n {
            if !in_fight(&units[i]) {
                continue;
            }
            if airborne(&units[i]) {
                continue;
            }
            units[i].x = (units[i].x + px[i]).clamp(2.0, BATTLE_WIDTH - 2.0);
            units[i].y = (units[i].y + py[i]).clamp(2.0, BATTLE_HEIGHT - 2.0);
        }
    }
}

fn bind_squad_guides(
    squads: &mut [SquadState],
    units: &mut [Unit],
    fac: FactionId,
    baseline: f32,
    contact: f32,
    dir: f32,
    default_order: BattleOrder,
    deploys: Option<&[SquadDeploy]>,
) {
    for (si, s) in squads.iter_mut().enumerate() {
        if s.faction != fac {
            continue;
        }
        let mut sx = 0.0;
        let mut sy = 0.0;
        let mut n = 0.0;
        for u in units.iter().filter(|u| u.squad == s.id) {
            sx += u.x;
            sy += u.y;
            n += 1.0;
        }
        if n > 0.0 {
            s.guide_x = sx / n;
            s.guide_y = sy / n;
        }
        if !s.is_air {
            let (gx, gy) = slide_land(s.guide_x, s.guide_y);
            s.guide_x = gx;
            s.guide_y = gy;
        }
        let order = deploys
            .and_then(|d| d.get(si))
            .map(|d| d.order)
            .unwrap_or(default_order);
        s.order = order;
        s.engage_x = contact;
        s.engage_y = order_engage_y(order, dir, s.guide_y);
        s.home_x = baseline;
        s.face_sign = dir;
    }
    for u in units.iter_mut().filter(|u| u.faction == fac) {
        if let Some(s) = squads.iter().find(|s| s.id == u.squad) {
            u.slot_dx = u.x - s.guide_x;
            u.slot_dy = u.y - s.guide_y;
        }
    }
}

fn enemy_is_routing(squads: &[SquadState], fac: FactionId) -> bool {
    squads.iter().any(|s| s.faction != fac && s.routing)
}

fn enemy_in_fight_centroid(units: &[Unit], fac: FactionId) -> Option<(f32, f32)> {
    let mut sx = 0.0;
    let mut sy = 0.0;
    let mut n = 0.0;
    for u in units.iter().filter(|u| in_fight(u) && u.faction != fac) {
        sx += u.x;
        sy += u.y;
        n += 1.0;
    }
    if n > 0.0 {
        Some((sx / n, sy / n))
    } else {
        None
    }
}

fn march_guides(squads: &mut [SquadState], units: &[Unit]) {
    for i in 0..squads.len() {
        if squads[i].routing {
            continue;
        }
        refresh_engage_x(&mut squads[i], units);
        let step = if squads[i].is_air {
            GUIDE_SPEED * 1.35
        } else {
            GUIDE_SPEED
        };
        let fac = squads[i].faction;
        if squads[i].is_air && !enemy_is_routing(squads, fac) {
            let dest = if squads[i].air_outbound {
                squads[i].engage_x + squads[i].face_sign * OVERFLY
            } else {
                squads[i].home_x + squads[i].face_sign * 4.0
            };
            let dx = dest - squads[i].guide_x;
            let chase = step * 1.6;
            if dx.abs() <= chase {
                squads[i].guide_x = dest;
                squads[i].air_outbound = !squads[i].air_outbound;
            } else {
                squads[i].guide_x += dx.signum() * chase;
            }
            let dy = squads[i].engage_y - squads[i].guide_y;
            if dy.abs() <= step {
                squads[i].guide_y = squads[i].engage_y;
            } else {
                squads[i].guide_y += dy.signum() * step;
            }
            continue;
        }
        if enemy_is_routing(squads, fac) {
            if let Some((cx, cy)) = enemy_in_fight_centroid(units, fac) {
                let leash_lo = ESCAPE_RIM + PURSUE_LEASH;
                let leash_hi = BATTLE_WIDTH - ESCAPE_RIM - PURSUE_LEASH;
                let tx = cx.clamp(leash_lo, leash_hi);
                let (gx, gy) = step_toward(squads[i].guide_x, squads[i].guide_y, tx, cy, step * 1.45);
                squads[i].guide_x = gx;
                squads[i].guide_y = gy.clamp(Y_PAD, BATTLE_HEIGHT - Y_PAD);
            }
            continue;
        }
        let (tx, ty) = guide_dest(&squads[i]);
        let (gx, gy) = step_toward(squads[i].guide_x, squads[i].guide_y, tx, ty, step);
        if squads[i].is_air {
            squads[i].guide_x = gx;
            squads[i].guide_y = gy.clamp(Y_PAD, BATTLE_HEIGHT - Y_PAD);
        } else {
            let (gx, gy) = slide_land(gx, gy);
            squads[i].guide_x = gx;
            squads[i].guide_y = gy;
        }
    }
}

fn refresh_engage_x(s: &mut SquadState, units: &[Unit]) {
    if s.order == BattleOrder::Rear {
        return;
    }
    let mut best_x = None;
    let mut best_y = None;
    let mut best_d = f32::MAX;
    for u in units.iter().filter(|u| in_fight(u) && u.faction != s.faction) {
        if s.is_air && u.kind.domain() != UnitDomain::Land {
            continue;
        }
        // Prefer the assigned lane (front / left / right), then close on that enemy.
        let d = (u.x - s.guide_x).hypot(u.y - s.guide_y) + (u.y - s.engage_y).abs() * 0.7;
        if d < best_d {
            best_d = d;
            best_x = Some(u.x);
            best_y = Some(u.y);
        }
    }
    let dest = if let Some(ex) = best_x {
        if s.is_air {
            ex
        } else {
            ex - s.face_sign * 8.0
        }
    } else {
        BATTLE_WIDTH * 0.5 + s.face_sign * 2.0
    };
    let lo = ESCAPE_RIM + PURSUE_LEASH;
    let hi = BATTLE_WIDTH - ESCAPE_RIM - PURSUE_LEASH;
    s.engage_x = dest.clamp(lo, hi);
    if s.is_air {
        if let Some(ey) = best_y {
            s.engage_y = ey.clamp(Y_PAD, BATTLE_HEIGHT - Y_PAD);
        }
    }
}

fn octant(dx: f32, dy: f32) -> u8 {
    if dx.abs() < 1e-4 && dy.abs() < 1e-4 {
        return 0;
    }
    let a = dy.atan2(dx);
    let o = (a / (std::f32::consts::PI / 4.0)).round() as i32;
    o.rem_euclid(8) as u8
}

fn nearest_enemy(
    self_i: usize,
    ux: f32,
    uy: f32,
    uz: f32,
    fac: FactionId,
    radius: f32,
    units: &[Unit],
    grid: &SpatialGrid,
) -> (Option<usize>, f32) {
    let (cx, cy) = SpatialGrid::cell(ux, uy);
    let max_rings = (radius / GRID_CELL).ceil() as i32;
    let r2 = radius * radius;
    let mut best = None;
    let mut best_d2 = f32::MAX;
    for ring in 0..=max_rings {
        let gx0 = cx - ring;
        let gx1 = cx + ring;
        let gy0 = cy - ring;
        let gy1 = cy + ring;
        for gy in gy0..=gy1 {
            for gx in gx0..=gx1 {
                if ring > 0 && gx > gx0 && gx < gx1 && gy > gy0 && gy < gy1 {
                    continue;
                }
                for &j in grid.bucket(gx, gy) {
                    if j == self_i {
                        continue;
                    }
                    let e = &units[j];
                    if !in_fight(e) || e.faction == fac {
                        continue;
                    }
                    let dx = e.x - ux;
                    let dy = e.y - uy;
                    let dz = e.z - uz;
                    let d2 = dx * dx + dy * dy + dz * dz;
                    if d2 <= r2 && d2 < best_d2 {
                        best_d2 = d2;
                        best = Some(j);
                    }
                }
            }
        }
        if ring >= 1 && best_d2 < (ring as f32 * GRID_CELL) * (ring as f32 * GRID_CELL) {
            break;
        }
    }
    (best, best_d2.sqrt())
}

fn airborne(u: &Unit) -> bool {
    u.kind.domain() == UnitDomain::Land && (u.z > 0.12 || u.vz > 0.08)
}

fn step_ballistic(u: &mut Unit) {
    u.x = (u.x + u.vx * DT).clamp(2.0, BATTLE_WIDTH - 2.0);
    u.y = (u.y + u.vy * DT).clamp(2.0, BATTLE_HEIGHT - 2.0);
    u.z += u.vz * DT;
    u.vz -= GRAVITY * DT;
    u.vx *= 0.94;
    u.vy *= 0.94;
    if u.z > 0.0 {
        return;
    }
    let impact = (-u.vz).max(0.0);
    u.z = 0.0;
    u.vz = 0.0;
    u.vx = 0.0;
    u.vy = 0.0;
    if u.alive && impact > 0.4 {
        u.hp -= impact * FALL_DMG;
        if u.hp <= 0.0 {
            u.alive = false;
            u.state = ST_DEAD;
        } else {
            u.state = ST_HIT;
        }
    }
    if u.kind.domain() == UnitDomain::Land {
        let (x, y) = slide_land(u.x, u.y);
        u.x = x;
        u.y = y;
    }
}

fn nearest_land_enemy_xy(
    self_i: usize,
    ux: f32,
    uy: f32,
    fac: FactionId,
    radius: f32,
    units: &[Unit],
    grid: &SpatialGrid,
) -> (Option<usize>, f32) {
    let (cx, cy) = SpatialGrid::cell(ux, uy);
    let max_rings = (radius / GRID_CELL).ceil() as i32;
    let r2 = radius * radius;
    let mut best = None;
    let mut best_d2 = f32::MAX;
    for ring in 0..=max_rings {
        let gx0 = cx - ring;
        let gx1 = cx + ring;
        let gy0 = cy - ring;
        let gy1 = cy + ring;
        for gy in gy0..=gy1 {
            for gx in gx0..=gx1 {
                if ring > 0 && gx > gx0 && gx < gx1 && gy > gy0 && gy < gy1 {
                    continue;
                }
                for &j in grid.bucket(gx, gy) {
                    if j == self_i {
                        continue;
                    }
                    let e = &units[j];
                    if !in_fight(e) || e.faction == fac || e.kind.domain() != UnitDomain::Land {
                        continue;
                    }
                    if airborne(e) {
                        continue;
                    }
                    let dx = e.x - ux;
                    let dy = e.y - uy;
                    let d2 = dx * dx + dy * dy;
                    if d2 <= r2 && d2 < best_d2 {
                        best_d2 = d2;
                        best = Some(j);
                    }
                }
            }
        }
        if ring >= 1 && best_d2 < (ring as f32 * GRID_CELL) * (ring as f32 * GRID_CELL) {
            break;
        }
    }
    (best, best_d2.sqrt())
}

fn apply_blast(units: &mut [Unit], bx: f32, by: f32, radius: f32, dmg: f32, rng: &mut Rng) {
    let r2 = radius * radius;
    for u in units.iter_mut() {
        if u.kind.domain() != UnitDomain::Land {
            continue;
        }
        if !u.alive && u.z <= 0.12 {
            continue;
        }
        let dx = u.x - bx;
        let dy = u.y - by;
        let d2 = dx * dx + dy * dy;
        if d2 > r2 {
            continue;
        }
        let dist = d2.sqrt();
        let falloff = 1.0 - 0.65 * (dist / radius).clamp(0.0, 1.0);
        if u.alive {
            u.hp -= dmg * falloff;
            if u.hp <= 0.0 {
                u.alive = false;
                u.state = ST_DEAD;
            } else {
                u.state = ST_HIT;
            }
        }
        let (nx, ny) = if dist < 1e-3 {
            let a = rng.next_f32() * std::f32::consts::TAU;
            (a.cos(), a.sin())
        } else {
            (dx / dist, dy / dist)
        };
        u.vx += nx * (5.5 * falloff);
        u.vy += ny * (5.5 * falloff);
        u.vz += 2.4 + 2.0 * falloff;
    }
}

fn update_squad_morale(
    squads: &mut [SquadState],
    units: &[Unit],
    rout_frac: &std::collections::HashMap<FactionId, f32>,
) {
    let mut alive = vec![0u32; squads.len()];
    for u in units {
        if !in_fight(u) {
            continue;
        }
        let i = u.squad as usize;
        if i < alive.len() {
            alive[i] += 1;
        }
    }
    for (i, s) in squads.iter_mut().enumerate() {
        if s.routing {
            continue;
        }
        let lost = s.initial.saturating_sub(alive[i]);
        let thresh = rout_frac.get(&s.faction).copied().unwrap_or(ROUT_CASUALTY_FRAC);
        if s.initial > 0 && (lost as f32 / s.initial as f32) >= thresh {
            s.routing = true;
        }
    }
}

fn record_frame(frames: &mut Vec<Frame>, tick: u32, units: &[Unit]) {
    frames.push(Frame {
        tick,
        units: units
            .iter()
            .map(|u| UnitSnapshot {
                faction: u.faction,
                kind: u.kind,
                x: u.x,
                y: u.y,
                z: u.z,
                alive: u.alive,
                facing: u.facing,
                // Fled bodies stay `alive` (survivors); the viewer fades ST_FLED, not corpses.
                state: if u.alive { u.state } else { ST_DEAD },
                aim_x: u.aim_x,
                aim_y: u.aim_y,
            })
            .collect(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Squad, UnitDomain, UnitKind};
    use crate::scenario;

    fn seed_battle(count_a: u32, count_b: u32, seed: u64) -> (World, Ledger) {
        let (mut w, mut l) = scenario::duel_line(3, seed);
        let prov = 1u32;
        scenario::recruit_army(
            &mut w,
            &mut l,
            0,
            prov,
            vec![Squad { kind: UnitKind::Soldier, count: count_a }],
        );
        scenario::recruit_army(
            &mut w,
            &mut l,
            1,
            prov,
            vec![Squad { kind: UnitKind::Soldier, count: count_b }],
        );
        (w, l)
    }

    fn ms(v: f32) -> f32 {
        v * MAP_SCALE
    }

    #[test]
    fn battle_is_deterministic() {
        let (mut w1, mut l1) = seed_battle(30, 30, 999);
        let (mut w2, mut l2) = seed_battle(30, 30, 999);
        let (s1, s2) = (w1.seed, w2.seed);
        let r1 = resolve_battle_in_province(&mut w1, &mut l1, 1, 0, 1, s1);
        let r2 = resolve_battle_in_province(&mut w2, &mut l2, 1, 0, 1, s2);
        assert_eq!(r1.digest(), r2.digest(), "same seed → identical battle");
        assert_eq!(l1.digest(), l2.digest());
    }

    #[test]
    fn battle_report_reconciles() {
        let (mut w, mut l) = seed_battle(40, 25, 12);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        assert!(r.reconciles(), "initial == casualties + survivors per side");
        // Ledger casualties match the report.
        for (f, c) in &r.casualties {
            assert_eq!(l.balance(Account::Casualties(*f)) as u32, *c);
        }
        l.assert_balanced();
    }

    #[test]
    fn bigger_army_tends_to_win() {
        let mut big_wins = 0;
        for s in 0..8u64 {
            let (mut w, mut l) = seed_battle(60, 25, 100 + s);
            let seed = w.seed;
            let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
            if r.winner == Some(0) {
                big_wins += 1;
            }
        }
        assert!(big_wins >= 6, "the much larger army should usually win ({big_wins}/8)");
    }

    #[test]
    fn scales_to_1000_units() {
        // Proves the resolver handles the target scale (deterministically, one-shot).
        let (mut w, mut l) = seed_battle(500, 500, 4242);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        assert_eq!(r.initial.iter().map(|(_, n)| *n).sum::<u32>(), 1000);
        assert!(r.reconciles());
    }

    #[test]
    fn few_thousand_bodies_resolve_in_seconds() {
        let t = std::time::Instant::now();
        let (mut w, mut l) = seed_battle(1850, 1855, 11);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let dt = t.elapsed();
        assert_eq!(r.initial.iter().map(|(_, n)| *n).sum::<u32>(), 3705);
        assert!(r.reconciles());
        assert!(
            r.frames.iter().any(|f| f.units.iter().any(|u| u.state == ST_FIRE || u.state == ST_AIM)),
            "3705 bodies should still fight"
        );
        assert!(
            dt < std::time::Duration::from_secs(20),
            "3705-body resolve took {dt:?} (enemy search must stay local, not whole-map)"
        );
    }

    #[test]
    fn fight_holds_a_front_instead_of_commuting() {
        let (mut w, mut l) = seed_battle(48, 48, 77);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        assert!(r.frames.len() > 8);
        let fire_i = r
            .frames
            .iter()
            .position(|f| f.units.iter().any(|u| u.state == ST_FIRE || u.state == ST_AIM))
            .expect("a fight should produce aim/fire states");
        let contact = &r.frames[fire_i];
        let med = |fac: FactionId| -> f32 {
            let mut xs: Vec<f32> = contact
                .units
                .iter()
                .filter(|u| u.alive && u.faction == fac && u.kind == UnitKind::Soldier)
                .map(|u| u.x)
                .collect();
            xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
            xs[xs.len() / 2]
        };
        let ma = med(0);
        let md = med(1);
        assert!(
            md > ma && md - ma < 90.0 && ma > ms(30.0) && md < BATTLE_WIDTH - ms(30.0),
            "first shots when the lines have closed (F0={ma:.1} F1={md:.1} frame={fire_i})"
        );
        let last = r.frames.last().unwrap();
        let loser = match r.winner {
            Some(0) => 1,
            Some(1) => 0,
            _ => return,
        };
        let routed = last
            .units
            .iter()
            .filter(|u| {
                u.faction == loser && (u.state == ST_ROUT || u.state == ST_FLED || !u.alive)
            })
            .count();
        assert!(routed > 0, "the losing side should rout, flee, or die, not commute");
        // Contact still happened on a front; pursuit after the break is covered separately.
    }

    fn min_xy_dist(frame: &Frame, kind: UnitKind, fac: FactionId) -> f32 {
        let pts: Vec<(f32, f32)> = frame
            .units
            .iter()
            .filter(|u| u.alive && u.kind == kind && u.faction == fac)
            .map(|u| (u.x, u.y))
            .collect();
        let mut best = f32::MAX;
        for i in 0..pts.len() {
            for j in (i + 1)..pts.len() {
                let dx = pts[i].0 - pts[j].0;
                let dy = pts[i].1 - pts[j].1;
                let d = (dx * dx + dy * dy).sqrt();
                if d < best {
                    best = d;
                }
            }
        }
        best
    }

    #[test]
    fn regiments_are_distinct_and_bodies_do_not_stack() {
        let (mut w, mut l) = seed_battle(200, 200, 3);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let first = &r.frames[0];
        let soldiers = first
            .units
            .iter()
            .filter(|u| u.faction == 0 && u.kind == UnitKind::Soldier)
            .count();
        assert_eq!(soldiers, 200);
        let mut ys: Vec<f32> = first
            .units
            .iter()
            .filter(|u| u.alive && u.faction == 0 && u.kind == UnitKind::Soldier)
            .map(|u| u.y)
            .collect();
        ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let gaps = ys.windows(2).map(|w| w[1] - w[0]).filter(|g| *g > 5.0).count();
        assert!(
            gaps >= 1,
            "two infantry units of 100 should leave a gap along the front"
        );
        let d0 = min_xy_dist(first, UnitKind::Soldier, 0);
        assert!(
            d0 > 1.2,
            "soldiers must not occupy the same spot at deploy (min={d0:.3})"
        );
        let mid = &r.frames[r.frames.len() / 3];
        let dm = min_xy_dist(mid, UnitKind::Soldier, 0);
        assert!(
            dm > 0.32,
            "soldiers must stay separated during the fight (min={dm:.3})"
        );
    }

    #[test]
    fn routers_phase_out_at_the_map_edge() {
        let (mut w, mut l) = seed_battle(80, 20, 5);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        assert!(r.reconciles());
        assert!(
            r.ticks < MAX_TICKS,
            "escaping the rim must end the fight before the tick cap (ticks={})",
            r.ticks
        );
        let last = r.frames.last().unwrap();
        let rim_routers = last
            .units
            .iter()
            .filter(|u| {
                u.alive
                    && u.state == ST_ROUT
                    && (u.x <= ESCAPE_RIM + 0.5 || u.x >= BATTLE_WIDTH - ESCAPE_RIM - 0.5)
            })
            .count();
        assert_eq!(
            rim_routers, 0,
            "a router that hits the map edge must flee, not idle on the rim"
        );
        let Some(winner) = r.winner else {
            return;
        };
        let loser = if winner == 0 { 1 } else { 0 };
        let leftover = last
            .units
            .iter()
            .filter(|u| u.alive && u.faction == loser && u.state != ST_FLED)
            .count();
        assert_eq!(
            leftover, 0,
            "the broken side should be dead or fled, not still fighting"
        );
        for u in last.units.iter().filter(|u| u.state == ST_FLED) {
            assert!(u.alive, "escaped routers are survivors, not corpses");
        }
    }

    #[test]
    fn winners_chase_the_rout() {
        let (mut w, mut l) = seed_battle(80, 20, 5);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let rout_i = r
            .frames
            .iter()
            .position(|f| f.units.iter().any(|u| u.faction == 1 && u.state == ST_ROUT));
        let Some(rout_i) = rout_i else {
            return;
        };
        let med = |frame: &Frame, fac: FactionId| -> Option<f32> {
            let mut xs: Vec<f32> = frame
                .units
                .iter()
                .filter(|u| {
                    u.alive
                        && u.faction == fac
                        && u.state != ST_FLED
                        && u.kind == UnitKind::Soldier
                })
                .map(|u| u.x)
                .collect();
            if xs.is_empty() {
                return None;
            }
            xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
            Some(xs[xs.len() / 2])
        };
        let later_i = r
            .frames
            .iter()
            .enumerate()
            .skip(rout_i + 1)
            .take(12)
            .filter(|(_, f)| f.units.iter().any(|u| u.faction == 1 && u.state == ST_ROUT))
            .map(|(i, _)| i)
            .last()
            .unwrap_or_else(|| (rout_i + 4).min(r.frames.len() - 1));
        let start = med(&r.frames[rout_i], 0).expect("chasers at rout start");
        let later = med(&r.frames[later_i], 0).expect("chasers during pursuit");
        assert!(
            later > start + 4.0,
            "standing army should chase routers homeward (start={start:.1} later={later:.1} frames {rout_i}->{later_i})"
        );
        let chase_frame = &r.frames[later_i];
        let chasing = chase_frame
            .units
            .iter()
            .filter(|u| {
                u.faction == 0
                    && u.alive
                    && (u.state == ST_MARCH || u.state == ST_AIM || u.state == ST_FIRE)
            })
            .count();
        let idle = chase_frame
            .units
            .iter()
            .filter(|u| u.faction == 0 && u.alive && u.state == ST_IDLE)
            .count();
        assert!(
            chasing > idle,
            "pursuers should be marching/shooting, not waiting (chase={chasing} idle={idle})"
        );
    }

    #[test]
    fn terrain_slows_land_not_air() {
        let river = terrain_speed(RIVER_X, ms(60.0), 30.0, UnitDomain::Land);
        let open = terrain_speed(ms(20.0), ms(60.0), 30.0, UnitDomain::Land);
        let hill = terrain_speed(HILL_CX, HILL_CY, 30.0, UnitDomain::Land);
        let high = terrain_speed(ms(20.0), ms(60.0), 90.0, UnitDomain::Land);
        let low = terrain_speed(ms(20.0), ms(60.0), 10.0, UnitDomain::Land);
        assert!(river < open, "river crossing is slower ({river} vs {open})");
        assert!(hill < open, "the hill is slower than open ground ({hill} vs {open})");
        assert!(high < low, "higher province elevation slows land ({high} vs {low})");
        assert_eq!(terrain_speed(RIVER_X, ms(60.0), 90.0, UnitDomain::Air), 1.0);
    }

    #[test]
    fn hit_and_aim_tracks_are_baked() {
        let (mut w, mut l) = seed_battle(48, 48, 21);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let mut saw_hit = false;
        let mut aim_on_fire = 0u32;
        let mut fire_n = 0u32;
        for f in &r.frames {
            for u in &f.units {
                if u.state == ST_HIT {
                    saw_hit = true;
                }
                if u.state == ST_FIRE {
                    fire_n += 1;
                    if u.aim_x.abs() + u.aim_y.abs() > 1.0 {
                        aim_on_fire += 1;
                    }
                }
            }
        }
        assert!(saw_hit, "non-lethal hits should bake ST_HIT");
        assert!(fire_n > 0, "a fight should fire");
        assert!(
            aim_on_fire * 2 >= fire_n,
            "most fire ticks must carry an aim point (aim={aim_on_fire} fire={fire_n})"
        );
    }

    #[test]
    fn prophet_swings_the_fight() {
        let (mut w0, mut l0) = seed_battle(36, 36, 44);
        let (mut w1, mut l1) = seed_battle(36, 36, 44);
        scenario::add_agent(&mut w1, 0, 1, crate::model::AgentKind::Prophet, 3);
        let s0 = w0.seed;
        let s1 = w1.seed;
        let r0 = resolve_battle_in_province(&mut w0, &mut l0, 1, 0, 1, s0);
        let r1 = resolve_battle_in_province(&mut w1, &mut l1, 1, 0, 1, s1);
        let c0 = r0.casualties_of(1);
        let c1 = r1.casualties_of(1);
        assert!(
            c1 > c0 || (c1 == c0 && r1.ticks <= r0.ticks && r1.winner == Some(0)),
            "a prophet should make the host more lethal (without cas={c0} with={c1} ticks {} vs {})",
            r0.ticks,
            r1.ticks
        );
        assert_ne!(r0.digest(), r1.digest(), "agent presence must change the bake");
    }

    #[test]
    fn victor_takes_the_province() {
        let (mut w, mut l) = seed_battle(80, 20, 5);
        let seed = w.seed;
        assert_eq!(w.provinces[1].owner(&w.cfg), None);
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let Some(winner) = r.winner else {
            return;
        };
        assert_eq!(r.owner_before, None);
        assert_eq!(r.owner_after, Some(winner));
        assert_eq!(w.provinces[1].owner(&w.cfg), Some(winner));
        assert!(
            l.journal().iter().any(|t| t.kind == "battle_claim" || t.kind == "consecrate"),
            "the nested result must post to the world ledger"
        );
    }

    #[test]
    fn bombers_pass_above_the_slab() {
        let (mut w, mut l) = scenario::duel_line(3, 9);
        let seed = w.seed;
        scenario::recruit_army(
            &mut w,
            &mut l,
            0,
            1,
            vec![Squad { kind: UnitKind::Bomber, count: 5 }],
        );
        scenario::recruit_army(
            &mut w,
            &mut l,
            1,
            1,
            vec![Squad { kind: UnitKind::Soldier, count: 40 }],
        );
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let mut min_z = f32::MAX;
        let mut max_x = f32::MIN;
        let mut min_x = f32::MAX;
        for f in &r.frames {
            for u in f.units.iter().filter(|u| u.kind == UnitKind::Bomber && u.alive) {
                min_z = min_z.min(u.z);
                max_x = max_x.max(u.x);
                min_x = min_x.min(u.x);
            }
        }
        assert!(min_z > 8.0, "bombers must stay off the infantry plane (min_z={min_z})");
        assert!(
            max_x - min_x > 40.0,
            "bombers should pass along the field, not taxi in place (span={})",
            max_x - min_x
        );
    }

    fn median_y(frame: &Frame, fac: FactionId) -> f32 {
        let mut ys: Vec<f32> = frame
            .units
            .iter()
            .filter(|u| u.alive && u.faction == fac && u.kind == UnitKind::Soldier)
            .map(|u| u.y)
            .collect();
        ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
        ys[ys.len() / 2]
    }

    #[test]
    fn land_units_stay_out_of_the_hill() {
        let (mut w, mut l) = seed_battle(200, 200, 3);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        for f in &r.frames {
            for u in f.units.iter().filter(|u| u.alive && u.kind == UnitKind::Soldier) {
                if u.z > 0.5 {
                    continue;
                }
                assert!(
                    !land_blocked(u.x, u.y),
                    "living land at ({:.1},{:.1}) is inside the hill/ruin",
                    u.x,
                    u.y
                );
            }
        }
    }

    #[test]
    fn deployed_regiments_keep_their_origins() {
        let (mut w, mut l) = seed_battle(300, 100, 11);
        let seed = w.seed;
        let plan = BattlePlan {
            order_a: BattleOrder::Front,
            order_d: BattleOrder::Front,
            deploys: vec![
                SquadDeploy {
                    x: ms(22.0),
                    y: ms(24.0),
                    facing: 0.0,
                    formation: FormationKind::Line,
                    order: BattleOrder::Front,
                },
                SquadDeploy {
                    x: ms(22.0),
                    y: ms(58.0),
                    facing: 0.0,
                    formation: FormationKind::Line,
                    order: BattleOrder::Front,
                },
                SquadDeploy {
                    x: ms(22.0),
                    y: ms(96.0),
                    facing: 0.0,
                    formation: FormationKind::Line,
                    order: BattleOrder::Front,
                },
                SquadDeploy {
                    x: ms(168.0),
                    y: ms(58.0),
                    facing: std::f32::consts::PI,
                    formation: FormationKind::Line,
                    order: BattleOrder::Front,
                },
            ],
        };
        let r = resolve_battle_with_plan(&mut w, &mut l, 1, 0, 1, seed, Some(&plan));
        let first = &r.frames[0];
        let band = |lo: f32, hi: f32| {
            first
                .units
                .iter()
                .filter(|u| u.faction == 0 && u.kind == UnitKind::Soldier && u.y >= lo && u.y < hi)
                .count()
        };
        assert!(
            band(ms(4.0), ms(44.0)) >= 70,
            "first Line regiment should sit near y=24 (got {})",
            band(ms(4.0), ms(42.0))
        );
        assert!(
            band(ms(42.0), ms(78.0)) >= 80,
            "second Line regiment should sit near y=58 (got {})",
            band(ms(42.0), ms(78.0))
        );
        assert!(
            band(ms(78.0), ms(118.0)) >= 80,
            "third Line regiment should sit near y=96 (got {})",
            band(ms(78.0), ms(118.0))
        );
        let ys: Vec<f32> = first
            .units
            .iter()
            .filter(|u| u.faction == 0 && u.kind == UnitKind::Soldier)
            .map(|u| u.y)
            .collect();
        let spread = ys.iter().cloned().fold(f32::MIN, f32::max) - ys.iter().cloned().fold(f32::MAX, f32::min);
        assert!(spread > ms(50.0), "3-regiment Line should have spread along the front (spread={spread:.1})");
    }

    #[test]
    fn attack_left_shifts_the_front() {
        let (mut wf, mut lf) = seed_battle(80, 80, 19);
        let (mut wl, mut ll) = seed_battle(80, 80, 19);
        let seed = wf.seed;
        let front = BattlePlan {
            order_a: BattleOrder::Front,
            order_d: BattleOrder::Front,
            deploys: vec![],
        };
        let left = BattlePlan {
            order_a: BattleOrder::Left,
            order_d: BattleOrder::Front,
            deploys: vec![],
        };
        // Empty deploys → default rectangles; orders still apply.
        let rf = resolve_battle_with_plan(&mut wf, &mut lf, 1, 0, 1, seed, Some(&front));
        let rl = resolve_battle_with_plan(&mut wl, &mut ll, 1, 0, 1, seed, Some(&left));
        let fi = 8.min(rf.frames.len().saturating_sub(1));
        let li = 8.min(rl.frames.len().saturating_sub(1));
        let yf = median_y(&rf.frames[fi], 0);
        let yl = median_y(&rl.frames[li], 0);
        assert!(
            yl + 1.5 < yf,
            "Attack left should pull our right (low y) (front={yf:.1} left={yl:.1})"
        );
    }

    fn median_x(frame: &Frame, fac: FactionId) -> f32 {
        let mut xs: Vec<f32> = frame
            .units
            .iter()
            .filter(|u| u.alive && u.faction == fac && u.kind == UnitKind::Soldier)
            .map(|u| u.x)
            .collect();
        xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        xs[xs.len() / 2]
    }

    fn median_y_slice(frame: &Frame, start: usize, count: usize) -> f32 {
        let mut ys: Vec<f32> = frame.units[start..start + count]
            .iter()
            .filter(|u| u.alive && u.kind == UnitKind::Soldier)
            .map(|u| u.y)
            .collect();
        ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
        ys[ys.len() / 2]
    }

    #[test]
    fn per_regiment_orders_split_the_attacker() {
        let (mut w, mut l) = seed_battle(200, 100, 41);
        let seed = w.seed;
        let plan = BattlePlan {
            order_a: BattleOrder::Front,
            order_d: BattleOrder::Front,
            deploys: vec![
                SquadDeploy {
                    x: ms(28.0),
                    y: ms(28.0),
                    facing: 0.0,
                    formation: FormationKind::Line,
                    order: BattleOrder::Right,
                },
                SquadDeploy {
                    x: ms(28.0),
                    y: ms(92.0),
                    facing: 0.0,
                    formation: FormationKind::Line,
                    order: BattleOrder::Left,
                },
                SquadDeploy {
                    x: ms(168.0),
                    y: ms(60.0),
                    facing: std::f32::consts::PI,
                    formation: FormationKind::Line,
                    order: BattleOrder::Front,
                },
            ],
        };
        let r = resolve_battle_with_plan(&mut w, &mut l, 1, 0, 1, seed, Some(&plan));
        let fi = 18.min(r.frames.len().saturating_sub(1));
        let y_right = median_y_slice(&r.frames[fi], 0, 100);
        let y_left = median_y_slice(&r.frames[fi], 100, 100);
        assert!(
            y_left + 8.0 < y_right,
            "Left-ordered regiment should sit on our right (low y) vs Right-ordered (high y) (left={y_left:.1} right={y_right:.1})"
        );
    }

    #[test]
    fn fronts_meet_in_a_scrum_not_a_midline_wall() {
        let (mut w, mut l) = seed_battle(200, 200, 7);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let mut min_gap = f32::MAX;
        let mut crossed = false;
        let mut fire_frames = 0u32;
        for (i, f) in r.frames.iter().enumerate() {
            if i < 4 {
                continue;
            }
            let living0 = f
                .units
                .iter()
                .filter(|u| u.alive && u.faction == 0 && u.kind == UnitKind::Soldier)
                .count();
            let living1 = f
                .units
                .iter()
                .filter(|u| u.alive && u.faction == 1 && u.kind == UnitKind::Soldier)
                .count();
            if living0 < 20 || living1 < 20 {
                continue;
            }
            let ax = median_x(f, 0);
            let dx = median_x(f, 1);
            min_gap = min_gap.min((dx - ax).abs());
            if f.units.iter().any(|u| {
                u.alive
                    && u.kind == UnitKind::Soldier
                    && u.faction == 0
                    && u.x > RIVER_X + 0.5
            }) || f.units.iter().any(|u| {
                u.alive
                    && u.kind == UnitKind::Soldier
                    && u.faction == 1
                    && u.x < RIVER_X - 0.5
            }) {
                crossed = true;
            }
            if f.units.iter().any(|u| u.state == ST_FIRE) {
                fire_frames += 1;
            }
        }
        assert!(
            min_gap < 32.0,
            "living fronts should close to a scrum (min gap={min_gap:.1})"
        );
        assert!(
            crossed,
            "someone should cross the river during the scrum, not park on their own half"
        );
        assert!(
            fire_frames >= 3,
            "bake should keep fire poses across recorded frames (fire_frames={fire_frames})"
        );
    }

    #[test]
    fn first_arrivals_press_to_the_enemy() {
        let (mut w, mut l) = seed_battle(80, 20, 5);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let mut max_push = 0.0f32;
        for f in &r.frames {
            let living1 = f
                .units
                .iter()
                .filter(|u| u.alive && u.faction == 1 && u.kind == UnitKind::Soldier && u.state != ST_FLED)
                .count();
            if living1 == 0 {
                continue;
            }
            for u in f.units.iter().filter(|u| {
                u.alive && u.faction == 0 && u.kind == UnitKind::Soldier && u.state != ST_FLED
            }) {
                max_push = max_push.max(u.x);
            }
        }
        assert!(
            max_push > RIVER_X + 30.0,
            "the first line should press onto the enemy half, not park at the river (max_x={max_push:.1})"
        );
    }

    #[test]
    fn infantry_keep_personal_space_at_deploy() {
        let (mut w, mut l) = seed_battle(100, 100, 3);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let f0 = r.frames.first().expect("baked frames");
        let need = UnitKind::Soldier.spacing() * 0.92;
        let mut min_d = f32::MAX;
        let soldiers: Vec<&UnitSnapshot> = f0
            .units
            .iter()
            .filter(|u| u.alive && u.kind == UnitKind::Soldier)
            .collect();
        for i in 0..soldiers.len() {
            for j in (i + 1)..soldiers.len() {
                if soldiers[i].faction != soldiers[j].faction {
                    continue;
                }
                let dx = soldiers[i].x - soldiers[j].x;
                let dy = soldiers[i].y - soldiers[j].y;
                min_d = min_d.min((dx * dx + dy * dy).sqrt());
            }
        }
        assert!(
            min_d >= need,
            "same-faction infantry packed at {min_d:.2} (need >= {need:.2})"
        );
    }

    fn seed_air_duel(bombers: u32, infantry: u32, seed: u64) -> (World, Ledger) {
        let (mut w, mut l) = scenario::duel_line(3, seed);
        scenario::recruit_army(
            &mut w,
            &mut l,
            0,
            1,
            vec![Squad { kind: UnitKind::Bomber, count: bombers }],
        );
        scenario::recruit_army(
            &mut w,
            &mut l,
            1,
            1,
            vec![Squad { kind: UnitKind::Soldier, count: infantry }],
        );
        (w, l)
    }

    #[test]
    fn fifty_soldiers_bring_down_a_bomber() {
        let (mut w, mut l) = seed_air_duel(1, 50, 21);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let bomber_dead = r.frames.last().map(|f| {
            f.units
                .iter()
                .filter(|u| u.kind == UnitKind::Bomber)
                .all(|u| !u.alive)
        }).unwrap_or(false);
        let inf_left = r
            .frames
            .last()
            .map(|f| {
                f.units
                    .iter()
                    .filter(|u| u.kind == UnitKind::Soldier && u.alive)
                    .count()
            })
            .unwrap_or(0);
        assert!(bomber_dead, "50 infantry should bring down one bomber");
        assert!(inf_left >= 18, "the 50 should not be wiped (left={inf_left})");
    }

    #[test]
    fn ten_soldiers_struggle_against_a_bomber() {
        let (mut w, mut l) = seed_air_duel(1, 10, 22);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let bomber_alive = r.frames.last().map(|f| {
            f.units
                .iter()
                .any(|u| u.kind == UnitKind::Bomber && u.alive)
        }).unwrap_or(false);
        let inf_left = r
            .frames
            .last()
            .map(|f| {
                f.units
                    .iter()
                    .filter(|u| u.kind == UnitKind::Soldier && u.alive)
                    .count()
            })
            .unwrap_or(0);
        assert!(
            bomber_alive || inf_left <= 3,
            "10 infantry should not confidently kill a bomber (alive={bomber_alive} left={inf_left})"
        );
    }

    #[test]
    fn bomb_blast_launches_infantry() {
        let (mut w, mut l) = seed_air_duel(5, 80, 23);
        let seed = w.seed;
        let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
        let launched = r.frames.iter().any(|f| {
            f.units
                .iter()
                .any(|u| u.kind == UnitKind::Soldier && u.z > 1.0)
        });
        let dropped = r.frames.iter().any(|f| {
            f.units
                .iter()
                .any(|u| u.kind == UnitKind::Bomber && u.state == ST_FIRE)
        });
        assert!(dropped, "bombers should pickle bombs (ST_FIRE) on a pass");
        assert!(launched, "a bomb should throw infantry off the slab");
    }
}
