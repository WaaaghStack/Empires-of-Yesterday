//! Battle resolver — squad formation *guides* + individual line-of-sight combat.
//!
//! Rust is the only combat authority. The squad brain paints a moving formation field
//! (facing, interval, engagement line, morale). Each body is attracted to its slot, then
//! breaks it to fight whoever is in local perception. One loop, many kind profiles
//! (land / air / later naval). Resolved once, baked for the HD-2D replay.

use crate::ledger::{Account, Ledger, Phase};
use crate::model::{FactionId, ProvinceId, UnitDomain, UnitKind, World};
use crate::rng::Rng;

pub const BATTLE_WIDTH: f32 = 200.0;
pub const BATTLE_HEIGHT: f32 = 120.0;
const DT: f32 = 1.0;
const MAX_TICKS: u32 = 1400;
const RECORD_STRIDE: u32 = 3;
const ROUT_CASUALTY_FRAC: f32 = 0.6;
const ATTACK_COOLDOWN: u32 = 3;
const GRID_CELL: f32 = 10.0;
const CONSECRATE: f32 = 8.0;
/// Gap between the two engagement lines (fronts halt here and shoot across it).
const ENGAGE_GAP: f32 = 22.0;
/// How fast the formation *guide* marches (individuals can peel off faster).
const GUIDE_SPEED: f32 = 1.15;
/// After a break, pursuers look across the field so they do not lose the routers.
const CHASE_RADIUS: f32 = 180.0;
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
/// Rim band: routers that hit this fade out of the sim instead of idling at the wall.
const ESCAPE_RIM: f32 = 3.0;

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
    home_x: f32,
    face_sign: f32,
    is_air: bool,
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
                    let sid = next_sid;
                    next_sid += 1;
                    let is_air = part.kind.domain() == UnitDomain::Air;
                    squads.push(SquadState {
                        id: sid,
                        initial: part.count,
                        routing: false,
                        faction: fac,
                        guide_x: 0.0,
                        guide_y: BATTLE_HEIGHT * 0.5,
                        engage_x: 0.0,
                        home_x: 0.0,
                        face_sign: 0.0,
                        is_air,
                    });
                    for _ in 0..part.count {
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
                        });
                    }
                }
            }
        }
        let baseline = if side_idx == 0 { 32.0 } else { BATTLE_WIDTH - 32.0 };
        let dir = if side_idx == 0 { 1.0 } else { -1.0 };
        let contact = if side_idx == 0 {
            BATTLE_WIDTH * 0.5 - ENGAGE_GAP * 0.5
        } else {
            BATTLE_WIDTH * 0.5 + ENGAGE_GAP * 0.5
        };
        layout_regiment_blocks(&mut units, &squads, fac, baseline, dir);
        bind_squad_guides(&mut squads, &mut units, fac, baseline, contact, dir);
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
    while tick < MAX_TICKS && both_sides_fighting(&units, attacker, defender) {
        tick += 1;
        update_squad_morale(&mut squads, &units);
        march_guides(&mut squads, &units);

        let cell_of = |x: f32, y: f32| -> (i32, i32) {
            ((x / GRID_CELL) as i32, (y / GRID_CELL) as i32)
        };
        let mut grid: std::collections::HashMap<(i32, i32), Vec<usize>> =
            std::collections::HashMap::new();
        for (idx, u) in units.iter().enumerate() {
            if in_fight(u) {
                grid.entry(cell_of(u.x, u.y)).or_default().push(idx);
            }
        }

        for i in 0..units.len() {
            if !units[i].alive {
                units[i].state = ST_DEAD;
                continue;
            }
            if units[i].state == ST_FLED {
                continue;
            }
            let (ux, uy, uz, kind, fac, squad_id) = {
                let u = &units[i];
                (u.x, u.y, u.z, u.kind, u.faction, u.squad)
            };
            let Some(sq_i) = squads.iter().position(|s| s.id == squad_id) else {
                continue;
            };
            let routing = squads[sq_i].routing;
            let slot_x = squads[sq_i].guide_x + units[i].slot_dx;
            let slot_y = squads[sq_i].guide_y + units[i].slot_dy;
            let face_sign = squads[sq_i].face_sign;
            let cohesion = kind.cohesion();
            let speed = kind.move_speed();
            let reach = kind.reach();
            let perception = kind.perception();
            let cruise_z = kind.cruise_z();
            let enemy_routing = enemy_is_routing(&squads, fac);

            if routing {
                units[i].x += -face_sign * speed * 1.35 * DT;
                units[i].x = units[i].x.clamp(1.0, BATTLE_WIDTH - 1.0);
                units[i].z = cruise_z;
                units[i].facing = octant(-face_sign, 0.0);
                if at_home_rim(units[i].x, face_sign) {
                    units[i].state = ST_FLED;
                } else {
                    units[i].state = ST_ROUT;
                }
                continue;
            }

            let search_r = if enemy_routing { CHASE_RADIUS } else { perception };
            let (target, dist) = nearest_enemy(
                i,
                ux,
                uy,
                uz,
                fac,
                search_r,
                &units,
                &grid,
                cell_of,
                grid_cols,
                grid_rows,
            );

            let (state, fdx, fdy) = if let Some(j) = target {
                let (ex, ey) = (units[j].x, units[j].y);
                let fdx = ex - ux;
                let fdy = ey - uy;
                let target_routing =
                    units[j].state == ST_ROUT || squad_is_routing(&squads, units[j].squad);
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
            units[i].facing = octant(fdx, fdy);
            units[i].state = state;
        }

        separate_bodies(&mut units, &cell_of, grid_cols, grid_rows);
        grid.clear();
        for (idx, u) in units.iter().enumerate() {
            if in_fight(u) {
                grid.entry(cell_of(u.x, u.y)).or_default().push(idx);
            }
        }

        let mut hits: Vec<(usize, usize, f32)> = Vec::new();
        for i in 0..units.len() {
            if !in_fight(&units[i]) || units[i].state == ST_ROUT {
                continue;
            }
            let sq_routing = squads
                .iter()
                .find(|s| s.id == units[i].squad)
                .map(|s| s.routing)
                .unwrap_or(false);
            if sq_routing || tick < units[i].next_attack {
                continue;
            }
            let (ux, uy, uz, kind, fac) = {
                let u = &units[i];
                (u.x, u.y, u.z, u.kind, u.faction)
            };
            let (target, dist) = nearest_enemy(
                i,
                ux,
                uy,
                uz,
                fac,
                kind.reach(),
                &units,
                &grid,
                cell_of,
                grid_cols,
                grid_rows,
            );
            let Some(j) = target else {
                continue;
            };
            if dist > kind.reach() {
                continue;
            }
            let jitter = 0.9 + 0.2 * rng.next_f32();
            hits.push((i, j, kind.base_attack() * jitter));
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
            }
            let (ux, uy) = (units[i].x, units[i].y);
            units[i].next_attack = tick + ATTACK_COOLDOWN;
            units[i].state = ST_FIRE;
            units[i].facing = octant(tx - ux, ty - uy);
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

    // Victor consecrates the province (a balanced dominion injection).
    if let Some(w) = winner {
        world.provinces[province as usize].dom[w as usize] += CONSECRATE;
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
    }
    ledger.assert_balanced();

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
    }
}

