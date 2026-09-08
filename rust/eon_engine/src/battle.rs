//! Battle resolver — squad/regiment brains + individual line-of-sight combat.
//!
//! Per `eoy-battle-resolve`: the player does not control the battle. It is resolved deterministically
//! (fixed iteration order + seeded PRNG), **once**, and baked to a wide-row `BattleReport` for a
//! watchable HD-2D replay. Squads own orders/morale (the "brain"); individuals move to their
//! formation slot and attack whatever enters their reach (the "fight"). The outcome posts back to
//! the World ledger as balanced casualty transactions.

use crate::ledger::{Account, Ledger, Phase};
use crate::model::{FactionId, ProvinceId, UnitKind, World};
use crate::rng::Rng;

pub const BATTLE_WIDTH: f32 = 200.0;
pub const BATTLE_HEIGHT: f32 = 120.0;
const DT: f32 = 1.0;
const MAX_TICKS: u32 = 1400;
const RECORD_STRIDE: u32 = 3;
const ROUT_CASUALTY_FRAC: f32 = 0.6;
/// Attack cadence: a unit strikes at most once every this many ticks. This stretches the melee
/// grind over many ticks so a large battle plays out over minutes rather than a few seconds.
const ATTACK_COOLDOWN: u32 = 3;
/// Spatial-hash cell size (>= max unit reach) for O(n) target queries at scale.
const GRID_CELL: f32 = 7.0;
/// Faith the victor consecrates into the contested province.
const CONSECRATE: f32 = 8.0;

#[derive(Clone, Debug)]
struct Unit {
    faction: FactionId,
    kind: UnitKind,
    squad: u32,
    x: f32,
    y: f32,
    hp: f32,
    alive: bool,
    /// Earliest tick this unit may attack again (attack cooldown).
    next_attack: u32,
}