fn in_fight(u: &Unit) -> bool {
    u.alive && u.state != ST_FLED
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
    place_blocks(units, &air, baseline - dir * 10.0, dir, true);
}

fn place_blocks(units: &mut [Unit], sids: &[u32], baseline: f32, dir: f32, air: bool) {
    if sids.is_empty() {
        return;
    }
    let n = sids.len();
    let along_y = n.min(6).max(1);
    let y_pad = 8.0;
    let usable = (BATTLE_HEIGHT - 2.0 * y_pad).max(8.0);
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
        let cy = y_pad + usable * (row as f32 + 0.5) / along_y as f32;
        let block_h = (files.saturating_sub(1) as f32) * sp;
        let x0 = baseline - dir * col as f32 * (ranks as f32 * sp + 7.0);
        let face = if dir > 0.0 { 0 } else { 4 };
        for (m, &ui) in members.iter().enumerate() {
            let file = m % files;
            let rank = m / files;
            units[ui].x = x0 - dir * rank as f32 * sp;
            units[ui].y = (cy - block_h * 0.5 + file as f32 * sp).clamp(4.0, BATTLE_HEIGHT - 4.0);
            units[ui].z = kind.cruise_z();
            units[ui].facing = face;
        }
    }
}

fn separate_bodies(
    units: &mut [Unit],
    cell_of: &impl Fn(f32, f32) -> (i32, i32),
    grid_cols: i32,
    grid_rows: i32,
) {
    let n = units.len();
    for _ in 0..2 {
        let mut grid: std::collections::HashMap<(i32, i32), Vec<usize>> =
            std::collections::HashMap::new();
        for (idx, u) in units.iter().enumerate() {
            if in_fight(u) {
                grid.entry(cell_of(u.x, u.y)).or_default().push(idx);
            }
        }
        let mut px = vec![0.0f32; n];
        let mut py = vec![0.0f32; n];
        for i in 0..n {
            if !in_fight(&units[i]) {
                continue;
            }
            let (ux, uy, uz, di, ri) = {
                let u = &units[i];
                (u.x, u.y, u.z, u.kind.domain(), u.kind.spacing())
            };
            let (cx, cy) = cell_of(ux, uy);
            for gy in (cy - 1)..=(cy + 1) {
                for gx in (cx - 1)..=(cx + 1) {
                    if gx < -1 || gy < -1 || gx > grid_cols || gy > grid_rows {
                        continue;
                    }
                    let Some(bucket) = grid.get(&(gx, gy)) else {
                        continue;
                    };
                    for &j in bucket {
                        if j <= i || !in_fight(&units[j]) {
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
) {
    for s in squads.iter_mut().filter(|s| s.faction == fac) {
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
        s.engage_x = contact;
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

fn squad_is_routing(squads: &[SquadState], id: u32) -> bool {
    squads.iter().any(|s| s.id == id && s.routing)
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
        let step = if squads[i].is_air {
            GUIDE_SPEED * 1.35
        } else {
            GUIDE_SPEED
        };
        let fac = squads[i].faction;
        if enemy_is_routing(squads, fac) {
            if let Some((cx, cy)) = enemy_in_fight_centroid(units, fac) {
                let leash_lo = ESCAPE_RIM + PURSUE_LEASH;
                let leash_hi = BATTLE_WIDTH - ESCAPE_RIM - PURSUE_LEASH;
                let tx = cx.clamp(leash_lo, leash_hi);
                let dx = tx - squads[i].guide_x;
                let chase = step * 1.45;
                if dx.abs() <= chase {
                    squads[i].guide_x = tx;
                } else {
                    squads[i].guide_x += dx.signum() * chase;
                }
                let dy = cy - squads[i].guide_y;
                if dy.abs() <= chase {
                    squads[i].guide_y = cy;
                } else {
                    squads[i].guide_y += dy.signum() * chase;
                }
                squads[i].guide_y = squads[i].guide_y.clamp(8.0, BATTLE_HEIGHT - 8.0);
            }
            continue;
        }
        let dx = squads[i].engage_x - squads[i].guide_x;
        if dx.abs() <= step {
            squads[i].guide_x = squads[i].engage_x;
        } else {
            squads[i].guide_x += dx.signum() * step;
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
    grid: &std::collections::HashMap<(i32, i32), Vec<usize>>,
    cell_of: impl Fn(f32, f32) -> (i32, i32),
    grid_cols: i32,
    grid_rows: i32,
) -> (Option<usize>, f32) {
    let (cx, cy) = cell_of(ux, uy);
    let rings = (radius / GRID_CELL).ceil() as i32;
    let r2 = radius * radius;
    let mut best = None;
    let mut best_d2 = f32::MAX;
    for gy in (cy - rings)..=(cy + rings) {
        for gx in (cx - rings)..=(cx + rings) {
            if gx < -1 || gy < -1 || gx > grid_cols || gy > grid_rows {
                continue;
            }
            let Some(bucket) = grid.get(&(gx, gy)) else {
                continue;
            };
            for &j in bucket {
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
    (best, best_d2.sqrt())
}

fn update_squad_morale(squads: &mut [SquadState], units: &[Unit]) {
    for s in squads.iter_mut() {
        if s.routing {
            continue;
        }
        let alive = units
            .iter()
            .filter(|u| u.squad == s.id && in_fight(u))
            .count() as u32;
        let lost = s.initial.saturating_sub(alive);
        if s.initial > 0 && (lost as f32 / s.initial as f32) >= ROUT_CASUALTY_FRAC {
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
            })
            .collect(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Squad, UnitKind};
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
            ma > 45.0 && ma < 130.0 && md > 70.0 && md < 160.0,
            "contact medians should sit on a front (F0={ma:.1} F1={md:.1} frame={fire_i})"
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
            dm > 0.85,
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
}