#[derive(Clone, Debug)]
struct SquadState {
    id: u32,
    initial: u32,
    routing: bool,
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
    pub alive: bool,
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
        // Gather this side's units first, then lay them out as one rectangular formation so large
        // armies (hundreds of units) pack neatly near their baseline without running off-field.
        let mut side_units: Vec<usize> = Vec::new();
        for army in world.armies.iter().filter(|a| a.faction == fac && a.province == province) {
            for sq in &army.squads {
                if sq.count == 0 {
                    continue;
                }
                let sid = next_sid;
                next_sid += 1;
                squads.push(SquadState { id: sid, initial: sq.count, routing: false });
                for _ in 0..sq.count {
                    side_units.push(units.len());
                    units.push(Unit {
                        faction: fac,
                        kind: sq.kind,
                        squad: sid,
                        x: 0.0,
                        y: 0.0,
                        hp: sq.kind.base_hp(),
                        alive: true,
                        next_attack: 0,
                    });
                }
            }
        }
        let n = side_units.len().max(1);
        let cols = ((n as f32).sqrt() * 1.4).round().clamp(14.0, 44.0) as usize;
        let sx = 2.0; // row depth spacing (receding toward own edge)
        let sy = 1.9; // column spacing
        let baseline = if side_idx == 0 { 35.0 } else { BATTLE_WIDTH - 35.0 };
        let dir = if side_idx == 0 { 1.0 } else { -1.0 };
        let y0 = BATTLE_HEIGHT * 0.5 - (cols as f32 - 1.0) * sy * 0.5;
        for (m, &ui) in side_units.iter().enumerate() {
            let row = (m / cols) as f32;
            let col = (m % cols) as f32;
            units[ui].x = baseline - dir * row * sx;
            units[ui].y = y0 + col * sy;
        }
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
    while tick < MAX_TICKS && both_sides_alive(&units, attacker, defender) {
        tick += 1;
        update_squad_morale(&mut squads, &units);

        // Per-faction centroid of living units (used as the "advance to contact" target — O(n)).
        let fc = world.faction_count();
        let mut csum = vec![(0.0f32, 0.0f32, 0u32); fc];
        for u in units.iter() {
            if u.alive {
                let e = &mut csum[u.faction as usize];
                e.0 += u.x;
                e.1 += u.y;
                e.2 += 1;
            }
        }
        let centroid = |f: usize| -> (f32, f32) {
            let e = csum[f];
            if e.2 == 0 { (BATTLE_WIDTH * 0.5, BATTLE_HEIGHT * 0.5) } else { (e.0 / e.2 as f32, e.1 / e.2 as f32) }
        };

        // Uniform-grid spatial hash of living units (O(n)); deterministic bucket order.
        let cell_of = |x: f32, y: f32| -> (i32, i32) {
            ((x / GRID_CELL) as i32, (y / GRID_CELL) as i32)
        };
        let mut grid: std::collections::HashMap<(i32, i32), Vec<usize>> = std::collections::HashMap::new();
        for (idx, u) in units.iter().enumerate() {
            if u.alive {
                grid.entry(cell_of(u.x, u.y)).or_default().push(idx);
            }
        }

        for i in 0..units.len() {
            if !units[i].alive {
                continue;
            }
            let (ux, uy, reach, kind, fac, squad) = {
                let u = &units[i];
                (u.x, u.y, u.kind.reach(), u.kind, u.faction, u.squad)
            };
            let routing = squads.iter().find(|s| s.id == squad).map(|s| s.routing).unwrap_or(false);
            if routing {
                // Flee toward own baseline; no attacks.
                let dir = if fac == attacker { -1.0 } else { 1.0 };
                units[i].x += dir * kind.move_speed() * DT;
                continue;
            }

            // Nearest enemy within reach via the 3x3 neighborhood of cells (deterministic order).
            let (cx, cy) = cell_of(ux, uy);
            let reach2 = reach * reach;
            let mut target: Option<usize> = None;
            let mut best_d2 = f32::MAX;
            for gy in (cy - 1)..=(cy + 1) {
                for gx in (cx - 1)..=(cx + 1) {
                    if gx < -1 || gy < -1 || gx > grid_cols || gy > grid_rows {
                        continue;
                    }
                    if let Some(bucket) = grid.get(&(gx, gy)) {
                        for &j in bucket {
                            let e = &units[j];
                            if !e.alive || e.faction == fac {
                                continue;
                            }
                            let d2 = (e.x - ux).powi(2) + (e.y - uy).powi(2);
                            if d2 <= reach2 && d2 < best_d2 {
                                best_d2 = d2;
                                target = Some(j);
                            }
                        }
                    }
                }
            }

            match target {
                Some(j) => {
                    // Enemy in reach: attack if off cooldown, else hold position.
                    if tick >= units[i].next_attack {
                        let jitter = 0.9 + 0.2 * rng.next_f32();
                        let dmg = kind.base_attack() * jitter;
                        units[j].hp -= dmg;
                        if units[j].hp <= 0.0 {
                            units[j].alive = false;
                        }
                        units[i].next_attack = tick + ATTACK_COOLDOWN;
                    }
                }
                None => {
                    // Advance to contact toward the enemy faction centroid.
                    let mut enemy = (BATTLE_WIDTH * 0.5, BATTLE_HEIGHT * 0.5);
                    let mut best = -1.0f32;
                    for f in 0..fc {
                        if f as FactionId == fac {
                            continue;
                        }
                        if csum[f].2 as f32 > best {
                            best = csum[f].2 as f32;
                            enemy = centroid(f);
                        }
                    }
                    let dx = enemy.0 - ux;
                    let dy = enemy.1 - uy;
                    let d = (dx * dx + dy * dy).sqrt().max(1e-3);
                    units[i].x += dx / d * kind.move_speed() * DT;
                    units[i].y += dy / d * kind.move_speed() * DT;
                }
            }
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

fn both_sides_alive(units: &[Unit], a: FactionId, d: FactionId) -> bool {
    let a_alive = units.iter().any(|u| u.alive && u.faction == a);
    let d_alive = units.iter().any(|u| u.alive && u.faction == d);
    a_alive && d_alive
}

fn update_squad_morale(squads: &mut [SquadState], units: &[Unit]) {
    for s in squads.iter_mut() {
        if s.routing {
            continue;
        }
        let alive = units.iter().filter(|u| u.squad == s.id && u.alive).count() as u32;
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
                alive: u.alive,
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
}
